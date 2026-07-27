//  TimeOffApprovalView.swift
//  Iconik Employee — the manager queue, converted to Ambient in AMB.8
//
//  THE DESIGN'S THIRD CLAIM: the queue says on screen that it is a queue.
//  Pending and In Review sort OLDEST FIRST, deliberately reversing the employee
//  list, because a manager works a queue from the top. That was real workflow
//  knowledge buried in a bare `.sorted` call in a view body, where the next
//  person to touch this screen would have "fixed" the inconsistency. It now runs
//  through `TimeOffOrder`, which is compiled and tested, and the screen says it.
//
//  ⚠️ THIS SCREEN STILL HAS NO PERMISSION CHECK, AND THAT IS DELIBERATE HERE.
//  `TimeOffService.canManageRequests()` exists, does the right check against
//  `timeOffApprovals`, and has zero callers; the only gate today is the
//  visibility of a row in AllFeaturesView, which is itself gated on a DIFFERENT
//  area code (`users`). The lab mockup draws the locked-out state and marks it
//  PROPOSED for exactly this reason. Wiring it is an AUTHORIZATION change on a
//  payroll-adjacent surface and it belongs to TOF.1 — a style phase must not be
//  the thing that quietly closes an authorization hole, and it must not be the
//  thing that quietly widens one either. Tracked in AUDIT_ROADMAP.md, TOF.1.

import SwiftUI

struct TimeOffApprovalView: View {
    @StateObject private var timeOffService = TimeOffService.shared

    @State private var tab: QueueTab = .pending
    @State private var requestToDeny: TimeOffRequest?
    @State private var denialReason = ""
    /// Shown inside the denial sheet — see `denyRequest`.
    @State private var denialError = ""
    /// Raised from `onDismiss`, after the sheet has actually gone — see `denyRequest`.
    @State private var pendingSuccessMessage: String?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    /// THE DOUBLE-SUBMIT GUARD. The OLD screen swapped the whole list for a
    /// spinner whenever `TimeOffService.isLoading` was true, so a second tap on
    /// Approve was physically impossible. This conversion changed the loading test
    /// to `isLoading && requests.isEmpty` — which is never true on a screen that
    /// HAS rows, i.e. every screen where these buttons exist — and so deleted that
    /// guard without noticing.
    ///
    /// It matters because the write is not idempotent: `approveTimeOffRequest` has
    /// no status guard, and `PTOService.usePTOHours` is a read-modify-write that
    /// serves from a 300-second cache AND writes the debited balance back into it.
    /// Two taps two seconds apart on a 48-hour request debit 96 hours.
    @State private var inFlight: Set<String> = []

    private enum QueueTab: String, CaseIterable, Identifiable {
        case pending = "Pending"
        case inReview = "In Review"
        case history = "History"
        var id: String { rawValue }
    }

    private var tint: Color { TimeOffStyle.approvals }

    // MARK: - The three queues
    //
    // All three filter `timeOffRequests` directly rather than reading the
    // service's pre-filtered `pendingRequests`. That array is rebuilt by
    // `updateFilteredLists`, which returns early when the user id is nil — so it
    // can hold the previous contents while `timeOffRequests` is fresh. Filtering
    // the source array cannot go stale that way.

    /// OLDEST FIRST. A manager works a queue.
    private var pending: [TimeOffRequest] {
        TimeOffOrder.managerQueue(
            timeOffService.timeOffRequests.filter { $0.status == TimeOffStatus.pending.rawValue },
            createdAt: { $0.createdAt })
    }

    private var inReview: [TimeOffRequest] {
        TimeOffOrder.managerQueue(
            timeOffService.timeOffRequests.filter { $0.status == TimeOffStatus.underReview.rawValue },
            createdAt: { $0.createdAt })
    }

    /// History sorts by when it was ACTIONED, newest first — not by when it was
    /// filed. The two orders are genuinely different and a test asserts it.
    private var history: [TimeOffRequest] {
        TimeOffOrder.history(
            timeOffService.timeOffRequests.filter {
                $0.status != TimeOffStatus.pending.rawValue
                    && $0.status != TimeOffStatus.underReview.rawValue
            },
            actionedAt: { $0.updatedAt })
    }

    private var queue: [TimeOffRequest] {
        switch tab {
        case .pending: return pending
        case .inReview: return inReview
        case .history: return history
        }
    }

    /// History DELIBERATELY carries no badge — the app passes none, and a count on
    /// a history tab is a number nobody acts on.
    private func badge(_ tab: QueueTab) -> Int {
        switch tab {
        case .pending: return pending.count
        case .inReview: return inReview.count
        case .history: return 0
        }
    }

    private var hasFailed: Bool { !timeOffService.errorMessage.isEmpty }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: tint, intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    tabBar
                    queueOrderNote
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            // NO .ambientNoBounceWhenShort() here: it is scrollBounceBehavior
            // (.basedOnSize), which removes the very bounce .refreshable needs, so
            // pull-to-refresh silently died whenever the content fit on screen.
            .refreshable { await timeOffService.refreshRequests() }
        }
        .navigationTitle("Time Off Approvals")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $requestToDeny, onDismiss: {
            // A swipe-down does not run the toolbar's Cancel, so without this the
            // sentence typed about one photographer was pre-filled — and the
            // button pre-enabled — on the next one.
            denialReason = ""
            denialError = ""
            if let message = pendingSuccessMessage {
                pendingSuccessMessage = nil
                alertMessage = message
                showingAlert = true
            }
        }) { request in
            denialSheet(request)
        }
        .alert("Time Off Management", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .task { await timeOffService.startListeningToRequests() }
        .onDisappear {
            Task { await timeOffService.stopListening() }
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(QueueTab.allCases) { option in
                Button {
                    withAnimation(AmbientMotion.snappy) { tab = option }
                    AmbientHaptics.selection()
                } label: {
                    HStack(spacing: 5) {
                        Text(option.rawValue).font(.caption.weight(.semibold))
                        if badge(option) > 0 {
                            Text("\(badge(option))")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.red))
                        }
                    }
                    .foregroundStyle(tab == option ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    // ambient-allow: a tab control, not a container.
                    .background(Capsule().fill(tab == option
                                               ? AnyShapeStyle(tint)
                                               : AnyShapeStyle(.ultraThinMaterial)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// If the design does not say the order out loud, the next person to touch
    /// this screen will "fix" it to newest-first.
    @ViewBuilder
    private var queueOrderNote: some View {
        if tab != .history {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line").font(.caption2.weight(.bold))
                Text("Oldest first — work the queue from the top")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if hasFailed && timeOffService.timeOffRequests.isEmpty {
            // "All Caught Up!" over a failed fetch is a lie a manager would act on.
            TimeOffFailurePanel(title: "Couldn't load the queue",
                                message: timeOffService.errorMessage.isEmpty
                                    ? "The server didn't answer. Requests are safe — this screen just can't show them right now."
                                    : timeOffService.errorMessage,
                                tint: tint) {
                Task { await timeOffService.refreshRequests() }
            }
        } else {
            if hasFailed { failureBanner }
            if timeOffService.isLoading && timeOffService.timeOffRequests.isEmpty {
                loadingState
            } else if queue.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var failureBanner: some View {
        TimeOffFailureBanner(message: timeOffService.errorMessage, tint: tint) {
            Task { await timeOffService.refreshRequests() }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading requests...").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    /// Three distinct empty states with their own icons, as today.
    @ViewBuilder
    private var emptyState: some View {
        switch tab {
        case .pending:
            AmbientEmptyState(title: "All Caught Up!",
                              message: "There are no pending time off requests to review.",
                              systemImage: "checkmark.circle")
        case .inReview:
            AmbientEmptyState(title: "No Requests In Review",
                              message: "There are no time off requests currently under review.",
                              systemImage: "magnifyingglass")
        case .history:
            AmbientEmptyState(title: "No History",
                              message: "No time off requests have been processed yet.",
                              systemImage: "clock.arrow.circlepath")
        }
    }

    private var list: some View {
        LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
            ForEach(Array(queue.enumerated()), id: \.element.id) { index, request in
                VStack(alignment: .leading, spacing: 4) {
                    // Position in the queue — the thing FIFO order exists to
                    // communicate, and which nothing on this screen showed before.
                    if tab != .history {
                        Text("\(index + 1) of \(queue.count) · waiting \(TimeOffOrder.waitingDays(since: request.createdAt)) days")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    TimeOffRequestCard(
                        model: request.cardModel,
                        showsActions: tab != .history,
                        managerActions: true,
                        showsPhotographer: true,
                        actionsBusy: inFlight.contains(request.id),
                        onApprove: { approveRequest(request) },
                        onDeny: { requestToDeny = request },
                        // "Put in Review" is wired ONLY on the Pending tab,
                        // deliberately not on In Review — as today.
                        onReview: tab == .pending ? { putRequestInReview(request) } : nil)
                }
                .ambientScrollFade()
            }
        }
    }

    // MARK: - Denial

    /// THE LIVE APP COLLECTS THE REASON IN AN ALERT WITH AN INLINE FIELD. This is
    /// a sheet instead, and that is a deliberate change with a reason: an alert
    /// cannot show WHOSE request is being denied, cannot say the reason is
    /// required until you have already failed, and cannot say the person will read
    /// it. All three matter, because this text is the only thing the photographer
    /// is ever told about why their time off was refused.
    ///
    /// It also closes a real defect in the alert version: `denyRequest` guarded an
    /// empty reason and raised an error alert, but the guard ran AFTER the deny
    /// alert had already dismissed — so the manager had to reopen it and retype.
    /// Here Deny is simply disabled until there is a reason.
    private func denialSheet(_ request: TimeOffRequest) -> some View {
        let model = request.cardModel
        let trimmed = denialReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return NavigationView {
            ZStack {
                AmbientBackdrop(tint: .red, intensity: 0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Denying \(model.photographer)'s request")
                                .font(.headline)
                            Text("\(model.dateLabel) · \(model.durationLabel) · \(model.reason.label)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .ambientCard(density: .roomy, fillWidth: true)

                        VStack(alignment: .leading, spacing: 6) {
                            AmbientSectionTitle("Reason", trailing: "required")
                            TextEditor(text: $denialReason)
                                .frame(minHeight: 110)
                                .font(.subheadline)
                                .scrollContentBackground(.hidden)
                                .ambientCard(density: .compact, fillWidth: true)
                            Text("\(model.photographer) will see this on their own list. Say enough that they can plan around it.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            AmbientHaptics.impact(.medium)
                            denyRequest(request)
                        } label: {
                            Text(inFlight.contains(request.id) ? "Denying…" : "Deny Request")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                // ambient-allow: a control, not a card.
                                .background(Capsule().fill(trimmed.isEmpty || inFlight.contains(request.id) ? Color.gray : Color.red))
                        }
                        .buttonStyle(.plain)
                        .disabled(trimmed.isEmpty || inFlight.contains(request.id))

                        if !denialError.isEmpty {
                            TimeOffInlineNote(text: denialError,
                                              icon: "exclamationmark.triangle.fill",
                                              tint: .orange)
                        } else if trimmed.isEmpty {
                            Text("A reason is required before this can be sent.")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Deny")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        requestToDeny = nil
                        denialReason = ""
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    /// @MainActor ON THE METHOD, not `MainActor.run` at each write.
    ///
    /// The fix round wrapped every post-`await` state write in `MainActor.run`
    /// on the correct rationale that a `View` isolates `body`, not its methods —
    /// and then released the in-flight guard in a `defer`, which runs in that same
    /// nonisolated closure. So the ONE write that could drop the guard was the one
    /// the fix did not protect, and `inFlight` is a `Set` that `body` reads
    /// concurrently: a lost insert re-arms the double-tap this guard exists to
    /// stop. Isolating the method makes the `Task` inherit MainActor, so every
    /// write in it — including the `defer` — is on the main actor by construction
    /// rather than by remembering.
    @MainActor
    private func approveRequest(_ request: TimeOffRequest) {
        guard !inFlight.contains(request.id) else { return }
        inFlight.insert(request.id)
        Task {
            defer { inFlight.remove(request.id) }
            do {
                try await timeOffService.approveTimeOffRequest(requestId: request.id)
                alertMessage = "Request approved successfully"
            } catch {
                alertMessage = error.localizedDescription
            }
            showingAlert = true
        }
    }

    @MainActor
    private func denyRequest(_ request: TimeOffRequest) {
        let reason = denialReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, !inFlight.contains(request.id) else { return }
        // Cleared before the attempt, not only on success: otherwise a retry
        // leaves the previous error on screen for its whole duration.
        denialError = ""
        inFlight.insert(request.id)
        Task {
            defer { inFlight.remove(request.id) }
            do {
                try await timeOffService.denyTimeOffRequest(requestId: request.id, denialReason: reason)
                // MEDIUM 5 — the fix round moved the FAILURE out of the alert
                // because an alert raised on a view that is presenting a sheet
                // does not appear, and then left the SUCCESS alert doing exactly
                // that in the same transaction as the dismissal. The reasoning was
                // applied to one branch and not the other. The confirmation is
                // handed to `onDismiss` instead, so it fires after the sheet has
                // actually gone.
                pendingSuccessMessage = "Request denied successfully"
                requestToDeny = nil
                denialReason = ""
                denialError = ""
            } catch {
                // NOT an alert. The sheet is still up, and an alert raised on the
                // view that is presenting a sheet does not appear — so the old
                // arrangement made a failed deny completely silent, and the
                // manager's only feedback was to tap Deny again.
                denialError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func putRequestInReview(_ request: TimeOffRequest) {
        guard !inFlight.contains(request.id) else { return }
        inFlight.insert(request.id)
        Task {
            defer { inFlight.remove(request.id) }
            do {
                try await timeOffService.putTimeOffRequestInReview(requestId: request.id)
                alertMessage = "Request placed in review"
            } catch {
                alertMessage = error.localizedDescription
            }
            showingAlert = true
        }
    }
}
