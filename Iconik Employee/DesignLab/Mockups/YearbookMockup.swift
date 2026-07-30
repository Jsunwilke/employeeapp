//  YearbookMockup.swift
//  Iconik Employee — AMB.10's Yearbook mockup, built in batch 3
//
//  ARC SCAFFOLDING. Deleted at AMB.10's close, with the rest of the lab going at
//  AMB.12.
//
//  WHAT THE DESIGN IS ARGUING, in four claims the operator can accept or reject
//
//      1. PROGRESS MUST NOT READ AS AN ERROR AT 0%.
//         The live row colours its progress bar on a ladder — 100% green, ≥75
//         orange, ≥50 yellow, ELSE RED (`YearbookShootListsView.swift:306`). So a
//         brand-new list, correctly at 0%, renders a RED bar. Red in this app
//         means something is wrong, and nothing is wrong: the season has not
//         started. The bar gets a neutral track and ONE fill colour — the
//         feature's own — and the number beside it does the talking.
//
//      2. FILTERS MUST COMPOSE WITH SEARCH.
//         Tapping "Incomplete" today routes through `clearFilters()`
//         (`YearbookChecklistView.swift:141` → VM `:299`), which resets the
//         category to All and WIPES the text you typed. You cannot ask "which
//         football items are still open" — the app answers a different question
//         and throws your question away. The chips and the field compose.
//
//      3. WHEN EVERYTHING IS "REQUIRED", NOTHING IS.
//         `YearbookItem.required` defaults to TRUE (`YearbookModels.swift:161`),
//         so nearly every row carries a red REQUIRED chip and the red means
//         nothing at all. The tag inverts: the FEW optional items are marked
//         quietly, and the default — required — needs no decoration.
//
//      4. A FAILED LOAD MUST SAY SO.
//         `YearbookChecklistViewForSession`'s catch block prints and shows "No
//         Yearbook List Found" (`:177-181`), so a dropped connection is reported
//         as a school having no checklist — the photographer walks away. And on
//         the checklist screen `viewModel.error` is never read at all, so a failed
//         toggle is completely silent. Both get a state that says what happened.
//
//  WHAT IS NOT BEING PROPOSED
//      No data layer, service, permission or cache changes (D12). Per
//      AMB_BATCH3_PARITY.md §6, this mockup deliberately does NOT promise:
//
//        · CREATING a yearbook list. There is no create flow on iOS at all — both
//          the toolbar "+" and the empty state's button open a sheet whose whole
//          body is `Text("Create New Yearbook List")` (§0.3). So there is NO "+"
//          anywhere in this design, and the empty state says where lists come from
//          instead of offering a button that cannot work.
//        · DELETING or COPYING a list — dead API surface, no caller, no UI.
//        · PHOTOS or THUMBNAILS — an item carries image NUMBERS (`[String]`),
//          never an image reference.
//        · PER-ITEM ASSIGNMENT — the model has a completer, not an assignee.
//
//      Where a drawn state needs a fix, it is captioned PROPOSED so approving the
//      design is not mistaken for approving the fix.

import SwiftUI

// MARK: - Destinations

/// One enum, one `.ambientPush` — the AMB.3 rule. It carries the list's id so the
/// pushed screen is about the card that was tapped rather than about the first
/// card in the array.
private enum YearbookDestination: Identifiable {
    case checklist(String)

    var id: String {
        switch self {
        case .checklist(let listId): return "checklist-\(listId)"
        }
    }
}

/// Which state the root list is showing. A lab control, not a design element.
private enum YearbookListState: String, CaseIterable, Identifiable {
    case populated = "Lists"
    case empty = "Empty"
    case noMatches = "No matches"
    case loadFailed = "Load failed"
    case sessionEntry = "From a shift"

    var id: String { rawValue }
}

// MARK: - Root: the lists, grouped by school

struct YearbookMockup: View {
    /// The feature's own colour (D11) — the registered `FeatureTheme` deeper green
    /// from `DesignTokens.swift:48`, which today never reaches these screens.
    static let featureTint = Color(hex: "#2E9B4F")

    @State private var state: YearbookListState = .populated
    @State private var search = ""
    @State private var destination: YearbookDestination?

    /// Grouped by school, ascending — the live grouping
    /// (`YearbookShootListsView.swift`), kept.
    private var schools: [String] {
        Array(Set(YearbookLabData.lists.map { $0.schoolName })).sorted()
    }

    private func lists(for school: String) -> [YearbookShootList] {
        YearbookLabData.lists
            .filter { $0.schoolName == school }
            .sorted { $0.schoolYear > $1.schoolYear }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .checklist(let listId):
                YearbookChecklistMockup(list: YearbookLabData.list(id: listId))
            }
        }
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · state", trailing: "not a design element")
            Picker("State", selection: $state) {
                ForEach(YearbookListState.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .populated:
            VStack(alignment: .leading, spacing: 16) {
                searchField
                ForEach(schools, id: \.self) { school in
                    schoolSection(school)
                }
                noCreateNote
            }
        case .empty:
            emptyState
        case .noMatches:
            VStack(alignment: .leading, spacing: 16) {
                searchField
                noMatchesState
            }
        case .loadFailed:
            errorState
        case .sessionEntry:
            YearbookSessionEntryMockup()
        }
    }

    // MARK: 1 — search, hand-rolled

    /// The live screen uses `.searchable`, which the arc does not use: it puts a
    /// system field in the nav bar, outside the wash, and on a pushed screen it
    /// competes with the title. Hand-rolled, in the content, where it can be seen
    /// to be populated — which matters a great deal on the checklist screen (claim 2).
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search schools, years or items", text: $search)
                .font(.subheadline)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    // MARK: 2 — a school and its years

    private func schoolSection(_ school: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The icon is COMPOSED beside the title rather than forked into a
            // second section-title component. If a third surface wants one,
            // `AmbientSectionTitle` earns an icon slot — it does not get a
            // near-duplicate.
            HStack(spacing: 6) {
                Image(systemName: "building.2")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Self.featureTint)
                AmbientSectionTitle(school)
            }

            LazyVStack(spacing: AmbientDensity.roomy.stackSpacing) {
                ForEach(lists(for: school)) { list in
                    Button {
                        destination = .checklist(list.id)
                    } label: {
                        YearbookListCard(list: list)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }
        }
    }

    /// There is no create flow on iOS, so there is no button — and the reason is
    /// said out loud rather than left as an absence someone will "fix" by wiring a
    /// "+" to the placeholder sheet that already exists.
    private var noCreateNote: some View {
        Text("Lists are created in the web app. iOS has never been able to create one — the existing \"+\" opens an empty placeholder sheet — so this design has no create button, deliberately.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 3 — the states

    private var emptyState: some View {
        AmbientEmptyState(
            title: "No Yearbook Lists",
            message: "Yearbook lists are created in the web app. Once a list exists for one of your schools, it appears here.",
            systemImage: "list.clipboard")
    }

    /// A REAL state the live screen does not have: its empty check tests the
    /// UNFILTERED array, so filtering to zero rows renders a blank List and looks
    /// broken (parity §B.1).
    private var noMatchesState: some View {
        VStack(spacing: 8) {
            AmbientEmptyState(
                title: "No Matching Lists",
                message: "Nothing matches \"\(search.isEmpty ? "spring" : search)\". Search covers the school, the year and the names of items inside the list.",
                systemImage: "magnifyingglass")
            Text("Today a search that matches nothing renders a blank screen — the empty check tests the unfiltered list.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    /// PROPOSED — the root list has an error ALERT but no error state in the body,
    /// and the checklist screens have neither: `viewModel.error` is set in three
    /// places and read by one alert on one screen.
    private var errorState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Couldn't load your yearbook lists").font(.headline)
            Text("The server didn't answer. Your lists are safe — this screen just can't show them right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                withAnimation(AmbientMotion.gentle) { state = .populated }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    // ambient-allow: a control, not a card.
                    .background(Capsule().fill(Self.featureTint))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Text("PROPOSED — today a failed load prints to the console and the screen shows the empty state, so \"the network is down\" and \"this school has no list\" look identical.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - The list card

/// ROOMY. A school has a handful of years, not hundreds, and the two numbers that
/// matter (how far along, how many items) both want room.
private struct YearbookListCard: View {
    let list: YearbookShootList

    /// "2025-2026" → "2025-26". The live row computes this in a private property,
    /// so it is restated here rather than reached for.
    private var yearDisplay: String {
        let parts = list.schoolYear.split(separator: "-")
        guard parts.count == 2 else { return list.schoolYear }
        return "\(parts[0])-\(String(parts[1]).suffix(2))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(yearDisplay)
                    .font(AmbientDensity.roomy.titleFont)
                if list.isActive {
                    AmbientBadge(text: "Current", systemImage: "star.fill",
                                 tint: YearbookMockup.featureTint)
                }
                Spacer(minLength: 0)
                if list.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(YearbookMockup.featureTint)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            progressRow

            if let summary = categorySummary {
                Text(summary)
                    .font(AmbientDensity.roomy.subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("Updated \(YearbookLabData.relative.localizedString(for: list.updatedAt, relativeTo: Date()))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// ONE fill colour on a NEUTRAL track. No ladder, so 0% is not red — and no
    /// divide by zero: a list whose items have not been written yet has
    /// `total_count == 0`, and the live row hands that straight to
    /// `ProgressView(value:total:)`.
    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ProgressView(value: Double(list.completedCount),
                             total: Double(max(list.totalCount, 1)))
                    .progressViewStyle(.linear)
                    .tint(YearbookMockup.featureTint)
                Text("\(list.completedCount)/\(list.totalCount)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if list.totalCount == 0 {
                Text("No items yet — the list exists but nothing has been added to it in the web app.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if list.completedCount == 0 {
                Text("0% is a new list, not a problem — this bar is red on the live screen.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The live one-line summary: first three categories, then "+N more".
    private var categorySummary: String? {
        var seen: [String] = []
        for item in list.items where !seen.contains(item.category) {
            seen.append(item.category)
        }
        guard !seen.isEmpty else { return nil }
        let shown = seen.prefix(3).joined(separator: ", ")
        let extra = seen.count - min(seen.count, 3)
        return extra > 0 ? "\(shown) +\(extra) more" : shown
    }
}

// MARK: - Checklist

/// The screen a photographer actually works from. The ring leads, the chips
/// compose with the field, and the quiet tag is on the OPTIONAL items.
private struct YearbookChecklistMockup: View {
    let list: YearbookShootList

    private enum Quick: String, CaseIterable, Identifiable {
        case all = "All"
        case incomplete = "Incomplete"
        case completed = "Completed"
        var id: String { rawValue }
    }

    @State private var items: [YearbookItem] = []
    @State private var quick: Quick = .all
    @State private var category: String?
    @State private var search = ""
    @State private var detail: YearbookItem?
    @State private var exporting = false

    private var categories: [String] {
        var seen: [String] = []
        for item in items where !seen.contains(item.category) {
            seen.append(item.category)
        }
        return seen
    }

    /// All three filters AND the search text apply together. That is the whole
    /// claim: nothing here resets anything else.
    private var filtered: [YearbookItem] {
        items.filter { item in
            switch quick {
            case .all: break
            case .completed: if !item.completed { return false }
            case .incomplete: if item.completed { return false }
            }
            if let category, item.category != category { return false }
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let haystack = "\(item.name) \(item.description ?? "")"
                if !haystack.localizedCaseInsensitiveContains(query) { return false }
            }
            return true
        }
    }

    private var completedCount: Int { items.filter { $0.completed }.count }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: YearbookMockup.featureTint, intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    filterBar
                    searchField
                    composeNote
                    if filtered.isEmpty { noMatches } else { sections }
                    droppedMenuItemNote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("\(list.schoolName) • \(shortYear)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        exporting = true
                    } label: {
                        Label("Export Checklist", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if items.isEmpty { items = list.items }
        }
        .sheet(item: $detail) { item in
            YearbookItemDetailMockup(item: item)
        }
        .sheet(isPresented: $exporting) {
            YearbookExportMockup(list: list, items: items)
        }
    }

    private var shortYear: String {
        let parts = list.schoolYear.split(separator: "-")
        guard parts.count == 2 else { return list.schoolYear }
        return "\(parts[0])-\(String(parts[1]).suffix(2))"
    }

    // MARK: 1 — the ring leads

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ring
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(completedCount) of \(items.count) completed")
                        .font(.system(size: 19, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(list.schoolName) • \(shortYear)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            // Per-category progress, wrapping. The live screen shows one overall
            // number, so "which part of the book is behind" is a question you
            // answer by tapping through every category chip.
            AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(categories, id: \.self) { name in
                    let total = items.filter { $0.category == name }.count
                    let done = items.filter { $0.category == name && $0.completed }.count
                    AmbientBadge(text: "\(name) \(done)/\(total)",
                                 tint: done == total ? YearbookMockup.featureTint : .secondary)
                }
            }
        }
        .ambientCard(density: .hero, state: .highlighted,
                     glow: YearbookMockup.featureTint, fillWidth: true)
    }

    private var ring: some View {
        let fraction = items.isEmpty ? 0 : Double(completedCount) / Double(items.count)
        return ZStack {
            // ambient-allow: a progress ring is a gauge, not a container.
            Circle()
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(YearbookMockup.featureTint,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(AmbientMotion.gentle, value: fraction)
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .frame(width: 64, height: 64)
    }

    // MARK: 2 — chips that compose

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Quick.allCases) { option in
                    chip(option.rawValue, selected: quick == option) {
                        // Sets ONLY the quick filter. The live handler calls
                        // clearFilters(), which is the defect.
                        quick = option
                    }
                }

                Divider().frame(height: 20)

                ForEach(categories, id: \.self) { name in
                    chip(name, selected: category == name) {
                        category = (category == name) ? nil : name
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(AmbientMotion.snappy) { action() }
            AmbientHaptics.selection()
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                // ambient-allow: a filter chip is a control, not a container.
                .background(Capsule().fill(selected
                                           ? AnyShapeStyle(YearbookMockup.featureTint)
                                           : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search items", text: $search)
                .font(.subheadline)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var composeNote: some View {
        Text("PROPOSED: filters and search combine — type \"team\", tap Incomplete, tap Sports, and all three hold. Today a quick filter wipes both the typed text and the chosen category.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 3 — the items

    private var sections: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(categories, id: \.self) { name in
                let rows = filtered.filter { $0.category == name }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        // The count is of the FULL category, not the filtered
                        // subset. The live header counts what is on screen, so
                        // under "Completed" every header reads N/N and the screen
                        // claims the book is finished.
                        AmbientSectionTitle(name, trailing: fullCount(name))

                        LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                            ForEach(rows) { item in
                                row(item)
                                    .ambientScrollFade()
                            }
                        }
                    }
                }
            }

            Text("Category counts are of the whole category, not of what the filter left — the live header counts the filtered rows, so under \"Completed\" every heading reads N/N.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fullCount(_ category: String) -> String {
        let all = items.filter { $0.category == category }
        let done = all.filter { $0.completed }.count
        return "\(done)/\(all.count)"
    }

    private func row(_ item: YearbookItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                toggle(item)
            } label: {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.completed
                                     ? AnyShapeStyle(YearbookMockup.featureTint)
                                     : AnyShapeStyle(Color.secondary))
            }
            .buttonStyle(.plain)

            Button {
                detail = item
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.name)
                            .font(AmbientDensity.compact.titleFont)
                            .strikethrough(item.completed)
                            .foregroundStyle(item.completed
                                             ? AnyShapeStyle(Color.secondary)
                                             : AnyShapeStyle(Color.primary))
                            .fixedSize(horizontal: false, vertical: true)

                        // THE INVERSION. Required is the default and therefore
                        // silent; the few optional items are the ones worth
                        // marking, and they are marked quietly.
                        if !item.required {
                            AmbientBadge(text: "Optional", tint: .secondary)
                        }

                        Spacer(minLength: 0)

                        // The note dot tests EMPTINESS, not nil — the live row
                        // tests `!= nil`, so an item whose note was cleared to ""
                        // keeps its badge forever.
                        if let notes = item.notes,
                           !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Image(systemName: "note.text")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }

                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(AmbientDensity.compact.subtitleFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if item.completed, let attribution = attribution(item) {
                        Text(attribution)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let numbers = item.imageNumbers, !numbers.isEmpty {
                        Text("\(numbers.count) \(numbers.count == 1 ? "image" : "images")")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .ambientCard(density: .compact,
                     state: item.completed ? .receded : .normal,
                     fillWidth: true)
    }

    /// "Marisa Chen · Jul 12" — through the shared formatter cache, not a
    /// `DateFormatter` allocated per row per body evaluation (parity §3, perf).
    private func attribution(_ item: YearbookItem) -> String? {
        guard let name = item.photographerName, let date = item.completedDate else { return nil }
        return "\(name) · \(Formatters.monthDay.string(from: date))"
    }

    private func toggle(_ item: YearbookItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(AmbientMotion.snappy) {
            items[index].completed.toggle()
            if items[index].completed {
                items[index].completedDate = Date()
                items[index].photographerName = "You"
            } else {
                items[index].completedDate = nil
                items[index].photographerName = nil
            }
        }
        AmbientHaptics.impact(.light)
    }

    private var noMatches: some View {
        AmbientEmptyState(
            title: "No Items Match",
            message: "Nothing here matches the filter and the search together. Clear one of them.",
            systemImage: "line.3.horizontal.decrease.circle",
            actionTitle: "Clear Filters",
            actionIcon: "arrow.counterclockwise",
            action: {
                withAnimation(AmbientMotion.snappy) {
                    quick = .all
                    category = nil
                    search = ""
                }
            },
            actionTint: YearbookMockup.featureTint)
    }

    /// The overflow menu keeps Export and loses one item. Said out loud, with the
    /// operator's veto explicitly available — a dropped control is exactly the
    /// class of thing this arc has lost silently four times.
    private var droppedMenuItemNote: some View {
        Text("The overflow menu keeps Export and DROPS \"Mark All Required Complete\": the live menu item calls an empty function and has never done anything. Deliberately dropped rather than quietly kept — operator may veto. Export is unchanged, including that it exports EVERY item and ignores the filters and search, despite being called exportCompletedItems.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Item detail

/// A sheet, as today. Three PROPOSED additions, all of them about a save that can
/// fail: the live sheet dismisses unconditionally even on failure, surfaces no
/// error, and discards unsaved notes when you toggle completion.
private struct YearbookItemDetailMockup: View {
    let item: YearbookItem

    private enum LabState: String, CaseIterable, Identifiable {
        case clean = "Clean"
        case unsaved = "Unsaved edits"
        case saveFailed = "Save failed"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var labState: LabState = .clean
    @State private var imageNumbers = ""
    @State private var notes = ""
    @State private var completed = false

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: YearbookMockup.featureTint, intensity: 0.6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        labControl
                        header
                        statusSection
                        attributionSection
                        imagesSection
                        notesSection
                        toggleButton
                        if labState == .saveFailed { saveError }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if labState != .saveFailed { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            imageNumbers = (item.imageNumbers ?? []).joined(separator: ", ")
            notes = item.notes ?? ""
            completed = item.completed
        }
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · state", trailing: "not a design element")
            Picker("State", selection: $labState) {
                ForEach(LabState.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.system(size: 20, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !item.required {
                    AmbientBadge(text: "Optional", tint: .secondary)
                }
            }
            Text(item.category)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let description = item.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ambientCard(density: .hero, state: .highlighted,
                     glow: YearbookMockup.featureTint, fillWidth: true)
    }

    private var statusSection: some View {
        AmbientFormSection(title: "Status",
                           status: completed ? "Completed" : "Incomplete",
                           statusTint: completed ? YearbookMockup.featureTint : .orange) {
            HStack(spacing: 8) {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(completed
                                     ? AnyShapeStyle(YearbookMockup.featureTint)
                                     : AnyShapeStyle(Color.secondary))
                Text(completed ? "Photographed" : "Still to shoot")
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
        }
    }

    /// Photographer and date. The raw `completed_by_session` UUID the live sheet
    /// prints under "Session" is DROPPED: it is a database key with no lookup
    /// behind it, and no photographer has ever needed it.
    @ViewBuilder
    private var attributionSection: some View {
        if completed {
            AmbientFormSection(title: "Completed by",
                               status: item.photographerName ?? "Unknown",
                               statusTint: nil) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Photographer").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(item.photographerName ?? "Unknown").font(.subheadline)
                    }
                    Divider()
                    HStack {
                        Text("Date").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(item.completedDate.map { Formatters.mediumDate.string(from: $0) } ?? "—")
                            .font(.subheadline)
                    }
                    Text("The raw session UUID the live sheet shows here is dropped — it is a database key with nothing behind it.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var imagesSection: some View {
        let count = imageNumbers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        return AmbientFormSection(title: "Image numbers",
                                  status: count == 0 ? "none" : "\(count)",
                                  statusTint: count == 0 ? nil : .blue) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("4102, 4103, 4110", text: $imageNumbers)
                    .font(.subheadline)
                    .keyboardType(.numbersAndPunctuation)
                Text("Frame numbers, comma separated. Nothing here stores a photo.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var notesSection: some View {
        AmbientFormSection(title: "Notes",
                           status: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "optional" : "written",
                           statusTint: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .orange) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .font(.subheadline)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                if notes.isEmpty {
                    Text("What was shot, what is still missing, who to ask.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var toggleButton: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(AmbientMotion.snappy) { completed.toggle() }
                AmbientHaptics.impact(.medium)
            } label: {
                Label(completed ? "Mark as Incomplete" : "Mark as Complete",
                      systemImage: completed ? "circle" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // ambient-allow: a filled primary control, not a card.
                    .background(Capsule().fill(completed ? Color.red : YearbookMockup.featureTint))
            }
            .buttonStyle(.plain)

            // PROPOSED — the live `toggleCompletion` discards whatever you typed
            // in Notes and Image Numbers, silently, and does not tell you.
            if labState == .unsaved {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                    Text("You have unsaved notes. Marking this complete saves them too — PROPOSED. Today toggling throws your edits away without a word.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.orange)
                .ambientCard(density: .compact,
                             border: .hairline(Color.orange.opacity(0.35)),
                             fillWidth: true)
            }
        }
        .padding(.top, 2)
    }

    /// PROPOSED — the live sheet dismisses unconditionally, even when both of its
    /// two sequential writes failed. The photographer believes it saved.
    private var saveError: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.caption.weight(.semibold))
                Text("Couldn't save — the server didn't answer. Your text is still here; try Save again.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.red)
            .ambientCard(density: .compact,
                         border: .hairline(Color.red.opacity(0.4)),
                         fillWidth: true)

            Text("PROPOSED — today a failed save dismisses the sheet with no message, and the row keeps the old value until the whole screen is rebuilt.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Export preview

/// Export is KEPT, unchanged, and honest about what it does: it exports every
/// item regardless of the filters, which is not what its name
/// (`exportCompletedItems`) suggests.
private struct YearbookExportMockup: View {
    let list: YearbookShootList
    let items: [YearbookItem]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: YearbookMockup.featureTint, intensity: 0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AmbientNoteCard(
                            title: "Export",
                            text: "\(list.schoolName) — \(list.schoolYear)\n\(items.filter { $0.completed }.count) of \(items.count) completed\n\nShared as plain text through the system share sheet, grouped by category with ✓ / ○ marks, the photographer and date, notes and image numbers.",
                            accent: YearbookMockup.featureTint,
                            density: .roomy)

                        Text("Unchanged, including the part worth knowing: it exports EVERY item and ignores the active filters and the search text, despite the function being called exportCompletedItems.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Session entry

/// The shift-detail variant: reached as a SHEET from a shift, for one school.
/// Drawn as a lab state rather than a duplicate screen set, because the only two
/// things that differ are the year picker and what happens when the load fails.
private struct YearbookSessionEntryMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            yearPicker
            failureState
        }
    }

    /// The live picker is a plain `VStack` of buttons that is NOT inside a
    /// ScrollView (`YearbookChecklistViewForSession.swift`), so a school with
    /// several years pushes the older ones off the bottom of the screen with no
    /// way to reach them. Here it scrolls.
    private var yearPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Select school year", trailing: "scrollable")

            Text("Multiple yearbook lists found for Westbrook High School.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: AmbientDensity.compact.stackSpacing) {
                    ForEach(YearbookLabData.years) { entry in
                        HStack(spacing: 8) {
                            Text(entry.year)
                                .font(AmbientDensity.compact.titleFont)
                            if entry.isCurrent {
                                AmbientBadge(text: "Current", systemImage: "star.fill",
                                             tint: YearbookMockup.featureTint)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .ambientCard(density: .compact, fillWidth: true)
                    }
                }
            }
            .frame(maxHeight: 220)

            Text("Today this list is not in a ScrollView, so a school with six years of books hides the oldest three off-screen with no way to reach them.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// PROPOSED — the distinct failure state. Today the catch block prints and
    /// renders "No Yearbook List Found / No yearbook checklist exists for X",
    /// which is a factual claim about the school made on the strength of a
    /// dropped connection. A photographer who reads it stops looking.
    private var failureState: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Load failed", trailing: "PROPOSED")

            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text("Couldn't load the checklist").font(.headline)
                Text("Westbrook High School may well have one — this device just couldn't reach the server.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {} label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        // ambient-allow: a control, not a card.
                        .background(Capsule().fill(YearbookMockup.featureTint))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .ambientCard(density: .roomy, state: .highlighted,
                         border: .hairline(Color.orange.opacity(0.35)),
                         fillWidth: true, contentAlignment: .center)

            Text("PROPOSED — today a network failure, a missing org id and a genuinely absent list all render the same screen: \"No yearbook checklist exists for this school.\" Two of those three are lies. There is also no retry, and if the first fetch returns nil the spinner never stops.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Sample data

/// Seeded to contain every case that decides the design: three schools; a 0%
/// list (the one the live screen paints RED); a 100% list (the checkmark); a list
/// with six categories (the "+3 more" summary); a ZERO-ITEM list (the divide-by-
/// zero the live row hands straight to ProgressView); optional items that are
/// genuinely rare, so the inverted tag can be judged; a completed item with
/// attribution and image numbers; and an item whose note is an EMPTY STRING, the
/// case the live row's `!= nil` test gets wrong.
private enum YearbookLabData {

    /// One formatter, not one per row per body evaluation — which is what the live
    /// row does (`YearbookShootListsView.swift:206`).
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static let lists: [YearbookShootList] = [
        // The working list: six categories, part-done, current year.
        YearbookShootList(
            id: "yb-1",
            organizationId: "org",
            schoolId: "school-west",
            schoolName: "Westbrook High School",
            schoolYear: "2025-2026",
            startDate: DesignLabSampleData.day(-30),
            endDate: DesignLabSampleData.day(180),
            isActive: true,
            completedCount: westbrookItems.filter { $0.completed }.count,
            totalCount: westbrookItems.count,
            items: westbrookItems,
            createdAt: DesignLabSampleData.day(-40),
            updatedAt: Date().addingTimeInterval(-2 * 3600)),
        // LAST year's book, finished. The checkmark case.
        YearbookShootList(
            id: "yb-2",
            organizationId: "org",
            schoolId: "school-west",
            schoolName: "Westbrook High School",
            schoolYear: "2024-2025",
            startDate: DesignLabSampleData.day(-400),
            endDate: DesignLabSampleData.day(-200),
            isActive: false,
            completedCount: finishedItems.count,
            totalCount: finishedItems.count,
            items: finishedItems,
            createdAt: DesignLabSampleData.day(-410),
            updatedAt: DesignLabSampleData.day(-205)),
        // 0% — the list the live screen paints RED.
        YearbookShootList(
            id: "yb-3",
            organizationId: "org",
            schoolId: "school-north",
            schoolName: "Northgate Middle School",
            schoolYear: "2025-2026",
            startDate: DesignLabSampleData.day(-5),
            endDate: DesignLabSampleData.day(200),
            isActive: true,
            completedCount: 0,
            totalCount: northgateItems.count,
            items: northgateItems,
            createdAt: DesignLabSampleData.day(-5),
            updatedAt: DesignLabSampleData.day(-5)),
        // ZERO items — total_count 0. The live row hands this to
        // ProgressView(value:total:) unguarded.
        YearbookShootList(
            id: "yb-4",
            organizationId: "org",
            schoolId: "school-river",
            schoolName: "Riverside Elementary",
            schoolYear: "2025-2026",
            startDate: DesignLabSampleData.day(-2),
            endDate: DesignLabSampleData.day(210),
            isActive: true,
            completedCount: 0,
            totalCount: 0,
            items: [],
            createdAt: DesignLabSampleData.day(-2),
            updatedAt: DesignLabSampleData.day(-2))
    ]

    /// SIX categories, so the root card's summary has to say "+3 more", and the
    /// checklist's per-category pills have to wrap.
    private static let westbrookItems: [YearbookItem] = [
        YearbookItem(id: "i1", name: "Varsity Football Team Photo",
                     description: "Full squad on the field, coaches at the ends.",
                     category: "Sports", completed: true,
                     completedDate: DesignLabSampleData.day(-17),
                     photographerName: "Marisa Chen",
                     imageNumbers: ["4102", "4103", "4110"],
                     notes: "Number 44 was absent — retake booked.", order: 1),
        YearbookItem(id: "i2", name: "Individual Player Portraits",
                     description: "One frame per athlete, plain backdrop.",
                     category: "Sports", order: 2),
        YearbookItem(id: "i3", name: "Action Shots — Home Game",
                     category: "Sports", completed: true,
                     completedDate: DesignLabSampleData.day(-11),
                     photographerName: "Devon Pike",
                     imageNumbers: ["4220"],
                     // EMPTY-STRING note: the live row tests `!= nil`, so this
                     // draws a note badge over nothing.
                     notes: "", order: 3),
        YearbookItem(id: "i4", name: "Homecoming Court",
                     description: "Optional — only if the school runs one this year.",
                     category: "Sports", required: false, order: 4),

        YearbookItem(id: "i5", name: "Class Group Photos",
                     description: "One per homeroom, in the gym.",
                     category: "Academics", completed: true,
                     completedDate: DesignLabSampleData.day(-20),
                     photographerName: "Marisa Chen",
                     imageNumbers: ["3801", "3802", "3803", "3804"], order: 1),
        YearbookItem(id: "i6", name: "Teacher Portraits", category: "Academics", order: 2),
        YearbookItem(id: "i7", name: "Classroom Activities",
                     description: "Candids — labs, art room, library.",
                     category: "Academics", order: 3),

        YearbookItem(id: "i8", name: "Marching Band", category: "Clubs", completed: true,
                     completedDate: DesignLabSampleData.day(-9),
                     photographerName: "Devon Pike", order: 1),
        YearbookItem(id: "i9", name: "Robotics Club", category: "Clubs", order: 2),
        YearbookItem(id: "i10", name: "Chess Club",
                     description: "Optional — small group, include if there is time.",
                     category: "Clubs", required: false, order: 3),

        YearbookItem(id: "i11", name: "Senior Portraits", category: "Seniors", completed: true,
                     completedDate: DesignLabSampleData.day(-25),
                     photographerName: "Marisa Chen",
                     imageNumbers: ["3600", "3601", "3602", "3603", "3604", "3605"], order: 1),
        YearbookItem(id: "i12", name: "Senior Superlatives", category: "Seniors", order: 2),

        YearbookItem(id: "i13", name: "Building Exterior", category: "Campus", completed: true,
                     completedDate: DesignLabSampleData.day(-30),
                     photographerName: "Devon Pike", order: 1),
        YearbookItem(id: "i14", name: "New Science Wing", category: "Campus", order: 2),

        YearbookItem(id: "i15", name: "Fall Play — Curtain Call", category: "Performing Arts", order: 1),
        YearbookItem(id: "i16", name: "Orchestra Concert", category: "Performing Arts", order: 2)
    ]

    private static let finishedItems: [YearbookItem] = [
        YearbookItem(id: "f1", name: "Class Group Photos", category: "Academics", completed: true,
                     completedDate: DesignLabSampleData.day(-260),
                     photographerName: "Marisa Chen", order: 1),
        YearbookItem(id: "f2", name: "Senior Portraits", category: "Seniors", completed: true,
                     completedDate: DesignLabSampleData.day(-250),
                     photographerName: "Marisa Chen", order: 1),
        YearbookItem(id: "f3", name: "Spring Sports", category: "Sports", completed: true,
                     completedDate: DesignLabSampleData.day(-215),
                     photographerName: "Devon Pike", order: 1)
    ]

    private static let northgateItems: [YearbookItem] = [
        YearbookItem(id: "n1", name: "Class Group Photos", category: "Academics", order: 1),
        YearbookItem(id: "n2", name: "Teacher Portraits", category: "Academics", order: 2),
        YearbookItem(id: "n3", name: "8th Grade Group", category: "Academics", order: 3),
        YearbookItem(id: "n4", name: "Basketball Teams", category: "Sports", order: 1),
        YearbookItem(id: "n5", name: "Student Council",
                     description: "Optional — the adviser may not have them together.",
                     category: "Clubs", required: false, order: 1)
    ]

    /// Six years, which is what makes the un-scrollable live picker a bug rather
    /// than a nit.
    static let years: [LabSchoolYear] = [
        LabSchoolYear(year: "2025-2026", isCurrent: true),
        LabSchoolYear(year: "2024-2025", isCurrent: false),
        LabSchoolYear(year: "2023-2024", isCurrent: false),
        LabSchoolYear(year: "2022-2023", isCurrent: false),
        LabSchoolYear(year: "2021-2022", isCurrent: false),
        LabSchoolYear(year: "2020-2021", isCurrent: false)
    ]

    static func list(id: String) -> YearbookShootList {
        lists.first { $0.id == id } ?? lists[0]
    }
}

/// One year in the session-entry picker. There is no production type for this
/// shape — the live screen builds it from the distinct `school_year` values it
/// got back — so it stays a small lab struct.
private struct LabSchoolYear: Identifiable {
    let year: String
    let isCurrent: Bool

    var id: String { year }
}
