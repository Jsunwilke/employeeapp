//  YearbookMockup.swift
//  Iconik Employee — AMB.10's Yearbook mockup, built in batch 3
//
//  ARC SCAFFOLDING. Deleted at AMB.10's close, with the rest of the lab going at
//  AMB.12.
//
//  REFACTORED AT THE CONVERSION (AMB.10): this file no longer carries its own
//  copies of the card, the chip, the ring, the search field, the item row, the
//  year row or the failure state. It IMPORTS them from `Yearbook/YearbookKit.swift`
//  and asks `Yearbook/YearbookRules.swift` the same questions the real screens ask
//  — the arc's rule since AMB.7 (`design-lives-in-production-code`). What is left
//  here is what the lab is for: SAMPLE DATA, the state pickers, and the captions
//  that say what each drawn state is arguing.
//
//  WHAT THE DESIGN ARGUED, in four claims the operator ACCEPTED on 2026-07-29 —
//  all four are now built:
//
//      1. PROGRESS MUST NOT READ AS AN ERROR AT 0%.
//         The live row coloured its progress bar on a ladder — 100% green, ≥75
//         orange, ≥50 yellow, ELSE RED — so a brand-new list, correctly at 0%,
//         rendered RED. Red in this app means something is wrong, and nothing was
//         wrong: the season had not started. The bar has a neutral track and ONE
//         fill colour, and the number beside it does the talking.
//
//      2. FILTERS MUST COMPOSE WITH SEARCH.
//         Tapping "Incomplete" routed through `clearFilters()`, which reset the
//         category to All and WIPED the text you had typed. You could not ask
//         "which football items are still open" — the app answered a different
//         question and threw yours away.
//
//      3. WHEN EVERYTHING IS "REQUIRED", NOTHING IS.
//         `YearbookItem.required` defaults to TRUE, so nearly every row carried a
//         red REQUIRED chip and the red meant nothing at all. The tag inverts.
//
//      4. A FAILED LOAD MUST SAY SO.
//         `YearbookChecklistViewForSession`'s catch block printed and showed "No
//         Yearbook List Found", so a dropped connection was reported as a school
//         having no checklist. On the checklist screen `viewModel.error` was never
//         read at all, so a failed toggle was completely silent.
//
//  WHAT WAS NOT PROMISED, and still is not: creating a yearbook list (there is no
//  create flow on iOS — both the old "+" and the old empty-state button opened a
//  sheet whose whole body was `Text("Create New Yearbook List")`), deleting or
//  copying one (dead API surface), photos or thumbnails (an item carries image
//  NUMBERS, never an image reference), and per-item assignment (the model has a
//  completer, not an assignee).

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
    /// The feature's own colour (D11), through the kit — so the lab and the real
    /// screens cannot be tinted differently.
    static var featureTint: Color { YearbookStyle.tint }

    @State private var state: YearbookListState = .populated
    @State private var search = ""
    @State private var destination: YearbookDestination?

    /// Grouped by school ascending, years descending — `YearbookRules`, the same
    /// call the real root list makes.
    private var groups: [(school: String, lists: [YearbookShootList])] {
        YearbookRules.groupedBySchool(YearbookRules.lists(YearbookLabData.lists, matching: search))
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
                ForEach(groups, id: \.school) { group in
                    schoolSection(group.school, lists: group.lists)
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

    /// The kit's field. The live screen used `.searchable`, which the arc does not
    /// use: it puts a system field in the nav bar, outside the wash, and on a
    /// pushed screen it competes with the title.
    private var searchField: some View {
        YearbookSearchField(placeholder: "Search schools, years or items", text: $search)
    }

    // MARK: 2 — a school and its years

    private func schoolSection(_ school: String, lists: [YearbookShootList]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The icon is COMPOSED beside the title rather than forked into a
            // second section-title component.
            HStack(spacing: 6) {
                Image(systemName: "building.2")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Self.featureTint)
                AmbientSectionTitle(school)
            }

            LazyVStack(spacing: AmbientDensity.roomy.stackSpacing) {
                ForEach(lists) { list in
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
    /// "+" to the placeholder sheet that used to exist.
    private var noCreateNote: some View {
        Text("Lists are created in the web app. iOS has never been able to create one — the old \"+\" opened an empty placeholder sheet — so this design has no create button, deliberately.")
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

    /// A REAL state the live screen did not have: its empty check tested the
    /// UNFILTERED array, so filtering to zero rows rendered a blank List and looked
    /// broken (parity §B.1).
    private var noMatchesState: some View {
        VStack(spacing: 8) {
            AmbientEmptyState(
                title: "No Matching Lists",
                message: "Nothing matches \"\(search.isEmpty ? "spring" : search)\". Search covers the school, the year and the names of items inside the list.",
                systemImage: "magnifyingglass")
            Text("Before AMB.10 a search that matched nothing rendered a blank screen — the empty check tested the unfiltered list.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    /// The root list had an error ALERT but no error state in the body, and the
    /// checklist screens had neither.
    private var errorState: some View {
        VStack(spacing: 10) {
            YearbookFailureCard(
                title: "Couldn't load your yearbook lists",
                message: YearbookFailureCard.genericMessage,
                tint: Self.featureTint,
                retry: { withAnimation(AmbientMotion.gentle) { state = .populated } })

            Text("PROPOSED, and BUILT — before AMB.10 a failed load printed to the console and the screen showed the empty state, so \"the network is down\" and \"this school has no list\" looked identical.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Checklist

/// The screen a photographer actually works from. The ring leads, the chips
/// compose with the field, and the quiet tag is on the OPTIONAL items.
private struct YearbookChecklistMockup: View {
    let list: YearbookShootList

    @State private var items: [YearbookItem] = []
    @State private var filter = YearbookFilter()
    @State private var detail: YearbookItem?
    @State private var exporting = false

    private var categories: [String] { YearbookRules.categories(in: items) }

    /// All three filters AND the search text apply together — one call into the
    /// same rule the real screen uses. That is the whole claim: nothing here
    /// resets anything else.
    private var filtered: [YearbookItem] { YearbookRules.items(items, matching: filter) }

    private var completedCount: Int { items.filter { $0.completed }.count }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: YearbookMockup.featureTint, intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    filterBar
                    YearbookSearchField(placeholder: "Search items", text: $filter.searchText)
                    composeNote
                    if filtered.isEmpty { noMatches } else { sections }
                    droppedMenuItemNote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(YearbookRules.listTitle(schoolName: list.schoolName,
                                                 schoolYear: list.schoolYear))
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

    // MARK: 1 — the ring leads

    /// Per-category progress, wrapping. The live screen showed one overall number,
    /// so "which part of the book is behind" was a question you answered by
    /// tapping through every category chip.
    private var hero: some View {
        YearbookHeroCard(schoolName: list.schoolName,
                         schoolYear: list.schoolYear,
                         items: items,
                         completedCount: completedCount,
                         totalCount: items.count)
    }

    // MARK: 2 — chips that compose

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(YearbookQuickFilter.allCases) { option in
                    YearbookFilterChip(label: option.label,
                                       isSelected: filter.quick == option) {
                        // Sets ONLY the quick filter. The live handler called
                        // clearFilters(), which was the defect.
                        filter.quick = option
                    }
                }

                Divider().frame(height: 20)

                ForEach(categories, id: \.self) { name in
                    YearbookFilterChip(label: name,
                                       isSelected: filter.category == name) {
                        filter.category = (filter.category == name) ? nil : name
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private var composeNote: some View {
        Text("Filters and search combine — type \"team\", tap Incomplete, tap Sports, and all three hold. Before AMB.10 a quick filter wiped both the typed text and the chosen category.")
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
                        // subset. The live header counted what was on screen, so
                        // under "Completed" every header read N/N and the screen
                        // claimed the book was finished.
                        AmbientSectionTitle(name,
                                            trailing: YearbookRules.categoryCountLabel(items, category: name))

                        LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                            ForEach(rows) { item in
                                YearbookItemRow(item: item) {
                                    toggle(item)
                                } onTap: {
                                    detail = item
                                }
                                .ambientScrollFade()
                            }
                        }
                    }
                }
            }

            Text("Category counts are of the whole category, not of what the filter left.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                withAnimation(AmbientMotion.snappy) { filter = .clear }
            },
            actionTint: YearbookMockup.featureTint)
    }

    /// The overflow menu keeps Export and loses one item. Said out loud, with the
    /// operator's veto explicitly available — a dropped control is exactly the
    /// class of thing this arc has lost silently four times.
    private var droppedMenuItemNote: some View {
        Text("The overflow menu keeps Export and DROPS \"Mark All Required Complete\": the live menu item called an empty function and had never done anything. Deliberately dropped rather than quietly kept. Export is unchanged, including that it exports EVERY item and ignores the filters and search, despite being called exportCompletedItems.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Item detail

/// A sheet, as today. Three additions, all of them about a save that can fail:
/// the live sheet dismissed unconditionally even on failure, surfaced no error,
/// and discarded unsaved notes when you toggled completion. All three are built —
/// see `Yearbook/Views/YearbookItemDetailView.swift`; the lab keeps the states as
/// a picker because a mockup can show all three at once and the real screen
/// cannot.
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
                if YearbookRules.showsOptionalBadge(item) {
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
    /// printed under "Session" is DROPPED: it is a database key with no lookup
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
                        Text(item.completedDate.map { Formatters.mediumDateTime.string(from: $0) } ?? "—")
                            .font(.subheadline)
                    }
                    Text("The raw session UUID the live sheet showed here is dropped — it is a database key with nothing behind it.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var imagesSection: some View {
        let count = YearbookRules.parseImageNumbers(imageNumbers).count
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
                           status: YearbookRules.hasNote(notes) ? "written" : "optional",
                           statusTint: YearbookRules.hasNote(notes) ? .orange : nil) {
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

            // The live `toggleCompletion` discarded whatever you typed in Notes and
            // Image Numbers, silently, and did not tell you.
            if labState == .unsaved {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                    Text("You have unsaved notes. Marking this complete saves them too — BUILT. Before AMB.10 toggling threw your edits away without a word.")
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

    /// The live sheet dismissed unconditionally, even when both of its two
    /// sequential writes failed. The photographer believed it saved.
    private var saveError: some View {
        VStack(alignment: .leading, spacing: 6) {
            YearbookInlineFailure(
                message: "Couldn't save — the server didn't answer. Your text is still here; try Save again.")

            Text("BUILT — before AMB.10 a failed save dismissed the sheet with no message, and the row kept the old value until the whole screen was rebuilt.")
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

    /// The live picker was a plain `VStack` of buttons NOT inside a ScrollView, so
    /// a school with several years pushed the older ones off the bottom of the
    /// screen with no way to reach them. Here — and now in the real screen — it
    /// scrolls.
    private var yearPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Select school year", trailing: "scrollable")

            Text("Multiple yearbook lists found for Westbrook High School.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: AmbientDensity.compact.stackSpacing) {
                    ForEach(YearbookLabData.years) { entry in
                        YearbookYearRow(year: entry.year, isCurrent: entry.isCurrent) {}
                    }
                }
            }
            .frame(maxHeight: 220)

            Text("Before AMB.10 this list was not in a ScrollView, so a school with six years of books hid the oldest three off-screen with no way to reach them.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The distinct failure state. The live catch block printed and rendered "No
    /// Yearbook List Found / No yearbook checklist exists for X", which is a
    /// factual claim about the school made on the strength of a dropped
    /// connection. A photographer who reads it stops looking.
    private var failureState: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Load failed", trailing: "BUILT")

            YearbookFailureCard(
                systemImage: "wifi.exclamationmark",
                title: "Couldn't load the checklist",
                message: "Westbrook High School may well have one — this device just couldn't reach the server.",
                retryTitle: "Retry",
                retry: {})

            Text("Before AMB.10 a network failure, a missing org id and a genuinely absent list all rendered the same screen: \"No yearbook checklist exists for this school.\" Two of those three were lies. There was also no retry, and if the first fetch returned nil the spinner never stopped.")
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

    // The relative formatter that used to live here moved to `YearbookStyle` in
    // YearbookKit — one instance for the lab AND the real screens, instead of the
    // live row's fresh `RelativeDateTimeFormatter` per body evaluation.

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
