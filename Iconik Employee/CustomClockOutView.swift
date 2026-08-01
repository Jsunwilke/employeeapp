//  CustomClockOutView.swift
//  Iconik Employee — closing a long shift at the time you actually stopped,
//  converted to Ambient in AMB.13
//
//  The old `Form` presentation is GONE from this file.
//
//  Reached only from the long-shift alert on `TimeTrackingMainView`, which is
//  unchanged: past 24 hours the app offers to set a real clock-out time rather
//  than stamping "now" on a shift that ended yesterday.
//
//  THIS SCREEN CONFIRMS NOW. Operator decision 2026-08-01 — it is the second of
//  the two writes that change a shift already recorded, and it writes an
//  operator-chosen timestamp onto payroll with, until now, no confirmation and
//  no in-flight guard: the button stayed live for the whole network call.
//
//  ALSO CHANGED:
//    - THE NOTES FIELD HAS ITS 500-CHARACTER CAP DRAWN. This was the one field
//      of five without a counter, so the same rule was invisible here and
//      enforced only by a rejection after Save.
//    - THE PICKERS START FROM THE SHIFT, not from `Date()`. They defaulted to
//      now regardless of when the shift began.
//    - THE 24-HOUR CEILING comes from `TimeClockRules`, which is the same value
//      `clockOutManual` enforces — and deliberately NOT the 16-hour ceiling that
//      governs a shift typed in from nothing. Two different acts, two numbers,
//      both written down once.

import SwiftUI

struct CustomClockOutView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    let clockInTime: Date

    @Environment(\.presentationMode) private var presentationMode

    @State private var end: Date
    @State private var notes = ""
    @State private var isSaving = false
    @State private var showingConfirmation = false
    @State private var failureMessage: String?

    init(timeTrackingService: TimeTrackingService, clockInTime: Date) {
        self.timeTrackingService = timeTrackingService
        self.clockInTime = clockInTime
        // Derived from the shift rather than from now, which is what the shipped
        // pickers did. The ceiling is the earlier of "24 hours after you started"
        // and "now" — so the control cannot offer a time the write refuses.
        let ceiling = min(clockInTime.addingTimeInterval(TimeClockLimits.liveClockOutMaximum), Date())
        _end = State(initialValue: ceiling)
    }

    private var refusal: TimeClockRefusal? {
        TimeClockRules.refusalForLiveClockOut(clockIn: clockInTime, clockOut: end)
    }

    private var latest: Date {
        min(clockInTime.addingTimeInterval(TimeClockLimits.liveClockOutMaximum), Date())
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(spacing: 16) {
                        AmbientFailureCard(
                            message: "This shift has been running for more than 24 hours. Set the time you actually stopped.",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: TimeClockStyle.overrun
                        )

                        AmbientFormSection(title: "Stopped at", status: "") {
                            DatePicker("End", selection: $end, in: clockInTime...latest)
                                .font(.subheadline)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        presets

                        TimeClockSummaryCard(title: "You're about to record",
                                             start: clockInTime,
                                             end: end,
                                             refusal: refusal,
                                             crossesMidnight: !Calendar.current.isDate(
                                                clockInTime, inSameDayAs: end))

                        TimeClockNotesField(title: "Notes",
                                            placeholder: "What happened?",
                                            text: $notes,
                                            minHeight: 70)

                        if let failureMessage {
                            AmbientFailureCard(message: failureMessage,
                                               tint: .red,
                                               actionTitle: "Try again") {
                                self.failureMessage = nil
                                save()
                            }
                        }

                        AmbientActionButton(title: "Clock Out",
                                            systemImage: "stop.circle.fill",
                                            tint: TimeClockStyle.overrun,
                                            isLoading: isSaving,
                                            isEnabled: refusal == nil) {
                            showingConfirmation = true
                        }
                    }
                    .padding(16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Set Clock-Out Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                        .disabled(isSaving)
                }
            }
            .alert("Clock out at this time?", isPresented: $showingConfirmation) {
                Button("Clock out") { save() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This records \(TimeClockFormat.hoursAndMinutes(end.timeIntervalSince(clockInTime))), ending \(Formatters.mediumDateTime.string(from: end)).")
            }
        }
    }

    /// The three shipped presets, as chips instead of a horizontally scrolling
    /// row of tinted rectangles. Each is clamped into the picker's own range, so
    /// a preset can never set a value the write would refuse — "End of
    /// yesterday" on a shift that started this morning would have done exactly
    /// that.
    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(presetOptions, id: \.0) { label, date in
                AmbientChip(text: label, isOn: abs(end.timeIntervalSince(date)) < 60,
                            tint: TimeClockStyle.overrun) {
                    end = min(max(date, clockInTime), latest)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var presetOptions: [(String, Date)] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let endOfYesterday = startOfToday.addingTimeInterval(-60)
        return [("End of yesterday", endOfYesterday),
                ("Start of today", startOfToday),
                ("Now", Date())]
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        failureMessage = nil

        Task {
            do {
                try await timeTrackingService.clockOutManual(
                    clockOutDateTime: end,
                    notes: notes.isEmpty ? nil : notes
                )
                isSaving = false
                presentationMode.wrappedValue.dismiss()
            } catch {
                isSaving = false
                failureMessage = "Couldn't clock you out. \(error.userFacingMessage)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
