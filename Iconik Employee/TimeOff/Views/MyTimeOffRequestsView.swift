//  MyTimeOffRequestsView.swift
//  Iconik Employee — "My Time Off", converted to Ambient in AMB.8
//
//  The old screen and its 213-line hand-rolled `TimeOffRequestCard` are GONE from
//  this file, not left beside the new one. The card now lives in
//  `TimeOff/TimeOffKit.swift`, which the design lab's mockup also draws with, so
//  the mockup and this screen cannot diverge.
//
//  WHAT THIS SCREEN GAINED, and why each is in scope for a design phase:
//    - THE BALANCE LEADS (the design's first claim). The only dedicated balance
//      screen lived in Settings; the number you need in order to decide anything
//      about time off was in a different feature. Settings keeps its route.
//    - AN ERROR STATE. `TimeOffService.errorMessage` has always existed, has
//      always been set on failure, and had NEVER been read by any view — so a
//      failed load rendered as "You haven't submitted any time off requests yet."
//      That is the shape that hid Chat for a year, and drawing it is a view
//      change, not a service change.
//
//  WHAT IT DELIBERATELY DID NOT GAIN, each named because the design audit was
//  right that leaving them unsaid is how a silent omission becomes permanent:
//
//    - AN ENTRY TO THE APPROVALS QUEUE. The lab mockup carries one so the operator
//      could reach the other mockup, and that mockup's own comment says surfacing
//      it for real is a navigation question rather than a design one. D3 says
//      navigation stays as it is.
//
//    - TAPPABLE CARDS. The mockup wraps each card in a Button that pushes the
//      detail screen. The real detail screen takes a `TimeOffCalendarEntry` — one
//      per DAY, built by the Schedule — not a request, so making these rows push
//      it would mean inventing a second entry point into a screen that does not
//      accept what this list holds. That is a navigation change (D3) and a data
//      change, not a restyle.
//
//    - THE OFFLINE STATE. The mockup draws one and marks it PROPOSED, and it is
//      proposed for a concrete reason: nothing in this data layer can tell
//      "offline" from "the request failed". TimeOffService has no reachability
//      check and no cache to serve stale rows from, so an honest offline state
//      needs both — which is the OFF arc's work, not a style phase's. Drawing it
//      without them would mean labelling every failure "offline", which is the
//      same class of confident-wrong-answer this phase exists to remove.

import SwiftUI

struct MyTimeOffRequestsView: View {
    @StateObject private var timeOffService = TimeOffService.shared
    private let ptoService = PTOService.shared

    @State private var selectedStatus: TimeOffStatus?
    @State private var showingNewRequest = false
    @State private var editingRequest: TimeOffRequest?
    @State private var requestToCancel: TimeOffRequest?
    @State private var showingCancelAlert = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    /// Held while ANYTHING is presented, flushed when nothing is — see
    /// `isPresentingSomething`.
    ///
    /// AN ARRAY, NOT A SLOT. A single slot silently dropped the middle of three
    /// results, which contradicted the "queued, never discarded" contract this
    /// queue was built to honour — and the dropped one can be a failed payroll
    /// write.
    @State private var queuedAlerts: [String] = []
    /// THE DOUBLE-SUBMIT GUARD, on this screen too.
    ///
    /// It was added to the approvals queue and not here, which is the instance
    /// being fixed instead of the class for the fifth round running.
    /// `cancelTimeOffRequest` reaches `PTOService.releasePTOHours` — a
    /// read-modify-write that serves from a 300-second cache AND writes the
    /// released balance back into it — and its own status guard reads the LOCAL
    /// array, so a second tap inside the refresh window still sees "pending" and
    /// passes. Two taps on a 16-hour request release 32 hours of reservation and
    /// the balance is overstated from then on.
    @State private var inFlight: Set<String> = []
    @State private var destination: TimeOffDestination?

    // The balance is loaded here so the lead card can show it. Nil while loading;
    // `balanceFailed` is a SEPARATE state, because a failure must never render as
    // "0.0 hours available".
    @State private var balance: PTOBalance?
    @State private var balanceFailed = false

    /// One enum, one `.ambientPush` — the AMB.3 rule. Two stacked
    /// `NavigationLink(isActive:)` is the shape that produced AMB.1's dead tap.
    private enum TimeOffDestination: String, Identifiable {
        case balance
        var id: String { rawValue }
    }

    private var tint: Color { TimeOffStyle.requests }

    /// Newest first — the order the fetch already returns (`created_at`
    /// descending). Named through the tested rule type so the contrast with the
    /// manager queue's FIFO order is explicit rather than an accident of two
    /// different `.sorted` calls in two different files.
    private var requests: [TimeOffRequest] {
        let all = TimeOffOrder.employeeList(timeOffService.myRequests, createdAt: { $0.createdAt })
        guard let selectedStatus else { return all }
        return all.filter { $0.status == selectedStatus.rawValue }
    }

    private var hasFailed: Bool { !timeOffService.errorMessage.isEmpty }

    /// EVERY PRESENTATION SURFACE ON THIS SCREEN, ENUMERATED ONCE.
    ///
    /// An alert raised while something else is presented does not appear. Five
    /// rounds of this phase extended the guard one surface at a time — the deny
    /// sheet, then the two list sheets — and each round the audit found the
    /// surface that had not been added yet. The project already has the rule for
    /// this shape: a feedback loop is a STATE MACHINE, enumerate it once. These
    /// are the four things that can be on screen over this view. If a fifth is
    /// ever added it belongs in this list and nowhere else.
    private var isPresentingSomething: Bool {
        showingNewRequest                 // the new-request sheet
            || editingRequest != nil      // the edit sheet
            || showingCancelAlert         // the cancel confirmation alert
            || showingAlert               // a result alert already up
            || destination != nil         // pushed to the PTO balance screen
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: tint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    balanceLead
                    TimeOffPrimaryButton(title: "New Time Off Request",
                                         systemImage: "plus.circle.fill",
                                         tint: tint) { showingNewRequest = true }
                    chipRow
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            // NO .ambientNoBounceWhenShort() here: it is scrollBounceBehavior
            // (.basedOnSize), which removes the very bounce .refreshable needs, so
            // pull-to-refresh silently died whenever the content fit on screen.
            .refreshable { await refresh() }
        }
        .navigationTitle("My Time Off")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: destination) { newValue in
            // The push popped. Anything queued while it was up would otherwise sit
            // there until an unrelated sheet happened to dismiss.
            if newValue == nil { flushQueuedAlert() }
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .balance: PTOBalanceView(isPushed: true)
            }
        }
        .sheet(isPresented: $showingNewRequest, onDismiss: flushQueuedAlert) {
            TimeOffRequestView(timeOffService: timeOffService)
        }
        .sheet(item: $editingRequest, onDismiss: flushQueuedAlert) { request in
            TimeOffRequestView(timeOffService: timeOffService, editingRequest: request)
        }
        .alert("Cancel Request", isPresented: $showingCancelAlert) {
            // BOTH buttons flush. This alert was added to `isPresentingSomething`
            // and NOT to the flush set, so a result that landed while it was up
            // stranded — and leaving the screen destroyed it. The fifth surface
            // got into the queue enumeration and not into the drain, which is the
            // same half-swept class this round is named for.
            Button("Cancel Request", role: .destructive) {
                if let requestToCancel { cancelRequest(requestToCancel) } else { flushQueuedAlert() }
            }
            Button("Keep Request", role: .cancel) {
                requestToCancel = nil
                flushQueuedAlert()
            }
        } message: {
            Text("Are you sure you want to cancel this time off request? This action cannot be undone.")
        }
        .alert("Time Off", isPresented: $showingAlert) {
            // Flushing from the alert's own dismissal is what makes a queued
            // message reachable when the thing blocking it was ANOTHER alert.
            Button("OK", role: .cancel) { flushQueuedAlert() }
        } message: {
            Text(alertMessage)
        }
        .task {
            await timeOffService.startListeningToRequests()
            await loadBalance()
        }
        .onDisappear {
            // NOT WHEN WE ARE PUSHING. `ambientPush` is a real NavigationLink, so
            // this fires when the PTO balance screen covers us — and tearing down
            // the shared realtime channel there raced the resubscribe on the way
            // back. A regression introduced by adding that push in the first place.
            guard destination == nil else { return }
            Task { await timeOffService.stopListening() }
        }
    }

    // MARK: - The balance, which today lives only in Settings

    private var balanceLead: some View {
        TimeOffBalanceLead(available: balance?.availableBalance,
                           pendingHours: balance?.pendingBalance,
                           failed: balanceFailed,
                           tint: tint) {
            destination = .balance
        }
    }

    // MARK: - Chips

    /// All six are ALWAYS rendered, even at zero — the app's real behaviour, and
    /// the deliberate opposite of the call AMB.5 made for Tasks. A status you can
    /// never see is a status you forget you can be in. Only the badge is
    /// conditional.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TimeOffChip(label: "All",
                            count: timeOffService.myRequests.count,
                            tint: .secondary,
                            selected: selectedStatus == nil) {
                    withAnimation(AmbientMotion.snappy) { selectedStatus = nil }
                    AmbientHaptics.selection()
                }
                ForEach(TimeOffStatus.filterOptions, id: \.self) { status in
                    TimeOffChip(label: status.displayName,
                                count: timeOffService.getMyRequests(status: status).count,
                                tint: TimeOffStatusDisplay.from(raw: status.rawValue).color,
                                selected: selectedStatus == status) {
                        withAnimation(AmbientMotion.snappy) { selectedStatus = status }
                        AmbientHaptics.selection()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    // MARK: - The list and its states

    @ViewBuilder
    private var content: some View {
        if hasFailed && timeOffService.myRequests.isEmpty {
            // A FAILURE IS NOT AN EMPTY LIST. Rendering the empty state underneath
            // would restate the exact lie this screen shipped with for years. The
            // mockup drew a full PANEL for this case, not a banner.
            TimeOffFailurePanel(title: "Couldn't load your requests",
                                message: timeOffService.errorMessage.isEmpty
                                    ? "The server didn't answer. Your requests are safe — this screen just can't show them right now."
                                    : timeOffService.errorMessage,
                                tint: tint) {
                Task { await refresh() }
            }
        } else {
            if hasFailed {
                // A failed REFRESH over a list we already have: say so, keep the
                // rows. Silently showing stale data is how a broken realtime feed
                // goes unnoticed.
                failureBanner
            }
            if timeOffService.isFetchingList && timeOffService.myRequests.isEmpty {
                loadingState
            } else if requests.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var failureBanner: some View {
        TimeOffFailureBanner(message: timeOffService.errorMessage, tint: tint) {
            Task { await refresh() }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading your requests...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    /// FIVE DISTINCT EMPTY STATES, as the app has always had: one unfiltered and
    /// one per status. The filtered ones carry NO call to action, because "create
    /// your first request" is wrong when you have six and are looking at a filter.
    @ViewBuilder
    private var emptyState: some View {
        if let selectedStatus {
            AmbientEmptyState(
                title: "No \(selectedStatus.displayName) Requests",
                message: "You don't have any \(selectedStatus.displayName.lowercased()) requests.",
                systemImage: "line.3.horizontal.decrease.circle")
        } else {
            AmbientEmptyState(
                title: "No Time Off Requests",
                message: "You haven't submitted any time off requests yet.",
                systemImage: "calendar.badge.clock",
                actionTitle: "Create First Request",
                actionIcon: "plus.circle.fill",
                action: { showingNewRequest = true },
                actionTint: tint)
        }
    }

    private var list: some View {
        LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
            ForEach(requests) { request in
                TimeOffRequestCard(
                    model: request.cardModel,
                    showsActions: true,
                    actionsBusy: inFlight.contains(request.id),
                    onEdit: { editingRequest = request },
                    onCancel: {
                        requestToCancel = request
                        showingCancelAlert = true
                    })
                .ambientScrollFade()
            }
        }
    }

    // MARK: - Actions

    /// Shows whatever was held back, once nothing is in the way. Never drops it:
    /// a queued message is the outcome of a payroll write, and the one thing this
    /// phase has repeatedly proved is that a silently discarded failure is worse
    /// than a late one.
    private func flushQueuedAlert() {
        guard !queuedAlerts.isEmpty else { return }
        // Oldest first, one per dismissal — the alert's OK button calls back in.
        alertMessage = queuedAlerts.removeFirst()
        // A tick, so the alert that just dismissed is fully gone before the next
        // is raised on the same presenter.
        DispatchQueue.main.async { showingAlert = true }
    }

    private func refresh() async {
        await timeOffService.refreshRequests()
        await loadBalance()
    }

    private func loadBalance() async {
        let userId = UserManager.shared.getCurrentUserIDUnified()
        let organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        guard let userId, !userId.isEmpty, !organizationID.isEmpty else {
            await MainActor.run {
                balance = nil
                balanceFailed = true
            }
            return
        }
        do {
            let loaded = try await ptoService.getPTOBalance(userId: userId, organizationID: organizationID)
            await MainActor.run {
                balance = loaded
                balanceFailed = false
            }
        } catch {
            // Recorded as a failure rather than left nil, so the lead card shows
            // "Balance unavailable" instead of a permanent spinner.
            await MainActor.run {
                balance = nil
                balanceFailed = true
            }
        }
    }

    private func cancelRequest(_ request: TimeOffRequest) {
        guard !inFlight.contains(request.id) else { return }
        inFlight.insert(request.id)
        Task {
            defer { inFlight.remove(request.id) }
            // A LOCAL, not the shared `alertMessage`. `inFlight` is keyed per
            // request, so two cards can be cancelling at once; writing the text to
            // shared state in one hop and reading it back in another let A append
            // B's message — a failed cancel becoming a duplicated success, in the
            // round titled for not dropping results.
            var outcome: String
            do {
                try await timeOffService.cancelTimeOffRequest(requestId: request.id)
                outcome = "Request cancelled successfully"
            } catch {
                outcome = error.localizedDescription
            }
            // The MainActor.run here is REDUNDANT and the comment that used to
            // justify it was wrong: SwiftUI's `View` protocol is itself
            // `@MainActor`, so conformance isolates the whole type — methods
            // included. Verified with a compiler probe. Kept as an explicit hop
            // rather than deleted, but no longer claiming to fix anything.
            //
            // The GUARD is the real change: this screen presents two sheets, and
            // an alert raised while one of them is up does not appear. Tapping
            // Edit on another card while a cancel is in flight would have
            // swallowed the result — including a FAILURE. Queued, not discarded.
            await MainActor.run {
                requestToCancel = nil
                if isPresentingSomething {
                    queuedAlerts.append(outcome)
                } else {
                    alertMessage = outcome
                    showingAlert = true
                }
            }
        }
    }
}
