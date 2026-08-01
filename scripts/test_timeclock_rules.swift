//  test_timeclock_rules.swift
//  Copied in as main.swift by scripts/test_timeclock_rules.sh and compiled
//  against the REAL `Iconik Employee/TimeClock/TimeClockRules.swift`.
//
//  These are payroll rules. Every case below is a rule the app enforces on a
//  write that becomes somebody's paycheque, and several of them are cases the
//  shipped forms got wrong — the 16h/24h ceiling split has its own section.

import Foundation

var failures = 0
var checks = 0

func check(_ condition: Bool, _ what: String) {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ \(what)")
    }
}

func equal<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
    checks += 1
    if actual != expected {
        failures += 1
        print("  ✗ \(what)\n      expected: \(expected)\n      actual:   \(actual)")
    }
}

func section(_ title: String) { print("\n\(title)") }

// A fixed "now" so nothing here depends on when it runs.
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(secondsFromGMT: 0)!
let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12))!

func at(_ hoursFromNow: Double) -> Date { now.addingTimeInterval(hoursFromNow * 3600) }

// MARK: - The ceiling split, which is the bug this file was written for

section("A recorded shift caps at 16 hours; a live clock-out caps at 24")

equal(TimeClockRules.refusalForRecordedShift(start: at(-8), end: at(-1), now: now),
      nil, "an ordinary 7-hour shift is accepted")

equal(TimeClockRules.refusalForRecordedShift(start: at(-16), end: at(-0.5), now: now),
      nil, "15h30m stays under the ceiling")

equal(TimeClockRules.refusalForRecordedShift(start: at(-17), end: at(-0.5), now: now),
      .tooLong(limit: 16 * 3600), "16h30m does not")

equal(TimeClockRules.refusalForRecordedShift(start: at(-17), end: now, now: now),
      .tooLong(limit: 16 * 3600),
      "17 hours recorded after the fact is refused at 16")

equal(TimeClockRules.refusalForRecordedShift(start: at(-16), end: now, now: now),
      nil, "exactly 16 hours is accepted — the rule is `> 16h`, not `>= 16h`")

// THE REGRESSION GUARD. This is the exact case `EditTimeEntryView` used to
// accept: 17 hours passed its 24-hour client check, enabled Save, and threw on
// the write because `updateTimeEntry` validates at 16.
check(TimeClockRules.refusalForRecordedShift(start: at(-17), end: now, now: now) != nil,
      "REGRESSION: a 17-hour EDIT must be refused by the form, not by the server")

equal(TimeClockRules.refusalForLiveClockOut(clockIn: at(-17), clockOut: now, now: now),
      nil, "17 hours IS accepted when closing a live shift — a different act")

equal(TimeClockRules.refusalForLiveClockOut(clockIn: at(-25), clockOut: now, now: now),
      .tooLong(limit: 24 * 3600), "past 24 hours a live clock-out is refused")

equal(TimeClockRules.refusalForLiveClockOut(clockIn: at(-24), clockOut: now, now: now),
      nil, "exactly 24 hours is accepted")

// MARK: - Order of refusals

section("A refusal reports the reason the WRITE will report")

// `validateManualEntry` checks the future first, so an entry that is both too
// long and in the future says "future". A form that said "too long" would send
// the user to fix the wrong field.
equal(TimeClockRules.refusalForRecordedShift(start: at(-20), end: at(2), now: now),
      .inTheFuture,
      "both future and over-long reports the future, matching the service's order")

equal(TimeClockRules.refusalForRecordedShift(start: now, end: at(-1), now: now),
      .endsBeforeItStarts, "an end before its start is refused")

equal(TimeClockRules.refusalForRecordedShift(start: now, end: now, now: now),
      .endsBeforeItStarts, "a zero-length entry is refused as ordering, not as length")

equal(TimeClockRules.refusalForRecordedShift(start: at(-1.0 / 120), end: now, now: now),
      .tooShort, "30 seconds is under the one-minute floor")

equal(TimeClockRules.refusalForRecordedShift(start: at(-1.0 / 60), end: now, now: now),
      nil, "exactly one minute is accepted")

equal(TimeClockRules.refusalForLiveClockOut(clockIn: at(-2), clockOut: at(1), now: now),
      .inTheFuture, "a live clock-out cannot be stamped in the future")

// MARK: - Moving a running shift's start

section("A running shift's start moves back at most 48 hours")

equal(TimeClockRules.refusalForActiveClockIn(newStart: at(-3), now: now, calendar: cal),
      nil, "three hours back is fine")

equal(TimeClockRules.refusalForActiveClockIn(newStart: at(-49), now: now, calendar: cal),
      .clockInTooFarBack(hours: 48), "49 hours back is refused")

equal(TimeClockRules.refusalForActiveClockIn(newStart: at(-48), now: now, calendar: cal),
      nil, "exactly 48 hours back is accepted — the rule is `<`, not `<=`")

equal(TimeClockRules.refusalForActiveClockIn(newStart: at(0.5), now: now, calendar: cal),
      .inTheFuture, "a start in the future is refused")

// MARK: - Notes

section("Notes cap at 500, counted after trimming")

equal(TimeClockRules.refusalForNotes(nil), nil, "no notes is fine")
equal(TimeClockRules.refusalForNotes(""), nil, "empty notes is fine")
equal(TimeClockRules.refusalForNotes(String(repeating: "a", count: 500)), nil,
      "exactly 500 characters is accepted")
equal(TimeClockRules.refusalForNotes(String(repeating: "a", count: 501)),
      .notesTooLong(limit: 500), "501 characters is refused")

// The server trims before counting and the shipped counters did not, so 500
// characters wrapped in whitespace was refused by a form that had just told the
// user they were at 502/500.
equal(TimeClockRules.refusalForNotes("  " + String(repeating: "a", count: 500) + "  "),
      nil, "500 characters padded with whitespace is accepted — the count trims first")

// MARK: - The edit window

section("A completed entry is editable for 30 days after it was CREATED")

let createdToday = now
let created29 = cal.date(byAdding: .day, value: -29, to: now)!
let created31 = cal.date(byAdding: .day, value: -31, to: now)!

check(TimeClockRules.isEditable(createdAt: createdToday, isRunning: false, now: now, calendar: cal),
      "an entry created today is editable")
check(TimeClockRules.isEditable(createdAt: created29, isRunning: false, now: now, calendar: cal),
      "29 days old is editable")
check(!TimeClockRules.isEditable(createdAt: created31, isRunning: false, now: now, calendar: cal),
      "31 days old is not editable")

// The window runs from CREATION, so a manual entry typed today for a shift last
// spring is editable. This is the fact the new copy on the row states.
check(TimeClockRules.isEditable(createdAt: createdToday, isRunning: false, now: now, calendar: cal),
      "a manual entry created today for an old shift is editable")

check(TimeClockRules.isEditable(createdAt: created31, isRunning: true, now: now, calendar: cal),
      "a RUNNING entry is always editable, however old")

equal(TimeClockRules.editWindowDaysRemaining(createdAt: created29, isRunning: false, now: now, calendar: cal),
      1, "29 days old leaves 1 day")
equal(TimeClockRules.editWindowDaysRemaining(createdAt: createdToday, isRunning: false, now: now, calendar: cal),
      30, "created today leaves the full 30")
equal(TimeClockRules.editWindowDaysRemaining(createdAt: created31, isRunning: false, now: now, calendar: cal),
      nil, "a closed window has no days remaining")
equal(TimeClockRules.editWindowDaysRemaining(createdAt: created31, isRunning: true, now: now, calendar: cal),
      nil, "a running entry has no window to count")

// MARK: - The long shift

section("Past 24 hours the app offers a custom clock-out time")

check(!TimeClockRules.isLongShift(clockIn: at(-23), now: now), "23 hours is not a long shift")
check(TimeClockRules.isLongShift(clockIn: at(-25), now: now), "25 hours is a long shift")
check(!TimeClockRules.isLongShift(clockIn: at(-24), now: now),
      "exactly 24 hours is not yet long — the rule is `>`")

// MARK: - Pay periods

section("Pay periods are the ORGANISATION's, resolved once for the whole app")

// The clock no longer defines a pay period. `PayPeriodSequence` does, walking
// back through whatever `PayPeriodService` answers — so a weekly or monthly org
// gets its real boundaries instead of a hardcoded fortnight. Those rules have
// their own coverage in scripts/test_mileage_rules.sh, which compiles the SAME
// file; what belongs here is that the clock asks rather than guesses.

equal(TimeClockRange.payPeriod.fixedPeriod(now: now, calendar: cal), nil,
      "the clock cannot answer for a pay period on its own — the caller supplies it")

// A resolver standing in for PayPeriodService: bi-weekly from a Monday.
let orgAnchor = cal.date(from: DateComponents(year: 2024, month: 12, day: 29))!
func orgPeriod(containing date: Date) -> (start: Date, end: Date)? {
    let days = cal.dateComponents([.day], from: orgAnchor, to: date).day ?? 0
    let elapsed = days >= 0 ? days / 14 : ((days - 13) / 14)
    let start = cal.date(byAdding: .day, value: elapsed * 14, to: orgAnchor)!
    let end = cal.date(byAdding: .day, value: 13, to: start)!
    return (start, end)
}

let walked = PayPeriodSequence.build(now: now, calendar: cal, resolve: orgPeriod)
equal(walked.count, PayPeriodSequence.chipCount, "six periods to walk back through")
check(walked[0].isCurrent, "the first is the current one")
check(walked[0].contains(now), "and it contains today")
check(!walked[1].isCurrent, "the second is not")
check(walked[1].end < walked[0].start, "and it ends before the current one starts")

// THE POINT OF THE WHOLE CHANGE: the org's grid and the literal the clock used
// to carry agree TODAY, which is why nobody noticed there were two of them.
let oldAnchor = cal.date(from: DateComponents(year: 2024, month: 2, day: 25))!
let daysApart = cal.dateComponents([.day], from: oldAnchor, to: orgAnchor).day ?? -1
check(daysApart % 14 == 0,
      "the clock's old 2024-02-25 literal sits on the org's own grid — by luck, not by design (\(daysApart) days)")

section("The three ranges")

equal(TimeClockRange.allCases.map(\.rawValue), ["Today", "This Week", "Pay Period"],
      "the ranges keep their shipped order and labels")

let todayRange = TimeClockRange.today.fixedPeriod(now: now, calendar: cal)
equal(todayRange?.start, now, "Today starts at now — the caller formats it to a day key")
equal(todayRange?.end, now, "Today ends at now")
check(TimeClockRange.week.fixedPeriod(now: now, calendar: cal) != nil,
      "This Week is a calendar fact, so this file can answer it")

// MARK: - Formatting

section("Durations read the way the shipped screens read them")

equal(TimeClockFormat.hoursAndMinutes(7 * 3600 + 18 * 60), "7h 18m", "hours and minutes")
equal(TimeClockFormat.hoursAndMinutes(8 * 3600), "8h", "whole hours drop the minutes")
equal(TimeClockFormat.hoursAndMinutes(0), "0h", "zero reads as 0h")
equal(TimeClockFormat.hoursAndMinutes(-500), "0h", "a negative interval never renders as -1h")
equal(TimeClockFormat.hoursAndMinutes(59), "0h", "under a minute reads as 0h")

equal(TimeClockFormat.elapsed(7 * 3600 + 18 * 60 + 42), "07:18:42", "the running clock")
equal(TimeClockFormat.elapsed(0), "00:00:00", "a clock that just started")
equal(TimeClockFormat.elapsed(-5), "00:00:00", "a negative elapsed never renders as -00:00:05")
equal(TimeClockFormat.elapsed(100 * 3600), "100:00:00", "past 99 hours the hours field grows")

// MARK: - Result

print("")
if failures == 0 {
    print("✅ \(checks) checks passed")
} else {
    print("❌ \(failures) of \(checks) checks FAILED")
    exit(1)
}
