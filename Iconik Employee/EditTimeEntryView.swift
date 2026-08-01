//  EditTimeEntryView.swift
//  Iconik Employee — editing a recorded shift, converted to Ambient in AMB.13
//
//  The old `Form` presentation is GONE from this file.
//
//  THE CEILING NO LONGER LIES. This form accepted an entry up to 24 hours long,
//  enabled Save, and then threw — because `updateTimeEntry` routes a completed
//  entry through `validateManualEntry`, whose ceiling is 16. A 17-hour edit
//  passed every check the user could see and failed the one they could not. Both
//  numbers now come from `TimeClockRules`, which is compiled and run by
//  `scripts/test_timeclock_rules.sh` with a regression check on exactly this
//  case.
//
//  THE 30-DAY WINDOW IS EXPLAINED. Until now the only sentence in the app that
//  told a photographer why an entry had gone read-only lived on
//  `TimeEntryDetailView` — a screen with zero call sites, deleted by this phase.
//  It says so here, where the question gets asked, and it counts down: "editable
//  for 3 more days" while the window is closing.
//
//  ALSO CHANGED:
//    - A USER-VISIBLE TYPO IS GONE: "you can only edit the clock-in time and
//      notes while clocked-inly clocked in".
//    - Delete keeps its confirmation — it was the only one on the whole surface
//      — and the confirmation now names what is being destroyed.
//    - Save cannot be double-fired.
//    - A dead `onAppear` that read `availableSessions` before it was ever
//      loaded, and a dead auto-correct that rewrote the clock-out date behind
//      the user's back, are both gone.
//
//  WHAT DID NOT CHANGE: overlap detection still happens on Save. It is a server
//  round trip against the user's other entries, and running it on every picker
//  drag would be a data change rather than a restyle.

import SwiftUI

struct EditTimeEntryView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @Environment(\.presentationMode) private var presentationMode

    let timeEntry: TimeEntry

    @State private var start: Date
    @State private var end: Date
    @State private var sessions: [Session] = []
    @State private var selectedSessionId: String?
    @State private var sessionLoadFailed = false
    @State private var notes: String
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false
    @State private var failureMessage: String?

    init(timeEntry: TimeEntry, timeTrackingService: TimeTrackingService) {
        self.timeEntry = timeEntry
        self.timeTrackingService = timeTrackingService
        _start = State(initialValue: timeEntry.clockInTime ?? Date())
        _end = State(initialValue: timeEntry.clockOutTime ?? timeEntry.clockInTime ?? Date())
        _notes = State(initialValue: timeEntry.notes ?? "")
        _selectedSessionId = State(initialValue: timeEntry.sessionId)
    }

    private var isRunning: Bool { timeEntry.status == "clocked-in" }

    private var isEditable: Bool {
        TimeClockRules.isEditable(createdAt: timeEntry.createdAt, isRunning: isRunning)
    }

    private var daysRemaining: Int? {
        TimeClockRules.editWindowDaysRemaining(createdAt: timeEntry.createdAt, isRunning: isRunning)
    }

    /// A RUNNING entry is governed by the 48-hour start-time rule; a completed
    /// one by the recorded-shift rules. Two different writes inside
    /// `updateTimeEntry`, so two different refusals.
    private var refusal: TimeClockRefusal? {
        if isRunning {
            return TimeClockRules.refusalForActiveClockIn(newStart: start)
                ?? TimeClockRules.refusalForNotes(notes)
        }
        return TimeClockRules.refusalForRecordedShift(start: start, end: end)
            ?? TimeClockRules.refusalForNotes(notes)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(spacing: 16) {
                        TimeClockEditWindowNote(daysRemaining: daysRemaining, isRunning: isRunning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ambientCard(density: .compact,
                                         fill: .surface,
                                         border: .hairline(Color.primary.opacity(0.10)),
                                         fillWidth: true)

                        if isEditable {
                            editableBody
                        } else {
                            readOnlyBody
                        }
                    }
                    .padding(16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle(isEditable ? "Edit Entry" : "Time Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isEditable ? "Cancel" : "Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Delete this entry?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes \(TimeClockFormat.hoursAndMinutes(timeEntry.payrollSeconds)) from \(TimeEntry.dayLabel(for: timeEntry.date, now: Date(), calendar: .current)). It cannot be undone.")
            }
        }
        .task(id: timeEntry.date) { await loadSessions() }
    }

    // MARK: - Editable

    @ViewBuilder
    private var editableBody: some View {
        AmbientFormSection(title: "When", status: "") {
            VStack(spacing: 8) {
                DatePicker("Started", selection: $start, in: ...Date())
                // A running shift has no end to edit — that is what clocking out
                // is for. The shipped form hid the whole section; saying why is
                // better than a section that silently is not there.
                if !isRunning {
                    Divider()
                    DatePicker("Stopped", selection: $end, in: ...Date())
                }
            }
            .font(.subheadline)
        }

        TimeClockSummaryCard(title: isRunning ? "This shift becomes" : "You're about to record",
                             start: start,
                             end: isRunning ? Date() : end,
                             refusal: refusal,
                             crossesMidnight: !isRunning && !Calendar.current.isDate(start, inSameDayAs: end))

        sessionSection

        TimeClockNotesField(title: "Notes",
                            placeholder: "Notes for this entry…",
                            text: $notes)

        if let failureMessage {
            AmbientFailureCard(message: failureMessage, tint: .red, actionTitle: "Try again") {
                self.failureMessage = nil
                save()
            }
        }

        AmbientActionButton(title: "Save changes",
                            systemImage: "checkmark",
                            tint: TimeClockStyle.accent,
                            isLoading: isSaving,
                            isEnabled: refusal == nil) {
            save()
        }

        AmbientActionButton(title: "Delete entry",
                            systemImage: "trash",
                            role: .destructive,
                            isEnabled: !isSaving) {
            showingDeleteConfirmation = true
        }
    }

    // MARK: - Read-only

    @ViewBuilder
    private var readOnlyBody: some View {
        TimeClockSummaryCard(title: "Recorded",
                             start: timeEntry.clockInTime ?? Date(),
                             end: timeEntry.clockOutTime)

        if let name = timeEntry.sessionName, !name.isEmpty {
            AmbientNoteCard(title: "Session", text: name, accent: TimeClockStyle.accent)
        }

        if let entryNotes = timeEntry.notes, !entryNotes.isEmpty {
            AmbientNoteCard(title: "Notes", text: entryNotes, accent: .secondary)
        }
    }

    // MARK: - Session

    @ViewBuilder
    private var sessionSection: some View {
        if isRunning {
            // `updateTimeEntry` writes only start_time and notes for a running
            // entry, so offering a session picker here would be an affordance
            // whose value is discarded.
            EmptyView()
        } else if sessionLoadFailed {
            AmbientFailureCard(message: "Couldn't load that day's sessions. Your existing one is unchanged.") {
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
        guard !isRunning else { return }
        sessionLoadFailed = false
        guard let dateString = timeEntry.date,
              let day = Formatters.isoDate.date(from: dateString) else { return }
        do {
            let loaded = try await timeTrackingService.getSessionsForDate(day)
            guard !Task.isCancelled else { return }
            sessions = loaded.sorted { lhs, rhs in
                guard let a = lhs.startDate, let b = rhs.startDate else { return false }
                return a < b
            }
        } catch {
            guard !Task.isCancelled else { return }
            sessions = []
            sessionLoadFailed = true
        }
    }

    // MARK: - Writes

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        failureMessage = nil

        Task {
            do {
                try await timeTrackingService.updateTimeEntry(
                    entryId: timeEntry.id,
                    startTime: start,
                    endTime: isRunning ? (timeEntry.clockOutTime ?? end) : end,
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

    private func delete() {
        guard !isSaving else { return }
        isSaving = true
        failureMessage = nil

        Task {
            do {
                try await timeTrackingService.deleteTimeEntry(entryId: timeEntry.id)
                isSaving = false
                presentationMode.wrappedValue.dismiss()
            } catch {
                isSaving = false
                failureMessage = "Couldn't delete the entry. \(error.userFacingMessage)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
