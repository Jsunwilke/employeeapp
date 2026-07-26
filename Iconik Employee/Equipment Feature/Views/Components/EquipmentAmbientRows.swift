//
//  EquipmentAmbientRows.swift
//  Iconik Employee
//
//  Equipment in the Ambient design language — the row vocabulary (AMB.3).
//
//  Ported from the approved AMB.2 lab mockup (DesignLab/Mockups/EquipmentMockup.swift
//  and the specimen sheet's LabEquipmentRow), which the operator reviewed on iPhone
//  and iPad. This file is the production half: the same drawing, against the real
//  models instead of the lab's sample types.
//
//  Replaces KitCard.swift and EquipmentCard.swift, both deleted in the same commit.
//  Every capability those two rendered is listed in AMB_BATCH1_PARITY.md and is
//  accounted for here or in the screen that owns it.
//

import SwiftUI

// MARK: - Kit tape colour

/// The kit's tape colour as a FLUSH EDGE BAND on the card.
///
/// This matches the app rather than the first cut of the mockup. `KitColorBorder`
/// was a plain Rectangle sitting first in an `HStack(spacing: 0)`, so it ran the
/// full height of the card, flush to the leading edge, with the container's corner
/// radius clipping its ends — binding tape on a case. Drawn instead as an inset
/// rounded pill it reads as a stray mark, which is what the operator caught in the
/// lab (751b05a).
///
/// So: full height, flush, square ends, and the CARD is clipped to its own radius
/// so the band follows the corner instead of overhanging it. Full saturation is
/// deliberate — this colour is matching real tape wrapped on a real case, so it has
/// to be recognisable rather than tasteful.
///
/// Rainbow is a real tape colour (`KitTemplate.isRainbow`): a band drawn as a flat
/// `Color(hex: "rainbow")` renders garbage, so it is special-cased. The gradient
/// mirrors `KitColorBorder`'s without its endless animation — a colour spinning
/// forever on every row of a list is a battery cost and a distraction.
struct KitTapeEdge: ViewModifier {
    /// A hex string, or the literal "rainbow", or nil for a thing in no kit.
    let hex: String?
    let density: AmbientDensity

    private var isRainbow: Bool { hex?.lowercased() == "rainbow" }

    /// Branches on a value fixed at the call site — a row's kit does not change
    /// under it — so the `_ConditionalContent` identity switch cannot fire
    /// mid-animation. Same reasoning as `AmbientGlow`.
    func body(content: Content) -> some View {
        if let hex {
            content
                .overlay(alignment: .leading) {
                    Group {
                        if isRainbow {
                            Rectangle().fill(KitTapeEdge.rainbow)
                        } else {
                            Rectangle().fill(Color(hex: hex))
                        }
                    }
                    .frame(width: 4)
                }
                // Clipping the CARD, not the band: this is what makes the band
                // follow the corner curve instead of overhanging it.
                .clipShape(RoundedRectangle(cornerRadius: density.cornerRadius,
                                            style: .continuous))
        } else {
            content
        }
    }

    static let rainbow = LinearGradient(
        colors: [.red, .orange, .yellow, .green, .blue, .purple],
        startPoint: .top, endPoint: .bottom)
}

extension View {
    /// Bind a card with a kit's tape colour. No-op when the thing is in no kit.
    func kitTapeEdge(_ hex: String?, density: AmbientDensity) -> some View {
        modifier(KitTapeEdge(hex: hex, density: density))
    }
}

/// The kit colour as a dot, for a kit icon or a tape-colour reference line.
///
/// Renders NOTHING when the kit has no colour — the same rule `KitColorIndicator`
/// followed. Drawing the ring unconditionally would leave a stray stroked circle on
/// every colourless kit.
struct KitTapeDot: View {
    /// A hex string, or the literal "rainbow", or nil.
    let hex: String?
    var size: CGFloat = 12

    private var isRainbow: Bool { hex?.lowercased() == "rainbow" }

    var body: some View {
        if let hex {
            Group {
                if isRainbow {
                    Circle().fill(AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                        center: .center))
                } else {
                    Circle().fill(Color(hex: hex))
                }
            }
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
        }
    }
}

// MARK: - Kit due state

/// Exactly one of the three, which is the rule `KitCard` and `KitDetailView` both
/// followed: overdue wins, then permanent, then a return date.
enum KitDueState {
    case permanent
    case on(Date)
    /// `days` is nil when the count is not a whole day yet, or when the assignment
    /// is flagged overdue by status with no return date to measure from.
    case overdue(days: Int?)

    init(_ kit: UserKitAssignment) {
        if kit.isOverdue {
            // NOT `?? 0`. `daysOverdue` returns 0 on the due date itself and nil for
            // a status-flagged assignment with no return date, so a plain default
            // renders "0D OVERDUE" — which the badge this replaced never did: the
            // old OverdueBadge guarded `days > 0` and drew nothing at all. Neither
            // is right, so a sub-day overdue now says "OVERDUE" with no number.
            let days = kit.daysOverdue
            self = .overdue(days: (days ?? 0) > 0 ? days : nil)
        } else if kit.isPermanent {
            self = .permanent
        } else if let date = kit.expectedReturnDate {
            self = .on(date)
        } else {
            self = .permanent
        }
    }
}

struct KitDueBadge: View {
    let due: KitDueState
    /// The kit detail has room for "3 days overdue"; a list row does not.
    var spelledOut = false

    var body: some View {
        switch due {
        case .permanent:
            AmbientBadge(text: "Permanent", systemImage: "infinity", tint: .blue)
        case .on(let date):
            AmbientBadge(text: "Due \(Formatters.monthDay.string(from: date))",
                         systemImage: "calendar", tint: .secondary)
        case .overdue(let days):
            AmbientBadge(text: overdueText(days),
                         systemImage: "exclamationmark.triangle.fill", tint: .red)
        }
    }

    private func overdueText(_ days: Int?) -> String {
        guard let days else { return "Overdue" }
        if spelledOut { return "\(days) day\(days == 1 ? "" : "s") overdue" }
        return "\(days)d overdue"
    }
}

// MARK: - Kit row

/// Everything `KitCard` rendered: tape edge, box icon with its colour dot, name,
/// description, item count, and exactly one of overdue / permanent / return date.
struct EquipmentKitRow: View {
    let kit: UserKitAssignment
    var density: AmbientDensity = .compact

    var body: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: density.contentSpacing) {
                Text(kit.displayName)
                    .font(density.titleFont)
                    .lineLimit(1)

                if let detail = kit.kitTemplate?.description, !detail.isEmpty {
                    Text(detail)
                        .font(density.subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    AmbientBadge(text: "\(kit.itemCount) item\(kit.itemCount == 1 ? "" : "s")",
                                 systemImage: "cube.box.fill", tint: .secondary)
                    KitDueBadge(due: KitDueState(kit))
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .ambientCard(density: density, border: .hairline(borderTint))
        .kitTapeEdge(kit.kitColorHex, density: density)
    }

    private var borderTint: Color {
        kit.isOverdue ? .red.opacity(0.5) : Color.primary.opacity(0.08)
    }

    private var icon: some View {
        // ambient-allow: an icon tile, not a card — it is the row's leading glyph
        // and the row itself is the card.
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: kit.kitTemplate != nil ? "shippingbox.fill" : "cube.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .overlay(alignment: .topLeading) {
                KitTapeDot(hex: kit.kitColorHex, size: 12).offset(x: -3, y: -3)
            }
    }
}

// MARK: - Form furniture

/// The item thumbnail the four equipment forms show in their summary section.
///
/// One definition rather than the four near-identical copies the forms each carried
/// — check out, check in, request and damage report all drew the same 60pt photo or
/// grey camera placeholder, and they had already drifted (check in used 50pt and a
/// smaller glyph).
struct EquipmentFormThumbnail: View {
    let photoPath: String?
    var side: CGFloat = 60

    var body: some View {
        if let photoPath, !photoPath.isEmpty {
            SupabaseImageView(
                storageURL: photoPath,
                bucket: "equipment-photos",
                width: side,
                height: side,
                contentMode: .fill,
                cornerRadius: 8
            )
        } else {
            // ambient-allow: a photo placeholder inside a Form row, not a card.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: side * 0.34, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
        }
    }
}

// MARK: - Equipment row

/// Who is holding an item, as a row can state it.
///
/// This is a value rather than a lookup because the two lists that draw a row know
/// different things. Your own gear has its `EquipmentAssignment` in hand, so it can
/// say "You" and when it is due. The inventory list does not: `equipmentService.equipment`
/// is equipment rows with no assignment join, which is why `EquipmentCard` said the
/// literal "Currently checked out" rather than naming anybody. Resolving the name
/// there would mean a new query, and AMB.3 does not change the data layer.
struct EquipmentRowAssignee {
    let label: String
    var dueLabel: String?
    var overdue: Bool = false
}

/// The per-item menu a kit's packing list shows on a checked-out item, carried over
/// from `KitItemRow`: View Details and Report Damage. It is the only route to
/// reporting damage on a kit item without first opening the item.
struct EquipmentRowMenuActions {
    let onViewDetails: () -> Void
    let onReportDamage: () -> Void
}

/// Equipment's row, rebuilt from Ambient primitives.
///
/// Everything scales off `density`, which is the point — the same row definition
/// serves your handful of assigned items and a several-hundred-row inventory.
struct EquipmentRow: View {
    let item: EquipmentItem
    var kitColorHex: String?
    var assignee: EquipmentRowAssignee?
    var menuActions: EquipmentRowMenuActions?
    var density: AmbientDensity = .compact
    /// Force the serial on at compact, where it is otherwise dropped for height.
    ///
    /// The kit detail sets this. `KitItemRow` showed the serial on every row, and a
    /// packing list is precisely where you check a serial against the case in front
    /// of you — so hiding it there is feature loss. The lab mockup had this gap too
    /// (it drew the kit's items with the plain compact row), which is why the parity
    /// inventory is checked against the SOURCE and not against the mockup.
    var showsSerial: Bool = false

    private var thumbnailSize: CGFloat {
        switch density {
        case .hero: return 64
        case .roomy: return 56
        case .compact: return 40
        }
    }

    private var cornerRadius: CGFloat { density == .compact ? 8 : 10 }

    /// Retired equipment reads as finished, the same way a past shift does.
    private var state: AmbientCardState {
        item.statusEnum == .retired ? .receded : .normal
    }

    /// The app's rule, kept: a checked-out item in a kit offers the menu, anything
    /// else shows its status.
    private var showsMenu: Bool {
        menuActions != nil && item.statusEnum == .checkedOut
    }

    var body: some View {
        HStack(spacing: density == .compact ? 10 : 14) {
            thumbnail

            VStack(alignment: .leading, spacing: density.contentSpacing) {
                Text(item.name)
                    .font(density.titleFont)
                    .lineLimit(density == .compact ? 1 : 2)

                HStack(spacing: 8) {
                    if let category = item.category {
                        Text(category.name)
                            .font(density.subtitleFont)
                            .foregroundStyle(.secondary)
                    }
                    conditionDot
                }

                if density != .compact || showsSerial,
                   let serial = item.serial_number, !serial.isEmpty {
                    Text("SN: \(serial)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // The assignee stays even at compact: "who has this" is the single
                // most useful thing on a checked-out row, and AllEquipmentView
                // passed showAssignee: true, so dropping it would be feature loss.
                if let assignee {
                    assigneeLine(assignee)
                }
            }

            Spacer(minLength: 0)

            if showsMenu, let menuActions {
                itemMenu(menuActions)
            } else {
                AmbientBadge(text: item.statusEnum.label, tint: item.statusEnum.color)
            }
        }
        .ambientCard(density: density, state: state, border: .hairline(borderTint))
        .kitTapeEdge(kitColorHex, density: density)
    }

    private var borderTint: Color {
        item.statusEnum == .needsRepair
            ? item.statusEnum.color.opacity(0.55)
            : Color.primary.opacity(0.08)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let photoPath = item.photo_url, !photoPath.isEmpty {
            SupabaseImageView(
                storageURL: photoPath,
                bucket: "equipment-photos",
                width: thumbnailSize,
                height: thumbnailSize,
                contentMode: .fill,
                cornerRadius: cornerRadius
            )
        } else {
            // ambient-allow: a photo placeholder, not a card.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: thumbnailSize, height: thumbnailSize)
                .overlay {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: thumbnailSize * 0.34, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private var conditionDot: some View {
        HStack(spacing: 4) {
            Circle().fill(item.conditionEnum.color).frame(width: 7, height: 7)
            Text(item.conditionEnum.label)
                .font(density.subtitleFont)
                .foregroundStyle(.secondary)
        }
    }

    private func assigneeLine(_ assignee: EquipmentRowAssignee) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill").font(.system(size: 8))
            Text(assignee.label).lineLimit(1)
            if let due = assignee.dueLabel {
                Text(assignee.overdue ? "· was due \(due)" : "· due \(due)")
                    .lineLimit(1)
            }
        }
        .font(.caption2)
        .foregroundStyle(assignee.overdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
    }

    private func itemMenu(_ actions: EquipmentRowMenuActions) -> some View {
        Menu {
            Button {
                actions.onViewDetails()
            } label: {
                Label("View Details", systemImage: "info.circle")
            }

            Button {
                actions.onReportDamage()
            } label: {
                Label("Report Damage", systemImage: "exclamationmark.triangle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
    }
}
