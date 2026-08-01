//  TimeTrackingMainView.swift
//  Iconik Employee — the time clock, converted to Ambient in AMB.13
//
//  The old presentation is GONE from this file, not left beside the new one.
//
//  WHAT CHANGED, and why each is in scope for a design phase (D12):
//
//    - THE CLOCK LEADS. It used to be a subheadline in a grey box above a
//      segmented date picker, and the picker was the loudest thing on screen.
//      A photographer opens this to answer one question — am I on the clock,
//      and since when. That is now the hero card.
//
//    - THE 24-HOUR WARNING IS LEGIBLE AND LIVE. It was a caption-sized ⚠️ inside
//      the Clock Out button: the least visible place on the screen, only seen
//      after you had decided to leave, and it never updated on its own because
//      it read `Date()` in a computed body with nothing driving a redraw. It is
//      now a sentence on the card, driven by the service's published clock.
//
//    - THE SHEETS CANNOT RENDER EMPTY. Two of them were `if let` with no `else`,
//      so a nil entry at presentation time opened a blank sheet. They are now
//      `.sheet(item:)`, which cannot present without a value.
//
//    - NOTHING WRITES TWICE. Clock-out is guarded in flight and the button says
//      so, rather than staying live during its own network call.
//
//  WHAT IT DELIBERATELY DID NOT GAIN:
//
//    - A CONFIRMATION ON ORDINARY CLOCK IN / CLOCK OUT. Operator decision
//      2026-08-01: people do this several times a day and a prompt they tap
//      through without reading is worse than none. The two writes that CHANGE a
//      shift already recorded — the live start-time edit and the late custom
//      clock-out — do confirm; see `ActiveClockInEditView` and
//      `CustomClockOutView`.
//
//    - PAGINATION. `getTimeEntries` caps at 100 rows with no indication
//      (AMB13_CLOCK_PARITY.md §7). The list now SAYS when it is truncated, which
//      is presentation; making it fetch more is a data change and belongs to its
//      own phase.

import SwiftUI

struct TimeTrackingMainView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService

    @State private var showingSessionSelection = false
    @State private var showingClockOut = false
    @State private var showingLongShiftAlert = false
    /// `.sheet(item:)` rather than a boolean plus an `if let`, so a sheet can
    /// never be presented without the entry it is about to edit.
    @State private var entryBeingAdjusted: TimeEntry?
    @State private var shiftBeingClosedOut: RunningShift?
    @State private var alertMessage: String?

    /// A running shift that DEFINITELY has a start time.
    ///
    /// Handing `.sheet(item:)` the `TimeEntry` and then unwrapping
    /// `clockInTime` inside the builder reintroduces the exact defect this
    /// phase set out to remove: a sheet that presents and draws nothing. The
    /// unwrap happens where the value is SET, so an entry without a start time
    /// cannot open the sheet at all.
    private struct RunningShift: Identifiable {
        let id: String
        let clockInTime: Date

        init?(_ entry: TimeEntry?) {
            guard let entry, let start = entry.clockInTime else { return nil }
            self.id = entry.id
            self.clockInTime = start
        }
    }

    private var status: TimeClockStatus {
        guard timeTrackingService.isClockIn,
              let start = timeTrackingService.currentTimeEntry?.clockInTime else {
            return .stopped
        }
        // The elapsed figure comes from the service's published ticker, not from
        // `Date()` in this body — the distinction that keeps it moving.
        return .running(since: start, elapsed: timeTrackingService.elapsedTime)
    }

    private var isLongShift: Bool {
        guard let start = timeTrackingService.currentTimeEntry?.clockInTime else { return false }
        return TimeClockRules.isLongShift(clockIn: start,
                                          now: start.addingTimeInterval(timeTrackingService.elapsedTime))
    }

    private var attachment: TimeClockAttachment {
        guard let entry = timeTrackingService.currentTimeEntry, timeTrackingService.isClockIn else {
            return TimeClockAttachment()
        }
        var name: String?
        if let sessionId = entry.sessionId, !sessionId.isEmpty {
            name = (entry.sessionName?.isEmpty == false && entry.sessionName != sessionId)
                ? entry.sessionName
                : "Session"
        }
        return TimeClockAttachment(sessionName: name, notes: entry.notes)
    }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(spacing: 16) {
                    TimeClockHeroCard(status: status,
                                      attachment: attachment,
                                      isLongShift: isLongShift,
                                      isOffline: timeTrackingService.isUsingOfflineData)

                    actions

                    TimeEntryListView(timeTrackingService: timeTrackingService)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .ambientNoBounceWhenShort()
        }
        .navigationTitle("Time Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .tabBarClearance()
        .sheet(isPresented: $showingSessionSelection) {
            SessionSelectionView(timeTrackingService: timeTrackingService)
        }
        .sheet(isPresented: $showingClockOut) {
            // No `onFailure` back to this screen: the sheet stays open and
            // reports in place. Doing both put an alert on top of the sheet
            // that was already showing the same sentence.
            ClockOutView(timeTrackingService: timeTrackingService,
                         clockInTime: timeTrackingService.currentTimeEntry?.clockInTime)
        }
        .sheet(item: $shiftBeingClosedOut) { shift in
            CustomClockOutView(timeTrackingService: timeTrackingService,
                               clockInTime: shift.clockInTime)
        }
        .sheet(item: $entryBeingAdjusted) { entry in
            ActiveClockInEditView(timeEntry: entry, timeTrackingService: timeTrackingService)
        }
        .alert("Long shift detected", isPresented: $showingLongShiftAlert) {
            Button("Clock out now") { showingClockOut = true }
            Button("Set the time I stopped") {
                shiftBeingClosedOut = RunningShift(timeTrackingService.currentTimeEntry)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You've been clocked in for more than 24 hours. Would you like to set the time you actually stopped?")
        }
        .alert("Time tracking",
               isPresented: Binding(get: { alertMessage != nil },
                                    set: { if !$0 { alertMessage = nil } })) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if timeTrackingService.isClockIn {
            VStack(spacing: 10) {
                AmbientActionButton(title: "Clock Out",
                                    systemImage: "stop.circle.fill",
                                    role: .primary,
                                    tint: isLongShift ? TimeClockStyle.overrun : TimeClockStyle.accent) {
                    // The 24-hour check that used to live in `checkForLongShift`,
                    // now asking TimeClockRules instead of restating `24 * 60 * 60`.
                    if isLongShift {
                        showingLongShiftAlert = true
                    } else {
                        showingClockOut = true
                    }
                }

                AmbientActionButton(title: "Edit start time",
                                    systemImage: "clock.arrow.circlepath",
                                    role: .secondary) {
                    entryBeingAdjusted = timeTrackingService.currentTimeEntry
                }
            }
        } else {
            AmbientActionButton(title: "Clock In",
                                systemImage: "play.circle.fill",
                                role: .primary,
                                tint: TimeClockStyle.accent) {
                showingSessionSelection = true
            }
        }
    }
}

#Preview {
    NavigationView {
        TimeTrackingMainView(timeTrackingService: TimeTrackingService())
    }
}
