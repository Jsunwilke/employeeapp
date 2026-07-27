//  ScheduleRows.swift
//  Iconik Employee — the schedule's rows and timeline
//
//  Split out of ScheduleView so the screen file stays about data and state, and
//  this one is only about how a shift reads. Both layouts share the same three
//  states — done, happening now, still to come — signalled several ways at once
//  (weight, fill, strikethrough, a word) so they survive dark mode, greyscale
//  and colour-blindness rather than leaning on a dimmer grey.

import SwiftUI

// MARK: - Countdown

/// The screen's opening line: how long until the next call time, or how much of
/// the current shift is left. Ticks every second, so it's genuinely live.
struct ScheduleCountdownCard: View {
    let session: Session
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = CountdownState(session: session, now: context.date)
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(tint.opacity(0.18), lineWidth: 7)
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
                    Text("\(session.schoolName) · \(ScheduleStyle.timeRange(session))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .ambientCard(density: .hero,
                         state: .highlighted,
                         border: .hairline(tint.opacity(0.25)),
                         glow: tint)
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
            caption = "Scheduled"; value = "Time TBD"; symbol = "questionmark"; progress = 0
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
            value = Formatters.shortTime.string(from: end)
            symbol = "checkmark"
            progress = 1
        }
    }

    private static func clock(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        let days = total / 86_400
        if days >= 1 { return "\(days)d \((total % 86_400) / 3600)h" }
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, seconds) }
        return "\(seconds)s"
    }
}

// MARK: - Day layout row

struct ScheduleShiftRow: View {
    let session: Session
    var standing: ShiftStanding = .upcoming

    /// A draft is never drawn as finished — no strikethrough, no receded card.
    /// "Done" is a false statement about work nobody was ever given, and a draft
    /// dated in the past is far more likely to be a plan that slipped than a job
    /// that happened.
    private var isPast: Bool { standing == .past && session.isPublished }
    /// A draft is never drawn as "happening now" either. It is provisional work,
    /// and the loud live treatment would say the opposite.
    private var isLive: Bool { standing == .live && session.isPublished }
    private var isDraft: Bool { !session.isPublished }

    var body: some View {
        let accent = ScheduleStyle.accent(for: session)
        return HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(session.startDate.map { Formatters.shortTime.string(from: $0) } ?? "—")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .strikethrough(isPast, color: .secondary)
                Rectangle()
                    .fill(accent.opacity(0.35))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Text(session.endDate.map { Formatters.shortTime.string(from: $0) } ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 58)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    ScheduleTypeIcons(session: session, size: 24)
                    Text(session.schoolName)
                        .font(.system(size: 17, weight: isPast ? .medium : .semibold))
                        .lineLimit(1)
                    if isLive {
                        Text("NOW")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(accent))
                            .foregroundStyle(.white)
                    }
                }
                ScheduleTypePills(session: session)
                if !session.photographers.isEmpty {
                    AmbientAvatarStack(subjects: ScheduleStyle.avatarSubjects(session.photographers), size: 24, maxVisible: 5)
                }
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .roomy,
                     state: isDraft ? .normal : standing.cardState,
                     border: draftAwareBorder(accent: accent))
    }

    /// A draft carries the dashed edge the design system reserves for a card that
    /// is not the same KIND of thing as the ones around it. That is exactly what
    /// a draft is among announced shifts, and it reads before any label does.
    private func draftAwareBorder(accent: Color) -> AmbientCardBorder {
        if isDraft { return .dashed(accent.opacity(0.55)) }
        if isLive { return .strong(AnyShapeStyle(accent)) }
        return .hairline(AnyShapeStyle(ScheduleStyle.accentGradient(for: session)))
    }
}

// MARK: - Draft group heading

/// The heading that separates unpublished work from announced shifts (PUB.1 / P6).
/// Drafts are never interleaved with real shifts — they sit under this, in both
/// layouts, so "what is coming" and "what I have been given" are never read as
/// the same thing.
struct ScheduleDraftHeading: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 11, weight: .bold))
                Text("Not published yet")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                Spacer()
                Text("\(count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)

            Text("Planned work — it can still change, and it hasn't been announced to anyone yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ScheduleTimeOffRow: View {
    let entry: TimeOffCalendarEntry

    private var scheduleTimeLabel: String {
        guard entry.isPartialDay else { return "All day" }
        // Not "All day" — a partial day with unreadable times is not a whole day.
        guard let start = TimeOfDay(entry.startTime),
              let end = TimeOfDay(entry.endTime) else { return "Time not set" }
        return "\(start.displayString)–\(end.displayString)"
    }

    var body: some View {
        let tint = ScheduleStyle.accent(for: entry)
        return HStack(spacing: 14) {
            Image(systemName: entry.reason.systemImageName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.reason.displayName).font(.system(size: 16, weight: .semibold))
                // The times are stored as "09:00" and were printed RAW here, so a
                // 12-hour-locale photographer read "13:00–17:00" on their own
                // schedule. Formatted through TimeOfDay like everywhere else.
                Text("\(scheduleTimeLabel) · \(entry.photographerName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // THE BADGE TAKES THE STATUS COLOUR, NOT THE SCHEDULE'S ACCENT.
            // `ScheduleStyle.accent(for:)` deliberately maps by status AND
            // partial-day — it makes approved ORANGE when partial and GREY when
            // not — which is a useful signal for the ROW, and a wrong one for a
            // badge that names a status. Feeding it to both meant an approved
            // full-day request wore a grey "Approved" badge here and a green one
            // on every other screen. The card's dashed border keeps the schedule's
            // accent, because that IS the calendar signal (AMB.1's language for
            // "not the same kind of thing as a shift").
            AmbientBadge(text: TimeOffStatusDisplay.from(raw: entry.statusRaw).label,
                         tint: TimeOffStatusDisplay.from(raw: entry.statusRaw).color)
        }
        .ambientCard(density: .roomy, border: .dashed(tint.opacity(0.3)))
    }
}

// MARK: - Timeline

/// A continuous scroll anchored on today. Days already worked sit inside one
/// flat grey band that ends at the NOW line, so "behind me" is a property of the
/// region rather than something you read off each row.
struct ScheduleTimeline: View {
    let days: [Date]
    let items: (Date) -> [ScheduleItem]
    /// A day's unpublished work, asked for separately because it is drawn as its
    /// own group under the day's announced shifts rather than mixed into them.
    let drafts: (Date) -> [Session]
    let hours: (Date) -> TimeInterval
    let onSelectShift: (Session) -> Void
    let onSelectTimeOff: (TimeOffCalendarEntry) -> Void

    static let anchorID = "schedule-timeline-today"

    var body: some View {
        // Re-evaluated each minute, so a shift crosses from upcoming to live to
        // done while you're looking at it.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let startOfToday = Calendar.current.startOfDay(for: now)
            let past = days.filter { $0 < startOfToday }
            let ahead = days.filter { $0 >= startOfToday }

            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                if !past.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(past, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 10) {
                                header(day, now: now)
                                body(for: day, now: now)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(pastBand)
                    .padding(.bottom, 2)

                    nowDivider
                }

                ForEach(ahead, id: \.self) { day in
                    Section {
                        body(for: day, now: now)
                    } header: {
                        // The divider above already says TODAY. Only label the
                        // header too when there's no history, so the marker is
                        // never missing and never doubled.
                        header(day, now: now, showTodayChip: past.isEmpty)
                            .id(Calendar.current.isDateInToday(day)
                                ? ScheduleTimeline.anchorID
                                : "day-\(day.timeIntervalSince1970)")
                    }
                }
            }
        }
    }

    // MARK: pieces

    private var pastBand: some View {
        Rectangle()
            .fill(Color(.systemGray5).opacity(0.5))
            .overlay(alignment: .top) { hairline }
            .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle().fill(Color(.separator).opacity(0.6)).frame(height: 0.5)
    }

    /// The line between what's done and what's ahead. Deliberately the loudest
    /// horizontal element in the timeline — it's the one landmark you scroll to
    /// find, so it has to be findable at a glance while flicking.
    private var nowDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.accentColor],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 3)
            Text("TODAY")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .kerning(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Capsule().fill(Color.accentColor))
                .shadow(color: Color.accentColor.opacity(0.35), radius: 8, y: 3)
            Rectangle()
                .fill(LinearGradient(colors: [Color.accentColor, .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 3)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func header(_ day: Date, now: Date, showTodayChip: Bool = false) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let isPast = day < Calendar.current.startOfDay(for: now)
        let dayHours = hours(day)

        return HStack(spacing: 8) {
            Text(Formatters.weekdayShort.string(from: day).uppercased())
                .font(.system(size: isToday ? 13 : 12, weight: .heavy))
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
            Text(Formatters.dayNumber.string(from: day))
                .font(.system(size: isToday ? 23 : 19, weight: .bold, design: .rounded))
                .strikethrough(isPast, color: .secondary)
            Text(Formatters.monthYear.string(from: day).prefix(3))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if isToday && showTodayChip {
                Text("TODAY")
                    .font(.system(size: 10, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            } else if isPast {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if dayHours > 0 {
                Text(Formatters.duration(dayHours))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        // Today's header is tinted and outlined, not just materialised — it has
        // to stay findable after you've scrolled past the divider.
        .background(Capsule().fill(headerFill(isPast: isPast, isToday: isToday)))
        .overlay(Capsule().strokeBorder(isToday ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.07),
                                        lineWidth: isToday ? 2 : 1))
        .shadow(color: isToday ? Color.accentColor.opacity(0.2) : .clear, radius: 8, y: 3)
        .grayscale(isPast ? 0.9 : 0)
        .opacity(isPast ? 0.8 : 1)
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
    }

    private func headerFill(isPast: Bool, isToday: Bool) -> AnyShapeStyle {
        if isPast { return AnyShapeStyle(Color(.systemBackground).opacity(0.5)) }
        if isToday { return AnyShapeStyle(Color.accentColor.opacity(0.14)) }
        return AnyShapeStyle(.regularMaterial)
    }

    private func body(for day: Date, now: Date) -> some View {
        VStack(spacing: 10) {
            let dayItems = items(day)
            let dayDrafts = drafts(day)
            if dayItems.isEmpty && dayDrafts.isEmpty { clearDayRow }
            ForEach(dayItems) { item in
                switch item {
                case .shift(let session):
                    Button { onSelectShift(session) } label: {
                        ScheduleTimelineRow(session: session, standing: ShiftStanding.of(session, now: now))
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade(minOpacity: 0.5)
                case .timeOff(let entry):
                    Button { onSelectTimeOff(entry) } label: {
                        ScheduleTimeOffRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .opacity(day < Calendar.current.startOfDay(for: now) ? 0.55 : 1)
                    .ambientScrollFade(minOpacity: 0.5)
                }
            }

            if !dayDrafts.isEmpty {
                ScheduleDraftHeading(count: dayDrafts.count)
                    // Indented to clear the time gutter and the spine, so the
                    // heading lines up with the cards it introduces rather than
                    // with the clock.
                    .padding(.leading, 77)
                    .padding(.top, dayItems.isEmpty ? 0 : 4)
                ForEach(dayDrafts, id: \.dayOccurrenceKey) { session in
                    Button { onSelectShift(session) } label: {
                        ScheduleTimelineRow(session: session, standing: ShiftStanding.of(session, now: now))
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade(minOpacity: 0.5)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private var clearDayRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.system(size: 12, weight: .semibold))
            Text("No shifts").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .ambientCard(density: .compact, fillWidth: true)
    }
}

// MARK: - Timeline row

/// Time gutter on the left against a spine, card on the right.
struct ScheduleTimelineRow: View {
    let session: Session
    let standing: ShiftStanding

    /// The same rule the day row applies, so one draft cannot read as provisional
    /// in Day view and as a struck-through "DONE" job in Timeline.
    private var isPast: Bool { standing == .past && session.isPublished }
    /// As in the day row: unpublished work is never drawn as "happening now".
    private var isLive: Bool { standing == .live && session.isPublished }
    private var isDraft: Bool { !session.isPublished }

    var body: some View {
        let accent = ScheduleStyle.accent(for: session)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.startDate.map { Formatters.shortTime.string(from: $0) } ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .strikethrough(isPast, color: .secondary)
                    .foregroundStyle(isPast ? Color.secondary : .primary)
                Text(ScheduleStyle.duration(session) ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let end = session.endDate {
                    Text(Formatters.shortTime.string(from: end))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .frame(width: 58, alignment: .trailing)

            // Solid node ahead, hollow behind, ringed while live.
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isPast ? Color.clear : accent)
                        .overlay(Circle().strokeBorder(isPast ? Color.secondary : accent, lineWidth: 2))
                        .frame(width: 9, height: 9)
                    if isLive {
                        Circle().stroke(accent.opacity(0.35), lineWidth: 4).frame(width: 18, height: 18)
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
                    ScheduleTypeIcons(session: session, size: 22)
                    Text(session.schoolName)
                        .font(.system(size: 16, weight: isPast ? .medium : .semibold))
                        .lineLimit(1)
                    if isLive {
                        Text("NOW")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(accent))
                            .foregroundStyle(.white)
                    } else if isPast {
                        Text("DONE")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.16)))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ScheduleTypePills(session: session)

                    if !session.photographers.isEmpty {
                        HStack(spacing: 8) {
                            AmbientAvatarStack(subjects: ScheduleStyle.avatarSubjects(session.photographers), size: 22, maxVisible: 4)
                            Text(session.photographers.map(\.name).joined(separator: ", "))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                // Desaturating only the coloured content keeps the offscreen
                // pass small; the card's material and shadow stay untouched.
                .grayscale(isPast ? 0.9 : 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            // ambient-allow: ScheduleTimelineRow deliberately stays hand-rolled.
            // Flat fill when past — the material would let the ambient colour
            // wash through, which is the signal we're removing from finished
            // work — and only the coloured CONTENT is desaturated, because the
            // timeline is a long lazy list and a whole-card greyscale pass per
            // row costs real frames (measured in AMB.1). .ambientCard has no
            // third fill state, and adding one for a single caller would be
            // designing the system around its exception.
            .background(cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { edge }
            // ambient-allow: ScheduleTimelineRow deliberately stays hand-rolled.
            // A past row here takes a FLAT fill rather than a desaturated
            // material, and desaturates only its coloured content, because the
            // timeline is a long lazy list and a whole-card greyscale pass per
            // row costs real frames (measured in AMB.1). Folding it into
            // .ambientCard would undo that.
            .shadow(color: isLive ? accent.opacity(0.22) : .clear, radius: 14, y: 5)
            .opacity(isPast ? 0.75 : 1)
        }
    }

    private var cardFill: AnyShapeStyle {
        if isPast { return AnyShapeStyle(Color(.systemBackground).opacity(0.5)) }
        return isLive ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial)
    }

    /// The same dashed edge the day row gives a draft, drawn by hand because this
    /// row is deliberately outside `.ambientCard` (see the note on its background).
    @ViewBuilder
    private var edge: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if isDraft {
            shape.strokeBorder(borderStyle, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        } else {
            shape.strokeBorder(borderStyle, lineWidth: isLive ? 2 : 1)
        }
    }

    private var borderStyle: AnyShapeStyle {
        if isDraft { return AnyShapeStyle(ScheduleStyle.accent(for: session).opacity(0.55)) }
        if isLive { return AnyShapeStyle(ScheduleStyle.accent(for: session)) }
        if isPast { return AnyShapeStyle(Color.primary.opacity(0.07)) }
        return AnyShapeStyle(ScheduleStyle.accentGradient(for: session))
    }
}
