//  Design4_Agenda.swift
//  Schedule Design Lab — Design 4: "Agenda"
//
//  Premise: the schedule is a document you read, not a canvas you interpret. A
//  continuous scroll of days with pinned headers, a dense typographic row per
//  shift, search across school/crew/type, and swipe actions for the two things
//  people do most (navigate there, send it on). No paging, no modes to learn —
//  scroll forward and the future keeps arriving.
//
//  Detail: a native grouped list. Highest information density of the five, and
//  the cheapest to extend when the next field ships.

import SwiftUI
import Charts
import UIKit

struct AgendaScheduleView: View {
    @ObservedObject private var store = ScheduleLabStore.shared
    @Environment(\.openURL) private var openURL

    @State private var weekOffset = 0
    @State private var query = ""
    @State private var hideEmptyDays = true
    @State private var pushed: Session?

    /// Four weeks from the anchor week — enough to read forward without paging.
    private var days: [Date] {
        (0..<4).flatMap { store.week(offset: weekOffset + $0) }
    }

    private var anchorWeek: [Date] { store.week(offset: weekOffset) }

    var body: some View {
        NavigationStack {
            List {
                weekChartSection
                ForEach(visibleDays, id: \.self) { day in
                    daySection(day)
                }
                if visibleDays.isEmpty {
                    LabEmptyDay(title: "No matches",
                                message: query.isEmpty ? "Nothing scheduled in this window." : "Nothing matches “\(query)”.",
                                systemImage: "text.magnifyingglass")
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "School, person, or type")
            .refreshable { await store.reload() }
            .navigationTitle("Agenda")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { optionsMenu }
                ToolbarItem(placement: .navigationBarLeading) { weekStepper }
            }
            .labPush(item: $pushed) { session in
                AgendaDetailView(session: session)
            }
        }
        .tint(.blue)
    }

    // MARK: chrome

    private var weekStepper: some View {
        HStack(spacing: 2) {
            Button { withAnimation(LabAnim.snappy) { weekOffset -= 1 } } label: {
                Image(systemName: "chevron.left")
            }
            if weekOffset != 0 {
                Button("Today") { withAnimation(LabAnim.snappy) { weekOffset = 0 } }
                    .font(.subheadline.weight(.semibold))
            }
            Button { withAnimation(LabAnim.snappy) { weekOffset += 1 } } label: {
                Image(systemName: "chevron.right")
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Show", selection: Binding(get: { store.mode }, set: { store.mode = $0 })) {
                ForEach(ScheduleMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("Hide empty days", isOn: $hideEmptyDays)
            Divider()
            Button {
                Task { await store.reload() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: sections

    private var visibleDays: [Date] {
        days.filter { day in
            let items = filteredItems(on: day)
            return hideEmptyDays ? !items.isEmpty : true
        }
    }

    /// Search runs over the fields people actually remember: the school, who they
    /// were with, and what kind of job it was.
    private func filteredItems(on day: Date) -> [ScheduleLabItem] {
        let items = store.items(on: day)
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            switch item {
            case .shift(let session):
                let haystack = ([session.schoolName]
                                + session.photographers.map(\.name)
                                + session.sessionType.map { ScheduleLabStyle.typeName($0, in: session) }
                                + [session.notes ?? ""])
                    .joined(separator: " ")
                    .lowercased()
                return haystack.contains(trimmed)
            case .timeOff(let entry):
                return "\(entry.reason.displayName) \(entry.photographerName)".lowercased().contains(trimmed)
            }
        }
    }

    private var weekChartSection: some View {
        Section {
            AgendaWeekChart(week: anchorWeek, store: store)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            HStack {
                Text(weekLabel)
                Spacer()
                Text(store.mode.rawValue)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var weekLabel: String {
        guard let first = anchorWeek.first, let last = anchorWeek.last else { return "" }
        return "\(ScheduleLabStyle.monthDay.string(from: first)) – \(ScheduleLabStyle.monthDay.string(from: last))"
    }

    private func daySection(_ day: Date) -> some View {
        let items = filteredItems(on: day)
        return Section {
            if items.isEmpty {
                Text("Clear")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(items) { item in
                    row(item)
                }
            }
        } header: {
            AgendaDayHeader(date: day, count: items.count)
        }
    }

    @ViewBuilder
    private func row(_ item: ScheduleLabItem) -> some View {
        switch item {
        case .shift(let session):
            Button {
                pushed = session
            } label: {
                AgendaShiftRow(session: session)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    UIPasteboard.general.string = LabActions.shareText(for: session)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .tint(.indigo)

                if let url = LabActions.directionsURL(for: session) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Directions", systemImage: "car.fill")
                    }
                    .tint(.blue)
                }
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = LabActions.shareText(for: session)
                } label: {
                    Label("Copy summary", systemImage: "doc.on.doc")
                }
                if let url = LabActions.directionsURL(for: session) {
                    Button { openURL(url) } label: { Label("Directions", systemImage: "car.fill") }
                }
            }
        case .timeOff(let entry):
            AgendaTimeOffRow(entry: entry)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
        }
    }
}

// MARK: - Week chart

private struct AgendaWeekChart: View {
    let week: [Date]
    @ObservedObject var store: ScheduleLabStore

    private struct Bar: Identifiable {
        let id: Date
        let label: String
        let hours: Double
        let isToday: Bool
    }

    private var bars: [Bar] {
        week.map { date in
            let hours = store.shifts(on: date).reduce(0.0) { total, session in
                guard let start = session.startDate, let end = session.endDate, end > start else { return total }
                return total + end.timeIntervalSince(start) / 3600
            }
            return Bar(id: date,
                       label: ScheduleLabStyle.weekdayNarrow.string(from: date),
                       hours: hours,
                       isToday: Calendar.current.isDateInToday(date))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ScheduleLabStyle.durationString(store.hours(in: week) * 3600))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                Text("scheduled this week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart(bars) { bar in
                BarMark(
                    x: .value("Day", bar.label),
                    y: .value("Hours", bar.hours)
                )
                .foregroundStyle(bar.isToday ? Color.blue : Color.blue.opacity(0.35))
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(Int(hours))h").font(.system(size: 9))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 10, weight: .semibold))
                }
            }
            .frame(height: 76)
        }
    }
}

// MARK: - Rows

private struct AgendaDayHeader: View {
    let date: Date
    let count: Int

    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        return HStack(spacing: 8) {
            Text(ScheduleLabStyle.weekdayFull.string(from: date))
                .fontWeight(isToday ? .heavy : .semibold)
                .foregroundStyle(isToday ? Color.blue : .primary)
            Text(ScheduleLabStyle.monthDay.string(from: date))
                .foregroundStyle(.secondary)
            if isToday {
                Text("Today")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue))
                    .foregroundStyle(.white)
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .font(.subheadline)
    }
}

private struct AgendaShiftRow: View {
    let session: Session

    var body: some View {
        let accent = ScheduleLabStyle.accent(for: session)
        return HStack(alignment: .top, spacing: 12) {
            // Time gutter: the column your eye runs down when scanning a day.
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.startDate.map { ScheduleLabStyle.time.string(from: $0) } ?? "—")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(ScheduleLabStyle.duration(session) ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 62, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.schoolName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    if !session.isPublished {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(session.sessionType.prefix(2), id: \.self) { type in
                        Text(ScheduleLabStyle.typeName(type, in: session))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ScheduleLabStyle.typeColor(type))
                    }
                    if let label = session.multiDayLabel {
                        Text("· \(label)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if !session.photographers.isEmpty {
                    HStack(spacing: 6) {
                        LabCrewStack(crew: session.photographers, size: 20, maxVisible: 3)
                        Text(session.photographers.map(\.name).joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
    }
}

private struct AgendaTimeOffRow: View {
    let entry: TimeOffCalendarEntry

    var body: some View {
        let tint = ScheduleLabStyle.accent(for: entry)
        return HStack(alignment: .top, spacing: 12) {
            Text(entry.isPartialDay ? entry.startTime : "All day")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(tint.opacity(0.5))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: entry.reason.systemImageName)
                        .font(.caption2)
                        .foregroundStyle(tint)
                    Text(entry.reason.displayName)
                        .font(.system(size: 15, weight: .medium))
                }
                Text("\(entry.photographerName) · \(entry.status.displayName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Detail

struct AgendaDetailView: View {
    let session: Session
    @State private var selectedDayID: String?
    @State private var showAllCrew = false

    private var accent: Color { ScheduleLabStyle.accent(for: session) }
    private var activeDay: SessionDay? {
        if let selectedDayID, let day = session.days.first(where: { $0.id == selectedDayID }) { return day }
        return session.day(onDate: session.date)
    }
    private var shown: Session { activeDay.map { session.with(day: $0) } ?? session }

    var body: some View {
        List {
            Section {
                headerRow
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            }

            Section("When") {
                LabeledContent("Date") {
                    Text(shown.startDate.map { ScheduleLabStyle.longDate.string(from: $0) } ?? "—")
                }
                LabeledContent("Time", value: ScheduleLabStyle.timeRange(shown))
                if let duration = ScheduleLabStyle.duration(shown) {
                    LabeledContent("Duration", value: duration)
                }
                if session.dayCount > 1 {
                    LabeledContent("Part of", value: "\(session.dayCount)-day job")
                }
            }

            if session.dayCount > 1 {
                Section("Days") {
                    ForEach(Array(session.sortedDays.enumerated()), id: \.element.id) { index, day in
                        Button {
                            withAnimation(LabAnim.snappy) { selectedDayID = day.id }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Day \(index + 1) · \(dayLabel(day))")
                                        .font(.subheadline.weight(day.id == activeDay?.id ? .semibold : .regular))
                                    if let notes = day.day_notes, !notes.isEmpty {
                                        Text(notes).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if day.id == activeDay?.id {
                                    Image(systemName: "checkmark").foregroundStyle(accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Crew on this day") {
                ForEach(visibleCrew, id: \.id) { person in
                    HStack(spacing: 12) {
                        LabAvatar(name: person.name, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.name).font(.subheadline)
                            if let notes = person.notes, !notes.isEmpty {
                                Text(notes).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                if shown.photographers.count > 4 {
                    Button(showAllCrew ? "Show fewer" : "Show all \(shown.photographers.count)") {
                        withAnimation(LabAnim.snappy) { showAllCrew.toggle() }
                    }
                    .font(.subheadline)
                }
                if shown.photographers.isEmpty {
                    Text("Nobody assigned").foregroundStyle(.secondary)
                }
            }

            Section("Staffing needed") {
                LabeledContent("Photographers", value: "\(session.photographersNeeded)")
                LabeledContent("Posers", value: "\(session.posersNeeded)")
                LabeledContent("Helpers", value: "\(session.helpersNeeded)")
            }

            if let notes = activeDay?.day_notes, !notes.isEmpty {
                Section("Notes for this day") {
                    Text(notes).font(.subheadline)
                }
            }
            if let notes = session.notes, !notes.isEmpty {
                Section("Session notes") {
                    Text(notes).font(.subheadline)
                }
            }

            Section {
                if let url = LabActions.directionsURL(for: session) {
                    Link(destination: url) {
                        Label("Get directions", systemImage: "car.fill")
                    }
                }
                ShareLink(item: LabActions.shareText(for: shown)) {
                    Label("Share shift", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = LabActions.shareText(for: shown)
                } label: {
                    Label("Copy summary", systemImage: "doc.on.doc")
                }
            }

            Section("Record") {
                LabeledContent("Status", value: session.isPublished ? "Published" : "Draft")
                if let creator = session.createdBy {
                    LabeledContent("Scheduled by", value: creator.name)
                }
                LabeledContent("Created", value: ScheduleLabStyle.monthDay.string(from: session.createdAt))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.schoolName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedDayID = session.day(onDate: session.date)?.id }
        .tint(accent)
    }

    private var visibleCrew: [SessionPhotographer] {
        showAllCrew ? shown.photographers : Array(shown.photographers.prefix(4))
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.gradient)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: ScheduleLabStyle.symbol(for: session))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(session.schoolName)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    ForEach(session.sessionType, id: \.self) { type in
                        LabBadge(text: ScheduleLabStyle.typeName(type, in: session),
                                 tint: ScheduleLabStyle.typeColor(type))
                    }
                    if !session.isPublished {
                        LabBadge(text: "Draft", systemImage: "pencil", tint: .orange)
                    }
                }
            }
            Spacer()
        }
    }

    private func dayLabel(_ day: SessionDay) -> String {
        guard let date = Session.parseDateTime(date: day.date, time: "00:00") else { return day.date }
        var label = ScheduleLabStyle.monthDay.string(from: date)
        if let startString = day.start_time,
           let start = Session.parseDateTime(date: day.date, time: startString) {
            label += ", \(ScheduleLabStyle.time.string(from: start))"
        }
        return label
    }
}

// MARK: - Preview

struct AgendaScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        AgendaScheduleView()
    }
}
