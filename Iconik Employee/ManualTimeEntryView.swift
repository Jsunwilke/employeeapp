//  ManualTimeEntryView.swift
//  Iconik Employee — writing a shift down after the fact, converted in AMB.13
//
//  The old `Form` presentation is GONE from this file.
//
//  NO CONFIRMATION HERE, deliberately. Operator decision 2026-08-01: a
//  confirmation belongs on the two writes that CHANGE a shift already recorded.
//  This one creates a record you are typing in on purpose, and the summary card
//  above the button already states exactly what it will write.
//
//  WHAT CHANGED:
//    - THE DATE PICKER IS BOUNDED. It let you pick a date in the future and
//      refused it only after Save.
//    - CROSS-MIDNIGHT IS POSSIBLE. `createDateTime` forced both start and end
//      onto the SAME day, so an overnight shift failed as "End time must be
//      after start time" — a shift a photographer really works, which the form
//      simply could not express. It now takes a start and an end that each
//      carry their own day, the way `EditTimeEntryView` always has.
//    - THE VALIDATION IS THE WRITE'S. `TimeClockRules.refusalForRecordedShift`
//      is the same 16-hour ceiling, one-minute floor and future check that
//      `validateManualEntry` enforces, in the same ORDER — so the reason shown
//      is the reason the write would give.
//    - OVERLAP IS STILL DISCOVERED ON SAVE, and that is unchanged on purpose:
//      overlap detection is a server round trip against other entries, and
//      running it on every picker drag would be a data change, not a restyle.
//      What is new is that the refusal is reported properly instead of as a
//      generic alert.
//    - A session that fails to load no longer fails silently. The picker simply
//      never appeared, with the reason in a `print`.

import SwiftUI

struct ManualTimeEntryView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @Environment(\.presentationMode) private var presentationMode

    @State private var start: Date
    @State private var end: Date
    @State private var sessions: [Session] = []
    @State private var selectedSessionId: String?
    @State private var sessionLoadFailed = false
    @State private var notes = ""
    @State private var isSaving = false
    @State private var failureMessage: String?

    init(timeTrackingService: TimeTrackingService) {
        self.timeTrackingService = timeTrackingService
        // Yesterday 9–5 rather than "now to an hour from now", which the shipped
        // defaults produced and which is always in the future for the second
        // half of the day.
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: yesterday) ?? yesterday
        _start = State(initialValue: nine)
        _end = State(initialValue: nine.addingTimeInterval(8 * 3600))
    }

    private var refusal: TimeClockRefusal? {
        TimeClockRules.refusalForRecordedShift(start: start, end: end)
            ?? TimeClockRules.refusalForNotes(notes)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(spacing: 16) {
                        AmbientFormSection(title: "When", status: "") {
                            VStack(spacing: 8) {
                                DatePicker("Started", selection: $start, in: ...Date())
                                    .onChange(of: start) { _ in
                                        // Keep the end after the start without
                                        // silently rewriting a deliberate
                                        // overnight span.
                                        if end <= start { end = start.addingTimeInterval(3600) }
                                    }
                                Divider()
                                DatePicker("Stopped", selection: $end, in: ...Date())
                            }
                            .font(.subheadline)
                        }

                        TimeClockSummaryCard(title: "You're about to record",
                                             start: start,
                                             end: end,
                                             refusal: refusal,
                                             crossesMidnight: !Calendar.current.isDate(
                                                start, inSameDayAs: end))

                        sessionSection

                        TimeClockNotesField(title: "Notes",
                                            placeholder: "Why is this being added by hand?",
                                            text: $notes)

                        if let failureMessage {
                            AmbientFailureCard(message: failureMessage,
                                               tint: .red,
                                               actionTitle: "Try again") {
                                self.failureMessage = nil
                                save()
                            }
                        }

                        AmbientActionButton(title: "Save entry",
                                            systemImage: "checkmark",
                                            tint: TimeClockStyle.accent,
                                            isLoading: isSaving,
                                            isEnabled: refusal == nil) {
                            save()
                        }
                    }
                    .padding(16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                        .disabled(isSaving)
                }
            }
        }
        .task(id: Calendar.current.startOfDay(for: start)) { await loadSessions() }
    }

    // MARK: - Session

    @ViewBuilder
    private var sessionSection: some View {
        if sessionLoadFailed {
            AmbientFailureCard(message: "Couldn't load that day's sessions. You can still save without one.") {
                Task { await loadSessions() }
            }
        } else if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
                AmbientSectionTitle("Session", trailing: "Optional")
                ForEach(sessions, id: \.id) { session in
                    TimeClockSessionRow(session: TimeClockSessionDisplay(session),
                                        isSelected: selectedSessionId == session.id) {
                        selectedSessionId = selectedSessionId == session.id ? nil : session.id
                    }
                }
            }
        }
    }

    private func loadSessions() async {
        sessionLoadFailed = false
        do {
            let loaded = try await timeTrackingService.getSessionsForDate(start)
            guard !Task.isCancelled else { return }
            sessions = loaded.sorted { lhs, rhs in
                guard let a = lhs.startDate, let b = rhs.startDate else { return false }
                return a < b
            }
            // A session that is no longer on the chosen day cannot stay selected.
            if let id = selectedSessionId, !sessions.contains(where: { $0.id == id }) {
                selectedSessionId = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            sessions = []
            selectedSessionId = nil
            sessionLoadFailed = true
        }
    }

    // MARK: - The write

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        failureMessage = nil

        Task {
            do {
                try await timeTrackingService.createManualTimeEntry(
                    date: start,
                    startTime: start,
                    endTime: end,
                    sessionId: selectedSessionId,
                    notes: notes.isEmpty ? nil : notes
                )
                isSaving = false
                presentationMode.wrappedValue.dismiss()
            } catch {
                isSaving = false
                failureMessage = error.userFacingMessage
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

#Preview {
    ManualTimeEntryView(timeTrackingService: TimeTrackingService())
}
