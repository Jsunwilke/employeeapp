//  test_report_rules.swift
//  Real tests of the real rule files the app compiles.
//
//  Run:  scripts/test_report_rules.sh
//
//  Compiles Reports/ReportSchoolLink.swift and Reports/ReportRules.swift — the
//  same sources the app builds — and executes them. It does NOT reimplement the
//  rules in another language and test that, which is a mistake already made once
//  in this arc and caught by the operator.
//
//  Every behaviour here is one the approved mockup demonstrates and the
//  behaviour contract in AMB_BATCH2_PARITY.md requires of the converted screen.
//
//  There is no XCTest target in this project — the Tests folders are wired to
//  nothing and there is no test scheme — so this runs standalone.

import Foundation

var failures = 0, checks = 0

func check(_ passed: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if passed {
        print("  ok    \(what)")
    } else {
        failures += 1
        print("  FAIL  \(what)  \(detail())")
    }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) {
    check(a == b, what, "expected \(b), got \(a)")
}

// ───────────────────────────────────────────── school ownership

print("\nSCHOOL OWNERSHIP — a source replaces its own school, never appends")
do {
    var link = ReportSchoolLink(stops: ["riverside"], sessionSchool: "riverside")
    link.set("lincoln", for: .session)
    eq(link.stops, ["lincoln"], "session change replaces")

    link.addStop("oakmont")
    link.set("pine", for: .session)
    eq(link.stops, ["oakmont", "pine"], "hand-added school survives")

    link.set("pine", for: .note)
    link.set(nil, for: .session)
    eq(link.stops, ["oakmont", "pine"], "shared school kept while the note holds it")
    link.set(nil, for: .note)
    eq(link.stops, ["oakmont"], "released when both let go")
}

// ROUTE ORDER IS THE DRIVE. `set` was a remove-then-append, so pointing a
// source at the school it ALREADY held moved that stop to the end — re-tapping
// the selected session, or switching between two sessions at the same school on
// one day, silently reordered the route and filed a different total mileage.
print("\nSCHOOL OWNERSHIP — re-pointing a source at its own school changes nothing")
do {
    var link = ReportSchoolLink(stops: ["lincoln", "riverside"], sessionSchool: "lincoln")
    link.set("lincoln", for: .session)
    eq(link.stops, ["lincoln", "riverside"], "route order is preserved")
    eq(link.sessionSchool, "lincoln", "and the source still holds it")

    // The same school arriving from the OTHER source must still register, so
    // it survives until both let go.
    link.set("lincoln", for: .note)
    eq(link.stops, ["lincoln", "riverside"], "no duplicate when the note agrees")
    link.set(nil, for: .session)
    eq(link.stops, ["lincoln", "riverside"], "and the note still holds it")
    link.set(nil, for: .note)
    eq(link.stops, ["riverside"], "released when both let go")
}

// A SOURCE MUST NOT REMOVE A SCHOOL IT DID NOT PUT THERE. Found by the AMB.7
// audit: `set` claimed a school that was already in the list, so clearing that
// source took the photographer's own stop away with it.
print("\nSCHOOL OWNERSHIP — a hand-added school is nobody's to remove")
do {
    var link = ReportSchoolLink()
    link.addStop("lincoln")
    link.set("lincoln", for: .session)          // the session happens to agree
    eq(link.stops, ["lincoln"], "no duplicate when a source agrees with a hand-add")
    check(link.handAdded.contains("lincoln"), "and the hand-add is still recorded as the owner")
    link.set(nil, for: .session)
    eq(link.stops, ["lincoln"], "going off-schedule does NOT take the hand-added stop")

    link.set("riverside", for: .session)
    eq(link.stops, ["lincoln", "riverside"], "the session adds its own alongside")
    link.set(nil, for: .session)
    eq(link.stops, ["lincoln"], "and removes only its own")

    link.removeStop("lincoln")
    eq(link.stops, [], "the photographer can still remove their own")
    check(!link.handAdded.contains("lincoln"), "and removing it releases the hand-add")
    link.set("lincoln", for: .note)
    link.set(nil, for: .note)
    eq(link.stops, [], "and after that it is the note's to remove again")
}

// ───────────────────────────────────────────── mileage

print("\nMILEAGE — a typed value wins and is never overwritten")
do {
    var m = ReportMileage(calculated: 18.2)
    eq(m.value, 18.2, "starts at the calculated figure")
    check(!m.isOverridden, "not overridden yet")
    eq(m.displayText, "18.2", "shows the calculated figure")

    m.type("42")
    eq(m.value, 42, "typed value is used")
    check(m.isOverridden, "reports itself overridden")

    // THE RULE. In the live app this is where the typed number is destroyed.
    m.recalculate(to: 71.4)
    eq(m.value, 42, "recalculation does NOT clobber a typed value")
    eq(m.calculated, 71.4, "the route figure still updated underneath")

    m.useCalculated()
    eq(m.value, 71.4, "handing it back restores the route figure")
    check(!m.isOverridden, "no longer overridden")
}

print("\nMILEAGE — partial and junk input do not destroy anything")
do {
    var m = ReportMileage(calculated: 18.2)
    m.type("")
    check(!m.isOverridden, "empty text is not an override")
    eq(m.value, 18.2, "falls back to the route")
    // Swift's Double("12.") DOES parse, to 12.0 — I assumed otherwise and the
    // test caught me, which is the point of running it rather than reasoning
    // about it. Mid-typing toward "12.5" the value reading 12.0 is correct.
    m.type("12.")
    eq(m.displayText, "12.", "mid-typing text is shown verbatim, not reformatted")
    eq(m.value, 12.0, "a partially typed number parses as far as it goes")

    // Genuinely unparseable input (a decimalPad cannot produce this, a paste can)
    // must NOT silently become a number, and must not be treated as no override
    // either — the photographer's text is still theirs.
    m.type("abc")
    eq(m.value, 18.2, "junk falls back to the route figure rather than inventing one")
    check(m.isOverridden, "still counts as overridden, so nothing silently recalculates over it")
    eq(m.displayText, "abc", "and their text is left alone")
}

// ───────────────────────────────────────────── vehicle

print("\nVEHICLE — no default, and the first tap never commits")
do {
    var v = VehicleSelection()
    check(v.needsChoice, "nothing is pre-selected")
    check(v.confirmed == nil, "no vehicle to begin with")

    v.tap(.personal)
    check(v.confirmed == nil, "FIRST TAP DOES NOT COMMIT")
    check(v.isAwaitingConfirmation, "confirmation is armed")
    check(v.pending == .personal, "and it remembers WHICH one was tapped")

    v.confirm()
    check(v.confirmed == .personal, "second tap commits")
    check(!v.isAwaitingConfirmation, "confirmation cleared")
    check(!v.needsChoice, "the report has its vehicle")
}

print("\nVEHICLE — both options confirm, and cancelling changes nothing")
do {
    var v = VehicleSelection()
    v.tap(.company)
    v.cancel()
    check(v.confirmed == nil, "cancel leaves it unchosen")
    check(!v.isAwaitingConfirmation, "and disarms")

    v.tap(.company); v.confirm()
    eq(v.confirmed, .company, "company confirms the same way personal does")

    // Changing an already-confirmed vehicle is still two taps.
    v.tap(.personal)
    eq(v.confirmed, .company, "still company until confirmed")
    v.confirm()
    eq(v.confirmed, .personal, "now changed")
}

// ───────────────────────────────────────────── session auto-select

print("\nSESSION — first unreported, once per date, and a manual pick latches")
do {
    let today = [SessionAutoSelect.Candidate(id: "a", alreadyReported: true),
                 SessionAutoSelect.Candidate(id: "b"),
                 SessionAutoSelect.Candidate(id: "c")]
    var s = SessionAutoSelect()
    s.run(for: "2026-07-26", sessions: today)
    eq(s.selection, "b", "skips the one already reported")

    // A listener refresh re-runs it. It must not move.
    s.run(for: "2026-07-26", sessions: today)
    eq(s.selection, "b", "second run for the same date does nothing")

    s.pick("c")
    eq(s.selection, "c", "a manual pick applies")
    check(s.isLatched, "and latches")
    s.run(for: "2026-07-26", sessions: today)
    eq(s.selection, "c", "auto-select cannot override a manual pick")
}

print("\nSESSION — off-schedule is a real choice, and a new date starts over")
do {
    let today = [SessionAutoSelect.Candidate(id: "a")]
    var s = SessionAutoSelect()
    s.run(for: "2026-07-26", sessions: today)
    s.pick(nil)
    check(s.selection == nil, "off-schedule holds")
    check(s.isLatched, "choosing off-schedule latches too")

    s.dateChanged()
    check(!s.isLatched, "a new date unlatches")
    check(s.selection == nil, "and clears the selection")
    s.run(for: "2026-07-27", sessions: today)
    eq(s.selection, "a", "the new date gets its own auto-select")
}

print("\nSESSION — a day where everything is already reported")
do {
    let today = [SessionAutoSelect.Candidate(id: "a", alreadyReported: true),
                 SessionAutoSelect.Candidate(id: "b", alreadyReported: true)]
    var s = SessionAutoSelect()
    s.run(for: "2026-07-26", sessions: today)
    check(s.selection == nil, "selects nothing rather than re-offering a filed session")
}

// ───────────────────────────────────────────── option lists

// OWNERSHIP MUST NOT DEPEND ON THE ORDER THE CLAIMS ARRIVED IN. A school held
// by both a source and the photographer survives until BOTH let go — the same
// rule the two sources already follow between themselves.
print("\nSCHOOL OWNERSHIP — order independence")
do {
    var a = ReportSchoolLink()          // hand-add first, then the session
    a.addStop("riverside")
    a.set("riverside", for: .session)
    a.set(nil, for: .session)

    var b = ReportSchoolLink()          // the session first, then the hand-add
    b.set("riverside", for: .session)
    b.addStop("riverside")
    b.set(nil, for: .session)

    eq(a.stops, ["riverside"], "hand-add then session: the stop survives")
    eq(b.stops, ["riverside"], "session then hand-add: the stop survives too")
    eq(a.stops, b.stops, "and the two orders agree")

    // Discriminating: pre-fix, `a` kept the stop and `b` lost it, so `b` is the
    // one to assert against — and removal is exercised on `a`, which held it
    // either way, so it tests `removeStop` rather than the ordering.
    check(b.handAdded.contains("riverside"),
          "the hand-add is recorded whichever order it arrived in")
    var c = a
    c.removeStop("riverside")
    eq(c.stops, [], "the photographer letting go is what removes it")
    check(!c.handAdded.contains("riverside"), "and the claim is released with it")
}

// THE SILENT SUBSTITUTION. The screen says "You typed this — it won't be
// overwritten" while `value` fell back to the calculated figure whenever the
// text would not parse. A decimal pad on a non-US locale emits a comma, and a
// paste carries whitespace. This is reimbursement data.
print("\nMILEAGE — text that is not a plain number")
do {
    var m = ReportMileage(calculated: 18.2)
    m.type("12,5")
    eq(m.value, 12.5, "a comma decimal separator is read, not discarded")
    check(!m.typedIsUnreadable, "and is not flagged as unreadable")

    m.type(" 12.5 ")
    eq(m.value, 12.5, "surrounding whitespace is trimmed")

    m.type("about twelve")
    check(m.typedIsUnreadable, "text that is not a number IS flagged")
    eq(m.value, 18.2, "and the report falls back to the calculated figure")

    // Already true before the comma work; kept as regression cover, not as
    // evidence for it.
    m.type("0")
    eq(m.value, 0, "a deliberate zero is honoured rather than treated as empty")

    m.type("1,234")
    check(m.typedIsUnreadable, "a grouped number is refused rather than read as 1.234")
    m.type("1.234,5")
    check(m.typedIsUnreadable, "and so is a number carrying both separators")
    m.type("12.")
    eq(m.value, 12.0, "a half-typed number still parses")
    check(!m.typedIsUnreadable, "and a half-typed number is not flagged")
    m.type("0")
    check(!m.typedIsUnreadable, "a zero is not flagged as unreadable either")
}

// `Double` accepts more than a mileage. A NaN reaches the JSON encoder, which
// refuses it, so the submit dies with something nobody can act on.
print("\nMILEAGE — text that Double accepts but a report cannot")
do {
    var m = ReportMileage(calculated: 18.2)
    for text in ["nan", "inf", "-inf", "1e3", "0x1p4", "NaN", "-5", "-0.5", "+5"] {
        m.type(text)
        check(m.typedIsUnreadable, "\"\(text)\" is refused")
        // The value that actually goes on the report — the calculated figure,
        // not whatever Double made of the text.
        eq(m.value, 18.2, "\"\(text)\" cannot reach the report")
    }
    m.type("18")
    eq(m.value, 18, "and a plain integer still works")
}

// GROUPING IS PRESENTATION, AND IT MUST LOSE NOTHING. The screen draws the
// GROUPED lists; the report stores values from the FLAT lists. If a group ever
// disagrees with its flat list, a checkbox a photographer needs silently stops
// existing — and the screen still builds, still looks right, and still submits.
// That is the exact failure shape this arc keeps finding, so it is a test.
print("\nOPTIONS — 22 job descriptions, grouped, nothing lost")
do {
    eq(ReportOptions.jobDescriptions.count, 22, "22 job descriptions")
    check(ReportOptions.groupingIsFaithful(flat: ReportOptions.jobDescriptions,
                                           groups: ReportOptions.jobDescriptionGroups),
          "every job description appears exactly once across the groups")
    eq(Set(ReportOptions.flattened(ReportOptions.jobDescriptionGroups)),
       Set(ReportOptions.jobDescriptions),
       "and no group invents one that is not in the list")
    check(ReportOptions.jobDescriptions.contains("NONE"),
          "\"NONE\" is an ordinary option in the list")
}

print("\nOPTIONS — 12 extra items, grouped, nothing lost")
do {
    eq(ReportOptions.extraItems.count, 12, "12 extra items")
    check(ReportOptions.groupingIsFaithful(flat: ReportOptions.extraItems,
                                           groups: ReportOptions.extraItemGroups),
          "every extra item appears exactly once across the groups")
    eq(Set(ReportOptions.flattened(ReportOptions.extraItemGroups)),
       Set(ReportOptions.extraItems),
       "and no group invents one that is not in the list")
}

print("\nOPTIONS — the grouping check can actually fail")
do {
    // A test that cannot fail is fake evidence in another costume, so prove the
    // check catches both a dropped option and an invented one.
    let dropped: [(String, [String])] = [("Some", Array(ReportOptions.extraItems.dropLast()))]
    check(!ReportOptions.groupingIsFaithful(flat: ReportOptions.extraItems, groups: dropped),
          "a dropped option is caught")
    let invented: [(String, [String])] = [("Some", ReportOptions.extraItems.dropLast() + ["Typo"])]
    check(!ReportOptions.groupingIsFaithful(flat: ReportOptions.extraItems, groups: invented),
          "an invented option is caught")
}

print("\nOPTIONS — the scan answers")
do {
    eq(ReportOptions.yesNo, ["Yes", "No"], "Cards Scanned has no NA")
    eq(ReportOptions.yesNoNA, ["Yes", "No", "NA"], "the other two do")
}

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 { print("FAILED"); exit(1) }
print("PASSED")
