//  StatsMockup.swift
//  Iconik Employee — AMB.9's Statistics mockup, built in batch 3
//
//  ARC SCAFFOLDING. Deleted at AMB.9's close.
//
//  REPOINTED 2026-07-29, when the operator approved this design AND the query
//  repair it needs. Every chart, card and state below now comes from
//  `Stats/StatsKit.swift` — the production views the real screen draws — and every
//  number comes from `Stats/StatsRules.swift`'s `StatsAggregate`. The mockup's own
//  145-line copies of the bar, the monthly chart and the five sections are
//  DELETED, not left beside them. Only the sample values are private to this file.
//
//  That direction is the mechanism: there is no second copy of the design, so the
//  lab and the shipped screen cannot drift. It is the same arrangement TimeOffKit
//  established in AMB.8, for the same reason.
//
//  THE FINDING THAT DROVE THE REDESIGN (AMB_BATCH3_PARITY.md §0)
//      The live Statistics screen never rendered. Its queries named columns that
//      DO NOT EXIST — `daily_job_reports.start_time` and `.end_time`,
//      `schools.value` and `.type`, all four proved absent by live query — so two
//      of five fetches failed and one failure replaced the ENTIRE tab area with
//      "Error Loading Data". Observed on a signed-in simulator 2026-07-29.
//
//      Underneath that: a hardcoded "Weather Impact" table (930 invented jobs), a
//      doubled mileage accumulator making every total 2× actual, a trends chart
//      that answered only the names John, Sarah and Mike, an "Average Job Time"
//      pinned to a literal 3.0 hours, and monthly buckets with no year in the key.
//      All of it is gone; none of it was restyled.

import SwiftUI

// MARK: - Lab state

private enum StatsLabState: String, CaseIterable, Identifiable {
    case populated = "Populated"
    case loading = "Loading"
    case emptyPeriod = "Empty"
    case error = "Error"

    var id: String { rawValue }
}

// MARK: - Root

struct StatsMockup: View {
    /// Read by `DesignLabView` for the lab's own chrome. It is the PRODUCTION
    /// tint now, not a hex restated beside it.
    static let featureTint = StatsStyle.tint

    @State private var state: StatsLabState = .populated
    @State private var period: StatsPeriod = .year

    private var data: StatsAggregate { StatsSample.aggregate(for: period) }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: StatsStyle.tint, intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    labControl
                    StatsPeriodChips(period: $period, reference: StatsSample.reference)

                    switch state {
                    case .populated:
                        StatsOverviewSection(aggregate: data)
                        StatsMileageSection(aggregate: data)
                        StatsLocationsSection(aggregate: data)
                        StatsPhotographersSection(aggregate: data)
                        StatsJobTypesSection(aggregate: data)
                    case .loading:
                        StatsLoadingState(spanLabel: data.spanLabel)
                    case .emptyPeriod:
                        StatsEmptyPeriodState(periodLabel: data.periodLabel)
                    case .error:
                        StatsErrorState(message: "One of the queries didn't answer. Nothing is wrong with your reports.") {
                            withAnimation(AmbientMotion.gentle) { state = .populated }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · state", trailing: "not a design element")
            Picker("State", selection: $state) {
                ForEach(StatsLabState.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Sample data

/// Sample values only. The TYPES are production types and the totals are their
/// computed properties, so the overview tiles here are sums of these rows for the
/// same reason they are on the real screen.
private enum StatsSample {

    /// A FIXED reference date, so the lab's chips read "July / Q3 / 2026" and its
    /// spans read the same on any day someone opens it. The real screen passes
    /// `Date()`.
    static let reference: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 15
        components.hour = 12
        return Calendar.current.date(from: components) ?? Date()
    }()

    static func aggregate(for period: StatsPeriod) -> StatsAggregate {
        switch period {
        case .year: return year
        case .quarter: return quarter
        case .month: return month
        }
    }

    /// Six photographers, so the old three-name cap is visibly dead — and TWO of
    /// them are called Chris, the roster defect the parity doc records: the old
    /// list was keyed on `first_name` alone, so two employees with one first name
    /// merged into a single row. Here they are two rows because the aggregation
    /// keys on `user_id`.
    private static func person(_ name: String, trips: Int, personal: Double,
                              company: Double = 0, rate: Double = 0.67) -> StatsPhotographer {
        StatsPhotographer(key: name.lowercased(),
                          name: name,
                          trips: trips,
                          personalMiles: personal,
                          companyMiles: company,
                          reimbursement: personal * rate + company * 0.15)
    }

    private static func jobType(_ name: String, _ count: Int, of total: Int) -> StatsJobType {
        StatsJobType(name: name, count: count, percent: StatsAggregator.percent(count, of: total))
    }

    private static let yearPeople = [
        person("Maria", trips: 22, personal: 378.4, rate: 0.72),
        person("Chris A", trips: 20, personal: 351.6),
        person("Chris N", trips: 16, personal: 231.2, company: 45.0),
        person("Priya", trips: 15, personal: 243.8, rate: 0.60),
        person("Tom", trips: 11, personal: 182.4),
        person("Alex", trips: 8, personal: 141.8)
    ]

    private static let monthPeople = [
        person("Maria", trips: 4, personal: 68.4, rate: 0.72),
        person("Chris A", trips: 3, personal: 57.2),
        person("Chris N", trips: 3, personal: 30.0, company: 14.0),
        person("Priya", trips: 2, personal: 38.6, rate: 0.60),
        person("Tom", trips: 2, personal: 30.2),
        person("Alex", trips: 1, personal: 24.2)
    ]

    private static let yearPlaces = [
        StatsDestination(name: "Westfield Consolidated High School", visits: 20, miles: 369.6),
        StatsDestination(name: "Northgate Elementary", visits: 17, miles: 264.8),
        StatsDestination(name: "St. Bartholomew Academy", visits: 14, miles: 239.2),
        StatsDestination(name: "Riverbend Middle School", visits: 12, miles: 196.4),
        StatsDestination(name: "Oakmont Prep", visits: 10, miles: 167.0),
        StatsDestination(name: "Lakeshore Charter", visits: 8, miles: 135.6),
        StatsDestination(name: "Pinehurst Elementary", visits: 6, miles: 111.4),
        StatsDestination(name: "Cedar Valley Day School", visits: 5, miles: 90.2)
    ]

    private static let monthPlaces = [
        StatsDestination(name: "Westfield Consolidated High School", visits: 4, miles: 82.4),
        StatsDestination(name: "Northgate Elementary", visits: 4, miles: 66.2),
        StatsDestination(name: "St. Bartholomew Academy", visits: 3, miles: 51.0),
        StatsDestination(name: "Riverbend Middle School", visits: 2, miles: 36.8),
        StatsDestination(name: "Oakmont Prep", visits: 2, miles: 26.2)
    ]

    private static let yearJobTypes: [StatsJobType] = {
        let counts = [("Fall Portraits", 26), ("Sports — Team", 20), ("Graduation", 15),
                      ("Yearbook Groups", 13), ("Underclass Retakes", 11), ("Event Coverage", 7)]
        let total = counts.reduce(0) { $0 + $1.1 }
        return counts.map { jobType($0.0, $0.1, of: total) }
    }()

    private static let monthJobTypes: [StatsJobType] = {
        let counts = [("Fall Portraits", 5), ("Sports — Team", 4), ("Graduation", 2),
                      ("Yearbook Groups", 2), ("Underclass Retakes", 1), ("Event Coverage", 1)]
        let total = counts.reduce(0) { $0 + $1.1 }
        return counts.map { jobType($0.0, $0.1, of: total) }
    }()

    /// Two dimmed bars from the months BEFORE the period, then the period's own —
    /// chronological, year-labelled, and crossing the year boundary in the year
    /// case, which a year-less bucket key could not survive.
    private static let yearMonths = [
        StatsMonthBucket(year: 2025, month: 11, miles: 126.8, isComparison: true),
        StatsMonthBucket(year: 2025, month: 12, miles: 142.0, isComparison: true),
        StatsMonthBucket(year: 2026, month: 1, miles: 168.4, isComparison: false),
        StatsMonthBucket(year: 2026, month: 2, miles: 151.8, isComparison: false),
        StatsMonthBucket(year: 2026, month: 3, miles: 205.6, isComparison: false),
        StatsMonthBucket(year: 2026, month: 4, miles: 233.0, isComparison: false),
        StatsMonthBucket(year: 2026, month: 5, miles: 264.2, isComparison: false),
        StatsMonthBucket(year: 2026, month: 6, miles: 288.6, isComparison: false),
        StatsMonthBucket(year: 2026, month: 7, miles: 262.6, isComparison: false)
    ]

    private static let shortMonths = [
        StatsMonthBucket(year: 2026, month: 5, miles: 264.2, isComparison: true),
        StatsMonthBucket(year: 2026, month: 6, miles: 288.6, isComparison: true),
        StatsMonthBucket(year: 2026, month: 7, miles: 262.6, isComparison: false)
    ]

    private static let year = build(.year, people: yearPeople, places: yearPlaces,
                                   jobTypes: yearJobTypes, months: yearMonths)
    private static let quarter = build(.quarter, people: monthPeople, places: monthPlaces,
                                       jobTypes: monthJobTypes, months: shortMonths)
    private static let month = build(.month, people: monthPeople, places: monthPlaces,
                                     jobTypes: monthJobTypes, months: shortMonths)

    /// The label and the span come from the REAL period type, so the lab cannot
    /// claim a span the production window would not produce.
    private static func build(_ period: StatsPeriod,
                              people: [StatsPhotographer],
                              places: [StatsDestination],
                              jobTypes: [StatsJobType],
                              months: [StatsMonthBucket]) -> StatsAggregate {
        return StatsAggregate(period: period,
                              periodLabel: period.label(reference: reference),
                              spanLabel: period.window(reference: reference).spanLabel,
                              months: months,
                              photographers: people,
                              destinations: places,
                              jobTypes: jobTypes)
    }
}
