//  AmbientCard.swift
//  Iconik Employee — the Ambient design language, card container
//
//  The one card in the app.
//
//  This exists because the last attempt did not. `cardStyle()` was written
//  during the audit roadmap's Phase 3 and NOTHING EVER CALLED IT — the app went
//  on hand-rolling 115 card backgrounds across 39 files. The lesson was not
//  "write a design system"; that was done and it failed. So this file ships with
//  a build gate beside it (scripts/check_card_drift.py) that fails a write which
//  hand-rolls a new card, and every phase of the AMB arc removes files from that
//  gate's grandfather list as it converts them.
//
//  Anything that needs a rounded, filled, floating container goes through
//  `.ambientCard(...)`. If a surface genuinely cannot be expressed here, the fix
//  is to extend this file — not to hand-roll one and move on.

import SwiftUI

// MARK: - Card vocabulary

/// How loudly a card speaks relative to its siblings.
///
/// The schedule proved these have to be signalled several ways at once — fill
/// weight, colour, border, saturation — so that "done" and "happening now"
/// survive dark mode, greyscale and colour-blindness rather than leaning on a
/// dimmer grey.
enum AmbientCardState {
    /// The default: a glass card over whatever wash the screen carries.
    case normal
    /// Happening now, or the one thing on the screen that matters.
    case highlighted
    /// Behind you. Desaturated and dimmed, still legible, clearly finished.
    case receded
}

/// What fills a card.
///
/// Added in AMB.6. The lab's chat mockup had to prototype its own bubble because
/// this container could only fill with a MATERIAL, and "my message" needs a solid
/// colour — a material takes its appearance from what is behind it, which is
/// exactly what an identity colour must not do. The rule the arc set for that
/// situation is that the primitive gets extended rather than hand-rolled around,
/// so here it is.
enum AmbientCardFill {
    /// The default: glass over whatever wash the screen carries.
    case material
    /// A solid tint. Used by the chat bubble for the sender's own messages.
    case tint(Color)
}

/// The hairline around a card. Ambient cards are separated by a lit edge rather
/// than by a heavy drop shadow, which is what keeps a dense list from looking
/// like a pile of receipts.
enum AmbientCardBorder {
    case none
    /// 1pt solid. The resting edge.
    case hairline(AnyShapeStyle)
    /// 2pt solid. Reserved for `highlighted` — the "this one" edge.
    case strong(AnyShapeStyle)
    /// 1pt dashed. For a card that is not the same KIND of thing as the cards
    /// around it — time off among shifts, a placeholder, something provisional.
    case dashed(AnyShapeStyle)

    static func hairline(_ color: Color) -> AmbientCardBorder { .hairline(AnyShapeStyle(color)) }
    static func strong(_ color: Color) -> AmbientCardBorder { .strong(AnyShapeStyle(color)) }
    static func dashed(_ color: Color) -> AmbientCardBorder { .dashed(AnyShapeStyle(color)) }
    static func hairline(_ gradient: LinearGradient) -> AmbientCardBorder { .hairline(AnyShapeStyle(gradient)) }
}

// MARK: - The modifier

struct AmbientCardModifier: ViewModifier {
    var density: AmbientDensity = .roomy
    var state: AmbientCardState = .normal
    var fill: AmbientCardFill = .material
    var border: AmbientCardBorder = .none
    /// A coloured bloom under the card. Hero surfaces only — a glow on every row
    /// of a list is the "pile of receipts" failure.
    var glow: Color?
    /// Stretch the card to the full available width.
    ///
    /// This has to live INSIDE the modifier rather than being applied by the
    /// caller, because it must sit between the padding and the background. A
    /// caller writing `.frame(maxWidth: .infinity).ambientCard()` gets the
    /// opposite order: the content stretches first and the padding is then
    /// added OUTSIDE it, so the card overflows its container by twice the
    /// horizontal padding.
    var fillWidth: Bool = false
    var contentAlignment: Alignment = .leading

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: density.cornerRadius, style: .continuous)
    }

    private var fillStyle: AnyShapeStyle {
        switch fill {
        case .tint(let color):
            return AnyShapeStyle(color)
        case .material:
            switch state {
            case .highlighted: return AnyShapeStyle(.regularMaterial)
            case .normal, .receded: return AnyShapeStyle(.ultraThinMaterial)
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, density.horizontalPadding)
            .padding(.vertical, density.verticalPadding)
            .modifier(AmbientFillWidth(active: fillWidth, alignment: contentAlignment))
            .background(fillStyle, in: shape)
            .overlay { borderOverlay }
            .modifier(AmbientGlow(color: glow))
            .grayscale(state == .receded ? 0.85 : 0)
            .opacity(state == .receded ? 0.7 : 1)
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch border {
        case .none:
            EmptyView()
        case .hairline(let style):
            shape.strokeBorder(style, lineWidth: 1)
        case .strong(let style):
            shape.strokeBorder(style, lineWidth: 2)
        case .dashed(let style):
            shape.strokeBorder(style, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }
}

/// Split out so the shadow is applied only when a glow is asked for — an
/// always-on `.shadow(color: .clear)` still costs an offscreen pass per row.
///
/// Both this and `AmbientFillWidth` branch on a value that is fixed at the call
/// site and never changes at runtime, so the `_ConditionalContent` identity
/// switch they introduce can never fire mid-animation.
private struct AmbientGlow: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.shadow(color: color.opacity(0.18), radius: 18, y: 8)
        } else {
            content
        }
    }
}

private struct AmbientFillWidth: ViewModifier {
    let active: Bool
    let alignment: Alignment

    func body(content: Content) -> some View {
        if active {
            content.frame(maxWidth: .infinity, alignment: alignment)
        } else {
            content
        }
    }
}

extension View {
    /// Wrap content in the app's card container.
    ///
    /// This is the ONLY sanctioned way to build a card. See the file header for
    /// why that is enforced rather than requested.
    func ambientCard(
        density: AmbientDensity = .roomy,
        state: AmbientCardState = .normal,
        fill: AmbientCardFill = .material,
        border: AmbientCardBorder = .none,
        glow: Color? = nil,
        fillWidth: Bool = false,
        contentAlignment: Alignment = .leading
    ) -> some View {
        modifier(AmbientCardModifier(density: density, state: state, fill: fill,
                                     border: border, glow: glow, fillWidth: fillWidth,
                                     contentAlignment: contentAlignment))
    }
}
