//  MileageRules.swift
//  Iconik Employee — the Mileage domain rules, as compiled types
//
//  PRODUCTION CODE, COMPILED AND RUN BY `scripts/test_mileage_rules.sh`.
//
//  WHY THIS FILE EXISTS
//      Mileage is money. Every number on the Mileage screens is either a payroll
//      figure or a label describing one, and before AMB.9 all of it was inline
//      arithmetic inside a 276-line SwiftUI body: the pay-period boundaries were a
//      hardcoded 14-day step that contradicted the org's real settings, the
//      personal/company split was assembled by hand in three places, and the card
//      titled "Current Period" showed a PAST period's totals. None of it could be
//      verified except by reading it.
//
//      So the arithmetic lives here, in SwiftUI-free value types that
//      `scripts/test_mileage_rules.sh` COMPILES FROM THIS PATH and runs. Not a
//      paraphrase in another language — that mistake was made once on this arc and
//      the operator's verdict was "your logic was fake and doesn't actually do
//      anything". The same file Xcode builds is the file the test builds.
//
//  NO SwiftUI IMPORT. Deliberate, and load-bearing: `swiftc` compiles this
//  standalone alongside VehicleRates.swift, which is Foundation-only for the same
//  reason. Anything that needs a Color or a View belongs in MileageKit.swift.
//
//  WHAT IS DELIBERATELY NOT HERE
//      Historical rates. Compensation is Σ(miles × TODAY's rate for that vehicle
//      type), because no per-report rate is stored anywhere in the data — the
//      column does not exist, so a "rate at the time" cannot be recovered. That is
//      recorded in AMB_BATCH3_PARITY.md §1 and left as it is rather than invented
//      here. What DID change is that the money now goes through
//      `VehicleRates.Split.add` per report, so personal and company miles are
//      never paid at the same rate by accident.

import Foundation

// MARK: - The cycle the org is actually on

/// Which pay-period cycle the organisation runs.
///
/// THE DEFECT THIS EXISTS TO KILL: the carousel used to step its labels back by a
/// HARDCODED 14 days (`MileageReportsView.swift:11-24`) while the DATA came from
/// `PayPeriodService`, which honours `PayPeriodSettings.type` — weekly, bi-weekly
/// or monthly. For a weekly org the chips said one thing and the totals under them
/// described another span entirely, and nothing on the screen said which.
///
/// The mapping mirrors `PayPeriodService.getPayPeriod` exactly, INCLUDING its
/// fallbacks, so the caption cannot describe a cycle the boundaries are not on:
/// an unknown type and inactive-or-missing settings both fall to bi-weekly there,
/// and both fall to bi-weekly here.
enum MileagePeriodCycle: String, Equatable, CaseIterable {
    case weekly
    case biweekly
    case monthly

    static func from(type: String?, isActive: Bool) -> MileagePeriodCycle {
        // Inactive or missing settings mean PayPeriodService uses its default
        // 2/25/2024-anchored 14-day period, which IS a bi-weekly cycle.
        guard isActive,
              let raw = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return .biweekly }
        switch raw {
        case "weekly":              return .weekly
        case "bi-weekly", "biweekly": return .biweekly
        case "monthly":             return .monthly
        // Same branch PayPeriodService takes for an unrecognised type.
        default:                    return .biweekly
        }
    }

    /// The caption under the carousel. It ships as a statement of fact rather than
    /// the mockup's PROPOSED note, because the boundaries above it are now the
    /// org's real ones.
    var caption: String {
        switch self {
        case .weekly:   return "Weekly pay periods"
        case .biweekly: return "Bi-weekly pay periods"
        case .monthly:  return "Monthly pay periods"
        }
    }
}

// MARK: - One pay period

/// A pay period, identified by how far back it is rather than by its start date.
///
/// THE INDEX IS THE IDENTITY, and that is the fix for a real defect: the old screen
/// held the selection as a `Date` seeded in `init` from a value the pay-period
/// service had not answered for yet, so on first render the selected date matched
/// NONE of the six cards. An index cannot be seeded wrong — it is resolved against
/// whatever list the service produces.
struct MileagePeriod: Equatable, Identifiable {
    /// 0 is the current period; 1 is the one before it, and so on.
    let index: Int
    let start: Date
    let end: Date

    var id: Int { index }
    var isCurrent: Bool { index == 0 }

    /// "Jul 20 – Aug 2". The formatter is injected so this file stays SwiftUI-free
    /// and the test can pin a POSIX one.
    func rangeLabel(monthDay: (Date) -> String) -> String {
        "\(monthDay(start)) – \(monthDay(end))"
    }

    /// THE HEADER CANNOT LIE, because it is derived from the selection rather than
    /// typed above it. The old card was titled "Current Period" permanently while
    /// its values were replaced with the selected period's.
    func headerLabel(monthDay: (Date) -> String) -> String {
        isCurrent
            ? "This pay period · \(rangeLabel(monthDay: monthDay))"
            : rangeLabel(monthDay: monthDay)
    }

    func contains(_ date: Date) -> Bool { date >= start && date <= end }
}

/// The six chips, newest first.
///
/// Built by WALKING BACKWARDS THROUGH THE REAL RESOLVER — one day before a
/// period's start is, by definition, inside the previous period — so a monthly org
/// gets calendar months of unequal length and a weekly org gets seven-day steps,
/// with no period-length arithmetic in this type at all. That is what makes it
/// correct for all three cycles instead of for one.
///
/// THE WALK STOPS RATHER THAN GUESSES. A resolver that answers with a period which
/// overlaps, repeats or does not abut the one already collected is describing a
/// cycle this walk cannot represent, and the two guards below end the sequence
/// there. Fewer honest chips; never a wrong one.
///
/// THE RESOLVER THAT PROVOKES THIS, and whose repair is NOT in AMB.9's scope:
/// `PayPeriodService.getMonthlyPayPeriod` (PayPeriodService.swift:166) assigns
/// `components.day = startDay` and lets Foundation roll an out-of-range day
/// forward, so a monthly org anchored on the 29th or the 31st gets periods that
/// jump (a day-31 anchor answers "Jul 1 – Jul 31" for July and then
/// "May 31 – Jun 29", skipping Jun 30) and a day-29 anchor leaves Feb 28 in no
/// period at all. That is a PRE-EXISTING defect in the payroll rule, owned by
/// `PayPeriodService` and shared with every other screen that reads it — and no
/// live organisation is on a monthly cycle (all three are bi-weekly, verified
/// 2026-07-29), so this phase guards against the shape instead of rewriting the
/// rule that produces it.
enum MileagePeriodSequence {
    static let chipCount = 6

    /// `resolve` is `PayPeriodService.getPayPeriod(for:)` in production and a
    /// hand-written cycle in the test.
    static func build(count: Int = chipCount,
                      now: Date = Date(),
                      calendar: Calendar = .current,
                      resolve: (Date) -> (start: Date, end: Date)?) -> [MileagePeriod] {
        var periods: [MileagePeriod] = []
        var probe = now

        for index in 0..<max(0, count) {
            guard let answer = resolve(probe) else { break }
            if let previous = periods.last {
                // NON-DECREASING: a resolver that keeps answering with the same
                // period — a misconfigured start date, a monthly cycle whose
                // day-of-month arithmetic sticks — would otherwise produce six
                // identical chips that all select the same range. Six copies of one
                // period is worse than fewer honest chips.
                if previous.start <= answer.start { break }
                // CONTIGUOUS: the previous chip's start is the day after this one
                // ends, because that is the day this walk probed with. When it is
                // not, the resolver has skipped days (mileage filed in them would
                // belong to no chip) or overlapped the chip already drawn (the same
                // trip counted twice). Either way the boundaries stop being the
                // org's, so the sequence ends here — see the day-29/31
                // `getMonthlyPayPeriod` shapes in this type's doc comment.
                guard let expectedEnd = calendar.date(byAdding: .day,
                                                     value: -1,
                                                     to: calendar.startOfDay(for: previous.start)),
                      calendar.startOfDay(for: answer.end) == expectedEnd else { break }
            }
            periods.append(MileagePeriod(index: index, start: answer.start, end: answer.end))
            guard let dayBefore = calendar.date(byAdding: .day,
                                                value: -1,
                                                to: calendar.startOfDay(for: answer.start)) else { break }
            probe = dayBefore
        }

        return periods
    }
}

// MARK: - The figures

/// What one bucket of trips is worth: miles, the two halves, and the money.
///
/// BOTH HALVES ARE ALWAYS PRESENT, including at zero. The old summary card drew
/// the split line only when company miles were greater than zero
/// (`MileageReportsView.swift:244`), which meant a period driven entirely in a
/// company car never stated that the PERSONAL half was the zero one — and the two
/// halves are reimbursed at different rates, so which half the miles fell in is
/// payroll, not trim.
struct MileageFigures: Equatable {
    let miles: Double
    let personalMiles: Double
    let companyMiles: Double
    let reimbursement: Double

    static let zero = MileageFigures(miles: 0, personalMiles: 0, companyMiles: 0, reimbursement: 0)

    init(miles: Double, personalMiles: Double, companyMiles: Double, reimbursement: Double) {
        self.miles = miles
        self.personalMiles = personalMiles
        self.companyMiles = companyMiles
        self.reimbursement = reimbursement
    }

    init(split: VehicleRates.Split) {
        self.miles = split.totalMiles
        self.personalMiles = split.personalMiles
        self.companyMiles = split.companyMiles
        self.reimbursement = split.totalCompensation
    }

    /// "Personal 132.4 mi · Company 18.0 mi" — unconditionally, both halves.
    var splitLine: String {
        let personal = "Personal \(MileageFigures.oneDecimal(personalMiles)) mi"
        let company = "Company \(MileageFigures.oneDecimal(companyMiles)) mi"
        // BOTH HALVES, ALWAYS. Dropping either one is the defect, not a tidy-up.
        return [personal, company].joined(separator: " · ")
    }

    /// "132.4 miles". One decimal everywhere, so the hero and the rows under it
    /// round the same way.
    var milesLine: String { "\(MileageFigures.oneDecimal(miles)) miles" }

    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// The money, in one place.
///
/// Everything here routes through `VehicleRates.Split.add` — the per-report
/// accumulator that ALREADY EXISTED IN THE APP AND HAD NO CALLERS
/// (`VehicleRates.swift:61-69`) while three screens hand-rolled their own bucket
/// arithmetic and disagreed about the answer.
enum MileageMath {

    /// Accumulate rows into personal/company buckets, one report at a time.
    static func accumulate<T>(_ rows: [T],
                              miles: (T) -> Double,
                              vehicleType: (T) -> String?,
                              personalRate: Double,
                              companyCarRate: Double?) -> VehicleRates.Split {
        var split = VehicleRates.Split()
        for row in rows {
            split.add(miles: miles(row),
                      vehicleType: vehicleType(row),
                      personalRate: personalRate,
                      companyCarRate: companyCarRate)
        }
        return split
    }

    /// Same accumulator, from bucket totals rather than rows — so a screen holding
    /// only "personal miles" and "company miles" still gets its money through the
    /// one code path, and re-derives it when a rate lands late.
    static func split(personalMiles: Double,
                      companyMiles: Double,
                      personalRate: Double,
                      companyCarRate: Double?) -> VehicleRates.Split {
        var split = VehicleRates.Split()
        split.add(miles: personalMiles, vehicleType: "personal",
                  personalRate: personalRate, companyCarRate: companyCarRate)
        split.add(miles: companyMiles, vehicleType: "company",
                  personalRate: personalRate, companyCarRate: companyCarRate)
        return split
    }

    /// One trip's money, at the rate ITS vehicle type pays.
    static func amount(miles: Double,
                       vehicleType: String?,
                       personalRate: Double,
                       companyCarRate: Double?) -> Double {
        miles * VehicleRates.rate(forVehicleType: vehicleType,
                                  personalRate: personalRate,
                                  companyCarRate: companyCarRate)
    }

    /// THE CALENDAR THE STORED DAY IS READ IN, and the single convention for every
    /// date on these screens.
    ///
    /// `daily_job_reports.date` is "the day the report is about". iOS writes it as a
    /// bare day, which the column carries as midnight UTC and PostgREST returns as
    /// "2026-08-01T00:00:00+00:00" — so the day a report is FOR is the UTC component
    /// of the decoded instant, never the local one. Reading it with
    /// `Calendar.current` in any western zone shifts every report back a day: a trip
    /// filed on the 1st of August rendered "Fri 31", fell out of August's tile and
    /// out of the year total at the January boundary, and Mileage disagreed with
    /// Statistics about the same row — Stats already parses the stored day off the
    /// string (`StatsDay`, StatsRules.swift) and got it right.
    ///
    /// It is a fixed-offset UTC calendar rather than the device's, and gregorian
    /// rather than the device's calendar identifier, because the stored value is not
    /// a local wall clock and not a locale question.
    static let storedDayCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    /// The month tile counts the CALENDAR month of `reference`, both month and year
    /// — a month test without a year folds last July into this one.
    ///
    /// TWO CALENDARS, DELIBERATELY, and this is the same pairing Stats ships
    /// (`StatsWindow` is built from `StatsDay(date: reference, calendar: .current)`
    /// while the reports it buckets carry days parsed out of the stored string).
    /// The report's day is a STORED day, so it is read in UTC; "this month" is a
    /// question about the reader's own calendar, so the reference is read locally.
    /// Reading both in one calendar is wrong whichever one is picked — locally the
    /// stored day shifts, in UTC the reader's "this month" flips over an evening.
    static func isInSameMonth(_ date: Date,
                              as reference: Date,
                              referenceCalendar: Calendar = .current) -> Bool {
        let stored = storedDayCalendar.dateComponents([.year, .month], from: date)
        let now = referenceCalendar.dateComponents([.year, .month], from: reference)
        return stored.month == now.month && stored.year == now.year
    }

    static func isInSameYear(_ date: Date,
                             as reference: Date,
                             referenceCalendar: Calendar = .current) -> Bool {
        storedDayCalendar.component(.year, from: date)
            == referenceCalendar.component(.year, from: reference)
    }
}

// MARK: - The vehicle, across storage and screen

/// A report's `vehicle_type`, as a type rather than a bare string.
///
/// ANYTHING THAT IS NOT LITERALLY "company" IS PERSONAL — NULL on pre-CAR rows,
/// an empty string, a typo. That is `VehicleRates.isCompany`'s rule and it is
/// mirrored here rather than re-decided, because the money already depends on it.
enum MileageVehicle: String, Equatable, CaseIterable {
    case personal
    case company

    /// The two options on the edit form's choice row, in this order.
    static let choiceLabels = ["Personal", "Company"]

    static func from(storage: String?) -> MileageVehicle {
        VehicleRates.isCompany(storage) ? .company : .personal
    }

    /// Nil for a label the form does not offer, so a caller cannot silently get
    /// "personal" out of a typo.
    static func from(choiceLabel: String) -> MileageVehicle? {
        switch choiceLabel {
        case "Personal": return .personal
        case "Company":  return .company
        default:         return nil
        }
    }

    /// What goes in the column.
    var storageValue: String { rawValue }

    /// The choice row's label.
    var choiceLabel: String { self == .company ? "Company" : "Personal" }

    /// The badge on the detail hero. PERSONAL IS BADGED TOO: the old screen drew
    /// an orange "Company car" line and NOTHING AT ALL for a personal trip, so the
    /// absence of a mark was the only signal that a trip was in your own car —
    /// unreadable next to a trip whose badge simply had not been noticed.
    var badgeLabel: String { self == .company ? "Company" : "Personal" }

    /// The read-mode row.
    var readLabel: String { self == .company ? "Company car" : "Personal car" }
}

// MARK: - The edit

/// What the detail screen's Save does before it writes.
///
/// The two messages are the app's own, preserved: "Please select a school." shipped
/// verbatim, and the invalid-number case replaces "Invalid mileage value. Please
/// enter a number." with the same sentence in the mockup's wording. Both are now
/// drawn INLINE next to the field instead of in one of two stacked `.alert`
/// modifiers, which is the shape that could swallow the other.
enum MileageEditValidation: Equatable {
    case valid(school: String, vehicle: MileageVehicle, miles: Double)
    case missingSchool
    case invalidMiles

    /// SCHOOL IS CHECKED FIRST, as it is in the approved design's `save()`. Order
    /// matters when both are wrong: a blank form should be told to pick a school
    /// rather than to fix a number it has not been given.
    static func evaluate(school: String, vehicle: MileageVehicle, milesText: String) -> MileageEditValidation {
        let trimmedSchool = school.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSchool.isEmpty else { return .missingSchool }
        let trimmedMiles = milesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let miles = Double(trimmedMiles), miles.isFinite, miles >= 0 else {
            return .invalidMiles
        }
        return .valid(school: trimmedSchool, vehicle: vehicle, miles: miles)
    }

    var message: String? {
        switch self {
        case .valid:         return nil
        case .missingSchool: return "Please select a school."
        case .invalidMiles:  return "Please enter a number for the miles driven."
        }
    }

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

// MARK: - The school list, as a state rather than an absence

/// Whether the org's schools are on their way, here, absent, or unreachable.
///
/// THE DEAD END THIS REPLACES: the edit form tested `schoolOptions.isEmpty` and
/// rendered "Loading schools..." whenever it was true. An organisation with ZERO
/// schools therefore showed a spinner caption forever, next to a validation
/// message ("Please select a school.") that could never be satisfied — and a
/// FAILED load looked exactly the same. Three different situations, one wrong
/// screen.
enum MileageSchoolsState: Equatable {
    case loading
    case ready
    /// The org genuinely has no schools. Not a failure, and not a spinner.
    case empty
    case failed(String)

    /// The list is only pickable in `.ready`.
    var allowsPicking: Bool { self == .ready }

    var message: String? {
        switch self {
        case .loading:            return "Loading schools…"
        case .ready:              return nil
        case .empty:              return "No schools on your organization yet."
        case .failed(let reason): return reason
        }
    }
}
