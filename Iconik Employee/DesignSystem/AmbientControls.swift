//  AmbientControls.swift
//  Iconik Employee — the Ambient design language, controls and status views
//
//  PROMOTED IN AMB.12, and the promotion list was written for this phase by the
//  two phases before it. AMB.9 closed with "chips, failure cards and loading
//  states into the design system" as a reasoned won't-fix deferred to the tail;
//  AMB.10's review round added the same finding from a different angle, listing
//  a search field, a failure card, a loading row, FIVE separate chip
//  implementations and a primary button as kit-level duplication. Batch 4's three
//  mockups then each redeclared the SAME loading row, the SAME failure card and
//  the SAME label/value line privately, which is the third independent signal
//  and the one that settles it.
//
//  The arc's rule when a second surface needs a primitive is to promote it rather
//  than fork it — `AmbientCardFill.surface`, `AmbientEmptyState`'s action slot and
//  `AmbientFormSection` all arrived that way. These arrive the same way.
//
//  WHY A CONTROL IS NOT A CARD, since the gate asks. Everything here that draws a
//  Capsule is a CONTROL: a thing you press. A card is a container you read. They
//  are annotated `ambient-allow` for the drift gate one site at a time rather than
//  by exempting the file, because the day this file grows a genuine container is
//  the day that container should go through `.ambientCard(...)` like every other.

import SwiftUI

// MARK: - Buttons

/// What a button MEANS, which is what decides how it is drawn. Callers pick the
/// meaning; the design system picks the fill, and it picks it once.
enum AmbientButtonRole {
    /// The one thing this screen is for. Filled with the surface's tint.
    case primary
    /// An alternative, equal in weight but not the default. Glass with an edge.
    case secondary
    /// Destroys something. Red on a red wash, never a filled red slab — a solid
    /// red full-width button reads as the primary action of the screen, which is
    /// exactly the mistake Settings' plain "Logout" row made in the other
    /// direction by reading as nothing at all.
    case destructive
}

/// How much room the button takes. `regular` is a full-width commitment;
/// `small` is an inline action inside a card or a row.
enum AmbientButtonSize {
    case regular
    case small

    var verticalPadding: CGFloat { self == .regular ? 13 : 8 }
    var horizontalPadding: CGFloat { self == .regular ? 18 : 14 }
    var font: Font {
        self == .regular ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }
}

/// The app's button.
///
/// Disabled is drawn, not just behaviourally off: batch 4's inventory found
/// buttons across Settings and the manager tools that were never disabled and
/// validated only AFTER the tap, so the screen looked ready and answered with an
/// error. A disabled button here is visibly grey and does not fire.
///
/// `isLoading` shows a spinner IN the button and disables it, because the other
/// shape this app keeps shipping is a submit button that stays live during its
/// own network call.
struct AmbientActionButton: View {
    let title: String
    var systemImage: String?
    var role: AmbientButtonRole = .primary
    var size: AmbientButtonSize = .regular
    var tint: Color = AmbientStyle.brand
    /// Full width is the default for `regular` because that is what a commitment
    /// looks like; an inline action passes `false`.
    var fillWidth: Bool = true
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    private var live: Bool { isEnabled && !isLoading }

    var body: some View {
        Button {
            guard live else { return }
            AmbientHaptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage).font(size.font)
                }
                Text(title).font(size.font)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .modifier(AmbientButtonWidth(active: fillWidth))
            // ambient-allow: a control, not a container.
            .background(Capsule().fill(background))
            .overlay {
                if role == .secondary {
                    Capsule().strokeBorder(Color.primary.opacity(0.12))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!live)
        .accessibilityAddTraits(.isButton)
    }

    /// DISABLED IS DRAWN AS A DIMMED LABEL, NOT AS WHITE-ON-GREY.
    ///
    /// The first version kept the white foreground and only swapped the fill for
    /// `Color.secondary.opacity(0.4)`. In light mode that is a near-white slab, so
    /// "Flag photographer" and "Save to Photos" came out as white text on almost
    /// white — legible only if you already knew what they said. A disabled button
    /// still has a job: it tells you what you have not done yet.
    private var foreground: Color {
        guard live else { return .secondary }
        switch role {
        case .primary: return .white
        case .secondary: return .primary
        case .destructive: return .red
        }
    }

    private var background: AnyShapeStyle {
        guard live else { return AnyShapeStyle(Color.secondary.opacity(0.16)) }
        switch role {
        case .primary: return AnyShapeStyle(tint)
        case .secondary: return AnyShapeStyle(.ultraThinMaterial)
        case .destructive: return AnyShapeStyle(Color.red.opacity(0.12))
        }
    }
}

/// Split out for the same reason `AmbientFillWidth` is: the branch is fixed at
/// the call site, so the identity switch can never fire mid-animation.
private struct AmbientButtonWidth: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

// MARK: - Chips

/// A filter chip — one of a set, on or off.
///
/// FIVE of these existed across the converted kits before this phase, differing
/// in padding, corner treatment and whether the selected state used the feature
/// tint or a system accent. They are one control.
struct AmbientChip: View {
    let text: String
    var systemImage: String?
    let isOn: Bool
    var tint: Color = AmbientStyle.brand
    var count: Int?
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(AmbientMotion.snappy) { action() }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
                }
                Text(text).font(.caption.weight(.semibold))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(isOn ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // ambient-allow: a filter chip, not a container.
            .background(Capsule().fill(isOn
                                       ? AnyShapeStyle(tint)
                                       : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A chip that selects one pay period out of several, and marks which one is NOW.
///
/// PROMOTED OUT OF `Misc Features/MileageKit.swift` when the time clock became the
/// second surface to carry a period carousel. It is `AmbientChip`'s sibling rather
/// than a variant of it: `AmbientChip` is an on/off filter, and this one has a
/// third piece of state — "this is the current period" — which is the whole reason
/// the carousel is legible when you have scrolled three periods back.
///
/// Its default tint is the app brand rather than any one feature's colour, so a
/// caller that forgets to pass one gets something that belongs to the app instead
/// of to mileage.
struct AmbientPeriodChip: View {
    let label: String
    let isCurrent: Bool
    let isSelected: Bool
    var tint: Color = AmbientStyle.brand
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(AmbientMotion.snappy) { action() }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 5) {
                if isCurrent {
                    Circle()
                        .fill(isSelected ? Color.white : tint)
                        .frame(width: 5, height: 5)
                }
                Text(label).font(.caption.weight(.semibold))
                if isCurrent {
                    Text("Now")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // ambient-allow: a selection chip is a control, not a container.
            .background(Capsule().fill(isSelected
                                       ? AnyShapeStyle(tint)
                                       : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status views

/// A load in progress, as a card rather than a bare spinner.
///
/// The bare spinner is what this replaces: it centres itself in whatever space
/// happens to be free, so a screen mid-load jumps when the content lands.
struct AmbientLoadingRow: View {
    let message: String
    var density: AmbientDensity = .roomy

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .ambientCard(density: density, fillWidth: true, contentAlignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// A fetch that failed, saying so, with a way back.
///
/// THIS IS THE COMPONENT BATCH 4 EXISTS TO ADD. The inventory found a failed
/// fetch rendered as an EMPTY STATE on at least six screens, three of them
/// payroll- or manager-critical: "No time entries for pay period" when payroll
/// failed to load, "No sessions assigned for today" inviting an unattributed
/// clock-in, and a green "All users are currently in good standing" drawn while
/// the flag query was still in flight. An empty state is a statement of fact
/// about the data. A failure is a statement about the connection. Drawing one as
/// the other tells the user something false.
///
/// The retry closure is optional but strongly encouraged: before this phase
/// exactly ONE retry affordance existed in the whole Settings tree.
struct AmbientFailureCard: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var tint: Color = .orange
    var actionTitle: String = "Retry"
    var actionIcon: String = "arrow.clockwise"
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)

            if let action {
                AmbientActionButton(title: actionTitle,
                                    systemImage: actionIcon,
                                    role: .primary,
                                    size: .small,
                                    tint: tint,
                                    fillWidth: false,
                                    action: action)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

// MARK: - Read-out rows

/// One label and one value, baseline-aligned, label secondary and value
/// emphasised. The read-only half of a form.
struct AmbientStatLine: View {
    let label: String
    let value: String
    var valueTint: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(valueTint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// A row that goes somewhere: icon, title, one line saying what is behind it,
/// chevron.
///
/// The subtitle is not decoration. Settings' rows were a bare word each —
/// "Account Info", "School Info" — so the only way to learn what a row held was
/// to open it.
struct AmbientNavRow: View {
    let title: String
    var detail: String?
    let systemImage: String
    var tint: Color = AmbientStyle.brand
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AmbientDensity.compact.titleFont)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let badge {
                    AmbientBadge(text: badge, tint: tint)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search

/// The app's search field.
///
/// A card rather than a `.searchable` modifier because `.searchable` renders in
/// the navigation bar, and this app's features are handed a `NavigationView` by
/// the shell (D3/NAV.1) whose bar already carries the Home button and the title.
struct AmbientSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .ambientCard(density: .compact,
                     fill: .surface,
                     border: .hairline(Color.primary.opacity(0.10)),
                     fillWidth: true)
    }
}
