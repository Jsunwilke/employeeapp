//  YearbookShootListsView.swift
//  Iconik Employee — the yearbook lists, converted to Ambient in AMB.10
//
//  The old screen and its `YearbookListRow` are GONE from this file, not left
//  beside the new one. The design lives in `Yearbook/YearbookKit.swift`, which the
//  design lab's mockup also draws with, so the mockup and this screen cannot
//  diverge; every judgement it renders is made in `Yearbook/YearbookRules.swift`,
//  which `scripts/test_yearbook_rules.sh` compiles and runs.
//
//  WHAT THIS SCREEN GAINED:
//    · 0% NO LONGER READS AS AN ERROR. The old bar was coloured on a ladder whose
//      bottom rung was RED, so a brand-new list — correctly at zero — rendered red.
//    · A ZERO-ITEM LIST SAYS SO instead of handing `total: 0` to a ProgressView.
//    · A REAL NO-MATCHES STATE. The old empty check tested the UNFILTERED array, so
//      a search that matched nothing rendered a blank List and looked broken.
//    · A REAL FAILURE STATE IN THE BODY. `viewModel.error` was read only by an
//      alert, and a missing organization id printed to the console and left the
//      screen spinning forever.
//    · PULL-TO-REFRESH THAT WAITS. The old `.refreshable` called a subscribe method
//      that returns immediately, so the spinner ended before any data arrived.
//
//  WHAT IS DELIBERATELY NOT DRAWN: a create button. There is NO create flow for a
//  yearbook list on iOS — the old toolbar "+" and the old empty-state button both
//  opened a sheet whose entire body was `Text("Create New Yearbook List")`
//  (AMB_BATCH3_PARITY.md §0.3). The empty state says where lists come from instead
//  of offering something that cannot work. Delete and copy are dead API surface
//  with no UI, and stay that way.
//
//  CLEARANCE: this is a SHELL-WRAPPED feature — `MainEmployeeView.featureContainer`
//  applies `tabBarClearance` inside its own `NavigationView`, so this root must not
//  apply it again. The PUSHED checklist insets itself; see YearbookChecklistView.

import SwiftUI

/// One `@State` destination, one `.ambientPush` — the AMB.3 rule. It carries the
/// list that was tapped rather than an index into an array the next realtime
/// event can reorder.
private enum YearbookListsDestination: Identifiable {
    case checklist(YearbookShootList)

    var id: String {
        switch self {
        case .checklist(let list): return "checklist-\(list.id)"
        }
    }
}

struct YearbookShootListsView: View {
    @StateObject private var viewModel = YearbookShootListViewModel()

    @State private var searchText = ""
    @State private var currentOrganizationId: String?
    /// Set when the org id itself could not be resolved — the case that used to
    /// print to the console and leave the screen loading forever.
    @State private var organizationProblem: String?
    @State private var destination: YearbookListsDestination?

    private var tint: Color { YearbookStyle.tint }

    private var filteredLists: [YearbookShootList] {
        YearbookRules.lists(viewModel.shootLists, matching: searchText)
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: tint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
            .refreshable { await reload() }
        }
        .navigationBarTitle("Yearbook Checklists", displayMode: .inline)
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .checklist(let list):
                YearbookChecklistView(shootList: list, sessionContext: nil)
            }
        }
        // FIRST APPEARANCE ONLY (AMB.10 review): `.onAppear` refires on every
        // pop-back from a pushed checklist, and unguarded this re-tore the org
        // subscription AND ran two full org fetches (every list with its whole
        // items array) per round trip. After the first load the live
        // subscription keeps the rows current; `.refreshable` and the failure
        // card's Try Again own the awaited path.
        .onAppear {
            if currentOrganizationId == nil { loadOrganizationAndLists() }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let problem = organizationProblem {
            failureCard(problem)
        } else if viewModel.isLoading && viewModel.shootLists.isEmpty {
            YearbookLoadingRow(message: "Loading yearbook lists…")
        } else if viewModel.shootLists.isEmpty {
            // A LOAD FAILURE AND AN EMPTY ORG ARE DIFFERENT CLAIMS. Since AMB.10
            // the subscription publishes nothing on a failed fetch (it can no
            // longer clobber a good list with []); the awaited refresh owns
            // failure reporting, and when the error IS carried this screen says
            // so rather than asserting the org has no lists.
            if let error = viewModel.error {
                failureCard(error.localizedDescription)
            } else {
                emptyState
            }
        } else {
            // A failed REFRESH over a populated screen is a report, not a state:
            // the rows behind it are real, they are just older than now.
            if let error = viewModel.error {
                YearbookInlineFailure(message: error.localizedDescription) {
                    viewModel.dismissError()
                }
            }
            searchField
            if filteredLists.isEmpty {
                noMatchesState
            } else {
                ForEach(YearbookRules.groupedBySchool(filteredLists), id: \.school) { group in
                    schoolSection(group.school, lists: group.lists)
                }
            }
            sourceNote
        }
    }

    private var searchField: some View {
        YearbookSearchField(placeholder: "Search schools, years or items", text: $searchText)
    }

    /// A school and its years, newest first.
    private func schoolSection(_ school: String, lists: [YearbookShootList]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The icon is COMPOSED beside the title rather than forked into a
            // second section-title component.
            HStack(spacing: 6) {
                Image(systemName: "building.2")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                AmbientSectionTitle(school)
            }

            LazyVStack(spacing: AmbientDensity.roomy.stackSpacing) {
                ForEach(lists) { list in
                    Button {
                        destination = .checklist(list)
                    } label: {
                        YearbookListCard(list: list, tint: tint)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }
        }
    }

    /// Said out loud, so nobody "fixes" the missing "+" by wiring it back to the
    /// placeholder sheet that used to be there.
    private var sourceNote: some View {
        Text("Yearbook lists are created in the web app. This screen tracks and completes them.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - States

    private var emptyState: some View {
        AmbientEmptyState(
            title: "No Yearbook Lists",
            message: "Yearbook lists are created in the web app. Once a list exists for one of your schools, it appears here.",
            systemImage: "list.clipboard")
    }

    /// THE STATE THE OLD SCREEN DID NOT HAVE. Its empty check tested the
    /// UNFILTERED array, so filtering to zero rows rendered a blank List.
    private var noMatchesState: some View {
        AmbientEmptyState(
            title: "No Matching Lists",
            message: "Nothing matches “\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))”. Search covers the school, the year and the names of items inside the list.",
            systemImage: "magnifyingglass",
            actionTitle: "Clear Search",
            actionIcon: "arrow.counterclockwise",
            action: { withAnimation(AmbientMotion.snappy) { searchText = "" } },
            actionTint: tint)
    }

    private func failureCard(_ message: String) -> some View {
        YearbookFailureCard(
            title: "Couldn't load your yearbook lists",
            message: message,
            tint: tint,
            retry: { Task { await reload() } })
    }

    // MARK: - Loading

    private func loadOrganizationAndLists() {
        UserManager.shared.getCurrentUserOrganizationID { organizationId in
            DispatchQueue.main.async {
                guard let orgId = organizationId else {
                    self.organizationProblem =
                        "This device couldn't work out which studio you belong to, so it can't ask for your lists."
                    return
                }
                self.organizationProblem = nil
                self.currentOrganizationId = orgId
                // The subscription keeps the screen live but cannot REPORT a
                // failure (since AMB.10 its failure path publishes nothing at
                // all — never an empty list). So the FIRST load also runs the
                // awaited fetch, the one path that can say a fetch failed.
                self.viewModel.loadOrganizationLists(organizationId: orgId)
                Task { await self.viewModel.refreshOrganizationLists(organizationId: orgId) }
            }
        }
    }

    /// Awaited by both `.refreshable` and the failure card's Try Again, so the
    /// spinner and the button both mean what they look like — including when the
    /// organization id itself is still unresolved.
    private func reload() async {
        let orgId: String?
        if let known = currentOrganizationId {
            orgId = known
        } else {
            orgId = await withCheckedContinuation { continuation in
                UserManager.shared.getCurrentUserOrganizationID { continuation.resume(returning: $0) }
            }
        }

        guard let orgId else {
            organizationProblem =
                "This device couldn't work out which studio you belong to, so it can't ask for your lists."
            return
        }
        organizationProblem = nil
        currentOrganizationId = orgId
        await viewModel.refreshOrganizationLists(organizationId: orgId)
    }
}

// MARK: - Preview
struct YearbookShootListsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            YearbookShootListsView()
        }
    }
}
