//  test_report_school_link.swift
//  A real test of the real file.
//
//  Run:  swift scripts/test_report_school_link.swift \
//              "Iconik Employee/DesignLab/ReportSchoolLink.swift"
//  or:   scripts/test_report_school_link.sh
//
//  This compiles and executes ReportSchoolLink.swift — the SAME source the app
//  builds. It exists because the previous "verification" of this rule was a
//  Python reimplementation of it, which cannot detect the case that matters:
//  the Swift behaving differently from the description of the Swift.
//
//  There is no XCTest target in this project (the Tests folders are not wired
//  to any target and there is no test scheme), so this runs standalone.

import Foundation

var failures = 0
var checks = 0

func expect(_ actual: [String], _ expected: [String], _ what: String) {
    checks += 1
    if actual == expected {
        print("  ok    \(what)")
    } else {
        failures += 1
        print("  FAIL  \(what)\n          expected \(expected)\n          got      \(actual)")
    }
}

func expect(_ actual: String?, _ expected: String?, _ what: String) {
    checks += 1
    if actual == expected {
        print("  ok    \(what)")
    } else {
        failures += 1
        print("  FAIL  \(what)  expected \(expected as Any), got \(actual as Any)")
    }
}

let lincoln = "s1", riverside = "s2", oakmont = "s3"

print("\nA. changing the session REPLACES its school rather than adding one")
do {
    var link = ReportSchoolLink(stops: [riverside], sessionSchool: riverside)
    link.set(lincoln, for: .session)
    expect(link.stops, [lincoln], "Riverside swapped for Lincoln")
    expect(link.sessionSchool, lincoln, "session now owns Lincoln")
}

print("\nB. off-schedule removes the session's school")
do {
    var link = ReportSchoolLink(stops: [riverside], sessionSchool: riverside)
    link.set(nil, for: .session)
    expect(link.stops, [], "no schools left")
    expect(link.sessionSchool, nil, "session owns nothing")
}

print("\nC. a school added by hand survives a session change")
do {
    var link = ReportSchoolLink(stops: [riverside], sessionSchool: riverside)
    link.addStop(oakmont)
    link.set(lincoln, for: .session)
    expect(link.stops, [oakmont, lincoln], "Oakmont kept, Riverside replaced")
}

print("\nD. a school BOTH sources point at survives until both let go")
do {
    var link = ReportSchoolLink(stops: [riverside], sessionSchool: riverside)
    link.set(riverside, for: .note)
    expect(link.stops, [riverside], "still one school, not duplicated")
    link.set(lincoln, for: .session)
    expect(link.stops, [riverside, lincoln], "note still needs Riverside")
    link.set(nil, for: .note)
    expect(link.stops, [lincoln], "released once the note lets go")
}

print("\nE. \"No photoshoot note\" removes only the note's school")
do {
    var link = ReportSchoolLink(stops: [riverside], sessionSchool: riverside)
    link.set(oakmont, for: .note)
    expect(link.stops, [riverside, oakmont], "both present")
    link.set(nil, for: .note)
    expect(link.stops, [riverside], "session's school untouched")
}

print("\nF. removing a school by hand releases whichever source held it")
do {
    var link = ReportSchoolLink(stops: [riverside], sessionSchool: riverside)
    link.removeStop(riverside)
    expect(link.sessionSchool, nil, "session let go")
    link.set(lincoln, for: .session)
    expect(link.stops, [lincoln], "no stale removal of an absent school")
}

print("\nG. route ORDER is preserved — mileage is calculated along it")
do {
    var link = ReportSchoolLink()
    link.addStop(riverside)
    link.addStop(lincoln)
    link.addStop(oakmont)
    expect(link.stops, [riverside, lincoln, oakmont], "added order kept")
    link.removeStop(lincoln)
    expect(link.stops, [riverside, oakmont], "order kept after a removal")
}

print("\nH. setting a source to the school it already holds is a no-op")
do {
    var link = ReportSchoolLink(stops: [riverside], sessionSchool: riverside)
    link.set(riverside, for: .session)
    expect(link.stops, [riverside], "not duplicated, not dropped")
    expect(link.sessionSchool, riverside, "still owned")
}

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("FAILED")
    exit(1)
}
print("PASSED")
