//  StatsRules.swift
//  Iconik Employee — the Statistics domain rules, as compiled types
//
//  PRODUCTION CODE, COMPILED AND RUN BY `scripts/test_stats_rules.sh`.
//
//  WHY THIS FILE EXISTS
//      Every number on the Statistics screen was computed inside a 566-line
//      ObservableObject, in four separate fetch closures, from columns that do
//      not exist. Nothing about it could be checked without a device and a
//      manager account — and when it was finally opened on one (2026-07-29) the
//      screen did not render at all. The arithmetic that survived the query
//      failure was wrong in five separate ways (AMB_BATCH3_PARITY.md §0):
//      totals doubled, buckets keyed without a year, trips counted as
//      job-description entries, a hardcoded 3.0-hour job time, and a fabricated
//      weather table.
//
//      So the arithmetic moved here, into SwiftUI-free value types that a shell
//      script compiles and RUNS. The test does not reimplement any of this in
//      another language — that mistake was made once on this arc and the
//      operator's verdict was that the logic was fake. The script compiles THIS
//      file, from this path, alongside the REAL VehicleRates.swift.
//
//  NO SwiftUI IMPORT. Deliberate and load-bearing: `swiftc` compiles this
//  standalone. Anything needing a Color or a View belongs in StatsKit.swift.
//
//  THE ONE DEVIATION FROM THE OLD CODE WORTH READING TWICE — see `StatsDay`.
//  Reports are bucketed by the DAY THE REPORT IS FOR, parsed straight out of
//  the stored string, never by re-interpreting an instant in the device's time
//  zone. That re-interpretation is the boundary defect the parity inventory
//  names (§4: "UTC filter instants vs local bucketing → boundary reports land in
//  the wrong bucket"), and it cannot be fixed by being careful — only by not
//  having a time zone in the arithmetic at all.

import Foundation

// MARK: - A day, as the column stores it

/// The calendar day a daily job report is FOR.
///
/// `daily_job_reports.date` is a `timestamp with time zone` used as a day: the
/// value PostgREST returns is rendered in UTC ("2026-07-15T00:00:00+00:00"), and
/// the day is the first ten characters of it. Parsing those ten characters is the
/// whole of this type.
///
/// The alternative — decode to a `Date` and read `Calendar.current.component(.month,
/// …)` — shifts every midnight-UTC report back a day in any western time zone, so
/// the 1st of a month lands in the previous month's bar and in the previous
/// period's totals. That is what the old screen did.
///
/// It is also why `Date` never appears in the aggregation below: there is no
/// instant here to get wrong.
struct StatsDay: Comparable, Hashable {
    let year: Int
    let month: Int
    let day: Int

    /// THE ONE RESIDUAL, NAMED RATHER THAN FIXED HERE: 177 of the live rows were
    /// written by the WEB app and carry a real evening instant rather than a bare day
    /// (verified 2026-07-29). Under this convention — the day is the UTC prefix — such
    /// a row buckets a day LATE, because 8pm local on the 15th is the 16th in UTC.
    /// Re-interpreting the instant locally instead would be worse: it would move all
    /// ~2,300 iOS-written rows (which are correct as stored) to fix 177. The fix is on
    /// the WRITE side — the web app should store the bare local day the way iOS does —
    /// which is another repo and another phase (AMB_BATCH3_PARITY.md §6).
    ///
    /// Parses the leading "yyyy-MM-dd" of ANY of the three forms the column has
    /// been observed to produce: a bare day, a whole-second timestamp, and a
    /// fractional-second timestamp. A decoder that handles one form and throws on
    /// the others empties the entire fetch, which this app has paid for twice
    /// (JobBox.timestamp, Session.created_at).
    init?(stored raw: String?) {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 10 else { return nil }
        let parts = text.prefix(10).split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.year = y
        self.month = m
        self.day = d
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Today, in the device's calendar — the only place a time zone belongs,
    /// because "today" is a local question.
    init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 1970
        self.month = c.month ?? 1
        self.day = c.day ?? 1
    }

    /// "2026-07-15" — what the date filter sends and what the visit key uses.
    var storageString: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Sortable and comparable as one number, which is what makes a month bucket
    /// impossible to key without its year.
    var monthKey: Int { year * 100 + month }
    var sortKey: Int { year * 10_000 + month * 100 + day }

    static func < (a: StatsDay, b: StatsDay) -> Bool { a.sortKey < b.sortKey }
}

// MARK: - Month names

/// POSIX month names, not a device-locale `DateFormatter`.
///
/// A bar label and a chip label are compared against expected strings by the
/// test harness, and a formatter that reads the device locale makes that test a
/// property of whoever runs it. The app is English-only in practice; the display
/// formatters in `Formatters` stay device-locale for everything a person types.
enum StatsMonthNames {
    static let abbreviated = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let full = ["January", "February", "March", "April", "May", "June",
                       "July", "August", "September", "October", "November", "December"]

    static func abbreviation(_ month: Int) -> String {
        guard (1...12).contains(month) else { return "—" }
        return abbreviated[month - 1]
    }

    static func name(_ month: Int) -> String {
        guard (1...12).contains(month) else { return "—" }
        return full[month - 1]
    }
}

// MARK: - The period

/// Month, quarter, year — REAL CALENDAR PERIODS.
///
/// The old picker said "Month / Quarter / Year" and meant the trailing 31, 92 or
/// 365 days from the instant you opened the screen (`StatsViewModel:548-565`), so
/// "Month" in mid-July was half of June. The chips are labelled with the
/// period's NAME here — "July", "Q3", "2026" — which is only honest if the
/// window really is that period, so the label and the boundary are computed by
/// the same type.
enum StatsPeriod: String, CaseIterable, Identifiable {
    case month
    case quarter
    case year

    var id: String { rawValue }

    /// "July" / "Q3" / "2026".
    func label(reference: Date, calendar: Calendar = .current) -> String {
        let today = StatsDay(date: reference, calendar: calendar)
        switch self {
        case .month: return StatsMonthNames.name(today.month)
        case .quarter: return "Q\(Self.quarterNumber(ofMonth: today.month))"
        case .year: return "\(today.year)"
        }
    }

    func window(reference: Date, calendar: Calendar = .current) -> StatsWindow {
        StatsWindow(period: self, today: StatsDay(date: reference, calendar: calendar))
    }

    static func quarterNumber(ofMonth month: Int) -> Int { (month - 1) / 3 + 1 }
}

/// The period's real boundaries, plus the two months of context the approved
/// design draws dimmed beside it.
///
/// All four boundaries are DAYS, inclusive of `firstDay` and `lastDay`. There is
/// no "end exclusive at midnight" instant to be off by one about.
struct StatsWindow: Equatable {
    let period: StatsPeriod
    /// Today, as the screen was opened. The bars never run past this month —
    /// drawing empty bars for months that have not happened would present the
    /// rest of a quarter as a run of zeroes.
    let today: StatsDay
    let firstDay: StatsDay
    let lastDay: StatsDay
    /// Two months before `firstDay`. The dimmed context bars start here, and so
    /// does the fetch — one query serves both.
    let contextFirstDay: StatsDay

    init(period: StatsPeriod, today: StatsDay) {
        self.period = period
        self.today = today

        let firstMonth: Int
        let monthSpan: Int
        switch period {
        case .month:
            firstMonth = today.month
            monthSpan = 1
        case .quarter:
            firstMonth = (StatsPeriod.quarterNumber(ofMonth: today.month) - 1) * 3 + 1
            monthSpan = 3
        case .year:
            firstMonth = 1
            monthSpan = 12
        }

        let first = StatsDay(year: today.year, month: firstMonth, day: 1)
        let lastMonth = StatsWindow.month(first.year, first.month, offsetBy: monthSpan - 1)
        self.firstDay = first
        self.lastDay = StatsDay(year: lastMonth.year, month: lastMonth.month,
                                day: StatsWindow.daysInMonth(year: lastMonth.year, month: lastMonth.month))
        let context = StatsWindow.month(first.year, first.month, offsetBy: -2)
        self.contextFirstDay = StatsDay(year: context.year, month: context.month, day: 1)
    }

    /// Inside the selected period. Everything in the sections and every total is
    /// gated on this.
    func contains(_ day: StatsDay) -> Bool { day >= firstDay && day <= lastDay }

    /// Anything the one fetch should return.
    func isFetched(_ day: StatsDay) -> Bool { day >= contextFirstDay && day <= lastDay }

    /// "2026-05-01" — the `gte` bound of the single query.
    var queryFirstDayString: String { contextFirstDay.storageString }
    /// "2026-08-01" — the EXCLUSIVE `lt` bound, so the last day of the period is
    /// included whatever time of day its timestamp carries.
    var queryEndExclusiveString: String {
        let next = StatsWindow.month(lastDay.year, lastDay.month, offsetBy: 1)
        return StatsDay(year: next.year, month: next.month, day: 1).storageString
    }

    /// "Jul 1 – Sep 30, 2026", with "· to date" while the period is still running
    /// — the old screen presented one month of a quarter as a quarter.
    ///
    /// One year is enough: all three periods are contained in the reference's
    /// calendar year, so there is no cross-year span to spell out (and no dead
    /// branch pretending otherwise).
    var spanLabel: String {
        let start = "\(StatsMonthNames.abbreviation(firstDay.month)) \(firstDay.day)"
        let end = "\(StatsMonthNames.abbreviation(lastDay.month)) \(lastDay.day)"
        let base = "\(start) – \(end), \(lastDay.year)"
        return today < lastDay ? "\(base) · to date" : base
    }

    // MARK: month arithmetic

    /// Month stepping done on integers. `Calendar.date(byAdding:)` would need a
    /// concrete instant, which is the thing this file refuses to hold.
    static func month(_ year: Int, _ month: Int, offsetBy offset: Int) -> (year: Int, month: Int) {
        let zeroBased = year * 12 + (month - 1) + offset
        return (zeroBased / 12, zeroBased % 12 + 1)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeap(year) ? 29 : 28
        default: return 30
        }
    }

    static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

// MARK: - What comes out of the fetch

/// One `daily_job_reports` row, reduced to the eight columns that exist.
///
/// `start_time` and `end_time` are ABSENT from the table (proved by live query
/// 2026-07-29) and are absent from this type, which is why no average-job-time
/// figure can be computed or accidentally faked into 3.0 hours.
struct StatsReport {
    let userId: String?
    let yourName: String?
    let day: StatsDay?
    let miles: Double
    let vehicleType: String?
    let destination: String?
    let jobDescriptions: [String]

    init(userId: String? = nil,
         yourName: String? = nil,
         day: StatsDay?,
         miles: Double = 0,
         vehicleType: String? = nil,
         destination: String? = nil,
         jobDescriptions: [String] = []) {
        self.userId = userId
        self.yourName = yourName
        self.day = day
        self.miles = miles
        self.vehicleType = vehicleType
        self.destination = destination
        self.jobDescriptions = jobDescriptions
    }
}

/// One `users` row: id, first_name, amount_per_mile — the three columns the
/// manager mileage screen already selects.
struct StatsPersonRecord {
    let id: String
    let firstName: String?
    let amountPerMile: Double?

    init(id: String, firstName: String? = nil, amountPerMile: Double? = nil) {
        self.id = id
        self.firstName = firstName
        self.amountPerMile = amountPerMile
    }
}

// MARK: - What the screen draws

/// One month's miles.
///
/// KEYED BY YEAR AND MONTH. The old buckets were keyed by the month NAME
/// (`StatsViewModel:221-263`), so a window spanning a year boundary summed two
/// Decembers into one bar and then sorted the bars Jan→Dec — out of chronological
/// order for any window that crosses New Year.
struct StatsMonthBucket: Identifiable, Equatable {
    let year: Int
    let month: Int
    let miles: Double
    /// Outside the selected period: drawn dimmed, in no total.
    let isComparison: Bool

    var id: Int { year * 100 + month }
    var monthLabel: String { StatsMonthNames.abbreviation(month) }
    var yearLabel: String { "\(year)" }
}

/// One photographer's period.
///
/// IDENTIFIED BY `user_id` WHEN THERE IS ONE. The old roster was keyed on
/// `users.first_name` alone, so two employees called Chris merged into one row
/// and a renamed employee orphaned their own history.
struct StatsPhotographer: Identifiable, Equatable {
    /// `user_id` lowercased when present, else the name, else the unattributed
    /// sentinel. Never shown.
    let key: String
    /// What the row says: the `users.first_name` for that id, falling back to
    /// the name the report itself carries.
    let name: String
    /// COUNT OF REPORTS. A report with no mileage is still a trip.
    let trips: Int
    let personalMiles: Double
    let companyMiles: Double
    /// personal × that user's own `amount_per_mile`, company × the org rate —
    /// the same rule Manager Mileage uses, through the same `VehicleRates`.
    let reimbursement: Double

    var id: String { key }
    var miles: Double { personalMiles + companyMiles }
}

/// One destination, and how often it was visited.
struct StatsDestination: Identifiable, Equatable {
    let name: String
    /// ONE PER DESTINATION PER DAY — a report filed twice for one school on one
    /// day is one visit. The old screen's rule, kept.
    let visits: Int
    let miles: Double

    var id: String { name.lowercased() }
}

/// One job description, and its share of all of them.
struct StatsJobType: Identifiable, Equatable {
    let name: String
    let count: Int
    /// Whole percent of all job-description entries in the period, rounded.
    /// Guarded: a period with no entries yields 0, not a division by zero.
    let percent: Int

    var id: String { name.lowercased() }
}

/// Everything the screen shows, for one period.
///
/// THE TOTALS ARE COMPUTED FROM THE PARTS. Nothing here is accumulated a second
/// time alongside the sections, which is exactly how every mileage figure on the
/// live screen came to be 2× actual (`StatsViewModel:239-245` adds to the total
/// bucket in a branch and again unconditionally on the next line). An overview
/// tile cannot contradict the section under it if it is the sum of that section.
struct StatsAggregate: Equatable {
    let period: StatsPeriod
    /// "July" / "Q3" / "2026".
    let periodLabel: String
    /// "Jul 1 – Sep 30, 2026 · to date".
    let spanLabel: String
    /// Chronological, context months first.
    let months: [StatsMonthBucket]
    /// Miles descending.
    let photographers: [StatsPhotographer]
    /// Visits descending.
    let destinations: [StatsDestination]
    /// Count descending.
    let jobTypes: [StatsJobType]

    // THE FIVE DERIVED FIGURES ARE COMPUTED ONCE, IN THE INITIALISER, and stored.
    //
    // They were computed properties, and each one is a reduce or a sort over the whole
    // period: `totalMiles` is read by an overview tile AND by the Mileage section's
    // title, `photographersByTrips` sorts the roster inside a `ForEach`, and SwiftUI
    // re-evaluates all of it on every body pass. Deriving them here keeps the property
    // this aggregate exists to hold — a total is the sum of the section under it,
    // never a second accumulation — while paying for it once per load.
    let totalMiles: Double
    let totalTrips: Int
    let totalReimbursement: Double
    /// Trips descending — the Photographers section's order, named rather than left
    /// as a `.sorted` in a view body.
    let photographersByTrips: [StatsPhotographer]
    let topDestinations: [StatsDestination]

    var photographerCount: Int { photographers.count }
    var schoolsVisited: Int { destinations.count }

    /// DERIVED, NOT PASSED IN. A memberwise initialiser taking the five totals would
    /// let a caller hand in figures that disagree with the sections — the exact defect
    /// this type was built to make impossible (the live screen's totals were 2× the
    /// sections because they were accumulated separately). Both call sites — the
    /// aggregator and the lab's sample builder — supply only the parts.
    init(period: StatsPeriod,
         periodLabel: String,
         spanLabel: String,
         months: [StatsMonthBucket],
         photographers: [StatsPhotographer],
         destinations: [StatsDestination],
         jobTypes: [StatsJobType]) {
        self.period = period
        self.periodLabel = periodLabel
        self.spanLabel = spanLabel
        self.months = months
        self.photographers = photographers
        self.destinations = destinations
        self.jobTypes = jobTypes

        self.totalMiles = photographers.reduce(0) { $0 + $1.miles }
        self.totalTrips = photographers.reduce(0) { $0 + $1.trips }
        self.totalReimbursement = photographers.reduce(0) { $0 + $1.reimbursement }
        self.photographersByTrips = photographers.sorted {
            $0.trips != $1.trips ? $0.trips > $1.trips : $0.name.lowercased() < $1.name.lowercased()
        }
        self.topDestinations = Array(destinations.prefix(5))
    }

    /// The bars inside the period, summed. Equal to `totalMiles` by construction
    /// — asserted by the test suite, because "the chart and the tile disagree" is
    /// the failure this screen shipped.
    var inPeriodBarMiles: Double {
        months.filter { !$0.isComparison }.reduce(0) { $0 + $1.miles }
    }

    /// No reports filed in the period. NOT an error — the old screen raised it
    /// through the error path and replaced the whole screen with "No data
    /// available for the selected time period".
    var isEmpty: Bool { totalTrips == 0 }
}

// MARK: - The aggregation

enum StatsAggregator {

    /// The unattributed bucket. A report with neither a `user_id` nor a name
    /// still carries miles and is still a trip, so it gets a row rather than
    /// being dropped — dropping it would make the overview tiles disagree with
    /// the sum of the sections, which is the property this file exists to hold.
    static let unattributedKey = "·unattributed"
    static let unattributedName = "Unattributed"

    static func aggregate(reports: [StatsReport],
                          people: [StatsPersonRecord],
                          companyCarRate: Double?,
                          period: StatsPeriod,
                          reference: Date = Date(),
                          calendar: Calendar = .current) -> StatsAggregate {
        let window = period.window(reference: reference, calendar: calendar)

        // users, by lowercased id — the repo's lowercase-UUID rule.
        var peopleById: [String: StatsPersonRecord] = [:]
        for person in people { peopleById[person.id.lowercased()] = person }

        var milesByMonth: [Int: Double] = [:]
        var crews: [String: CrewAccumulator] = [:]
        var places: [String: PlaceAccumulator] = [:]
        var jobCounts: [String: (name: String, count: Int)] = [:]
        var jobEntryTotal = 0
        var visitKeys = Set<String>()

        for report in reports {
            // An undated row cannot be placed in a period at all. It is skipped
            // rather than defaulted to today, which is the substitution that
            // stamps wrong dates on Class Groups jobs elsewhere in the app.
            guard let day = report.day else { continue }
            guard window.isFetched(day) else { continue }

            let inPeriod = window.contains(day)

            // MONTH BARS cover the context months too — that is what the fetch
            // reaches back for — so this accumulates outside the period gate.
            milesByMonth[day.monthKey, default: 0] += report.miles

            guard inPeriod else { continue }

            // PHOTOGRAPHER
            let key = crewKey(for: report)
            let person = report.userId.flatMap { peopleById[$0.lowercased()] }
            var crew = crews[key] ?? CrewAccumulator(name: displayName(for: report, person: person))
            crew.trips += 1
            crew.split.add(miles: report.miles,
                           vehicleType: report.vehicleType,
                           personalRate: VehicleRates.resolvePersonalRate(person?.amountPerMile),
                           companyCarRate: companyCarRate)
            crews[key] = crew

            // DESTINATION
            if let destination = trimmed(report.destination) {
                let placeKey = destination.lowercased()
                var place = places[placeKey] ?? PlaceAccumulator(name: destination)
                place.miles += report.miles
                let visitKey = "\(placeKey)|\(day.storageString)"
                if !visitKeys.contains(visitKey) {
                    visitKeys.insert(visitKey)
                    place.visits += 1
                }
                places[placeKey] = place
            }

            // JOB TYPES
            for description in report.jobDescriptions {
                guard let name = trimmed(description) else { continue }
                let typeKey = name.lowercased()
                let existing = jobCounts[typeKey]
                jobCounts[typeKey] = (name: existing?.name ?? name, count: (existing?.count ?? 0) + 1)
                jobEntryTotal += 1
            }
        }

        return StatsAggregate(
            period: period,
            periodLabel: period.label(reference: reference, calendar: calendar),
            spanLabel: window.spanLabel,
            months: buckets(milesByMonth: milesByMonth, window: window),
            photographers: crews.map { key, crew in
                StatsPhotographer(key: key,
                                  name: crew.name,
                                  trips: crew.trips,
                                  personalMiles: crew.split.personalMiles,
                                  companyMiles: crew.split.companyMiles,
                                  reimbursement: crew.split.totalCompensation)
            }.sorted {
                $0.miles != $1.miles ? $0.miles > $1.miles : $0.name.lowercased() < $1.name.lowercased()
            },
            destinations: places.map { _, place in
                StatsDestination(name: place.name, visits: place.visits, miles: place.miles)
            }.sorted {
                if $0.visits != $1.visits { return $0.visits > $1.visits }
                if $0.miles != $1.miles { return $0.miles > $1.miles }
                return $0.name.lowercased() < $1.name.lowercased()
            },
            jobTypes: jobCounts.map { _, entry in
                StatsJobType(name: entry.name,
                             count: entry.count,
                             percent: percent(entry.count, of: jobEntryTotal))
            }.sorted {
                $0.count != $1.count ? $0.count > $1.count : $0.name.lowercased() < $1.name.lowercased()
            })
    }

    /// Whole percent, guarded. `Int(Double.nan)` traps, so an unguarded division
    /// here is not a wrong label — it is a crash on an empty period.
    static func percent(_ count: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(count) / Double(total) * 100).rounded())
    }

    /// `user_id` first, the report's own name second, the sentinel last.
    static func crewKey(for report: StatsReport) -> String {
        if let id = trimmed(report.userId) { return id.lowercased() }
        if let name = trimmed(report.yourName) { return name.lowercased() }
        return unattributedKey
    }

    private static func displayName(for report: StatsReport, person: StatsPersonRecord?) -> String {
        if let first = trimmed(person?.firstName) { return first }
        if let name = trimmed(report.yourName) { return name }
        return unattributedName
    }

    /// Every month from the context start through the last month worth drawing —
    /// chronological, gap-filled, year-labelled.
    ///
    /// The last bar is the LATER of this month and the last month that has data,
    /// clamped to the period. That is what keeps `inPeriodBarMiles == totalMiles`
    /// true (no in-period month can hold miles the bars do not show) while still
    /// refusing to draw the rest of a quarter as a row of zeroes.
    private static func buckets(milesByMonth: [Int: Double], window: StatsWindow) -> [StatsMonthBucket] {
        let firstKey = window.firstDay.monthKey
        let lastKey = window.lastDay.monthKey
        let todayKey = min(max(window.today.monthKey, firstKey), lastKey)
        let lastDataKey = milesByMonth.filter { $0.value != 0 && $0.key >= firstKey && $0.key <= lastKey }
            .keys.max() ?? firstKey
        let stopKey = min(max(todayKey, lastDataKey), lastKey)

        var result: [StatsMonthBucket] = []
        var cursor = (year: window.contextFirstDay.year, month: window.contextFirstDay.month)
        while cursor.year * 100 + cursor.month <= stopKey {
            let key = cursor.year * 100 + cursor.month
            result.append(StatsMonthBucket(year: cursor.year,
                                           month: cursor.month,
                                           miles: milesByMonth[key] ?? 0,
                                           isComparison: key < firstKey))
            cursor = StatsWindow.month(cursor.year, cursor.month, offsetBy: 1)
        }
        return result
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private struct CrewAccumulator {
        let name: String
        var trips: Int = 0
        var split = VehicleRates.Split()
    }

    private struct PlaceAccumulator {
        let name: String
        var visits: Int = 0
        var miles: Double = 0
    }
}
