//  ScheduleLabKit.swift
//  Iconik Employee — Schedule Design Lab
//
//  Shared foundation for the five schedule design prototypes. Everything here is
//  presentation-neutral: one store, the real `Session` / `SessionDay` /
//  `TimeOffCalendarEntry` models, formatting, and back-compat wrappers for the
//  SwiftUI APIs that landed after our iOS 16.6 floor.
//
//  Nothing in the lab writes to Supabase. It reads (one-shot fetch, no realtime
//  subscription, so it can never fight the production listeners in
//  SlingWeeklyView / ShiftDetailView) and falls back to a rich sample week when
//  there is no org, no network, or nothing scheduled.

import SwiftUI
import UIKit

// MARK: - Unified schedule item

/// One thing on a day: a shift (always a *day occurrence* — `session.with(day:)`,
/// so a multi-day job carries that day's own times and crew) or a time-off entry.
enum ScheduleLabItem: Identifiable {
    case shift(Session)
    case timeOff(TimeOffCalendarEntry)

    var id: String {
        switch self {
        case .shift(let session): return "shift-\(session.dayOccurrenceKey)"
        case .timeOff(let entry): return "off-\(entry.id)"
        }
    }

    var session: Session? {
        if case .shift(let session) = self { return session }
        return nil
    }

    var timeOffEntry: TimeOffCalendarEntry? {
        if case .timeOff(let entry) = self { return entry }
        return nil
    }

    var startDate: Date? {
        switch self {
        case .shift(let session):
            return session.startDate
        case .timeOff(let entry):
            guard entry.isPartialDay else { return nil }
            return Session.parseDateTime(date: Formatters.isoDate.string(from: entry.date),
                                         time: entry.startTime)
        }
    }

    var endDate: Date? {
        switch self {
        case .shift(let session):
            return session.endDate
        case .timeOff(let entry):
            guard entry.isPartialDay else { return nil }
            return Session.parseDateTime(date: Formatters.isoDate.string(from: entry.date),
                                         time: entry.endTime)
        }
    }

    /// All-day time off sorts to the top of a day; everything else by start time.
    var sortKey: Date {
        startDate ?? .distantPast
    }

    var title: String {
        switch self {
        case .shift(let session):
            return session.schoolName.isEmpty ? "Untitled session" : session.schoolName
        case .timeOff(let entry):
            return entry.reason.displayName
        }
    }
}

// MARK: - Store

/// One store, five presentations. Owns the week window, the My/All filter, and
/// the day-occurrence expansion that every design needs.
@MainActor
final class ScheduleLabStore: ObservableObject {
    static let shared = ScheduleLabStore()

    enum DataSource: String, CaseIterable, Identifiable {
        case live = "Live"
        case sample = "Sample"
        var id: String { rawValue }
    }

    @Published var dataSource: DataSource = .live
    @Published var mode: ScheduleMode = .allShifts

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var timeOff: [TimeOffCalendarEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    /// True when `.live` was asked for but produced nothing, so sample data is
    /// standing in. Surfaced in the lab chrome so a design is never judged
    /// against data the operator thinks is real.
    @Published private(set) var isShowingSampleFallback = false

    private let sessionService = SessionService.shared
    private let timeOffService = TimeOffService.shared
    private let userManager = UserManager.shared
    private var hasLoadedOnce = false

    private init() {}

    // MARK: Viewer identity

    /// The id "My Shifts" filters on. Sample crews are seeded with this id, so the
    /// filter is exercised for real even with no backend.
    var viewerID: String {
        userManager.getCurrentUserIDUnified()?.lowercased() ?? ScheduleLabSampleData.viewerID
    }

    var viewerEmail: String? {
        UserDefaults.standard.string(forKey: "userEmail")
    }

    var viewerName: String {
        let first = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let last = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? "You" : full
    }

    // MARK: Loading

    func loadIfNeeded() {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        Task { await reload() }
    }

    func setDataSource(_ source: DataSource) {
        guard source != dataSource else { return }
        dataSource = source
        Task { await reload() }
    }

    func reload() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        guard dataSource == .live else {
            applySample()
            isShowingSampleFallback = false
            return
        }

        let organizationID = userManager.getCachedOrganizationID()
        guard !organizationID.isEmpty else {
            applySample()
            isShowingSampleFallback = true
            loadError = "No organization on this device — showing sample data."
            return
        }

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: Date())) ?? Date()
        let end = calendar.date(byAdding: .day, value: 56, to: calendar.startOfDay(for: Date())) ?? Date()

        do {
            let fetched = try await sessionService.fetchSessions(
                from: start,
                to: end,
                organizationID: organizationID,
                includeUnpublished: Permissions.has("schedule", level: .edit)
            )
            let entries = await timeOffService.getTimeOffForCalendar(dateRange: (start: start, end: end))

            if fetched.isEmpty && entries.isEmpty {
                applySample()
                isShowingSampleFallback = true
                loadError = "Nothing scheduled in the live window — showing sample data."
            } else {
                sessions = fetched
                timeOff = entries
                isShowingSampleFallback = false
            }
        } catch {
            applySample()
            isShowingSampleFallback = true
            loadError = "Live load failed (\(error.localizedDescription)) — showing sample data."
        }
    }

    private func applySample() {
        let sample = ScheduleLabSampleData.build(viewerID: viewerID, viewerName: viewerName)
        sessions = sample.sessions
        timeOff = sample.timeOff
    }

    // MARK: Week math

    /// Sunday-first week for a given offset from the current week — matches the
    /// production week strip so a design can be compared like for like.
    func week(offset: Int) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        guard let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today),
              let start = calendar.date(byAdding: .day, value: 7 * offset, to: sunday) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func weekOffset(containing date: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        guard let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) else { return 0 }
        let days = calendar.dateComponents([.day], from: sunday, to: calendar.startOfDay(for: date)).day ?? 0
        return Int(floor(Double(days) / 7.0))
    }

    // MARK: Queries

    /// Day occurrences for a date, honouring the My/All filter. A multi-day job
    /// only appears on a day whose *own* crew includes the viewer.
    func shifts(on day: Date) -> [Session] {
        let key = Self.dayKey(day)
        let viewer = viewerID
        let email = viewerEmail
        return sessions.compactMap { session -> Session? in
            guard let match = session.day(onDate: key) else { return nil }
            let occurrence = session.with(day: match)
            if mode == .myShifts, !occurrence.isUserAssigned(userID: viewer, userEmail: email) {
                return nil
            }
            return occurrence
        }
        .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    func timeOffEntries(on day: Date) -> [TimeOffCalendarEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let viewer = viewerID
        return timeOff
            .filter { calendar.startOfDay(for: $0.date) == start }
            .filter { mode == .allShifts || $0.photographerId.lowercased() == viewer }
            .sorted { $0.startTime < $1.startTime }
    }

    func items(on day: Date) -> [ScheduleLabItem] {
        let shiftItems = shifts(on: day).map(ScheduleLabItem.shift)
        let offItems = timeOffEntries(on: day).map(ScheduleLabItem.timeOff)
        return (offItems + shiftItems).sorted { $0.sortKey < $1.sortKey }
    }

    func hasItems(on day: Date) -> Bool {
        !shifts(on: day).isEmpty || !timeOffEntries(on: day).isEmpty
    }

    /// Org-wide staffing need for a day (every session, unfiltered) — the number
    /// behind the production heat map.
    func staffing(on day: Date) -> DayStaffingTotals {
        let key = Self.dayKey(day)
        var photographers = 0, posers = 0, helpers = 0
        for session in sessions where !session.isTimeOff && session.day(onDate: key) != nil {
            photographers += session.photographersNeeded
            posers += session.posersNeeded
            helpers += session.helpersNeeded
        }
        return DayStaffingTotals(photographers: photographers, posers: posers, helpers: helpers)
    }

    /// 0…1 load for a day, normalised against the busiest day of its week — the
    /// input for every bar/heat treatment in the lab.
    func loadFraction(on day: Date, in week: [Date]) -> Double {
        let peak = week.map { staffing(on: $0).total }.max() ?? 0
        guard peak > 0 else { return 0 }
        return Double(staffing(on: day).total) / Double(peak)
    }

    /// Total scheduled hours for the viewer (or everyone, in All mode) that week.
    func hours(in week: [Date]) -> Double {
        week.reduce(0.0) { total, day in
            total + shifts(on: day).reduce(0.0) { sum, session in
                guard let start = session.startDate, let end = session.endDate, end > start else { return sum }
                return sum + end.timeIntervalSince(start) / 3600
            }
        }
    }

    /// The next shift starting from now, across the whole loaded window.
    func nextShift(after date: Date = Date()) -> Session? {
        sessions
            .flatMap { $0.dayOccurrences() }
            .filter { session in
                guard let start = session.startDate else { return false }
                if mode == .myShifts, !session.isUserAssigned(userID: viewerID, userEmail: viewerEmail) { return false }
                return start > date
            }
            .min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    static func dayKey(_ date: Date) -> String {
        Formatters.isoDate.string(from: date)
    }
}


// MARK: - Bridge to the production kit
//
// Ambient was chosen on 2026-07-24 and its visual vocabulary was promoted into
// Schedule/ScheduleStyleKit.swift, which the shipping schedule now uses. The lab
// keeps working by forwarding to those exact types — one definition, so the
// prototypes and the real screen cannot drift while the lab is still around for
// comparison. When the lab is deleted these aliases go with it.

typealias ScheduleLabStyle = ScheduleStyle
typealias LabFlowLayout = ScheduleFlowLayout
typealias LabTypePills = ScheduleTypePills
typealias LabTypeIcons = ScheduleTypeIcons
typealias LabBadge = ScheduleBadge
typealias LabAvatar = ScheduleAvatar
typealias LabCrewStack = ScheduleCrewStack
typealias LabEmptyDay = ScheduleEmptyState
typealias LabAnim = ScheduleMotion
typealias LabHaptics = ScheduleHaptics

extension View {
    func labScrollFade(minOpacity: Double = 0.4, minScale: CGFloat = 0.92) -> some View {
        scheduleScrollFade(minOpacity: minOpacity, minScale: minScale)
    }
    func labCarousel(margin: CGFloat) -> some View { scheduleCarousel(margin: margin) }
    func labScrollTargets() -> some View { scheduleScrollTargets() }
    func labNoBounceWhenShort() -> some View { scheduleNoBounceWhenShort() }
    func labParallax(_ amount: CGFloat) -> some View { scheduleParallax(amount) }
    func labPush<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        schedulePush(item: item, destination: destination)
    }

    /// Lab-only: the Board prototype's sheet corner radius (iOS 16.4+).
    @ViewBuilder
    func labCornerRadiusForSheet(_ radius: CGFloat) -> some View {
        if #available(iOS 16.4, *) { self.presentationCornerRadius(radius) } else { self }
    }
}

enum LabActions {
    static func directionsURL(for session: Session) -> URL? {
        let query = session.schoolName.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }

    @MainActor
    static func shareText(for session: Session) -> String {
        var lines = [session.schoolName]
        if let start = session.startDate {
            lines.append(ScheduleLabStyle.longDate.string(from: start))
        }
        lines.append(ScheduleLabStyle.timeRange(session))
        if !session.sessionType.isEmpty {
            lines.append(session.sessionType.map { ScheduleLabStyle.typeName($0, in: session) }
                .joined(separator: ", "))
        }
        if !session.photographers.isEmpty {
            lines.append("Crew: " + session.photographers.map(\.name).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Sample data

/// A realistic three-week dataset built from the production models, so every
/// design is judged against the shapes that actually break layouts: overlapping
/// shifts, a three-day job, an unpublished draft, all-day and partial time off,
/// a long crew list, and an empty day.
enum ScheduleLabSampleData {
    static let viewerID = "00000000-0000-0000-0000-0000000000you"
    private static let organizationID = "lab-org"

    struct Bundle {
        let sessions: [Session]
        let timeOff: [TimeOffCalendarEntry]
    }

    static func build(viewerID: String, viewerName: String) -> Bundle {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: sunday) ?? sunday
        }
        func key(_ offset: Int) -> String {
            Formatters.isoDate.string(from: day(offset))
        }

        let you = SessionPhotographer(id: viewerID, name: viewerName, email: nil,
                                      notes: "Bring the 70-200 and two full batteries.")
        let maria = SessionPhotographer(id: "lab-maria", name: "Maria Alvarez", email: "maria@example.com", notes: nil)
        let devon = SessionPhotographer(id: "lab-devon", name: "Devon Wright", email: "devon@example.com",
                                        notes: "Handles posing line.")
        let priya = SessionPhotographer(id: "lab-priya", name: "Priya Nair", email: "priya@example.com", notes: nil)
        let sam = SessionPhotographer(id: "lab-sam", name: "Sam Okafor", email: "sam@example.com", notes: nil)
        let june = SessionPhotographer(id: "lab-june", name: "June Castillo", email: "june@example.com", notes: nil)

        var sessions: [Session] = []

        // Last week — two finished jobs, so "previous week" isn't a dead screen.
        sessions.append(single(
            id: "lab-prev-1", dayKey: key(-6), start: "08:00", end: "13:30",
            school: "Riverside Middle School", types: ["fall_portraits"], color: "#0ea5e9",
            crew: [you, maria], notes: "Retakes in the gym. Check the list at the office first.",
            staffing: (2, 1, 0)))
        sessions.append(single(
            id: "lab-prev-2", dayKey: key(-3), start: "16:00", end: "20:00",
            school: "Lincoln High School", types: ["sports"], color: "#f97316",
            crew: [devon, priya], notes: nil, staffing: (2, 0, 1)))

        // Monday — the viewer's headline job plus an afternoon job that is not theirs.
        sessions.append(single(
            id: "lab-mon-1", dayKey: key(1), start: "07:45", end: "14:30",
            school: "Lincoln High School", types: ["fall_portraits", "class_groups"], color: "#2563eb",
            crew: [you, maria, devon, priya, sam],
            notes: "Park behind the auditorium. Ask for Ms. Reyes at the front desk — she has the bell schedule.",
            dayNotes: "Underclass portraits, 6 lines. Gym opens at 7:15.",
            staffing: (3, 2, 1)))
        sessions.append(single(
            id: "lab-mon-2", dayKey: key(1), start: "15:30", end: "17:00",
            school: "Maple Grove Elementary", types: ["class_groups"], color: "#16a34a",
            crew: [june], notes: nil, staffing: (1, 1, 0)))

        // Tuesday — three overlapping jobs: the case that breaks timeline layouts.
        sessions.append(single(
            id: "lab-tue-1", dayKey: key(2), start: "08:00", end: "12:00",
            school: "Westview Academy", types: ["senior_portraits"], color: "#7c3aed",
            crew: [you, priya], notes: "Studio setup in the library.", staffing: (2, 1, 0)))
        sessions.append(single(
            id: "lab-tue-2", dayKey: key(2), start: "09:30", end: "13:00",
            school: "Harbor Point School", types: ["yearbook"], color: "#0891b2",
            crew: [maria], notes: nil, staffing: (1, 0, 0)))
        // Two disciplines in one job — the case the cards have to survive.
        sessions.append(single(
            id: "lab-tue-3", dayKey: key(2), start: "13:00", end: "18:15",
            school: "Cedar Ridge High", types: ["underclass", "sports"], color: "#dc2626",
            crew: [you, devon, sam], notes: "Underclass in the gym until 3, then fall team and individual. Bring the second backdrop.",
            staffing: (2, 1, 2)))

        // Wednesday–Friday — one three-day job, crew changing per day, plus a draft.
        sessions.append(multiDay(
            id: "lab-multi", school: "Northgate Preparatory",
            types: ["fall_portraits"], color: "#ea580c",
            notes: "Three-day underclass block. Same room all three days — leave the stands set up.",
            days: [
                (key(3), "07:45", "15:00", "Day 1 — 9th and 10th grade.", [you, maria, devon]),
                (key(4), "07:45", "15:00", "Day 2 — 11th grade + makeups.", [you, priya]),
                (key(5), "08:30", "12:30", "Day 3 — 12th grade, half day.", [maria, sam])
            ],
            staffing: (3, 1, 1)))
        sessions.append(single(
            id: "lab-draft", dayKey: key(3), start: "16:00", end: "18:30",
            school: "Bellview Charter", types: ["other"], custom: "Homecoming Court",
            color: "#db2777", crew: [you], notes: "Times not confirmed with the school yet.",
            published: false, staffing: (1, 0, 0)))

        // Friday night game.
        sessions.append(single(
            id: "lab-fri-game", dayKey: key(5), start: "16:30", end: "21:00",
            school: "Cedar Ridge High", types: ["sports"], color: "#dc2626",
            crew: [you, devon], notes: "Friday night football. Sideline pass at gate C.",
            staffing: (2, 0, 1)))

        // Saturday is intentionally empty — the empty state is part of the design.

        // Next week — so paging forward has something to land on.
        sessions.append(single(
            id: "lab-next-1", dayKey: key(8), start: "08:00", end: "16:00",
            school: "Lincoln High School", types: ["senior_portraits"], color: "#2563eb",
            crew: [you, maria, june], notes: "Senior sessions, 20-minute slots.", staffing: (3, 1, 1)))
        sessions.append(single(
            id: "lab-next-2", dayKey: key(10), start: "09:00", end: "11:30",
            school: "Harbor Point School", types: ["class_groups"], color: "#0891b2",
            crew: [priya], notes: nil, staffing: (1, 1, 0)))
        // Three types — proves the pills wrap instead of truncating.
        sessions.append(single(
            id: "lab-next-3", dayKey: key(11), start: "10:00", end: "19:30",
            school: "Westview Academy", types: ["graduation", "class_groups", "candids"], color: "#9333ea",
            crew: [you, maria, devon, priya, sam, june],
            notes: "Graduation. Full crew. Load in at 9:00, ceremony starts at 11:00.",
            staffing: (4, 2, 2)))

        let timeOff: [TimeOffCalendarEntry] = [
            TimeOffCalendarEntry(
                id: "lab-off-1", requestId: "lab-req-1", title: "Vacation",
                date: day(0), startTime: "00:00", endTime: "23:59",
                photographerId: viewerID, photographerName: viewerName,
                status: .approved, isPartialDay: false, reason: .vacation,
                notes: "Out of town — back Monday."),
            TimeOffCalendarEntry(
                id: "lab-off-2", requestId: "lab-req-2", title: "Appointment",
                date: day(4), startTime: "13:00", endTime: "16:00",
                photographerId: "lab-devon", photographerName: devon.name,
                status: .pending, isPartialDay: true, reason: .personal,
                notes: "Dentist — will be back for the evening job.")
        ]

        return Bundle(sessions: sessions, timeOff: timeOff)
    }

    // MARK: builders

    private static func single(
        id: String,
        dayKey: String,
        start: String,
        end: String,
        school: String,
        types: [String],
        custom: String? = nil,
        color: String,
        crew: [SessionPhotographer],
        notes: String?,
        dayNotes: String? = nil,
        published: Bool = true,
        staffing: (Int, Int, Int)
    ) -> Session {
        let dayRow = SessionDay(
            id: "\(id)-d1", session_id: id, date: dayKey,
            start_time: start, end_time: end, day_notes: dayNotes,
            sort_order: 0, photographers: crew
        )
        return Session(
            id: id,
            organization_id: organizationID,
            school_id: "school-\(school.hashValue)",
            school_name: school,
            date: dayKey,
            start_time: start,
            end_time: end,
            days: [dayRow],
            session_types: types,
            custom_session_type: custom,
            photographers: crew,
            notes: notes,
            status: "scheduled",
            session_color: color,
            is_published: published,
            photographers_needed: staffing.0,
            posers_needed: staffing.1,
            helpers_needed: staffing.2,
            created_at: Date(),
            created_by: SessionCreatedBy(id: "lab-admin", name: "Schedule Admin", email: "admin@example.com")
        )
    }

    private static func multiDay(
        id: String,
        school: String,
        types: [String],
        color: String,
        notes: String?,
        days: [(String, String, String, String?, [SessionPhotographer])],
        staffing: (Int, Int, Int)
    ) -> Session {
        let rows = days.enumerated().map { index, day in
            SessionDay(
                id: "\(id)-d\(index + 1)", session_id: id, date: day.0,
                start_time: day.1, end_time: day.2, day_notes: day.3,
                sort_order: index, photographers: day.4
            )
        }
        let allCrew = days.flatMap { $0.4 }
        var unique: [SessionPhotographer] = []
        for person in allCrew where !unique.contains(where: { $0.id == person.id }) {
            unique.append(person)
        }
        return Session(
            id: id,
            organization_id: organizationID,
            school_id: "school-\(school.hashValue)",
            school_name: school,
            date: rows[0].date,
            start_time: rows[0].start_time ?? "",
            end_time: rows[0].end_time ?? "",
            days: rows,
            session_types: types,
            custom_session_type: nil,
            photographers: unique,
            notes: notes,
            status: "scheduled",
            session_color: color,
            is_published: true,
            photographers_needed: staffing.0,
            posers_needed: staffing.1,
            helpers_needed: staffing.2,
            created_at: Date(),
            created_by: SessionCreatedBy(id: "lab-admin", name: "Schedule Admin", email: "admin@example.com")
        )
    }
}
