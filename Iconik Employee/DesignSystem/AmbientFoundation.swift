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
    /// A chat message bubble. Added in AMB.6 with the tinted fill (see
    /// `AmbientCardFill`) so Chat could stop hand-rolling one.
    ///
    /// It is NOT in `allCases`, which is given explicitly below: the three list
    /// densities are a spectrum a surface chooses along, and the specimen
    /// sheet's density switch walks them. A bubble is not a point on that
    /// spectrum — offering it there would invite a list to be drawn as bubbles.
    case bubble

    /// Explicit, so `.bubble` stays out of density pickers and specimen sweeps.
    static var allCases: [AmbientDensity] { [.hero, .roomy, .compact] }

    var horizontalPadding: CGFloat {
        switch self {
        case .hero: return 18
        case .roomy: return 16
        case .compact: return 12
        case .bubble: return 12
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .hero: return 18
        case .roomy: return 16
        case .compact: return 10
        case .bubble: return 8
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .hero: return 24
        case .roomy: return 22
        case .compact: return 14
        case .bubble: return 16
        }
    }

    /// Vertical rhythm between lines inside a card.
    var contentSpacing: CGFloat {
        switch self {
        case .hero: return 10
        case .roomy: return 7
        case .compact: return 3
        case .bubble: return 3
        }
    }

    /// Gap between sibling cards in a list.
    var stackSpacing: CGFloat {
        switch self {
        case .hero: return 16
        case .roomy: return 12
        case .compact: return 8
        case .bubble: return 2
        }
    }

    /// Primary line — the one thing you read when scanning.
    var titleFont: Font {
        switch self {
        case .hero: return .system(size: 19, weight: .semibold)
        case .roomy: return .system(size: 17, weight: .semibold)
        case .compact: return .system(size: 15, weight: .semibold)
        case .bubble: return .system(size: 15, weight: .semibold)
        }
    }

    var subtitleFont: Font {
        switch self {
        case .hero: return .subheadline
        case .roomy: return .footnote
        case .compact: return .caption
        case .bubble: return .caption
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

    /// The company blue, taken from the Iconik logo (Logo.svg, the only place it
    /// was ever written down — the app's AccentColor asset is empty, so the app
    /// has been running on the system default blue). Used where a surface needs
    /// to feel like THIS app rather than like one of its features.
    static let brand = Color(hex: "#009AE2")

    /// THE wash — the one background colour the whole app is washed in (D14,
    /// operator 2026-07-30). It is the WEB app's aura blue, hsl(203 100% 37%)
    /// ≈ #0074BD, written down in the web repo's `src/styles/variables.css`;
    /// the web is standardising every page on that aura, so using the same
    /// value here makes the two apps read as one product.
    ///
    /// It is deliberately NOT `brand` (the logo blue, #009AE2): brand is what
    /// marks a control as belonging to this app, and the two live at different
    /// jobs. D14 supersedes D11 for BACKGROUNDS only — feature accents (tiles,
    /// icons, bar pills, badges) keep their own colours.
    static let wash = Color(hex: "#0074BD")

    /// What the wash turns when the signed-in photographer is flagged (D14).
    /// The system red, so it stays legible in both light and dark. This is the
    /// ONE red wash in the app; no feature may wash a screen red.
    static let flagged = Color.red

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

/// The ambient wash: two soft blooms of a tint behind the page.
///
/// D14 (operator, 2026-07-30) settled what that tint is: ONE colour for the
/// whole app — `AmbientStyle.wash`, the web app's aura blue — so the app stops
/// changing colour by feature and reads as the same product as the web. Every
/// production screen therefore calls this with no arguments at all.
///
/// The `tint` parameter survives for the design lab, whose specimen and palette
/// sheets exist precisely to show colours side by side.
///
/// RED MEANS FLAGGED. When the signed-in photographer is flagged, the wash turns
/// red app-wide, whatever tint was passed. That happens HERE, once, because this
/// is the one view every washed screen already goes through — count stores, not
/// call sites (the PUB.1 lesson). `UserFlagState.shared` is that one store.
struct AmbientBackdrop: View {
    var tint: Color = AmbientStyle.wash
    /// How loud the wash is. 1.0 is the schedule's — appropriate when the tint
    /// MEANS something and the page has few things on it.
    ///
    /// Turn it down for a page that carries a lot of its own colour. The home
    /// dashboard is the case that forced this: a full-strength wash behind nine
    /// coloured feature tiles fights every one of them, but no wash at all
    /// leaves the cards the same colour as the page they sit on.
    var intensity: Double = 1

    @ObservedObject private var flagState = UserFlagState.shared

    /// Explicit, because the `@ObservedObject` above would otherwise drag the
    /// store into the memberwise initialiser and make it private.
    init(tint: Color = AmbientStyle.wash, intensity: Double = 1) {
        self.tint = tint
        self.intensity = intensity
    }

    private var effectiveTint: Color { flagState.isFlagged ? AmbientStyle.flagged : tint }

    /// Flagged runs at full strength no matter what the screen asked for — a
    /// 0.3 red is a smudge, and this is the one state that has to be visible
    /// from across a room.
    private var effectiveIntensity: Double { flagState.isFlagged ? 1 : intensity }

    var body: some View {
        ZStack {
            Color(.systemBackground)
            Circle().fill(effectiveTint.opacity(0.55 * effectiveIntensity)).frame(width: 420, height: 420)
                .blur(radius: 120).offset(x: -110, y: -260)
            Circle().fill(effectiveTint.opacity(0.28 * effectiveIntensity)).frame(width: 360, height: 360)
                .blur(radius: 140).offset(x: 140, y: 120)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: effectiveTint)
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

    // GIVE THIS A DEFINITE WIDTH. Put it in a VStack, or pin it with
    // `.frame(maxWidth: .infinity, alignment: .leading)` — never bare inside an
    // HStack.
    //
    // WHY, found on a device at AMB.12 and worth the warning because it fails
    // SILENTLY and it fails as a DEAD TAP rather than as a wrong picture. An
    // HStack measures its children with an unspecified width. `proposal.width`
    // is then nil, this reports the size of ONE long line, and the HStack hands
    // back a share based on that — after which `placeSubviews` gets the real,
    // narrower bounds and wraps onto two lines that extend BELOW the frame the
    // parent reserved. The chips still draw. The control sitting next to them
    // still draws. But the overflowing row is outside its own frame, so it eats
    // the taps meant for its neighbour: on the Training screen the layout
    // toggle beside the filter chips opened a critique instead of switching to
    // the list.
    //
    // Every production call site was checked when this was found — all the
    // others sit in a VStack, which proposes a definite width, so this is a note
    // rather than a fix. Fixing it inside the layout would mean changing what it
    // reports for an unspecified proposal, which moves pixels on eight already
    // shipped surfaces to protect against a call shape nothing currently uses.

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
