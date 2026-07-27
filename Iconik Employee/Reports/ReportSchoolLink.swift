//  ReportSchoolLink.swift
//  Iconik Employee — the daily job report's school-ownership rule
//
//  PRODUCTION CODE, used by the lab. It lives in Reports/ rather than DesignLab/
//  precisely so the conversion has nothing to move: the mockup and the real
//  screen run the SAME rule, which is the only way "exactly as designed" is a
//  property of the code rather than a promise someone has to keep.
//
//  WHY IT IS ITS OWN FILE
//      I previously "verified" this rule by rewriting it in Python and testing
//      the Python. That proves nothing about the Swift: if the two differ,
//      the test passes and the app is still wrong. The operator's words were
//      "your logic was fake and doesn't actually do anything."
//
//      So the rule lives here, in plain Foundation with no SwiftUI and no view
//      state, which means the REAL source file can be compiled and run directly
//      by scripts/test_report_school_link.swift. Same code the app builds.
//
//  THE RULE
//      A report carries a list of schools. Two things can put one there on your
//      behalf — the scheduled session, and an attached photoshoot note — and you
//      can add more yourself.
//
//        · Each source remembers the school IT contributed.
//        · Changing a source REPLACES its own school rather than adding another.
//        · Clearing a source (off-schedule, or "No photoshoot note") removes it.
//        · A school you added by hand is owned by no source, so nothing removes
//          it but you.
//        · If both sources point at the SAME school, it survives until both let
//          go of it.
//
//      Order is preserved: schools stay in the order they were added, because
//      that order is the route the mileage is calculated along.

import Foundation

struct ReportSchoolLink: Equatable {

    /// Which of the two automatic sources is being changed.
    enum Source {
        case session
        case note
    }

    /// School ids, in route order.
    private(set) var stops: [String]
    /// The school the scheduled session put on the report, if any.
    private(set) var sessionSchool: String?
    /// The school the attached photoshoot note put on the report, if any.
    private(set) var noteSchool: String?
    /// Schools the photographer added THEMSELVES.
    ///
    /// This is what makes "a school you added by hand is owned by no source"
    /// true rather than merely written down. Without it, a source that later
    /// pointed at the same school claimed it, and clearing that source took the
    /// hand-added stop away with it — hand-add Lincoln, pick the Lincoln
    /// session, go off-schedule, and Lincoln vanished from the route.
    private(set) var handAdded: Set<String>

    init(stops: [String] = [], sessionSchool: String? = nil, noteSchool: String? = nil,
         handAdded: Set<String> = []) {
        self.stops = stops
        self.sessionSchool = sessionSchool
        self.noteSchool = noteSchool
        self.handAdded = handAdded
    }

    /// Point a source at a school, or pass nil to clear it.
    mutating func set(_ school: String?, for source: Source) {
        let owned = self[source]
        let other = self[source.other]

        // Take out what this source was holding — unless the other source is
        // holding the same school, or the photographer put it there themselves.
        if let owned, owned != other, !handAdded.contains(owned) {
            stops.removeAll { $0 == owned }
        }

        guard let school else {
            self[source] = nil
            return
        }

        if !stops.contains(school) {
            stops.append(school)
        }
        self[source] = school
    }

    /// Add a school by hand. Owned by no source, so no source can remove it.
    ///
    /// A school a SOURCE is already holding is not claimed — otherwise adding
    /// one the session had already put there would pin it forever and the
    /// session could never clear its own school again, which is the inverse of
    /// the rule this set exists to enforce.
    mutating func addStop(_ school: String) {
        let ownedBySource = school == sessionSchool || school == noteSchool
        if !ownedBySource { handAdded.insert(school) }
        guard !stops.contains(school) else { return }
        stops.append(school)
    }

    /// Remove a school by hand. Whichever source was holding it lets go, so a
    /// later change cannot try to remove something that is already gone.
    mutating func removeStop(_ school: String) {
        stops.removeAll { $0 == school }
        handAdded.remove(school)
        if sessionSchool == school { sessionSchool = nil }
        if noteSchool == school { noteSchool = nil }
    }

    // MARK: private

    private subscript(source: Source) -> String? {
        get { source == .session ? sessionSchool : noteSchool }
        set {
            switch source {
            case .session: sessionSchool = newValue
            case .note: noteSchool = newValue
            }
        }
    }
}

private extension ReportSchoolLink.Source {
    var other: ReportSchoolLink.Source { self == .session ? .note : .session }
}
