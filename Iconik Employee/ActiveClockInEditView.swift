//  ActiveClockInEditView.swift
//  Iconik Employee — moving a running shift's start, converted in AMB.13
//
//  The old `Form` presentation is GONE from this file.
//
//  THIS SCREEN CONFIRMS NOW. Operator decision 2026-08-01: the two writes that
//  change a shift ALREADY RECORDED get a confirmation, and this is one of them.
//  Its own copy always admitted that "adjusting clock-in time will update your
//  total hours" — and then wrote it with no confirmation at all. The alert
//  states the consequence in numbers rather than in the abstract.
//
//  ALSO CHANGED:
//    - THE PREVIEW MOVES. "Time Elapsed" read `Date()` inside a computed body
//      with nothing driving a redraw, so it was frozen at whatever it happened
//      to be when the sheet opened. It is now derived from the picker, so it
//      follows your thumb.
//    - THE REFUSAL COMES FROM `TimeClockRules`, compiled and tested, rather than
//      from a second copy of the 48-hour rule written into this file.
//    - The Save button cannot be double-fired.

import SwiftUI

struct ActiveClockInEditView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @Environment(\.presentationMode) private var presentationMode

    let currentEntry: TimeEntry

    @State private var newStart: Date
    @State private var isSaving = false
    @State private var showingConfirmation = false
    @State private var failureMessage: String?

    init(timeEntry: TimeEntry, timeTrackingService: TimeTrackingService) {
        self.currentEntry = timeEntry
        self.timeTrackingService = timeTrackingService
        _newStart = State(initialValue: timeEntry.clockInTime ?? Date())
    }

    private var refusal: TimeClockRefusal? {
        TimeClockRules.refusalForActiveClockIn(newStart: newStart)
    }

    private var newTotal: String {
        TimeClockFormat.hoursAndMinutes(Date().timeIntervalSince(newStart))
    }

    private var hasChanged: Bool {
        guard let original = currentEntry.clockInTime else { return true }
        // To the minute — the picker cannot express seconds, so a second-level
        // comparison would call every open-and-close a change.
        return abs(original.timeIntervalSince(newStart)) >= 60
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(spacing: 16) {
                        TimeClockEditWindowNote(daysRemaining: nil, isRunning: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ambientCard(density: .compact,
                                         fill: .surface,
                                         border: .hairline(Color.primary.opacity(0.10)),
                                         fillWidth: true)

                        AmbientFormSection(title: "Started at", status: "") {
                            DatePicker("Start", selection: $newStart, in: earliest...Date())
                                .font(.subheadline)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        TimeClockSummaryCard(title: "This shift becomes",
                                             start: newStart,
                                             end: Date(),
                                             refusal: refusal)

                        // Only once there is something to compare against.
                        // Unchanged, it repeats the line directly above it.
                        if hasChanged, let original = currentEntry.clockInTime {
                            AmbientStatLine(label: "Was",
                                            value: Formatters.mediumDateTime.string(from: original))
                                .padding(.horizontal, 4)
                        }

                        if let failureMessage {
                            AmbientFailureCard(message: failureMessage,
                                               tint: .red,
                                               actionTitle: "Try again") {
                                self.failureMessage = nil
                                save()
                            }
                        }

                        AmbientActionButton(title: "Save start time",
                                            systemImage: "checkmark",
                                            tint: TimeClockStyle.accent,
                                            isLoading: isSaving,
                                            isEnabled: refusal == nil && hasChanged) {
                            showingConfirmation = true
                        }
                    }
                    .padding(16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Edit Start Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                        .disabled(isSaving)
                }
            }
            .alert("Change your start time?", isPresented: $showingConfirmation) {
                Button("Change it") { save() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This shift will start at \(Formatters.shortTime.string(from: newStart)), and today's total becomes \(newTotal).")
            }
        }
    }

    /// The picker cannot offer a time the rules will refuse. 48 hours back is the
    /// window `TimeEntryValidator.canEditActiveClockIn` enforces, so the control
    /// and the write agree rather than the control offering and the write
    /// rejecting.
    private var earliest: Date {
        Calendar.current.date(byAdding: .hour,
                              value: -TimeClockLimits.activeClockInWindowHours,
                              to: Date()) ?? Date()
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        failureMessage = nil

        Task {
            do {
                try await timeTrackingService.updateActiveClockInTime(newClockInTime: newStart)
                isSaving = false
                presentationMode.wrappedValue.dismiss()
            } catch {
                isSaving = false
                failureMessage = "Couldn't change the start time. \(error.userFacingMessage)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
