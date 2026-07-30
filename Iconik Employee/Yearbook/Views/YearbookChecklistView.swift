//  YearbookChecklistView.swift
//  Iconik Employee — the checklist a photographer works from, Ambient (AMB.10)
//
//  The old screen's `progressHeader`, `filterBar`, `searchBar`, `FilterChip` and
//  its two hand-rolled `systemGray6` bars are GONE from this file. The design
//  lives in `Yearbook/YearbookKit.swift` (which the lab mockup imports) and every
//  judgement in `Yearbook/YearbookRules.swift` (which a script runs).
//
//  WHAT THIS SCREEN GAINED:
//    · THE FILTERS COMPOSE WITH THE SEARCH (claim 2). Every quick chip used to
//      route through the view model's `clearFilters()`, which reset the category
//      AND wiped the typed text — so "which football items are still open" was a
//      question the app answered by throwing it away.
//    · CATEGORY COUNTS ARE OF THE WHOLE CATEGORY. The old header counted the rows
//      ON SCREEN, so under "Completed" every heading read N/N and the screen
//      claimed the book was finished.
//    · ERRORS ARE SURFACED. `viewModel.error` was set in three places and read by
//      NOTHING on this screen, so a failed check-off was completely silent.
//    · THE OPTIONAL BADGE IS THE INVERSION (claim 3) — `required` defaults to true.
//
//  WHAT WAS DROPPED, deliberately and with the operator's approval: the overflow
//  menu's "Mark All Required Complete", whose handler was an EMPTY FUNCTION and
//  had never done anything, and the menu's Filters toggle, because the filter bar
//  is always shown now. Export is KEPT and unchanged — including the part worth
//  knowing, that it exports EVERY item and ignores the active filters despite
//  being called `exportCompletedItems`.
//
//  CLEARANCE: this screen is PUSHED from the root, and a pushed screen insets
//  itself — a container's root inset is not inherited by what it pushes. It is
//  NOT inset when it is presented inside the shift-detail SHEET (`sessionContext`
//  non-nil): a sheet floats above the floating tab bar, so the clearance would be
//  a dead gap at the bottom of the sheet.

import SwiftUI

struct YearbookChecklistView: View {
    @StateObject private var viewModel: YearbookShootListViewModel
    let sessionContext: YearbookSessionContext?

    /// ONE sheet, one binding.
    ///
    /// FOUND ON DEVICE, and it is why this is an enum: with the old screen's TWO
    /// stacked `.sheet` modifiers (`.sheet(item:)` for the item detail plus
    /// `.sheet(isPresented:)` for the export), tapping an item did nothing at
    /// all, and unifying them fixed it. NOT a general law — `ShiftDetailView`
    /// chains four `.sheet`s that all ship and work — so the precise trigger is
    /// unestablished; the observed fact is that THIS mixed pair failed on device
    /// and one enum-driven sheet is the shape that cannot.
    private enum ChecklistSheet: Identifiable {
        case item(String)
        case export(String)

        var id: String {
            switch self {
            case .item(let itemId): return "item-\(itemId)"
            case .export: return "export"
            }
        }
    }

    @State private var sheet: ChecklistSheet?

    private var tint: Color { YearbookStyle.tint }

    init(shootList: YearbookShootList, sessionContext: YearbookSessionContext?) {
        let viewModel = YearbookShootListViewModel(sessionContext: sessionContext)
        viewModel.selectedShootList = shootList
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.sessionContext = sessionContext
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: tint, intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let list = viewModel.selectedShootList {
                        // A failed toggle or save, said out loud. Dismissible
                        // because the screen around it still works.
                        if let error = viewModel.error {
                            YearbookInlineFailure(message: error.localizedDescription) {
                                viewModel.dismissError()
                            }
                        }
                        hero(list)
                        filterBar
                        YearbookSearchField(placeholder: "Search items",
                                            text: $viewModel.filter.searchText)
                        sections
                    } else {
                        AmbientEmptyState(
                            title: "Checklist not found",
                            message: "This yearbook list is no longer available on this device.",
                            systemImage: "list.clipboard")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .modifier(YearbookPushedClearance(active: sessionContext == nil))
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: exportChecklist) {
                        Label("Export Checklist", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .item(let itemId):
                YearbookItemDetailView(itemId: itemId, viewModel: viewModel)
            case .export(let text):
                ShareSheet(activityItems: [text])
            }
        }
    }

    private var navigationTitle: String {
        guard let list = viewModel.selectedShootList else { return "Yearbook Checklist" }
        return YearbookRules.listTitle(schoolName: list.schoolName, schoolYear: list.schoolYear)
    }

    // MARK: - 1. The hero

    private func hero(_ list: YearbookShootList) -> some View {
        YearbookHeroCard(schoolName: list.schoolName,
                         schoolYear: list.schoolYear,
                         items: viewModel.allItems,
                         // The stored counters, not a recount: they are what the
                         // root card and the web app show, and a screen that
                         // silently disagrees with the row that opened it is worse
                         // than one that carries the same drift.
                         completedCount: list.completedCount,
                         totalCount: list.totalCount,
                         tint: tint)
    }

    // MARK: - 2. Chips that compose

    /// Each chip sets ONE thing. Nothing here resets anything else — that is the
    /// whole of claim 2.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(YearbookQuickFilter.allCases) { option in
                    YearbookFilterChip(label: option.label,
                                       isSelected: viewModel.filter.quick == option,
                                       tint: tint) {
                        viewModel.filter.quick = option
                    }
                }

                if !viewModel.categories.isEmpty {
                    Divider().frame(height: 20)

                    ForEach(viewModel.categories, id: \.self) { name in
                        YearbookFilterChip(label: name,
                                           isSelected: viewModel.filter.category == name,
                                           tint: tint) {
                            // Toggling is the only route back to "every
                            // category" now that the quick chips no longer
                            // reset it.
                            viewModel.filter.category =
                                (viewModel.filter.category == name) ? nil : name
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    // MARK: - 3. The items

    @ViewBuilder
    private var sections: some View {
        let groups = viewModel.groupedFilteredItems
        switch YearbookRules.emptyReason(total: viewModel.allItems.count,
                                         shown: viewModel.filteredItems.count) {
        case .populated:
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        // The count is of the FULL category, not of what the
                        // filter left.
                        AmbientSectionTitle(group.category,
                                            trailing: YearbookRules.categoryCountLabel(
                                                viewModel.allItems, category: group.category))

                        LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                            ForEach(group.items) { item in
                                YearbookItemRow(item: item, tint: tint) {
                                    toggle(item)
                                } onTap: {
                                    sheet = .item(item.id)
                                }
                                .ambientScrollFade()
                            }
                        }
                    }
                }
            }
        case .filteredOut:
            AmbientEmptyState(
                title: "No Items Match",
                message: "Nothing here matches the filter and the search together. Clear one of them.",
                systemImage: "line.3.horizontal.decrease.circle",
                actionTitle: "Clear Filters",
                actionIcon: "arrow.counterclockwise",
                action: {
                    withAnimation(AmbientMotion.snappy) { viewModel.filter = .clear }
                },
                actionTint: tint)
        case .nothingAtAll:
            AmbientEmptyState(
                title: "No Items Yet",
                message: "This list exists but nothing has been added to it. Items are added in the web app.",
                systemImage: "list.clipboard")
        }
    }

    // MARK: - Actions

    private func toggle(_ item: YearbookItem) {
        AmbientHaptics.impact(.light)
        Task { await viewModel.toggleItemCompletion(item) }
    }

    private func exportChecklist() {
        sheet = .export(viewModel.exportCompletedItems())
    }
}

/// Clearance for the floating tab bar, applied only when this screen is PUSHED.
///
/// Split into a modifier so the branch is decided once at the call site and the
/// screen's identity does not change with it.
private struct YearbookPushedClearance: ViewModifier {
    let active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if active { content.tabBarClearance() } else { content }
    }
}

// MARK: - Share Sheet

/// KEPT WHERE IT WAS, deliberately: `Training/PhotoCritiqueDetailView.swift:61`
/// presents this same type, so it is a cross-feature declaration rather than a
/// yearbook detail. Moving or renaming it would push churn into a screen AMB.10
/// has no business touching.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview
struct YearbookChecklistView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            YearbookChecklistView(
                shootList: YearbookShootListViewModel.preview.selectedShootList!,
                sessionContext: nil
            )
        }
    }
}
