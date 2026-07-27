//  test_timeoff_rules.swift
//  Run via scripts/test_timeoff_rules.sh — which compiles the REAL
//  Iconik Employee/TimeOff/TimeOffRules.swift alongside this harness.
//
//  Every assertion here is annotated with the behaviour it discriminates
//  against, so a reader can tell what would break if the rule regressed. Where a
//  check exists because of a specific defect, the defect is named.
//
//  PROVING A TEST CAN FAIL. A test that passes with and without its fix is fake
//  evidence in another costume — AMB.7 shipped one of those and its audit caught
//  it. Two techniques are used here: explicit NEGATIVE CONTROLS (assert that a
//  deliberately broken input is REJECTED), and discriminating values chosen so
//  the pre-fix behaviour produces a different answer, noted inline.

import Foundation

var failures = 0
var checks = 0

func check(_ passed: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if passed {
        print("  ok    \(what)")
    } else {
        failures += 1
        let d = detail()
        print("  FAIL  \(what)\(d.isEmpty ? "" : " — \(d)")")
    }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) {
    check(a == b, what, "expected \(b), got \(a)")
}

let cal = Calendar.current
func day(_ offset: Int) -> Date {
    cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))!
}

// ---------------------------------------------------------------------------
print("\nTIME OF DAY — a pinned POSIX locale, because a fixed format is not free")

eq(TimeOfDay("09:00")?.minutes, 540, "09:00 parses to 540 minutes")
eq(TimeOfDay("17:30")?.minutes, 1050, "17:30 parses to 1050 minutes")
eq(TimeOfDay(hour: 13, minute: 5).storageString, "13:05", "13:05 round-trips zero-padded")
eq(TimeOfDay("00:00")?.minutes, 0, "midnight parses")
eq(TimeOfDay("23:59")?.minutes, 1439, "23:59 parses")

// NEGATIVE CONTROLS. The old code built a DateFormatter with dateFormat "HH:mm"
// and NO locale in five places. On a device in a 12-hour region that formatter
// can hand back nil, and nil is not an error anywhere in the old code — it
// degrades to "Invalid time range", to a silently skipped edit-mode seed, or to
// 0.0 PTO hours requested. These assert the parser is strict about the storage
// format rather than lenient in a locale-dependent way.
check(TimeOfDay("9:00 AM") == nil, "a 12-hour string is REJECTED, not half-read")
check(TimeOfDay("9:00") == nil, "an unpadded hour is REJECTED (storage is always HH:mm)")
check(TimeOfDay("24:00") == nil, "hour 24 is REJECTED")
check(TimeOfDay("12:60") == nil, "minute 60 is REJECTED")
check(TimeOfDay("") == nil, "empty string is REJECTED")
check(TimeOfDay("not a time") == nil, "garbage is REJECTED")
check(TimeOfDay("09:00:00") == nil, "a seconds component is REJECTED")

// ---------------------------------------------------------------------------
print("\nSPAN — a full day range is INCLUSIVE OF BOTH ENDPOINTS")

// THE RULE. days + 1. This is a payroll number: PTO hours derive from it, so an
// off-by-one here is an off-by-eight-hours on someone's balance.
// Discriminating: a plain subtraction gives 4 for Mon-Fri, this must give 5.
eq(TimeOffSpan(startDay: day(0), endDay: day(4), isPartialDay: false).dayCount, 5,
   "Mon to Fri is 5 days, not 4")
eq(TimeOffSpan(startDay: day(0), endDay: day(0), isPartialDay: false).dayCount, 1,
   "a single full day is 1 day")
eq(TimeOffSpan(startDay: day(3), endDay: day(9), isPartialDay: false).dayCount, 7,
   "a full week is 7 days")

// A partial day is a SINGLE date and the type refuses to represent otherwise —
// the form forces end = start when the type is switched, and encoding that here
// means a caller cannot construct the impossible state.
let partial = TimeOffSpan(startDay: day(2), endDay: day(9), isPartialDay: true,
                          start: TimeOfDay("13:00"), end: TimeOfDay("17:00"))
eq(partial.dayCount, 1, "a partial day collapses to 1 day even if an end date was passed")
eq(partial.endDay, partial.startDay, "a partial day's end date is forced to its start date")
eq(partial.partialHours, 4.0, "13:00-17:00 is 4.0 hours")
eq(partial.partialMinutes, 240, "13:00-17:00 is 240 minutes")

// NEGATIVE CONTROL: a full-day span must NOT report partial hours, or a caller
// could bill a full-day request by an elapsed-time calculation.
let full = TimeOffSpan(startDay: day(0), endDay: day(2), isPartialDay: false,
                       start: TimeOfDay("13:00"), end: TimeOfDay("17:00"))
check(full.partialHours == nil, "a full-day span reports NO partial hours even if times were passed")
check(full.start == nil, "a full-day span discards a start time")

// Unreadable times yield NIL, not 0.0. Zero is a legitimate answer a caller
// cannot tell apart from a failure — the same shape that hid a broken feature in
// this app for a year. PTOService.calculatePTOHours returns 0 here.
let unreadable = TimeOffSpan(startDay: day(1), endDay: day(1), isPartialDay: true,
                             start: nil, end: nil)
check(unreadable.partialHours == nil, "missing times yield nil, NOT 0.0")

// ---------------------------------------------------------------------------
print("\nPARTIAL DAY RANGE — an invalid range is REPAIRED, not rejected")

// The app moves the end to start + 1 hour rather than erroring. That is a
// deliberate kindness on a phone form and a redesign must not "improve" it into
// a validation error, which would look identical in a screenshot.
var range = PartialDayRange(start: TimeOfDay("13:00")!, end: TimeOfDay("11:00")!)
eq(range.end.storageString, "14:00", "an end BEFORE the start is repaired to start + 1 hour")

range = PartialDayRange(start: TimeOfDay("09:00")!, end: TimeOfDay("09:00")!)
eq(range.end.storageString, "10:00", "an end EQUAL to the start is repaired too (<=, not <)")

range = PartialDayRange(start: TimeOfDay("09:00")!, end: TimeOfDay("17:00")!)
eq(range.end.storageString, "17:00", "a valid range is left alone")

// Moving the start past the end repairs on the setter too, not just at init —
// which is where a half-implemented version would break.
range.setStart(TimeOfDay("18:00")!)
eq(range.end.storageString, "19:00", "moving the start past the end repairs the end")

range = PartialDayRange(start: TimeOfDay("09:00")!, end: TimeOfDay("17:00")!)
range.setEnd(TimeOfDay("08:00")!)
eq(range.end.storageString, "10:00", "setting an end before the start repairs it")

print("\n  the 30-minute minimum — the ONLY thing that disables Submit")
check(PartialDayRange(start: TimeOfDay("09:00")!, end: TimeOfDay("09:30")!).meetsMinimum,
      "exactly 30 minutes MEETS the minimum (>=, not >)")

// I asserted the wrong thing here first and the harness caught it, which is the
// reason for running these rather than reasoning about them. I expected a
// 10-minute range to be repaired to 60. It is NOT, and it should not be: the two
// rules are separate and both are the app's. REPAIR fires only on an INVERTED
// range (end <= start), because that is a range the user cannot have meant. A
// 10-minute range is one they plainly did mean — it is simply too short to file,
// and the 30-minute gate is what says so. Silently inflating it to an hour would
// file time off the photographer never asked for.
let shortRange = PartialDayRange(start: TimeOfDay("09:00")!, end: TimeOfDay("09:10")!)
eq(shortRange.minutes, 10, "a 10-minute FORWARD range is left alone — repair is only for inverted ranges")
check(!shortRange.meetsMinimum, "…and it fails the 30-minute minimum instead")
check(!PartialDayRange(start: TimeOfDay("09:00")!, end: TimeOfDay("09:29")!).meetsMinimum,
      "29 minutes fails the minimum")

print("\n  the clamp boundary — a fix round created this case, so it gets a test")

// The fix round changed TimeOfDay's clamp from 24*60 to 24*60-1, because hour 24
// made `Calendar.date(bySettingHour: 24, …)` return nil and silently defeated the
// end-time repair. That fix creates a NEW edge: a start late enough that start+1h
// clamps back onto the start itself.
eq(TimeOfDay(minutes: 24 * 60).storageString, "23:59", "the clamp lands on 23:59, never 24:00")
check(TimeOfDay(TimeOfDay(minutes: 24 * 60).storageString) != nil,
      "the clamped value ROUND-TRIPS through the parser — 24:00 did not")
eq(TimeOfDay(minutes: 24 * 60 + 500).storageString, "23:59", "an overshoot still lands on 23:59")

// 23:59 start: the repair has nowhere to go, so it produces a zero-length range.
// That is NOT silently accepted — the 30-minute gate blocks it, and the duration
// reads 0.0 rather than a negative number, which is what the old clamp produced.
var lateRange = PartialDayRange(start: TimeOfDay("23:59")!, end: TimeOfDay("23:00")!)
eq(lateRange.end.storageString, "23:59", "a 23:59 start clamps the repaired end back onto itself")
eq(lateRange.minutes, 0, "…giving a zero-length range, not a negative one")
check(!lateRange.meetsMinimum, "…which the 30-minute minimum blocks")

// 23:00 start: this is the case that was BROKEN before the clamp fix — the repair
// computed 24:00, the date conversion returned nil, and the range stayed inverted
// so the form rendered a negative duration.
lateRange = PartialDayRange(start: TimeOfDay("23:00")!, end: TimeOfDay("22:00")!)
eq(lateRange.end.storageString, "23:59", "a 23:00 start repairs to 23:59, not to a nil hour 24")
check(lateRange.minutes > 0, "…and the range is no longer inverted")

// 23:00 -> 23:59 is 59 minutes, which CLEARS the 30-minute floor. I asserted the
// opposite here first and the harness caught it — the second time in this file
// that running the rules beat reasoning about them.
let lateSpan = TimeOffSpan(startDay: day(1), endDay: day(1), isPartialDay: true,
                           start: TimeOfDay("23:00"), end: TimeOfDay("23:59"))
eq(lateSpan.partialMinutes, 59, "23:00 to 23:59 is 59 minutes")
check((lateSpan.partialMinutes ?? -1) >= 0, "a late-evening span never reports NEGATIVE minutes")
check(SubmitGate.evaluate(span: lateSpan).isAllowed, "…and 59 minutes is allowed")

// The genuinely blocked one is the 23:59 start, whose repair has nowhere to go.
let zeroSpan = TimeOffSpan(startDay: day(1), endDay: day(1), isPartialDay: true,
                           start: TimeOfDay("23:59"), end: TimeOfDay("23:59"))
eq(SubmitGate.evaluate(span: zeroSpan), .blockedByPartialDayMinimum,
   "a zero-length range at the clamp boundary is BLOCKED, not submitted")

// ---------------------------------------------------------------------------
print("\nFULL DAY RANGE — moving the start past the end DRAGS THE END WITH IT")

var dates = FullDayRange(start: day(5), end: day(9))
dates.setStart(day(12))
eq(dates.end, day(12), "start moved past end drags end to match")
check(dates.end >= dates.start, "end is never before start")

dates = FullDayRange(start: day(5), end: day(9))
dates.setStart(day(6))
eq(dates.end, day(9), "a start move that stays before the end leaves the end alone")

dates = FullDayRange(start: day(5), end: day(9))
dates.setEnd(day(1))
eq(dates.end, day(5), "an end set before the start is clamped to the start")

// NEGATIVE CONTROL: the init must clamp too, or edit mode could seed an
// inverted range straight from the database.
eq(FullDayRange(start: day(10), end: day(2)).end, day(10),
   "an inverted range passed to init is clamped, not stored inverted")

// ---------------------------------------------------------------------------
print("\nPTO HOURS FIELD — auto-filled from the dates, but a typed value WINS")

// The real rule, from the old form:
//   if ptoHoursRequested == 0 || ptoHoursRequested == calculatedHours {
//       ptoHoursRequested = calculatedHours
//   }
var field = PTOHoursField()
field.autoFill(calculated: 8)
eq(field.value, 8, "an untouched field fills from the dates")

field.autoFill(calculated: 16)
eq(field.value, 16, "an untouched field REFILLS when the dates change")

field.userTyped(6, calculated: 16)
eq(field.value, 6, "typing sets the value")
check(field.isUserEdited, "typing a different number takes the field over")

field.autoFill(calculated: 24)
eq(field.value, 6, "a taken-over field is NOT overwritten when the dates change")

// Typing the auto-filled number back, or clearing to zero, hands the field back
// to the dates — which is exactly what `== 0 || == calculatedHours` did.
field.userTyped(0, calculated: 24)
check(!field.isUserEdited, "clearing to zero hands the field back to the dates")
field.autoFill(calculated: 32)
eq(field.value, 32, "and it refills again afterwards")

field = PTOHoursField()
field.autoFill(calculated: 8)
field.userTyped(8, calculated: 8)
check(!field.isUserEdited, "typing exactly the calculated number is NOT a takeover")

// ---------------------------------------------------------------------------
print("\nPTO MATH — a full day is 8 hours, and the remainder keeps its sign")

eq(PTOMath.calculatedHours(for: TimeOffSpan(startDay: day(0), endDay: day(4), isPartialDay: false)),
   40.0, "5 full days is 40 PTO hours")
eq(PTOMath.calculatedHours(for: TimeOffSpan(startDay: day(0), endDay: day(0), isPartialDay: false)),
   8.0, "1 full day is 8 PTO hours")
eq(PTOMath.calculatedHours(for: partial), 4.0, "a 4-hour partial day is 4 PTO hours")
check(PTOMath.calculatedHours(for: unreadable) == nil,
      "unreadable partial times yield nil hours, NOT zero")

// The sign is the point. The old screen clamped the projection at zero in one
// path (PTOService.calculateProjectedBalance ends `max(0, …)`) and left it
// unclamped in another, so the same shortfall read as two different numbers.
eq(PTOMath.remaining(available: 16, requested: 40), -24.0,
   "a shortfall is NEGATIVE, not clamped to zero")
eq(PTOMath.remaining(available: 40, requested: 16), 24.0, "a surplus is positive")
eq(PTOMath.remaining(available: 8, requested: 8), 0.0, "an exact match is zero")

// ---------------------------------------------------------------------------
print("\nPTO STANDING — three outcomes, and it does NOT decide whether to block")

eq(PTOStanding.evaluate(availableNow: 40, projectedByRequestDate: 46, requested: 8),
   .sufficient, "enough banked today is sufficient")
eq(PTOStanding.evaluate(availableNow: 40, projectedByRequestDate: 46, requested: 40),
   .sufficient, "exactly the available amount is sufficient (<=, not <)")
eq(PTOStanding.evaluate(availableNow: 16, projectedByRequestDate: 46, requested: 24),
   .coveredByFutureAccrual, "short today but covered by the request date")
eq(PTOStanding.evaluate(availableNow: 16, projectedByRequestDate: 24, requested: 24),
   .coveredByFutureAccrual, "exactly covered by accrual counts as covered")
eq(PTOStanding.evaluate(availableNow: 16, projectedByRequestDate: 24, requested: 64),
   .short(shortBy: 40), "short after accrual reports how short, as a POSITIVE number")

// NEGATIVE CONTROL: the shortfall must be measured against the PROJECTED
// balance, not the available-now one, or the message would overstate the gap.
// Discriminating: against availableNow the answer would be 48, not 40.
if case .short(let by) = PTOStanding.evaluate(availableNow: 16, projectedByRequestDate: 24, requested: 64) {
    eq(by, 40.0, "shortBy is measured against the PROJECTED balance (48 would mean against available-now)")
} else {
    check(false, "shortBy is measured against the projected balance")
}

// ---------------------------------------------------------------------------
print("\nSUBMIT GATE — ONLY the partial-day minimum blocks submission")

// This is surprising and it is preserved deliberately. A full-day request is
// never blocked — not by a missing reason, not by a PTO shortfall. Tightening it
// would change who can file what, which belongs to TOF.1 and not to a restyle.
check(SubmitGate.evaluate(span: TimeOffSpan(startDay: day(0), endDay: day(4), isPartialDay: false)).isAllowed,
      "a full-day request is ALLOWED")
check(SubmitGate.evaluate(span: TimeOffSpan(startDay: day(0), endDay: day(0), isPartialDay: false)).isAllowed,
      "a same-day full-day request is ALLOWED")
check(SubmitGate.evaluate(span: partial).isAllowed, "a 4-hour partial day is ALLOWED")

let tooShort = TimeOffSpan(startDay: day(1), endDay: day(1), isPartialDay: true,
                           start: TimeOfDay("09:00"), end: TimeOfDay("09:15"))
eq(SubmitGate.evaluate(span: tooShort), .blockedByPartialDayMinimum,
   "a 15-minute partial day is BLOCKED")

let exactly30 = TimeOffSpan(startDay: day(1), endDay: day(1), isPartialDay: true,
                            start: TimeOfDay("09:00"), end: TimeOfDay("09:30"))
check(SubmitGate.evaluate(span: exactly30).isAllowed, "exactly 30 minutes is ALLOWED")

eq(SubmitGate.evaluate(span: unreadable), .blockedByPartialDayMinimum,
   "a partial day with unreadable times is BLOCKED rather than silently allowed")

// ---------------------------------------------------------------------------
print("\nQUEUE ORDER — the manager queue is FIFO, the employee list is not")

struct Row: Equatable { let id: String; let created: Date; let actioned: Date }
let rows = [
    Row(id: "newest", created: day(-1), actioned: day(-1)),
    Row(id: "oldest", created: day(-9), actioned: day(-2)),
    Row(id: "middle", created: day(-5), actioned: day(-8)),
]

eq(TimeOffOrder.employeeList(rows, createdAt: { $0.created }).map(\.id),
   ["newest", "middle", "oldest"],
   "your own list is NEWEST first")

eq(TimeOffOrder.managerQueue(rows, createdAt: { $0.created }).map(\.id),
   ["oldest", "middle", "newest"],
   "the manager queue is OLDEST first — a manager works a queue")

// History sorts by when it was ACTIONED, not when it was filed. Discriminating:
// by created_at this would be newest/middle/oldest, so the orders differ.
eq(TimeOffOrder.history(rows, actionedAt: { $0.actioned }).map(\.id),
   ["newest", "oldest", "middle"],
   "history sorts by when it was ACTIONED, not when it was filed")

// NEGATIVE CONTROL: the two list orders must actually differ, or the FIFO claim
// the design puts on screen would be decorative.
check(TimeOffOrder.employeeList(rows, createdAt: { $0.created }).map(\.id)
      != TimeOffOrder.managerQueue(rows, createdAt: { $0.created }).map(\.id),
      "the employee order and the manager order are genuinely opposite")

eq(TimeOffOrder.waitingDays(since: day(-6), now: day(0)), 6, "waiting days counts whole days")
eq(TimeOffOrder.waitingDays(since: day(0), now: day(0)), 0, "filed today is 0 days waiting")
eq(TimeOffOrder.waitingDays(since: day(3), now: day(0)), 0, "a future date floors at 0, never negative")

// ---------------------------------------------------------------------------
print("\nATTRIBUTION — conditional on BOTH the name and the date")

// Sample row t5 in the lab is an approved request whose approver name never came
// back. A card that drops the `&&` renders a bare "Approved by" with nothing
// after it, which is why this returns nil rather than a half-built string.
check(TimeOffAttribution(name: "Alex Fontaine", date: day(-3), status: .approved) != nil,
      "both present builds an attribution")
check(TimeOffAttribution(name: nil, date: day(-3), status: .approved) == nil,
      "a missing NAME yields no attribution")
check(TimeOffAttribution(name: "Alex Fontaine", date: nil, status: .approved) == nil,
      "a missing DATE yields no attribution")
check(TimeOffAttribution(name: "", date: day(-3), status: .approved) == nil,
      "an EMPTY-STRING name yields no attribution — empty string is not nil")
check(TimeOffAttribution(name: "   ", date: day(-3), status: .approved) == nil,
      "a whitespace-only name yields no attribution")

eq(TimeOffAttribution(name: "Alex Fontaine", date: day(-3), status: .approved)?.verb,
   "Approved by Alex Fontaine", "approved reads as a sentence")
eq(TimeOffAttribution(name: "Alex Fontaine", date: day(-3), status: .denied)?.verb,
   "Denied by Alex Fontaine", "denied reads as a sentence")
eq(TimeOffAttribution(name: "Alex Fontaine", date: day(-3), status: .underReview)?.verb,
   "In review by Alex Fontaine", "under review reads as a sentence")

// ---------------------------------------------------------------------------
print("\nSTATUS — the raw values the SHARED database actually stores")

eq(TimeOffRuleStatus.parse("underReview"), .underReview,
   "the camelCase raw value iOS writes is recognised")
eq(TimeOffRuleStatus.underReview.label, "In Review",
   "underReview reads as 'In Review', never rawValue.capitalized")

// NEGATIVE CONTROL, and this one is a live cross-client defect. The shipped
// detail screen renders `status.rawValue.capitalized`, which produces the
// literal "Underreview" on screen.
check(TimeOffRuleStatus.underReview.rawValue.capitalized != TimeOffRuleStatus.underReview.label,
      "the shipped 'Underreview' spelling is NOT what this returns")

// An unknown status must not silently become .pending. The web app writes
// 'partially_approved' (its queries.js), which the shipped iOS code maps to
// .pending via `?? .pending` — so a request someone already decided renders as
// awaiting a decision, with live Edit and Cancel buttons on it.
check(TimeOffRuleStatus.parse("partially_approved") == nil,
      "the web app's 'partially_approved' is NOT silently read as pending")
check(TimeOffRuleStatus.parse("under_review") == nil,
      "the web app's snake_case 'under_review' is NOT silently read as pending")
check(TimeOffRuleStatus.parse("") == nil, "an empty status is not pending")
check(TimeOffRuleStatus.parse("Approved") == nil,
      "status matching is exact — the stored raw values are lowercase-first")

eq(TimeOffRuleStatus.pending.isEditable, true, "pending is editable")
eq(TimeOffRuleStatus.underReview.isEditable, true, "under review is editable")
eq(TimeOffRuleStatus.approved.isEditable, false, "approved is NOT editable")
eq(TimeOffRuleStatus.denied.isEditable, false, "denied is NOT editable")
eq(TimeOffRuleStatus.cancelled.isEditable, false, "cancelled is NOT editable")

// ---------------------------------------------------------------------------
print("\nREASON — the two clients' vocabularies do not intersect AT ALL")

// The web writes "Vacation", "Sick Leave", "Personal Day", "Family Emergency",
// "Medical Appointment", "Other". iOS writes "vacation", "sick", "personal",
// "emergency", "bereavement", "other". Not one string in common — so with the
// shipped `?? .other`, EVERY web-created request renders as "Other" with a grey
// ellipsis, and the approved design leans on the reason icon as the fastest read
// on the card.

print("  what iOS writes")
eq(TimeOffReasonVocabulary.parse("vacation"), .vacation, "iOS 'vacation'")
eq(TimeOffReasonVocabulary.parse("sick"), .sick, "iOS 'sick'")
eq(TimeOffReasonVocabulary.parse("personal"), .personal, "iOS 'personal'")
eq(TimeOffReasonVocabulary.parse("emergency"), .emergency, "iOS 'emergency'")
eq(TimeOffReasonVocabulary.parse("bereavement"), .bereavement, "iOS 'bereavement'")
eq(TimeOffReasonVocabulary.parse("other"), .other, "iOS 'other'")

print("  what the WEB writes — every one of these rendered as 'Other' before")
eq(TimeOffReasonVocabulary.parse("Vacation"), .vacation, "web 'Vacation'")
eq(TimeOffReasonVocabulary.parse("Sick Leave"), .sick, "web 'Sick Leave'")
eq(TimeOffReasonVocabulary.parse("Personal Day"), .personal, "web 'Personal Day'")
eq(TimeOffReasonVocabulary.parse("Family Emergency"), .emergency, "web 'Family Emergency'")
eq(TimeOffReasonVocabulary.parse("Medical Appointment"), .medical, "web 'Medical Appointment'")
eq(TimeOffReasonVocabulary.parse("Other"), .other, "web 'Other'")

print("  tolerance, and its limits")
eq(TimeOffReasonVocabulary.parse("  Sick Leave  "), .sick, "surrounding whitespace is tolerated")
eq(TimeOffReasonVocabulary.parse("SICK LEAVE"), .sick, "case is tolerated")

// NEGATIVE CONTROL: an unrecognised string must NOT collapse to .other, or
// "someone wrote something new" becomes indistinguishable from "the user picked
// Other" — the same class as reporting a failed fetch as an empty list.
check(TimeOffReasonVocabulary.parse("Jury Duty") == nil,
      "an unrecognised reason yields nil, NOT a silent .other")
check(TimeOffReasonVocabulary.parse("") == nil, "an empty reason yields nil")

// The two vocabularies really are disjoint — asserted rather than asserted-about,
// so this check fails the day someone aligns them and makes the mapping moot.
let iosRaw: Set<String> = ["vacation", "sick", "personal", "emergency", "bereavement", "other"]
let webRaw: Set<String> = ["Vacation", "Sick Leave", "Personal Day",
                           "Family Emergency", "Medical Appointment", "Other"]
check(iosRaw.intersection(webRaw).isEmpty,
      "the iOS and web reason vocabularies share ZERO strings")
check(webRaw.allSatisfy { TimeOffReasonVocabulary.parse($0) != nil },
      "every string the web app can write is now recognised")
check(iosRaw.allSatisfy { TimeOffReasonVocabulary.parse($0) != nil },
      "every string iOS can write is still recognised")

// ---------------------------------------------------------------------------
print("\nPTO TRACKING — does the stored figure mean anything yet")

// The operator states PTO has never functioned. The code agrees: nothing accrues,
// `used` is never persisted, and the web's PTO writes are dead code. So the
// screens must not assert a number the system cannot support.
eq(PTOTracking.evaluate(enabled: false, balance: 0, accrued: 0, used: 0, banking: 0),
   .notConfigured, "PTO switched off is notConfigured")
eq(PTOTracking.evaluate(enabled: false, balance: 40, accrued: 40, used: 8, banking: 0),
   .notConfigured, "…even with figures on file — the org has turned it off")
eq(PTOTracking.evaluate(enabled: true, balance: 0, accrued: 0, used: 0, banking: 0),
   .noActivity, "enabled but nothing has ever accrued or been used")
eq(PTOTracking.evaluate(enabled: true, balance: 40, accrued: 0, used: 0, banking: 0),
   .tracked, "a real balance is tracked")
eq(PTOTracking.evaluate(enabled: true, balance: 0, accrued: 40, used: 40, banking: 0),
   .tracked, "fully spent but with history is tracked — the zero is REAL")
eq(PTOTracking.evaluate(enabled: true, balance: 0, accrued: 0, used: 0, banking: 12),
   .tracked, "banked hours count as activity")

// THE CASE THIS TYPE EXISTS FOR, and the one a naive test would get backwards.
// Reservations ARE written on create, so a person can have pending hours while
// nothing has ever accrued. That is the BROKEN state. Treating pending as
// evidence of a working system would make the shortfall warning fire hardest for
// exactly the people it is most wrong about.
eq(PTOTracking.evaluate(enabled: true, balance: 0, accrued: 0, used: 0, banking: 0),
   .noActivity, "pending hours are NOT part of the test — see the doc comment")
check(!PTOTracking.evaluate(enabled: true, balance: 0, accrued: 0, used: 0, banking: 0).showsFigures,
      "…so no figure is shown for the never-accrued case")
check(PTOTracking.evaluate(enabled: true, balance: 40, accrued: 40, used: 0, banking: 0).showsFigures,
      "…and a real one is")

// SELF-HEALING: the moment TOF.1 makes accrual work, this flips with no code
// change. Asserted so nobody has to remember.
check(PTOTracking.evaluate(enabled: true, balance: 0.5, accrued: 0, used: 0, banking: 0).showsFigures,
      "half an hour of real balance is enough to start showing figures again")

// ---------------------------------------------------------------------------
print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("FAILED")
    exit(1)
}
print("PASSED")
