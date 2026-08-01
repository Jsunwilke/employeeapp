//  SessionSelectionView.swift
//  Iconik Employee — clocking in, converted to Ambient in AMB.13
//
//  The old presentation and its hand-rolled `SessionRow` are GONE from this
//  file. The row is `TimeClockSessionRow` in `TimeClock/TimeClockKit.swift`,
//  which the design lab's mockup also draws with.
//
//  THE ONE THAT MATTERS: A FAILED SESSION FETCH NO LONGER INVITES AN
//  UNATTRIBUTED CLOCK-IN. The catch block set `isLoading = false` and nothing
//  else, so a request that failed drew the EMPTY state — "No sessions assigned
//  for today" plus "You can still clock in without selecting a session" — on a
//  day that very likely had sessions. Failure is now its own state.
//
//  ALSO CHANGED:
//    - SELECTION IS A TOGGLE. The shipped row could only ever set a selection.
//      On a screen whose whole point is that attaching a session is optional, a
//      mis-tap could be undone only by cancelling the sheet and reopening it.
//    - THE BUTTON CANNOT BE DOUBLE-FIRED. It never disabled and showed no
//      spinner; a second tap was stopped only by a server round trip. It now
//      goes through `AmbientActionButton(isLoading:)`, which disables and spins
//      in one place.
//    - THE WRITE LIVES HERE. It used to hand `onClockIn` back to three different
//      callers, two of which duplicated the same Task-and-catch and one of which
//      (`TimeTrackingButton`) was dead. The home dashboard's copy swallowed its
//      error into a bare `// Clock in error` comment. One screen, one write, one
//      error path.
//    - Debug `print`s carrying session ids off a payroll path are gone.

import SwiftUI

struct SessionSelectionView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @Environment(\.presentationMode) private var presentationMode

    @State private var sessions: [Session] = []
    @State private var selectedSessionId: String?
    @State private var notes = ""
    @State private var phase: LoadPhase = .loading
    @State private var isClockingIn = false
    @State private var failureMessage: String?

    private enum LoadPhase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(spacing: 16) {
                        sessionSection

                        TimeClockNotesField(title: "Notes",
                                            placeholder: "Anything worth recording about this shift…",
                                            text: $notes,
                                            minHeight: 70)

                        if let failureMessage {
                            AmbientFailureCard(message: failureMessage,
                                               tint: .red,
                                               actionTitle: "Try again") {
                                self.failureMessage = nil
                                clockIn()
                            }
                        }

                        AmbientActionButton(title: selectedSessionId == nil ? "Clock In" : "Clock In to session",
                                            systemImage: "play.circle.fill",
                                            tint: TimeClockStyle.accent,
                                            isLoading: isClockingIn) {
                            clockIn()
                        }
                    }
                    .padding(16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Clock In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                        .disabled(isClockingIn)
                }
            }
        }
        .task { await loadSessions() }
    }

    // MARK: - Sessions

    @ViewBuilder
    private var sessionSection: some View {
        switch phase {
        case .loading:
            AmbientLoadingRow(message: "Loading today's sessions…")

        case .failed(let message):
            // NOT the empty state. The empty state says "nothing is assigned to
            // you"; this says "we could not find out" — and still lets you clock
            // in, because being unable to reach the server is not a reason to
            // stop somebody starting work.
            AmbientFailureCard(message: message) {
                Task { await loadSessions() }
            }

        case .loaded:
            if sessions.isEmpty {
                AmbientEmptyState(
                    title: "No sessions today",
                    message: "Nothing is assigned to you today. You can still clock in without a session.",
                    systemImage: "calendar.badge.exclamationmark"
                )
            } else {
                VStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
                    AmbientSectionTitle("Today's sessions", trailing: "Optional")
                    ForEach(sessions, id: \.id) { session in
                        TimeClockSessionRow(session: TimeClockSessionDisplay(session),
                                            isSelected: selectedSessionId == session.id) {
                            // Toggle, not set.
                            selectedSessionId = selectedSessionId == session.id ? nil : session.id
                        }
                    }
                }
            }
        }
    }

    private func loadSessions() async {
        phase = .loading
        do {
            let loaded = try await timeTrackingService.getTodayAssignedSessions()
            guard !Task.isCancelled else { return }
            sessions = loaded.sorted { lhs, rhs in
                guard let a = lhs.startDate, let b = rhs.startDate else { return false }
                return a < b
            }
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed("Couldn't load today's sessions. \(error.userFacingMessage)")
        }
    }

    // MARK: - The write

    private func clockIn() {
        guard !isClockingIn else { return }
        isClockingIn = true
        failureMessage = nil

        Task {
            do {
                try await timeTrackingService.clockIn(
                    sessionId: selectedSessionId,
                    notes: notes.isEmpty ? nil : notes
                )
                isClockingIn = false
                presentationMode.wrappedValue.dismiss()
            } catch {
                // Reported IN the sheet, and the flag is reset. The shipped
                // clock-out sheet set its equivalent flag and never cleared it,
                // wedging the button at "Processing…" with nothing shown.
                isClockingIn = false
                failureMessage = "Couldn't clock you in. \(error.userFacingMessage)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

#Preview {
    SessionSelectionView(timeTrackingService: TimeTrackingService())
}
