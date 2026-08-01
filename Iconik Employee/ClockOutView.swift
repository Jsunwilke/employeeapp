//  ClockOutView.swift
//  Iconik Employee — clocking out, converted to Ambient in AMB.13
//
//  REPLACES `NotesInputView.swift`, which is deleted in the same change.
//
//  The old file was named for the least important thing it did. It was built to
//  serve clocking IN and clocking OUT, but only the clock-out half was ever
//  wired up — the clock-in path goes through `SessionSelectionView`, which has
//  its own notes field. Half a screen serving a caller that does not exist is
//  how a `isClockOut: Bool` ends up threaded through every line of a body.
//
//  THE BUG IT SHIPPED WITH: `isProcessing` was set true on tap and never reset.
//  A clock-out that failed left the button reading "Processing…" forever, with
//  no error anywhere in the sheet — on the app's primary way out of a shift. It
//  now goes through `AmbientActionButton(isLoading:)` and reports failure in
//  place, with the flag cleared either way.
//
//  WHAT IT GAINED: you see what you are about to record before you commit. The
//  old sheet asked for notes and said nothing at all about hours.

import SwiftUI

struct ClockOutView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    /// Nil only if the entry vanished between opening this sheet and drawing it,
    /// in which case there is nothing to summarise — the write still refuses
    /// server-side.
    let clockInTime: Date?
    /// Reported by the presenting screen, because this sheet dismisses itself on
    /// success and a failure the user never sees is the shape being removed.
    var onFailure: ((String) -> Void)?

    @Environment(\.presentationMode) private var presentationMode

    @State private var notes = ""
    @State private var isSaving = false
    @State private var failureMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(spacing: 16) {
                        if let clockInTime {
                            TimeClockSummaryCard(title: "You're about to record",
                                                 start: clockInTime,
                                                 end: Date(),
                                                 crossesMidnight: !Calendar.current.isDate(
                                                    clockInTime, inSameDayAs: Date()))
                        }

                        TimeClockNotesField(title: "Notes",
                                            placeholder: "How did the shift go?",
                                            text: $notes)

                        if let failureMessage {
                            AmbientFailureCard(message: failureMessage,
                                               tint: .red,
                                               actionTitle: "Try again") {
                                self.failureMessage = nil
                                clockOut()
                            }
                        }

                        AmbientActionButton(title: "Clock Out",
                                            systemImage: "stop.circle.fill",
                                            tint: TimeClockStyle.accent,
                                            isLoading: isSaving) {
                            clockOut()
                        }
                    }
                    .padding(16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Clock Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func clockOut() {
        guard !isSaving else { return }
        isSaving = true
        failureMessage = nil

        Task {
            do {
                try await timeTrackingService.clockOut(notes: notes.isEmpty ? nil : notes)
                isSaving = false
                presentationMode.wrappedValue.dismiss()
            } catch {
                isSaving = false
                let message = "Couldn't clock you out. \(error.userFacingMessage)"
                failureMessage = message
                onFailure?(message)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

#Preview {
    ClockOutView(timeTrackingService: TimeTrackingService(),
                 clockInTime: Date().addingTimeInterval(-7 * 3600))
}
