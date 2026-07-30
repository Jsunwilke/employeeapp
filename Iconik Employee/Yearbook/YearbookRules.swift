//  YearbookRules.swift
//  Iconik Employee — the Yearbook domain rules, as compiled types
//
//  PRODUCTION CODE, COMPILED AND RUN BY `scripts/test_yearbook_rules.sh`
//  alongside the REAL `Yearbook/Models/YearbookModels.swift`. Not a paraphrase in
//  another language: a test that reimplements the logic proves nothing about the
//  logic that ships (the arc paid for that lesson once already).
//
//  NO SwiftUI IMPORT. Deliberate and load-bearing — `swiftc` compiles this file
//  standalone with the models. Anything that needs a `Color` or a `View` belongs
//  in `YearbookKit.swift`.
//
//  WHY THIS FILE EXISTS. Every decision the yearbook screens make about what to
//  show was written inline, once per screen, and four of them were wrong:
//
//    1. THE COMPOSED FILTER. Tapping "Incomplete" routed through the view model's
//       `clearFilters()`, which reset the category AND wiped the typed search — so
//       "which football items are still open" was a question the app answered by
//       throwing it away. Here the three parts compose and nothing resets anything
//       else.
//    2. THE CATEGORY COUNT IS OF THE WHOLE CATEGORY. The old header counted the
//       FILTERED rows, so under "Completed" every heading read N/N and the screen
//       claimed the book was finished.
//    3. THE NOTE BADGE TESTS EMPTINESS, NOT NIL. `item.notes != nil` kept the badge
//       forever on an item whose note had been cleared to "".
//    4. THE OPTIONAL BADGE IS THE INVERSION. `required` defaults to TRUE, so a
//       "REQUIRED" chip on nearly every row carried no information at all.
//
//  Plus the two arithmetic guards a list screen needs: a zero-item list must not
//  divide by zero, and a 0% list is a NEW list rather than an error.

import Foundation

// MARK: - The quick filter

/// All / Incomplete / Completed — the three-way completion filter.
///
/// It REPLACES the view model's `showCompletedOnly` + `showIncompleteOnly` pair of
/// booleans, which could both be true at once (an unrepresentable state that
/// silently meant "completed"), and the old `QuickFilter` enum whose `.required`
/// case fell through to `break` and did nothing at all.
enum YearbookQuickFilter: String, CaseIterable, Identifiable {
    case all
    case incomplete
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .incomplete: return "Incomplete"
        case .completed: return "Completed"
        }
    }

    func admits(_ item: YearbookItem) -> Bool {
        switch self {
        case .all: return true
        case .incomplete: return !item.completed
        case .completed: return item.completed
        }
    }
}

// MARK: - The composed filter

/// The whole filter state of the checklist screen, in one value.
///
/// THE POINT IS THAT IT IS ONE VALUE. Three independent pieces of `@Published`
/// state is what let a quick-filter tap reach over and clear the other two.
struct YearbookFilter: Equatable {
    var quick: YearbookQuickFilter = .all
    /// Nil is "every category". A category chip TOGGLES: tapping the selected one
    /// clears it, which is the only way back to all categories now that the quick
    /// filters no longer reset it.
    var category: String?
    var searchText: String = ""

    init(quick: YearbookQuickFilter = .all, category: String? = nil, searchText: String = "") {
        self.quick = quick
        self.category = category
        self.searchText = searchText
    }

    /// Whitespace-only is not a search. A user who types a space and deletes the
    /// word behind it must not be left looking at an empty screen.
    var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// True when nothing is filtering — the discriminator between "this list is
    /// empty" and "your filter matched nothing".
    var isClear: Bool { quick == .all && category == nil && query.isEmpty }

    static let clear = YearbookFilter()
}

/// Why a section of the screen has nothing in it. The old screen could not tell
/// these apart: its empty check tested the UNFILTERED array, so filtering to zero
/// rows rendered a blank list and looked broken.
enum YearbookEmptyReason: Equatable {
    /// There is content to draw.
    case populated
    /// There is genuinely nothing here.
    case nothingAtAll
    /// There is something here; the filter is hiding all of it.
    case filteredOut
}

// MARK: - The rules

enum YearbookRules {

    // MARK: 1 — the composed predicate

    /// Quick filter AND category AND search, all at once.
    ///
    /// Search covers the item's NAME, its DESCRIPTION, and its CATEGORY, all
    /// case-insensitively — the same three fields the old screen searched (D12:
    /// typing "Sports" has always surfaced every Sports item, and the chip bar
    /// existing beside the field does not make that capability disposable).
    static func matches(_ item: YearbookItem, filter: YearbookFilter) -> Bool {
        guard filter.quick.admits(item) else { return false }
        if let category = filter.category, item.category != category { return false }
        let query = filter.query
        guard !query.isEmpty else { return true }
        if item.name.localizedCaseInsensitiveContains(query) { return true }
        if let description = item.description,
           description.localizedCaseInsensitiveContains(query) { return true }
        if item.category.localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    /// The filtered rows, in the model's own `order`.
    ///
    /// `order` is per-category and therefore repeats across the array, and
    /// `sorted(by:)` is NOT stable — so the id breaks the tie rather than leaving
    /// the row order to the sort's internals.
    static func items(_ items: [YearbookItem], matching filter: YearbookFilter) -> [YearbookItem] {
        items.filter { matches($0, filter: filter) }.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    // MARK: 2 — categories and their FULL counts

    /// Categories in the order the book is assembled in — by the lowest `order` in
    /// each category, ties broken by first appearance — rather than the alphabet.
    ///
    /// Computed from a dictionary rather than by sorting the items, for the same
    /// reason as above: `order` repeats across categories and an unstable sort
    /// would let the chip bar and the section list disagree between two runs.
    static func categories(in items: [YearbookItem]) -> [String] {
        var minOrder: [String: Int] = [:]
        var firstIndex: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            if let existing = minOrder[item.category] {
                minOrder[item.category] = min(existing, item.order)
            } else {
                minOrder[item.category] = item.order
                firstIndex[item.category] = index
            }
        }
        return minOrder.keys.sorted {
            (minOrder[$0] ?? 0, firstIndex[$0] ?? 0) < (minOrder[$1] ?? 0, firstIndex[$1] ?? 0)
        }
    }

    /// done/total of the WHOLE category — never of the filtered subset.
    static func categoryCount(_ items: [YearbookItem], category: String) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for item in items where item.category == category {
            total += 1
            if item.completed { done += 1 }
        }
        return (done, total)
    }

    /// "3/7", from the full category.
    static func categoryCountLabel(_ items: [YearbookItem], category: String) -> String {
        let count = categoryCount(items, category: category)
        return "\(count.done)/\(count.total)"
    }

    /// True when every item in the category is done — and FALSE for an empty
    /// category, because "0 of 0 complete" is not an achievement to colour green.
    static func categoryIsComplete(_ items: [YearbookItem], category: String) -> Bool {
        let count = categoryCount(items, category: category)
        return count.total > 0 && count.done == count.total
    }

    /// The root card's one-line summary: the first three categories, then "+N more".
    static func categorySummary(_ items: [YearbookItem], limit: Int = 3) -> String? {
        let names = categories(in: items)
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(limit).joined(separator: ", ")
        let extra = names.count - min(names.count, limit)
        return extra > 0 ? "\(shown) +\(extra) more" : shown
    }

    // MARK: 3 — progress, guarded

    /// 0...1, never NaN.
    ///
    /// A list whose items have not been written yet carries `total_count == 0`, and
    /// the old row handed that straight to `ProgressView(value:total:)`. It also
    /// clamps: `completed_count` is incremented ±1 from the stored value by the
    /// service rather than recounted, so it CAN drift above the total, and a ring
    /// trimmed past 1 draws a second lap.
    static func progressFraction(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        let raw = Double(completed) / Double(total)
        return min(max(raw, 0), 1)
    }

    /// Whole percent for the ring's centre label.
    static func progressPercent(completed: Int, total: Int) -> Int {
        Int((progressFraction(completed: completed, total: total) * 100).rounded())
    }

    // MARK: 4 — the school year, shortened

    /// "2025-2026" → "2025-26". Anything else passes through untouched: the column
    /// is free text written by the web app, and inventing a shape for a value that
    /// does not have one is how a screen starts lying about which year it is showing.
    static func shortSchoolYear(_ schoolYear: String) -> String {
        let parts = schoolYear.split(separator: "-")
        guard parts.count == 2, !parts[1].isEmpty else { return schoolYear }
        return "\(parts[0])-\(String(parts[1].suffix(2)))"
    }

    /// "Westbrook High School • 2025-26"
    static func listTitle(schoolName: String, schoolYear: String) -> String {
        "\(schoolName) • \(shortSchoolYear(schoolYear))"
    }

    // MARK: 5 — attribution

    /// "Marisa Chen · Jul 12", or nil when either half is missing.
    ///
    /// The formatter is passed IN rather than built here: this file is compiled
    /// standalone by the test script, and a shared `DateFormatter` cache is the
    /// caller's business (`Formatters.monthDay`). The old row allocated a
    /// `DateFormatter` per row per body evaluation.
    static func attribution(photographerName: String?,
                            completedDate: Date?,
                            monthDay: (Date) -> String) -> String? {
        guard let name = photographerName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let date = completedDate else { return nil }
        return "\(name) · \(monthDay(date))"
    }

    // MARK: 6 — the note badge

    /// A note exists when there is TEXT in it. The old row tested `!= nil`, so an
    /// item whose note was cleared to "" kept its badge forever.
    static func hasNote(_ notes: String?) -> Bool {
        guard let notes else { return false }
        return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: 7 — the inversion

    /// `required` defaults to TRUE, so the badge marks the FEW optional items and
    /// the default carries no decoration at all.
    static func showsOptionalBadge(_ item: YearbookItem) -> Bool { !item.required }

    // MARK: 8 — image numbers

    /// "1 image" / "3 images", or nil when there are none. The old row was always
    /// plural.
    static func imageCountLabel(_ imageNumbers: [String]?) -> String? {
        let numbers = (imageNumbers ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !numbers.isEmpty else { return nil }
        return numbers.count == 1 ? "1 image" : "\(numbers.count) images"
    }

    /// The detail sheet's comma-separated field, parsed. Blank entries are dropped
    /// so "4102, " is one image number rather than two.
    static func parseImageNumbers(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: 9 — the root list's search

    /// School OR school year OR any item's name, all CASE-INSENSITIVE.
    ///
    /// DELIBERATE DIFFERENCE FROM THE LIVE SCREEN: the year was matched with
    /// `String.contains`, which is case-SENSITIVE, while the school and the item
    /// names beside it were not. Nothing about a school year is case-bearing, so
    /// the sensitivity was invisible until a query mixed the two — a consistency
    /// fix, recorded rather than slipped in.
    static func matchesListSearch(_ list: YearbookShootList, query rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if list.schoolName.localizedCaseInsensitiveContains(query) { return true }
        if list.schoolYear.localizedCaseInsensitiveContains(query) { return true }
        return list.items.contains { $0.name.localizedCaseInsensitiveContains(query) }
    }

    static func lists(_ lists: [YearbookShootList], matching query: String) -> [YearbookShootList] {
        lists.filter { matchesListSearch($0, query: query) }
    }

    /// Schools ascending; within a school, years DESCENDING (this year first).
    static func groupedBySchool(_ lists: [YearbookShootList]) -> [(school: String, lists: [YearbookShootList])] {
        Dictionary(grouping: lists) { $0.schoolName }
            .sorted { $0.key < $1.key }
            .map { (school: $0.key, lists: $0.value.sorted { $0.schoolYear > $1.schoolYear }) }
    }

    // MARK: 10 — empty, and WHY

    /// `total` is what exists; `shown` is what survived the filter.
    static func emptyReason(total: Int, shown: Int) -> YearbookEmptyReason {
        if shown > 0 { return .populated }
        return total == 0 ? .nothingAtAll : .filteredOut
    }
}
