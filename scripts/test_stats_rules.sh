#!/bin/bash
#
# Runs the REAL Stats rules — Iconik Employee/Stats/StatsRules.swift compiled
# alongside the REAL Misc Features/VehicleRates.swift, the same two files Xcode
# builds. Not a paraphrase in another language: a test that reimplements the
# logic proves nothing about the logic that ships.
#
# Every check here was proved able to FAIL before being kept (see
# --prove-can-fail, which reverts each rule in a scratch copy and expects a
# failure). A test that cannot fail is fake evidence in a costume.
#
#   ./scripts/test_stats_rules.sh
#   ./scripts/test_stats_rules.sh --prove-can-fail
#
set -euo pipefail

cd "$(dirname "$0")/.."
RULES="Iconik Employee/Stats/StatsRules.swift"
RATES="Iconik Employee/Misc Features/VehicleRates.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for f in "$RULES" "$RATES"; do
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

func check(_ name: String, _ actual: [Int], _ expected: [Int]) {
    check(name,
          actual.map(String.init).joined(separator: ","),
          expected.map(String.init).joined(separator: ","))
}

let cal = Calendar.current
func on(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = 12
    return cal.date(from: c)!
}

func bar(_ months: [StatsMonthBucket], _ key: Int) -> StatsMonthBucket? {
    months.first { $0.id == key }
}

// ---------------------------------------------------------------------------
// THE DAY. A `timestamp with time zone` column used as a day, read as a day.
// Re-interpreting the instant in the device's zone is the boundary defect the
// parity inventory names (§4) — it moves a midnight-UTC report into the previous
// month in every western zone.
print("the stored day")

check("bare day",            StatsDay(stored: "2026-07-15")?.storageString ?? "nil", "2026-07-15")
check("whole-second stamp",  StatsDay(stored: "2026-07-15T00:00:00+00:00")?.storageString ?? "nil", "2026-07-15")
check("fractional stamp",    StatsDay(stored: "2026-07-15T00:00:00.123456+00:00")?.storageString ?? "nil", "2026-07-15")
check("padded",              StatsDay(stored: "  2026-07-15T00:00:00Z \n")?.storageString ?? "nil", "2026-07-15")
// A midnight-UTC report on the FIRST of a month stays on the first. This is the
// single assertion the old bucketing could not make.
check("first of month holds", StatsDay(stored: "2026-07-01T00:00:00+00:00")?.month ?? -1, 7)
check("nil is nil",          StatsDay(stored: nil)?.storageString ?? "nil", "nil")
check("garbage rejected",    StatsDay(stored: "not a date")?.storageString ?? "nil", "nil")
check("short rejected",      StatsDay(stored: "2026-07")?.storageString ?? "nil", "nil")
check("month 13 rejected",   StatsDay(stored: "2026-13-01")?.storageString ?? "nil", "nil")
check("month key carries the year", StatsDay(stored: "2025-12-05")!.monthKey, 202512)
check("…and differs from the same month a year later",
      StatsDay(stored: "2025-12-05")!.monthKey == StatsDay(stored: "2026-12-05")!.monthKey, false)

// ---------------------------------------------------------------------------
// THE PERIOD. Real calendar boundaries, named by the period they are.
print("calendar periods")

let julyMid = on(2026, 7, 15)
check("month label",   StatsPeriod.month.label(reference: julyMid), "July")
check("quarter label",  StatsPeriod.quarter.label(reference: on(2026, 8, 20)), "Q3")
check("year label",    StatsPeriod.year.label(reference: julyMid), "2026")
check("Q1 boundary",   StatsPeriod.quarter.label(reference: on(2026, 3, 31)), "Q1")
check("Q2 boundary",   StatsPeriod.quarter.label(reference: on(2026, 4, 1)), "Q2")

let monthWindow = StatsPeriod.month.window(reference: julyMid)
check("month starts on the 1st", monthWindow.firstDay.storageString, "2026-07-01")
check("month ends on the 31st",  monthWindow.lastDay.storageString, "2026-07-31")
check("context reaches back two months", monthWindow.contextFirstDay.storageString, "2026-05-01")
check("query gte",  monthWindow.queryFirstDayString, "2026-05-01")
check("query lt",   monthWindow.queryEndExclusiveString, "2026-08-01")
check("month span", monthWindow.spanLabel, "Jul 1 – Jul 31, 2026 · to date")
check("a finished period drops 'to date'",
      StatsPeriod.month.window(reference: on(2026, 7, 31)).spanLabel, "Jul 1 – Jul 31, 2026")
check("30-day month ends on the 30th",
      StatsPeriod.month.window(reference: on(2026, 6, 9)).lastDay.storageString, "2026-06-30")
check("February 2028 ends on the 29th",
      StatsPeriod.month.window(reference: on(2028, 2, 9)).lastDay.storageString, "2028-02-29")
check("February 2026 ends on the 28th",
      StatsPeriod.month.window(reference: on(2026, 2, 9)).lastDay.storageString, "2026-02-28")

// A trailing 31-day window from mid-August would start on 18 July. Q3 starts on
// 1 July, and this is the check that discriminates the two.
let quarterWindow = StatsPeriod.quarter.window(reference: on(2026, 8, 20))
check("quarter starts at the quarter", quarterWindow.firstDay.storageString, "2026-07-01")
check("quarter ends at the quarter",   quarterWindow.lastDay.storageString, "2026-09-30")
check("quarter context",               quarterWindow.contextFirstDay.storageString, "2026-05-01")
check("quarter span", quarterWindow.spanLabel, "Jul 1 – Sep 30, 2026 · to date")

let yearWindow = StatsPeriod.year.window(reference: on(2026, 12, 10))
check("year starts 1 Jan",  yearWindow.firstDay.storageString, "2026-01-01")
check("year ends 31 Dec",   yearWindow.lastDay.storageString, "2026-12-31")
// The context months cross New Year, which is exactly why the buckets are keyed
// by year AND month.
check("year context crosses New Year", yearWindow.contextFirstDay.storageString, "2025-11-01")
check("year query lt", yearWindow.queryEndExclusiveString, "2027-01-01")

check("period containment", yearWindow.contains(StatsDay(stored: "2026-01-01")!), true)
check("context is NOT in the period", yearWindow.contains(StatsDay(stored: "2025-12-31")!), false)
check("context is fetched", yearWindow.isFetched(StatsDay(stored: "2025-12-31")!), true)
check("before the context is not fetched", yearWindow.isFetched(StatsDay(stored: "2025-10-31")!), false)

// ---------------------------------------------------------------------------
// THE AGGREGATION. One fixture, read from every angle.
print("aggregation")

// TWO EMPLOYEES CALLED CHRIS, with different ids — the roster defect the parity
// doc records (the old roster was keyed on first_name alone and merged them).
let people = [
    StatsPersonRecord(id: "aaaaaaaa-0000-0000-0000-000000000001", firstName: "Chris", amountPerMile: 0.80),
    StatsPersonRecord(id: "bbbbbbbb-0000-0000-0000-000000000002", firstName: "Chris", amountPerMile: nil),
    StatsPersonRecord(id: "cccccccc-0000-0000-0000-000000000003", firstName: "Maria", amountPerMile: 0)
]
let chrisA = "AAAAAAAA-0000-0000-0000-000000000001"   // UPPERCASE on purpose: Swift mints
let chrisB = "bbbbbbbb-0000-0000-0000-000000000002"   // uppercase UUIDs, Supabase stores lower
let maria  = "cccccccc-0000-0000-0000-000000000003"

let reports = [
    StatsReport(userId: chrisA, yourName: "Chris A", day: StatsDay(stored: "2026-07-02T00:00:00+00:00"),
                miles: 10, vehicleType: "personal", destination: "Westfield",
                jobDescriptions: ["Fall Portraits", "Sports"]),
    // Same school, same day → ONE visit, both lots of miles.
    StatsReport(userId: chrisA, yourName: "Chris A", day: StatsDay(stored: "2026-07-02"),
                miles: 5, vehicleType: "personal", destination: "Westfield"),
    StatsReport(userId: chrisB, yourName: "Chris N", day: StatsDay(stored: "2026-07-10"),
                miles: 20, vehicleType: "company", destination: "Northgate",
                jobDescriptions: ["Graduation"]),
    // ZERO MILEAGE. Still a trip — the old screen did not count it as a job at all.
    StatsReport(userId: maria, yourName: "Maria", day: StatsDay(stored: "2026-07-11"),
                miles: 0, vehicleType: "personal", destination: "Northgate",
                jobDescriptions: ["Fall Portraits"]),
    // No user_id at all: still carries miles, still a trip.
    StatsReport(userId: nil, yourName: "Guest", day: StatsDay(stored: "2026-07-12"),
                miles: 7.5, vehicleType: nil, destination: nil),
    // Case- and whitespace-variant destination: the same place.
    StatsReport(userId: maria, yourName: "Maria", day: StatsDay(stored: "2026-07-31"),
                miles: 3, vehicleType: "personal", destination: "  westfield  ",
                jobDescriptions: ["  "]),
    // CONTEXT month: drawn dimmed, in NO total.
    StatsReport(userId: chrisA, yourName: "Chris A", day: StatsDay(stored: "2026-06-20"),
                miles: 100, vehicleType: "personal", destination: "Westfield",
                jobDescriptions: ["Fall Portraits"]),
    // Before the fetch window: must not appear anywhere.
    StatsReport(userId: chrisA, yourName: "Chris A", day: StatsDay(stored: "2026-04-30"),
                miles: 999, vehicleType: "personal", destination: "Westfield"),
    // Undated: skipped, never defaulted to today.
    StatsReport(userId: chrisA, yourName: "Chris A", day: nil,
                miles: 500, vehicleType: "personal", destination: "Westfield")
]

let july = StatsAggregator.aggregate(reports: reports, people: people, companyCarRate: 0.15,
                                     period: .month, reference: julyMid)

check("period label carried", july.periodLabel, "July")
check("span carried",         july.spanLabel, "Jul 1 – Jul 31, 2026 · to date")

// TOTALS. 10 + 5 + 20 + 0 + 7.5 + 3. The doubled-accumulator shape gives 91.
check("total miles",  july.totalMiles, 45.5)
check("total trips",  july.totalTrips, 6)
check("photographers", july.photographerCount, 4)
check("schools visited", july.schoolsVisited, 2)
check("not empty", july.isEmpty, false)

// The tiles are the sum of the sections, and the bars agree with the tiles.
check("bars inside the period equal the total", july.inPeriodBarMiles, july.totalMiles)

// PER PHOTOGRAPHER, keyed by user_id — lowercased on both sides.
let byKey = Dictionary(uniqueKeysWithValues: july.photographers.map { ($0.key, $0) })
check("the two Chrises stay apart", byKey.count, 4)
let a = byKey[chrisA.lowercased()]
check("Chris A trips", a?.trips ?? -1, 2)
check("Chris A miles", a?.miles ?? -1, 15)
check("Chris A name from users.first_name", a?.name ?? "nil", "Chris")
// HIS OWN RATE, not a flat 0.67: 15 × 0.80.
check("Chris A reimbursement at his own rate", a?.reimbursement ?? -1, 12.0)

let b = byKey[chrisB]
check("Chris B is company miles", b?.companyMiles ?? -1, 20)
check("Chris B has no personal miles", b?.personalMiles ?? -1, 0)
// Company miles pay the ORG rate: 20 × 0.15.
check("Chris B reimbursement at the org company rate", b?.reimbursement ?? -1, 3.0)

let m = byKey[maria]
check("Maria trips include the zero-mileage report", m?.trips ?? -1, 2)
check("Maria miles", m?.miles ?? -1, 3)
// amount_per_mile of 0 is falsy → the IRS fallback, per VehicleRates.
check("a zero rate falls back to 0.67", m?.reimbursement ?? -1, 2.01)

let guest = byKey[StatsAggregator.crewKey(for: reports[4])]
check("an un-linked report still gets a row", guest?.name ?? "nil", "Guest")
check("…and its miles are in the total", guest?.miles ?? -1, 7.5)
check("…at the fallback rate", guest?.reimbursement ?? -1, 5.025)
check("total reimbursement is the sum of the rows", july.totalReimbursement, 22.035)

check("photographers are miles-descending", july.photographers.map { Int($0.miles) }, [20, 15, 7, 3])
check("…and trips-descending on request", july.photographersByTrips.first?.trips ?? -1, 2)

// DESTINATIONS. One visit per place per day; miles summed; case-variant merged.
let places = Dictionary(uniqueKeysWithValues: july.destinations.map { ($0.id, $0) })
check("two reports at one school on one day is ONE visit", places["westfield"]?.visits ?? -1, 2)
check("…and both lots of miles", places["westfield"]?.miles ?? -1, 18)
check("northgate visits", places["northgate"]?.visits ?? -1, 2)
check("northgate miles", places["northgate"]?.miles ?? -1, 20)
check("a report with no destination is not a place", july.destinations.count, 2)
check("destinations sort by visits then miles", july.destinations.first?.name ?? "nil", "Northgate")
check("top five is a prefix", july.topDestinations.count, 2)

// JOB TYPES. Counts from the array, whole percents of all entries.
check("job types found", july.jobTypes.count, 3)
check("the blank entry is not a job type",
      july.jobTypes.contains { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }, false)
let types = Dictionary(uniqueKeysWithValues: july.jobTypes.map { ($0.id, $0) })
check("Fall Portraits count", types["fall portraits"]?.count ?? -1, 2)
check("Fall Portraits percent", types["fall portraits"]?.percent ?? -1, 50)
check("Graduation percent", types["graduation"]?.percent ?? -1, 25)
check("job types sort count-descending then name", july.jobTypes.map(\.name).joined(separator: ","),
      "Fall Portraits,Graduation,Sports")

// MONTH BARS. May and June dimmed, July live; the June miles are in NO total.
check("three bars", july.months.count, 3)
check("bars are chronological", july.months.map(\.id), [202605, 202606, 202607])
check("May is context", bar(july.months, 202605)?.isComparison ?? false, true)
check("May is empty", bar(july.months, 202605)?.miles ?? -1, 0)
check("June is context", bar(july.months, 202606)?.isComparison ?? false, true)
check("June carries its miles", bar(july.months, 202606)?.miles ?? -1, 100)
check("July is not context", bar(july.months, 202607)?.isComparison ?? true, false)
check("July miles", bar(july.months, 202607)?.miles ?? -1, 45.5)
check("bar labels carry the year", bar(july.months, 202606)?.yearLabel ?? "nil", "2026")
check("bar labels name the month", bar(july.months, 202606)?.monthLabel ?? "nil", "Jun")
// The out-of-window and undated rows are nowhere: 999 and 500 would show up in
// the total or in an April bar.
check("out-of-window reports are absent", july.months.contains { $0.miles == 999 }, false)

// ---------------------------------------------------------------------------
// TWO DECEMBERS. The year-less key summed them into one bar.
print("two Decembers")

let decembers = [
    StatsReport(userId: chrisA, day: StatsDay(stored: "2025-12-05"), miles: 100,
                vehicleType: "personal", destination: "Westfield"),
    StatsReport(userId: chrisA, day: StatsDay(stored: "2026-12-05"), miles: 50,
                vehicleType: "personal", destination: "Westfield")
]
let year = StatsAggregator.aggregate(reports: decembers, people: people, companyCarRate: 0.15,
                                     period: .year, reference: on(2026, 12, 10))
check("Nov 2025 through Dec 2026 is 14 bars", year.months.count, 14)
check("December 2025 keeps its own 100 miles", bar(year.months, 202512)?.miles ?? -1, 100)
check("December 2026 keeps its own 50 miles", bar(year.months, 202612)?.miles ?? -1, 50)
check("December 2025 is context", bar(year.months, 202512)?.isComparison ?? false, true)
check("December 2026 is not", bar(year.months, 202612)?.isComparison ?? true, false)
// Last year's December is NOT in this year's totals.
check("the year total is this year only", year.totalMiles, 50)
check("bars in the period equal the total", year.inPeriodBarMiles, 50)

// ---------------------------------------------------------------------------
// THE BARS NEVER HIDE IN-PERIOD MILES, and never draw a future month as a zero.
print("bar range")

let augustRef = on(2026, 8, 20)
let quiet = StatsAggregator.aggregate(reports: [], people: people, companyCarRate: 0.15,
                                      period: .quarter, reference: augustRef)
check("an empty quarter stops at this month", quiet.months.map(\.id), [202605, 202606, 202607, 202608])
check("an empty period is empty", quiet.isEmpty, true)
check("…with no photographers", quiet.photographerCount, 0)
check("…and no invented total", quiet.totalMiles, 0)

let futureDated = [
    StatsReport(userId: chrisA, day: StatsDay(stored: "2026-09-15"), miles: 40,
                vehicleType: "personal", destination: "Westfield")
]
let stretched = StatsAggregator.aggregate(reports: futureDated, people: people, companyCarRate: 0.15,
                                          period: .quarter, reference: augustRef)
check("a later in-period month extends the bars",
      stretched.months.map(\.id), [202605, 202606, 202607, 202608, 202609])
check("…so the bars still equal the total", stretched.inPeriodBarMiles, stretched.totalMiles)

// ---------------------------------------------------------------------------
// THE PERCENT GUARD. `Int(Double.nan)` traps, so an unguarded division here is a
// CRASH on an empty period, not a wrong label.
print("percent guard")
check("no entries yields 0%", StatsAggregator.percent(0, of: 0), 0)
check("all of them is 100%", StatsAggregator.percent(3, of: 3), 100)
check("rounded, not truncated", StatsAggregator.percent(1, of: 3), 33)
check("rounded up", StatsAggregator.percent(2, of: 3), 67)

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
  if ! swiftc -O -o "$out" "$rules_file" "$RATES" "$WORK/main.swift" 2>"$WORK/compile.log"; then
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
    "the day is read from the stored string|s/text\.prefix\(10\)/text.prefix(11)/"
    "a period starts on the 1st, not today|s/month: firstMonth, day: 1/month: firstMonth, day: today.day/"
    "a quarter starts at the quarter|s/\(StatsPeriod\.quarterNumber\(ofMonth: today\.month\) - 1\) \* 3 \+ 1/today.month/"
    "a period ends on the month's real last day|s/case 1, 3, 5, 7, 8, 10, 12: return 31/case 1, 3, 5, 7, 8, 10, 12: return 30/"
    "month buckets are keyed by year AND month|s/var monthKey: Int \{ year \* 100 \+ month \}/var monthKey: Int { month }/"
    "monthly miles are added once|s/milesByMonth\[day\.monthKey, default: 0\] \+= report\.miles/milesByMonth[day.monthKey, default: 0] += report.miles * 2/"
    "photographer miles are added once|s/crew\.split\.add\(miles: report\.miles,/crew.split.add(miles: report.miles * 2,/"
    "a zero-mileage report is still a trip|s/crew\.trips \+= 1/if report.miles > 0 { crew.trips += 1 }/"
    "context months are excluded from the totals|s/guard inPeriod else \{ continue \}/if false { continue }/"
    "context bars are flagged as context|s/isComparison: key < firstKey/isComparison: false/"
    "a visit is one destination per day|s/if !visitKeys\.contains\(visitKey\) \{/if true {/"
    "each photographer's own rate is used|s/personalRate: VehicleRates\.resolvePersonalRate\(person\?\.amountPerMile\)/personalRate: VehicleRates.defaultMileageRate/"
    "reports are keyed by user_id when there is one|s/if let id = trimmed\(report\.userId\) \{ return id\.lowercased\(\) \}//"
    "the percent share is guarded against an empty period|s/guard total > 0 else \{ return 0 \}/guard total >= 0 else { return 0 }/"
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
