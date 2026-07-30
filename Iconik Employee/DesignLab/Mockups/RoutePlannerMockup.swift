//  RoutePlannerMockup.swift
//  Iconik Employee — the Route Planner mockup, built in batch 3
//
//  ARC SCAFFOLDING. Deleted at the close of whichever phase converts the screen.
//
//  WHERE THIS SCREEN LANDS IS AN OPEN OPERATOR DECISION.
//      The Route Planner belongs to NO phase in the arc registry. The card-drift
//      gate's own header says so: its row was tagged AMB.9 by the generator only
//      so it would not read as AMB.7 having failed, and "where the route planner
//      really lands is the operator's call"
//      (`scripts/check_card_drift.py:106-111`). This mockup exists so batch 3
//      shows the whole "On the road" family — Mileage and the Route Planner share
//      a palette family and a job — and so the operator can judge them together.
//      APPROVING THIS MOCKUP DOES NOT DECIDE THE PHASE. It decides what the
//      screen should look like whenever it is built.
//
//  WHAT THE DESIGN IS ARGUING, in four claims
//
//      1. THE OPTIMIZE BUTTON MUST NOT VANISH.
//         Today the whole bottom bar renders only at two or more selections
//         (parity §3, Mode A) — below two there is no button, no caption, and no
//         explanation. A control that disappears teaches nothing; a disabled
//         control with a reason teaches the rule in one glance. So Optimize is
//         ALWAYS on screen, disabled below two with "Select at least two schools".
//
//      2. A SCHOOL WITH NO MAP PIN SAYS SO.
//         Coordinate-less schools are selectable, counted in "3 selected", and
//         then silently dropped by the optimizer's `validSchools` filter
//         (`RouteOptimizerService.swift:203`) — with no notice anywhere. The
//         current screen even draws a slashed-pin indicator beside them, which
//         does not block selection and does not say what it means. Here the row
//         says it in words and cannot be selected. PROPOSED: the drop happens in
//         the service, so making this true is a data-layer change.
//
//      3. A FAILED OPTIMIZATION MUST NOT LOOK LIKE SUCCESS.
//         When Google returns no order the service silently returns the ORIGINAL
//         order with `totalDistanceMiles: 0`, and the `> 0` gate then hides the
//         totals pill — so the user sees their own list back, unlabelled, and
//         nothing that says it failed (parity §3, dead-list item 4). Skipped
//         schools are decoded, counted and printed to the console only. Both are
//         drawn here as visible notices.
//
//      4. THE RESULT READS AS A TIMELINE.
//         The route is a text list today: a green start row, numbered stops, an
//         optional red end row, with per-leg captions hidden whenever a leg
//         rounds to zero. There is no map and there cannot be one — no polyline
//         is requested from the server and MapKit is not imported. So the design
//         commits to the honest form: a vertical timeline, drawn with the line
//         and dots derived from MEASURED height (the AMB.11 geometry lesson —
//         constant offsets in a flexing column drift apart at Dynamic Type).
//
//  WHAT IS NOT BEING PROPOSED
//      No data layer, service or optimizer change (D12). The malformed
//      `comgooglemaps://` deep link, the discarded server error, the 2-second
//      GPS sleep and the 10,000:1 distance:time cost model are recorded in
//      AMB_BATCH3_PARITY.md §3 and are NOT fixed here. Both map buttons are dead
//      in the mockup.

import SwiftUI

// MARK: - Destinations

/// One enum, one `.ambientPush`. The live screen swaps two full-screen modes with
/// a boolean; here the preview is PUSHED, which is what the lab is for — a mode
/// swap inside one screen is exactly how the app ended up drawing two stacked
/// title rows in preview mode (parity §3).
private enum RoutePlannerDestination: String, Identifiable {
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

// MARK: - Mode A — selection

struct RoutePlannerMockup: View {
    /// `FeatureTheme.color(for: "routePlanner")` — the "On the road" family it
    /// shares with Mileage.
    static let featureTint = Color(hex: "#F76B15")

    @State private var state: RoutePlannerLabState = .selection
    @State private var query = ""
    @State private var startFrom: String? = "Current Location"
    @State private var addsEndPoint = false
    @State private var endAt: String? = "Home"
    @State private var selected: Set<String> = ["ws-1", "ws-3", "ws-5"]
    @State private var optimizing = false
    @State private var destination: RoutePlannerDestination?

    private var schools: [LabRouteSchool] {
        guard state != .selectionEmpty else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return RouteSample.schools }
        return RouteSample.schools.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
            || $0.address.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Only routable schools count. The current screen counts everything it let
    /// you tick, which is how "3 selected" becomes a two-stop route.
    private var selectedCount: Int {
        RouteSample.schools.filter { selected.contains($0.id) && $0.hasCoordinates }.count
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.8)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        labControl
                        if state.isPreview { previewHint }
                        searchField
                        routeSection
                        schoolsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()

                optimizeBar
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

    // MARK: search

    /// Hand-rolled, as the app's is — `.searchable` is out at the iOS 16.6 floor
    /// for this shell, and the live filter searches name and address only, which
    /// this repeats rather than quietly widening (that would be a data change).
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.footnote).foregroundStyle(.secondary)
            TextField("Search schools", text: $query)
                .font(.subheadline)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.footnote).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    // MARK: start and end

    private var routeSection: some View {
        AmbientFormSection(title: "Route",
                           status: "\(selectedCount) stop\(selectedCount == 1 ? "" : "s")",
                           statusTint: selectedCount >= 2 ? Self.featureTint : nil) {
            VStack(alignment: .leading, spacing: 12) {
                AmbientChoiceRow(title: "Start from",
                                 options: ["Current Location", "Home", "Work"],
                                 selection: $startFrom,
                                 tint: Self.featureTint)

                // The warning the live screen shows, kept — and now attached to
                // the option it is about rather than floating under the picker.
                if startFrom == "Work" {
                    warningLine("Organization address not set")
                }

                Divider()

                Toggle(isOn: $addsEndPoint) {
                    Text("Add end point").font(.subheadline.weight(.semibold))
                }
                .tint(Self.featureTint)

                if addsEndPoint {
                    AmbientChoiceRow(title: "End at",
                                     options: ["Home", "Work"],
                                     selection: $endAt,
                                     tint: Self.featureTint)
                    if endAt == "Work" {
                        warningLine("Organization address not set")
                    }
                }
            }
        }
    }

    private func warningLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2.weight(.semibold))
            Text(text).font(.caption)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.orange)
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

            if schools.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                    ForEach(schools) { school in
                        schoolRow(school)
                    }
                }
            }
        }
    }

    private func schoolRow(_ school: LabRouteSchool) -> some View {
        let on = selected.contains(school.id)
        return Button {
            guard school.hasCoordinates else { return }
            withAnimation(AmbientMotion.snappy) {
                if on { selected.remove(school.id) } else { selected.insert(school.id) }
            }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(school.hasCoordinates
                                     ? (on ? AnyShapeStyle(Self.featureTint) : AnyShapeStyle(.secondary))
                                     : AnyShapeStyle(.quaternary))

                VStack(alignment: .leading, spacing: 3) {
                    Text(school.name)
                        .font(AmbientDensity.compact.titleFont)
                        .lineLimit(1)
                    Text(school.address)
                        .font(AmbientDensity.compact.subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // PROPOSED — today this school is tickable, is counted, and is
                    // then dropped by the service with no notice at all.
                    if !school.hasCoordinates {
                        AmbientBadge(text: "No map pin — can't be routed",
                                     systemImage: "mappin.slash", tint: .orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .opacity(school.hasCoordinates ? 1 : 0.55)
            .ambientCard(density: .compact,
                         border: on ? .hairline(Self.featureTint.opacity(0.5)) : .none,
                         fillWidth: true)
        }
        .buttonStyle(.plain)
        .disabled(!school.hasCoordinates)
    }

    /// The live screen has NO empty state: no schools, or no search match, leaves
    /// a blank section reading "0 selected".
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

    // MARK: the bottom bar — always present

    private var optimizeBar: some View {
        VStack(spacing: 6) {
            Button {
                optimizing = true
                AmbientHaptics.impact(.medium)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    optimizing = false
                    destination = .preview
                }
            } label: {
                HStack(spacing: 8) {
                    if optimizing {
                        ProgressView().tint(.white)
                        Text("Optimizing…")
                    } else {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        Text("Optimize Route")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                // ambient-allow: a filled primary action is a control, not a card.
                .background(Capsule().fill(selectedCount >= 2
                                           ? Self.featureTint
                                           : Color.gray.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .disabled(selectedCount < 2 || optimizing)

            if selectedCount < 2 {
                Text("Select at least two schools")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Mode B — the preview

/// The result, as a timeline. Every position is derived from MEASURED height:
/// each row's marker column is a `GeometryReader`, the dot sits one radius down
/// from the row's top edge, and the connector runs from there to the measured
/// bottom — so the line still meets the dots at the largest Dynamic Type size,
/// which a stack of constant offsets does not (the AMB.11 lesson).
private struct RoutePreviewMockup: View {
    let showsSkips: Bool
    let startLabel: String
    let endLabel: String?

    private var stops: [LabRouteSchool] { RouteSample.optimizedStops }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: RoutePlannerMockup.featureTint, intensity: 0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    totals
                    if showsSkips { skipNotice }
                    timeline
                    mapButtons
                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Optimized Route")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Drawn unconditionally. The live totals pill is gated on distance > 0, which
    /// is exactly the condition a FAILED optimization produces — so the one time
    /// the user most needs to be told something is wrong, the number is hidden.
    private var totals: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "car.fill").font(.footnote.weight(.semibold))
                Text(RouteSample.totalDistanceLabel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            Divider().frame(height: 26)
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").font(.footnote.weight(.semibold))
                Text(RouteSample.totalDurationLabel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .hero,
                     state: .highlighted,
                     glow: RoutePlannerMockup.featureTint,
                     fillWidth: true)
    }

    /// PROPOSED — `skippedShipments` is decoded, counted and printed to the
    /// console today and surfaced nowhere (parity §3, item 3).
    private var skipNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.footnote.weight(.semibold))
                Text("2 schools skipped").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            ForEach(RouteSample.skipped, id: \.self) { name in
                Text("· \(name)").font(.caption)
            }
            Text("PROPOSED — the router already tells the app which schools it refused; today that list only reaches the console.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.orange)
        .ambientCard(density: .compact,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Route", trailing: "\(stops.count) stops")
            VStack(spacing: 0) {
                timelineRow(marker: .start,
                            isLast: false,
                            title: startLabel,
                            subtitle: "Starting point",
                            leg: RouteSample.legs.first)

                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    timelineRow(marker: .stop(index + 1),
                                isLast: endLabel == nil && index == stops.count - 1,
                                title: stop.name,
                                subtitle: stop.address,
                                leg: RouteSample.legs.count > index + 1
                                     ? RouteSample.legs[index + 1] : nil)
                }

                if let endLabel {
                    timelineRow(marker: .end,
                                isLast: true,
                                title: endLabel,
                                subtitle: "End point",
                                leg: nil)
                }
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    private enum Marker {
        case start
        case stop(Int)
        case end

        var color: Color {
            switch self {
            case .start: return .green
            case .stop: return .blue
            case .end: return .red
            }
        }
    }

    private func timelineRow(marker: Marker,
                             isLast: Bool,
                             title: String,
                             subtitle: String,
                             leg: LabRouteLeg?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            markerColumn(marker: marker, isLast: isLast)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Per-leg caption. Drawn even at zero — a leg that rounds to
                // "0.0 mi" disappears entirely today, so two stops at the same
                // school read as one.
                if let leg {
                    Text("\(leg.distanceLabel) · \(leg.durationLabel)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(RoutePlannerMockup.featureTint)
                        .padding(.top, 4)
                        .padding(.bottom, 10)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    /// The measured column. `dotRadius` is the ONLY constant: everything else —
    /// where the line starts, where it stops — is read off `proxy.size.height`.
    private func markerColumn(marker: Marker, isLast: Bool) -> some View {
        let dotRadius: CGFloat = 7
        return GeometryReader { proxy in
            let centerX = proxy.size.width / 2
            ZStack(alignment: .topLeading) {
                if !isLast {
                    Path { path in
                        path.move(to: CGPoint(x: centerX, y: dotRadius * 2))
                        path.addLine(to: CGPoint(x: centerX, y: proxy.size.height))
                    }
                    .stroke(Color.primary.opacity(0.18),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }

                markerDot(marker, radius: dotRadius)
                    .position(x: centerX, y: dotRadius)
            }
        }
    }

    @ViewBuilder
    private func markerDot(_ marker: Marker, radius: CGFloat) -> some View {
        switch marker {
        case .start, .end:
            Circle()
                .fill(marker.color)
                .frame(width: radius * 2, height: radius * 2)
        case .stop(let number):
            ZStack {
                Circle().fill(marker.color)
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: radius * 2 + 4, height: radius * 2 + 4)
        }
    }

    private var mapButtons: some View {
        HStack(spacing: 10) {
            Button {} label: {
                Label("Apple Maps", systemImage: "map.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // ambient-allow: a filled primary action is a control.
                    .background(Capsule().fill(RoutePlannerMockup.featureTint))
            }
            .buttonStyle(.plain)

            Button {} label: {
                Label("Google Maps", systemImage: "globe")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // ambient-allow: a secondary control, not a container.
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("There is no map, and cannot be one yet: the router is asked not to return a drawable route.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Durations are travel time only — the 5 minutes allowed at each school is not included. Both map buttons are dead in the lab.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Sample data

private struct LabRouteSchool: Identifiable {
    let id: String
    let name: String
    let address: String
    /// Two of the eight have none. That is the case the design exists to fix.
    let hasCoordinates: Bool
}

private struct LabRouteLeg {
    let miles: Double
    let minutes: Int

    var distanceLabel: String { String(format: "%.1f mi", miles) }
    var durationLabel: String { minutes == 0 ? "under a minute" : "\(minutes) min" }
}

private enum RouteSample {
    /// Addresses of deliberately varying length — the short one and the one that
    /// must truncate on a 375pt screen both have to read.
    static let schools: [LabRouteSchool] = [
        LabRouteSchool(id: "ws-1", name: "Northgate Elementary",
                       address: "412 Northgate Rd, Fairview", hasCoordinates: true),
        LabRouteSchool(id: "ws-2", name: "Cedar Valley Day School",
                       address: "8 Mill Ln", hasCoordinates: false),
        LabRouteSchool(id: "ws-3", name: "Westfield Consolidated High School",
                       address: "1900 West Westfield Township Boulevard, Suite 2, Westfield", hasCoordinates: true),
        LabRouteSchool(id: "ws-4", name: "Pinehurst Elementary",
                       address: "77 Pinehurst Ave, Bellmore", hasCoordinates: true),
        LabRouteSchool(id: "ws-5", name: "St. Bartholomew Academy",
                       address: "620 Chapel St, Old Town", hasCoordinates: true),
        LabRouteSchool(id: "ws-6", name: "Lakeshore Charter",
                       address: "Lot 4, County Rd 19", hasCoordinates: false),
        LabRouteSchool(id: "ws-7", name: "Riverbend Middle School",
                       address: "3300 Riverbend Pkwy, Ashford", hasCoordinates: true),
        LabRouteSchool(id: "ws-8", name: "Oakmont Prep",
                       address: "15 Oakmont Sq, Granton", hasCoordinates: true)
    ]

    static let optimizedStops: [LabRouteSchool] = [
        schools[0], schools[4], schools[2]
    ]

    /// One more leg than stops: start → 1, 1 → 2, 2 → 3.
    static let legs: [LabRouteLeg] = [
        LabRouteLeg(miles: 12.3, minutes: 24),
        LabRouteLeg(miles: 9.1, minutes: 18),
        LabRouteLeg(miles: 17.0, minutes: 30)
    ]

    static let totalDistanceLabel = "38.4 mi"
    static let totalDurationLabel = "1h 12m"

    static let skipped = ["Cedar Valley Day School", "Lakeshore Charter"]
}
