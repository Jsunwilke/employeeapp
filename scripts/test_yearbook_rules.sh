#!/bin/bash
#
# Runs the REAL Yearbook rules — Iconik Employee/Yearbook/YearbookRules.swift
# compiled alongside the REAL Yearbook/Models/YearbookModels.swift, the same two
# files Xcode builds. Not a paraphrase in another language: a test that
# reimplements the logic proves nothing about the logic that ships.
#
# Every check here was proved able to FAIL before being kept (see
# --prove-can-fail, which reverts each rule in a scratch copy and expects a
# failure). A test that cannot fail is fake evidence in a costume.
#
#   ./scripts/test_yearbook_rules.sh
#   ./scripts/test_yearbook_rules.sh --prove-can-fail
#
set -euo pipefail

cd "$(dirname "$0")/.."
RULES="Iconik Employee/Yearbook/YearbookRules.swift"
MODELS="Iconik Employee/Yearbook/Models/YearbookModels.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for f in "$RULES" "$MODELS"; do
  if [[ ! -f "$f" ]]; then
    echo "FATAL: cannot find $f"
    exit 1
  fi
done

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var passed = 0
var failed = 0

func check(_ name: String, _ actual: String, _ expected: String) {
    if actual == expected {
        passed += 1
    } else {
        failed += 1
        print("  FAIL  \(name)")
        print("        expected: \(expected)")
        print("        actual:   \(actual)")
    }
}

func check(_ name: String, _ actual: Int, _ expected: Int) {
    check(name, "\(actual)", "\(expected)")
}

func check(_ name: String, _ actual: Double, _ expected: Double) {
    check(name, String(format: "%.4f", actual), String(format: "%.4f", expected))
}

func check(_ name: String, _ actual: Bool, _ expected: Bool) {
    check(name, "\(actual)", "\(expected)")
}

func check(_ name: String, _ actual: [String], _ expected: [String]) {
    check(name, actual.joined(separator: ","), expected.joined(separator: ","))
}

let cal = Calendar.current
func on(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = 12
    return cal.date(from: c)!
}

/// The display formatter the app passes in (`Formatters.monthDay`), pinned here so
/// the expected strings are a property of the rule and not of the device locale.
let monthDay: (Date) -> String = { date in
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MMM d"
    return f.string(from: date)
}

// ---------------------------------------------------------------------------
// THE FIXTURE. Seeded to contain every case that decides a rule: three
// categories; optional items that are genuinely rare (so the inverted badge can
// be judged); a completed item with attribution and image numbers; an item whose
// note is an EMPTY STRING (the case `!= nil` gets wrong); and repeated `order`
// values across categories (the unstable-sort trap).

func item(_ id: String,
          _ name: String,
          category: String,
          order: Int,
          completed: Bool = false,
          required: Bool = true,
          description: String? = nil,
          notes: String? = nil,
          images: [String]? = nil,
          photographer: String? = nil,
          date: Date? = nil) -> YearbookItem {
    YearbookItem(id: id, name: name, description: description, category: category,
                 required: required, completed: completed, completedDate: date,
                 photographerName: photographer, imageNumbers: images, notes: notes,
                 order: order)
}

let items: [YearbookItem] = [
    item("i1", "Varsity Football Team Photo", category: "Sports", order: 1, completed: true,
         description: "Full squad on the field, coaches at the ends.",
         notes: "Number 44 was absent — retake booked.",
         images: ["4102", "4103", "4110"],
         photographer: "Marisa Chen", date: on(2026, 7, 12)),
    item("i2", "Individual Player Portraits", category: "Sports", order: 2,
         description: "One frame per athlete, plain backdrop."),
    item("i3", "Action Shots — Home Game", category: "Sports", order: 3, completed: true,
         // EMPTY-STRING note: the old row tested `!= nil` and drew a badge over nothing.
         notes: "", images: ["4220"], photographer: "Devon Pike", date: on(2026, 7, 18)),
    item("i4", "Homecoming Court", category: "Sports", order: 4, required: false,
         description: "Only if the school runs one this year."),
    item("i5", "Class Group Photos", category: "Academics", order: 1, completed: true,
         description: "One per homeroom, in the gym.",
         images: ["3801"], photographer: "Marisa Chen", date: on(2026, 7, 2)),
    item("i6", "Teacher Portraits", category: "Academics", order: 2),
    item("i7", "Marching Band", category: "Clubs", order: 1, completed: true,
         photographer: "Devon Pike", date: on(2026, 7, 9))
]

func ids(_ rows: [YearbookItem]) -> [String] { rows.map(\.id) }

// ---------------------------------------------------------------------------
// 1. THE COMPOSED FILTER. Quick AND category AND search, all at once — the whole
// claim of the redesign. The old screen routed a quick-filter tap through
// clearFilters(), which reset the category and wiped the typed text.
print("the composed filter")

check("no filter shows everything", ids(YearbookRules.items(items, matching: .clear)).count, 7)
check("an empty search is not a search",
      ids(YearbookRules.items(items, matching: YearbookFilter(searchText: ""))).count, 7)
check("a whitespace-only search is not a search either",
      ids(YearbookRules.items(items, matching: YearbookFilter(searchText: "   \n "))).count, 7)

// Ordered by `order` then id — i2 and i6 both carry order 2 in different
// categories, which is the tie the unstable sort would otherwise decide.
check("incomplete only", ids(YearbookRules.items(items, matching: YearbookFilter(quick: .incomplete))),
      ["i2", "i6", "i4"])
check("completed only", ids(YearbookRules.items(items, matching: YearbookFilter(quick: .completed))),
      ["i1", "i5", "i7", "i3"])

check("category only", ids(YearbookRules.items(items, matching: YearbookFilter(category: "Sports"))),
      ["i1", "i2", "i3", "i4"])

check("search matches the NAME, case-insensitively",
      ids(YearbookRules.items(items, matching: YearbookFilter(searchText: "PORTRAITS"))),
      ["i2", "i6"])
check("search matches the DESCRIPTION too",
      ids(YearbookRules.items(items, matching: YearbookFilter(searchText: "homeroom"))), ["i5"])
check("search is trimmed before it is used",
      ids(YearbookRules.items(items, matching: YearbookFilter(searchText: "  homeroom  "))), ["i5"])
check("a search that matches nothing matches nothing",
      ids(YearbookRules.items(items, matching: YearbookFilter(searchText: "zzz"))).count, 0)
check("the category IS part of the text search — typing clubs surfaces the Clubs items (D12: the old screen searched it)",
      ids(YearbookRules.items(items, matching: YearbookFilter(searchText: "clubs"))), ["i7"])

// ALL THREE AT ONCE. This is the question the live app answers by throwing away.
check("category + quick + search compose",
      ids(YearbookRules.items(items, matching:
        YearbookFilter(quick: .incomplete, category: "Sports", searchText: "o"))),
      ["i2", "i4"])
check("…and a quick filter cannot widen a category",
      ids(YearbookRules.items(items, matching:
        YearbookFilter(quick: .completed, category: "Academics"))), ["i5"])
check("…nor can a category widen a search",
      ids(YearbookRules.items(items, matching:
        YearbookFilter(quick: .all, category: "Clubs", searchText: "portraits"))).count, 0)

check("a clear filter knows it is clear", YearbookFilter.clear.isClear, true)
check("a typed space does not make it dirty", YearbookFilter(searchText: " ").isClear, true)
check("a category makes it dirty", YearbookFilter(category: "Sports").isClear, false)
check("a quick filter makes it dirty", YearbookFilter(quick: .completed).isClear, false)

check("rows come back in `order`",
      ids(YearbookRules.items(items, matching: YearbookFilter(category: "Sports"))),
      ["i1", "i2", "i3", "i4"])

// ---------------------------------------------------------------------------
// 2. CATEGORY COUNTS ARE OF THE WHOLE CATEGORY. The old header counted the rows
// ON SCREEN, so under "Completed" every heading read N/N.
print("category counts")

check("categories in assembly order", YearbookRules.categories(in: items),
      ["Sports", "Academics", "Clubs"])
check("an empty list has no categories", YearbookRules.categories(in: []).count, 0)

check("Sports is 2 of 4", YearbookRules.categoryCountLabel(items, category: "Sports"), "2/4")
check("Academics is 1 of 2", YearbookRules.categoryCountLabel(items, category: "Academics"), "1/2")
check("Clubs is 1 of 1", YearbookRules.categoryCountLabel(items, category: "Clubs"), "1/1")
check("an unknown category is 0/0", YearbookRules.categoryCountLabel(items, category: "Nope"), "0/0")

// The filtered subset is NOT what the header counts: under "Completed", Sports
// has two rows on screen and the header must still say 2/4.
let completedOnly = YearbookRules.items(items, matching: YearbookFilter(quick: .completed))
check("the filtered subset does not change the header",
      YearbookRules.categoryCountLabel(items, category: "Sports"), "2/4")
check("…even though the filter left only two Sports rows",
      completedOnly.filter { $0.category == "Sports" }.count, 2)

check("a finished category is complete", YearbookRules.categoryIsComplete(items, category: "Clubs"), true)
check("a part-done category is not", YearbookRules.categoryIsComplete(items, category: "Sports"), false)
check("an EMPTY category is not complete — 0 of 0 is not an achievement",
      YearbookRules.categoryIsComplete(items, category: "Nope"), false)

check("summary lists up to three", YearbookRules.categorySummary(items) ?? "nil",
      "Sports, Academics, Clubs")
check("summary counts the rest",
      YearbookRules.categorySummary(items + [item("i8", "Fall Play", category: "Performing Arts", order: 1),
                                             item("i9", "Building Exterior", category: "Campus", order: 1)]) ?? "nil",
      "Sports, Academics, Clubs +2 more")
check("a zero-item list has no summary", YearbookRules.categorySummary([]) ?? "nil", "nil")

// ---------------------------------------------------------------------------
// 3. PROGRESS, GUARDED. A zero-item list must not divide by zero, and 0% is a NEW
// list rather than an error.
print("progress")

check("zero of zero is zero, not NaN", YearbookRules.progressFraction(completed: 0, total: 0), 0)
check("zero percent of zero", YearbookRules.progressPercent(completed: 0, total: 0), 0)
check("a brand-new list is 0%", YearbookRules.progressFraction(completed: 0, total: 12), 0)
check("half", YearbookRules.progressFraction(completed: 6, total: 12), 0.5)
check("100%", YearbookRules.progressFraction(completed: 12, total: 12), 1)
check("100 percent", YearbookRules.progressPercent(completed: 12, total: 12), 100)
check("percent rounds", YearbookRules.progressPercent(completed: 1, total: 3), 33)
check("percent rounds up", YearbookRules.progressPercent(completed: 2, total: 3), 67)
// completed_count is incremented ±1 from the STORED value by the service rather
// than recounted, so it can drift past the total. A ring trimmed past 1 laps.
check("a drifted count clamps at 1", YearbookRules.progressFraction(completed: 15, total: 12), 1)
check("a negative count clamps at 0", YearbookRules.progressFraction(completed: -2, total: 12), 0)

// ---------------------------------------------------------------------------
// 4. THE SCHOOL YEAR, SHORTENED — and left alone when it is not the expected shape.
print("school year")

check("the expected shape", YearbookRules.shortSchoolYear("2025-2026"), "2025-26")
check("last year", YearbookRules.shortSchoolYear("2024-2025"), "2024-25")
check("century roll", YearbookRules.shortSchoolYear("2099-2100"), "2099-00")
check("no separator passes through", YearbookRules.shortSchoolYear("2025"), "2025")
check("three parts pass through", YearbookRules.shortSchoolYear("2025-2026-2027"), "2025-2026-2027")
check("empty passes through", YearbookRules.shortSchoolYear(""), "")
check("a trailing separator passes through", YearbookRules.shortSchoolYear("2025-"), "2025-")
check("free text passes through", YearbookRules.shortSchoolYear("Fall term"), "Fall term")
check("a one-character tail is kept whole", YearbookRules.shortSchoolYear("2025-6"), "2025-6")
check("the title is school then short year",
      YearbookRules.listTitle(schoolName: "Westbrook High School", schoolYear: "2025-2026"),
      "Westbrook High School • 2025-26")

// ---------------------------------------------------------------------------
// 5. ATTRIBUTION. Both halves or nothing.
print("attribution")

check("name and date", YearbookRules.attribution(photographerName: "Marisa Chen",
                                                 completedDate: on(2026, 7, 12),
                                                 monthDay: monthDay) ?? "nil",
      "Marisa Chen · Jul 12")
check("no date, no line", YearbookRules.attribution(photographerName: "Marisa Chen",
                                                    completedDate: nil,
                                                    monthDay: monthDay) ?? "nil", "nil")
check("no name, no line", YearbookRules.attribution(photographerName: nil,
                                                    completedDate: on(2026, 7, 12),
                                                    monthDay: monthDay) ?? "nil", "nil")
check("a blank name is no name", YearbookRules.attribution(photographerName: "   ",
                                                           completedDate: on(2026, 7, 12),
                                                           monthDay: monthDay) ?? "nil", "nil")

// ---------------------------------------------------------------------------
// 6. THE NOTE BADGE tests EMPTINESS, not nil.
print("the note badge")

check("a real note", YearbookRules.hasNote("Number 44 was absent"), true)
check("nil is no note", YearbookRules.hasNote(nil), false)
check("an EMPTY STRING is no note", YearbookRules.hasNote(""), false)
check("whitespace is no note", YearbookRules.hasNote("  \n "), false)
check("the fixture's cleared note draws no badge", YearbookRules.hasNote(items[2].notes), false)
check("the fixture's real note does", YearbookRules.hasNote(items[0].notes), true)

// ---------------------------------------------------------------------------
// 7. THE INVERSION. `required` defaults to TRUE, so the badge marks the OPTIONAL few.
print("the optional badge")

check("required is the default", YearbookItem(name: "x", category: "y", order: 1).required, true)
check("a required item is not badged", YearbookRules.showsOptionalBadge(items[0]), false)
check("an optional item is", YearbookRules.showsOptionalBadge(items[3]), true)
check("exactly one row in the fixture is badged",
      items.filter(YearbookRules.showsOptionalBadge).count, 1)

// ---------------------------------------------------------------------------
// 8. IMAGE NUMBERS. Singularised, and parsed without inventing entries.
print("image numbers")

check("three", YearbookRules.imageCountLabel(["4102", "4103", "4110"]) ?? "nil", "3 images")
check("one is singular", YearbookRules.imageCountLabel(["4220"]) ?? "nil", "1 image")
check("none is nil", YearbookRules.imageCountLabel([]) ?? "nil", "nil")
check("nil is nil", YearbookRules.imageCountLabel(nil) ?? "nil", "nil")
check("blank entries do not count", YearbookRules.imageCountLabel(["", "  "]) ?? "nil", "nil")

check("parsed", YearbookRules.parseImageNumbers("4102, 4103, 4110"), ["4102", "4103", "4110"])
check("a trailing comma is not an image", YearbookRules.parseImageNumbers("4102,"), ["4102"])
check("padding is trimmed", YearbookRules.parseImageNumbers("  4102 ,  4103 "), ["4102", "4103"])
check("empty is empty", YearbookRules.parseImageNumbers("   ").count, 0)

// ---------------------------------------------------------------------------
// 9. THE ROOT LIST'S SEARCH. School OR year OR item name, all case-INSENSITIVE.
// The year was matched case-sensitively while everything beside it was not.
print("the root list search")

func list(_ id: String, school: String, year: String, active: Bool = true,
          completed: Int = 0, items rows: [YearbookItem] = []) -> YearbookShootList {
    YearbookShootList(id: id, organizationId: "org", schoolId: "school-\(school)",
                      schoolName: school, schoolYear: year,
                      startDate: on(2025, 8, 1), endDate: on(2026, 7, 31),
                      isActive: active, completedCount: completed, totalCount: rows.count,
                      items: rows, createdAt: on(2025, 8, 1), updatedAt: on(2026, 7, 20))
}

let lists = [
    list("yb-1", school: "Westbrook High School", year: "2025-2026", completed: 4, items: items),
    list("yb-2", school: "Westbrook High School", year: "2024-2025", active: false),
    list("yb-3", school: "Northgate Middle School", year: "2025-2026"),
    // A school_year is FREE TEXT written by the web app; this is the row that
    // discriminates a case-insensitive year match from a case-sensitive one.
    list("yb-4", school: "Riverside Elementary", year: "Fall2025-2026")
]

func listIds(_ rows: [YearbookShootList]) -> [String] { rows.map(\.id) }

check("an empty query matches everything", listIds(YearbookRules.lists(lists, matching: "")).count, 4)
check("whitespace matches everything", listIds(YearbookRules.lists(lists, matching: "  ")).count, 4)
check("school, case-insensitively", listIds(YearbookRules.lists(lists, matching: "northgate")), ["yb-3"])
check("year", listIds(YearbookRules.lists(lists, matching: "2024-2025")), ["yb-2"])
check("A YEAR MATCHES CASE-INSENSITIVELY — the live screen's year match was case-SENSITIVE",
      listIds(YearbookRules.lists(lists, matching: "fall2025")), ["yb-4"])
check("an item name inside the list", listIds(YearbookRules.lists(lists, matching: "marching band")), ["yb-1"])
check("nothing matches nothing", listIds(YearbookRules.lists(lists, matching: "zzz")).count, 0)

check("grouped by school, ascending",
      YearbookRules.groupedBySchool(lists).map(\.school),
      ["Northgate Middle School", "Riverside Elementary", "Westbrook High School"])
check("years within a school run DESCENDING",
      YearbookRules.groupedBySchool(lists).first { $0.school == "Westbrook High School" }?
        .lists.map(\.schoolYear) ?? [],
      ["2025-2026", "2024-2025"])

// ---------------------------------------------------------------------------
// 10. EMPTY, AND WHY. The old screen's empty check tested the UNFILTERED array,
// so a search that matched nothing rendered a blank screen.
print("empty, and why")

check("populated", YearbookRules.emptyReason(total: 7, shown: 3) == .populated, true)
check("nothing at all", YearbookRules.emptyReason(total: 0, shown: 0) == .nothingAtAll, true)
check("FILTERED OUT is not the same as empty",
      YearbookRules.emptyReason(total: 7, shown: 0) == .filteredOut, true)
check("…and it is specifically not 'nothing at all'",
      YearbookRules.emptyReason(total: 7, shown: 0) == .nothingAtAll, false)

// A zero-item list: the reason is nothingAtAll even with a filter typed, because
// there is nothing behind the filter either.
check("a zero-item list is empty, not filtered",
      YearbookRules.emptyReason(total: 0, shown: 0) == .filteredOut, false)
let zeroItemList = list("yb-5", school: "Riverside Elementary", year: "2025-2026")
check("a zero-item list has no progress",
      YearbookRules.progressFraction(completed: zeroItemList.completedCount,
                                     total: zeroItemList.totalCount), 0)
check("…and no categories", YearbookRules.categories(in: zeroItemList.items).count, 0)
check("…and filtering it yields nothing rather than crashing",
      YearbookRules.items(zeroItemList.items, matching: YearbookFilter(searchText: "team")).count, 0)

print("")
if failed == 0 {
    print("\(passed) checks passed.")
} else {
    print("\(passed) passed, \(failed) FAILED.")
    exit(1)
}
SWIFT

run_suite() {
  local rules_file="$1"
  local out="$WORK/run"
  if ! swiftc -O -o "$out" "$rules_file" "$MODELS" "$WORK/main.swift" 2>"$WORK/compile.log"; then
    echo "COMPILE FAILED"
    cat "$WORK/compile.log"
    return 2
  fi
  "$out"
}

if [[ "${1:-}" == "--prove-can-fail" ]]; then
  echo "Proving each rule's test can fail (reverting rules one at a time)…"
  echo ""
  # Each entry: label, then a perl expression that breaks exactly one rule.
  # A break that still passes means the corresponding checks are vacuous.
  declare -a BREAKS=(
    "the quick filter separates completed from incomplete|s/case \.incomplete: return !item\.completed/case .incomplete: return item.completed/"
    "the category clause applies|s/if let category = filter\.category, item\.category != category \{ return false \}/if let category = filter.category, category.isEmpty { return false }/"
    "the search text is trimmed|s/var query: String \{ searchText\.trimmingCharacters\(in: \.whitespacesAndNewlines\) \}/var query: String { searchText }/"
    "the search covers the description|s/description\.localizedCaseInsensitiveContains\(query\)/description.isEmpty/"
    "the search covers the CATEGORY (D12)|s/if item\\.category\\.localizedCaseInsensitiveContains\\(query\\) \\{ return true \\}//"
    "the filtered rows come back in order|s/\.sorted \{ \(\\\$0\.order, \\\$0\.id\) < \(\\\$1\.order, \\\$1\.id\) \}//"
    "a category count is of the WHOLE category|s/for item in items where item\.category == category \{/for item in items {/"
    "an empty category is not 'complete'|s/count\.total > 0 && count\.done == count\.total/count.done == count.total/"
    "the summary says how many more|s/extra > 0 \? .* : shown/shown/"
    "progress guards against zero items|s/guard total > 0 else \{ return 0 \}/guard total >= 0 else { return 0 }/"
    "progress clamps a drifted count|s/return min\(max\(raw, 0\), 1\)/return raw/"
    "the school year is shortened to two digits|s/String\(parts\[1\]\.suffix\(2\)\)/String(parts[1])/"
    "a malformed school year passes through|s/guard parts\.count == 2, !parts\[1\]\.isEmpty else \{ return schoolYear \}/guard parts.count >= 2 else { return schoolYear }/"
    "attribution needs a real name|s/!name\.isEmpty,/true,/"
    "attribution needs a date|s/let date = completedDate else \{ return nil \}/let date = Optional(completedDate ?? Date()) else { return nil }/"
    "the note badge tests emptiness, not nil|s/return !notes\.trimmingCharacters\(in: \.whitespacesAndNewlines\)\.isEmpty/return true/"
    "the OPTIONAL badge is the inversion|s/static func showsOptionalBadge\(_ item: YearbookItem\) -> Bool \{ !item\.required \}/static func showsOptionalBadge(_ item: YearbookItem) -> Bool { item.required }/"
    "one image is singular|s/numbers\.count == 1 \? \"1 image\"/numbers.count == 0 ? \"1 image\"/"
    "a blank image entry is not an image|s/!\\\$0\.trimmingCharacters\(in: \.whitespacesAndNewlines\)\.isEmpty/true/"
    "the root search matches the year CASE-INSENSITIVELY|s/if list\.schoolYear\.localizedCaseInsensitiveContains\(query\) \{ return true \}/if list.schoolYear.contains(query) { return true }/"
    "the root search reaches inside the items|s/return list\.items\.contains \{ \\\$0\.name\.localizedCaseInsensitiveContains\(query\) \}/return false/"
    "years within a school run descending|s/\\\$0\.schoolYear > \\\$1\.schoolYear/\$0.schoolYear < \$1.schoolYear/"
    "empty-because-filtered is distinct from empty|s/return total == 0 \? \.nothingAtAll : \.filteredOut/return .nothingAtAll/"
  )
  fails=0
  for entry in "${BREAKS[@]}"; do
    label="${entry%%|*}"
    expr="${entry#*|}"
    cp "$RULES" "$WORK/broken.swift"
    perl -pi -e "$expr" "$WORK/broken.swift"
    if cmp -s "$RULES" "$WORK/broken.swift"; then
      echo "  UNMATCHED  $label  (the perl expression changed nothing — fix the test, not the rule)"
      fails=$((fails+1))
      continue
    fi
    if run_suite "$WORK/broken.swift" >/dev/null 2>&1; then
      echo "  NOT PROVEN $label  (suite still passed with the rule reverted)"
      fails=$((fails+1))
    else
      echo "  proven     $label"
    fi
  done
  echo ""
  if [[ $fails -gt 0 ]]; then
    echo "$fails rule(s) are not covered by a failing test."
    exit 1
  fi
  echo "Every rule above is covered by a test that fails without it."
  exit 0
fi

run_suite "$RULES"
