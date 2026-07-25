//  ScheduleView.swift
//  Iconik Employee — the schedule
//
//  Replaces SlingWeeklyView (deleted in the same commit). Same data, same
//  manager tools, new shape: the screen leads with a live countdown to the next
//  call time, and the photographer picks how the rest is read —
//
//    Day       one day at a time from a capsule strip. Best on a shoot day.
//    Timeline  a continuous time-gutter scroll anchored on today, with finished
//              days behind a grey band. Best for planning a stretch.
//
//  The choice is per-user (@AppStorage) and sticks.
//
//  Everything the old screen could do, this does: the realtime session listener,
//  time off, My/All filtering, org-wide staffing heat, publish-a-day and create
//  for managers, offline state, and per-day occurrences of multi-day jobs.
//
//  Deliberately NOT carried over: the per-card weather fetch. It was keyed off
//  `session.location`, which is hard-coded to nil in the Session model, so it
//  could never fire. Weather lives in the shift detail, where it reads the
//  school's real coordinates.

import SwiftUI

struct ScheduleView: View {
    // MARK: Services

    private let sessionService = SessionService.shared
    private let timeOffService = TimeOffService.shared
    private let userManager = UserManager.shared
    @ObservedObject private var organizationService = OrganizationService.shared

    // MARK: Data

    @State private var sessions: [Session] = []
    @State private var timeOff: [TimeOffCalendarEntry] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var isListening = false
    private let subscriptionId = UUID()

    // MARK: View state

    @AppStorage("scheduleLayout") private var layoutRaw = ScheduleLayout.day.rawValue
    @AppStorage("scheduleMode") private var modeRaw = ScheduleMode.myShifts.rawValue
    @AppStorage("userOrganizationID") private var organizationID: String = ""

    @State private var weekOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var pushedSession: Session?
    @State private var selectedTimeOff: TimeOffCalendarEntry?
    @State private var showCreateSession = false
    @State private var staffingPopoverDay: Date?
    /// The timeline anchors on today once, not every time this screen re-appears.
    @State private var hasAnchored = false
    @State private var hasStarted = false
    @State private var index = ScheduleIndex()

    // Manager publishing
    @State private var isPublishingDay = false
    @State private var publishMessage: String?

    private var layout: ScheduleLayout { ScheduleLayout(rawValue: layoutRaw) ?? .day }
    private var mode: ScheduleMode { ScheduleMode(rawValue: modeRaw) ?? .myShifts }
    private var canEdit: Bool { Permissions.has("schedule", level: .edit) }

    // MARK: - Body

    var body: some View {
        ZStack {
            ScheduleBackdrop(tint: ambientTint)

            if isLoading && sessions.isEmpty {
                loadingState
            } else if !errorMessage.isEmpty && sessions.isEmpty {
                errorState
            } else {
                content
            }
        }
        .navigationTitle(layout == .day ? ScheduleStyle.relativeDayLabel(selectedDay) : "Schedule")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    modeMenu
                    if canEdit {
                        Button { showCreateSession = true } label: { Image(systemName: "plus") }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateSession) { CreateSessionView() }
        .sheet(item: $selectedTimeOff) { entry in
            TimeOffDetailView(
                timeOffEntry: entry,
                onCancel: { selectedTimeOff = nil; loadTimeOff() },
                onDelete: { selectedTimeOff = nil; loadTimeOff() }
            )
        }
        .schedulePush(item: $pushedSession) { session in
            ShiftDetailView(session: session,
                            allSessions: sessions,
                            currentUserID: userManager.getCurrentUserID())
                .id(session.dayOccurrenceKey)
        }
        .onAppear(perform: start)
        .onDisappear {
            sessionService.stopListeningToSessions(subscriptionId: subscriptionId)
            isListening = false
            organizationService.stopListening()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            isListening = false
            loadSessions()
        }
        .onChange(of: weekOffset) { _ in loadTimeOff() }
        .onChange(of: modeRaw) { _ in rebuildIndex() }
        .tint(ambientTint)
    }

    @ViewBuilder
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    if let banner = statusBanner { banner }

                    if let focus = focusSession {
                        ScheduleCountdownCard(session: focus, tint: ScheduleStyle.accent(for: focus))
                            .padding(.horizontal, 18)
                            .onTapGesture { pushedSession = focus }
                    }

                    layoutSwitch

                    switch layout {
                    case .day:
                        weekStrip
                        dayHeader
                        dayList
                    case .timeline:
                        ScheduleTimeline(
                            days: timelineDays,
                            items: { items(on: $0) },
                            hours: { hours(on: $0) },
                            onSelectShift: { pushedSession = $0 },
                            onSelectTimeOff: { selectedTimeOff = $0 }
                        )
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .refreshable { await refresh() }
            .onAppear {
                // Only on the FIRST appearance. onAppear also fires when you pop
                // back from a shift, and re-anchoring there yanked the timeline
                // to today, losing the place you were reading.
                guard !hasAnchored else { return }
                hasAnchored = true
                anchorOnToday(proxy, animated: false)
            }
            .onChange(of: layoutRaw) { _ in anchorOnToday(proxy, animated: true) }
        }
    }

    // MARK: - Ambient tint

    /// In Day layout the screen takes the colour of the day you're on; in
    /// Timeline it follows whatever is coming up next.
    private var ambientTint: Color {
        if layout == .day, let first = shifts(on: selectedDay).first {
            return ScheduleStyle.accent(for: first)
        }
        if let focus = focusSession { return ScheduleStyle.accent(for: focus) }
        return .indigo
    }

    /// What the countdown is about: the shift in progress, else the next one on
    /// the selected day, else the next one anywhere.
    private var focusSession: Session? {
        let now = Date()
        let day = shifts(on: layout == .day ? selectedDay : Calendar.current.startOfDay(for: now))
        if let live = day.first(where: { session in
            guard let start = session.startDate, let end = session.endDate else { return false }
            return start <= now && now <= end
        }) { return live }
        if let next = day.first(where: { ($0.startDate ?? .distantPast) > now }) { return next }
        return nextShift(after: now) ?? day.first
    }

    /// The index keeps occurrences in start order, so this is a scan of a
    /// prebuilt array rather than a re-expansion of every session.
    private func nextShift(after date: Date) -> Session? {
        index.occurrences.first { ($0.startDate ?? .distantPast) > date }
    }

    // MARK: - Chrome

    private var layoutSwitch: some View {
        HStack(spacing: 4) {
            ForEach(ScheduleLayout.allCases) { option in
                Button {
                    withAnimation(ScheduleMotion.gentle) { layoutRaw = option.rawValue }
                    ScheduleHaptics.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.system(size: 11, weight: .semibold))
                        Text(option.title).font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        if layout == option {
                            Capsule().fill(.thickMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                        }
                    }
                    .foregroundStyle(layout == option ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeMenu: some View {
        Menu {
            Picker("Show", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                ForEach(ScheduleMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Image(systemName: mode == .myShifts ? "person.crop.circle.fill" : "person.2.circle.fill")
        }
    }

    /// Offline / stale-data state, and the result of a publish. Only appears when
    /// there is something to say.
    @ViewBuilder
    private var statusBanner: (some View)? {
        if let publishMessage {
            banner(text: publishMessage, systemImage: "checkmark.circle.fill", tint: .green)
        } else if sessionService.isUsingOfflineData {
            banner(text: sessionService.lastSyncTime.map { "Offline · last synced \($0.timeAgoDisplay())" } ?? "Offline",
                   systemImage: "icloud.slash", tint: .orange)
        } else if !sessionService.isConnected {
            banner(text: "No connection", systemImage: "wifi.slash", tint: .orange)
        } else {
            nil as EmptyView?
        }
    }

    private func banner(text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
            Text(text).font(.footnote.weight(.medium))
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12), in: Capsule())
        .padding(.horizontal, 18)
    }

    // MARK: - Day layout

    private var weekStrip: some View {
        let week = week(offset: weekOffset)
        return VStack(spacing: 8) {
            HStack {
                Button { step(-1) } label: { Image(systemName: "chevron.left").font(.footnote.weight(.bold)) }
                Spacer()
                Text(weekLabel(week))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { step(1) } label: { Image(systemName: "chevron.right").font(.footnote.weight(.bold)) }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 26)

            HStack(spacing: 8) {
                ForEach(week, id: \.self) { date in
                    dayCapsule(date)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func dayCapsule(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDay)
        let isToday = Calendar.current.isDateInToday(date)
        let mine = !shifts(on: date).isEmpty
        let staffing = staffing(on: date)

        return Button {
            withAnimation(ScheduleMotion.snappy) { selectedDay = date }
            ScheduleHaptics.selection()
        } label: {
            VStack(spacing: 3) {
                Text(ScheduleStyle.weekdayNarrow.string(from: date))
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.7)
                Text(ScheduleStyle.dayNumber.string(from: date))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                // Org-wide staffing load, the heat map the schedulers rely on.
                Circle()
                    .fill(mine ? Color.primary.opacity(isSelected ? 0.9 : 0.5)
                               : getHeatMapColor(total: staffing.total))
                    .frame(width: 5, height: 5)
                    .opacity(mine || staffing.total > 0 ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thickMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                }
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
                }
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.35) {
            guard staffing.total > 0 else { return }
            staffingPopoverDay = date
            ScheduleHaptics.impact(.medium)
        }
        .popover(isPresented: Binding(
            get: { staffingPopoverDay == date },
            set: { if !$0 { staffingPopoverDay = nil } }
        )) {
            StaffingPopoverView(staffing: staffing, date: date)
        }
        .accessibilityLabel(Text(ScheduleStyle.longDate.string(from: date)))
        .accessibilityValue(Text("\(shifts(on: date).count) shifts, org staffing need \(staffing.total)"))
    }

    private var dayHeader: some View {
        let dayShifts = shifts(on: selectedDay)
        let dayOff = timeOffEntries(on: selectedDay)
        let unpublished = dayShifts.contains { !$0.isPublished }

        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ScheduleStyle.longDate.string(from: selectedDay))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(daySummary(shifts: dayShifts.count, timeOff: dayOff.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            // Managers publish a whole day at once, as before.
            if canEdit && unpublished && organizationService.organizationHasPublishing {
                Button {
                    publishDay()
                } label: {
                    HStack(spacing: 8) {
                        if isPublishingDay {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "paperplane.fill").font(.system(size: 12, weight: .semibold))
                        }
                        Text("Publish this day")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(ambientTint, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isPublishingDay)
            }
        }
        .padding(.horizontal, 18)
    }

    private func daySummary(shifts: Int, timeOff: Int) -> String {
        if shifts == 0 && timeOff == 0 { return "Clear" }
        var parts: [String] = []
        if shifts > 0 {
            let total = self.shifts(on: selectedDay).reduce(0.0) { sum, session in
                guard let start = session.startDate, let end = session.endDate, end > start else { return sum }
                return sum + end.timeIntervalSince(start)
            }
            parts.append("\(shifts) shift\(shifts == 1 ? "" : "s") · \(ScheduleStyle.durationString(total))")
        }
        if timeOff > 0 { parts.append("\(timeOff) time off") }
        return parts.joined(separator: " · ")
    }

    private var dayList: some View {
        LazyVStack(spacing: 14) {
            let dayItems = items(on: selectedDay)
            if dayItems.isEmpty {
                ScheduleEmptyState(title: "Clear day",
                                   message: mode == .myShifts
                                       ? "You have nothing scheduled."
                                       : "Nothing scheduled for anyone.",
                                   systemImage: "moon.stars.fill")
                    .padding(.top, 10)
            }
            ForEach(dayItems) { item in
                switch item {
                case .shift(let session):
                    Button { pushedSession = session } label: {
                        ScheduleShiftRow(session: session, standing: ShiftStanding.of(session))
                    }
                    .buttonStyle(.plain)
                    .scheduleScrollFade()
                case .timeOff(let entry):
                    Button { selectedTimeOff = entry } label: {
                        ScheduleTimeOffRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .scheduleScrollFade()
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Timeline layout

    /// Centred on today: a week of history above, today always present even when
    /// clear (it's the scroll anchor), then six weeks ahead. Built with the index
    /// rather than re-filtering 49 days on every render.
    private var timelineDays: [Date] { index.timelineDays }

    private func anchorOnToday(_ proxy: ScrollViewProxy, animated: Bool) {
        guard layout == .timeline else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(ScheduleMotion.gentle) { proxy.scrollTo(ScheduleTimeline.anchorID, anchor: .top) }
            } else {
                proxy.scrollTo(ScheduleTimeline.anchorID, anchor: .top)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(1.3)
            Text("Loading your schedule…").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorState: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            Text("Couldn't load the schedule").font(.headline)
            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") { loadSessions() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func start() {
        // Re-entrant: onAppear fires again on every pop back from a shift.
        defer { hasStarted = true }
        guard !hasStarted else {
            if !isListening { loadSessions() }
            return
        }
        userManager.initializeOrganizationID()
        let orgID = userManager.getCachedOrganizationID()
        if !orgID.isEmpty {
            organizationService.startListeningToOrganization(organizationID: orgID)
        }
        if sessions.isEmpty || !isListening { loadSessions() }
        loadTimeOff()
    }

    private func loadSessions() {
        if sessions.isEmpty { isLoading = true }
        errorMessage = ""

        guard isListening == false else { return }

        let orgID = organizationID.isEmpty ? userManager.getCachedOrganizationID() : organizationID
        guard !orgID.isEmpty else {
            isLoading = false
            errorMessage = "Organization ID not found"
            return
        }

        isListening = true
        sessionService.startListeningToSessions(
            subscriptionId: subscriptionId,
            organizationID: orgID,
            includeUnpublished: canEdit
        ) { incoming in
            DispatchQueue.main.async {
                self.sessions = incoming
                self.rebuildIndex()
                self.isLoading = false
            }
        }
    }

    private func loadTimeOff() {
        let visible = week(offset: weekOffset)
        let calendar = Calendar.current
        // Timeline reads further ahead than one week, so widen the window to match.
        let start = layout == .timeline
            ? calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date())) ?? Date()
            : (visible.first ?? Date())
        let end = layout == .timeline
            ? calendar.date(byAdding: .day, value: 42, to: calendar.startOfDay(for: Date())) ?? Date()
            : (visible.last ?? Date())

        Task {
            let entries = await timeOffService.getTimeOffForCalendar(dateRange: (start: start, end: end))
            await MainActor.run {
                self.timeOff = entries
                self.rebuildIndex()
            }
        }
    }

    private func refresh() async {
        loadTimeOff()
        let orgID = organizationID.isEmpty ? userManager.getCachedOrganizationID() : organizationID
        guard !orgID.isEmpty else { return }
        do {
            let fresh = try await sessionService.fetchSessions(
                organizationID: orgID,
                includeUnpublished: canEdit,
                forceRefresh: true
            )
            await MainActor.run {
                self.sessions = fresh
                self.rebuildIndex()
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

    private func publishDay() {
        isPublishingDay = true
        let orgID = organizationID.isEmpty ? userManager.getCachedOrganizationID() : organizationID
        let dayKey = Formatters.isoDate.string(from: selectedDay)

        Task {
            do {
                try await sessionService.publishSessionsForDate(organizationID: orgID, date: dayKey)
                await MainActor.run {
                    isPublishingDay = false
                    publishMessage = "Published every shift on this day."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { publishMessage = nil }
                }
            } catch {
                await MainActor.run {
                    isPublishingDay = false
                    errorMessage = "Couldn't publish: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Queries

    // Every one of these was recomputed from the full session list on each
    // access — and the timeline asks about ~50 days per body evaluation, inside
    // a TimelineView that re-runs every minute and while rows are being created
    // mid-scroll. Each call also allocated a fresh Session per day occurrence.
    // They now read a prebuilt index (see rebuildIndex) and are O(1).

    private func shifts(on day: Date) -> [Session] {
        index.shiftsByDay[Formatters.isoDate.string(from: day)] ?? []
    }

    private func timeOffEntries(on day: Date) -> [TimeOffCalendarEntry] {
        index.timeOffByDay[Formatters.isoDate.string(from: day)] ?? []
    }

    private func items(on day: Date) -> [ScheduleItem] {
        index.itemsByDay[Formatters.isoDate.string(from: day)] ?? []
    }

    private func hasItems(on day: Date) -> Bool {
        index.itemsByDay[Formatters.isoDate.string(from: day)]?.isEmpty == false
    }

    /// Org-wide staffing need for a day — every session, unfiltered. This is the
    /// number behind the heat dot and the long-press breakdown.
    private func staffing(on day: Date) -> DayStaffingTotals {
        index.staffingByDay[Formatters.isoDate.string(from: day)]
            ?? DayStaffingTotals(photographers: 0, posers: 0, helpers: 0)
    }

    private func hours(on day: Date) -> TimeInterval {
        index.hoursByDay[Formatters.isoDate.string(from: day)] ?? 0
    }

    // MARK: - Index

    /// Fold the session and time-off lists into per-day buckets once, whenever
    /// the data or the My/All filter changes. Scrolling then costs dictionary
    /// lookups instead of a full scan per day per frame.
    private func rebuildIndex() {
        index = ScheduleIndex.build(
            sessions: sessions,
            timeOff: timeOff,
            mode: mode,
            viewerID: userManager.getCurrentUserIDUnified(),
            viewerEmail: UserDefaults.standard.string(forKey: "userEmail")
        )
    }

    // MARK: - Week math

    private func week(offset: Int) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        guard let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today),
              let start = calendar.date(byAdding: .day, value: 7 * offset, to: sunday) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func weekLabel(_ week: [Date]) -> String {
        guard let first = week.first, let last = week.last else { return "" }
        return "\(ScheduleStyle.monthDay.string(from: first)) – \(ScheduleStyle.monthDay.string(from: last))"
    }

    private func step(_ delta: Int) {
        withAnimation(ScheduleMotion.snappy) {
            weekOffset += delta
            let candidates = week(offset: weekOffset)
            if let first = candidates.first {
                let weekday = Calendar.current.component(.weekday, from: selectedDay) - 1
                selectedDay = candidates.indices.contains(weekday) ? candidates[weekday] : first
            }
        }
        ScheduleHaptics.impact(.soft)
    }
}

// MARK: - Filter

/// Whose shifts the schedule shows. Previously declared in SlingWeeklyView,
/// which this file replaces.
enum ScheduleMode: String, CaseIterable {
    case myShifts = "My Shifts"
    case allShifts = "All Shifts"
}

// MARK: - Layout choice

enum ScheduleLayout: String, CaseIterable, Identifiable {
    case day, timeline
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .timeline: return "Timeline"
        }
    }

    var symbol: String {
        switch self {
        case .day: return "square.fill.text.grid.1x2"
        case .timeline: return "list.bullet.indent"
        }
    }
}

// MARK: - Unified item

/// One thing on a day: a shift (always a day occurrence) or a time-off entry.
enum ScheduleItem: Identifiable {
    case shift(Session)
    case timeOff(TimeOffCalendarEntry)

    var id: String {
        switch self {
        case .shift(let session): return "shift-\(session.dayOccurrenceKey)"
        case .timeOff(let entry): return "off-\(entry.id)"
        }
    }

    /// All-day time off sorts to the top of a day; everything else by start time.
    var sortKey: Date {
        switch self {
        case .shift(let session): return session.startDate ?? .distantPast
        case .timeOff(let entry):
            guard entry.isPartialDay else { return .distantPast }
            return Session.parseDateTime(date: Formatters.isoDate.string(from: entry.date),
                                         time: entry.startTime) ?? .distantPast
        }
    }
}

// MARK: - Per-day index

/// The schedule folded into per-day buckets, built once per data/filter change.
///
/// Before this existed, every day cell recomputed its own answer by scanning the
/// whole session list and allocating a `Session` copy per day occurrence. The
/// timeline asks about roughly fifty days per body evaluation, and it does that
/// inside a minute-ticking `TimelineView` and again as lazy rows are created
/// during a scroll — so the same scan ran hundreds of times a second while your
/// thumb was moving. That was the scroll stutter.
struct ScheduleIndex {
    var shiftsByDay: [String: [Session]] = [:]
    var timeOffByDay: [String: [TimeOffCalendarEntry]] = [:]
    var itemsByDay: [String: [ScheduleItem]] = [:]
    var staffingByDay: [String: DayStaffingTotals] = [:]
    var hoursByDay: [String: TimeInterval] = [:]
    /// A week of history that had work, today (always), then six weeks ahead.
    var timelineDays: [Date] = []
    /// Every visible occurrence in start order — what "next shift" reads.
    var occurrences: [Session] = []

    static func build(
        sessions: [Session],
        timeOff: [TimeOffCalendarEntry],
        mode: ScheduleMode,
        viewerID: String?,
        viewerEmail: String?
    ) -> ScheduleIndex {
        var index = ScheduleIndex()
        let formatter = Formatters.isoDate

        for session in sessions {
            // Staffing is org-wide: it counts every session on the day, whatever
            // the My/All filter says, because it answers "how loaded is the org".
            let dayRows = session.days.isEmpty ? [] : session.days
            let keys: [String] = dayRows.isEmpty ? [session.date] : dayRows.map(\.date)
            if !session.isTimeOff {
                for key in Set(keys) {
                    var totals = index.staffingByDay[key]
                        ?? DayStaffingTotals(photographers: 0, posers: 0, helpers: 0)
                    totals = DayStaffingTotals(
                        photographers: totals.photographers + session.photographersNeeded,
                        posers: totals.posers + session.posersNeeded,
                        helpers: totals.helpers + session.helpersNeeded
                    )
                    index.staffingByDay[key] = totals
                }
            }

            for occurrence in session.dayOccurrences() {
                if mode == .myShifts {
                    guard let viewerID,
                          occurrence.isUserAssigned(userID: viewerID, userEmail: viewerEmail) else { continue }
                }
                index.shiftsByDay[occurrence.date, default: []].append(occurrence)
                index.occurrences.append(occurrence)
                if let start = occurrence.startDate, let end = occurrence.endDate, end > start {
                    index.hoursByDay[occurrence.date, default: 0] += end.timeIntervalSince(start)
                }
            }
        }

        for entry in timeOff {
            if mode == .myShifts, entry.photographerId != viewerID { continue }
            index.timeOffByDay[formatter.string(from: entry.date), default: []].append(entry)
        }

        for key in index.shiftsByDay.keys {
            index.shiftsByDay[key]?.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        }
        for key in index.timeOffByDay.keys {
            index.timeOffByDay[key]?.sort { $0.startTime < $1.startTime }
        }
        index.occurrences.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        for key in Set(index.shiftsByDay.keys).union(index.timeOffByDay.keys) {
            let shifts = (index.shiftsByDay[key] ?? []).map(ScheduleItem.shift)
            let off = (index.timeOffByDay[key] ?? []).map(ScheduleItem.timeOff)
            index.itemsByDay[key] = (off + shifts).sorted { $0.sortKey < $1.sortKey }
        }

        // Timeline window, resolved here so the view never re-filters 49 days.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func hasWork(_ date: Date) -> Bool {
            index.itemsByDay[formatter.string(from: date)]?.isEmpty == false
        }
        let past = (1...7)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .filter(hasWork)
            .sorted()
        let future = (1...42)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .filter(hasWork)
        index.timelineDays = past + [today] + future

        return index
    }
}
