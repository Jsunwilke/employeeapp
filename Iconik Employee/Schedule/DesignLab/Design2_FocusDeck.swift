//  Design2_FocusDeck.swift
//  Schedule Design Lab — Design 2: "Deck"
//
//  Premise: on a shoot day you have one job in front of you, not a list. Each
//  shift is a full card you flick through; the card already carries what you'd
//  otherwise open the detail for (call time, crew, the note that matters), so
//  the detail is a continuation of the same card rather than a new screen.
//
//  Detail: the card grows into the page (matched geometry), so you never lose
//  your place in the deck.

import SwiftUI

struct DeckScheduleView: View {
    @ObservedObject private var store = ScheduleLabStore.shared

    @State private var weekOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var expanded: Session?
    @Namespace private var deck

    private var week: [Date] { store.week(offset: weekOffset) }
    private var items: [ScheduleLabItem] { store.items(on: selectedDay) }

    var body: some View {
        ZStack {
            backdrop
            if let session = expanded {
                // Only one view carries the hero id at a time, so the card's frame
                // is genuinely handed over instead of being mirrored.
                DeckDetailView(session: session, heroID: session.dayOccurrenceKey, namespace: deck) {
                    withAnimation(LabAnim.gentle) { expanded = nil }
                }
                .transition(.opacity)
                .zIndex(2)
            } else {
                VStack(spacing: 0) {
                    dayHeader
                    deckArea
                    weekRail
                }
                .transition(.opacity)
            }
        }
        .animation(LabAnim.gentle, value: expanded)
    }

    /// The day's dominant session color, washed behind everything. Gives each day
    /// its own temperature without tinting the content itself.
    private var backdrop: some View {
        let tint = store.shifts(on: selectedDay).first.map { ScheduleLabStyle.accent(for: $0) } ?? .gray
        return LinearGradient(
            colors: [tint.opacity(0.28), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: tint)
    }

    // MARK: header

    private var dayHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(ScheduleLabStyle.relativeDayLabel(selectedDay))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text(ScheduleLabStyle.longDate.string(from: selectedDay))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                LabModeMenu(store: store)
                    .font(.title2)
                Text(countLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private var countLabel: String {
        let shifts = store.shifts(on: selectedDay).count
        if shifts == 0 { return "Clear" }
        let hours = store.shifts(on: selectedDay).reduce(0.0) { total, session in
            guard let start = session.startDate, let end = session.endDate else { return total }
            return total + end.timeIntervalSince(start)
        }
        return "\(shifts) · \(ScheduleLabStyle.durationString(hours))"
    }

    // MARK: deck

    private var deckArea: some View {
        GeometryReader { outer in
            let cardWidth = min(outer.size.width - 56, 420)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if items.isEmpty {
                        emptyCard(width: cardWidth)
                    } else {
                        ForEach(items) { item in
                            deckCard(item, width: cardWidth, screenMid: outer.size.width / 2)
                        }
                    }
                }
                .padding(.vertical, 8)
                .labScrollTargets()
            }
            .labCarousel(margin: (outer.size.width - cardWidth) / 2)
            .labNoBounceWhenShort()
        }
    }

    @ViewBuilder
    private func deckCard(_ item: ScheduleLabItem, width: CGFloat, screenMid: CGFloat) -> some View {
        GeometryReader { proxy in
            // Depth: cards ease back as they leave the centre, so the focused
            // card is unambiguous even mid-scroll.
            let distance = abs(proxy.frame(in: .global).midX - screenMid)
            let scale = max(1 - (distance / (width * 3.2)), 0.9)

            Group {
                switch item {
                case .shift(let session):
                    Button {
                        LabHaptics.impact(.medium)
                        withAnimation(LabAnim.gentle) { expanded = session }
                    } label: {
                        DeckShiftCard(session: session, heroID: session.dayOccurrenceKey, namespace: deck)
                    }
                    .buttonStyle(.plain)
                case .timeOff(let entry):
                    DeckTimeOffCard(entry: entry)
                }
            }
            .scaleEffect(scale)
            .animation(.easeOut(duration: 0.15), value: scale)
        }
        .frame(width: width)
    }

    private func emptyCard(width: CGFloat) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing on this day")
                .font(.title3.weight(.semibold))
            if let next = store.nextShift() {
                VStack(spacing: 2) {
                    Text("Next up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(next.schoolName).font(.subheadline.weight(.semibold))
                    if let start = next.startDate {
                        Text("\(ScheduleLabStyle.monthDay.string(from: start)) · \(ScheduleLabStyle.time.string(from: start))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
                Button("Jump there") {
                    guard let start = next.startDate else { return }
                    withAnimation(LabAnim.gentle) {
                        weekOffset = store.weekOffset(containing: start)
                        selectedDay = Calendar.current.startOfDay(for: start)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: week rail

    private var weekRail: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shiftWeek(-1) } label: {
                    Image(systemName: "chevron.left").font(.footnote.weight(.bold))
                }
                Spacer()
                Text(ScheduleLabStyle.monthYear.string(from: week.first ?? Date()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { shiftWeek(1) } label: {
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)

            HStack(spacing: 8) {
                ForEach(week, id: \.self) { date in
                    railCell(date)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 14)
        .padding(.top, 6)
        .background(.ultraThinMaterial)
        .clipShape(UnevenTopRoundedRectangle(radius: 26))
        .ignoresSafeArea(edges: .bottom)
    }

    private func railCell(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDay)
        let count = store.shifts(on: date).count
        let isToday = Calendar.current.isDateInToday(date)

        return Button {
            withAnimation(LabAnim.snappy) { selectedDay = date }
            LabHaptics.selection()
        } label: {
            VStack(spacing: 5) {
                Text(ScheduleLabStyle.weekdayNarrow.string(from: date))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Text(ScheduleLabStyle.dayNumber.string(from: date))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                HStack(spacing: 2) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle().frame(width: 4, height: 4)
                    }
                    if count > 3 {
                        Text("+").font(.system(size: 8, weight: .bold))
                    }
                }
                .frame(height: 5)
                .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                }
            }
            .overlay(alignment: .top) {
                if isToday && !isSelected {
                    Capsule().fill(Color.accentColor).frame(width: 14, height: 2.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shiftWeek(_ delta: Int) {
        withAnimation(LabAnim.snappy) {
            weekOffset += delta
            let candidates = store.week(offset: weekOffset)
            if let first = candidates.first {
                let weekday = Calendar.current.component(.weekday, from: selectedDay) - 1
                selectedDay = candidates.indices.contains(weekday) ? candidates[weekday] : first
            }
        }
        LabHaptics.impact(.soft)
    }
}

// MARK: - Cards

private struct DeckShiftCard: View {
    let session: Session
    let heroID: String
    let namespace: Namespace.ID

    private var accent: Color { ScheduleLabStyle.accent(for: session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            VStack(alignment: .leading, spacing: 16) {
                times
                if !session.photographers.isEmpty { crew }
                if let note = highlightNote { noteBlock(note) }
                Spacer(minLength: 0)
                footer
            }
            .padding(20)
        }
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .matchedGeometryEffect(id: heroID, in: namespace)
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [accent, accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: ScheduleLabStyle.symbol(for: session))
                .font(.system(size: 78, weight: .semibold))
                .foregroundStyle(.white.opacity(0.16))
                .offset(x: 12, y: 18)
                .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(session.sessionType.prefix(2), id: \.self) { type in
                        Text(ScheduleLabStyle.typeName(type, in: session))
                            .font(.system(size: 10, weight: .bold))
                            .textCase(.uppercase)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.white.opacity(0.22)))
                    }
                    if !session.isPublished {
                        Text("Draft")
                            .font(.system(size: 10, weight: .bold))
                            .textCase(.uppercase)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.28)))
                    }
                }
                Text(session.schoolName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                if let label = session.multiDayLabel {
                    Text(label).font(.caption.weight(.semibold)).opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(height: 168)
    }

    private var times: some View {
        HStack(spacing: 0) {
            timeColumn(title: "Start", value: session.startDate.map { ScheduleLabStyle.time.string(from: $0) } ?? "—")
            Divider().frame(height: 34)
            timeColumn(title: "End", value: session.endDate.map { ScheduleLabStyle.time.string(from: $0) } ?? "—")
            Divider().frame(height: 34)
            timeColumn(title: "Length", value: ScheduleLabStyle.duration(session) ?? "—")
        }
    }

    private func timeColumn(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var crew: some View {
        HStack(spacing: 10) {
            LabCrewStack(crew: session.photographers, size: 30)
            Text(crewLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var crewLabel: String {
        let names = session.photographers.map(\.name)
        if names.count <= 2 { return names.joined(separator: " & ") }
        return "\(names[0]), \(names[1]) +\(names.count - 2) more"
    }

    /// The one note worth surfacing on the face of the card: this day's note
    /// first, then the session note.
    private var highlightNote: String? {
        if let day = session.day(onDate: session.date), let notes = day.day_notes, !notes.isEmpty {
            return notes
        }
        if let notes = session.notes, !notes.isEmpty { return notes }
        return nil
    }

    private func noteBlock(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Label("\(session.photographersNeeded + session.posersNeeded + session.helpersNeeded) needed",
                  systemImage: "person.2.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Open")
                .font(.caption.weight(.bold))
            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
        }
        .foregroundStyle(accent)
    }
}

private struct DeckTimeOffCard: View {
    let entry: TimeOffCalendarEntry

    var body: some View {
        let tint = ScheduleLabStyle.accent(for: entry)
        return VStack(alignment: .leading, spacing: 14) {
            Image(systemName: entry.reason.systemImageName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(tint)
            Text(entry.reason.displayName)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(entry.isPartialDay ? "\(entry.startTime) – \(entry.endTime)" : "All day")
                .font(.headline)
                .foregroundStyle(.secondary)
            LabBadge(text: entry.status.displayName, systemImage: entry.status.systemImageName, tint: tint)
            if !entry.notes.isEmpty {
                Text(entry.notes).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.photographerName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.1), radius: 14, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(tint.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }
}

// MARK: - Detail

private struct DeckDetailView: View {
    let session: Session
    let heroID: String
    let namespace: Namespace.ID
    let onClose: () -> Void

    @State private var selectedDayID: String?
    @State private var appeared = false

    private var accent: Color { ScheduleLabStyle.accent(for: session) }
    private var activeDay: SessionDay? {
        if let selectedDayID, let day = session.days.first(where: { $0.id == selectedDayID }) { return day }
        return session.day(onDate: session.date)
    }
    private var shown: Session { activeDay.map { session.with(day: $0) } ?? session }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    DeckShiftCard(session: shown, heroID: heroID, namespace: namespace)
                        .frame(height: 420)
                        .padding(.horizontal, 16)

                    Group {
                        quickActions
                        if session.dayCount > 1 { daysCard }
                        crewCard
                        notesCards
                        staffingCard
                        metaCard
                    }
                    .padding(.horizontal, 16)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)

                    Spacer(minLength: 40)
                }
                .padding(.top, 64)
            }

            closeBar
        }
        .onAppear {
            selectedDayID = session.day(onDate: session.date)?.id
            withAnimation(LabAnim.gentle.delay(0.12)) { appeared = true }
        }
        .tint(accent)
    }

    private var closeBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            ShareLink(item: LabActions.shareText(for: shown)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            if let url = LabActions.directionsURL(for: session) {
                Link(destination: url) {
                    DeckActionTile(title: "Directions", systemImage: "car.fill", tint: accent)
                }
            }
            DeckActionTile(title: "Crew", systemImage: "person.2.fill", tint: accent)
            DeckActionTile(title: "Add to cal", systemImage: "calendar.badge.plus", tint: accent)
        }
    }

    private var daysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabSectionTitle("Runs \(session.dayCount) days")
            ForEach(Array(session.sortedDays.enumerated()), id: \.element.id) { index, day in
                let isActive = day.id == activeDay?.id
                Button {
                    withAnimation(LabAnim.snappy) { selectedDayID = day.id }
                    LabHaptics.selection()
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(isActive ? accent : Color(.tertiarySystemFill)))
                            .foregroundStyle(isActive ? .white : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dayDateLabel(day)).font(.subheadline.weight(.semibold))
                            if let notes = day.day_notes, !notes.isEmpty {
                                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(dayTimeLabel(day) ?? "")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .deckCardStyle()
    }

    private func dayDateLabel(_ day: SessionDay) -> String {
        guard let date = Session.parseDateTime(date: day.date, time: "00:00") else { return day.date }
        return "\(ScheduleLabStyle.weekdayShort.string(from: date)) \(ScheduleLabStyle.monthDay.string(from: date))"
    }

    private func dayTimeLabel(_ day: SessionDay) -> String? {
        guard let startString = day.start_time,
              let start = Session.parseDateTime(date: day.date, time: startString) else { return nil }
        guard let endString = day.end_time,
              let end = Session.parseDateTime(date: day.date, time: endString) else {
            return ScheduleLabStyle.time.string(from: start)
        }
        return "\(ScheduleLabStyle.time.string(from: start))–\(ScheduleLabStyle.time.string(from: end))"
    }

    private var crewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabSectionTitle("On this day", trailing: "\(shown.photographers.count)")
            ForEach(shown.photographers, id: \.id) { person in
                HStack(spacing: 12) {
                    LabAvatar(name: person.name, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(person.name).font(.subheadline.weight(.semibold))
                        if let notes = person.notes, !notes.isEmpty {
                            Text(notes).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .deckCardStyle()
    }

    @ViewBuilder
    private var notesCards: some View {
        if let dayNotes = activeDay?.day_notes, !dayNotes.isEmpty {
            LabNoteCard(title: "This day", text: dayNotes, accent: accent)
        }
        if let notes = session.notes, !notes.isEmpty {
            LabNoteCard(title: "Session notes", text: notes, accent: .secondary)
        }
    }

    private var staffingCard: some View {
        HStack(spacing: 10) {
            LabStatTile(value: session.photographersNeeded, label: "Photographers", systemImage: "camera.fill", tint: .blue)
            LabStatTile(value: session.posersNeeded, label: "Posers", systemImage: "person.fill", tint: .green)
            LabStatTile(value: session.helpersNeeded, label: "Helpers", systemImage: "hands.sparkles.fill", tint: .orange)
        }
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabSectionTitle("Details")
            LabeledContent("Status", value: session.isPublished ? "Published" : "Draft")
            if let creator = session.createdBy {
                LabeledContent("Scheduled by", value: creator.name)
            }
            LabeledContent("Session ID", value: String(session.id.prefix(8)))
        }
        .font(.subheadline)
        .deckCardStyle()
    }
}

private struct DeckActionTile: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
            Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(tint)
    }
}

private extension View {
    func deckCardStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Rounded only on the top corners — the week rail is anchored to the bottom edge.
struct UnevenTopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                              control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                              control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - Preview

struct DeckScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        DeckScheduleView()
    }
}
