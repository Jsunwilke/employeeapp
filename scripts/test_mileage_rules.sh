#!/bin/bash
#
# Runs the REAL MileageRules.swift — the same file Xcode compiles — together with
# the REAL VehicleRates.swift it accumulates money through, and checks their rules.
# Not a paraphrase in another language: a test that reimplements the logic proves
# nothing about the logic that ships. That mistake was made once on this arc and the
# operator's verdict was that the logic was fake and did not do anything.
#
# Every check here was proved able to FAIL before being kept (see --prove-can-fail,
# which reverts each rule in a scratch copy and expects a failure). A test that
# cannot fail is fake evidence in a costume.
#
#   ./scripts/test_mileage_rules.sh
#   ./scripts/test_mileage_rules.sh --prove-can-fail
#
# WHAT THIS HARNESS CANNOT REACH, stated rather than faked: the zero-row-UPDATE
# guard added to `DailyJobReportService` (a write that matches nothing now throws
# instead of returning a 200 the screen reports as a save). It needs a live
# PostgREST round trip, and this script compiles Foundation-only value types with
# swiftc — there is no client, no network and no table here. It is verified by
# reading the request path and on the device, not pretended at with a stub.
#
# main.swift naming: Swift only executes top-level code from a file with that name,
# so the harness is written out as main.swift rather than compiled by its own name.
set -euo pipefail

cd "$(dirname "$0")/.."
RULES="Iconik Employee/Misc Features/MileageRules.swift"
RATES="Iconik Employee/Misc Features/VehicleRates.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for file in "$RULES" "$RATES"; do
  if [[ ! -f "$file" ]]; then
    echo "FATAL: cannot find $file"
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

func check(_ name: String, _ actual: Int, _ expected: Int) { check(name, "\(actual)", "\(expected)") }
func check(_ name: String, _ actual: Bool, _ expected: Bool) { check(name, "\(actual)", "\(expected)") }
func check(_ name: String, _ actual: Double, _ expected: Double) {
    check(name, String(format: "%.4f", actual), String(format: "%.4f", expected))
}

let calendar = Calendar.current

// A POSIX "MMM d" so the labels are checked against fixed text rather than against
// whatever region the machine running this happens to be set to.
let monthDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MMM d"
    return f
}()
func monthDay(_ date: Date) -> String { monthDayFormatter.string(from: date) }

func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

// ── The cycle. The carousel used to step a HARDCODED 14 days while the data came
//    from PayPeriodService, so a weekly or monthly org saw labels and totals that
//    described different spans. The caption must describe the boundaries actually
//    drawn, which means mirroring the service's fallbacks and not just its cases.
print("the org's cycle")
check("weekly",            MileagePeriodCycle.from(type: "weekly", isActive: true).rawValue, "weekly")
check("bi-weekly",         MileagePeriodCycle.from(type: "bi-weekly", isActive: true).rawValue, "biweekly")
check("biweekly no dash",  MileagePeriodCycle.from(type: "biweekly", isActive: true).rawValue, "biweekly")
check("mixed case",        MileagePeriodCycle.from(type: "Bi-Weekly", isActive: true).rawValue, "biweekly")
check("padded",            MileagePeriodCycle.from(type: "  monthly \n", isActive: true).rawValue, "monthly")
check("monthly",           MileagePeriodCycle.from(type: "monthly", isActive: true).rawValue, "monthly")
// PayPeriodService falls to bi-weekly for an unknown type and for inactive or
// missing settings. A caption that said "Monthly" over 14-day boundaries would be
// the same lie the old title told.
check("unknown type",      MileagePeriodCycle.from(type: "fortnightly", isActive: true).rawValue, "biweekly")
check("nil type",          MileagePeriodCycle.from(type: nil, isActive: true).rawValue, "biweekly")
check("empty type",        MileagePeriodCycle.from(type: "", isActive: true).rawValue, "biweekly")
check("inactive settings", MileagePeriodCycle.from(type: "monthly", isActive: false).rawValue, "biweekly")

check("weekly caption",   MileagePeriodCycle.weekly.caption, "Weekly pay periods")
check("biweekly caption", MileagePeriodCycle.biweekly.caption, "Bi-weekly pay periods")
check("monthly caption",  MileagePeriodCycle.monthly.caption, "Monthly pay periods")

// ── The six chips, built by walking backwards through the REAL resolver.
print("the period carousel")

// A bi-weekly cycle anchored on Monday 20 July 2026 — the shape PayPeriodService
// answers in for `type: "bi-weekly"`.
let anchor = date(2026, 7, 20)
func biweekly(_ probe: Date) -> (start: Date, end: Date)? {
    let days = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: probe)).day ?? 0
    let elapsed = Int(floor(Double(days) / 14.0))
    let start = calendar.date(byAdding: .day, value: 14 * elapsed, to: anchor)!
    return (start, calendar.date(byAdding: .day, value: 13, to: start)!)
}

let fortnights = MileagePeriodSequence.build(now: anchor, calendar: calendar, resolve: biweekly)
check("six chips",      fortnights.count, 6)
check("index 0 first",  fortnights.first?.index ?? -1, 0)
check("0 is current",   fortnights.first?.isCurrent ?? false, true)
check("1 is not",       fortnights[1].isCurrent, false)
check("newest first",   fortnights[0].start > fortnights[1].start, true)
check("chip 0 range",   fortnights[0].rangeLabel(monthDay: monthDay), "Jul 20 – Aug 2")
check("chip 1 range",   fortnights[1].rangeLabel(monthDay: monthDay), "Jul 6 – Jul 19")
check("chip 5 range",   fortnights[5].rangeLabel(monthDay: monthDay), "May 11 – May 24")

// CONTIGUOUS AND NON-OVERLAPPING: each chip ends the day before the newer one
// starts. A step that skips or doubles a day loses or double-counts a report's
// mileage, which is money.
var contiguous = true
for index in 0..<(fortnights.count - 1) {
    let expectedEnd = calendar.date(byAdding: .day, value: -1,
                                    to: calendar.startOfDay(for: fortnights[index].start))!
    if calendar.startOfDay(for: fortnights[index + 1].end) != expectedEnd { contiguous = false }
}
check("chips are contiguous", contiguous, true)

// Claim 3: THE HEADER IS DERIVED FROM THE SELECTION. The old card was titled
// "Current Period" permanently while its values were replaced.
check("current header", fortnights[0].headerLabel(monthDay: monthDay),
      "This pay period · Jul 20 – Aug 2")
check("past header",    fortnights[1].headerLabel(monthDay: monthDay), "Jul 6 – Jul 19")
check("past header has no claim",
      fortnights[1].headerLabel(monthDay: monthDay).contains("This pay period"), false)

// ── THE WALK STOPS RATHER THAN DRAWING A CHIP THAT IS NOT A PERIOD.
//
// WHAT USED TO BE HERE, AND WHY IT IS GONE: a hand-written "monthly" resolver that
// answered whole calendar months, checked to produce six neat chips. Production's
// monthly resolver does NOT do that. `PayPeriodService.getMonthlyPayPeriod` sets
// `components.day = startDay` and lets Foundation roll an out-of-range day forward,
// so an org anchored on the 29th or the 31st gets overlapping and gap-leaving
// answers. A test asserting behaviour production does not have is fake evidence, so
// the fiction is deleted and what is tested instead is the GUARD that copes with
// the real shapes — the two below are the actual sequences the live resolver
// returns for those anchors (reproduced against PayPeriodService's own arithmetic).
//
// SHAPE 1 — a day-31 anchor. Production answers "Jul 1 – Jul 31" for a July probe
// and then "May 31 – Jun 29" for the Jun 30 probe: Jun 30 belongs to NO period.
// Mileage filed on a skipped day would appear in no chip, so the walk must stop
// with the one honest chip rather than draw a carousel with a hole in it.
var day31Probes: [Date] = []
func day31Anchored(_ probe: Date) -> (start: Date, end: Date)? {
    day31Probes.append(probe)
    if probe >= date(2026, 7, 1) { return (date(2026, 7, 1), date(2026, 7, 31)) }
    return (date(2026, 5, 31), date(2026, 6, 29))
}
let day31 = MileagePeriodSequence.build(now: date(2026, 7, 15), calendar: calendar, resolve: day31Anchored)
check("gap-leaving resolver stops", day31.count, 1)
check("the honest chip is kept",    day31.first?.rangeLabel(monthDay: monthDay) ?? "none", "Jul 1 – Jul 31")
// The walk did probe again — it stopped on the ANSWER, not by refusing to ask.
check("the walk did ask for more",  day31Probes.count >= 2, true)

// SHAPE 2 — a day-29 anchor. The chips run back Jun 29, May 29, Apr 29, Mar 29, and
// then the Mar 28 probe answers "Mar 1 – Mar 31" (Feb 29 does not exist in 2026, so
// the rolled-forward day lands in March): an answer that OVERLAPS the chip already
// drawn and leaves Feb 28 in no period. It is not non-decreasing — Mar 1 is before
// Mar 29 — so only the contiguity guard can catch it.
func day29Anchored(_ probe: Date) -> (start: Date, end: Date)? {
    let starts = [date(2026, 6, 29), date(2026, 5, 29), date(2026, 4, 29), date(2026, 3, 29)]
    for start in starts where probe >= start {
        return (start, calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!)
    }
    // The rolled-forward Feb 29 → Mar 1 answer.
    return (date(2026, 3, 1), date(2026, 3, 31))
}
let day29 = MileagePeriodSequence.build(now: date(2026, 7, 15), calendar: calendar, resolve: day29Anchored)
check("overlapping resolver stops", day29.count, 4)
check("last honest chip",  day29[3].rangeLabel(monthDay: monthDay), "Mar 29 – Apr 28")
// TRUNCATED BUT CONSISTENT: whatever the walk kept is still contiguous and ordered.
func isConsistent(_ chips: [MileagePeriod]) -> Bool {
    for index in 0..<max(0, chips.count - 1) {
        if chips[index].start <= chips[index + 1].start { return false }
        let expectedEnd = calendar.date(byAdding: .day, value: -1,
                                        to: calendar.startOfDay(for: chips[index].start))!
        if calendar.startOfDay(for: chips[index + 1].end) != expectedEnd { return false }
    }
    return true
}
check("day-29 chips are consistent", isConsistent(day29), true)
check("day-31 chips are consistent", isConsistent(day31), true)

// A CONTIGUOUS monthly cycle is still walked in full — the guard rejects broken
// shapes, not unequal period lengths. These are 31, 30, 31 … days long, which the
// old hardcoded 14-day step could not represent at all.
func monthlyFromFirst(_ probe: Date) -> (start: Date, end: Date)? {
    let comps = calendar.dateComponents([.year, .month], from: probe)
    let start = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1))!
    let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
    return (start, end)
}
let months = MileagePeriodSequence.build(now: date(2026, 7, 15), calendar: calendar, resolve: monthlyFromFirst)
check("six months",     months.count, 6)
check("july",           months[0].rangeLabel(monthDay: monthDay), "Jul 1 – Jul 31")
check("june",           months[1].rangeLabel(monthDay: monthDay), "Jun 1 – Jun 30")
check("february",       months[5].rangeLabel(monthDay: monthDay), "Feb 1 – Feb 28")
check("months are consistent", isConsistent(months), true)

// A WEEKLY org steps seven days.
func weekly(_ probe: Date) -> (start: Date, end: Date)? {
    let days = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: probe)).day ?? 0
    let elapsed = Int(floor(Double(days) / 7.0))
    let start = calendar.date(byAdding: .day, value: 7 * elapsed, to: anchor)!
    return (start, calendar.date(byAdding: .day, value: 6, to: start)!)
}
let weeks = MileagePeriodSequence.build(now: anchor, calendar: calendar, resolve: weekly)
check("weekly chip 0", weeks[0].rangeLabel(monthDay: monthDay), "Jul 20 – Jul 26")
check("weekly chip 1", weeks[1].rangeLabel(monthDay: monthDay), "Jul 13 – Jul 19")

// A resolver that keeps answering with the same period — a misconfigured start
// date — must produce ONE chip, not six identical ones that all select the same
// range.
let stuck = MileagePeriodSequence.build(now: anchor, calendar: calendar) { _ in
    (start: anchor, end: calendar.date(byAdding: .day, value: 13, to: anchor)!)
}
check("stuck resolver yields one", stuck.count, 1)

// ONLY THE NON-DECREASING GUARD CATCHES THIS ONE, which is why both guards exist:
// an answer that starts LATER than the chip already drawn while its end still abuts
// that chip's start — i.e. an inverted period, start after end, the shape a resolver
// with mis-ordered boundaries returns. Contiguity is satisfied and the walk is
// nevertheless going forwards, so the chips would stop describing time in order.
let inverted = MileagePeriodSequence.build(now: anchor, calendar: calendar) { probe in
    if probe >= anchor {
        return (anchor, calendar.date(byAdding: .day, value: 13, to: anchor)!)
    }
    return (calendar.date(byAdding: .day, value: 16, to: anchor)!,
            calendar.date(byAdding: .day, value: -1, to: anchor)!)
}
check("a forwards answer stops the walk", inverted.count, 1)

// No settings at all, and no fallback: no chips rather than invented ones.
check("silent resolver yields none",
      MileagePeriodSequence.build(now: anchor, calendar: calendar) { _ in nil }.count, 0)
check("count is honoured",
      MileagePeriodSequence.build(count: 3, now: anchor, calendar: calendar, resolve: biweekly).count, 3)

// ── The money. Every figure goes through VehicleRates.Split.add — the per-report
//    accumulator that existed in the app with ZERO callers while three screens
//    hand-rolled their own bucket arithmetic and disagreed about the answer.
print("the money")

struct Row { let miles: Double; let vehicle: String? }
func accumulate(_ rows: [Row], personal: Double, company: Double?) -> MileageFigures {
    MileageFigures(split: MileageMath.accumulate(rows,
                                                 miles: { $0.miles },
                                                 vehicleType: { $0.vehicle },
                                                 personalRate: personal,
                                                 companyCarRate: company))
}

// DISCRIMINATING: 150 miles at the personal rate alone would be $75.00. The two
// halves are paid at different rates and the total must reflect that.
let mixed = accumulate([Row(miles: 100, vehicle: "personal"),
                        Row(miles: 50, vehicle: "company")],
                       personal: 0.50, company: 0.10)
check("mixed miles",        mixed.miles, 150)
check("mixed personal",     mixed.personalMiles, 100)
check("mixed company",      mixed.companyMiles, 50)
check("mixed money",        mixed.reimbursement, 55.0)

// vehicle_type is NULL on pre-CAR rows and anything unexpected counts as personal —
// VehicleRates' rule, mirrored rather than re-decided because the money depends on it.
let loose = accumulate([Row(miles: 10, vehicle: nil),
                        Row(miles: 10, vehicle: ""),
                        Row(miles: 10, vehicle: "Company"),
                        Row(miles: 10, vehicle: "company")],
                       personal: 1.00, company: 2.00)
check("nil is personal",       loose.personalMiles, 30)
check("only exact is company", loose.companyMiles, 10)
check("loose money",           loose.reimbursement, 50.0)

// A REAL $0.00: an explicit zero rate is respected, so miles with no money is a
// state the screen can show — and it is now distinguishable from a failed load,
// which has its own state.
let unpaid = accumulate([Row(miles: 28.6, vehicle: "personal")], personal: 0, company: nil)
check("zero rate keeps the miles", unpaid.miles, 28.6)
check("zero rate pays nothing",    unpaid.reimbursement, 0)

// The bucket-totals entry point must agree with the row-by-row one, or the hero and
// the widget would state different money for the same miles.
let fromBuckets = MileageFigures(split: MileageMath.split(personalMiles: 100,
                                                          companyMiles: 50,
                                                          personalRate: 0.50,
                                                          companyCarRate: 0.10))
check("buckets match rows", fromBuckets.reimbursement, mixed.reimbursement)
check("buckets match miles", fromBuckets.miles, mixed.miles)

// A NULL company rate falls back to 0.10, not to zero and not to the personal rate.
let nullCompany = accumulate([Row(miles: 100, vehicle: "company")], personal: 0.67, company: nil)
check("null company rate", nullCompany.reimbursement, 10.0)

check("one trip's money",
      MileageMath.amount(miles: 18, vehicleType: "company", personalRate: 0.67, companyCarRate: 0.10), 1.80)
check("one personal trip's money",
      MileageMath.amount(miles: 18, vehicleType: nil, personalRate: 0.67, companyCarRate: 0.10), 12.06)

// Claim 2: THE SPLIT IS ALWAYS VISIBLE. The old card drew this line only when
// company miles were greater than zero, so a company-only period never stated that
// the PERSONAL half was the zero one.
let companyOnly = accumulate([Row(miles: 70.4, vehicle: "company")], personal: 0.67, company: 0.10)
check("company-only split line", companyOnly.splitLine, "Personal 0.0 mi · Company 70.4 mi")
let personalOnly = accumulate([Row(miles: 132.4, vehicle: "personal")], personal: 0.67, company: 0.10)
check("personal-only split line", personalOnly.splitLine, "Personal 132.4 mi · Company 0.0 mi")
check("empty split line", MileageFigures.zero.splitLine, "Personal 0.0 mi · Company 0.0 mi")
check("miles line", mixed.milesLine, "150.0 miles")
// 24.66, not 24.65: the latter is not exactly representable in binary and lands
// just under the midpoint, so it rounds DOWN — a fact about doubles, not a rule
// this file gets to assert either way.
check("one decimal", MileageFigures.oneDecimal(24.66), "24.7")

// ── The month and year buckets, ON THE STORED-DAY CONVENTION.
//
// `daily_job_reports.date` is "the day the report is about": iOS writes a bare day,
// the column carries it as MIDNIGHT UTC, and the app's one convention is that the
// day is the UTC prefix of that instant (which is how Stats has always read it —
// `StatsDay`). So the REPORT dates below are minted in UTC, the way the decoder
// produces them, and the REFERENCE ("this month") is minted locally, because "this
// month" is a question about the reader's calendar.
//
// These checks used to mint both sides with `Calendar.current` and pass the local
// calendar in, which is precisely the bug they failed to catch: a report stored
// 2026-08-01T00:00:00Z read locally in any western zone is July 31, so every
// 1st-of-month trip fell out of the month tile and the Mileage screen disagreed with
// Statistics about the same row.
print("the month and year buckets")

// A stored day, exactly as the decoder hands it over: midnight UTC. MINTED BY THE
// HARNESS'S OWN UTC CALENDAR, not by `MileageMath.storedDayCalendar` — using the
// production one on both sides of the comparison would make these checks pass even
// with the pin reverted, which is fake evidence (see --prove-can-fail).
let utcCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
}()
func storedDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}

// A calendar fixed at a given offset from UTC, standing in for a device zone.
func zone(_ offsetHours: Int) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: offsetHours * 3600)!
    return c
}

check("same month same year",
      MileageMath.isInSameMonth(storedDay(2026, 7, 3), as: date(2026, 7, 28), referenceCalendar: calendar), true)
check("same month other year",
      MileageMath.isInSameMonth(storedDay(2025, 7, 3), as: date(2026, 7, 28), referenceCalendar: calendar), false)
check("other month",
      MileageMath.isInSameMonth(storedDay(2026, 6, 30), as: date(2026, 7, 1), referenceCalendar: calendar), false)
check("same year",
      MileageMath.isInSameYear(storedDay(2026, 1, 1), as: date(2026, 12, 31), referenceCalendar: calendar), true)
check("other year",
      MileageMath.isInSameYear(storedDay(2025, 12, 31), as: date(2026, 1, 1), referenceCalendar: calendar), false)

// THE 1st-OF-MONTH CASE, in a zone where it used to fail. A trip stored
// 2026-08-01T00:00:00Z is an August trip and a 2026 trip in EVERY device zone —
// including one seven hours behind UTC, where reading the instant locally makes it
// July 31, and one two hours ahead, where the old code happened to be right.
let firstOfAugust = storedDay(2026, 8, 1)
let firstOfJanuary = storedDay(2026, 1, 1)
for offsetHours in [-11, -7, 0, 2, 14] {
    let zoned = zone(offsetHours)
    // "Today" in that zone, mid-August and mid-January — a reference far from any
    // boundary, so only the STORED side can be misread.
    let augustReference = zoned.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12))!
    let januaryReference = zoned.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 12))!
    check("the 1st of August is in August (UTC\(offsetHours))",
          MileageMath.isInSameMonth(firstOfAugust, as: augustReference, referenceCalendar: zoned), true)
    check("the 1st of August is not in July (UTC\(offsetHours))",
          MileageMath.isInSameMonth(firstOfAugust,
                                    as: zoned.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))!,
                                    referenceCalendar: zoned), false)
    check("the 1st of January is in this year (UTC\(offsetHours))",
          MileageMath.isInSameYear(firstOfJanuary, as: januaryReference, referenceCalendar: zoned), true)
    check("the 1st of January is not in the year before (UTC\(offsetHours))",
          MileageMath.isInSameYear(firstOfJanuary,
                                   as: zoned.date(from: DateComponents(year: 2025, month: 12, day: 15, hour: 12))!,
                                   referenceCalendar: zoned), false)
}

// THE OTHER HALF OF THE CONVENTION: "this month" is read in the READER's calendar,
// never in UTC. At 6pm on the last day of July, seven hours behind UTC, it is already
// August in UTC — a screen that took "this month" off the UTC clock would drop every
// July trip out of the month tile for the evening of the 31st, and out of the year
// total on New Year's Eve.
let minus7 = zone(-7)
check("an evening reference is still this month",
      MileageMath.isInSameMonth(storedDay(2026, 7, 31),
                                as: minus7.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 18))!,
                                referenceCalendar: minus7), true)
check("New Year's Eve is still this year",
      MileageMath.isInSameYear(storedDay(2026, 12, 31),
                               as: minus7.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 18))!,
                               referenceCalendar: minus7), true)

// The stored calendar is UTC, fixed-offset, and nothing about it follows the machine
// running this.
check("the stored-day calendar is UTC",
      MileageMath.storedDayCalendar.timeZone.secondsFromGMT(), 0)
check("a stored day reads back as itself",
      MileageMath.storedDayCalendar.component(.day, from: firstOfAugust), 1)
check("…and in the stored month",
      MileageMath.storedDayCalendar.component(.month, from: firstOfAugust), 8)

// ── The vehicle, across storage and screen.
print("the vehicle")
check("company stored",   MileageVehicle.from(storage: "company").rawValue, "company")
check("personal stored",  MileageVehicle.from(storage: "personal").rawValue, "personal")
check("nil stored",       MileageVehicle.from(storage: nil).rawValue, "personal")
check("garbage stored",   MileageVehicle.from(storage: "van").rawValue, "personal")
check("round trip",       MileageVehicle.from(storage: MileageVehicle.company.storageValue).rawValue, "company")
check("choice order",     MileageVehicle.choiceLabels.joined(separator: "/"), "Personal/Company")
check("choice company",   MileageVehicle.from(choiceLabel: "Company")?.rawValue ?? "nil", "company")
check("choice personal",  MileageVehicle.from(choiceLabel: "Personal")?.rawValue ?? "nil", "personal")
check("choice unknown",   MileageVehicle.from(choiceLabel: "company")?.rawValue ?? "nil", "nil")
// PERSONAL IS BADGED TOO: the old read mode drew nothing at all for a personal
// trip, so absence was the only signal. A badge needs a word.
check("personal badge",   MileageVehicle.personal.badgeLabel, "Personal")
check("company badge",    MileageVehicle.company.badgeLabel, "Company")
check("personal read",    MileageVehicle.personal.readLabel, "Personal car")
check("company read",     MileageVehicle.company.readLabel, "Company car")

// ── The edit.
print("the edit")
func validate(_ school: String, _ miles: String) -> MileageEditValidation {
    MileageEditValidation.evaluate(school: school, vehicle: .personal, milesText: miles)
}

if case .valid(let school, let vehicle, let miles) = validate("  Oakmont Prep  ", " 38.2 ") {
    check("valid school trimmed", school, "Oakmont Prep")
    check("valid vehicle", vehicle.rawValue, "personal")
    check("valid miles", miles, 38.2)
} else {
    print("  FAIL  a good form validates"); failed += 1
}
check("zero miles is valid", validate("Oakmont Prep", "0").isValid, true)

check("blank school",      validate("", "12").message ?? "nil", "Please select a school.")
check("whitespace school", validate("   ", "12").message ?? "nil", "Please select a school.")
// ORDER: with both wrong, a blank form is told to pick a school rather than to fix
// a number it has not been given.
check("school before miles", validate("", "not a number").message ?? "nil", "Please select a school.")
check("garbage miles",   validate("Oakmont Prep", "abc").message ?? "nil",
      "Please enter a number for the miles driven.")
check("empty miles",     validate("Oakmont Prep", "").message ?? "nil",
      "Please enter a number for the miles driven.")
check("negative miles",  validate("Oakmont Prep", "-3").message ?? "nil",
      "Please enter a number for the miles driven.")
check("infinite miles",  validate("Oakmont Prep", "inf").message ?? "nil",
      "Please enter a number for the miles driven.")
check("valid has no message", validate("Oakmont Prep", "12.5").message ?? "nil", "nil")

// ── The school list. Three situations the old form drew identically: loading, an
//    org with no schools at all, and a failed load — the last two both showing
//    "Loading schools..." forever beside an unsatisfiable "Please select a school."
print("the school list")
check("loading blocks picking", MileageSchoolsState.loading.allowsPicking, false)
check("empty blocks picking",   MileageSchoolsState.empty.allowsPicking, false)
check("failed blocks picking",  MileageSchoolsState.failed("x").allowsPicking, false)
check("ready allows picking",   MileageSchoolsState.ready.allowsPicking, true)
check("loading says so",        MileageSchoolsState.loading.message ?? "nil", "Loading schools…")
check("empty says so",          MileageSchoolsState.empty.message ?? "nil",
      "No schools on your organization yet.")
check("failed says why",        MileageSchoolsState.failed("no network").message ?? "nil", "no network")
check("ready says nothing",     MileageSchoolsState.ready.message ?? "nil", "nil")
check("empty is not loading",   MileageSchoolsState.empty == MileageSchoolsState.loading, false)

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
    "a past period claims to be this pay period|s/^ +isCurrent\$/        true/"
    "chip 0 not marked as the current period|s/index == 0/index == 99/"
    "the walk back skips a week instead of a day|s/value: -1,/value: -8,/"
    "the stuck-resolver guard removed|s/if previous\.start <= answer\.start \{ break \}//"
    "the contiguity guard removed (gaps and overlaps drawn as chips)|s/calendar\.startOfDay\(for: answer\.end\) == expectedEnd/true/"
    "the split line drops the company half|s/\[personal, company\]/[personal]/"
    "every row paid at the personal rate|s/vehicleType: vehicleType\(row\)/vehicleType: nil/"
    "the company vehicle type stops being recognised|s/VehicleRates\.isCompany\(storage\)/false/"
    "monthly resolves as weekly|s/return \.monthly/return .weekly/"
    "a blank school passes validation|s/!trimmedSchool\.isEmpty/true/"
    "negative miles accepted|s/miles >= 0/miles >= -1000/"
    "the month bucket ignores the year|s/&& stored\.year == now\.year//"
    # A FIXED offset rather than `.current`: a break that reverts the pin to the
    # device zone proves nothing on a machine whose device zone IS UTC, and a proof
    # that depends on the runner's region is the fake-evidence shape this harness
    # exists to refuse. Seven hours off is US Pacific, the zone the defect was found
    # in.
    "the stored day is read seven hours off UTC (a device zone, not the stored day)|s/TimeZone\(secondsFromGMT: 0\) \?\? \.current/TimeZone(secondsFromGMT: -25200) ?? .current/"
    "the reference month is read in UTC instead of the reader's calendar|s/now = referenceCalendar\.dateComponents/now = storedDayCalendar.dateComponents/"
    "the reference year is read in UTC instead of the reader's calendar|s/== referenceCalendar\.component\(\.year, from: reference\)/== storedDayCalendar.component(.year, from: reference)/"
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
