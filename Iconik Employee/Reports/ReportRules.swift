//  ReportRules.swift
//  Iconik Employee — the daily job report's behaviour rules
//
//  PRODUCTION CODE, used by the lab. Same reasoning as ReportSchoolLink: these
//  live in Reports/ so the conversion has nothing to move, and the mockup and
//  the real screen run the SAME rule.
//
//  WHY THESE ARE TYPES AND NOT VIEW STATE
//      The operator's requirement is that the real screen "act EXACTLY as the
//      mockup does". A prose instruction to that effect already existed in the
//      phase kickoff when AMB.1 shipped a static day strip where the lab
//      scrolled, and then shipped it scrolling at the wrong width. Prose does
//      not hold. A rule that is a compiled type with a failing test does.
//
//      Each of these is deliberately free of SwiftUI so it can be compiled and
//      RUN by scripts/test_report_rules.sh — not paraphrased in another language
//      and tested there, which is a mistake already made once in this arc and
//      caught by the operator: "your logic was fake and doesn't actually do
//      anything."

import Foundation

// MARK: - Mileage

/// Total miles for a report, and the one rule that matters about it.
///
/// The number is calculated from the route between the schools on the report.
/// The photographer may type over it. THE TYPED VALUE WINS AND IS NEVER
/// OVERWRITTEN by a later recalculation — in the live app it is silently
/// replaced whenever anything triggers a recalc, and cleared outright if the
/// photographer has no home address set.
///
/// This matters beyond tidiness: mileage feeds reimbursement, and prepopulated
/// -form research found people leave a prefilled number alone when it favours
/// them. A figure that changes under you without saying so is the worst version
/// of that.
struct ReportMileage: Equatable {
    /// Miles derived from the current route. Updated freely by recalculation.
    private(set) var calculated: Double
    /// What the photographer typed, if anything. Raw text, because a partially
    /// typed "1" or "12." must survive keystrokes without being reinterpreted.
    private(set) var typed: String?

    init(calculated: Double = 0, typed: String? = nil) {
        self.calculated = calculated
        self.typed = typed
    }

    /// Whether the photographer has taken control of the number.
    var isOverridden: Bool {
        guard let typed else { return false }
        return !typed.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// What the photographer typed, read as a number.
    ///
    /// LENIENT ON PURPOSE. `Double("12,5")` is nil, and a decimal pad on a
    /// non-US locale emits a comma; `Double(" 12.5")` is nil too, and a paste
    /// carries whitespace. The screen said "You typed this — it won't be
    /// overwritten" while `value` quietly fell back to the calculated figure,
    /// so a comma meant the report filed a DIFFERENT number from the one on
    /// screen. This is reimbursement data.
    var typedValue: Double? {
        guard let typed else { return nil }
        let cleaned = typed
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    /// The photographer has typed something that is not a number at all.
    ///
    /// The screen MUST say so rather than filing the calculated figure behind
    /// their back — that silent substitution is the whole reason this is
    /// exposed rather than swallowed.
    var typedIsUnreadable: Bool { isOverridden && typedValue == nil }

    /// The value that goes on the report.
    var value: Double { typedValue ?? calculated }

    /// What the field shows. A typed value is shown verbatim so editing is not
    /// fought by reformatting mid-keystroke.
    var displayText: String {
        typed ?? String(format: "%.1f", calculated)
    }

    mutating func type(_ text: String) {
        typed = text
    }

    /// Hand the number back to the route.
    mutating func useCalculated() {
        typed = nil
    }

    /// The route changed. This updates the calculated figure and MUST NOT touch
    /// a typed one.
    mutating func recalculate(to miles: Double) {
        calculated = miles
    }
}

// MARK: - Vehicle

/// Personal or company, and the two-step that guards it.
///
/// NO DEFAULT (operator, 2026-07-26): nothing is pre-selected, the photographer
/// must choose, and BOTH options take a second tap. The first tap NEVER commits
/// — it arms a confirmation shown inline beside the buttons, so finishing the
/// choice does not mean reaching to the top of a long scroll.
///
/// This field sets the mileage reimbursement rate, which is why the live app
/// guards it and why the guard is worth keeping exactly.
struct VehicleSelection: Equatable {
    enum Vehicle: String, CaseIterable {
        case personal
        case company
    }

    /// The committed choice. Nil means the photographer has not chosen yet.
    private(set) var confirmed: Vehicle?
    /// Tapped but not yet confirmed. Not applied to anything.
    private(set) var pending: Vehicle?

    init(confirmed: Vehicle? = nil) {
        self.confirmed = confirmed
    }

    /// The report cannot be considered complete until this is false.
    var needsChoice: Bool { confirmed == nil }
    var isAwaitingConfirmation: Bool { pending != nil }

    /// First tap. Arms the confirmation and changes nothing else.
    mutating func tap(_ vehicle: Vehicle) {
        pending = vehicle
    }

    /// Second tap. Only now does the value change.
    mutating func confirm() {
        if let pending { confirmed = pending }
        pending = nil
    }

    mutating func cancel() {
        pending = nil
    }
}

// MARK: - Session auto-select

/// Which of today's sessions the report attaches itself to.
///
/// The live rule, kept: pick the FIRST session of the day the photographer has
/// not already filed a report against; run at most ONCE per date, so a listener
/// refresh cannot move it; and once the photographer picks one by hand, latch —
/// nothing automatic overrides a deliberate choice. Changing the report's date
/// resets all of that so the new day gets its own run.
struct SessionAutoSelect: Equatable {
    /// A session as this rule needs to see it.
    struct Candidate: Equatable {
        let id: String
        /// Already reported by this photographer, so auto-select skips it.
        let alreadyReported: Bool

        init(id: String, alreadyReported: Bool = false) {
            self.id = id
            self.alreadyReported = alreadyReported
        }
    }

    /// The chosen session. Nil means off-schedule, which is a real choice.
    private(set) var selection: String?
    /// True once the photographer has picked by hand.
    private(set) var isLatched = false
    /// The date key auto-select last ran for.
    private(set) var ranFor: String?

    init() {}

    /// Run auto-select for a date. Safe to call repeatedly — it does nothing
    /// after the first run for that date, and nothing at all once latched.
    ///
    /// `sessions` must already be in the order the picker shows them, which is
    /// earliest first with undated sessions last.
    mutating func run(for date: String, sessions: [Candidate]) {
        guard !isLatched else { return }
        guard ranFor != date else { return }
        ranFor = date
        selection = sessions.first { !$0.alreadyReported }?.id
    }

    /// A deliberate choice, including choosing off-schedule. Latches.
    mutating func pick(_ id: String?) {
        selection = id
        isLatched = true
    }

    /// The report's date moved, so the day's sessions are different ones.
    /// Everything resets and the new date gets its own auto-select.
    mutating func dateChanged() {
        selection = nil
        isLatched = false
        ranFor = nil
    }
}
