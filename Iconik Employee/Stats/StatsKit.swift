//  StatsKit.swift
//  Iconik Employee — the Statistics design, as production code
//
//  PRODUCTION CODE THAT THE LAB MOCKUP IMPORTS. Same mechanism as
//  TimeOff/TimeOffKit.swift: the mockup draws these exact views with sample
//  values and `StatsView` draws them with a service's values, so a conversion is
//  swapping the data rather than matching a screenshot. There is no second copy
//  to drift from — the mockup's private chart components were DELETED when these
//  arrived, not left beside them.
//
//  Everything here takes plain values from `Stats/StatsRules.swift`, which is
//  SwiftUI-free and RUN by `scripts/test_stats_rules.sh`. Nothing here computes a
//  number: the sections read `StatsAggregate`, whose totals are sums of its own
//  parts. That is deliberate — the shipped screen's overview tiles disagreed with
//  the sections beneath them (every mileage figure was 2× actual), and a view
//  that can do arithmetic is a view that can disagree.
//
//  ONE BAR RECIPE for the whole screen. The old screen had three near-identical
//  horizontal bars plus a hand-drawn `Path` line chart, and every one of them
//  carried a 5pt floor so a zero still drew something visible — a chart that
//  cannot say "none". These say none.

import SwiftUI

// MARK: - Identity

enum StatsStyle {
    /// D11: the wash takes the FEATURE's colour, read from `FeatureTheme` rather
    /// than restated, so the tile you tap and the screen you land on agree. The
    /// live screen applied no wash at all.
    static var tint: Color { FeatureTheme.color(for: "stats") }
}

// MARK: - Formatting

enum StatsFormat {
    /// "18.2 mi".
    static func miles(_ value: Double) -> String { String(format: "%.1f mi", value) }

    /// "$1,234.50" — grouped and to the cent, through the app's ONE money
    /// formatter. The old reimbursement bars labelled themselves "$<Int>", losing
    /// up to a dollar per photographer, and were one of the four spellings of
    /// currency that `Formatters.currency` was added to replace. This screen does
    /// not get to be the fifth.
    static func money(_ value: Double) -> String { Formatters.currency(value) }

    /// "50%" from a whole percent that `StatsRules` already guarded.
    static func percent(_ whole: Int) -> String { "\(whole)%" }
}

// MARK: - The one bar

/// One horizontal bar. The width is DERIVED from the measured track and a real
/// zero draws nothing.
struct StatsBar: View {
    let value: Double
    let maxValue: Double
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let fraction = maxValue > 0 ? min(max(value / maxValue, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: height)
    }
}

// MARK: - The period chips

/// Month / Quarter / Year, labelled with the period's NAME — "July", "Q3",
/// "2026" — because that is what the window now is.
struct StatsPeriodChips: View {
    @Binding var period: StatsPeriod
    let reference: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(StatsPeriod.allCases) { option in
                    chip(option)
                }
                Spacer(minLength: 0)
            }
            Text("Real calendar periods: July means the 1st to the 31st, and Q3 means July through September.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chip(_ option: StatsPeriod) -> some View {
        let selected = option == period
        return Button {
            withAnimation(AmbientMotion.snappy) { period = option }
            AmbientHaptics.selection()
        } label: {
            Text(option.label(reference: reference))
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                // ambient-allow: a selection chip is a control, not a container.
                .background(Capsule().fill(selected
                                           ? AnyShapeStyle(StatsStyle.tint)
                                           : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overview

/// Four tiles, every one a SUM of the sections below it.
struct StatsOverviewSection: View {
    let aggregate: StatsAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Overview", trailing: aggregate.spanLabel)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    AmbientStatTile(value: Int(aggregate.totalMiles.rounded()),
                                    label: "Miles",
                                    systemImage: "car.fill",
                                    tint: .blue)
                    AmbientStatTile(value: aggregate.totalTrips,
                                    label: "Trips",
                                    systemImage: "briefcase.fill",
                                    tint: .green)
                }
                HStack(spacing: 10) {
                    AmbientStatTile(value: aggregate.photographerCount,
                                    label: "Photographers",
                                    systemImage: "person.fill",
                                    tint: .orange)
                    AmbientStatTile(value: aggregate.schoolsVisited,
                                    label: "Schools visited",
                                    systemImage: "mappin.and.ellipse",
                                    tint: .red)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Trips are counted as reports, not job descriptions — a report listing three jobs is one trip.")
                Text("Schools visited counts the destinations reports were actually filed for, not every school on the org's list.")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Mileage

struct StatsMileageSection: View {
    let aggregate: StatsAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("Mileage", trailing: StatsFormat.miles(aggregate.totalMiles))
            monthlyMilesCard
            byPhotographerCard
        }
    }

    /// Hand-built vertical bars — no `import Charts` at the iOS 16.6 floor. What
    /// the old charts lacked and these have: a BASELINE, a value on every bar,
    /// and a label carrying the YEAR. The dimmed bars are the two months before
    /// the period, drawn for contrast and excluded from every total — which is
    /// only safe to draw because the buckets are keyed by month AND year.
    private var monthlyMilesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Monthly miles").font(.subheadline.weight(.semibold))

            let maxValue = max(aggregate.months.map(\.miles).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(aggregate.months) { bucket in
                    VStack(spacing: 4) {
                        Text("\(Int(bucket.miles.rounded()))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(bucket.isComparison ? .tertiary : .secondary)
                        Capsule()
                            .fill(bucket.isComparison
                                  ? AnyShapeStyle(Color.primary.opacity(0.14))
                                  : AnyShapeStyle(StatsStyle.tint.gradient))
                            // NO MINIMUM FLOOR. A month with no miles draws
                            // nothing, which is the honest picture of a month
                            // with no miles.
                            .frame(height: 108 * bucket.miles / maxValue)
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
            // The baseline, so a zero bar reads as zero rather than as missing.
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

            let maxValue = max(aggregate.photographers.map(\.miles).max() ?? 1, 1)
            VStack(spacing: 12) {
                ForEach(aggregate.photographers) { person in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            AmbientAvatar(name: person.name, size: 24)
                            Text(person.name).font(.caption.weight(.semibold))
                            Spacer(minLength: 6)
                            Text(StatsFormat.miles(person.miles))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        StatsBar(value: person.miles, maxValue: maxValue,
                                 tint: AmbientStyle.avatarColor(person.name))
                        Text("\(StatsFormat.money(person.reimbursement)) reimbursement")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Text("Personal miles pay each photographer's own rate and company-car miles pay the organisation's rate — the same rule the manager mileage screen uses.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy, fill: .surface,
                     border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
    }
}

// MARK: - Locations

/// ONE card with two metric columns, not three near-identical card sets. The old
/// screen drew "Top Locations by Visits", "Locations by Mileage" and "Visit
/// Efficiency" as three five-row bar charts over the same five schools — the same
/// information, read three times.
struct StatsLocationsSection: View {
    let aggregate: StatsAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Locations", trailing: "top \(aggregate.topDestinations.count) of \(aggregate.schoolsVisited)")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Top schools by visits").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 6)
                    Text("miles").font(.caption2).foregroundStyle(.tertiary)
                }

                let top = aggregate.topDestinations
                let maxVisits = max(top.map(\.visits).max() ?? 1, 1)
                VStack(spacing: 10) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, place in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                Text(place.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text("\(place.visits) visits")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                // The second metric as a COLUMN, not a second card.
                                Text(StatsFormat.miles(place.miles))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 62, alignment: .trailing)
                            }
                            StatsBar(value: Double(place.visits), maxValue: Double(maxVisits),
                                     tint: StatsStyle.tint)
                        }
                    }
                }

                Text("A visit is one destination on one day, so a school photographed twice in a day counts once. Destinations come from the reports themselves, typed or picked.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ambientCard(density: .roomy, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
        }
    }
}

// MARK: - Photographers

struct StatsPhotographersSection: View {
    let aggregate: StatsAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Photographers", trailing: "\(aggregate.photographerCount)")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(aggregate.photographersByTrips) { person in
                    HStack(spacing: 10) {
                        AmbientAvatar(name: person.name, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name).font(AmbientDensity.compact.titleFont)
                            Text("\(person.trips) trips")
                                .font(AmbientDensity.compact.subtitleFont)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text(StatsFormat.miles(person.miles))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                }

                Divider()

                // The card that is deliberately NOT here. Job start and end times
                // do not exist as columns, so there is nothing to average — the
                // old card showed a hardcoded 3.0 hours for everyone.
                Text("Job duration isn't recorded anywhere, so it isn't drawn.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ambientCard(density: .roomy, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
        }
    }
}

// MARK: - Job types

struct StatsJobTypesSection: View {
    let aggregate: StatsAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Job types", trailing: "\(aggregate.jobTypes.count)")
            VStack(spacing: 10) {
                ForEach(aggregate.jobTypes) { type in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(AmbientStyle.avatarColor(type.name))
                                .frame(width: 9, height: 9)
                            Text(type.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(type.count)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text(StatsFormat.percent(type.percent))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                        // The old "Job Types Distribution" card rendered NO
                        // distribution graphic despite its title. This is the thin
                        // bar that title has always promised.
                        StatsBar(value: Double(type.percent), maxValue: 100,
                                 tint: AmbientStyle.avatarColor(type.name), height: 4)
                    }
                }
            }
            .ambientCard(density: .roomy, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
        }
    }
}

// MARK: - States

struct StatsLoadingState: View {
    let spanLabel: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Reading \(spanLabel)…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

/// A REAL empty state. The old screen rendered an empty period as an ERROR — "No
/// data available for the selected time period" came through the error path and
/// replaced the whole screen.
struct StatsEmptyPeriodState: View {
    let periodLabel: String

    var body: some View {
        AmbientEmptyState(
            title: "No reports in \(periodLabel) yet",
            message: "Statistics are built from filed daily job reports. Pick a different period, or check back once reports come in.",
            systemImage: "chart.bar")
    }
}

/// One fetch, one honest error state. The old screen ran five queries that raced
/// to write one `errorMessage`, and any one of them replaced the entire screen.
struct StatsErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Couldn't load statistics").font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    // ambient-allow: a control, not a card.
                    .background(Capsule().fill(StatsStyle.tint))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
