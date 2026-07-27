//  TimeOffDetailView.swift
//  Iconik Employee — the time-off detail sheet, converted to Ambient in AMB.8
//
//  Reached ONLY from the Schedule, and it operates on a CALENDAR ENTRY — one per
//  DAY of a multi-day request — not on the request itself. That distinction was
//  invisible in the old screen and is why cancelling from one day cancels the
//  whole request with no warning. The design says which it is.
//
//  ⚠️ THE PERMISSION LOGIC IS UNCHANGED, DELIBERATELY, AND IT IS KNOWN TO BE WRONG.
//  `canModifyRequest` reads `UserDefaults "userID"` — a key NOTHING in this app
//  ever writes (verified by grepping every write; only reads exist, here and in
//  two other files, one of which already carries a comment saying so). So
//  `isOwnRequest` is always false and the Cancel button appears only for holders
//  of `timeOffApprovals` edit — while the SERVICE then rejects a manager's cancel
//  with "You can only cancel your own requests". The net effect is that a
//  photographer cannot cancel their own time off from the calendar, and a manager
//  who can see the button cannot use it.
//
//  It is left exactly as it was because fixing it CHANGES WHO CAN ACT on a
//  payroll-adjacent record, and the roadmap assigns that to TOF.1 precisely so a
//  style phase is not the thing that quietly moves an authorization boundary.
//  This is called out here, in AUDIT_ROADMAP.md, and in the closeout, rather than
//  silently carried. It also means: DO NOT read a missing Cancel button during
//  the device smoke as a regression this phase introduced.
//
//  "DELETE TIME OFF" IS GONE. It rendered only when the status was APPROVED and
//  called `cancelTimeOffRequest`, which rejects anything that is not pending or
//  under review — so every single press was a guaranteed 403. There is no delete
//  operation anywhere in `TimeOffService`; "delete" was a status flip. A button
//  whose every press fails is not a capability, and preserving it would be
//  preserving a defect for the sake of a parity checkbox.

import SwiftUI

struct TimeOffDetailView: View {
    let timeOffEntry: TimeOffCalendarEntry
    var onCancel: (() -> Void)?
    // `onDelete` is GONE, along with the "Delete Time Off" button it served.
    // Delete-first covers what a deletion ORPHANS, not just the file being
    // replaced — a parameter nothing can invoke is the same dead wiring in
    // smaller print. ScheduleView's call site is updated in this commit.

    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var timeOffService = TimeOffService.shared

    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingCancelConfirmation = false
    /// THE THIRD CALLER of `cancelTimeOffRequest`, and the third place the
    /// double-submit guard belongs. Same read-modify-write over the same cached
    /// balance as the other two.
    @State private var isCancelling = false

    private var tint: Color { TimeOffStyle.requests }

    private var statusDisplay: TimeOffStatusDisplay {
        TimeOffStatusDisplay.from(raw: timeOffEntry.status.rawValue)
    }

    private var reasonDisplay: TimeOffReasonDisplay {
        TimeOffReasonDisplay.from(raw: timeOffEntry.reason.rawValue)
    }

    /// Preserved verbatim from the shipped screen, including the `"userID"` read.
    /// See the file header — changing it is TOF.1's call, not a restyle's.
    private var canModifyRequest: Bool {
        let currentUserId = UserDefaults.standard.string(forKey: "userID") ?? ""
        let isOwnRequest = timeOffEntry.photographerId == currentUserId
        return isOwnRequest || Permissions.has("timeOffApprovals", level: .edit)
    }

    /// The full request behind this day, when the service happens to hold it.
    /// It often does not: this screen never starts a listener, and its presenter
    /// (ScheduleView) loads time off through `getTimeOffForCalendar`, which does
    /// not populate `timeOffRequests`. So the span note degrades honestly rather
    /// than asserting a day count it cannot know.
    private var backingRequest: TimeOffRequest? {
        timeOffService.timeOffRequests.first { $0.id == timeOffEntry.requestId }
    }

    /// Only when the backing request is in memory — the calendar entry itself
    /// carries no duration. Empty rather than invented when it is not.
    private var durationSuffix: String {
        backingRequest?.cardModel.durationLabel ?? ""
    }

    private var timeLabel: String {
        guard timeOffEntry.isPartialDay else { return "Full Day" }
        // Not "Full Day" — see TimeOffPresentation.presentedTimeLabel.
        guard let start = TimeOfDay(timeOffEntry.startTime),
              let end = TimeOfDay(timeOffEntry.endTime) else { return "Time not set" }
        return "\(start.displayString) – \(end.displayString)"
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: tint, intensity: 0.7)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        hero
                        detailRows
                        spanNote
                        cancelButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Time Off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .alert("Time Off Request", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .alert("Cancel Time Off Request", isPresented: $showingCancelConfirmation) {
                Button("Cancel Request", role: .destructive) { cancelRequest() }
                Button("Keep Request", role: .cancel) { }
            } message: {
                Text("Are you sure you want to cancel this time off request? This action cannot be undone.")
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: reasonDisplay.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(reasonDisplay.color)
                Text(reasonDisplay.label).font(.headline)
                Spacer(minLength: 8)
                // ONE status rendering. The old screen printed
                // `status.rawValue.capitalized` here, which is where the shipped
                // "Underreview" came from.
                AmbientBadge(text: statusDisplay.label,
                             systemImage: statusDisplay.symbol,
                             tint: statusDisplay.color)
            }
            Text(Formatters.longDate.string(from: timeOffEntry.date))
                .font(.system(size: 22, weight: .bold))
            // The mockup drew "time · duration". Dropping the duration lost the
            // one number that says how much time off this actually is.
            Text(durationSuffix.isEmpty ? timeLabel : "\(timeLabel) · \(durationSuffix)")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .ambientCard(density: .hero, state: .highlighted, glow: tint, fillWidth: true)
    }

    // MARK: - Rows

    private var detailRows: some View {
        VStack(spacing: 0) {
            TimeOffDetailRow(label: "Photographer",
                             value: timeOffEntry.photographerName.isEmpty
                                 ? "Unknown"
                                 : timeOffEntry.photographerName)
            Divider()
            TimeOffDetailRow(label: "Type",
                             value: timeOffEntry.isPartialDay ? "Partial day request" : "Full day request")
            // The mockup drew PTO hours here. `TimeOffCalendarEntry` has no PTO
            // fields, so it is drawn only when the backing request is loaded —
            // shown when known, absent when not, never guessed.
            if let request = backingRequest, request.isPaidTimeOff, let hours = request.ptoHoursRequested {
                Divider()
                TimeOffDetailRow(label: "PTO hours", value: String(format: "%.1f", hours))
            }
            // The notes row is OMITTED ENTIRELY when empty — the app's real
            // behaviour, and better than an empty labelled row.
            if !timeOffEntry.notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").font(.subheadline).foregroundStyle(.secondary)
                    Text(timeOffEntry.notes)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// The thing the old screen never said: this is ONE DAY of a request, and
    /// cancelling here cancels all of it.
    ///
    /// The precise day count is shown only when the backing request is actually in
    /// memory. Otherwise the note states the consequence without inventing a
    /// number — the consequence is true either way, and a wrong count on a
    /// destructive confirmation is worse than no count.
    @ViewBuilder
    private var spanNote: some View {
        if let request = backingRequest, request.presentedSpan.dayCount > 1 {
            AmbientNoteCard(
                title: "Part of a longer request",
                text: "This is one day of a \(request.presentedSpan.dayCount)-day request (\(request.cardModel.dateLabel)). Cancelling here cancels all \(request.presentedSpan.dayCount) days.",
                accent: .orange,
                density: .compact)
        } else if timeOffEntry.status == .pending {
            AmbientNoteCard(
                title: "This cancels the whole request",
                text: "Time off is stored as one request across all its days. Cancelling from this day cancels every day the request covers.",
                accent: .orange,
                density: .compact)
        }
    }

    // MARK: - Actions

    /// Conditional on pending, as today.
    @ViewBuilder
    private var cancelButton: some View {
        if canModifyRequest && timeOffEntry.status == .pending {
            Button {
                showingCancelConfirmation = true
            } label: {
                Label(isCancelling ? "Cancelling…" : "Cancel Request",
                      systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // ambient-allow: a control, not a card.
                    .background(Capsule().fill(Color.red.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(isCancelling)
        }
    }

    private func cancelRequest() {
        guard !isCancelling else { return }
        isCancelling = true
        Task {
            defer { isCancelling = false }
            do {
                try await timeOffService.cancelTimeOffRequest(requestId: timeOffEntry.requestId)
                await MainActor.run {
                    onCancel?()
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    // The old screen set two success messages it never displayed
                    // (it dismissed instead), so only failures ever surfaced. That
                    // is kept: a success dismisses, a failure says why.
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }
        }
    }
}
