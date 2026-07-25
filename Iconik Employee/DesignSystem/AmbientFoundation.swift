//  AmbientFoundation.swift
//  Iconik Employee — the Ambient design language, foundation layer
//
//  Promoted out of Schedule/ScheduleStyleKit.swift in AMB.2 (2026-07-25). These
//  are the pieces that were never about shifts: density, motion, feedback, the
//  ambient wash, deterministic identity colours, and the iOS 16.6 availability
//  wrappers. The schedule keeps only what is genuinely about a shift.
//
//  Everything here is iOS 16.6-safe. Post-16 APIs go through the wrappers at the
//  bottom, which apply the modern treatment on iOS 17+ and no-op below.

import SwiftUI
import UIKit

// MARK: - Density

/// How tightly a surface is packed.
///
/// Ambient was designed on the schedule, where a photographer sees a handful of
/// items a day and glass and generous spacing read as calm. The same treatment
/// on a 300-row equipment list reads as slow and airy, so every container
/// primitive carries a compact sibling rather than leaving each screen to invent
/// its own tightening (AMB plan, D5).
///
/// The three steps are intent, not arbitrary numbers:
///
///   hero     one thing, the screen's opening statement — the countdown card
///   roomy    a browsable list of a handful of items — the schedule's day rows
///   compact  a dense list you scan rather than read — equipment, tasks, chat
///
/// `compact`'s numbers are taken from Equipment's real row (its card is
/// horizontal 12 / vertical 10 at radius 12), so converting Equipment in AMB.3
/// is a change of vocabulary rather than a change of size.
enum AmbientDensity: CaseIterable {
    case hero, roomy, compact

    var horizontalPadding: CGFloat {
        switch self {
        case .hero: return 18
        case .roomy: return 16
        case .compact: return 12
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .hero: return 18
        case .roomy: return 16
        case .compact: return 10
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .hero: return 24
        case .roomy: return 22
        case .compact: return 14
        }
    }

    /// Vertical rhythm between lines inside a card.
    var contentSpacing: CGFloat {
        switch self {
        case .hero: return 10
        case .roomy: return 7
        case .compact: return 3
        }
    }

    /// Gap between sibling cards in a list.
    var stackSpacing: CGFloat {
        switch self {
        case .hero: return 16
        case .roomy: return 12
        case .compact: return 8
        }
    }

    /// Primary line — the one thing you read when scanning.
    var titleFont: Font {
        switch self {
        case .hero: return .system(size: 19, weight: .semibold)
        case .roomy: return .system(size: 17, weight: .semibold)
        case .compact: return .system(size: 15, weight: .semibold)
        }
    }

    var subtitleFont: Font {
        switch self {
        case .hero: return .subheadline
        case .roomy: return .footnote
        case .compact: return .caption
        }
    }
}

// MARK: - Motion & feedback

enum AmbientMotion {
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let gentle = Animation.spring(response: 0.45, dampingFraction: 0.85)
}

enum AmbientHaptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Identity

/// Deterministic colour and initials for a person or a thing, so the same name
/// is the same colour everywhere — across launches, and between two devices
/// looking at the same crew.
enum AmbientStyle {

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    static func avatarColor(_ seed: String) -> Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .teal, .green, .orange, .mint]
        return palette[Int(stableHash(seed) % UInt64(palette.count))]
    }

    /// FNV-1a. `String.hashValue` is seeded per process, so it cannot deliver a
    /// colour that survives a relaunch. This is a plain hash over the bytes:
    /// stable across processes and devices, and never negative — so there is no
    /// `abs()` trap on `Int.min` either.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

// MARK: - Surfaces

/// The ambient wash: two soft blooms of a tint behind the page. The tint comes
/// from whatever the screen is about — the job in front of you on the schedule —
/// so the background agrees with the content instead of being decoration.
struct AmbientBackdrop: View {
    let tint: Color

    var body: some View {
        ZStack {
            Color(.systemBackground)
            Circle().fill(tint.opacity(0.55)).frame(width: 420, height: 420)
                .blur(radius: 120).offset(x: -110, y: -260)
            Circle().fill(tint.opacity(0.28)).frame(width: 360, height: 360)
                .blur(radius: 140).offset(x: 140, y: 120)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: tint)
    }
}

/// Rounded on the top corners only — for bars anchored to the bottom edge.
struct TopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                              control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                              control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - Layout

/// Wrapping row (iOS 16 `Layout`). Pills wrap rather than truncating at an
/// arbitrary count, because the things being labelled are user-defined and a
/// single item can carry several.
struct AmbientFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing; x = 0; lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing; x = bounds.minX; lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - iOS 16.6-safe wrappers

extension View {
    /// Fades and shrinks cells as they leave the viewport (iOS 17+).
    @ViewBuilder
    func ambientScrollFade(minOpacity: Double = 0.4, minScale: CGFloat = 0.92) -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTransition(.interactive) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : minOpacity)
                    .scaleEffect(phase.isIdentity ? 1 : minScale)
            }
        } else { self }
    }

    @ViewBuilder
    func ambientNoBounceWhenShort() -> some View {
        if #available(iOS 16.4, *) { self.scrollBounceBehavior(.basedOnSize) } else { self }
    }

    /// Snap-to-cell horizontal carousel with inset content (iOS 17+). Below 17 the
    /// scroll is free rather than snapping, which reads fine — the cells are the
    /// same width either way.
    ///
    /// Restored to the design system 2026-07-25: the schedule's day strip needs it,
    /// and so will any horizontally paged row Equipment or Chat grows. It existed in
    /// the design lab and was lost when the vocabulary was promoted.
    @ViewBuilder
    func ambientCarousel(margin: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, margin, for: .scrollContent)
        } else {
            self.padding(.horizontal, margin)
        }
    }

    /// Marks the cells a carousel snaps to (iOS 17+).
    @ViewBuilder
    func ambientScrollTargets() -> some View {
        if #available(iOS 17.0, *) { self.scrollTargetLayout() } else { self }
    }

    /// Stretch on over-scroll (iOS 17+).
    @ViewBuilder
    func ambientParallax(_ amount: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.visualEffect { content, proxy in
                let y = proxy.frame(in: .scrollView).minY
                return content.offset(y: y > 0 ? -y * amount : 0)
            }
        } else { self }
    }

    /// Push an optional item.
    ///
    /// Uses `NavigationLink(isActive:)` — deprecated in iOS 16, but the ONLY
    /// push API that works in both containers. The app shell hands most features
    /// a `NavigationView` (MainEmployeeView.featureContainer, per NAV.1's one bar
    /// per screen), and `navigationDestination` is a `NavigationStack`-only
    /// modifier: inside a `NavigationView` it is silently ignored, so the tap
    /// registers and nothing happens. That was the first bug AMB.1 shipped, and
    /// it is the reason every Ambient surface pushes through this one wrapper.
    func ambientPush<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        background(
            NavigationLink(
                isActive: Binding(
                    get: { item.wrappedValue != nil },
                    set: { if !$0 { item.wrappedValue = nil } }
                ),
                destination: {
                    if let value = item.wrappedValue { destination(value) }
                },
                label: { EmptyView() }
            )
            .hidden()
        )
    }
}
