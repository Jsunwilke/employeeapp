//
//  EquipmentKitDetailView.swift
//  Iconik Employee
//
//  A kit, in the Ambient design language — a packing list (AMB.3).
//
//  Replaces KitDetailView.swift, deleted in the same commit. Ported from the AMB.2
//  lab mockup the operator approved on iPhone and iPad.
//
//  CATEGORIES OPEN EXPANDED.
//      The app started every category collapsed, so a six-item kit opened on three
//      headers and no equipment — the wrong answer to the only question anyone opens
//      a kit to ask. Collapsing still works, it is just no longer the default.
//
//  THE ORDER IS THE ORDER A CASE GETS PACKED.
//      Cameras, lenses, lighting, stands, bags, backdrops, power, storage, audio,
//      accessories. That is the app's own sort and it is real domain logic — somebody
//      thinking about how a case is actually packed. An alphabetical sort would look
//      identical in a screenshot and be worse every single day, so it is carried over
//      verbatim rather than rewritten.
//

import SwiftUI

struct EquipmentKitDetailView: View {
    let kitAssignment: UserKitAssignment

    @State private var collapsedCategories: Set<String> = []
    @State private var pushedEquipment: EquipmentReference?
    @State private var showCheckInSheet = false
    @State private var itemForDamageReport: EquipmentItem?

    private var feature: Color { FeatureTheme.color(for: "equipment") }

    // MARK: - Category ordering (carried over verbatim from KitDetailView)

    private static let categorySortOrder: [String] = [
        "camera", "bodies",           // 1. Cameras first
        "lens",                        // 2. Lenses
        "light", "flash", "strobe",   // 3. Lighting
        "stand", "tripod", "monopod", // 4. Stands
        "bag", "case",                // 5. Bags & Cases
        "backdrop", "background",     // 6. Backdrops
        "battery", "power",           // 7. Power/Batteries
        "memory", "card", "storage",  // 8. Storage
        "audio", "mic",               // 9. Audio
        "accessori"                   // 10. Accessories (catch-all)
    ]

    private static func categorySortPriority(_ categoryName: String) -> Int {
        let lowercased = categoryName.lowercased()
        for (index, keyword) in categorySortOrder.enumerated() where lowercased.contains(keyword) {
            return index
        }
        // Uncategorized goes last; unknown categories go just before it.
        if categoryName == "Uncategorized" { return 999 }
        return 998
    }

    private var itemsByCategory: [(categoryName: String, items: [EquipmentItem])] {
        Dictionary(grouping: kitAssignment.items) { $0.category?.name ?? "Uncategorized" }
            .map { (categoryName: $0.key, items: $0.value) }
            .sorted { Self.categorySortPriority($0.categoryName) < Self.categorySortPriority($1.categoryName) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    AmbientSectionTitle("In this kit", trailing: "\(kitAssignment.itemCount)")

                    VStack(spacing: AmbientDensity.compact.stackSpacing) {
                        ForEach(itemsByCategory, id: \.categoryName) { group in
                            categorySection(group)
                        }
                    }

                    checkInButton.padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle(kitAssignment.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheckInSheet) {
            NavigationStack {
                EquipmentCheckInView(
                    assignments: kitAssignment.assignments,
                    items: kitAssignment.items,
                    kitName: kitAssignment.kitTemplate?.name
                )
            }
        }
        .sheet(item: $itemForDamageReport) { item in
            NavigationStack {
                DamageReportView(
                    equipment: item,
                    assignmentId: kitAssignment.assignments.first { $0.equipment_id == item.id }?.id
                )
            }
        }
        .ambientPush(item: $pushedEquipment) { reference in
            EquipmentDetailView(equipmentId: reference.id)
        }
    }

    // MARK: - Header

    /// Compact rather than the app's centred 80pt hero: same content, far less of
    /// the fold spent before the first item you came here to look at. The kit's
    /// name is the navigation title, so it is not repeated here.
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                // ambient-allow: the kit's icon tile, not a card.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 52, height: 52)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                KitTapeDot(hex: kitAssignment.kitColorHex, size: 16).offset(x: 20, y: -20)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let description = kitAssignment.kitTemplate?.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    AmbientBadge(text: "\(kitAssignment.itemCount) item\(kitAssignment.itemCount == 1 ? "" : "s")",
                                 systemImage: "cube.box.fill", tint: .secondary)
                    KitDueBadge(due: KitDueState(kitAssignment), spelledOut: true)
                }

                // The tape-colour reference line, kept: it is how you find the case
                // on a shelf.
                if kitAssignment.kitColorHex != nil {
                    HStack(spacing: 6) {
                        KitTapeDot(hex: kitAssignment.kitColorHex, size: 12)
                        Text("Tape colour for physical identification")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .ambientCard(density: .roomy, state: .highlighted,
                     border: .hairline(feature.opacity(0.3)),
                     glow: feature, fillWidth: true)
    }

    // MARK: - Category section

    private func categorySection(_ group: (categoryName: String, items: [EquipmentItem])) -> some View {
        let isOpen = !collapsedCategories.contains(group.categoryName)

        return VStack(spacing: AmbientDensity.compact.stackSpacing) {
            Button {
                withAnimation(AmbientMotion.snappy) {
                    if isOpen {
                        collapsedCategories.insert(group.categoryName)
                    } else {
                        collapsedCategories.remove(group.categoryName)
                    }
                }
                AmbientHaptics.selection()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: Self.categoryIcon(for: group.categoryName))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(group.categoryName).font(.footnote.weight(.semibold))
                    Text("\(group.items.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                ForEach(group.items) { item in
                    // Not wrapped in a Button: the row carries a Menu, and a Menu
                    // inside a Button's label does not receive its own taps. This is
                    // the app's own arrangement — contentShape plus onTapGesture,
                    // with the Menu as a sibling — and it is the shape of the AMB.1
                    // dead tap, so it is deliberate rather than incidental.
                    EquipmentRow(
                        item: item,
                        kitColorHex: kitAssignment.kitColorHex,
                        menuActions: EquipmentRowMenuActions(
                            onViewDetails: { pushedEquipment = EquipmentReference(id: item.id) },
                            onReportDamage: { itemForDamageReport = item }
                        ),
                        showsSerial: true
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        pushedEquipment = EquipmentReference(id: item.id)
                    }
                }
            }
        }
    }

    /// Carried over verbatim from KitDetailView.categoryIcon.
    private static func categoryIcon(for categoryName: String) -> String {
        let name = categoryName.lowercased()
        if name.contains("camera") || name.contains("bodies") { return "camera.fill" }
        if name.contains("lens") { return "camera.aperture" }
        if name.contains("light") { return "light.max" }
        if name.contains("bag") || name.contains("case") { return "bag.fill" }
        if name.contains("accessori") { return "gearshape.fill" }
        if name.contains("tripod") || name.contains("stand") { return "camera.on.rectangle.fill" }
        if name.contains("battery") || name.contains("power") { return "battery.100" }
        if name.contains("memory") || name.contains("card") || name.contains("storage") { return "sdcard.fill" }
        if name.contains("audio") || name.contains("mic") { return "mic.fill" }
        if name.contains("backdrop") || name.contains("background") { return "rectangle.portrait.fill" }
        return "cube.box.fill"
    }

    // MARK: - Check in

    private var checkInButton: some View {
        VStack(spacing: 6) {
            Button {
                showCheckInSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line").font(.footnote.weight(.semibold))
                    Text("Check in kit").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(feature))
            }
            .buttonStyle(.plain)

            if kitAssignment.kitTemplate != nil {
                Text("Returns all \(kitAssignment.itemCount) item\(kitAssignment.itemCount == 1 ? "" : "s") in this kit")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
