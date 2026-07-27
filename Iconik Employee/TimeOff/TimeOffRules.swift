//  TimeOffRules.swift
//  Iconik Employee — the Time Off domain rules, as compiled types
//
//  PRODUCTION CODE, COMPILED AND RUN BY `scripts/test_timeoff_rules.sh`.
//
//  WHY THIS FILE EXISTS
//      These rules were spread across a 519-line SwiftUI form as `.onChange`
//      handlers and inline arithmetic, which means they could only be verified by
//      reading them. AMB.7 proved the alternative: pull the rules into
//      SwiftUI-free value types, compile the REAL file in a test harness, and run
//      it. A rule that is a compiled type with a failing test holds; a rule that
//      is a sentence in a comment does not.
//
//      The test does NOT reimplement these rules in another language and check
//      that — that mistake was made once in this arc and the operator's verdict
//      was "your logic was fake and doesn't actually do anything". The script
//      compiles THIS file, from this path.
//
//  NO SwiftUI IMPORT. Deliberate, and load-bearing: `swiftc` compiles this
//  standalone. Anything that needs a Color or a View belongs in TimeOffKit.swift.

import Foundation

// MARK: - Time of day

/// A wall-clock time stored as the database stores it: the string "09:00".
///
/// PARSED WITH A PINNED POSIX LOCALE, which the app was not doing. Every
/// `DateFormatter` in the old Time Off code was built with `dateFormat = "HH:mm"`
/// and no locale, and a fixed format against the user's locale is the classic
/// way to get nil back on a device set to a 12-hour region. It appeared in five
/// places (the model's `durationInHours` and `timeFromString`, the form's edit-mode
/// seeding, the detail screen's formatter, and PTOService's hour calculation) and
/// a nil there is not an error anywhere — it degrades to "Invalid time range", to
/// a silently skipped seed, or to 0.0 hours requested.
struct TimeOfDay: Equatable, Comparable, Codable {
    /// Minutes since midnight. The single stored value, so two TimeOfDay cannot
    /// disagree with themselves.
    let minutes: Int

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    init(minutes: Int) {
        // CLAMPED TO 23:59, NOT 24:00. The old ceiling of 24*60 produced hour 24,
        // whose `storageString` is "24:00" — which this type's own `init?(_:)`
        // REJECTS, so a supposedly round-trip-safe value did not round-trip at its
        // own boundary. It also made `Calendar.date(bySettingHour: 24, …)` return
        // nil, which silently defeated the end-time repair for any start at or
        // after 23:00. Found by the correctness audit, which ran it.
        self.minutes = max(0, min(24 * 60 - 1, minutes))
    }

    init(hour: Int, minute: Int) {
        self.init(minutes: hour * 60 + minute)
    }

    /// Parses "HH:mm". Returns nil for anything else — including "9:00 AM",
    /// which is what an unpinned formatter would have produced on a 12-hour
    /// device and then failed to read back.
    init?(_ string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              parts[0].count == 2, parts[1].count == 2,
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        self.init(hour: h, minute: m)
    }

    /// Always "HH:mm", zero-padded, which is what the column holds.
    var storageString: String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    static func < (a: TimeOfDay, b: TimeOfDay) -> Bool { a.minutes < b.minutes }

    func adding(minutes delta: Int) -> TimeOfDay { TimeOfDay(minutes: minutes + delta) }
}

// MARK: - Span

/// How long a request is, and how it is written down.
///
/// THE RULE THAT MATTERS: a full-day span is INCLUSIVE OF BOTH ENDPOINTS. Monday
/// to Friday is five days, not four. It lives here rather than in a view because
/// it is a payroll number — it is what the PTO hours are derived from — and a
/// redesign must not be able to quietly change it to a subtraction.
struct TimeOffSpan: Equatable {
    let startDay: Date
    let endDay: Date
    let isPartialDay: Bool
    let start: TimeOfDay?
    let end: TimeOfDay?

    /// A partial day is a SINGLE date: the form forces end = start when the type
    /// is switched, and this type refuses to represent anything else.
    init(startDay: Date, endDay: Date, isPartialDay: Bool, start: TimeOfDay? = nil, end: TimeOfDay? = nil) {
        self.startDay = startDay
        self.endDay = isPartialDay ? startDay : endDay
        self.isPartialDay = isPartialDay
        self.start = isPartialDay ? start : nil
        self.end = isPartialDay ? end : nil
    }

    /// INCLUSIVE. days + 1.
    var dayCount: Int {
        let cal = Calendar.current
        let from = cal.startOfDay(for: startDay)
        let to = cal.startOfDay(for: endDay)
        let days = cal.dateComponents([.day], from: from, to: to).day ?? 0
        return max(1, days + 1)
    }

    /// Elapsed hours for a partial day. Nil when the times are missing or
    /// unparseable — NOT zero, because zero is a legitimate answer that a caller
    /// would be unable to tell apart from a failure.
    var partialHours: Double? {
        guard isPartialDay, let start, let end else { return nil }
        return Double(end.minutes - start.minutes) / 60.0
    }

    /// Minutes a partial day covers, for the 30-minute minimum.
    var partialMinutes: Int? {
        guard isPartialDay, let start, let end else { return nil }
        return end.minutes - start.minutes
    }
}

// MARK: - The partial-day time range

/// Start and end times for a partial day, with the app's real repair behaviour.
///
/// AN INVALID RANGE IS AUTO-REPAIRED, NOT REJECTED. If the end lands at or before
/// the start, the app moves the end to start + 1 hour rather than showing an
/// error. That is a deliberate kindness in a form a photographer fills on a phone,
/// and it is preserved exactly — a redesign that "improved" it into a validation
/// error would be a worse screen that looked the same in a screenshot.
struct PartialDayRange: Equatable {
    private(set) var start: TimeOfDay
    private(set) var end: TimeOfDay

    /// The app's floor: a partial day must be at least 30 minutes. This is the
    /// ONLY thing that disables Submit.
    static let minimumMinutes = 30

    init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
        repairIfNeeded()
    }

    mutating func setStart(_ value: TimeOfDay) {
        start = value
        repairIfNeeded()
    }

    mutating func setEnd(_ value: TimeOfDay) {
        end = value
        repairIfNeeded()
    }

    /// end <= start becomes start + 1 hour.
    private mutating func repairIfNeeded() {
        if end <= start {
            end = start.adding(minutes: 60)
        }
    }

    var minutes: Int { end.minutes - start.minutes }

    var meetsMinimum: Bool { minutes >= Self.minimumMinutes }
}

// MARK: - The full-day date range

/// Start and end dates, with the app's real coupling.
///
/// MOVING THE START PAST THE END DRAGS THE END WITH IT. The old form did this in
/// an `.onChange` (`if newValue > endDate { endDate = newValue }`) and bounded the
/// end picker at `startDate...`. Both halves are here so the coupling cannot be
/// half-implemented.
struct FullDayRange: Equatable {
    private(set) var start: Date
    private(set) var end: Date

    init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    mutating func setStart(_ value: Date) {
        start = value
        if end < start { end = start }
    }

    mutating func setEnd(_ value: Date) {
        end = max(start, value)
    }
}

// MARK: - PTO hours

/// The PTO hours field: auto-filled from the dates, but a hand-typed value wins.
///
/// THE REAL RULE, quoted from the old form so it survives the rewrite:
///
///     if ptoHoursRequested == 0 || ptoHoursRequested == calculatedHours {
///         ptoHoursRequested = calculatedHours
///     }
///
/// Which means: the field re-fills while it still holds either nothing or exactly
/// what the dates imply, and stops re-filling the moment the user types something
/// different. Modelled as a state machine rather than re-derived at each call
/// site, because "fixing the instance rather than the state machine" is what cost
/// AMB.7 five fix rounds.
struct PTOHoursField: Equatable {
    private(set) var value: Double
    /// True once the user has typed a value that is neither zero nor the
    /// auto-filled one. From then on the dates never overwrite it.
    private(set) var isUserEdited: Bool

    init(value: Double = 0, isUserEdited: Bool = false) {
        self.value = value
        self.isUserEdited = isUserEdited
    }

    /// Called whenever the dates change.
    mutating func autoFill(calculated: Double) {
        guard !isUserEdited else { return }
        value = calculated
    }

    /// Called when the user types.
    mutating func userTyped(_ typed: Double, calculated: Double) {
        value = typed
        // Typing the auto-filled number, or clearing to zero, is not a takeover:
        // it leaves the field tracking the dates again, which is what the old
        // `== 0 || == calculatedHours` test did.
        isUserEdited = !(typed == 0 || typed == calculated)
    }
}

/// A full day is EIGHT PTO hours. Weekends and holidays are counted — the app has
/// never known about either, and inventing that here would be a business-rule
/// change inside a design phase.
enum PTOMath {
    static let hoursPerFullDay: Double = 8

    /// What the dates imply. Mirrors PTOService.calculatePTOHours, except that a
    /// partial day with unreadable times yields nil rather than 0.0 — see the
    /// note on `TimeOffSpan.partialHours`.
    static func calculatedHours(for span: TimeOffSpan) -> Double? {
        if span.isPartialDay {
            guard let hours = span.partialHours else { return nil }
            return max(0, hours)
        }
        return Double(span.dayCount) * hoursPerFullDay
    }

    /// What is left after this request. Can go negative, and the sign is the
    /// whole point — the old screen showed a projected balance clamped at zero in
    /// one path and unclamped in another.
    static func remaining(available: Double, requested: Double) -> Double {
        available - requested
    }
}

/// How a request stands against the balance.
///
/// THREE OUTCOMES, and the design draws a different message for each. Note what
/// this type does NOT do: it does not decide whether to BLOCK submission. Blocking
/// a shortfall is a payroll change that belongs to TOF.1, not to a design phase,
/// so this reports the state and the view says so plainly.
enum PTOStanding: Equatable {
    /// Enough banked right now.
    case sufficient
    /// Not enough today, but the accrual by the request date covers it.
    case coveredByFutureAccrual
    /// Short even after accrual. `shortBy` is always positive.
    case short(shortBy: Double)

    static func evaluate(availableNow: Double,
                         projectedByRequestDate: Double,
                         requested: Double) -> PTOStanding {
        if requested <= availableNow { return .sufficient }
        if requested <= projectedByRequestDate { return .coveredByFutureAccrual }
        return .short(shortBy: requested - projectedByRequestDate)
    }
}

// MARK: - Submission

/// What actually disables Submit.
///
/// THE OLD RULE, PRESERVED EXACTLY: only the 30-minute partial-day minimum blocks
/// submission. A full-day request is NEVER blocked — not by a missing reason, not
/// by a PTO shortfall, not by anything. That is surprising enough to be worth
/// stating as a type, and it is deliberately NOT tightened here: tightening it
/// would change who can file what, which is TOF.1's call and not a restyle's.
enum SubmitGate: Equatable {
    case allowed
    case blockedByPartialDayMinimum

    static func evaluate(span: TimeOffSpan) -> SubmitGate {
        guard span.isPartialDay else { return .allowed }
        guard let minutes = span.partialMinutes else { return .blockedByPartialDayMinimum }
        return minutes >= PartialDayRange.minimumMinutes ? .allowed : .blockedByPartialDayMinimum
    }

    var isAllowed: Bool { self == .allowed }
}

// MARK: - Queue order

/// The order each list is read in.
///
/// THE MANAGER QUEUE IS FIFO AND THE EMPLOYEE LIST IS NOT. That is real workflow
/// knowledge — a manager works a queue from the top, an employee looks for what
/// they just filed — and in the old code it lived in three bare `.sorted` calls
/// in a view body where the next person to touch the screen would have "fixed"
/// the inconsistency. Naming the orders is what stops that.
enum TimeOffOrder {
    /// Your own requests: newest first.
    static func employeeList<T>(_ items: [T], createdAt: (T) -> Date) -> [T] {
        items.sorted { createdAt($0) > createdAt($1) }
    }

    /// Pending and In Review: OLDEST FIRST. The oldest request has been waiting
    /// longest and is the one to action next.
    static func managerQueue<T>(_ items: [T], createdAt: (T) -> Date) -> [T] {
        items.sorted { createdAt($0) < createdAt($1) }
    }

    /// History: by when it was ACTIONED, newest first — not by when it was filed.
    static func history<T>(_ items: [T], actionedAt: (T) -> Date) -> [T] {
        items.sorted { actionedAt($0) > actionedAt($1) }
    }

    /// How long a queued request has been waiting, in whole days, floored at 0.
    static func waitingDays(since created: Date, now: Date = Date()) -> Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: created),
                                      to: cal.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }
}

// MARK: - Attribution

/// Who actioned a request, and when.
///
/// CONDITIONAL ON BOTH THE NAME AND THE DATE. The old card tested both before
/// drawing the line, and one of the lab's sample rows is an approved request whose
/// approver name never came back — so a card that drops the `&&` renders a bare
/// "Approved by" with nothing after it. Returning nil rather than a half-built
/// string is what makes that unrepresentable.
struct TimeOffAttribution: Equatable {
    let name: String
    let date: Date
    let status: TimeOffRuleStatus

    init?(name: String?, date: Date?, status: TimeOffRuleStatus) {
        guard let name, let date, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.name = name
        self.date = date
        self.status = status
    }

    /// "Approved by Alex Fontaine" — a sentence a person would say, never
    /// `rawValue.capitalized`, which is where the shipped "Underreview" came from.
    var verb: String {
        switch status {
        case .approved: return "Approved by \(name)"
        case .denied: return "Denied by \(name)"
        case .underReview: return "In review by \(name)"
        case .pending, .cancelled: return name
        }
    }
}

// MARK: - Reason, across two clients

/// THE REASON VOCABULARIES OF THE TWO CLIENTS DO NOT INTERSECT AT ALL.
///
/// The web app writes human strings — "Vacation", "Sick Leave", "Personal Day",
/// "Family Emergency", "Medical Appointment", "Other" (its REASONS list in
/// `src/components/timeoff/TimeOffRequestModal.js`, written verbatim through
/// `formData.reason.trim()`). iOS writes lowercase enum raw values — "vacation",
/// "sick", "personal", "emergency", "bereavement", "other".
///
/// There is not one string in common. `TimeOffReason(rawValue:) ?? .other` means
/// EVERY REQUEST CREATED ON THE WEB RENDERS AS "Other" WITH A GREY ELLIPSIS on
/// iOS — and the approved design leans on the reason's icon and colour as the
/// fastest read on the card, so on real data that card would degrade to a column
/// of identical grey marks.
///
/// This resolves BOTH vocabularies for DISPLAY. It writes nothing and it does not
/// change what iOS stores: `TimeOffReason` remains the writable set, so this is a
/// presentation repair inside the surface being converted, not a data change.
/// Reconciling the two vocabularies at the database is a cross-client job and is
/// recorded for TOF.1 rather than done here.
enum TimeOffReasonVocabulary: String, CaseIterable, Equatable {
    case vacation
    case sick
    case personal
    case emergency
    case bereavement
    case medical
    case other

    var label: String {
        switch self {
        case .vacation: return "Vacation"
        case .sick: return "Sick Leave"
        case .personal: return "Personal Day"
        case .emergency: return "Family Emergency"
        case .bereavement: return "Bereavement"
        case .medical: return "Medical Appointment"
        case .other: return "Other"
        }
    }

    /// Recognises what EITHER client writes. Matching is case- and
    /// whitespace-insensitive because the web trims but does not normalise case.
    ///
    /// Returns nil rather than `.other` for a genuinely unrecognised string, so a
    /// caller can tell "someone wrote something new" apart from "the user picked
    /// Other". Collapsing those two is the same mistake as reporting a failed
    /// fetch as an empty list.
    static func parse(_ raw: String) -> TimeOffReasonVocabulary? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "vacation":                        return .vacation
        case "sick", "sick leave":              return .sick
        case "personal", "personal day":        return .personal
        case "emergency", "family emergency":   return .emergency
        case "bereavement":                     return .bereavement
        case "medical", "medical appointment":  return .medical
        case "other":                           return .other
        default:                                return nil
        }
    }
}

/// A SwiftUI-free mirror of `TimeOffStatus`, so this file compiles standalone.
///
/// It carries the RAW VALUES the shared database actually stores, including the
/// camelCase "underReview", so the test harness is checking the real strings the
/// web app writes rather than a tidied-up copy of them.
enum TimeOffRuleStatus: String, CaseIterable, Equatable {
    case pending
    case underReview
    case approved
    case denied
    case cancelled

    /// What a person would say out loud. NEVER `rawValue.capitalized`.
    var label: String {
        switch self {
        case .pending: return "Pending"
        case .underReview: return "In Review"
        case .approved: return "Approved"
        case .denied: return "Denied"
        case .cancelled: return "Cancelled"
        }
    }

    /// Edit and Cancel are offered on exactly these two.
    var isEditable: Bool { self == .pending || self == .underReview }

    /// An unknown status from another client must NOT silently become "Pending",
    /// which is what `TimeOffStatus(rawValue:) ?? .pending` does today: a request
    /// the web app had approved would render as awaiting a decision, with live
    /// Edit and Cancel buttons on it. Returning nil lets the caller say
    /// "unrecognised" instead of asserting a wrong one.
    static func parse(_ raw: String) -> TimeOffRuleStatus? {
        TimeOffRuleStatus(rawValue: raw)
    }
}

// MARK: - Whether the PTO figures mean anything yet

/// PTO HAS NEVER FUNCTIONED IN THIS APP (operator, 2026-07-27), and the code
/// agrees: `addAccruedHours` has NO CALLERS, so nothing ever accrues;
/// `usePTOHours` never persists `used`; the web app's entire PTO write surface —
/// reserve, use, release, adjust — is dead code with zero callers; and
/// `pto_settings` is written snake_case by the web and read camelCase by iOS, so
/// every accrual setting an admin configures is ignored.
///
/// The consequence for the SCREENS is concrete. Balances start at whatever a row
/// was created with and never grow, so "Use PTO Balance" defaulting ON means every
/// request computes as a shortfall — an orange "you are 8.0 hours short" on
/// essentially every request anyone files — and the balance hero reads
/// "0.0 hours available" for everyone, permanently.
///
/// An app that states a payroll number it cannot support is worse than one that
/// says it does not know. This decides which.
///
/// IT IS SELF-HEALING BY DESIGN: the moment real hours accrue or are used, the
/// figures become `.tracked` and the screens show them again with no code change.
/// That matters because the fix (TOF.1) is a cross-client data change, and nobody
/// should have to remember to come back and re-enable a screen.
enum PTOTracking: Equatable {
    /// Real figures. Show them.
    case tracked
    /// The organisation has PTO switched off. Nothing to show and nothing wrong.
    case notConfigured
    /// PTO is on, but no hours have ever entered the system for this person —
    /// nothing accrued, nothing used, nothing banked. Any figure derived from
    /// this is arithmetic on zeroes dressed up as a balance.
    case noActivity

    var showsFigures: Bool { self == .tracked }

    /// `pending` is deliberately NOT part of the test. Reservations DO get written
    /// on create, so a person can have pending hours while nothing has ever
    /// accrued — which is precisely the broken state, not evidence of a working
    /// one. Treating a non-zero pending as "tracked" would make the shortfall
    /// warning fire hardest for exactly the people it is most wrong about.
    static func evaluate(enabled: Bool,
                         balance: Double,
                         accrued: Double,
                         used: Double,
                         banking: Double) -> PTOTracking {
        guard enabled else { return .notConfigured }
        let anyActivity = balance != 0 || accrued != 0 || used != 0 || banking != 0
        return anyActivity ? .tracked : .noActivity
    }
}
