//  TimeClockRules.swift
//  Iconik Employee — the time clock's domain rules, as compiled types
//
//  PRODUCTION CODE, COMPILED AND RUN BY `scripts/test_timeclock_rules.sh`.
//
//  WHY THIS FILE EXISTS, and why it exists on THIS surface in particular.
//
//      The clock has seven write paths and they disagreed with each other. A
//      shift you CREATE may be at most 16 hours; a shift you EDIT was allowed up
//      to 24 by the form and then rejected at 16 by the write it calls
//      (`EditTimeEntryView.swift:318` against `Models.swift:706`). Nobody wrote
//      that ceiling down twice on purpose — it was written down twice because
//      there was nowhere to write it down once, so each form restated the rule
//      from memory and one of them remembered wrong. The same rule then appears
//      a third time inside `TimeTrackingService` as a server-side guard.
//
//      These are payroll rules. AMB.7 proved the shape that holds: pull them
//      into SwiftUI-free value types, compile the REAL file in a harness, and
//      run it. A rule that is a compiled type with a passing test holds; a rule
//      that is a sentence in a comment beside a `guard` does not.
//
//      The test does NOT reimplement these in another language and check that.
//      That mistake was made once on this arc and the operator's verdict was
//      "your logic was fake and doesn't actually do anything". The script
//      compiles THIS file, from this path.
//
//  WHAT THIS FILE IS NOT. It is not a new validation layer sitting in front of
//  the service. `TimeTrackingService` and `TimeEntryValidator` still perform
//  every check they performed before, in the same order, and the server checks
//  again after that — three layers, unchanged, because a design phase does not
//  get to move a business rule (D12). What this file changes is that the FORMS
//  now ask this type what the ceiling is instead of each restating it.
//
//  NO SwiftUI IMPORT. Deliberate and load-bearing: `swiftc` compiles this
//  standalone. Anything that needs a Color or a View belongs in TimeClockKit.

import Foundation

// MARK: - The limits, written down once

/// Every numeric rule the clock enforces, in one place.
///
/// The values are not new. Each one is copied from the write path that already
/// enforces it, and the file:line it came from is on the line beside it — so
/// this is a consolidation, not a redesign of the rules.
public enum TimeClockLimits {

    /// Notes cap, all five note fields. `Models.swift:680` (`validateNotes`).
    ///
    /// `CustomClockOutView` was the one screen of five that did not draw this,
    /// so its notes were capped only by the server's rejection after Save.
    public static let notesMaxCharacters = 500

    /// A shift must last at least a minute. `Models.swift:711`.
    public static let minimumDuration: TimeInterval = 60

    /// A shift you WRITE DOWN after the fact — created manually, or an existing
    /// entry edited — may be at most 16 hours. `Models.swift:706`, and the same
    /// number in `ManualTimeEntryView.swift:151`.
    ///
    /// THIS IS THE CEILING THE EDIT FORM WAS GETTING WRONG. `EditTimeEntryView`
    /// used 24 hours, so a 17-hour edit passed the form, enabled Save, and threw
    /// on the write — `updateTimeEntry` routes completed entries through
    /// `validateManualEntry`, which is this 16. The form now asks here.
    public static let recordedShiftMaximum: TimeInterval = 16 * 3600

    /// A shift you CLOSE from the running clock may be at most 24 hours.
    /// `TimeTrackingService.swift:397` (`clockOutManual`).
    ///
    /// A DIFFERENT NUMBER FROM THE ONE ABOVE, ON PURPOSE. This is a live shift
    /// being ended late — you really were clocked in that whole time and the
    /// record has to be able to say so. `recordedShiftMaximum` is a shift being
    /// typed in from nothing. They are different acts with different risks, and
    /// before this file the only way to know that was to read two services.
    public static let liveClockOutMaximum: TimeInterval = 24 * 3600

    /// Past this, the app offers to set a custom clock-out time rather than
    /// stamping "now". `TimeTrackingMainView.swift:261`.
    public static let longShiftThreshold: TimeInterval = 24 * 3600

    /// A completed entry stops being editable 30 days after it was CREATED —
    /// not 30 days after the shift it records. `Models.swift:728-729`.
    ///
    /// The distinction is real and is why the window is stated in the UI now: a
    /// manual entry typed today for a shift last spring is editable, and a clock
    /// entry from 40 days ago is not.
    public static let editWindowDays = 30

    /// A RUNNING shift's start time may be moved back at most 48 hours.
    /// `Models.swift:745-746`.
    public static let activeClockInWindowHours = 48

    // PAY PERIODS ARE NOT DEFINED HERE ANY MORE, and that is the point.
    //
    // This file used to carry a 14-day grid anchored on 2024-02-25, lifted from
    // the literal the entry list parsed. Mileage meanwhile asked
    // `PayPeriodService`, which honours the ORGANISATION's real
    // `pay_period_settings` — weekly, bi-weekly or monthly. Two definitions of
    // the same payroll concept, agreeing only by luck of the current
    // configuration. The clock now asks the same resolver, through the shared
    // `PayPeriodSequence` in Services/. See that file's header.
}

// MARK: - Why a write was refused

/// A refusal, carrying the words the user sees.
///
/// The strings are the SHIPPED strings, kept verbatim. Five forms had their own
/// wording for the same refusal — "End time must be after start time" and "End
/// must be after start" and "Clock out time must be after clock in time" are one
/// rule said three ways. They are unified here, and where the shipped wording
/// differed the clearer one won; each choice is noted.
public enum TimeClockRefusal: Equatable {
    case endsBeforeItStarts
    case tooShort
    case tooLong(limit: TimeInterval)
    case inTheFuture
    case notesTooLong(limit: Int)
    case clockInTooFarBack(hours: Int)
    case editWindowClosed(days: Int)

    public var message: String {
        switch self {
        case .endsBeforeItStarts:
            // `ManualTimeEntryView:172` and `Models.swift:701` both said this;
            // `EditTimeEntryView:295` abbreviated it to "End must be after
            // start" to fit a narrow trailing column. The full sentence wins —
            // the new layout has room for it.
            return "End time must be after start time"
        case .tooShort:
            return "A time entry must be at least 1 minute long"
        case .tooLong(let limit):
            return "A time entry cannot exceed \(Int(limit / 3600)) hours"
        case .inTheFuture:
            return "A time entry cannot be in the future"
        case .notesTooLong(let limit):
            return "Notes cannot exceed \(limit) characters"
        case .clockInTooFarBack(let hours):
            return "Clock-in time must be within the last \(hours) hours"
        case .editWindowClosed(let days):
            return "This entry can no longer be edited — the \(days)-day window has passed"
        }
    }
}

// MARK: - The rules

public enum TimeClockRules {

    // MARK: A shift written down after the fact

    /// Manual creation, and editing a completed entry. Both write paths reach
    /// `TimeEntryValidator.validateManualEntry`, so both get this.
    ///
    /// ORDER MATTERS AND MIRRORS THE SERVICE. `validateManualEntry` checks the
    /// future first, then ordering, then the ceiling, then the floor
    /// (`Models.swift:692-714`) — so a 20-hour entry ending tomorrow reports
    /// "in the future", not "too long", exactly as it does today. A form that
    /// reported a different reason from the one the write will report is the
    /// same class of lie this file exists to remove.
    public static func refusalForRecordedShift(start: Date,
                                               end: Date,
                                               now: Date = Date()) -> TimeClockRefusal? {
        if end > now { return .inTheFuture }
        if end <= start { return .endsBeforeItStarts }
        let duration = end.timeIntervalSince(start)
        if duration > TimeClockLimits.recordedShiftMaximum {
            return .tooLong(limit: TimeClockLimits.recordedShiftMaximum)
        }
        if duration < TimeClockLimits.minimumDuration { return .tooShort }
        return nil
    }

    // MARK: Closing a running shift late

    /// `clockOutManual` — the "Set Custom Time" path off the long-shift alert.
    /// Mirrors `TimeTrackingService.swift:379-399` in its order.
    public static func refusalForLiveClockOut(clockIn: Date,
                                              clockOut: Date,
                                              now: Date = Date()) -> TimeClockRefusal? {
        if clockOut > now { return .inTheFuture }
        if clockOut <= clockIn { return .endsBeforeItStarts }
        if clockOut.timeIntervalSince(clockIn) > TimeClockLimits.liveClockOutMaximum {
            return .tooLong(limit: TimeClockLimits.liveClockOutMaximum)
        }
        return nil
    }

    // MARK: Moving a running shift's start

    /// Mirrors `TimeEntryValidator.canEditActiveClockIn` (`Models.swift:733-751`,
    /// the 48-hour floor at `:745-746`)
    /// for the two checks that are about TIME. The caller still has to establish
    /// that the entry is actually running; that is a fact about the row, not a
    /// rule, and it stays with the service.
    public static func refusalForActiveClockIn(newStart: Date,
                                               now: Date = Date(),
                                               calendar: Calendar = .current) -> TimeClockRefusal? {
        if newStart > now { return .inTheFuture }
        let earliest = calendar.date(byAdding: .hour,
                                     value: -TimeClockLimits.activeClockInWindowHours,
                                     to: now) ?? now
        if newStart < earliest {
            return .clockInTooFarBack(hours: TimeClockLimits.activeClockInWindowHours)
        }
        return nil
    }

    // MARK: Notes

    /// Mirrors `TimeEntryValidator.validateNotes` (`Models.swift:673-690`) —
    /// empty is fine, and the count is taken AFTER trimming, which is what the
    /// server does and what the shipped counters did not.
    public static func refusalForNotes(_ notes: String?) -> TimeClockRefusal? {
        guard let notes, !notes.isEmpty else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > TimeClockLimits.notesMaxCharacters {
            return .notesTooLong(limit: TimeClockLimits.notesMaxCharacters)
        }
        return nil
    }

    // MARK: The edit window

    /// Mirrors `TimeEntryValidator.canEditEntry` (`Models.swift:719-728`).
    ///
    /// `isRunning` short-circuits to true: a shift in progress is always
    /// editable, because its start time is the thing you fix when you forgot to
    /// clock in on time.
    public static func isEditable(createdAt: Date,
                                  isRunning: Bool,
                                  now: Date = Date(),
                                  calendar: Calendar = .current) -> Bool {
        if isRunning { return true }
        let cutoff = calendar.date(byAdding: .day,
                                   value: -TimeClockLimits.editWindowDays,
                                   to: now) ?? now
        return createdAt >= cutoff
    }

    /// Whole days left in the edit window, for the badge that now says so.
    /// Nil when the entry is running (no window applies) or already closed.
    public static func editWindowDaysRemaining(createdAt: Date,
                                               isRunning: Bool,
                                               now: Date = Date(),
                                               calendar: Calendar = .current) -> Int? {
        guard !isRunning else { return nil }
        guard isEditable(createdAt: createdAt, isRunning: false, now: now, calendar: calendar) else {
            return nil
        }
        let elapsed = calendar.dateComponents([.day], from: createdAt, to: now).day ?? 0
        return max(TimeClockLimits.editWindowDays - elapsed, 0)
    }

    // MARK: The long shift

    /// Mirrors `TimeTrackingMainView.checkForLongShift` (`:255-271`).
    public static func isLongShift(clockIn: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(clockIn) > TimeClockLimits.longShiftThreshold
    }
}

// MARK: - Pay periods

/// A date range the list can total.
public struct TimeClockPeriod: Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// The three ranges the entry list offers, in the order it offers them.
public enum TimeClockRange: String, CaseIterable {
    case today = "Today"
    case week = "This Week"
    case payPeriod = "Pay Period"

    /// The span this range covers, for the two ranges this file can answer.
    ///
    /// NIL FOR `.payPeriod`, deliberately. A pay period is the ORGANISATION's,
    /// not a calendar fact, so it comes from `PayPeriodService` through
    /// `PayPeriodSequence` — and the caller supplies WHICH one, because the list
    /// can now walk back through previous periods. A function that guessed here
    /// is exactly the second definition this file just deleted.
    public func fixedPeriod(now: Date = Date(), calendar: Calendar = .current) -> TimeClockPeriod? {
        switch self {
        case .today:
            return TimeClockPeriod(start: now, end: now)
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)
            return TimeClockPeriod(start: interval?.start ?? now, end: interval?.end ?? now)
        case .payPeriod:
            return nil
        }
    }
}

// MARK: - Reading a duration

public enum TimeClockFormat {

    /// "7h 18m" / "7h". Mirrors `TimeEntryListView.formatTotalHours` (`:135-144`),
    /// which drops the minutes when they are zero — the shipped
    /// `TimeInterval.formatAsHoursMinutes()` does not, and both are on this
    /// surface today.
    public static func hoursAndMinutes(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    /// "07:18:42" — the running clock. Mirrors
    /// `TimeInterval.formatAsHoursMinutesSeconds()` (`Models.swift:772`).
    public static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
