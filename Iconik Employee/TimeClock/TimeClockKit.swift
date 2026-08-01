//  TimeClockKit.swift
//  Iconik Employee — the time clock design, as production code
//
//  PRODUCTION CODE THAT THE LAB MOCKUP IMPORTS. That direction is the whole
//  mechanism, and it is the answer to the operator's question at AMB.7 — "how
//  will you ensure it creates these exactly as we have designed instead of just
//  using them as inspiration?" The mockup draws with these types and so do the
//  real screens, so converting is swapping sample data for a service rather than
//  re-implementing a picture. There is no second copy to drift from.
//
//  The rules these views quote live next door in `TimeClockRules.swift`, which
//  is SwiftUI-free and is compiled and RUN by `scripts/test_timeclock_rules.sh`.
//  Nothing in this file decides what is allowed; it only says so.
//
//  WHAT THE DESIGN CLAIMS, in the order the operator will see them:
//
//    1. THE CLOCK IS THE SCREEN. Today the running shift is a line of 17-point
//       text in a grey box, and the thing that dominates is a segmented control
//       for a date range. A photographer opens this screen to answer one
//       question — am I on the clock, and since when — so that answer is the
//       hero card and everything else is below it.
//
//    2. A RUNNING SHIFT IS OBVIOUS FROM ACROSS A ROOM, and obvious in more than
//       one way at once: the card is `.highlighted` (a heavier material), it
//       carries a live green badge, it glows, and the elapsed figure is set in
//       rounded monospaced digits at 40pt. That is the schedule's "done / now /
//       still to come" rule applied to the only state this screen has.
//
//    3. A LOCKED ROW SAYS WHY. The 30-day edit window is real, it is enforced on
//       every write, and the only sentence in the entire app that explained it
//       lived on `TimeEntryDetailView` — a screen with zero call sites that no
//       photographer has ever opened. The explanation moves onto the row.
//
//    4. A FAILURE IS NOT AN EMPTY STATE. Two payroll screens drew a failed fetch
//       as "no entries" and "no sessions" — payroll appearing to be zero, and an
//       invitation to clock in unattributed. `AmbientFailureCard` exists for
//       this and both screens get it.
//
//    5. YOU SEE WHAT YOU ARE ABOUT TO RECORD. Every form that writes payroll
//       gets the same summary card: start, end, duration, and the refusal if
//       there is one — quoting `TimeClockRules`, so the form and the write can
//       no longer disagree about the ceiling.

import SwiftUI

// MARK: - Identity

enum TimeClockStyle {
    /// The feature's ACCENT (D11), read from `FeatureTheme` rather than restated
    /// so the tile you tap and the screen you land on cannot disagree. It does
    /// not reach the background: D14 gives every screen the one app wash.
    ///
    /// Time tracking, time off and approvals are adjacent teals — they read as a
    /// family without reading as identical.
    static var accent: Color { FeatureTheme.color(for: "timeTracking") }

    /// Running. Green everywhere on this surface, and it is the ONLY green here,
    /// so green means "on the clock" and nothing else.
    static let running = Color.green

    /// A shift that has been running past the long-shift threshold. Amber rather
    /// than red: nothing is wrong yet, but it wants a decision.
    static let overrun = Color.orange
}

// MARK: - What the clock is doing

/// The clock's state, as one value rather than as `isClockIn` plus four
/// optionals read separately by each view.
enum TimeClockStatus: Equatable {
    case stopped
    /// A shift in progress. `since` is the start; `elapsed` is supplied by the
    /// caller's ticker rather than computed here, because a view that computes
    /// `Date()` in its own body never redraws — the bug that froze the shipped
    /// "Time Elapsed" preview and the >24h warning glyph.
    case running(since: Date, elapsed: TimeInterval)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// What the running shift is attached to. Both are optional, and both being nil
/// is a normal, supported clock-in.
struct TimeClockAttachment: Equatable {
    var sessionName: String?
    var notes: String?

    init(sessionName: String? = nil, notes: String? = nil) {
        self.sessionName = sessionName
        self.notes = notes
    }

    var isEmpty: Bool {
        (sessionName?.isEmpty ?? true) && (notes?.isEmpty ?? true)
    }
}

// MARK: - The hero

/// The clock, as the one thing on the screen.
///
/// SIGNALLED SEVERAL WAYS AT ONCE, which is the schedule's rule and the reason
/// its states survive dark mode and greyscale: material weight, a border, a
/// glow, a badge, and the size of the number itself all change together. A
/// single green dot would not survive a photographer glancing at a phone in
/// direct sun on a football field, which is where this screen is actually used.
struct TimeClockHeroCard: View {
    let status: TimeClockStatus
    var attachment = TimeClockAttachment()
    /// True past `TimeClockLimits.longShiftThreshold`. Passed in rather than
    /// derived, for the same redraw reason as `elapsed`.
    var isLongShift = false
    /// Offline writes queue rather than fail, and the shipped screens never said
    /// so — a queued clock-in looked identical to a landed one.
    var isOffline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch status {
            case .running(let since, let elapsed):
                runningBody(since: since, elapsed: elapsed)
            case .stopped:
                stoppedBody
            }

            if !attachment.isEmpty { attachmentBlock }
        }
        .ambientCard(density: .hero,
                     state: status.isRunning ? .highlighted : .normal,
                     border: status.isRunning
                        ? .strong(stateTint.opacity(0.55))
                        : .hairline(Color.primary.opacity(0.10)),
                     glow: status.isRunning ? stateTint : nil,
                     fillWidth: true)
    }

    /// Amber wins over green when the shift has overrun — it is the state that
    /// needs a decision, and two "everything is fine" greens would hide it.
    private var stateTint: Color {
        guard status.isRunning else { return TimeClockStyle.accent }
        return isLongShift ? TimeClockStyle.overrun : TimeClockStyle.running
    }

    private var header: some View {
        HStack(spacing: 8) {
            AmbientBadge(text: status.isRunning ? "On the clock" : "Clocked out",
                         systemImage: status.isRunning ? "record.circle" : "pause.circle",
                         tint: status.isRunning ? stateTint : .secondary)
            if isOffline {
                AmbientBadge(text: "Queued", systemImage: "icloud.slash", tint: .orange)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func runningBody(since: Date, elapsed: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TimeClockFormat.elapsed(elapsed))
                // Monospaced digits, or the whole line shivers once a second as
                // the glyph widths change. Rounded to match the app's numerals.
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .accessibilityLabel("Clocked in for \(accessibleElapsed(elapsed))")

            Text("Since \(Formatters.shortTime.string(from: since))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        if isLongShift {
            // THIS USED TO BE A CAPTION-SIZED ⚠️ INSIDE THE CLOCK OUT BUTTON,
            // which is both the least legible place on the screen for it and a
            // place it could only be seen after you had decided to leave. It
            // also never updated on its own — it read `Date()` in a computed
            // body with nothing driving a redraw.
            Label("Running over 24 hours — set a clock-out time when you stop",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TimeClockStyle.overrun)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stoppedBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Ready to start")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("Clock in to begin recording hours")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var attachmentBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider().opacity(0.5)
            if let name = attachment.sessionName, !name.isEmpty {
                Label(name, systemImage: "calendar")
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let notes = attachment.notes, !notes.isEmpty {
                Label(notes, systemImage: "note.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// VoiceOver reads "07:18:42" as a time of day, which on a stopwatch is
    /// nonsense. Spelled out instead.
    private func accessibleElapsed(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes) minutes" }
        return "\(hours) hours \(minutes) minutes"
    }
}

// MARK: - Totals

/// Hours and entry count for whatever range is showing.
///
/// It reads as ONE claim rather than two stat tiles, because the count is only
/// there to make the hours believable — "31h 42m across 6 entries" is a sentence
/// a photographer can check against their week; two numbers in two boxes are not.
struct TimeClockTotalsCard: View {
    let totalSeconds: TimeInterval
    let entryCount: Int
    let rangeLabel: String
    /// True when the list hit its 100-row ceiling, in which case the total below
    /// it is NOT the range's total. See AMB13_CLOCK_PARITY.md §7 — the fetch cap
    /// is a data bug this phase does not fix, but a payroll figure that is
    /// silently short is not something to draw as if it were complete.
    var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TimeClockFormat.hoursAndMinutes(totalSeconds))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(rangeLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(entryCount == 1 ? "1 entry" : "\(entryCount) entries")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if isTruncated {
                Label("Showing the most recent 100 entries — this total is incomplete",
                      systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TimeClockStyle.overrun)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ambientCard(density: .roomy,
                     border: .hairline(Color.primary.opacity(0.10)),
                     fillWidth: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TimeClockFormat.hoursAndMinutes(totalSeconds)) \(rangeLabel), \(entryCount) entries")
    }
}

// MARK: - An entry, in a list

/// What kind of entry a row is — and this enum is DELIBERATELY SHORTER than the
/// one the app used to imply.
///
/// THE OLD THREE-WAY SPLIT WAS NOT REAL, and the mockup carried it before this
/// was checked against the schema. `TimeEntryDetailView` (the dead screen) named
/// three kinds — "Active Clock Entry", "Manual Time Entry", "Clock-based Entry"
/// — and `TimeEntryRow` drew three glyphs for them. The test both used was
/// `clockInTime != nil && clockOutTime != nil && status != "clocked-in"`, which
/// is TRUE OF EVERY COMPLETED ENTRY. So the "manual" pencil showed on every
/// finished shift, and the "clock-based" glyph was reachable only by an entry
/// MISSING A TIME — the exact opposite of what its label claimed.
///
/// `time_entries` has no column that records how a row was created
/// (`DATABASE_SCHEMA.md`), and `createManualTimeEntry` writes the same
/// `status: "clocked-out"` a real clock-out does. The app cannot tell the two
/// apart, so it must not claim to. Shipping a badge reading "Manual" on a shift
/// somebody actually clocked would be a confident wrong answer about payroll.
///
/// What IS knowable from the row is kept, including the case the old test
/// mislabelled: an entry that is not running and has no end time is a shift
/// whose clock-out never landed — which the service can genuinely produce, since
/// a queued offline clock-out whose row has gone is logged and dropped
/// (`TimeTrackingService.swift:212-218`). That is worth surfacing, not hiding.
enum TimeClockEntryKind: Equatable {
    /// Clocked in right now.
    case running
    /// A finished shift. How it came to exist is not recorded anywhere.
    case recorded
    /// Not running, but missing a start or an end — the clock-out never landed.
    case incomplete

    /// Nil for `.recorded`: a badge on every single row is noise, and there is
    /// nothing to say about an ordinary finished shift that the times do not
    /// already say.
    var label: String? {
        switch self {
        case .running: return "Active"
        case .recorded: return nil
        case .incomplete: return "Incomplete"
        }
    }

    var symbol: String? {
        switch self {
        case .running: return "record.circle"
        case .recorded: return nil
        case .incomplete: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .running: return TimeClockStyle.running
        case .recorded: return .secondary
        case .incomplete: return TimeClockStyle.overrun
        }
    }
}

/// Everything a row draws, as plain values — so the lab feeds it samples and
/// production feeds it a `TimeEntry`, and neither owns the other.
struct TimeClockEntryDisplay: Identifiable, Equatable {
    let id: String
    /// "Today", "Yesterday", "Mar 4" — the shipped relative rule.
    let dayLabel: String
    /// "9:00 AM – 5:30 PM", or "9:00 AM – Present" while running.
    let timeRange: String
    let durationText: String
    let kind: TimeClockEntryKind
    var sessionName: String?
    var notes: String?
    /// Nil when the entry cannot be edited. When set, it is the number of whole
    /// days left in the 30-day window.
    var editDaysRemaining: Int?

    var isEditable: Bool { kind == .running || editDaysRemaining != nil }

    init(id: String,
         dayLabel: String,
         timeRange: String,
         durationText: String,
         kind: TimeClockEntryKind,
         sessionName: String? = nil,
         notes: String? = nil,
         editDaysRemaining: Int? = nil) {
        self.id = id
        self.dayLabel = dayLabel
        self.timeRange = timeRange
        self.durationText = durationText
        self.kind = kind
        self.sessionName = sessionName
        self.notes = notes
        self.editDaysRemaining = editDaysRemaining
    }
}

/// One row in the entry list.
///
/// COMPACT (D5, settled at AMB.2 and proven at AMB.3): a pay period is a list
/// you scan for the one wrong day, not a list you read.
struct TimeClockEntryRow: View {
    let entry: TimeClockEntryDisplay
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.dayLabel)
                        .font(AmbientDensity.compact.titleFont)
                    Spacer(minLength: 4)
                    Text(entry.durationText)
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(entry.kind == .running
                                         ? TimeClockStyle.running
                                         : TimeClockStyle.accent)
                }

                HStack(spacing: 6) {
                    Text(entry.timeRange)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let label = entry.kind.label {
                        AmbientBadge(text: label,
                                     systemImage: entry.kind.symbol,
                                     tint: entry.kind.tint)
                    }
                    if !entry.isEditable {
                        AmbientBadge(text: "Locked", systemImage: "lock.fill", tint: .secondary)
                    }
                }

                if let session = entry.sessionName, !session.isEmpty {
                    Label(session, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let notes = entry.notes, !notes.isEmpty {
                    Label(notes, systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .ambientCard(density: .compact,
                         state: entry.isEditable ? .normal : .receded,
                         border: entry.kind == .running
                            ? .strong(TimeClockStyle.running.opacity(0.5))
                            : .hairline(Color.primary.opacity(0.08)),
                         fillWidth: true)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [entry.dayLabel, entry.durationText, entry.timeRange]
        if let label = entry.kind.label { parts.append(label) }
        if !entry.isEditable { parts.append("locked, outside the edit window") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Why a row is locked

/// The sentence that only ever existed on a dead screen.
///
/// `TimeEntryDetailView:36-44` is the only place in the app that has ever
/// explained the 30-day window to a photographer, and it has zero call sites. It
/// is shown here on the row's own edit form, where the question actually gets
/// asked — "why can't I fix this?"
struct TimeClockEditWindowNote: View {
    let daysRemaining: Int?
    let isRunning: Bool

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var message: String {
        if isRunning {
            return "This shift is still running — you can change its start time and notes."
        }
        guard let daysRemaining else {
            return "Read-only. Entries can be edited for \(TimeClockLimits.editWindowDays) days after they are created, and that window has passed."
        }
        if daysRemaining == 0 { return "Editable today — this is the last day of the \(TimeClockLimits.editWindowDays)-day window." }
        if daysRemaining == 1 { return "Editable for 1 more day." }
        return "Editable for \(daysRemaining) more days."
    }

    private var symbol: String {
        if isRunning { return "record.circle" }
        return daysRemaining == nil ? "lock.fill" : "pencil"
    }

    private var tint: Color {
        if isRunning { return TimeClockStyle.running }
        guard let daysRemaining else { return .secondary }
        return daysRemaining <= 3 ? TimeClockStyle.overrun : .secondary
    }
}

// MARK: - A session you can clock in against

struct TimeClockSessionDisplay: Identifiable, Equatable {
    let id: String
    let schoolName: String
    let position: String
    /// "8:00 AM – 3:00 PM", already formatted.
    var timeRange: String?
    var location: String?
    /// "Day 2 of 3" — multi-day sessions, which the shipped row drew as a black
    /// capsule that matched nothing else in the app.
    var dayLabel: String?
}

/// One selectable session.
///
/// SELECTION IS A TOGGLE, and that is a fix rather than a feature. The shipped
/// row set `selectedSession` on tap and offered no way to clear it, so a mis-tap
/// could only be undone by cancelling the sheet and opening it again — on a
/// screen whose whole point is that attaching a session is OPTIONAL.
struct TimeClockSessionRow: View {
    let session: TimeClockSessionDisplay
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(session.schoolName)
                            .font(AmbientDensity.compact.titleFont)
                            .lineLimit(1)
                        if let dayLabel = session.dayLabel {
                            AmbientBadge(text: dayLabel, tint: TimeClockStyle.accent)
                        }
                    }

                    Text(session.position)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TimeClockStyle.accent)

                    if let range = session.timeRange {
                        Label(range, systemImage: "clock")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    if let location = session.location, !location.isEmpty {
                        Label(location, systemImage: "location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(TimeClockStyle.accent) : AnyShapeStyle(.tertiary))
            }
            .ambientCard(density: .compact,
                         state: isSelected ? .highlighted : .normal,
                         border: isSelected
                            ? .strong(TimeClockStyle.accent.opacity(0.6))
                            : .hairline(Color.primary.opacity(0.08)),
                         fillWidth: true)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(session.schoolName), \(session.position)")
        .accessibilityHint(isSelected ? "Selected. Tap to clear." : "Tap to attach this session.")
    }
}

// MARK: - What you are about to record

/// The summary every payroll form carries above its confirm button.
///
/// FIVE FORMS WRITE PAYROLL AND ONLY ONE OF THEM ASKED "ARE YOU SURE" — the
/// delete. This is the answer that suits the other four better than a modal
/// would: rather than interrupting, the form states the record it is about to
/// write, in the same shape on every screen, and refuses in place when the rules
/// say no.
///
/// The refusal comes from `TimeClockRules`, so a form can no longer accept
/// something the write will reject — the shipped edit form allowed 24 hours
/// where the write enforced 16.
struct TimeClockSummaryCard: View {
    let title: String
    let start: Date
    /// Nil while a shift is still running.
    var end: Date?
    /// Set when the rules refuse this entry. Drawn INSTEAD of the duration
    /// reading as if it were fine.
    var refusal: TimeClockRefusal?
    /// Shown when start and end fall on different days.
    var crossesMidnight = false

    private var duration: TimeInterval? {
        guard let end else { return nil }
        return end.timeIntervalSince(start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AmbientSectionTitle(title)

            AmbientStatLine(label: "Starts",
                            value: Formatters.mediumDateTime.string(from: start))

            if let end {
                AmbientStatLine(label: "Ends",
                                value: Formatters.mediumDateTime.string(from: end))
            }

            if let duration {
                AmbientStatLine(label: "Records",
                                value: TimeClockFormat.hoursAndMinutes(duration),
                                valueTint: refusal == nil ? TimeClockStyle.accent : .red)
            }

            if crossesMidnight, refusal == nil {
                Label("Crosses midnight", systemImage: "moon.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TimeClockStyle.overrun)
            }

            if let refusal {
                Label(refusal.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ambientCard(density: .roomy,
                     fill: .surface,
                     border: .hairline(refusal == nil
                                       ? Color.primary.opacity(0.10)
                                       : Color.red.opacity(0.35)),
                     fillWidth: true)
    }
}

// MARK: - Notes with the cap drawn

/// The notes field, with its 500-character limit shown rather than discovered.
///
/// FOUR OF THE FIVE NOTE FIELDS drew a counter and one — `CustomClockOutView` —
/// did not, so the same rule was invisible on one screen and enforced only by a
/// rejection after Save. One field, one rule.
struct TimeClockNotesField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 90

    private var limit: Int { TimeClockLimits.notesMaxCharacters }
    private var count: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).count }

    var body: some View {
        AmbientFormSection(title: title,
                           status: "\(count)/\(limit)",
                           statusTint: count > limit * 9 / 10 ? .red : nil,
                           density: .compact) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.subheadline)
                        .frame(minHeight: minHeight)
                        .scrollContentBackgroundHiddenCompat()
                }
            }
        }
        // THE CAP IS ENFORCED HERE, once, for every screen that uses this field.
        // Each of the four shipped counters carried its own copy of this
        // truncation and `CustomClockOutView` carried none.
        .onChange(of: text) { value in
            if value.count > limit { text = String(value.prefix(limit)) }
        }
    }
}

private extension View {
    /// `scrollContentBackground` is iOS 16.0+, which is under our floor, but a
    /// `TextEditor` inside a card needs its own opaque backing gone or it draws a
    /// grey slab over the panel. Wrapped for consistency with the rest of the
    /// design system's availability handling.
    @ViewBuilder
    func scrollContentBackgroundHiddenCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

// MARK: - The range control

/// Today / This Week / Pay Period.
///
/// Chips rather than `Picker(.segmented)`, for the reason `AmbientChoiceRow`
/// gives: a segmented control cannot be tinted and reads as system chrome
/// sitting on top of the wash rather than as part of the screen. The shipped one
/// also carried a `.scaleEffect(0.9)`, which shrinks its text below the size
/// Dynamic Type was asked for.
struct TimeClockRangePicker: View {
    @Binding var selection: TimeClockRange

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TimeClockRange.allCases, id: \.self) { range in
                AmbientChip(text: range.rawValue,
                            isOn: selection == range,
                            tint: TimeClockStyle.accent) {
                    selection = range
                }
            }
            Spacer(minLength: 0)
        }
    }
}
