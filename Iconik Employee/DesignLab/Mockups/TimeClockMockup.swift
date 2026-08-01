//  TimeClockMockup.swift
//  Iconik Employee — the design lab, AMB.13's mockup
//
//  THE LAST MOCKUP THIS LAB WILL CARRY. The time clock is the one surface in the
//  arc that was never in a batch and never got a sitting — it belonged to no
//  phase from AMB.2 onward, was found while building the drift gate's allowlist
//  at AMB.10, and became its own phase by operator ruling on 2026-08-01 (D15)
//  because it is payroll. This lab and everything in it is deleted at the close
//  of AMB.13, once the converted screens have been smoked on both devices.
//
//  IT DRAWS WITH `TimeClockKit`, which is PRODUCTION code, and it quotes
//  `TimeClockRules`, which is compiled and run by
//  `scripts/test_timeclock_rules.sh`. So the ceiling this mockup shows you is
//  the ceiling the write enforces — not a number retyped into a prototype.
//
//  ONE DELIBERATE DEPARTURE FROM THE LAB'S OWN RULE, stated rather than snuck in.
//  D10/L1 says a mockup is PUSHED, never presented, because AMB.1's prototypes
//  supplied their own `NavigationStack` and hid a dead tap. That rule is about
//  matching the container the real screen will get. Every sub-screen of the clock
//  IS a sheet in production and stays one (D3: navigation is not restructured),
//  and a sheet legitimately carries its own `NavigationView`. So the sheets here
//  are presented as sheets — that IS the frame they will run in. The ROOT is
//  pushed, which is how the shell hands it over.
//
//  IT USES THE PRODUCTION WASH, unlike the two survivors in the gallery. Those
//  are colour references and keep their per-feature tints on purpose; this is a
//  SURFACE mockup whose whole job is to show what will ship, and D14 gives every
//  production screen the one company blue. A teal page here would mean approving
//  a background the converted screen will not have — the "approving an
//  approximation" failure D10 exists to prevent. The feature's teal stays where
//  D14 leaves it: on the buttons, chips and badges.
//
//  WHAT TO JUDGE, in the order it matters:
//    · Flip the three clock states at the top. Can you tell "running" from
//      "stopped" from across the room, and does the 24-hour overrun read as
//      something that wants a decision rather than as an error?
//    · Scroll the entry list. Is a locked row obviously locked, and does it now
//      say WHY without you having to open it?
//    · Flip the list to Failed. It should say the load failed and offer Retry —
//      it should NOT say you have no hours.
//    · Open Clock In. Tap a session, then tap it again — it should clear.
//    · Open any of the three edit forms. The summary card tells you exactly what
//      will be recorded, and refuses in place when the rules say no.

import SwiftUI

// MARK: - Sample data

/// Fixed sample data covering the cases that break this surface: a running
/// shift, an overrun, a manual entry, a locked entry past the 30-day window, an
/// entry with no session, and a long enough list to scroll.
private enum ClockSample {

    static let sessions: [TimeClockSessionDisplay] = [
        .init(id: "s1", schoolName: "Roosevelt High School", position: "Lead Photographer",
              timeRange: "8:00 AM – 11:30 AM", location: "Main Gym", dayLabel: nil),
        .init(id: "s2", schoolName: "St. Mary's Academy", position: "Assistant",
              timeRange: "12:30 PM – 3:00 PM", location: "Auditorium", dayLabel: "Day 2 of 3"),
        .init(id: "s3", schoolName: "Lincoln Elementary — Fall Retakes", position: "Lead Photographer",
              timeRange: "3:30 PM – 5:00 PM", location: nil, dayLabel: nil),
    ]

    static let entries: [TimeClockEntryDisplay] = [
        .init(id: "e1", dayLabel: "Today", timeRange: "7:42 AM – Present",
              durationText: "4h 18m", kind: .running,
              sessionName: "Roosevelt High School", notes: "Gym floor still wet, started in the library",
              editDaysRemaining: nil),
        .init(id: "e2", dayLabel: "Yesterday", timeRange: "8:00 AM – 4:30 PM",
              durationText: "8h 30m", kind: .clocked,
              sessionName: "St. Mary's Academy", notes: nil, editDaysRemaining: 29),
        .init(id: "e3", dayLabel: "Jul 30", timeRange: "6:15 AM – 2:45 PM",
              durationText: "8h 30m", kind: .clocked,
              sessionName: "Lincoln Elementary — Fall Retakes", notes: nil, editDaysRemaining: 28),
        // Typed in by hand — and typed in for a shift months earlier, which is
        // why the window runs from CREATION rather than from the shift's date.
        .init(id: "e4", dayLabel: "Jul 29", timeRange: "9:00 AM – 12:00 PM",
              durationText: "3h", kind: .manual,
              sessionName: nil, notes: "Forgot to clock in — equipment inventory",
              editDaysRemaining: 2),
        .init(id: "e5", dayLabel: "Jul 28", timeRange: "7:00 AM – 5:20 PM",
              durationText: "10h 20m", kind: .clocked,
              sessionName: "Roosevelt High School", notes: "Homecoming — ran long", editDaysRemaining: 1),
        // Past the 30-day window. The row is receded, badged Locked, and its
        // form explains why instead of just refusing to save.
        .init(id: "e6", dayLabel: "Jun 24", timeRange: "8:00 AM – 3:30 PM",
              durationText: "7h 30m", kind: .clocked,
              sessionName: "Westside Middle School", notes: nil, editDaysRemaining: nil),
    ]

    static var totalSeconds: TimeInterval {
        // 4h18 + 8h30 + 8h30 + 3h + 10h20 + 7h30
        (4 * 3600 + 18 * 60) + (8 * 3600 + 30 * 60) + (8 * 3600 + 30 * 60)
            + (3 * 3600) + (10 * 3600 + 20 * 60) + (7 * 3600 + 30 * 60)
    }

    static var clockedInSince: Date { DesignLabSampleData.at(7, 42) }
    static var overrunSince: Date { DesignLabSampleData.at(6, 30, dayOffset: -2) }
}

// MARK: - The mockup

struct TimeClockMockup: View {

    /// The three states the clock can be in, which is what the operator flips
    /// between. They are the whole design question on the root screen.
    private enum ClockDemo: String, CaseIterable, Identifiable {
        case stopped = "Clocked out"
        case running = "Running"
        case overrun = "Over 24h"
        var id: String { rawValue }
    }

    /// The four states the entry list can be in. "Failed" is the one that
    /// matters — the shipped screen drew it as "no entries", so payroll looked
    /// like zero when a request had simply timed out.
    private enum ListDemo: String, CaseIterable, Identifiable {
        case loaded = "Entries"
        case empty = "Empty"
        case failed = "Failed"
        case loading = "Loading"
        var id: String { rawValue }
    }

    private enum Sheet: String, Identifiable {
        case clockIn, clockOut, manualEntry, editEntry, lockedEntry, editStart, customClockOut
        var id: String { rawValue }
    }

    @State private var clock: ClockDemo = .running
    @State private var list: ListDemo = .loaded
    @State private var range: TimeClockRange = .payPeriod
    @State private var sheet: Sheet?

    /// The lab's own ticker. Production reads the service's published elapsed
    /// value; either way the view is DRIVEN rather than computing `Date()` in its
    /// own body, which is the bug that froze the shipped elapsed readouts.
    ///
    /// It holds the current INSTANT rather than an elapsed interval, so both
    /// demo shifts measure from their own start. The first cut kept one interval
    /// and offset it by a constant for the overrun case, which put a 33-hour
    /// figure above a "Since" line 53 hours earlier — a card disagreeing with
    /// itself about payroll, which is the exact thing this design claims to fix.
    @State private var now = Date()

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(spacing: 16) {
                    labControls

                    TimeClockHeroCard(status: status,
                                      attachment: attachment,
                                      isLongShift: clock == .overrun,
                                      isOffline: false)

                    actions

                    entryList
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .task { await tick() }
        .sheet(item: $sheet) { which in
            sheetContent(which)
        }
    }

    // MARK: State

    private var status: TimeClockStatus {
        switch clock {
        case .stopped:
            return .stopped
        case .running:
            return .running(since: ClockSample.clockedInSince,
                            elapsed: now.timeIntervalSince(ClockSample.clockedInSince))
        case .overrun:
            return .running(since: ClockSample.overrunSince,
                            elapsed: now.timeIntervalSince(ClockSample.overrunSince))
        }
    }

    private var attachment: TimeClockAttachment {
        guard clock != .stopped else { return .init() }
        return .init(sessionName: "Roosevelt High School",
                     notes: "Gym floor still wet, started in the library")
    }

    /// One second, forever, inside `.task` — so it dies with the view. A `Timer`
    /// installed after an `await` with no cancellation check is the leak this
    /// arc has now written down three times.
    private func tick() async {
        while !Task.isCancelled {
            now = Date()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // MARK: Lab chrome

    private var labControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Lab — clock state")
            HStack(spacing: 8) {
                ForEach(ClockDemo.allCases) { option in
                    AmbientChip(text: option.rawValue,
                                isOn: clock == option,
                                tint: TimeClockStyle.accent) { clock = option }
                }
                Spacer(minLength: 0)
            }

            AmbientSectionTitle("Lab — list state")
            HStack(spacing: 8) {
                ForEach(ListDemo.allCases) { option in
                    AmbientChip(text: option.rawValue,
                                isOn: list == option,
                                tint: .purple) { list = option }
                }
                Spacer(minLength: 0)
            }
        }
        .ambientCard(density: .compact, fill: .surface,
                     border: .dashed(Color.primary.opacity(0.2)), fillWidth: true)
    }

    // MARK: The actions under the hero

    @ViewBuilder
    private var actions: some View {
        if status.isRunning {
            VStack(spacing: 10) {
                AmbientActionButton(title: "Clock Out",
                                    systemImage: "stop.circle.fill",
                                    role: .primary,
                                    tint: clock == .overrun ? TimeClockStyle.overrun : TimeClockStyle.accent) {
                    sheet = clock == .overrun ? .customClockOut : .clockOut
                }
                AmbientActionButton(title: "Edit start time",
                                    systemImage: "clock.arrow.circlepath",
                                    role: .secondary) {
                    sheet = .editStart
                }
            }
        } else {
            AmbientActionButton(title: "Clock In",
                                systemImage: "play.circle.fill",
                                role: .primary,
                                tint: TimeClockStyle.accent) {
                sheet = .clockIn
            }
        }
    }

    // MARK: The entry list

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AmbientSectionTitle("Your hours")
                Spacer(minLength: 8)
                AmbientActionButton(title: "Add entry",
                                    systemImage: "plus",
                                    role: .secondary,
                                    size: .small,
                                    fillWidth: false) { sheet = .manualEntry }
            }

            TimeClockRangePicker(selection: $range)

            switch list {
            case .loading:
                AmbientLoadingRow(message: "Loading your hours…")

            case .failed:
                // THE POINT OF THE WHOLE STATE. Note what is NOT here: a totals
                // card reading 0h. A failed fetch says nothing about your hours.
                AmbientFailureCard(message: "Couldn't load your hours. Check your connection and try again.") {
                    list = .loaded
                }

            case .empty:
                TimeClockTotalsCard(totalSeconds: 0, entryCount: 0, rangeLabel: range.rawValue)
                AmbientEmptyState(title: "No hours yet",
                                  message: "Nothing recorded for this \(range.rawValue.lowercased()). Clock in, or add an entry by hand.",
                                  systemImage: "clock.badge.questionmark",
                                  actionTitle: "Add entry",
                                  actionIcon: "plus",
                                  action: { sheet = .manualEntry },
                                  actionTint: TimeClockStyle.accent)

            case .loaded:
                TimeClockTotalsCard(totalSeconds: ClockSample.totalSeconds,
                                    entryCount: ClockSample.entries.count,
                                    rangeLabel: range.rawValue)
                LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                    ForEach(ClockSample.entries) { entry in
                        TimeClockEntryRow(entry: entry) {
                            sheet = entry.isEditable ? .editEntry : .lockedEntry
                        }
                        .ambientScrollFade()
                    }
                }
            }
        }
    }

    // MARK: Sheets — the frame these really run in

    @ViewBuilder
    private func sheetContent(_ which: Sheet) -> some View {
        switch which {
        case .clockIn:      ClockInMockupSheet()
        case .clockOut:     ClockOutMockupSheet()
        case .manualEntry:  ManualEntryMockupSheet()
        // The two forms carry the times their ROW shows. Handing the locked
        // sheet the editable one's dates would have it contradict the row that
        // opened it — a small thing in a mockup and a payroll defect in the real
        // screen, which is why it is not left to a shared default here either.
        case .editEntry:
            EditEntryMockupSheet(entry: ClockSample.entries[3],
                                 start: DesignLabSampleData.at(9, 0, dayOffset: -3),
                                 end: DesignLabSampleData.at(12, 0, dayOffset: -3),
                                 locked: false)
        case .lockedEntry:
            EditEntryMockupSheet(entry: ClockSample.entries[5],
                                 start: DesignLabSampleData.at(8, 0, dayOffset: -38),
                                 end: DesignLabSampleData.at(15, 30, dayOffset: -38),
                                 locked: true)
        case .editStart:    EditStartMockupSheet()
        case .customClockOut: CustomClockOutMockupSheet()
        }
    }
}

// MARK: - Clock in

private struct ClockInMockupSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var selected: String?
    @State private var notes = ""
    @State private var demoEmpty = false
    @State private var demoFailed = false

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()
                ScrollView {
                    VStack(spacing: 16) {
                        labToggles

                        if demoFailed {
                            // The shipped screen drew this case as "No sessions
                            // assigned for today / You can still clock in without
                            // selecting a session" — inviting an unattributed
                            // clock-in on a day that probably has sessions.
                            AmbientFailureCard(message: "Couldn't load today's sessions. You can still clock in without one.") {
                                demoFailed = false
                            }
                        } else if demoEmpty {
                            AmbientEmptyState(title: "No sessions today",
                                              message: "Nothing is assigned to you today. You can still clock in without a session.",
                                              systemImage: "calendar.badge.exclamationmark")
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                AmbientSectionTitle("Today's sessions", trailing: "Optional")
                                ForEach(ClockSample.sessions) { session in
                                    TimeClockSessionRow(session: session,
                                                        isSelected: selected == session.id) {
                                        // TOGGLE. The shipped row could only ever
                                        // set a selection, never clear one.
                                        selected = selected == session.id ? nil : session.id
                                    }
                                }
                            }
                        }

                        TimeClockNotesField(title: "Notes",
                                            placeholder: "Anything worth recording about this shift…",
                                            text: $notes,
                                            minHeight: 70)

                        AmbientActionButton(title: selected == nil ? "Clock In" : "Clock In to session",
                                            systemImage: "play.circle.fill",
                                            tint: TimeClockStyle.accent) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Clock In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }

    private var labToggles: some View {
        HStack(spacing: 8) {
            AmbientChip(text: "Sessions", isOn: !demoEmpty && !demoFailed, tint: .purple) {
                demoEmpty = false; demoFailed = false
            }
            AmbientChip(text: "Empty", isOn: demoEmpty, tint: .purple) {
                demoEmpty = true; demoFailed = false
            }
            AmbientChip(text: "Failed", isOn: demoFailed, tint: .purple) {
                demoFailed = true; demoEmpty = false
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Clock out

private struct ClockOutMockupSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()
                ScrollView {
                    VStack(spacing: 16) {
                        // You see the record before you make it. The shipped
                        // sheet asked for notes and said nothing about hours.
                        TimeClockSummaryCard(title: "You're about to record",
                                             start: ClockSample.clockedInSince,
                                             end: Date())

                        TimeClockNotesField(title: "Notes",
                                            placeholder: "How did the shift go?",
                                            text: $notes)

                        // `isLoading` disables AND spins, in one place. The
                        // shipped button set a flag that was never reset, so a
                        // failed clock-out wedged it at "Processing…" for good.
                        AmbientActionButton(title: "Clock Out",
                                            systemImage: "stop.circle.fill",
                                            tint: TimeClockStyle.accent,
                                            isLoading: isSaving) {
                            isSaving = true
                        }

                        if isSaving {
                            Button("Reset (lab only)") { isSaving = false }
                                .font(.caption)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Clock Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}

// MARK: - Manual entry

private struct ManualEntryMockupSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var day = DesignLabSampleData.at(9, 0, dayOffset: -1)
    @State private var start = DesignLabSampleData.at(9, 0, dayOffset: -1)
    @State private var end = DesignLabSampleData.at(17, 0, dayOffset: -1)
    @State private var notes = ""

    private var combinedStart: Date { combine(day: day, time: start) }
    private var combinedEnd: Date { combine(day: day, time: end) }

    private var refusal: TimeClockRefusal? {
        TimeClockRules.refusalForRecordedShift(start: combinedStart, end: combinedEnd)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()
                ScrollView {
                    VStack(spacing: 16) {
                        AmbientFormSection(title: "When", status: "") {
                            VStack(spacing: 4) {
                                // BOUNDED. The shipped picker let you choose a
                                // date in the future and refused it only after
                                // Save.
                                DatePicker("Date", selection: $day, in: ...Date(),
                                           displayedComponents: .date)
                                Divider()
                                DatePicker("Start", selection: $start,
                                           displayedComponents: .hourAndMinute)
                                Divider()
                                DatePicker("End", selection: $end,
                                           displayedComponents: .hourAndMinute)
                            }
                            .font(.subheadline)
                        }

                        TimeClockSummaryCard(title: "You're about to record",
                                             start: combinedStart,
                                             end: combinedEnd,
                                             refusal: refusal)

                        TimeClockNotesField(title: "Notes",
                                            placeholder: "Why is this being added by hand?",
                                            text: $notes)

                        AmbientActionButton(title: "Save entry",
                                            systemImage: "checkmark",
                                            tint: TimeClockStyle.accent,
                                            isEnabled: refusal == nil) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }

    private func combine(day: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0,
                             second: 0, of: day) ?? day
    }
}

// MARK: - Edit an entry (and the locked case)

private struct EditEntryMockupSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    let entry: TimeClockEntryDisplay
    let locked: Bool

    @State private var start: Date
    @State private var end: Date
    @State private var notes: String
    @State private var showingDelete = false

    init(entry: TimeClockEntryDisplay, start: Date, end: Date, locked: Bool) {
        self.entry = entry
        self.locked = locked
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        _notes = State(initialValue: entry.notes ?? "")
    }

    private var refusal: TimeClockRefusal? {
        TimeClockRules.refusalForRecordedShift(start: start, end: end)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()
                ScrollView {
                    VStack(spacing: 16) {
                        // The sentence that only ever lived on a dead screen.
                        TimeClockEditWindowNote(daysRemaining: entry.editDaysRemaining,
                                                isRunning: entry.kind == .running)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ambientCard(density: .compact, fill: .surface,
                                         border: .hairline(Color.primary.opacity(0.1)),
                                         fillWidth: true)

                        if locked {
                            TimeClockSummaryCard(title: "Recorded",
                                                 start: start, end: end)
                        } else {
                            AmbientFormSection(title: "When", status: "") {
                                VStack(spacing: 4) {
                                    DatePicker("Start", selection: $start, in: ...Date())
                                    Divider()
                                    DatePicker("End", selection: $end, in: ...Date())
                                }
                                .font(.subheadline)
                            }

                            TimeClockSummaryCard(
                                title: "You're about to record",
                                start: start,
                                end: end,
                                refusal: refusal,
                                crossesMidnight: !Calendar.current.isDate(start, inSameDayAs: end))

                            TimeClockNotesField(title: "Notes",
                                                placeholder: "Notes for this entry…",
                                                text: $notes)

                            AmbientActionButton(title: "Save changes",
                                                systemImage: "checkmark",
                                                tint: TimeClockStyle.accent,
                                                isEnabled: refusal == nil) {
                                presentationMode.wrappedValue.dismiss()
                            }

                            AmbientActionButton(title: "Delete entry",
                                                systemImage: "trash",
                                                role: .destructive) {
                                showingDelete = true
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(locked ? "Time Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(locked ? "Done" : "Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .alert("Delete this entry?", isPresented: $showingDelete) {
                Button("Delete", role: .destructive) { presentationMode.wrappedValue.dismiss() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes \(entry.durationText) from \(entry.dayLabel). It cannot be undone.")
            }
        }
    }
}

// MARK: - Edit a running shift's start

private struct EditStartMockupSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var start = ClockSample.clockedInSince

    private var refusal: TimeClockRefusal? {
        TimeClockRules.refusalForActiveClockIn(newStart: start)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()
                ScrollView {
                    VStack(spacing: 16) {
                        TimeClockEditWindowNote(daysRemaining: nil, isRunning: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ambientCard(density: .compact, fill: .surface,
                                         border: .hairline(Color.primary.opacity(0.1)),
                                         fillWidth: true)

                        AmbientFormSection(title: "Started at", status: "") {
                            DatePicker("Start", selection: $start, in: ...Date())
                                .font(.subheadline)
                        }

                        // The elapsed figure here is DERIVED from the picker, so
                        // it moves as you drag. The shipped preview computed
                        // `Date()` in its body and never redrew.
                        TimeClockSummaryCard(title: "This shift becomes",
                                             start: start,
                                             end: Date(),
                                             refusal: refusal)

                        Text("Changing the start time changes today's total hours.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        AmbientActionButton(title: "Save start time",
                                            systemImage: "checkmark",
                                            tint: TimeClockStyle.accent,
                                            isEnabled: refusal == nil) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Edit Start Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}

// MARK: - Clock out at a chosen time (the long-shift path)

private struct CustomClockOutMockupSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var end = Date()
    @State private var notes = ""

    private var refusal: TimeClockRefusal? {
        TimeClockRules.refusalForLiveClockOut(clockIn: ClockSample.overrunSince, clockOut: end)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()
                ScrollView {
                    VStack(spacing: 16) {
                        AmbientFailureCard(message: "This shift has been running for more than 24 hours. Set the time you actually stopped.",
                                           systemImage: "exclamationmark.triangle.fill",
                                           tint: TimeClockStyle.overrun)

                        AmbientFormSection(title: "Stopped at", status: "") {
                            DatePicker("End", selection: $end,
                                       in: ClockSample.overrunSince...Date())
                                .font(.subheadline)
                        }

                        HStack(spacing: 8) {
                            ForEach(presets, id: \.0) { label, date in
                                AmbientChip(text: label, isOn: false,
                                            tint: TimeClockStyle.overrun) { end = date }
                            }
                            Spacer(minLength: 0)
                        }

                        TimeClockSummaryCard(title: "You're about to record",
                                             start: ClockSample.overrunSince,
                                             end: end,
                                             refusal: refusal,
                                             crossesMidnight: !Calendar.current.isDate(
                                                ClockSample.overrunSince, inSameDayAs: end))

                        // The one note field that never had a counter now has one.
                        TimeClockNotesField(title: "Notes",
                                            placeholder: "What happened?",
                                            text: $notes,
                                            minHeight: 70)

                        AmbientActionButton(title: "Clock Out",
                                            systemImage: "stop.circle.fill",
                                            tint: TimeClockStyle.overrun,
                                            isEnabled: refusal == nil) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Set Clock-Out Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }

    private var presets: [(String, Date)] {
        [("End of yesterday", DesignLabSampleData.at(23, 59, dayOffset: -1)),
         ("Start of today", Calendar.current.startOfDay(for: Date())),
         ("Now", Date())]
    }
}
