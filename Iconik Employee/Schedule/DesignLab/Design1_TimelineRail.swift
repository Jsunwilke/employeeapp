//  Design1_TimelineRail.swift
//  Schedule Design Lab — Design 1: "Rail"
//
//  Premise: a working day is a shape, not a list. The week strip is a load
//  histogram; the day is a real time axis with blocks in proportion, overlapping
//  jobs side by side, and a live "now" line. Answers "when am I free / when do
//  they collide" at a glance — the two things a flat card list can't show.
//
//  Detail: a run-of-show spine. Call time, the block itself, wrap, then the
//  supporting material hung off the same rail.

import SwiftUI

// MARK: - Week view

struct RailScheduleView: View {
    @ObservedObject private var store = ScheduleLabStore.shared

    @State private var weekOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var pushedSession: Session?

    private let hourHeight: CGFloat = 62
    private let gutter: CGFloat = 54

    private var week: [Date] { store.week(offset: weekOffset) }
    private var dayShifts: [Session] { store.shifts(on: selectedDay) }
    private var dayTimeOff: [TimeOffCalendarEntry] { store.timeOffEntries(on: selectedDay) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                weekStrip
                Divider().opacity(0.5)
                dayCanvas
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { LabModeMenu(store: store) }
            }
            .labPush(item: $pushedSession) { session in
                RailShiftDetailView(session: session)
            }
        }
        .tint(.indigo)
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ScheduleLabStyle.monthYear.string(from: week.first ?? Date()))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(weekSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            HStack(spacing: 2) {
                stepButton(systemName: "chevron.left") { step(-1) }
                Button("Today") { jumpToToday() }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.indigo.opacity(0.14)))
                    .disabled(weekOffset == 0 && Calendar.current.isDateInToday(selectedDay))
                stepButton(systemName: "chevron.right") { step(1) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var weekSummary: String {
        let hours = store.hours(in: week)
        let count = week.reduce(0) { $0 + store.shifts(on: $1).count }
        guard count > 0 else { return "No shifts this week" }
        return "\(count) shift\(count == 1 ? "" : "s") · \(ScheduleLabStyle.durationString(hours * 3600)) scheduled"
    }

    // MARK: week strip

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(week, id: \.self) { date in
                dayColumn(date)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -40 { step(1) }
                    else if value.translation.width > 40 { step(-1) }
                }
        )
    }

    private func dayColumn(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDay)
        let isToday = Calendar.current.isDateInToday(date)
        let load = store.loadFraction(on: date, in: week)
        let staffing = store.staffing(on: date)
        let mine = !store.shifts(on: date).isEmpty

        return Button {
            withAnimation(LabAnim.snappy) { selectedDay = date }
            LabHaptics.selection()
        } label: {
            VStack(spacing: 5) {
                Text(ScheduleLabStyle.weekdayNarrow.string(from: date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.indigo : .secondary)

                // Load histogram: height is this day's staffing need against the
                // week's peak, so a heavy day is visibly taller, not just redder.
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(getHeatMapColor(total: staffing.total).gradient)
                        .frame(height: max(load * 34, load > 0 ? 6 : 0))
                }
                .frame(height: 34)

                Text(ScheduleLabStyle.dayNumber.string(from: date))
                    .font(.system(size: 15, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .white : (isToday ? Color.indigo : .primary))
                    .frame(width: 28, height: 28)
                    .background {
                        if isSelected {
                            Circle().fill(Color.indigo)
                        } else if isToday {
                            Circle().strokeBorder(Color.indigo.opacity(0.4), lineWidth: 1.5)
                        }
                    }

                Circle()
                    .fill(mine ? Color.indigo : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ScheduleLabStyle.longDate.string(from: date)))
        .accessibilityValue(Text("\(store.shifts(on: date).count) shifts, staffing need \(staffing.total)"))
    }

    // MARK: day canvas

    private var dayCanvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                dayHeading

                ForEach(dayTimeOff) { entry in
                    RailTimeOffBanner(entry: entry)
                }

                if dayShifts.isEmpty {
                    LabEmptyDay(message: dayTimeOff.isEmpty
                                ? "No shifts on this day."
                                : "Time off only — no shifts scheduled.")
                } else {
                    RailTimeline(
                        shifts: dayShifts,
                        day: selectedDay,
                        hourHeight: hourHeight,
                        gutter: gutter,
                        onSelect: { pushedSession = $0 }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .labNoBounceWhenShort()
    }

    private var dayHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ScheduleLabStyle.relativeDayLabel(selectedDay))
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text(ScheduleLabStyle.monthDay.string(from: selectedDay))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if let first = dayShifts.first?.startDate, let last = dayShifts.compactMap(\.endDate).max() {
                Label("\(ScheduleLabStyle.time.string(from: first)) – \(ScheduleLabStyle.time.string(from: last))",
                      systemImage: "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.top, 14)
    }

    // MARK: actions

    private func step(_ delta: Int) {
        withAnimation(LabAnim.snappy) {
            weekOffset += delta
            let candidates = store.week(offset: weekOffset)
            if !candidates.isEmpty {
                let weekday = Calendar.current.component(.weekday, from: selectedDay) - 1
                selectedDay = candidates[min(max(weekday, 0), candidates.count - 1)]
            }
        }
        LabHaptics.impact(.soft)
    }

    private func jumpToToday() {
        withAnimation(LabAnim.gentle) {
            weekOffset = 0
            selectedDay = Calendar.current.startOfDay(for: Date())
        }
        LabHaptics.impact()
    }
}

// MARK: - Timeline canvas

private struct RailTimeline: View {
    let shifts: [Session]
    let day: Date
    let hourHeight: CGFloat
    let gutter: CGFloat
    let onSelect: (Session) -> Void

    /// A block placed on the axis: which lane it sits in, and how many lanes the
    /// cluster it belongs to needs. That is what makes overlaps legible instead
    /// of stacked on top of each other.
    private struct Placement: Identifiable {
        let id: String
        let session: Session
        let start: Date
        let end: Date
        let lane: Int
        let lanes: Int
    }

    // Laid out once at init — the body reads these several times, and lane
    // assignment is O(n log n) over the day's shifts.
    private let placements: [Placement]
    private let hourRange: ClosedRange<Int>

    init(shifts: [Session], day: Date, hourHeight: CGFloat, gutter: CGFloat, onSelect: @escaping (Session) -> Void) {
        self.shifts = shifts
        self.day = day
        self.hourHeight = hourHeight
        self.gutter = gutter
        self.onSelect = onSelect
        self.placements = Self.layout(shifts)
        self.hourRange = Self.hourRange(for: self.placements)
    }

    /// Greedy lane assignment: walk the day in start order, drop each shift into
    /// the first lane whose previous block has already ended, and start a new
    /// lane when none has. Blocks that never overlap all keep the full width.
    private static func layout(_ shifts: [Session]) -> [Placement] {
        let timed = shifts.compactMap { session -> (Session, Date, Date)? in
            guard let start = session.startDate else { return nil }
            let end = session.endDate ?? start.addingTimeInterval(3600)
            return (session, start, max(end, start.addingTimeInterval(900)))
        }
        .sorted { $0.1 < $1.1 }

        var result: [Placement] = []
        var cluster: [(Session, Date, Date)] = []

        func flush() {
            guard !cluster.isEmpty else { return }
            var laneEnds: [Date] = []
            var assigned: [(Session, Date, Date, Int)] = []
            for item in cluster {
                if let lane = laneEnds.firstIndex(where: { $0 <= item.1 }) {
                    laneEnds[lane] = item.2
                    assigned.append((item.0, item.1, item.2, lane))
                } else {
                    laneEnds.append(item.2)
                    assigned.append((item.0, item.1, item.2, laneEnds.count - 1))
                }
            }
            let lanes = laneEnds.count
            result += assigned.map {
                Placement(id: $0.0.dayOccurrenceKey, session: $0.0, start: $0.1, end: $0.2, lane: $0.3, lanes: lanes)
            }
            cluster = []
        }

        for item in timed {
            let clusterEnd = cluster.map({ $0.2 }).max()
            if let clusterEnd, item.1 >= clusterEnd { flush() }
            cluster.append(item)
        }
        flush()
        return result
    }

    /// Axis bounds: an hour of air either side of the day's real extent.
    private static func hourRange(for placements: [Placement]) -> ClosedRange<Int> {
        let calendar = Calendar.current
        let starts = placements.map { calendar.component(.hour, from: $0.start) }
        let ends = placements.map { placement -> Int in
            let hour = calendar.component(.hour, from: placement.end)
            let minute = calendar.component(.minute, from: placement.end)
            return minute > 0 ? hour + 1 : hour
        }
        let low = max((starts.min() ?? 8) - 1, 0)
        let high = min((ends.max() ?? 18) + 1, 24)
        return low...max(high, low + 3)
    }

    private var canvasHeight: CGFloat {
        CGFloat(hourRange.upperBound - hourRange.lowerBound) * hourHeight
    }

    private func offset(for date: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = Double(calendar.component(.hour, from: date))
        let minute = Double(calendar.component(.minute, from: date))
        return CGFloat(hour + minute / 60 - Double(hourRange.lowerBound)) * hourHeight
    }

    var body: some View {
        GeometryReader { proxy in
            let laneWidth = proxy.size.width - gutter
            ZStack(alignment: .topLeading) {
                hourGrid
                if Calendar.current.isDateInToday(day) { nowLine }
                ForEach(placements) { placement in
                    block(placement, laneWidth: laneWidth)
                }
            }
        }
        .frame(height: canvasHeight)
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(Array(hourRange), id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(hourLabel(hour))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: gutter - 8, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle()
                        .fill(Color(.separator).opacity(0.45))
                        .frame(height: 0.5)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour % 24
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return ScheduleLabStyle.time.string(from: date)
            .replacingOccurrences(of: ":00", with: "")
    }

    /// Live "now" marker — ticks every minute rather than only on redraw.
    private var nowLine: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let y = offset(for: context.date)
            if y >= 0 && y <= canvasHeight {
                HStack(spacing: 0) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .offset(x: gutter - 11)
                    Rectangle()
                        .fill(Color.red.opacity(0.8))
                        .frame(height: 1.5)
                }
                .offset(y: y - 3)
            }
        }
    }

    private func block(_ placement: Placement, laneWidth: CGFloat) -> some View {
        let width = (laneWidth / CGFloat(placement.lanes)) - 6
        let height = max(offset(for: placement.end) - offset(for: placement.start), 34)
        let accent = ScheduleLabStyle.accent(for: placement.session)

        return Button {
            LabHaptics.impact(.light)
            onSelect(placement.session)
        } label: {
            RailBlock(session: placement.session, accent: accent, compact: height < 64)
                .frame(width: width, height: height, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .offset(x: gutter + CGFloat(placement.lane) * (laneWidth / CGFloat(placement.lanes)),
                y: offset(for: placement.start))
    }
}

private struct RailBlock: View {
    let session: Session
    let accent: Color
    let compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.schoolName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(compact ? 1 : 2)
                    if !session.isPublished {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
                if !compact {
                    Text(ScheduleLabStyle.timeRange(session))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let label = session.multiDayLabel {
                        Text(label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    Spacer(minLength: 0)
                    LabCrewStack(crew: session.photographers, size: 20, maxVisible: 3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(accent.opacity(session.isPublished ? 0.28 : 0.6),
                              style: StrokeStyle(lineWidth: 1, dash: session.isPublished ? [] : [4, 3]))
        }
    }
}

private struct RailTimeOffBanner: View {
    let entry: TimeOffCalendarEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.reason.systemImageName)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.reason.displayName) · \(entry.photographerName)")
                    .font(.subheadline.weight(.semibold))
                Text(entry.isPartialDay ? "\(entry.startTime)–\(entry.endTime)" : "All day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LabBadge(text: entry.status.displayName,
                     systemImage: entry.status.systemImageName,
                     tint: ScheduleLabStyle.accent(for: entry))
        }
        .padding(12)
        .background(ScheduleLabStyle.accent(for: entry).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Detail

struct RailShiftDetailView: View {
    let session: Session
    @State private var selectedDayID: String?

    private var activeDay: SessionDay? {
        if let selectedDayID, let match = session.days.first(where: { $0.id == selectedDayID }) { return match }
        return session.day(onDate: session.date)
    }

    private var accent: Color { ScheduleLabStyle.accent(for: session) }

    private var displayedSession: Session {
        if let activeDay { return session.with(day: activeDay) }
        return session
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroBlock
                runOfShow
                if session.dayCount > 1 { dayPicker }
                crewSection
                notesSections
                staffingSection
                footer
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.schoolName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: LabActions.shareText(for: displayedSession)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear { selectedDayID = session.day(onDate: session.date)?.id }
        .tint(accent)
    }

    // Hero: the two facts you open a shift for — when, and for how long.
    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(session.sessionType, id: \.self) { type in
                    LabBadge(text: ScheduleLabStyle.typeName(type, in: session),
                             systemImage: nil,
                             tint: ScheduleLabStyle.typeColor(type))
                }
                if !session.isPublished {
                    LabBadge(text: "Draft", systemImage: "pencil", tint: .orange)
                }
            }
            Text(ScheduleLabStyle.timeRange(displayedSession))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            HStack(spacing: 14) {
                if let start = displayedSession.startDate {
                    Label(ScheduleLabStyle.longDate.string(from: start), systemImage: "calendar")
                }
                if let duration = ScheduleLabStyle.duration(displayedSession) {
                    Label(duration, systemImage: "hourglass")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    // The rail: the day as a sequence of moments rather than a table of fields.
    private var runOfShow: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailStop(time: displayedSession.startDate,
                     title: "Call time",
                     detail: session.schoolName,
                     systemImage: "figure.walk.arrival",
                     accent: accent,
                     isFirst: true,
                     isLast: false)
            RailStop(time: nil,
                     title: ScheduleLabStyle.duration(displayedSession).map { "\($0) on site" } ?? "On site",
                     detail: activeDay?.day_notes,
                     systemImage: ScheduleLabStyle.symbol(for: session),
                     accent: accent,
                     isFirst: false,
                     isLast: false)
            RailStop(time: displayedSession.endDate,
                     title: "Wrap",
                     detail: nil,
                     systemImage: "checkmark.circle",
                     accent: accent,
                     isFirst: false,
                     isLast: true)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabSectionTitle("This job runs \(session.dayCount) days")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(session.sortedDays.enumerated()), id: \.element.id) { index, day in
                        let isActive = day.id == activeDay?.id
                        Button {
                            withAnimation(LabAnim.snappy) { selectedDayID = day.id }
                            LabHaptics.selection()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Day \(index + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(isActive ? accent : .secondary)
                                Text(dayLabel(day))
                                    .font(.subheadline.weight(.semibold))
                                if let times = dayTimes(day) {
                                    Text(times).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 132, alignment: .leading)
                            .padding(10)
                            .background(isActive ? accent.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isActive ? accent.opacity(0.5) : .clear, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .labScrollTargets()
            }
            .labCarousel(margin: 0)
        }
    }

    private func dayLabel(_ day: SessionDay) -> String {
        guard let date = Session.parseDateTime(date: day.date, time: "00:00") else { return day.date }
        return ScheduleLabStyle.monthDay.string(from: date)
    }

    private func dayTimes(_ day: SessionDay) -> String? {
        guard let startString = day.start_time,
              let start = Session.parseDateTime(date: day.date, time: startString) else { return nil }
        guard let endString = day.end_time,
              let end = Session.parseDateTime(date: day.date, time: endString) else {
            return ScheduleLabStyle.time.string(from: start)
        }
        return "\(ScheduleLabStyle.time.string(from: start))–\(ScheduleLabStyle.time.string(from: end))"
    }

    private var crewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabSectionTitle("Crew for this day", trailing: "\(displayedSession.photographers.count)")
            ForEach(displayedSession.photographers, id: \.id) { person in
                HStack(spacing: 12) {
                    LabAvatar(name: person.name, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).font(.subheadline.weight(.semibold))
                        if let notes = person.notes, !notes.isEmpty {
                            Text(notes).font(.caption).foregroundStyle(.secondary)
                        } else if let email = person.email {
                            Text(email).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var notesSections: some View {
        if let dayNotes = activeDay?.day_notes, !dayNotes.isEmpty {
            LabNoteCard(title: "Notes for this day", text: dayNotes, accent: accent)
        }
        if let notes = session.notes, !notes.isEmpty {
            LabNoteCard(title: "Session notes", text: notes, accent: .secondary)
        }
    }

    private var staffingSection: some View {
        HStack(spacing: 10) {
            LabStatTile(value: session.photographersNeeded, label: "Photographers", systemImage: "camera.fill", tint: .blue)
            LabStatTile(value: session.posersNeeded, label: "Posers", systemImage: "person.fill", tint: .green)
            LabStatTile(value: session.helpersNeeded, label: "Helpers", systemImage: "hands.sparkles.fill", tint: .orange)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let url = LabActions.directionsURL(for: session) {
                Link(destination: url) {
                    Label("Directions", systemImage: "car.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
            }
            ShareLink(item: LabActions.shareText(for: displayedSession)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct RailStop: View {
    let time: Date?
    let title: String
    let detail: String?
    let systemImage: String
    let accent: Color
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time.map { ScheduleLabStyle.time.string(from: $0) } ?? "")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? .clear : accent.opacity(0.25))
                    .frame(width: 2, height: 8)
                ZStack {
                    Circle().fill(accent.opacity(0.16)).frame(width: 26, height: 26)
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Rectangle()
                    .fill(isLast ? .clear : accent.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, isLast ? 0 : 14)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 46)
    }
}

// MARK: - Shared design-lab chrome used by several designs

struct LabSectionTitle: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct LabNoteCard: View {
    let title: String
    let text: String
    var accent: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabSectionTitle(title)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 14)
        }
    }
}

struct LabStatTile: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// My Shifts / All Shifts control, shared so the five designs are compared on
/// layout rather than on who remembered to build the filter.
struct LabModeMenu: View {
    @ObservedObject var store: ScheduleLabStore

    var body: some View {
        Menu {
            Picker("Show", selection: Binding(get: { store.mode }, set: { store.mode = $0 })) {
                ForEach(ScheduleMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
        } label: {
            Image(systemName: store.mode == .myShifts
                  ? "person.crop.circle.fill"
                  : "person.2.circle.fill")
        }
    }
}

// MARK: - Preview

struct RailScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        RailScheduleView()
    }
}
