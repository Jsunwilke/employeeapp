//  RoutePlannerKit.swift
//  Iconik Employee — the Route Planner design, as production code
//
//  PRODUCTION CODE THAT THE LAB MOCKUP IMPORTS, the TimeOffKit.swift mechanism
//  (AMB.8) applied to the Route Planner: every piece the operator approved in
//  `DesignLab/Mockups/RoutePlannerMockup.swift` lives HERE, and both the real
//  screen and the mockup draw with it. There is no second copy, so there is
//  nothing to drift from — a conversion becomes "swap sample data for a service"
//  rather than "match a picture".
//
//  WHAT IS DELIBERATELY NOT HERE: anything that knows about Supabase, a `School`
//  row, or `RouteOptimizerService`. These take plain values and plain strings, so
//  the lab feeds them sample data and `RoutePlannerView` feeds them a service
//  result, and neither owns the other.
//
//  THE FORMATTING LIVES HERE TOO (`RoutePlannerFormat`), and that is load-bearing
//  rather than tidy: `RouteLeg.formattedDuration` used to do `Int(durationMinutes)`,
//  so 59.6 minutes read "59 min" — a truncation the mockup did not have. One
//  formatter both sides call cannot disagree about that.

import SwiftUI

// MARK: - Identity

enum RoutePlannerStyle {
    /// The "On the road" family the Route Planner shares with Mileage. Read from
    /// FeatureTheme rather than restated, so the tile you tap and the screen you
    /// land on cannot disagree.
    static var tint: Color { FeatureTheme.color(for: "routePlanner") }
}

// MARK: - Formatting

/// ONE place that turns miles and minutes into words.
enum RoutePlannerFormat {
    /// A genuinely zero leg reads "0.0 mi" rather than vanishing. The old preview
    /// hid the whole caption whenever `distanceMeters == 0`, so two stops at the
    /// same address read as one stop.
    static func distance(miles: Double) -> String {
        String(format: "%.1f mi", miles)
    }

    /// ROUNDED, NOT TRUNCATED. `Int(59.6)` is 59, and a route that takes 59.6
    /// minutes does not take 59 of them.
    static func duration(minutes: Double) -> String {
        let whole = Int(minutes.rounded())
        if whole == 0 { return "under a minute" }
        if whole < 60 { return "\(whole) min" }
        return "\(whole / 60)h \(whole % 60)m"
    }

    /// The per-leg caption — "12.3 mi · 24 min".
    static func leg(miles: Double, minutes: Double) -> String {
        "\(distance(miles: miles)) · \(duration(minutes: minutes))"
    }
}

// MARK: - Warning line

/// The orange line the live screen already shows for an address that is not set.
/// Attached to the option it is about rather than floating under the picker.
struct RoutePlannerWarningLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2.weight(.semibold))
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.orange)
    }
}

// MARK: - Search

/// Hand-rolled, as the app's already is: `.searchable` is out at the iOS 16.6
/// floor for this shell, and the live filter searches name and address only,
/// which this repeats rather than quietly widening (widening it is a data change).
struct RouteSearchCard: View {
    @Binding var text: String
    var placeholder: String = "Search schools"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.footnote).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .font(.subheadline)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.footnote).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

// MARK: - Start and end

/// The "Route" form section: where the day starts, and optionally where it ends.
///
/// Options arrive as plain strings so the lab and the app label them identically
/// without this file knowing what a `StartingPointType` is; the warnings arrive
/// resolved, so the rule about WHICH option is unavailable stays with whoever
/// knows the addresses.
struct RouteEndpointsSection: View {
    let status: String
    var statusTint: Color?

    let startOptions: [String]
    @Binding var start: String?
    /// Nil when the chosen start is available.
    var startWarning: String?

    @Binding var addsEndPoint: Bool
    let endOptions: [String]
    @Binding var end: String?
    var endWarning: String?
    /// The live screen disables the toggle when NEITHER address is available.
    var endPointDisabled: Bool = false
    /// The guidance line the live screen shows in that case.
    var endPointNote: String?

    var tint: Color = RoutePlannerStyle.tint

    var body: some View {
        AmbientFormSection(title: "Route", status: status, statusTint: statusTint) {
            VStack(alignment: .leading, spacing: 12) {
                AmbientChoiceRow(title: "Start from",
                                 options: startOptions,
                                 selection: $start,
                                 tint: tint)

                if let startWarning {
                    RoutePlannerWarningLine(text: startWarning)
                }

                Divider()

                Toggle(isOn: $addsEndPoint) {
                    Text("Add end point").font(.subheadline.weight(.semibold))
                }
                .tint(tint)
                .disabled(endPointDisabled)

                if let endPointNote {
                    RoutePlannerWarningLine(text: endPointNote)
                }

                if addsEndPoint {
                    AmbientChoiceRow(title: "End at",
                                     options: endOptions,
                                     selection: $end,
                                     tint: tint)
                    if let endWarning {
                        RoutePlannerWarningLine(text: endWarning)
                    }
                }
            }
        }
    }
}

// MARK: - The school list

/// PLAIN VALUES. The lab builds these from sample data; the screen builds them
/// from `School`.
struct RouteSchoolRowModel: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    /// False when the school has no coordinates. Such a school CANNOT be
    /// selected — the design's second claim. Before this it was tickable, was
    /// counted in "3 selected", and was then dropped by the optimizer's
    /// `validSchools` filter with no notice anywhere.
    let isRoutable: Bool
}

struct RouteSchoolRow: View {
    let model: RouteSchoolRowModel
    let isSelected: Bool
    var tint: Color = RoutePlannerStyle.tint
    var onToggle: () -> Void

    var body: some View {
        Button {
            guard model.isRoutable else { return }
            onToggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(model.isRoutable
                                     ? (isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                                     : AnyShapeStyle(.quaternary))

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .font(AmbientDensity.compact.titleFont)
                        .lineLimit(1)
                    Text(model.address)
                        .font(AmbientDensity.compact.subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !model.isRoutable {
                        AmbientBadge(text: "No map pin — can't be routed",
                                     systemImage: "mappin.slash", tint: .orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .opacity(model.isRoutable ? 1 : 0.55)
            .ambientCard(density: .compact,
                         border: isSelected ? .hairline(tint.opacity(0.5)) : .none,
                         fillWidth: true)
        }
        .buttonStyle(.plain)
        .disabled(!model.isRoutable)
    }
}

// MARK: - The bottom bar — always present

/// THE DESIGN'S FIRST CLAIM: the Optimize button must not vanish.
///
/// The live screen renders the whole bottom bar only at two or more selections —
/// below two there is no button, no caption and no explanation. A control that
/// disappears teaches nothing; a disabled control with a reason teaches the rule
/// in one glance.
struct RouteOptimizeBar: View {
    let enabled: Bool
    let isOptimizing: Bool
    /// Drawn under the button whenever it is disabled for a reason worth naming.
    var caption: String?
    var tint: Color = RoutePlannerStyle.tint
    var action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 8) {
                    if isOptimizing {
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
                .background(Capsule().fill(enabled ? tint : Color.gray.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .disabled(!enabled || isOptimizing)

            if let caption {
                Text(caption)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Totals

/// Drawn UNCONDITIONALLY. The live totals pill is gated on distance > 0, which is
/// exactly the condition a failed optimization produced — so the one time the user
/// most needed to be told something was wrong, the number was hidden.
struct RouteTotalsHero: View {
    let distanceLabel: String
    let durationLabel: String
    var tint: Color = RoutePlannerStyle.tint

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "car.fill").font(.footnote.weight(.semibold))
                Text(distanceLabel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            Divider().frame(height: 26)
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").font(.footnote.weight(.semibold))
                Text(durationLabel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .hero, state: .highlighted, glow: tint, fillWidth: true)
    }
}

// MARK: - Skipped schools

/// The router already tells the app which schools it refused; before this the list
/// only reached the console (`skippedShipments`, decoded, counted, printed).
struct RouteSkippedNotice: View {
    let names: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.footnote.weight(.semibold))
                Text(names.count == 1 ? "1 school skipped" : "\(names.count) schools skipped")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            ForEach(names, id: \.self) { name in
                Text("· \(name)")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("The router could not fit these into the route, so they are not stops on it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.orange)
        .ambientCard(density: .compact,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
    }
}

// MARK: - The timeline

enum RouteTimelineMarker: Equatable {
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

struct RouteTimelineEntry: Identifiable, Equatable {
    let id: String
    let marker: RouteTimelineMarker
    let title: String
    let subtitle: String
    /// The leg LEAVING this row — "12.3 mi · 24 min". Nil on the last row.
    let legLabel: String?

    init(id: String, marker: RouteTimelineMarker, title: String, subtitle: String, legLabel: String? = nil) {
        self.id = id
        self.marker = marker
        self.title = title
        self.subtitle = subtitle
        self.legLabel = legLabel
    }
}

/// The result, as a timeline. There is no map and there cannot be one — no
/// polyline is requested from the server and MapKit is not imported — so the
/// design commits to the honest form.
///
/// EVERY POSITION IS DERIVED FROM MEASURED HEIGHT: each row's marker column is a
/// `GeometryReader`, the dot sits one radius down from the row's top edge, and the
/// connector runs from there to the measured bottom. A stack of constant offsets
/// drifts apart from the dots at the largest Dynamic Type size — the AMB.11
/// geometry lesson.
struct RouteTimeline: View {
    let entries: [RouteTimelineEntry]
    var tint: Color = RoutePlannerStyle.tint

    private var stopCount: Int {
        entries.filter { if case .stop = $0.marker { return true } else { return false } }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Route", trailing: stopCount == 1 ? "1 stop" : "\(stopCount) stops")
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, isLast: index == entries.count - 1)
                }
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    private func row(_ entry: RouteTimelineEntry, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            markerColumn(marker: entry.marker, isLast: isLast)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let legLabel = entry.legLabel {
                    Text(legLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
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
    private func markerColumn(marker: RouteTimelineMarker, isLast: Bool) -> some View {
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
    private func markerDot(_ marker: RouteTimelineMarker, radius: CGFloat) -> some View {
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
}

// MARK: - Handing the route to a map app

struct RouteMapButtons: View {
    var tint: Color = RoutePlannerStyle.tint
    var openAppleMaps: () -> Void
    var openGoogleMaps: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: openAppleMaps) {
                Label("Apple Maps", systemImage: "map.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // ambient-allow: a filled primary action is a control.
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)

            Button(action: openGoogleMaps) {
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
}

// MARK: - Footnote

/// Two facts about the numbers above, both true in production.
struct RoutePreviewFootnote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("There is no map, and cannot be one yet: the router is asked not to return a drawable route.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Durations are travel time only — the 5 minutes allowed at each school is not included.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Failure

/// A FAILED OPTIMIZATION MUST NOT LOOK LIKE SUCCESS — the design's third claim.
/// Before this, no `optimizedOrder` meant the service handed back the user's own
/// list with `totalDistanceMiles: 0`, and the `> 0` gate then hid the totals, so
/// the preview opened on an unoptimized list with nothing saying it had failed.
/// Now the preview is not pushed at all and this card carries the server's words.
struct RouteFailureCard: View {
    let message: String
    /// What to do instead, when Retry would not run. RETRY IS OFFERED ONLY WHEN IT
    /// WILL ACTUALLY OPTIMIZE: the caller's `optimizeRoute()` guard-returns unless
    /// two routable schools and a start are selected, so a Retry drawn in that
    /// situation cleared the error and did nothing — the failure read as dismissed
    /// and the route was never planned. The caller passes this line instead.
    var hint: String?
    var tint: Color = RoutePlannerStyle.tint
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn't optimize this route").font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let retry {
                Button(action: retry) {
                    Text("Retry")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        // ambient-allow: a control, not a card.
                        .background(Capsule().fill(tint))
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
    }
}
