//  PhotoCritiqueListView.swift
//  Iconik Employee — the training photos list, converted to Ambient in AMB.12
//
//  The old screen's stat cards, segmented picker and hand-rolled states are GONE
//  from this file, not left beside the new ones. The design lives in
//  `Training/TrainingKit.swift`, which the design lab's mockup also draws with, so
//  the mockup and this screen cannot diverge.
//
//  WHAT THIS SCREEN GAINED:
//    · ONE VOCABULARY. The third stat tile said "Needs Work" while the filter
//      beside it and the badge on every card said "Needs Improvement". It says the
//      SERVICE'S word now — the one a manager chose when they submitted the photo.
//    · A REAL FAILURE STATE. `PhotoCritiqueService` publishes an `error`, sets it,
//      and NOBODY READ IT — so a dropped connection told a photographer their
//      managers had never sent them anything. Empty, no-matches and failed are
//      three distinct claims and are drawn as three distinct states.
//    · A GRID THAT FOLLOWS WIDTH. The column count came from the DEVICE IDIOM, so
//      an iPad in Slide Over at 320pt still drew three columns at ~100pt each. It
//      comes from the horizontal size class, which is what the window is doing.
//    · A LAYOUT TOGGLE THAT SAYS WHAT IT DOES. Its icon showed the CURRENT mode
//      with no accessibility label at all; it shows the destination now, and is
//      labelled.
//
//  WHAT IS DELIBERATELY UNCHANGED: the filter is still bound STRAIGHT INTO the
//  shared service singleton, so the choice persists across screen exits — existing
//  behaviour, kept. No permission gate: the query self-scopes to the signed-in
//  photographer (`PhotoCritiqueService.swift:61`), and drawing a gate would imply
//  one exists. No sort, no search, no pagination — none exist and none are added
//  (D12).
//
//  CLEARANCE: Training is a SELF-NAV feature. It owns its `NavigationView` and
//  applies `.homeToolbarItem()` and `.tabBarClearance()` itself, because the shell
//  cannot reach inside a self-nav feature (AMB.4).

import SwiftUI

struct PhotoCritiqueListView: View {
    @StateObject private var critiqueService = PhotoCritiqueService.shared
    // PSH.2: a tapped critique push parks a PendingDeepLink here; consumed below once
    // the service's listener has the critique. Plain let, NOT @ObservedObject (review
    // round): this view needs exactly one of the manager's publishers.
    private let tabBarManager = TabBarManager.shared

    /// WIDTH, NOT MODEL NAME (claim 3). `UIDevice.current.userInterfaceIdiom` is
    /// what the hardware is; this is what the WINDOW is, which is the only thing a
    /// column count can honestly follow.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isGridView = true
    @State private var selectedCritique: Critique?

    private var tint: Color { TrainingStyle.tint }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10),
              count: horizontalSizeClass == .compact ? 2 : 3)
    }

    var body: some View {
        NavigationView {
            ZStack {
                // D14: ONE wash for the whole app. Training's own colour is an
                // ACCENT (D11) and reaches the tiles, the chips and the selected
                // ring below, never the background.
                AmbientBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()
                .refreshable { await refreshData() }
            }
            .navigationTitle("Training Photos")
            .navigationBarTitleDisplayMode(.large)
            .homeToolbarItem()
            // Room for the app's floating bar. Applied inside this screen's own
            // navigation container, because the shell cannot reach into a self-nav
            // feature (AMB.4).
            .tabBarClearance()
            .onAppear {
                critiqueService.startListening()
                consumePending(tabBarManager.pendingCritique, in: critiqueService.critiques)
            }
            .onDisappear {
                critiqueService.stopListening()
            }
            // PSH.2 deep link: the push tap usually beats the listener's first load, so
            // re-check whenever either side changes. The consume rules (emitted value,
            // async mutation hop, expiry) live in TabBarManager.consumePendingDeepLink.
            .onReceive(tabBarManager.$pendingCritique) { pending in
                consumePending(pending, in: critiqueService.critiques)
            }
            .onReceive(critiqueService.$critiques) { list in
                consumePending(tabBarManager.pendingCritique, in: list)
            }
            .sheet(item: $selectedCritique) { critique in
                PhotoCritiqueDetailView(critique: critique)
            }
        }
        // FOUND ON DEVICE, and it predates this phase: without this an iPad at
        // REGULAR width renders a bare `NavigationView` as a SPLIT view, so
        // Training opened as a blank detail column with its whole screen collapsed
        // into a sidebar nobody knew to pull out. Every other self-nav container in
        // the app already says this (CaptureGalleryListView, TasksView, the NFC
        // forms); Training never did.
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func consumePending(_ pending: PendingDeepLink?, in critiques: [Critique]) {
        tabBarManager.consumePendingDeepLink(\.pendingCritique, emitted: pending,
                                             in: critiques, id: { $0.id }) { match in
            selectedCritique = match
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if critiqueService.isLoading && critiqueService.critiques.isEmpty {
            AmbientLoadingRow(message: "Loading training photos…")
        } else if critiqueService.critiques.isEmpty {
            // A FAILED FETCH AND AN EMPTY INBOX ARE DIFFERENT CLAIMS (claim 2).
            // "No Training Photos Yet" is a statement of fact about a photographer's
            // managers; a dropped connection is a statement about the network.
            if critiqueService.error != nil {
                failureCard
            } else {
                emptyState
            }
        } else {
            // A failed REFRESH over a populated screen is a report, not a state: the
            // cards behind it are real, they are just older than now. The service
            // keeps the previous list on failure, so this branch is reachable and
            // was, until this phase, completely silent.
            if critiqueService.error != nil {
                failureCard
            }
            statistics
            filterBar
            if critiqueService.filteredCritiques.isEmpty {
                noResultsState
            } else if isGridView {
                grid
            } else {
                list
            }
        }
    }

    // MARK: - Statistics

    /// The SHARED stat tile, not Training's own — the app had two stat-tile
    /// components before this phase and must not carry a third, so `StatsCard` is
    /// deleted with this change.
    private var statistics: some View {
        let stats = critiqueService.statistics

        return HStack(spacing: 10) {
            AmbientStatTile(value: stats.total,
                            label: "Total",
                            systemImage: "photo.stack",
                            tint: tint)
            AmbientStatTile(value: stats.goodExamples,
                            label: "Good Examples",
                            systemImage: "checkmark.circle",
                            tint: .green)
            // "Needs Improvement", not "Needs Work" — the service enum's own string
            // (PhotoCritiqueService.swift:16-20), which is also what the filter chip
            // beside it and the badge on every card say.
            AmbientStatTile(value: stats.needsImprovement,
                            label: "Needs Improvement",
                            systemImage: "exclamationmark.triangle",
                            tint: .orange)
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(alignment: .top, spacing: 8) {
            AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(PhotoCritiqueService.FilterType.allCases, id: \.self) { option in
                    // Bound straight into the shared singleton, exactly as before —
                    // which is why the choice survives leaving the screen.
                    AmbientChip(text: option.rawValue,
                                isOn: critiqueService.filter == option,
                                tint: tint) {
                        critiqueService.filter = option
                    }
                }
            }
            // FOUND ON DEVICE. Without this frame the three chips are proposed an
            // UNSPECIFIED width by the HStack, so `AmbientFlowLayout` sizes itself
            // for ONE line, wraps to two when it is finally squeezed, and draws its
            // second line — and the toggle beside it — OUTSIDE the row's reported
            // frame. The grid below then hit-tests where the toggle appears to be:
            // tapping the toggle opened a critique. The frame hands the flow layout
            // a concrete width, so what it reports is what it draws.
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(AmbientMotion.snappy) { isGridView.toggle() }
                AmbientHaptics.selection()
            } label: {
                // THE ICON SHOWS WHAT YOU WILL GET, not what you are looking at.
                Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 32, height: 32)
                    // ambient-allow: an icon control, not a container.
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isGridView ? "Show as a list" : "Show as a grid")
        }
    }

    // MARK: - Layouts

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(critiqueService.filteredCritiques) { critique in
                Button {
                    selectedCritique = critique
                } label: {
                    CritiqueGridCard(critique: critique)
                }
                .buttonStyle(.plain)
                .ambientScrollFade()
            }
        }
    }

    private var list: some View {
        LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
            ForEach(critiqueService.filteredCritiques) { critique in
                Button {
                    selectedCritique = critique
                } label: {
                    CritiqueListRow(critique: critique)
                }
                .buttonStyle(.plain)
                .ambientScrollFade()
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        AmbientEmptyState(
            title: "No Training Photos Yet",
            message: "Your training examples will appear here when managers submit them.",
            systemImage: "camera.on.rectangle")
    }

    /// Distinct from the empty state above, and worth keeping distinct: this one is
    /// about the FILTER, and it offers the way out.
    private var noResultsState: some View {
        AmbientEmptyState(
            title: "No Results",
            message: "No training photos match the selected filter.",
            systemImage: "magnifyingglass",
            actionTitle: "Show All",
            actionIcon: "square.grid.2x2",
            action: {
                withAnimation(AmbientMotion.snappy) { critiqueService.filter = .all }
            },
            actionTint: tint)
    }

    private var failureCard: some View {
        AmbientFailureCard(message: "Couldn't load your training photos.") {
            critiqueService.refresh()
        }
    }

    // MARK: - Refresh

    /// KEPT AS IT WAS, and it is worth saying why the sleep is still here: the
    /// service's `refresh()` is fire-and-forget — `startListening()` hops onto a
    /// detached Task — so there is nothing to await, and giving it one would be a
    /// data-layer change this phase does not make (D12). The delay keeps the pull
    /// gesture from snapping back before the first rows land.
    private func refreshData() async {
        critiqueService.refresh()
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}

struct PhotoCritiqueListView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoCritiqueListView()
    }
}
