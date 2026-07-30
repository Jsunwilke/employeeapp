//  StatsMockup.swift
//  Iconik Employee — AMB.9's Statistics mockup, built in batch 3
//
//  ARC SCAFFOLDING. Deleted at AMB.9's close.
//
//  THE FINDING THAT DRIVES THIS REDESIGN (AMB_BATCH3_PARITY.md §0)
//      The live Statistics screen almost certainly never renders at all. Its
//      queries name columns that DO NOT EXIST — `daily_job_reports.start_time`
//      and `.end_time`, `schools.value` and `.type`, all four proved absent by a
//      live query against the shared project — so two of the five fetches fail,
//      and `StatsView.swift:23` replaces the ENTIRE tab area with "Error Loading
//      Data" even though the other three datasets loaded fine.
//
//      What is underneath that, once the queries are repaired:
//        · "Weather Impact on Jobs" is HARDCODED — five literal rows,
//          930 fabricated jobs, shown to every org with no caveat.
//        · Every total-mileage figure is 2× actual: the accumulator adds to the
//          "total" bucket in a branch AND again unconditionally on the next line.
//        · "Mileage Trends" draws flat zero lines in grey for every real org — the
//          data model answers only the literal names John, Sarah and Mike, and
//          the chart is hard-capped at three photographers.
//        · "Average Job Time" defaults to the literal 3.0 hours — and since the
//          timestamp columns do not exist, it would read 3.0 for every row even
//          if the query succeeded.
//        · Monthly buckets carry no YEAR in the key, so a trailing 12-month
//          window sums the same month from two years into one bar.
//
//  WHAT THIS MOCKUP IS
//      Statistics as it looks when every number is REAL. Every figure below is
//      computed from the sample parts — the overview tiles are sums of the section
//      rows, not typed-in numbers — because arithmetic honesty is an arc rule and
//      this screen has been failing it in production.
//
//      Making these numbers real means repairing the queries, which is a
//      data-layer decision for the operator, so the whole screen is implicitly
//      PROPOSED. That is said once, quietly, at the top rather than stamped on
//      every card.
//
//  WHAT THE DESIGN IS ARGUING
//      1. ONE SCROLL. The five-button tab strip is gone: nothing here is
//         secondary (the operator's ruling on the report form), and switching
//         tabs today does not even refetch — it only hides four fifths of the
//         answer.
//      2. CALENDAR PERIODS, HONESTLY LABELLED. Month/Quarter/Year silently mean
//         trailing 31 / 92 / 365 days from right now. The chips here name real
//         calendar periods and the section headings state the span.
//      3. NO FABRICATED DATA. The weather section is gone, and its absence is
//         stated rather than left to be noticed. "Average job time" is gone for
//         the same reason.
//      4. DETERMINISTIC PER-PHOTOGRAPHER COLOUR. `AmbientStyle.avatarColor(name)`
//         — the same person is the same colour on every screen, on every device,
//         for any number of photographers. No three-name cap, no grey fallback.
//
//  WHAT IS NOT BEING PROPOSED
//      No query, data-layer, permission or rate-rule change (D12). Statistics is
//      gated at the SECTION level in All Features and `featureView(for:)`
//      re-checks nothing — recorded in the parity doc, not fixed here.

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
    /// `FeatureTheme.color(for: "stats")` — the deliberately desaturated manager
    /// family. The live screen never applies it: Statistics has no wash at all.
    static let featureTint = Color(hex: "#7A7FA6")

    @State private var state: StatsLabState = .populated
    @State private var period: StatsPeriod = .year

    private var data: StatsDataset { StatsSample.dataset(for: period) }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    labControl
                    proposedBanner
                    periodChips

                    switch state {
                    case .populated:
                        overview
                        mileageSection
                        locationsSection
                        photographersSection
                        jobTypesSection
                        weatherFootnote
                    case .loading:
                        loadingState
                    case .emptyPeriod:
                        emptyState
                    case .error:
                        errorState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
    }

    // MARK: lab chrome

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · state", trailing: "not a design element")
            Picker("State", selection: $state) {
                ForEach(StatsLabState.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// Said ONCE. The alternative — a PROPOSED stamp on every card — would make
    /// the screen unreadable and would still not be more honest.
    private var proposedBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").font(.footnote.weight(.semibold))
            Text("Every figure below is drawn from data the app really has — shipping this requires repairing the stats queries.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .ambientCard(density: .compact,
                     border: .dashed(Color.primary.opacity(0.18)),
                     fillWidth: true)
    }

    // MARK: 1 — the period

    private var periodChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(StatsPeriod.allCases) { option in
                    periodChip(option)
                }
                Spacer(minLength: 0)
            }
            Text("Calendar periods · PROPOSED — today the picker says Month / Quarter / Year and silently means the trailing 31, 92 or 365 days from this instant.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func periodChip(_ option: StatsPeriod) -> some View {
        let selected = option == period
        return Button {
            withAnimation(AmbientMotion.snappy) { period = option }
            AmbientHaptics.selection()
        } label: {
            Text(option.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                // ambient-allow: a selection chip is a control, not a container.
                .background(Capsule().fill(selected
                                           ? AnyShapeStyle(Self.featureTint)
                                           : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 2 — overview

    /// Every tile is a SUM of the sections below it. Nothing here is typed in, so
    /// the screen cannot contradict itself the way a doubled accumulator does.
    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Overview", trailing: data.spanLabel)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    AmbientStatTile(value: Int(data.totalMiles.rounded()),
                                    label: "Miles",
                                    systemImage: "car.fill",
                                    tint: .blue)
                    AmbientStatTile(value: data.totalTrips,
                                    label: "Trips",
                                    systemImage: "briefcase.fill",
                                    tint: .green)
                }
                HStack(spacing: 10) {
                    AmbientStatTile(value: data.photographers.count,
                                    label: "Photographers",
                                    systemImage: "person.fill",
                                    tint: .orange)
                    AmbientStatTile(value: data.schools.count,
                                    label: "Schools visited",
                                    systemImage: "mappin.and.ellipse",
                                    tint: .red)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Trips are counted as reports, not job descriptions — a report listing three jobs is one trip.")
                Text("Schools visited counts only schools actually visited, not every school on the org's list.")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 3 — mileage

    private var mileageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("Mileage", trailing: StatsSample.miles(data.totalMiles))

            monthlyMilesCard
            byPhotographerCard
        }
    }

    /// Hand-built vertical bars — no `import Charts` at the iOS 16.6 floor. What
    /// the live charts lack and this has: a BASELINE, a value on every bar, and a
    /// label that carries the YEAR. The dimmed bars are the period before the one
    /// selected, drawn for contrast and excluded from every total — which is only
    /// safe to draw at all because these buckets are keyed by month AND year.
    private var monthlyMilesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Monthly miles").font(.subheadline.weight(.semibold))

            let maxValue = max(data.months.map(\.miles).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data.months) { bucket in
                    VStack(spacing: 4) {
                        Text("\(Int(bucket.miles.rounded()))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(bucket.isComparison ? .tertiary : .secondary)
                        Capsule()
                            .fill(bucket.isComparison
                                  ? AnyShapeStyle(Color.primary.opacity(0.14))
                                  : AnyShapeStyle(Self.featureTint.gradient))
                            .frame(height: max(4, 108 * bucket.miles / maxValue))
                        Text(bucket.monthLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(bucket.yearLabel)
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // The baseline. Every live chart on this screen is drawn without one,
            // which is why a 5pt floor had to be added so a zero still showed
            // something — a bar with no axis has to fake its own presence.
            Rectangle()
                .fill(Color.primary.opacity(0.18))
                .frame(height: 1)

            Text("Buckets carry the year, so December 2025 and December 2026 cannot merge into one bar. Dimmed bars sit outside the selected period and are in no total.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy, fill: .surface,
                     border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
    }

    private var byPhotographerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By photographer").font(.subheadline.weight(.semibold))

            let maxValue = max(data.photographers.map(\.miles).max() ?? 1, 1)
            VStack(spacing: 12) {
                ForEach(data.photographers) { person in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            AmbientAvatar(name: person.name, size: 24)
                            Text(person.name).font(.caption.weight(.semibold))
                            Spacer(minLength: 6)
                            Text(StatsSample.miles(person.miles))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        bar(value: person.miles, maxValue: maxValue,
                            tint: AmbientStyle.avatarColor(person.name))
                        // Reimbursement, in real money — the live bars label
                        // themselves "$<Int>", truncating every cent.
                        Text("\(StatsSample.money(person.reimbursement)) reimbursement")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Text("PROPOSED: one rate rule shared with the manager screen. Today three engines disagree — Statistics uses a flat $0.67 for everyone, the employee screen uses the signed-in user's rate, and Manager Mileage uses each employee's own.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy, fill: .surface,
                     border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
    }

    // MARK: 4 — locations

    /// ONE card with two metric columns, not three near-identical card sets. The
    /// live screen draws "Top Locations by Visits", "Locations by Mileage" and
    /// "Visit Efficiency" as three separate five-row bar charts over the same five
    /// schools — the same information, read three times.
    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Locations", trailing: "top 5 of \(data.schools.count)")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Top schools by visits").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 6)
                    Text("miles").font(.caption2).foregroundStyle(.tertiary)
                }

                let top = Array(data.schools.sorted { $0.visits > $1.visits }.prefix(5))
                let maxVisits = max(top.map(\.visits).max() ?? 1, 1)
                VStack(spacing: 10) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, school in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                Text(school.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text("\(school.visits) visits")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                // The second metric as a COLUMN, not a second card.
                                Text(StatsSample.miles(school.miles))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 62, alignment: .trailing)
                            }
                            bar(value: Double(school.visits), maxValue: Double(maxVisits),
                                tint: Self.featureTint)
                        }
                    }
                }

                Text("A visit is one school on one day. Free-text destinations that match no school are not counted as locations.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ambientCard(density: .roomy, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
        }
    }

    // MARK: 5 — photographers

    private var photographersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Photographers", trailing: "\(data.photographers.count)")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(data.photographers) { person in
                    HStack(spacing: 10) {
                        AmbientAvatar(name: person.name, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name).font(AmbientDensity.compact.titleFont)
                            Text("\(person.trips) trips")
                                .font(AmbientDensity.compact.subtitleFont)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text(StatsSample.miles(person.miles))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                }

                Divider()

                // The card that is deliberately NOT here.
                Text("Job duration isn't tracked anywhere, so it isn't drawn (the old card showed a hardcoded 3.0 hours).")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Six photographers, all drawn. The live trends chart is hard-capped at three and only knows the names John, Sarah and Mike; everyone else gets a grey flat line at zero.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ambientCard(density: .roomy, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
        }
    }

    // MARK: 6 — job types

    private var jobTypesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Job types", trailing: "\(data.jobTypes.count)")
            VStack(spacing: 10) {
                ForEach(data.jobTypes) { type in
                    let share = data.totalTrips > 0
                        ? Double(type.count) / Double(data.totalTrips) : 0
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(AmbientStyle.avatarColor(type.name))
                                .frame(width: 9, height: 9)
                            Text(type.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(type.count)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text(StatsSample.percent(share))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                        // The live "Job Types Distribution" card renders NO
                        // distribution graphic despite its title. This is the
                        // thin bar the title has always promised.
                        bar(value: share, maxValue: 1,
                            tint: AmbientStyle.avatarColor(type.name), height: 4)
                    }
                }
            }
            .ambientCard(density: .roomy, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
        }
    }

    private var weatherFootnote: some View {
        Text("The old \"Weather Impact\" chart was hardcoded sample data and is gone.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: the states

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Reading \(data.spanLabel)…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    /// A REAL empty state. Today an empty period is rendered as an ERROR — "No
    /// data available for the selected time period" is raised through the
    /// error path and replaces the whole screen.
    private var emptyState: some View {
        AmbientEmptyState(
            title: "No reports in \(period.label) yet",
            message: "Statistics are built from filed daily job reports. Pick a different period, or check back once reports come in.",
            systemImage: "chart.bar")
    }

    private var errorState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Couldn't load statistics").font(.headline)
            Text("One of the queries didn't answer. Nothing is wrong with your reports.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                withAnimation(AmbientMotion.gentle) { state = .populated }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    // ambient-allow: a control, not a card.
                    .background(Capsule().fill(Self.featureTint))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Text("Today ONE failing query replaces the entire screen, even when four of five datasets loaded. A section that failed should say so where it sits.")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: the one bar

    /// One horizontal bar recipe for the whole screen. The live screen has three
    /// near-identical ones plus a hand-drawn `Path` chart.
    private func bar(value: Double, maxValue: Double, tint: Color, height: CGFloat = 8) -> some View {
        GeometryReader { proxy in
            let fraction = maxValue > 0 ? min(max(value / maxValue, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint.gradient)
                    // Width DERIVED from the measured track, and a real zero draws
                    // nothing. The live bars carry a 5pt floor, so a zero value
                    // still shows a bar — a chart that cannot say "none".
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Sample data

private enum StatsPeriod: String, CaseIterable, Identifiable {
    case month
    case quarter
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: return "July"
        case .quarter: return "Q3"
        case .year: return "2026"
        }
    }

}

private struct LabStatsPerson: Identifiable {
    let name: String
    let trips: Int
    let miles: Double

    var id: String { name }
    /// The flat rate the live screen uses, kept visible rather than hidden — the
    /// caption beside it names the reconciliation this design proposes.
    var reimbursement: Double { miles * 0.67 }
}

private struct LabStatsSchool: Identifiable {
    let name: String
    let visits: Int
    let miles: Double

    var id: String { name }
}

private struct LabStatsJobType: Identifiable {
    let name: String
    let count: Int

    var id: String { name }
}

private struct LabStatsMonth: Identifiable {
    let monthLabel: String
    let yearLabel: String
    let miles: Double
    /// Outside the selected period. Drawn dimmed for contrast, excluded from
    /// every total — which is only possible because the bucket knows its year.
    var isComparison: Bool = false

    var id: String { "\(monthLabel)-\(yearLabel)" }
}

/// Totals are COMPUTED from the parts. The overview tiles cannot drift from the
/// sections, which is the failure this screen ships today (every mileage total is
/// 2× actual because one accumulator adds twice).
private struct StatsDataset {
    let spanLabel: String
    let photographers: [LabStatsPerson]
    let schools: [LabStatsSchool]
    let jobTypes: [LabStatsJobType]
    let months: [LabStatsMonth]

    var totalMiles: Double { photographers.reduce(0) { $0 + $1.miles } }
    var totalTrips: Int { photographers.reduce(0) { $0 + $1.trips } }
}

private enum StatsSample {
    /// Six photographers, so the live screen's three-name cap is visibly dead —
    /// and TWO of them are called Chris, which is the roster defect the parity doc
    /// records: the photographer list is keyed on `first_name` alone, so two
    /// employees with the same first name merge into one row.
    static func dataset(for period: StatsPeriod) -> StatsDataset {
        switch period {
        case .year: return year
        case .quarter: return quarter
        case .month: return month
        }
    }

    private static let year = StatsDataset(
        spanLabel: "Jan 1 – Jul 31, 2026",
        photographers: [
            LabStatsPerson(name: "Maria Delgado", trips: 22, miles: 378.4),
            LabStatsPerson(name: "Chris Aldridge", trips: 20, miles: 351.6),
            LabStatsPerson(name: "Chris Nakamura", trips: 16, miles: 276.2),
            LabStatsPerson(name: "Priya Raman", trips: 15, miles: 243.8),
            LabStatsPerson(name: "Tom Boyle", trips: 11, miles: 182.4),
            LabStatsPerson(name: "Alex Whitfield", trips: 8, miles: 141.8)
        ],
        schools: [
            LabStatsSchool(name: "Westfield Consolidated High School", visits: 20, miles: 369.6),
            LabStatsSchool(name: "Northgate Elementary", visits: 17, miles: 264.8),
            LabStatsSchool(name: "St. Bartholomew Academy", visits: 14, miles: 239.2),
            LabStatsSchool(name: "Riverbend Middle School", visits: 12, miles: 196.4),
            LabStatsSchool(name: "Oakmont Prep", visits: 10, miles: 167.0),
            LabStatsSchool(name: "Lakeshore Charter", visits: 8, miles: 135.6),
            LabStatsSchool(name: "Pinehurst Elementary", visits: 6, miles: 111.4),
            LabStatsSchool(name: "Cedar Valley Day School", visits: 5, miles: 90.2)
        ],
        jobTypes: [
            LabStatsJobType(name: "Fall Portraits", count: 26),
            LabStatsJobType(name: "Sports — Team", count: 20),
            LabStatsJobType(name: "Graduation", count: 15),
            LabStatsJobType(name: "Yearbook Groups", count: 13),
            LabStatsJobType(name: "Underclass Retakes", count: 11),
            LabStatsJobType(name: "Event Coverage", count: 7)
        ],
        // Two dimmed bars from LAST year, then the seven months of the selected
        // one — chronological, year-labelled, and crossing the boundary.
        months: [
            LabStatsMonth(monthLabel: "Nov", yearLabel: "2025", miles: 126.8, isComparison: true),
            LabStatsMonth(monthLabel: "Dec", yearLabel: "2025", miles: 142.0, isComparison: true),
            LabStatsMonth(monthLabel: "Jan", yearLabel: "2026", miles: 168.4),
            LabStatsMonth(monthLabel: "Feb", yearLabel: "2026", miles: 151.8),
            LabStatsMonth(monthLabel: "Mar", yearLabel: "2026", miles: 205.6),
            LabStatsMonth(monthLabel: "Apr", yearLabel: "2026", miles: 233.0),
            LabStatsMonth(monthLabel: "May", yearLabel: "2026", miles: 264.2),
            LabStatsMonth(monthLabel: "Jun", yearLabel: "2026", miles: 288.6),
            LabStatsMonth(monthLabel: "Jul", yearLabel: "2026", miles: 262.6)
        ])

    /// July's own numbers. The month bars carry July 2025 alongside July 2026 —
    /// two bars a year-less key would have summed into one.
    private static let month = StatsDataset(
        spanLabel: "Jul 1 – Jul 31, 2026",
        photographers: [
            LabStatsPerson(name: "Maria Delgado", trips: 4, miles: 68.4),
            LabStatsPerson(name: "Chris Aldridge", trips: 3, miles: 57.2),
            LabStatsPerson(name: "Chris Nakamura", trips: 3, miles: 44.0),
            LabStatsPerson(name: "Priya Raman", trips: 2, miles: 38.6),
            LabStatsPerson(name: "Tom Boyle", trips: 2, miles: 30.2),
            LabStatsPerson(name: "Alex Whitfield", trips: 1, miles: 24.2)
        ],
        schools: [
            LabStatsSchool(name: "Westfield Consolidated High School", visits: 4, miles: 82.4),
            LabStatsSchool(name: "Northgate Elementary", visits: 4, miles: 66.2),
            LabStatsSchool(name: "St. Bartholomew Academy", visits: 3, miles: 51.0),
            LabStatsSchool(name: "Riverbend Middle School", visits: 2, miles: 36.8),
            LabStatsSchool(name: "Oakmont Prep", visits: 2, miles: 26.2)
        ],
        jobTypes: [
            LabStatsJobType(name: "Fall Portraits", count: 5),
            LabStatsJobType(name: "Sports — Team", count: 4),
            LabStatsJobType(name: "Graduation", count: 2),
            LabStatsJobType(name: "Yearbook Groups", count: 2),
            LabStatsJobType(name: "Underclass Retakes", count: 1),
            LabStatsJobType(name: "Event Coverage", count: 1)
        ],
        months: [
            LabStatsMonth(monthLabel: "Jul", yearLabel: "2025", miles: 214.8, isComparison: true),
            LabStatsMonth(monthLabel: "Jul", yearLabel: "2026", miles: 262.6)
        ])

    /// Q3 is July, August and September — and only July has happened. The heading
    /// says so instead of presenting one month's numbers as a quarter's, which is
    /// what a trailing-92-day window silently does.
    private static let quarter = StatsDataset(
        spanLabel: "Jul 1 – Sep 30, 2026 · July so far",
        photographers: month.photographers,
        schools: month.schools,
        jobTypes: month.jobTypes,
        months: [
            LabStatsMonth(monthLabel: "Jul", yearLabel: "2026", miles: 262.6),
            LabStatsMonth(monthLabel: "Aug", yearLabel: "2026", miles: 0),
            LabStatsMonth(monthLabel: "Sep", yearLabel: "2026", miles: 0)
        ])

    static func miles(_ value: Double) -> String {
        String(format: "%.1f mi", value)
    }

    /// "$1,234.50" — grouped and to the cent. The live reimbursement bars label
    /// themselves "$<Int>", which loses up to a dollar per photographer.
    static func money(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
