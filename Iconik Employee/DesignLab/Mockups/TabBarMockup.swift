//  TabBarMockup.swift
//  Iconik Employee — AMB.4's third mockup
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  WHY IT EXISTS
//      The operator asked why the bottom bar had not been redesigned, and the
//      answer was that it belonged to no phase: the arc's phase list is organised
//      by FEATURE, and the bar is nav-shell furniture from NAV.1 that sits on
//      every screen. The card-drift gate could not have caught it either — a
//      full-width bar is not a rounded-and-filled container, so the rule driving
//      this arc's conversions is blind to it by construction.
//
//      Operator decision, 2026-07-25: it joins AMB.4, with the main screen, and
//      before any other feature.
//
//  THE ONE THING TO LOOK AT
//      The REAL bar is on screen right now, underneath this page — it is on every
//      screen. So the proposed bar below sits directly above the live one, and
//      the comparison is immediate. That is the whole point of mocking this
//      surface in situ rather than in isolation.
//
//  WHAT CHANGES, AND WHY EACH ONE
//      1. MATERIAL INSTEAD OF AN OPAQUE SLAB. Today the bar is a solid
//         systemBackground with a drop shadow, so the ambient wash stops dead at
//         its top edge. It becomes glass over a top-rounded shape, which is what
//         TopRoundedRectangle in the design system was built for and has had no
//         caller until now.
//      2. THE REAL FEATURE COLOURS. The live bar does NOT read FeatureTheme —
//         TabBarButton.accentColor is a fourth hardcoded map covering seven ids
//         and defaulting everything else to blue. So the tile you tap and the bar
//         item you land on disagree for nearly every feature. Fixing it means two
//         VISIBLE colour changes worth saying out loud rather than slipping in:
//         Scan goes from orange to the palette's #2AA7D8, and Time goes from a
//         flat cyan to the palette's teal. Everything currently falling through
//         to blue takes its own colour for the first time.
//      3. ITEMS THAT FLEX. Buttons are a fixed 50pt today and the spacers are
//         minimums, so at the six items the customise screen allows the bar is
//         438pt wide — wider than any iPhone. Flexible widths remove the cliff.
//      4. THE iPAD HOME CIRCLE takes the company blue rather than Apple's default
//         blue, matching the dashboard's wash. Home is the container, not a
//         feature, so it takes the brand colour (D11).
//
//  WHAT DOES NOT CHANGE
//      Both device layouts and everything that makes them different: Scan stays a
//      permanent centre button on iPhone and stays absent on iPad; the iPad keeps
//      its prominent centre Home, its upward overflow, and the notch in the top
//      hairline. The sliding underline, the badges, the haptics and the labels
//      all stay.

import SwiftUI

/// The two genuinely different bars. Shared with `LabTabBar` so the mockup and
/// the thing it draws cannot disagree about which layout is which.
enum TabBarMockupLayout: String, CaseIterable, Identifiable {
    case iPhone, iPad
    var id: String { rawValue }
}

struct TabBarMockup: View {
    private typealias Layout = TabBarMockupLayout

    @State private var layout: Layout =
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    @State private var itemCount: Double = 4
    @State private var showLabels = true
    @State private var selected = "chat"
    @State private var unread = 3
    @State private var clockedIn = true

    /// The features a bar can carry, in the order the default configuration uses
    /// them. Ids are the REAL feature ids, so FeatureTheme returns the colour the
    /// converted bar would actually use.
    private let catalogue: [(id: String, title: String, symbol: String)] = [
        ("timeTracking", "Time", "clock.fill"),
        ("chat", "Chat", "bubble.left.and.bubble.right.fill"),
        ("photoshootNotes", "Notes", "note.text"),
        ("schedule", "Schedule", "calendar"),
        ("equipment", "Equipment", "camera.fill"),
        ("tasks", "Tasks", "checklist"),
    ]

    private var items: [(id: String, title: String, symbol: String)] {
        Array(catalogue.prefix(Int(itemCount)))
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: AmbientStyle.brand, intensity: 0.9)

            VStack(spacing: 14) {
                ScrollView {
                    VStack(spacing: 14) {
                        controls
                        comparison
                        colourNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }

                // The proposal, in the position it really occupies. The live bar
                // is immediately below it.
                VStack(spacing: 6) {
                    Text("PROPOSED — the live bar is directly below this")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    proposedBar
                }
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Layout", selection: $layout) {
                ForEach(Layout.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Text("Both layouts render on whichever device you are holding, because they are genuinely different bars and you should be able to judge each one on both screens.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Items besides Scan")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text("\(Int(itemCount))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Int(itemCount) >= 5 ? .orange : .secondary)
            }
            Slider(value: $itemCount, in: 2...6, step: 1)
                .tint(AmbientStyle.brand)

            Text("Six is what the customise screen allows today. Drag to six on the iPhone layout and compare the two bars below: the live one runs off the screen edge, the proposal does not.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Show labels", isOn: $showLabels)
                .font(.footnote.weight(.semibold))
                .tint(AmbientStyle.brand)
            Toggle("Clocked in (green dot on Time)", isOn: $clockedIn)
                .font(.footnote.weight(.semibold))
                .tint(AmbientStyle.brand)

            Stepper("Unread messages: \(unread)", value: $unread, in: 0...120)
                .font(.footnote.weight(.semibold))
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    // MARK: - Before and after

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Today", trailing: "opaque")
            LabTabBar(items: items, layout: layout, selected: $selected,
                      showLabels: showLabels, unread: unread,
                      clockedIn: clockedIn, ambient: false)

            AmbientSectionTitle("Proposed", trailing: "glass")
            LabTabBar(items: items, layout: layout, selected: $selected,
                      showLabels: showLabels, unread: unread,
                      clockedIn: clockedIn, ambient: true)

            Text("Tap items in either bar — the underline travels between them, which is behaviour the live bar loses every time a message arrives (it rebuilds itself on the unread count).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var colourNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("The two colours that visibly change")
            ForEach(["scan", "timeTracking"], id: \.self) { id in
                HStack(spacing: 10) {
                    Circle().fill(id == "scan" ? Color.orange : Color.cyan)
                        .frame(width: 18, height: 18)
                    Image(systemName: "arrow.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Circle().fill(FeatureTheme.color(for: id))
                        .frame(width: 18, height: 18)
                    Text(id == "scan" ? "Scan" : "Time")
                        .font(.footnote.weight(.medium))
                    Spacer()
                    Text(id == "scan" ? "orange → palette blue" : "flat cyan → palette teal")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("Everything else that currently falls through to blue — Schedule, Tasks, Groups and the rest — takes its own colour for the first time, matching its home tile.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var proposedBar: some View {
        LabTabBar(items: items, layout: layout, selected: $selected,
                  showLabels: showLabels, unread: unread,
                  clockedIn: clockedIn, ambient: true)
    }
}

// MARK: - The bar itself

/// Draws the bar either as it is today (`ambient: false`) or as proposed
/// (`ambient: true`), from the same structure, so the two are genuinely
/// comparable rather than two separate drawings that drifted.
private struct LabTabBar: View {
    let items: [(id: String, title: String, symbol: String)]
    let layout: TabBarMockupLayout
    @Binding var selected: String
    let showLabels: Bool
    let unread: Int
    let clockedIn: Bool
    let ambient: Bool

    @Namespace private var namespace

    var body: some View {
        content
            .padding(.top, 7)
            .padding(.horizontal, 4)
            .padding(.bottom, ambient ? 10 : 10)
            .background(background)
            .overlay(topEdge, alignment: .top)
            .clipped()
    }

    @ViewBuilder
    private var background: some View {
        if ambient {
            // Glass, so the ambient wash carries under the bar instead of
            // stopping at its top edge. TopRoundedRectangle has been in the
            // design system since AMB.2 for exactly this and had no caller.
            TopRoundedRectangle(radius: 22)
                .fill(.ultraThinMaterial)
        } else {
            // ambient-allow: this is the BEFORE half of a before/after, drawn to
            // match the live bar exactly (opaque slab + upward drop shadow).
            Color(.systemBackground)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
        }
    }

    @ViewBuilder
    private var topEdge: some View {
        let line = Color(.separator).opacity(ambient ? 0.45 : 1)
        if layout == .iPad {
            // The notch around the centre Home circle. NAV.1 shipped this and it
            // survives the conversion.
            HStack(spacing: 0) {
                Rectangle().fill(line).frame(height: 0.5)
                Color.clear.frame(width: 92, height: 0.5)
                Rectangle().fill(line).frame(height: 0.5)
            }
        } else {
            Rectangle().fill(line).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var content: some View {
        if layout == .iPad {
            HStack(alignment: .bottom, spacing: 0) {
                let mid = (items.count + 1) / 2
                HStack(spacing: 0) {
                    ForEach(Array(items.prefix(mid)), id: \.id) { item in
                        button(item).frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)

                homeCircle

                HStack(spacing: 0) {
                    ForEach(Array(items.dropFirst(mid)), id: \.id) { item in
                        button(item).frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 0) {
                let mid = (items.count + 1) / 2
                ForEach(Array(items.prefix(mid)), id: \.id) { item in
                    // Flexible on the proposal, the live bar's fixed 50pt on the
                    // "today" side — which is what makes it overflow at six.
                    button(item).modifier(ItemWidth(flexible: ambient, width: 50))
                }

                scanButton
                    .modifier(ItemWidth(flexible: ambient, width: 70))

                ForEach(Array(items.dropFirst(mid)), id: \.id) { item in
                    button(item).modifier(ItemWidth(flexible: ambient, width: 50))
                }
            }
        }
    }

    // MARK: pieces

    private func tint(_ id: String) -> Color {
        // The proposal reads the single source of truth. "Today" reproduces
        // TabBarButton.accentColor verbatim, including its fall-through to blue,
        // so the before/after shows the real disagreement rather than a flattering
        // version of it.
        if ambient { return FeatureTheme.color(for: id) }
        switch id {
        case "timeTracking": return .cyan
        case "chat": return .blue
        case "scan": return .orange
        case "photoshootNotes": return .purple
        case "dailyJobReport": return .green
        case "sportsShoot": return .indigo
        case "equipment": return .cyan
        default: return .blue
        }
    }

    private func button(_ item: (id: String, title: String, symbol: String)) -> some View {
        let isSelected = selected == item.id
        let accent = tint(item.id)
        return Button {
            withAnimation(AmbientMotion.snappy) { selected = item.id }
            AmbientHaptics.impact(.light)
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.symbol)
                        .font(.system(size: layout == .iPad ? 30 : 24))
                        .foregroundStyle(isSelected ? accent : Color.secondary)
                        .scaleEffect(isSelected ? 1.1 : 1)

                    if item.id == "chat", unread > 0 {
                        Text(unread > 99 ? "99+" : "\(unread)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 12, y: -8)
                    } else if item.id == "timeTracking", clockedIn {
                        Circle().fill(Color.green)
                            .frame(width: 8, height: 8)
                            .offset(x: 10, y: -6)
                    }
                }
                .frame(width: layout == .iPad ? 60 : 44, height: layout == .iPad ? 45 : 32)

                if showLabels {
                    Text(item.title)
                        .font(.system(size: layout == .iPad ? 12 : 10))
                        .foregroundStyle(isSelected ? accent : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 20, height: 3)
                        .matchedGeometryEffect(id: "tabSelection", in: namespace)
                } else {
                    Color.clear.frame(width: 20, height: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scanButton: some View {
        let isSelected = selected == "scan"
        let accent = tint("scan")
        return Button {
            withAnimation(AmbientMotion.snappy) { selected = "scan" }
            AmbientHaptics.impact(.medium)
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accent : Color.gray.opacity(0.2))
                        .frame(width: 50, height: 50)
                    // The glyph deliberately overflows its circle — the live bar
                    // does this on purpose and the code says so.
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                }
                .frame(width: 50, height: 50)
                if showLabels { Color.clear.frame(height: 12) }
                Color.clear.frame(width: 20, height: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var homeCircle: some View {
        let isSelected = selected == "home"
        return Button {
            withAnimation(AmbientMotion.snappy) { selected = "home" }
            AmbientHaptics.impact(.medium)
        } label: {
            ZStack {
                Circle()
                    // Company blue rather than Apple's default. Home is the
                    // container, not a feature, so it takes the brand colour —
                    // the same reasoning that gives the dashboard its wash.
                    .fill(isSelected ? (ambient ? AmbientStyle.brand : Color.blue)
                                     : Color(.systemGray5))
                    .frame(width: 78, height: 78)
                    .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 1.5))
                Image(systemName: "house.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.gray)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Home")
        .frame(width: 84, height: 44, alignment: .bottom)
    }
}

/// Fixed width reproduces today's overflow; flexible is the proposal.
private struct ItemWidth: ViewModifier {
    let flexible: Bool
    let width: CGFloat

    func body(content: Content) -> some View {
        if flexible {
            content.frame(maxWidth: .infinity)
        } else {
            content.frame(width: width)
        }
    }
}

