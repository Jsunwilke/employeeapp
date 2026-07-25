//  Design5_Ambient.swift
//  Schedule Design Lab — Design 5: "Ambient"
//
//  Premise: most of the time you open the schedule with one question — what's
//  next, and when do I need to move? So the screen leads with a live countdown
//  to the next call time (or the time left in the shift you're standing in),
//  and everything else is layered underneath in glass. Colour comes from the
//  session itself, so the app looks different on a football Friday than on a
//  portrait Monday.
//
//  Detail: a stretching full-bleed hero with a floating glass action bar.

import SwiftUI

/// Ambient runs in one of two layouts, and the photographer picks. Both keep the
/// countdown and the glass; they differ in how the rest of the schedule is read.
///
/// - `day`: one day at a time, chosen from the capsule strip. Best on a shoot day.
/// - `timeline`: Agenda's continuous time-gutter scroll with pinned day headers,
///   rendered in Ambient's material. Best for planning a stretch of days — you
///   can see the run of the week without picking days one at a time.
enum AmbientLayout: String, CaseIterable, Identifiable {
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

struct AmbientScheduleView: View {
    @ObservedObject private var store = ScheduleLabStore.shared

    @State private var weekOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var pushed: Session?
    /// Sticky per photographer — pick once, it stays picked.
    @AppStorage("ambientScheduleLayout") private var layoutRaw = AmbientLayout.day.rawValue

    private var layout: AmbientLayout { AmbientLayout(rawValue: layoutRaw) ?? .day }
    private var week: [Date] { store.week(offset: weekOffset) }
    private var items: [ScheduleLabItem] { store.items(on: selectedDay) }

    /// The colour the whole screen takes: in Day layout the day you're looking at,
    /// in Timeline layout whatever is coming up next.
    private var ambientTint: Color {
        if layout == .day, let first = store.shifts(on: selectedDay).first {
            return ScheduleLabStyle.accent(for: first)
        }
        if let focus = focusSession { return ScheduleLabStyle.accent(for: focus) }
        if let next = store.nextShift() { return ScheduleLabStyle.accent(for: next) }
        return .indigo
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop(tint: ambientTint)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            if let focus = focusSession {
                                AmbientCountdownCard(session: focus, tint: ScheduleLabStyle.accent(for: focus))
                                    .padding(.horizontal, 18)
                                    .onTapGesture { pushed = focus }
                            }

                            layoutSwitch

                            switch layout {
                            case .day:
                                weekSelector
                                dayList
                            case .timeline:
                                AmbientTimeline(
                                    store: store,
                                    days: timelineDays,
                                    onSelect: { pushed = $0 }
                                )
                            }
                        }
                        .padding(.top, 6)
                        .padding(.bottom, 40)
                    }
                    .onAppear {
                        // Opening the timeline lands on today, not on the top of a
                        // week already worked. The list is built with today always
                        // present, so this anchor always exists.
                        anchorOnToday(proxy, animated: false)
                    }
                    .onChange(of: layoutRaw) { _ in
                        anchorOnToday(proxy, animated: true)
                    }
                }
            }
            .navigationTitle(layout == .day ? ScheduleLabStyle.relativeDayLabel(selectedDay) : "Schedule")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { LabModeMenu(store: store) }
            }
            .labPush(item: $pushed) { session in
                AmbientDetailView(session: session)
            }
        }
        .tint(ambientTint)
    }

    /// The timeline is centred on today: a week of recent history above it (so
    /// you can check what you already shot), today always present even when it's
    /// clear, then six weeks ahead. Empty days either side are dropped — blank
    /// rows are noise — but today never is, because it's the anchor.
    private var timelineDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let past = (1...7)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .filter { store.hasItems(on: $0) }
            .sorted()
        let future = (1...42)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .filter { store.hasItems(on: $0) }
        return past + [today] + future
    }

    private func anchorOnToday(_ proxy: ScrollViewProxy, animated: Bool) {
        guard layout == .timeline else { return }
        // One run-loop hop so the lazy stack has built its sections first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(LabAnim.gentle) { proxy.scrollTo(AmbientTimeline.anchorID, anchor: .top) }
            } else {
                proxy.scrollTo(AmbientTimeline.anchorID, anchor: .top)
            }
        }
    }

    private var layoutSwitch: some View {
        HStack(spacing: 4) {
            ForEach(AmbientLayout.allCases) { option in
                Button {
                    withAnimation(LabAnim.gentle) { layoutRaw = option.rawValue }
                    LabHaptics.selection()
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

    /// What the countdown is about: the shift in progress, else the next one on
    /// this day, else the next one anywhere.
    private var focusSession: Session? {
        let now = Date()
        let today = store.shifts(on: selectedDay)
        if let live = today.first(where: { session in
            guard let start = session.startDate, let end = session.endDate else { return false }
            return start <= now && now <= end
        }) { return live }
        if let upcoming = today.first(where: { ($0.startDate ?? .distantPast) > now }) { return upcoming }
        return today.first ?? store.nextShift()
    }

    // MARK: week selector

    private var weekSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(allSelectableDays, id: \.self) { date in
                        dayCapsule(date).id(date)
                    }
                }
                .padding(.horizontal, 18)
                .labScrollTargets()
            }
            .labCarousel(margin: 18)
            .onAppear {
                proxy.scrollTo(selectedDay, anchor: .center)
            }
            .onChange(of: selectedDay) { day in
                withAnimation(LabAnim.gentle) { proxy.scrollTo(day, anchor: .center) }
            }
        }
    }

    /// Three weeks of scrollable days — the week concept without a pager.
    private var allSelectableDays: [Date] {
        (-1...1).flatMap { store.week(offset: weekOffset + $0) }
    }

    private func dayCapsule(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDay)
        let isToday = Calendar.current.isDateInToday(date)
        let count = store.shifts(on: date).count

        return Button {
            withAnimation(LabAnim.snappy) {
                selectedDay = date
                weekOffset = store.weekOffset(containing: date)
            }
            LabHaptics.selection()
        } label: {
            VStack(spacing: 3) {
                Text(ScheduleLabStyle.weekdayShort.string(from: date).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.7)
                Text(ScheduleLabStyle.dayNumber.string(from: date))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Circle()
                    .fill(count > 0 ? Color.primary.opacity(isSelected ? 0.9 : 0.45) : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 52, height: 74)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.thickMaterial)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.65)
                }
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
                }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .labScrollFade(minOpacity: 0.55, minScale: 0.9)
    }

    // MARK: day list

    private var dayList: some View {
        LazyVStack(spacing: 14) {
            if items.isEmpty {
                LabEmptyDay(title: "Clear day", message: "Nothing scheduled.", systemImage: "moon.stars.fill")
                    .padding(.top, 20)
            }
            ForEach(items) { item in
                switch item {
                case .shift(let session):
                    Button { pushed = session } label: {
                        AmbientShiftRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .labScrollFade()
                case .timeOff(let entry):
                    AmbientTimeOffRow(entry: entry)
                        .labScrollFade()
                }
            }
        }
        .padding(.horizontal, 18)
    }
}

// MARK: - Timeline layout

/// Agenda's continuous time-gutter scroll, wearing Ambient's glass: pinned day
/// headers, a live spine down the left with each shift's start time on it, and
/// the same material cards the Day layout uses. One scroll reads a whole week.
private struct AmbientTimeline: View {
    @ObservedObject var store: ScheduleLabStore
    let days: [Date]
    let onSelect: (Session) -> Void

    /// Scroll target for today.
    static let anchorID = "ambient-timeline-anchor"

    /// Where a shift sits relative to right now. Drives every past/future cue in
    /// the timeline, so "done" and "coming" can never disagree between the day
    /// header and the rows under it.
    enum Standing {
        case past, live, upcoming

        static func of(_ session: Session, now: Date) -> Standing {
            guard let start = session.startDate else { return .upcoming }
            let end = session.endDate ?? start
            if now > end { return .past }
            if now >= start { return .live }
            return .upcoming
        }
    }

    private func standing(ofDay day: Date, now: Date) -> Standing {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return .live }
        return day < calendar.startOfDay(for: now) ? .past : .upcoming
    }

    var body: some View {
        // Re-evaluated each minute so a shift crosses from upcoming to live to
        // past while you're looking at it, without a manual refresh.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let startOfToday = Calendar.current.startOfDay(for: now)
            let past = days.filter { $0 < startOfToday }
            let ahead = days.filter { $0 >= startOfToday }

            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                // Everything already worked sits inside one flat grey band, edge
                // to edge — the colour drains out of the page above the NOW line,
                // so "behind me" is a property of the whole region, not something
                // you have to read off each row. Past headers aren't pinned;
                // there's nothing to keep track of back there.
                if !past.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(past, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 10) {
                                header(day, now: now)
                                dayBody(day, now: now)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(pastBand)
                    .padding(.bottom, 2)

                    todayDivider
                }

                ForEach(ahead, id: \.self) { day in
                    Section {
                        dayBody(day, now: now)
                    } header: {
                        header(day, now: now)
                            .id(Calendar.current.isDateInToday(day)
                                ? AmbientTimeline.anchorID
                                : "day-\(day.timeIntervalSince1970)")
                    }
                }
            }
        }
    }

    /// The grey zone behind finished days, with a hairline where it ends.
    private var pastBand: some View {
        Rectangle()
            .fill(Color(.systemGray5).opacity(0.5))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(.separator).opacity(0.6))
                    .frame(height: 0.5)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(.separator).opacity(0.6))
                    .frame(height: 0.5)
            }
    }

    private func dayBody(_ day: Date, now: Date) -> some View {
        VStack(spacing: 10) {
            let items = store.items(on: day)
            if items.isEmpty {
                clearDayRow
            }
            ForEach(items) { item in
                row(item, on: day, now: now)
            }
        }
        .padding(.horizontal, 18)
    }

    /// The boundary marker. Everything above it is behind you.
    private var todayDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.accentColor.opacity(0.6)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5)
            Text("NOW")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4)))
            Rectangle()
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.6), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    private var clearDayRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12, weight: .semibold))
            Text("No shifts")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: header

    private func header(_ day: Date, now: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let dayStanding = standing(ofDay: day, now: now)
        let isPast = dayStanding == .past
        let count = store.shifts(on: day).count

        return HStack(spacing: 8) {
            Text(ScheduleLabStyle.weekdayShort.string(from: day).uppercased())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
            Text(ScheduleLabStyle.dayNumber.string(from: day))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                // Past days are struck through — unmistakable at a glance, and it
                // survives greyscale, dark mode and colour-blindness where a
                // dimmer grey would not.
                .strikethrough(isPast, color: .secondary)
            Text(ScheduleLabStyle.monthYear.string(from: day).prefix(3))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if isToday {
                Text("TODAY")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            } else if isPast {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if count > 0 {
                Text(dayHoursLabel(day))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        // Flat grey inside the past band, glass everywhere else.
        .background(Capsule().fill(isPast
                                   ? AnyShapeStyle(Color(.systemBackground).opacity(0.5))
                                   : AnyShapeStyle(.regularMaterial)))
        .overlay(Capsule().strokeBorder(isToday
                                        ? Color.accentColor.opacity(0.45)
                                        : Color.primary.opacity(0.07),
                                        lineWidth: isToday ? 1.5 : 1))
        .grayscale(isPast ? 0.9 : 0)
        .opacity(isPast ? 0.8 : 1)
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
    }

    private func dayHoursLabel(_ day: Date) -> String {
        let seconds = store.shifts(on: day).reduce(0.0) { total, session in
            guard let start = session.startDate, let end = session.endDate, end > start else { return total }
            return total + end.timeIntervalSince(start)
        }
        guard seconds > 0 else { return "" }
        return ScheduleLabStyle.durationString(seconds)
    }

    // MARK: rows

    @ViewBuilder
    private func row(_ item: ScheduleLabItem, on day: Date, now: Date) -> some View {
        switch item {
        case .shift(let session):
            Button { onSelect(session) } label: {
                AmbientTimelineRow(session: session, standing: Standing.of(session, now: now))
            }
            .buttonStyle(.plain)
            .labScrollFade(minOpacity: 0.5)
        case .timeOff(let entry):
            AmbientTimelineTimeOffRow(entry: entry)
                .opacity(standing(ofDay: day, now: now) == .past ? 0.55 : 1)
                .labScrollFade(minOpacity: 0.5)
        }
    }
}

/// The gutter row: time on the left against a spine, glass card on the right.
/// Carries three states — done, happening now, still to come — each signalled
/// more than one way (weight, fill, strikethrough, a word) so it survives dark
/// mode, greyscale and colour-blindness instead of leaning on a dimmer grey.
private struct AmbientTimelineRow: View {
    let session: Session
    let standing: AmbientTimeline.Standing

    private var isPast: Bool { standing == .past }
    private var isLive: Bool { standing == .live }

    var body: some View {
        let accent = ScheduleLabStyle.accent(for: session)
        return HStack(alignment: .top, spacing: 10) {
            // Time gutter — the column your eye runs down.
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.startDate.map { ScheduleLabStyle.time.string(from: $0) } ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .strikethrough(isPast, color: .secondary)
                    .foregroundStyle(isPast ? Color.secondary : .primary)
                Text(ScheduleLabStyle.duration(session) ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let end = session.endDate {
                    Text(ScheduleLabStyle.time.string(from: end))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .frame(width: 58, alignment: .trailing)

            // Spine: solid node ahead, hollow node behind, ringed while live.
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isPast ? Color.clear : accent)
                        .overlay(Circle().strokeBorder(isPast ? Color.secondary : accent, lineWidth: 2))
                        .frame(width: 9, height: 9)
                    if isLive {
                        Circle()
                            .stroke(accent.opacity(0.35), lineWidth: 4)
                            .frame(width: 18, height: 18)
                    }
                }
                .padding(.top, 5)
                Rectangle()
                    .fill(isPast ? Color.secondary.opacity(0.18) : accent.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 9)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // One badge per discipline — a job that is underclass AND
                    // sports shows both, overlapped.
                    LabTypeIcons(session: session, size: 22)
                    Text(session.schoolName)
                        .font(.system(size: 16, weight: isPast ? .medium : .semibold))
                        .lineLimit(1)
                    if isLive {
                        Text("NOW")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(accent))
                            .foregroundStyle(.white)
                    } else if isPast {
                        Text("DONE")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.16)))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }

                LabTypePills(session: session)

                if !session.photographers.isEmpty {
                    HStack(spacing: 8) {
                        LabCrewStack(crew: session.photographers, size: 22, maxVisible: 4)
                        Text(session.photographers.map(\.name).joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Past cards are a FLAT grey, not glass: the material would let the
            // ambient colour wash through, which is exactly the signal we're
            // trying to remove from work that's already done.
            .background(cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(borderStyle, lineWidth: isLive ? 2 : 1)
            }
            .shadow(color: isLive ? accent.opacity(0.22) : .clear, radius: 14, y: 5)
            // Finished work drains to near-monochrome: still readable, no longer
            // competing with anything you still have to do.
            .grayscale(isPast ? 0.9 : 0)
            .opacity(isPast ? 0.75 : 1)
        }
    }

    private var cardFill: AnyShapeStyle {
        if isPast { return AnyShapeStyle(Color(.systemBackground).opacity(0.5)) }
        return isLive ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderStyle: AnyShapeStyle {
        if isLive { return AnyShapeStyle(ScheduleLabStyle.accent(for: session)) }
        if isPast { return AnyShapeStyle(Color.primary.opacity(0.07)) }
        return AnyShapeStyle(ScheduleLabStyle.accentGradient(for: session))
    }
}

private struct AmbientTimelineTimeOffRow: View {
    let entry: TimeOffCalendarEntry

    var body: some View {
        let tint = ScheduleLabStyle.accent(for: entry)
        return HStack(alignment: .top, spacing: 10) {
            Text(entry.isPartialDay ? entry.startTime : "All day")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
                .padding(.top, 4)

            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(tint, lineWidth: 2)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                Rectangle()
                    .fill(tint.opacity(0.2))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 9)

            HStack(spacing: 10) {
                Image(systemName: entry.reason.systemImageName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.reason.displayName).font(.system(size: 14, weight: .semibold))
                    Text(entry.photographerName).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                LabBadge(text: entry.status.displayName, tint: tint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(tint.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
    }
}

// MARK: - Backdrop

private struct AmbientBackdrop: View {
    let tint: Color

    var body: some View {
        ZStack {
            Color(.systemBackground)
            // Two soft washes rather than a single flat gradient — reads as light
            // in the room instead of a coloured rectangle.
            Circle()
                .fill(tint.opacity(0.55))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -110, y: -260)
            Circle()
                .fill(tint.opacity(0.28))
                .frame(width: 360, height: 360)
                .blur(radius: 140)
                .offset(x: 140, y: 120)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: tint)
    }
}

// MARK: - Countdown

private struct AmbientCountdownCard: View {
    let session: Session
    let tint: Color

    var body: some View {
        // Ticks every second so the countdown is genuinely live, not a snapshot
        // taken when the view happened to render.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = CountdownState(session: session, now: context.date)
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.18), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: state.progress)
                        .stroke(tint.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: state.progress)
                    Image(systemName: state.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.caption)
                        .font(.system(size: 11, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(state.value)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(session.schoolName) · \(ScheduleLabStyle.timeRange(session))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.18), radius: 18, y: 8)
        }
    }
}

/// The three honest states a shift can be in relative to now.
private struct CountdownState {
    let caption: String
    let value: String
    let symbol: String
    let progress: Double

    init(session: Session, now: Date) {
        guard let start = session.startDate else {
            caption = "Scheduled"
            value = "Time TBD"
            symbol = "questionmark"
            progress = 0
            return
        }
        let end = session.endDate ?? start

        if now < start {
            let remaining = start.timeIntervalSince(now)
            caption = "Starts in"
            value = CountdownState.clock(remaining)
            symbol = "hourglass"
            // Fills over the last 12 hours before call time.
            progress = max(0, min(1, 1 - remaining / (12 * 3600)))
        } else if now <= end {
            let elapsed = now.timeIntervalSince(start)
            let total = max(end.timeIntervalSince(start), 1)
            caption = "Time left"
            value = CountdownState.clock(end.timeIntervalSince(now))
            symbol = "camera.fill"
            progress = max(0, min(1, elapsed / total))
        } else {
            caption = "Finished"
            value = ScheduleLabStyle.time.string(from: end)
            symbol = "checkmark"
            progress = 1
        }
    }

    private static func clock(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        let days = total / 86_400
        if days >= 1 { return "\(days)d \((total % 86_400) / 3600)h" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, seconds) }
        return "\(seconds)s"
    }
}

// MARK: - Rows

private struct AmbientShiftRow: View {
    let session: Session

    var body: some View {
        let accent = ScheduleLabStyle.accent(for: session)
        return HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(session.startDate.map { ScheduleLabStyle.time.string(from: $0) } ?? "—")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Rectangle()
                    .fill(accent.opacity(0.35))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Text(session.endDate.map { ScheduleLabStyle.time.string(from: $0) } ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 58)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    LabTypeIcons(session: session, size: 24)
                    Text(session.schoolName)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                }
                LabTypePills(session: session)
                if !session.photographers.isEmpty {
                    LabCrewStack(crew: session.photographers, size: 24, maxVisible: 5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(ScheduleLabStyle.accentGradient(for: session), lineWidth: 1)
        }
    }
}

private struct AmbientTimeOffRow: View {
    let entry: TimeOffCalendarEntry

    var body: some View {
        let tint = ScheduleLabStyle.accent(for: entry)
        return HStack(spacing: 14) {
            Image(systemName: entry.reason.systemImageName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.reason.displayName).font(.system(size: 16, weight: .semibold))
                Text("\(entry.isPartialDay ? "\(entry.startTime)–\(entry.endTime)" : "All day") · \(entry.photographerName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LabBadge(text: entry.status.displayName, tint: tint)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Detail

struct AmbientDetailView: View {
    let session: Session
    @State private var selectedDayID: String?

    private var accent: Color { ScheduleLabStyle.accent(for: session) }
    private var activeDay: SessionDay? {
        if let selectedDayID, let day = session.days.first(where: { $0.id == selectedDayID }) { return day }
        return session.day(onDate: session.date)
    }
    private var shown: Session { activeDay.map { session.with(day: $0) } ?? session }

    var body: some View {
        ZStack(alignment: .bottom) {
            AmbientBackdrop(tint: accent)

            ScrollView {
                VStack(spacing: 18) {
                    hero
                    facts
                    if session.dayCount > 1 { daySwitcher }
                    crew
                    notes
                    staffing
                    Spacer(minLength: 96)
                }
                .padding(.horizontal, 18)
            }

            actionBar
        }
        .navigationTitle(session.schoolName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedDayID = session.day(onDate: session.date)?.id }
        .tint(accent)
    }

    /// The hero carries the session's identity, not just its clock: the title,
    /// every discipline it covers, and then when it runs. Height follows the
    /// content so a three-type job doesn't get clipped.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // Multi-type jobs get a blended wash instead of one flat colour.
            LinearGradient(colors: heroColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: ScheduleLabStyle.symbol(for: session))
                .font(.system(size: 120, weight: .semibold))
                .foregroundStyle(.white.opacity(0.14))
                .offset(x: 30, y: 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            VStack(alignment: .leading, spacing: 10) {
                Text(session.schoolName.isEmpty ? "Session" : session.schoolName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)

                // Every session type, on white-on-colour chips that stay legible
                // over the wash. Wraps rather than truncating.
                LabFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(session.sessionType, id: \.self) { type in
                        HStack(spacing: 5) {
                            Image(systemName: ScheduleLabStyle.typeSymbol(type, in: session))
                                .font(.system(size: 10, weight: .bold))
                            Text(ScheduleLabStyle.typeName(type, in: session))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.24)))
                    }
                    if let label = session.multiDayLabel {
                        Text(label)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.22)))
                    }
                    if !session.isPublished {
                        Text("DRAFT")
                            .font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.3)))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(shown.startDate.map { ScheduleLabStyle.longDate.string(from: $0) } ?? "")
                        .font(.caption.weight(.semibold))
                        .opacity(0.85)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ScheduleLabStyle.timeRange(shown))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        if let duration = ScheduleLabStyle.duration(shown) {
                            Text(duration)
                                .font(.subheadline.weight(.semibold))
                                .opacity(0.9)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 200)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .labParallax(0.35)
        .shadow(color: accent.opacity(0.3), radius: 20, y: 10)
        .padding(.top, 6)
    }

    /// Two type colours blend; one type keeps its own light-to-dark wash.
    private var heroColors: [Color] {
        let colors = ScheduleLabStyle.typeColors(for: session)
        return colors.count > 1 ? colors : [accent, accent.opacity(0.55)]
    }

    private var facts: some View {
        HStack(spacing: 10) {
            LabStatTile(value: shown.photographers.count, label: "On crew", systemImage: "person.2.fill", tint: accent)
            LabStatTile(value: session.dayCount, label: "Days", systemImage: "calendar", tint: accent)
            LabStatTile(value: session.photographersNeeded + session.posersNeeded + session.helpersNeeded,
                        label: "Needed", systemImage: "person.badge.plus", tint: accent)
        }
    }

    private var daySwitcher: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabSectionTitle("Pick a day")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(session.sortedDays.enumerated()), id: \.element.id) { index, day in
                        let isActive = day.id == activeDay?.id
                        Button {
                            withAnimation(LabAnim.snappy) { selectedDayID = day.id }
                            LabHaptics.selection()
                        } label: {
                            VStack(spacing: 2) {
                                Text("DAY \(index + 1)")
                                    .font(.system(size: 9, weight: .heavy))
                                Text(dayLabel(day))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(isActive ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial),
                                        in: Capsule())
                            .foregroundStyle(isActive ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func dayLabel(_ day: SessionDay) -> String {
        guard let date = Session.parseDateTime(date: day.date, time: "00:00") else { return day.date }
        return ScheduleLabStyle.monthDay.string(from: date)
    }

    private var crew: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabSectionTitle("Crew", trailing: "\(shown.photographers.count)")
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
            if shown.photographers.isEmpty {
                Text("Nobody assigned to this day yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var notes: some View {
        if let dayNotes = activeDay?.day_notes, !dayNotes.isEmpty {
            AmbientNote(title: "This day", text: dayNotes, tint: accent)
        }
        if let sessionNotes = session.notes, !sessionNotes.isEmpty {
            AmbientNote(title: "Session notes", text: sessionNotes, tint: .secondary)
        }
    }

    private var staffing: some View {
        HStack(spacing: 10) {
            LabStatTile(value: session.photographersNeeded, label: "Photographers", systemImage: "camera.fill", tint: .blue)
            LabStatTile(value: session.posersNeeded, label: "Posers", systemImage: "person.fill", tint: .green)
            LabStatTile(value: session.helpersNeeded, label: "Helpers", systemImage: "hands.sparkles.fill", tint: .orange)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if let url = LabActions.directionsURL(for: session) {
                Link(destination: url) {
                    Label("Directions", systemImage: "car.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(accent, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            ShareLink(item: LabActions.shareText(for: shown)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 48, height: 46)
                    .background(.thinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(UnevenTopRoundedRectangle(radius: 24))
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct AmbientNote: View {
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabSectionTitle(title)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 16)
                .padding(.leading, 1)
        }
    }
}

// MARK: - Preview

struct AmbientScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        AmbientScheduleView()
    }
}
