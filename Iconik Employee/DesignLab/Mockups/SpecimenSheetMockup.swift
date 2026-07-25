//  SpecimenSheetMockup.swift
//  Iconik Employee — AMB.2's mockup
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  AMB.2's deliverable is the primitives themselves, so its mockup is a
//  specimen sheet rather than a screen: every Ambient component at every
//  density, drawn against EQUIPMENT'S REAL ROW CONTENT — the same fields
//  EquipmentCard renders today (name, category, condition, serial, status, kit
//  stripe, thumbnail).
//
//  THE DECISION THIS SHEET EXISTS TO SETTLE (D5)
//      Ambient was designed on the schedule, where a photographer sees a handful
//      of items a day. Equipment is the opposite: an unbounded, unpaginated list
//      that renders every item the organisation owns. If glass and generous
//      spacing make a 200-row list feel slow, that has to be found HERE — before
//      AMB.3 converts Equipment and AMB.4 through AMB.12 build on the result.
//
//      So the list below is long on purpose and the density control is live.
//      Flip it while scrolling. The question is not which looks nicer in a
//      screenshot; it is which one you can still scan on row 90.

import SwiftUI

struct SpecimenSheetMockup: View {
    /// Drives the equipment list below. `.hero` is deliberately not offered for
    /// a list — it is the one-thing-on-the-screen density.
    @State private var listDensity: AmbientDensity = .compact

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: .indigo)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    densityDecision
                    theList
                    cardStates
                    borders
                    badgesAndPills
                    people
                    numbers
                    prose
                    nothing
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - 1. The density decision

    private var densityDecision: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("1 · Density", trailing: "D5")

            Text("The same equipment row, three ways. Compact is the proposal for dense lists; roomy is what the schedule ships today.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(AmbientDensity.allCases, id: \.self) { density in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label(for: density))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                    LabEquipmentRow(item: DesignLabSampleData.equipment[0], density: density)
                }
            }
        }
    }

    private func label(for density: AmbientDensity) -> String {
        switch density {
        case .hero: return "HERO — \(Int(density.verticalPadding))pt padding, \(Int(density.cornerRadius))pt radius"
        case .roomy: return "ROOMY — \(Int(density.verticalPadding))pt padding, \(Int(density.cornerRadius))pt radius"
        case .compact: return "COMPACT — \(Int(density.verticalPadding))pt padding, \(Int(density.cornerRadius))pt radius"
        }
    }

    // MARK: - 2. The real test: a long list

    private var theList: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("2 · A real list", trailing: "\(DesignLabSampleData.equipment.count) items")

            Picker("Density", selection: $listDensity) {
                Text("Compact").tag(AmbientDensity.compact)
                Text("Roomy").tag(AmbientDensity.roomy)
            }
            .pickerStyle(.segmented)

            Text("Scroll this with the control set both ways. Equipment has no pagination — a real organisation's list is every item it owns.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVStack(spacing: listDensity.stackSpacing) {
                ForEach(DesignLabSampleData.equipment) { item in
                    LabEquipmentRow(item: item, density: listDensity)
                }
            }
            .animation(AmbientMotion.gentle, value: listDensity)
        }
    }

    // MARK: - 3. States

    private var cardStates: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("3 · Card states")
            Text("Signalled several ways at once — fill weight, saturation, opacity — so they survive dark mode and colour-blindness rather than leaning on a dimmer grey.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            specimen("normal") {
                Text("Still to come")
                    .ambientCard(density: .roomy, fillWidth: true)
            }
            specimen("highlighted") {
                Text("Happening now")
                    .ambientCard(density: .roomy, state: .highlighted,
                                 border: .strong(Color.orange), fillWidth: true)
            }
            specimen("receded") {
                Text("Finished")
                    .ambientCard(density: .roomy, state: .receded, fillWidth: true)
            }
            specimen("hero, with glow") {
                Text("The one thing on the screen")
                    .ambientCard(density: .hero, state: .highlighted,
                                 border: .hairline(Color.indigo.opacity(0.25)),
                                 glow: .indigo, fillWidth: true)
            }
        }
    }

    // MARK: - 4. Borders

    private var borders: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("4 · Edges")
            specimen("none") {
                Text("No edge")
                    .ambientCard(density: .compact, fillWidth: true)
            }
            specimen("hairline — the resting edge") {
                Text("1pt")
                    .ambientCard(density: .compact, border: .hairline(Color.blue.opacity(0.5)), fillWidth: true)
            }
            specimen("strong — “this one”") {
                Text("2pt")
                    .ambientCard(density: .compact, border: .strong(Color.blue), fillWidth: true)
            }
            specimen("dashed — a different KIND of thing") {
                Text("Time off among shifts")
                    .ambientCard(density: .compact, border: .dashed(Color.gray.opacity(0.6)), fillWidth: true)
            }
        }
    }

    // MARK: - 5. Badges and pills

    private var badgesAndPills: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("5 · Badges and pills")

            HStack(spacing: 8) {
                ForEach(LabEquipmentStatus.allCases, id: \.self) { status in
                    AmbientBadge(text: status.rawValue, systemImage: status.symbol, tint: status.color)
                }
            }

            specimen("pills, roomy — icons kept") {
                AmbientPillRow(pills: DesignLabSampleData.pills, density: .roomy)
            }
            specimen("pills, compact — icons dropped, wrapping kept") {
                AmbientPillRow(pills: DesignLabSampleData.pills, density: .compact)
            }
        }
    }

    // MARK: - 6. People

    private var people: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("6 · People")
            Text("Colour is derived from the name, so a person is the same colour on every screen and on every device.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ForEach(DesignLabSampleData.crew.prefix(4)) { person in
                    AmbientAvatar(name: person.name, size: 40)
                }
            }
            specimen("stack, overflowing") {
                AmbientAvatarStack(subjects: DesignLabSampleData.crew, size: 28, maxVisible: 4)
            }
            specimen("stack, compact") {
                AmbientAvatarStack(subjects: DesignLabSampleData.crew, size: 22, maxVisible: 5)
            }
        }
    }

    // MARK: - 7. Numbers

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("7 · Numbers")
            HStack(spacing: 10) {
                AmbientStatTile(value: 18, label: "Available", systemImage: "checkmark.circle.fill", tint: .green)
                AmbientStatTile(value: 7, label: "Checked out", systemImage: "person.fill", tint: .blue)
                AmbientStatTile(value: 2, label: "Repair", systemImage: "wrench.fill", tint: .orange)
            }
        }
    }

    // MARK: - 8. Prose

    private var prose: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("8 · Prose")
            AmbientNoteCard(
                title: "Notes",
                text: "Tripod head sticks when cold — warm it in the car before the first session. Serial is worn off the plate; it is on the inside of the leg clamp.",
                accent: .orange)
        }
    }

    // MARK: - 9. Nothing

    private var nothing: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientSectionTitle("9 · Nothing here")
            AmbientEmptyState(title: "No equipment found",
                              message: "Try adjusting your search or filters.",
                              systemImage: "shippingbox")
                .ambientCard(density: .roomy)
        }
    }

    private var footer: some View {
        Text("Sample data. Nothing here reads or writes anything.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    // MARK: - helper

    private func specimen<Content: View>(_ caption: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
            content()
        }
    }
}

// MARK: - The proposed equipment row

/// Equipment's row, rebuilt from Ambient primitives.
///
/// This is the actual proposal for AMB.3, drawn from what EquipmentCard renders
/// today so the comparison is like for like: the kit-colour stripe, a
/// thumbnail, the name, category and condition, the serial, and the status
/// badge. Everything scales off `density`, which is the point — the same row
/// definition serves a browsable list and a 300-row inventory.
struct LabEquipmentRow: View {
    let item: LabEquipmentItem
    var density: AmbientDensity = .compact

    private var thumbnailSize: CGFloat {
        switch density {
        case .hero: return 64
        case .roomy: return 56
        case .compact: return 40
        }
    }

    /// Retired equipment reads as finished, the same way a past shift does.
    private var state: AmbientCardState {
        item.status == .retired ? .receded : .normal
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
                        Text(category)
                            .font(density.subtitleFont)
                            .foregroundStyle(.secondary)
                    }
                    conditionDot
                }

                if density != .compact, let serial = item.serial {
                    Text("SN: \(serial)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // The assignee stays even at compact. AllEquipmentView passes
                // showAssignee: true, so "who has this" is on the real row —
                // dropping it at the dense density would be feature loss, and
                // it is the single most useful thing on a checked-out row.
                if let assignee = item.assignee {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill").font(.system(size: 8))
                        Text(item.mine ? "You" : assignee)
                            .lineLimit(1)
                        if let due = item.dueLabel, item.overdue {
                            Text("· was due \(due)")
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(item.overdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                }
            }

            Spacer(minLength: 0)

            AmbientBadge(text: item.status.rawValue, tint: item.status.color)
        }
        .ambientCard(density: density,
                     state: state,
                     border: .hairline(borderTint))
        .overlay(alignment: .leading) { kitStripe }
    }

    private var borderTint: Color {
        item.status == .needsRepair ? item.status.color.opacity(0.55) : Color.primary.opacity(0.08)
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: density == .compact ? 8 : 10, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(width: thumbnailSize, height: thumbnailSize)
            .overlay {
                Image(systemName: item.hasPhoto ? "camera.fill" : "circle.dashed")
                    .font(.system(size: thumbnailSize * 0.34, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
    }

    private var conditionDot: some View {
        HStack(spacing: 4) {
            Circle().fill(item.condition.color).frame(width: 7, height: 7)
            Text(item.condition.rawValue)
                .font(density.subtitleFont)
                .foregroundStyle(.secondary)
        }
    }

    /// The kit tape colour, as a stripe down the leading edge — Equipment's
    /// existing signal for "this belongs to a kit", kept because photographers
    /// already read it.
    @ViewBuilder
    private var kitStripe: some View {
        if let hex = item.kitColor {
            Capsule()
                .fill(Color(hex: hex))
                .frame(width: 3)
                .padding(.vertical, density.verticalPadding)
                .padding(.leading, 1)
        }
    }
}
