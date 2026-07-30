//  RoutePlannerMockup.swift
//  Iconik Employee — the Route Planner mockup, built in batch 3
//
//  ARC SCAFFOLDING. Deleted at the close of AMB.12, with the lab.
//
//  APPROVED BY THE OPERATOR 2026-07-29, AND REPOINTED IN THE SAME PHASE.
//      The screen was folded into AMB.9 and built. This file no longer holds a
//      single private view: every piece it draws now lives in
//      `Misc Features/RoutePlannerKit.swift`, which `RoutePlannerView` draws with
//      too. What remains here is the LAB HARNESS — the state picker and the sample
//      data — so the operator can still walk the four states without a network,
//      and so a change to the design shows up in both places or neither. That
//      direction is the whole mechanism (the TimeOffKit pattern from AMB.8): the
//      mockup imports production code, never the other way round.
//
//  WHAT THE DESIGN ARGUED, in four claims — all four now shipped
//
//      1. THE OPTIMIZE BUTTON MUST NOT VANISH. The old screen rendered the whole
//         bottom bar only at two or more selections. `RouteOptimizeBar` is always
//         on screen, disabled below two with "Select at least two schools".
//
//      2. A SCHOOL WITH NO MAP PIN SAYS SO. Coordinate-less schools were
//         selectable, counted, and then silently dropped by the optimizer's
//         `validSchools` filter. `RouteSchoolRow` says it in words and cannot be
//         selected; the count counts only routable schools.
//
//      3. A FAILED OPTIMIZATION MUST NOT LOOK LIKE SUCCESS. The service now
//         throws with the server's real message instead of returning the original
//         order at zero miles, the totals draw unconditionally, and skipped
//         schools are listed rather than printed to the console.
//
//      4. THE RESULT READS AS A TIMELINE. There is no map and cannot be one — no
//         polyline is requested and MapKit is not imported — so the honest form is
//         a vertical timeline whose positions are derived from MEASURED height
//         (the AMB.11 geometry lesson). That geometry lives in `RouteTimeline`.
//
//  BOTH MAP BUTTONS ARE STILL DEAD HERE, because the lab has no route to hand to
//  a map app. They are live on the real screen.

import SwiftUI

// MARK: - Destinations

/// One enum, one `.ambientPush`. The old screen swapped two full-screen modes
/// with a boolean, which is how it ended up drawing two stacked title rows in
/// preview mode.
private enum RoutePlannerLabDestination: String, Identifiable {
    case preview

    var id: String { rawValue }
}

private enum RoutePlannerLabState: String, CaseIterable, Identifiable {
    case selection = "Selection"
    case selectionEmpty = "No schools"
    case preview = "Preview"
    case previewSkips = "Skips"

    var id: String { rawValue }

    var isPreview: Bool { self == .preview || self == .previewSkips }
}

// MARK: - Selection

struct RoutePlannerMockup: View {
    /// Kept as the name the lab's own chrome reads (`DesignLabView`), pointed at
    /// the one definition in the kit.
    static var featureTint: Color { RoutePlannerStyle.tint }

    @State private var state: RoutePlannerLabState = .selection
    @State private var query = ""
    @State private var startFrom: String? = "Current Location"
    @State private var addsEndPoint = false
    @State private var endAt: String? = "Home"
    @State private var selected: Set<String> = ["ws-1", "ws-3", "ws-5"]
    @State private var optimizing = false
    @State private var destination: RoutePlannerLabDestination?

    private var rows: [RouteSchoolRowModel] {
        guard state != .selectionEmpty else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return RouteSample.schools }
        return RouteSample.schools.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
            || $0.address.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Only routable schools count.
    private var selectedCount: Int {
        RouteSample.schools.filter { selected.contains($0.id) && $0.isRoutable }.count
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.8)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        labControl
                        if state.isPreview { previewHint }
                        RouteSearchCard(text: $query)
                        routeSection
                        schoolsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()

                RouteOptimizeBar(enabled: selectedCount >= 2,
                                 isOptimizing: optimizing,
                                 caption: selectedCount < 2 ? "Select at least two schools" : nil,
                                 tint: Self.featureTint) {
                    optimizing = true
                    AmbientHaptics.impact(.medium)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        optimizing = false
                        destination = .preview
                    }
                }
            }
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .preview:
                RoutePreviewMockup(showsSkips: state == .previewSkips,
                                   startLabel: startFrom ?? "Current Location",
                                   endLabel: addsEndPoint ? endAt : nil)
            }
        }
    }

    // MARK: lab chrome

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · state", trailing: "not a design element")
            Picker("State", selection: $state) {
                ForEach(RoutePlannerLabState.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var previewHint: some View {
        Text("Tap Optimize to push the timeline\(state == .previewSkips ? " with two skipped schools" : "").")
            .font(.caption2).foregroundStyle(.tertiary)
    }

    // MARK: start and end

    private var routeSection: some View {
        RouteEndpointsSection(
            status: "\(selectedCount) stop\(selectedCount == 1 ? "" : "s")",
            statusTint: selectedCount >= 2 ? Self.featureTint : nil,
            startOptions: ["Current Location", "Home", "Work"],
            start: $startFrom,
            // The lab pretends the organisation address is unset, so the warning
            // the real screen shows for an unavailable option can be seen here.
            startWarning: startFrom == "Work" ? "Organization address not available" : nil,
            addsEndPoint: $addsEndPoint,
            endOptions: ["Home", "Work"],
            end: $endAt,
            endWarning: endAt == "Work" ? "Organization address not available" : nil,
            tint: Self.featureTint)
    }

    // MARK: the school list

    private var schoolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Schools")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(selectedCount) selected")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                if !selected.isEmpty {
                    Button("Clear") {
                        withAnimation(AmbientMotion.snappy) { selected.removeAll() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Self.featureTint)
                }
            }

            if rows.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                    ForEach(rows) { row in
                        RouteSchoolRow(model: row,
                                       isSelected: selected.contains(row.id),
                                       tint: Self.featureTint) {
                            withAnimation(AmbientMotion.snappy) {
                                if selected.contains(row.id) {
                                    selected.remove(row.id)
                                } else {
                                    selected.insert(row.id)
                                }
                            }
                            AmbientHaptics.selection()
                        }
                    }
                }
            }
        }
    }

    /// The old screen had NO empty state: no schools, or no search match, left a
    /// blank section reading "0 selected".
    @ViewBuilder
    private var emptyState: some View {
        if state == .selectionEmpty {
            AmbientEmptyState(
                title: "No schools yet",
                message: "Routes are built from your organization's schools. An administrator adds them in Settings.",
                systemImage: "building.2")
        } else {
            AmbientEmptyState(title: "No schools match",
                              message: "Search looks at the name and the address.",
                              systemImage: "magnifyingglass")
        }
    }
}

// MARK: - The preview

private struct RoutePreviewMockup: View {
    let showsSkips: Bool
    let startLabel: String
    let endLabel: String?

    private var entries: [RouteTimelineEntry] {
        var entries: [RouteTimelineEntry] = [
            RouteTimelineEntry(id: "start",
                               marker: .start,
                               title: startLabel,
                               subtitle: "Starting point",
                               legLabel: RouteSample.legLabel(0))
        ]
        for (index, stop) in RouteSample.optimizedStops.enumerated() {
            entries.append(RouteTimelineEntry(id: stop.id,
                                              marker: .stop(index + 1),
                                              title: stop.name,
                                              subtitle: stop.address,
                                              legLabel: RouteSample.legLabel(index + 1)))
        }
        if let endLabel {
            entries.append(RouteTimelineEntry(id: "end",
                                              marker: .end,
                                              title: endLabel,
                                              subtitle: "End point"))
        }
        return entries
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: RoutePlannerStyle.tint, intensity: 0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    RouteTotalsHero(distanceLabel: RouteSample.totalDistanceLabel,
                                    durationLabel: RouteSample.totalDurationLabel)
                    if showsSkips {
                        RouteSkippedNotice(names: RouteSample.skipped)
                    }
                    RouteTimeline(entries: entries)
                    RouteMapButtons(openAppleMaps: {}, openGoogleMaps: {})
                    RoutePreviewFootnote()
                    Text("Both map buttons are dead in the lab — there is no route here to hand to a map app.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Optimized Route")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sample data

private enum RouteSample {
    /// Addresses of deliberately varying length — the short one and the one that
    /// must truncate on a 375pt screen both have to read. Two of the eight have no
    /// map pin; that is the case the design exists to fix.
    static let schools: [RouteSchoolRowModel] = [
        RouteSchoolRowModel(id: "ws-1", name: "Northgate Elementary",
                            address: "412 Northgate Rd, Fairview", isRoutable: true),
        RouteSchoolRowModel(id: "ws-2", name: "Cedar Valley Day School",
                            address: "8 Mill Ln", isRoutable: false),
        RouteSchoolRowModel(id: "ws-3", name: "Westfield Consolidated High School",
                            address: "1900 West Westfield Township Boulevard, Suite 2, Westfield", isRoutable: true),
        RouteSchoolRowModel(id: "ws-4", name: "Pinehurst Elementary",
                            address: "77 Pinehurst Ave, Bellmore", isRoutable: true),
        RouteSchoolRowModel(id: "ws-5", name: "St. Bartholomew Academy",
                            address: "620 Chapel St, Old Town", isRoutable: true),
        RouteSchoolRowModel(id: "ws-6", name: "Lakeshore Charter",
                            address: "Lot 4, County Rd 19", isRoutable: false),
        RouteSchoolRowModel(id: "ws-7", name: "Riverbend Middle School",
                            address: "3300 Riverbend Pkwy, Ashford", isRoutable: true),
        RouteSchoolRowModel(id: "ws-8", name: "Oakmont Prep",
                            address: "15 Oakmont Sq, Granton", isRoutable: true)
    ]

    static let optimizedStops: [RouteSchoolRowModel] = [
        schools[0], schools[4], schools[2]
    ]

    /// One more leg than stops: start → 1, 1 → 2, 2 → 3. Formatted through the
    /// kit's formatter, so the lab cannot round differently from the app.
    private static let legs: [(miles: Double, minutes: Double)] = [
        (12.3, 24), (9.1, 18), (17.0, 29.6)
    ]

    static func legLabel(_ index: Int) -> String? {
        guard index >= 0 && index < legs.count else { return nil }
        return RoutePlannerFormat.leg(miles: legs[index].miles, minutes: legs[index].minutes)
    }

    static let totalDistanceLabel = RoutePlannerFormat.distance(miles: 38.4)
    static let totalDurationLabel = RoutePlannerFormat.duration(minutes: 71.6)

    static let skipped = ["Cedar Valley Day School", "Lakeshore Charter"]
}
