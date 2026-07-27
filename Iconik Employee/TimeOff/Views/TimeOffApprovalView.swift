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
    /// Messages that arrived while something was presented. AN ARRAY, NOT A SLOT:
    /// three rapid approvals dropped the middle result, which can be a failed
    /// payroll write, and that contradicted the contract this queue exists for.
    @State private var queuedAlerts: [String] = []
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
            // SWIPE BETWEEN TABS, RESTORED. The shipped screen was a real
            // `TabView` with `PageTabViewStyle`, so the three queues could be
            // paged horizontally. The conversion replaced it with a button row and
            // dropped the gesture — a genuine capability loss that I recorded and
            // then neither restored nor declared, which is the "writing it down
            // felt like diligence and functioned as a decision to ship it" trap.
            // `highPriorityGesture` is deliberate: a parent DragGesture loses to
            // child Buttons, and this needs 12pt of travel so it cannot steal a tap.
            .highPriorityGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        let all = QueueTab.allCases
                        guard let i = all.firstIndex(of: tab) else { return }
                        let next = value.translation.width < 0 ? i + 1 : i - 1
                        guard all.indices.contains(next) else { return }
                        withAnimation(AmbientMotion.snappy) { tab = all[next] }
                        AmbientHaptics.selection()
                    })
        }
        .navigationTitle("Time Off Approvals")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $requestToDeny, onDismiss: {
            // A swipe-down does not run the toolbar's Cancel, so without this the
            // sentence typed about one photographer was pre-filled — and the
            // button pre-enabled — on the next one.
            denialReason = ""
            denialError = ""
        }) { request in
            denialSheet(request)
        }
        // Keyed on the request ID rather than the request: `TimeOffRequest` is not
        // Equatable, and the identity is the only part that matters here — whose
        // sheet is up, or none.
        .onChange(of: requestToDeny?.id) { newValue in
            // The sheet just closed and something was waiting to be said.
            // `!showingAlert` matters: the deny success path dismisses the sheet
            // AND raises its own alert in one transaction, so without this the
            // flush would immediately overwrite it.
            guard newValue == nil, !showingAlert, !queuedAlerts.isEmpty else { return }
            alertMessage = queuedAlerts.removeFirst()
            showingAlert = true
        }
        .alert("Time Off Management", isPresented: $showingAlert) {
            // Flushing from the alert's dismissal is what makes a message queued
            // behind ANOTHER alert reachable at all.
            Button("OK", role: .cancel) { flushQueuedAlert() }
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
                                // Clear on APPEAR, not only on dismiss: a failure
                                // that lands after the sheet closed would
                                // otherwise greet the next photographer's deny
                                // with the previous one's error.
                                .onAppear { denialError = "" }
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
                    // Dismissing mid-write is what stranded the confirmation.
                    .disabled(inFlight.contains(request.id))
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Same reason as the disabled Cancel: no swiping the sheet away while the
        // deny is in flight.
        .interactiveDismissDisabled(inFlight.contains(request.id))
    }

    // MARK: - Actions

    /// REDUNDANT BUT EXPLICIT — and the comment that used to sit here was WRONG,
    /// so the correction is kept rather than quietly deleted.
    ///
    /// A previous round asserted that "a `View` isolates `body`, not its methods",
    /// wrapped every post-`await` write in `MainActor.run` on that basis, and then
    /// filed a CRITICAL claiming the `defer` below was an unprotected write racing
    /// `body`. THAT WAS FALSE. SwiftUI's `View` protocol is itself `@MainActor`, so
    /// conformance isolates the WHOLE TYPE — every method and computed property,
    /// not just `body`. Verified with a compiler probe rather than reasoned about:
    /// an unannotated method on a `View` can call a `@MainActor` function, and the
    /// identical method on a non-`View` struct fails with
    /// "call to main actor-isolated global function in a synchronous nonisolated
    /// context". These methods were already isolated in every earlier commit, the
    /// `defer` was never unprotected, and the race described could not occur.
    ///
    /// The annotations are kept because stating the isolation is better than
    /// relying on a protocol's inference two files away — but they FIX NOTHING,
    /// and a comment claiming otherwise is the same defect as a commit message
    /// describing a change that did not land.
    @MainActor
    private func approveRequest(_ request: TimeOffRequest) {
        guard !inFlight.contains(request.id) else { return }
        inFlight.insert(request.id)
        Task {
            defer { inFlight.remove(request.id) }
            // BOTH BRANCHES GO THROUGH `raise`, AND NEITHER ASSUMES SUCCESS.
            //
            // This block previously set `alertMessage` in the do and the catch and
            // then called `raise("Request approved successfully")` UNCONDITIONALLY
            // beneath both — so a FAILED approval overwrote the error and told the
            // manager a payroll write had succeeded when nothing had been written.
            // It got there because I applied the fix with a string replacement that
            // silently did not match, and committed without re-reading the region.
            // Judge a fix by reading what the code does, not by trusting the edit.
            do {
                try await timeOffService.approveTimeOffRequest(requestId: request.id)
                raise("Request approved successfully")
            } catch {
                raise(error.localizedDescription)
            }
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
                // REVERTED to raising the alert directly. Routing the
                // confirmation through `onDismiss` was worse, not better: the
                // toolbar Cancel had no in-flight guard, so dismissing while the
                // write was in flight consumed the (still empty) message, and the
                // success branch then set `requestToDeny = nil` when it was
                // ALREADY nil — no presentation change, no second `onDismiss`, no
                // confirmation ever. Worse, the message stayed set and fired
                // "Request denied successfully" the next time the manager backed
                // out of an unrelated deny sheet.
                //
                // Here the sheet is dismissed in the same transaction and the
                // alert is raised on a presenter that is no longer presenting.
                // Cancel is now disabled while a write is in flight, so the
                // dismiss-mid-write path that broke this cannot be entered.
                requestToDeny = nil
                denialReason = ""
                denialError = ""
                // ANYTHING QUEUED IS KEPT, NOT DROPPED. I nulled it here to stop
                // the `.onChange` flush overwriting this confirmation — and that
                // DESTROYED a different card's result. A failed approve on card B,
                // queued while this sheet was open, is not superseded by a deny on
                // card A: different row, different photographer, different payroll
                // write. Discarding it is the exact defect the round before this
                // one was titled for. The `!showingAlert` guard on the flush is
                // what protects this confirmation; the queue is flushed from the
                // alert's own OK button instead.
                alertMessage = "Request denied successfully"
                showingAlert = true
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
                raise("Request placed in review")
            } catch {
                raise(error.localizedDescription)
            }
        }
    }

    /// Shows the message now if nothing is presented, otherwise HOLDS it until the
    /// deny sheet closes — queued, never discarded, because a dropped message here
    /// is a failed payroll write nobody is told about.
    ///
    /// There is no `success:` parameter. The first version took one and never read
    /// it, which is how the caller above came to pass `success: true` on a failure
    /// path without anything complaining. A parameter that cannot change behaviour
    /// is a comment that looks like code.
    /// Shows whatever was held back, once nothing is in the way. Never drops it.
    @MainActor
    private func flushQueuedAlert() {
        guard !queuedAlerts.isEmpty else { return }
        alertMessage = queuedAlerts.removeFirst()
        DispatchQueue.main.async { showingAlert = true }
    }

    @MainActor
    private func raise(_ message: String) {
        alertMessage = message
        // The same enumeration as the list screen: a message shows only when
        // NOTHING is presented over this view. Two surfaces here — the deny sheet
        // and a result alert already up.
        if requestToDeny == nil && !showingAlert {
            showingAlert = true
        } else {
            queuedAlerts.append(message)
        }
    }
}
