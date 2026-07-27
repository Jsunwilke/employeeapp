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
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .balance: PTOBalanceView(isPushed: true)
            }
        }
        .sheet(isPresented: $showingNewRequest) {
            TimeOffRequestView(timeOffService: timeOffService)
        }
        .sheet(item: $editingRequest) { request in
            TimeOffRequestView(timeOffService: timeOffService, editingRequest: request)
        }
        .alert("Cancel Request", isPresented: $showingCancelAlert) {
            Button("Cancel Request", role: .destructive) {
                if let requestToCancel { cancelRequest(requestToCancel) }
            }
            Button("Keep Request", role: .cancel) { requestToCancel = nil }
        } message: {
            Text("Are you sure you want to cancel this time off request? This action cannot be undone.")
        }
        .alert("Time Off", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .task {
            await timeOffService.startListeningToRequests()
            await loadBalance()
        }
        .onDisappear {
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
            if timeOffService.isLoading && timeOffService.myRequests.isEmpty {
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
        Task {
            do {
                try await timeOffService.cancelTimeOffRequest(requestId: request.id)
                await MainActor.run { alertMessage = "Request cancelled successfully" }
            } catch {
                await MainActor.run { alertMessage = error.localizedDescription }
            }
            // These are @State writes from a nonisolated continuation — a `View`
            // isolates `body`, not its methods, so the code after `await` lands
            // off the main actor. The old screen wrapped every one of these.
            await MainActor.run {
                showingAlert = true
                requestToCancel = nil
            }
        }
    }
}
