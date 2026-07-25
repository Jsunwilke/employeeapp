//  Design3_WeekBoard.swift
//  Schedule Design Lab — Design 3: "Board"
//
//  Premise: the week is the unit people plan in. Every other design makes you
//  tap a day to find out what is in it; this one puts all seven days on one
//  screen as horizontal tracks against a shared hour axis, so gaps, long days,
//  double-books and the shape of the week are visible without a single tap.
//
//  Detail: a sheet inspector with detents — you can peek at a job at half
//  height, keep the week behind it, and drag up for everything.

import SwiftUI

struct BoardScheduleView: View {
    @ObservedObject private var store = ScheduleLabStore.shared

    @State private var weekOffset = 0
    @State private var inspected: Session?
    @State private var inspectedTimeOff: TimeOffCalendarEntry?

    private var week: [Date] { store.week(offset: weekOffset) }

    /// The hour window the board draws. Derived from the week's real extent so a
    /// week of evening games doesn't waste half the screen on empty mornings.
    private var hourWindow: ClosedRange<Int> {
        let calendar = Calendar.current
        var earliest = 23
        var latest = 0
        var found = false
        for day in week {
            for session in store.shifts(on: day) {
                guard let start = session.startDate else { continue }
                let end = session.endDate ?? start
                earliest = min(earliest, calendar.component(.hour, from: start))
                let endHour = calendar.component(.hour, from: end) + (calendar.component(.minute, from: end) > 0 ? 1 : 0)
                latest = max(latest, endHour)
                found = true
            }
        }
        guard found else { return 8...18 }
        return max(earliest - 1, 0)...min(max(latest + 1, earliest + 4), 24)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekHeader
                axis
                Divider()
                board
                summaryBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { LabModeMenu(store: store) }
            }
            .sheet(item: $inspected) { session in
                BoardInspector(session: session)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .labCornerRadiusForSheet(28)
            }
            .sheet(item: $inspectedTimeOff) { entry in
                BoardTimeOffInspector(entry: entry)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
                    .labCornerRadiusForSheet(28)
            }
        }
        .tint(.teal)
    }

    // MARK: header

    private var weekHeader: some View {
        HStack {
            Button { move(-1) } label: { chevron("chevron.left") }
            VStack(spacing: 1) {
                Text(rangeLabel)
                    .font(.system(.headline, design: .rounded))
                Text(subtitleLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            Button { move(1) } label: { chevron("chevron.right") }
        }
        .overlay(alignment: .trailing) {
            if weekOffset != 0 {
                Button("Today") { withAnimation(LabAnim.snappy) { weekOffset = 0 } }
                    .font(.caption.weight(.bold))
                    .padding(.trailing, 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.footnote.weight(.bold))
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color(.tertiarySystemFill)))
            .foregroundStyle(.primary)
    }

    private var rangeLabel: String {
        guard let first = week.first, let last = week.last else { return "" }
        return "\(ScheduleLabStyle.monthDay.string(from: first)) – \(ScheduleLabStyle.monthDay.string(from: last))"
    }

    private var subtitleLabel: String {
        let count = week.reduce(0) { $0 + store.shifts(on: $1).count }
        let hours = store.hours(in: week)
        guard count > 0 else { return "Nothing scheduled" }
        return "\(count) shifts · \(ScheduleLabStyle.durationString(hours * 3600))"
    }

    // MARK: axis

    private var axis: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: BoardMetrics.railWidth)
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(stride(from: hourWindow.lowerBound, through: hourWindow.upperBound, by: hourStep)), id: \.self) { hour in
                        Text(BoardMetrics.hourLabel(hour))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .offset(x: BoardMetrics.x(forHour: Double(hour), in: hourWindow, width: proxy.size.width))
                    }
                }
            }
            .frame(height: 14)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    /// Label every hour when there's room, every other hour when the window is long.
    private var hourStep: Int {
        hourWindow.count > 10 ? 2 : 1
    }

    // MARK: board

    private var board: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(week, id: \.self) { date in
                    BoardDayRow(
                        date: date,
                        shifts: store.shifts(on: date),
                        timeOff: store.timeOffEntries(on: date),
                        hourWindow: hourWindow,
                        onSelectShift: { inspected = $0 },
                        onSelectTimeOff: { inspectedTimeOff = $0 }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .labNoBounceWhenShort()
    }

    // MARK: summary

    private var summaryBar: some View {
        let busiest = week.max { store.staffing(on: $0).total < store.staffing(on: $1).total }
        return HStack(spacing: 0) {
            summaryCell(title: "Shifts", value: "\(week.reduce(0) { $0 + store.shifts(on: $1).count })")
            Divider().frame(height: 26)
            summaryCell(title: "Hours", value: ScheduleLabStyle.durationString(store.hours(in: week) * 3600))
            Divider().frame(height: 26)
            summaryCell(
                title: "Heaviest",
                value: busiest.map { ScheduleLabStyle.weekdayShort.string(from: $0) } ?? "—"
            )
        }
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func summaryCell(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func move(_ delta: Int) {
        withAnimation(LabAnim.snappy) { weekOffset += delta }
        LabHaptics.impact(.soft)
    }
}

// MARK: - Board geometry

enum BoardMetrics {
    static let railWidth: CGFloat = 46
    static let laneHeight: CGFloat = 34

    static func x(forHour hour: Double, in window: ClosedRange<Int>, width: CGFloat) -> CGFloat {
        let span = Double(window.upperBound - window.lowerBound)
        guard span > 0 else { return 0 }
        return CGFloat((hour - Double(window.lowerBound)) / span) * width
    }

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour % 24
        let date = Calendar.current.date(from: components) ?? Date()
        return ScheduleLabStyle.time.string(from: date)
            .replacingOccurrences(of: ":00", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}

// MARK: - Day row

private struct BoardDayRow: View {
    let date: Date
    let shifts: [Session]
    let timeOff: [TimeOffCalendarEntry]
    let hourWindow: ClosedRange<Int>
    let onSelectShift: (Session) -> Void
    let onSelectTimeOff: (TimeOffCalendarEntry) -> Void

    private struct Lane {
        var items: [Session] = []
    }

    /// Pack the day's shifts into as few horizontal lanes as possible: a second
    /// lane only appears when two jobs actually overlap.
    private var lanes: [Lane] {
        var lanes: [Lane] = []
        for session in shifts.sorted(by: { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }) {
            guard let start = session.startDate else { continue }
            if let index = lanes.firstIndex(where: { lane in
                guard let last = lane.items.last, let lastEnd = last.endDate ?? last.startDate else { return true }
                return lastEnd <= start
            }) {
                lanes[index].items.append(session)
            } else {
                lanes.append(Lane(items: [session]))
            }
        }
        return lanes
    }

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var isPast: Bool { date < Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            rail
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    gridLines(width: proxy.size.width)
                    if isToday { nowMarker(width: proxy.size.width) }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(timeOff) { entry in
                            timeOffTrack(entry, width: proxy.size.width)
                        }
                        ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                            laneTrack(lane, width: proxy.size.width)
                        }
                    }
                }
            }
            .frame(height: rowHeight)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isToday ? Color.teal.opacity(0.09) : Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.teal.opacity(0.35), lineWidth: 1)
            }
        }
        .opacity(isPast ? 0.62 : 1)
    }

    private var rowHeight: CGFloat {
        let rows = max(lanes.count + timeOff.count, 1)
        return CGFloat(rows) * BoardMetrics.laneHeight + CGFloat(max(rows - 1, 0)) * 4
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ScheduleLabStyle.weekdayShort.string(from: date))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isToday ? Color.teal : .secondary)
            Text(ScheduleLabStyle.dayNumber.string(from: date))
                .font(.system(size: 18, weight: isToday ? .bold : .medium, design: .rounded))
        }
        .frame(width: BoardMetrics.railWidth, alignment: .leading)
    }

    private func gridLines(width: CGFloat) -> some View {
        ForEach(Array(hourWindow), id: \.self) { hour in
            Rectangle()
                .fill(Color(.separator).opacity(hour % 2 == 0 ? 0.35 : 0.18))
                .frame(width: 0.5)
                .offset(x: BoardMetrics.x(forHour: Double(hour), in: hourWindow, width: width))
        }
    }

    private func nowMarker(width: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let calendar = Calendar.current
            let hour = Double(calendar.component(.hour, from: context.date))
                + Double(calendar.component(.minute, from: context.date)) / 60
            let x = BoardMetrics.x(forHour: hour, in: hourWindow, width: width)
            if hour >= Double(hourWindow.lowerBound) && hour <= Double(hourWindow.upperBound) {
                Rectangle()
                    .fill(Color.red.opacity(0.75))
                    .frame(width: 1.5)
                    .offset(x: x)
            }
        }
    }

    private func laneTrack(_ lane: Lane, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(lane.items, id: \.dayOccurrenceKey) { session in
                if let start = session.startDate {
                    let end = session.endDate ?? start.addingTimeInterval(3600)
                    let startX = BoardMetrics.x(forHour: hours(start), in: hourWindow, width: width)
                    let endX = BoardMetrics.x(forHour: hours(end), in: hourWindow, width: width)
                    Button {
                        LabHaptics.impact(.light)
                        onSelectShift(session)
                    } label: {
                        BoardChip(session: session, width: max(endX - startX - 3, 26))
                    }
                    .buttonStyle(.plain)
                    .offset(x: startX)
                }
            }
        }
        .frame(height: BoardMetrics.laneHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeOffTrack(_ entry: TimeOffCalendarEntry, width: CGFloat) -> some View {
        let tint = ScheduleLabStyle.accent(for: entry)
        let startHour = entry.isPartialDay ? hours(fromClock: entry.startTime) : Double(hourWindow.lowerBound)
        let endHour = entry.isPartialDay ? hours(fromClock: entry.endTime) : Double(hourWindow.upperBound)
        let startX = BoardMetrics.x(forHour: startHour, in: hourWindow, width: width)
        let endX = BoardMetrics.x(forHour: endHour, in: hourWindow, width: width)

        return Button {
            onSelectTimeOff(entry)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: entry.reason.systemImageName).font(.system(size: 9, weight: .bold))
                Text(entry.reason.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(width: max(endX - startX - 3, 40), height: BoardMetrics.laneHeight - 8, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .offset(x: startX)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: BoardMetrics.laneHeight - 4)
    }

    private func hours(_ date: Date) -> Double {
        let calendar = Calendar.current
        return Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
    }

    private func hours(fromClock clock: String) -> Double {
        let parts = clock.split(separator: ":").compactMap { Double($0) }
        guard let hour = parts.first else { return Double(hourWindow.lowerBound) }
        return hour + (parts.count > 1 ? parts[1] / 60 : 0)
    }
}

private struct BoardChip: View {
    let session: Session
    let width: CGFloat

    var body: some View {
        let accent = ScheduleLabStyle.accent(for: session)
        return HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.schoolName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                if width > 120, let start = session.startDate {
                    Text(ScheduleLabStyle.time.string(from: start))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if width > 150 {
                LabCrewStack(crew: session.photographers, size: 16, maxVisible: 2)
            }
        }
        .padding(.trailing, 5)
        .frame(width: width, height: BoardMetrics.laneHeight - 8, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accent.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(accent.opacity(session.isPublished ? 0.3 : 0.7),
                              style: StrokeStyle(lineWidth: 1, dash: session.isPublished ? [] : [3, 2]))
        )
        .clipped()
    }
}

// MARK: - Inspector sheet

private struct BoardInspector: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .overview
    @State private var selectedDayID: String?

    private enum Tab: String, CaseIterable {
        case overview = "Overview"
        case crew = "Crew"
        case days = "Days"
    }

    private var accent: Color { ScheduleLabStyle.accent(for: session) }
    private var activeDay: SessionDay? {
        if let selectedDayID, let day = session.days.first(where: { $0.id == selectedDayID }) { return day }
        return session.day(onDate: session.date)
    }
    private var shown: Session { activeDay.map { session.with(day: $0) } ?? session }

    var body: some View {
        VStack(spacing: 0) {
            head
            Picker("Section", selection: $tab) {
                ForEach(availableTabs, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            ScrollView {
                switch tab {
                case .overview: overview
                case .crew: crewList
                case .days: daysList
                }
            }
            .labNoBounceWhenShort()
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { selectedDayID = session.day(onDate: session.date)?.id }
        .tint(accent)
    }

    private var availableTabs: [Tab] {
        session.dayCount > 1 ? Tab.allCases : [.overview, .crew]
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.gradient)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: ScheduleLabStyle.symbol(for: session))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(session.schoolName)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(2)
                Text(ScheduleLabStyle.timeRange(shown))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(accent)
                if let start = shown.startDate {
                    Text(ScheduleLabStyle.longDate.string(from: start))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var overview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(session.sessionType, id: \.self) { type in
                    LabBadge(text: ScheduleLabStyle.typeName(type, in: session),
                             tint: ScheduleLabStyle.typeColor(type))
                }
                if !session.isPublished { LabBadge(text: "Draft", systemImage: "pencil", tint: .orange) }
                Spacer()
            }

            HStack(spacing: 10) {
                LabStatTile(value: session.photographersNeeded, label: "Photog", systemImage: "camera.fill", tint: .blue)
                LabStatTile(value: session.posersNeeded, label: "Posers", systemImage: "person.fill", tint: .green)
                LabStatTile(value: session.helpersNeeded, label: "Helpers", systemImage: "hands.sparkles.fill", tint: .orange)
            }

            if let notes = activeDay?.day_notes, !notes.isEmpty {
                LabNoteCard(title: "This day", text: notes, accent: accent)
            }
            if let notes = session.notes, !notes.isEmpty {
                LabNoteCard(title: "Session notes", text: notes, accent: .secondary)
            }

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
                ShareLink(item: LabActions.shareText(for: shown)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    private var crewList: some View {
        VStack(spacing: 0) {
            ForEach(shown.photographers, id: \.id) { person in
                HStack(spacing: 12) {
                    LabAvatar(name: person.name, size: 40)
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
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                Divider().padding(.leading, 72)
            }
            if shown.photographers.isEmpty {
                LabEmptyDay(title: "No crew assigned",
                            message: "Nobody is on this day yet.",
                            systemImage: "person.badge.plus")
            }
        }
        .padding(.bottom, 30)
    }

    private var daysList: some View {
        VStack(spacing: 8) {
            ForEach(Array(session.sortedDays.enumerated()), id: \.element.id) { index, day in
                let isActive = day.id == activeDay?.id
                Button {
                    withAnimation(LabAnim.snappy) { selectedDayID = day.id }
                } label: {
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text("DAY").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                            Text("\(index + 1)").font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .frame(width: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dayLabel(day)).font(.subheadline.weight(.semibold))
                            if let notes = day.day_notes, !notes.isEmpty {
                                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Text("\(day.photographers?.count ?? 0) crew")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if isActive {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isActive ? accent.opacity(0.5) : .clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    private func dayLabel(_ day: SessionDay) -> String {
        guard let date = Session.parseDateTime(date: day.date, time: "00:00") else { return day.date }
        var label = "\(ScheduleLabStyle.weekdayFull.string(from: date)), \(ScheduleLabStyle.monthDay.string(from: date))"
        if let startString = day.start_time,
           let start = Session.parseDateTime(date: day.date, time: startString) {
            label += " · \(ScheduleLabStyle.time.string(from: start))"
        }
        return label
    }
}

private struct BoardTimeOffInspector: View {
    let entry: TimeOffCalendarEntry

    var body: some View {
        let tint = ScheduleLabStyle.accent(for: entry)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: entry.reason.systemImageName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.reason.displayName)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text(entry.photographerName).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            LabeledContent("When", value: entry.isPartialDay ? "\(entry.startTime) – \(entry.endTime)" : "All day")
            LabeledContent("Date", value: ScheduleLabStyle.longDate.string(from: entry.date))
            LabeledContent("Status", value: entry.status.displayName)
            if !entry.notes.isEmpty {
                LabNoteCard(title: "Note", text: entry.notes, accent: tint)
            }
            Spacer()
        }
        .font(.subheadline)
        .padding(20)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Preview

struct BoardScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        BoardScheduleView()
    }
}
