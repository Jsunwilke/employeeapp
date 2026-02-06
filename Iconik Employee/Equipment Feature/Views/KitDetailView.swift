//
//  KitDetailView.swift
//  Iconik Employee
//
//  Equipment Management Feature - Kit Detail View
//

import SwiftUI

struct KitDetailView: View {
    let kitAssignment: UserKitAssignment

    @StateObject private var equipmentService = EquipmentService.shared

    @State private var showCheckInSheet = false
    @State private var selectedItemForDamage: EquipmentItem?
    @State private var showEquipmentDetail = false
    @State private var selectedEquipmentId: UUID?
    @State private var expandedCategories: Set<String> = []

    // Category sort order for photography workflow
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

    // Get sort priority for a category name (lower = higher priority)
    private func categorySortPriority(_ categoryName: String) -> Int {
        let lowercased = categoryName.lowercased()
        for (index, keyword) in Self.categorySortOrder.enumerated() {
            if lowercased.contains(keyword) {
                return index
            }
        }
        // Uncategorized goes last
        if categoryName == "Uncategorized" { return 999 }
        // Unknown categories go before Uncategorized
        return 998
    }

    // Group items by category
    private var itemsByCategory: [(categoryName: String, items: [EquipmentItem])] {
        var grouped: [String: [EquipmentItem]] = [:]

        for item in kitAssignment.items {
            let categoryName = item.category?.name ?? "Uncategorized"
            grouped[categoryName, default: []].append(item)
        }

        // Sort categories by workflow order: Camera → Lenses → Lighting → Stands → etc.
        return grouped.sorted { lhs, rhs in
            categorySortPriority(lhs.key) < categorySortPriority(rhs.key)
        }.map { (categoryName: $0.key, items: $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Kit header
                kitHeaderSection

                // Kit items list
                kitItemsSection

                // Actions section
                actionsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(kitAssignment.displayName)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showCheckInSheet) {
            NavigationStack {
                EquipmentCheckInView(
                    assignments: kitAssignment.assignments,
                    items: kitAssignment.items,
                    kitName: kitAssignment.kitTemplate?.name
                )
            }
        }
        .sheet(item: $selectedItemForDamage) { item in
            NavigationStack {
                DamageReportView(
                    equipment: item,
                    assignmentId: kitAssignment.assignments.first { $0.equipment_id == item.id }?.id
                )
            }
        }
        .navigationDestination(isPresented: $showEquipmentDetail) {
            if let equipmentId = selectedEquipmentId {
                EquipmentDetailView(equipmentId: equipmentId)
            }
        }
    }

    // MARK: - Header Section

    private var kitHeaderSection: some View {
        VStack(spacing: 12) {
            // Kit icon with color
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 80)

                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)

                // Color indicator - supports rainbow
                if let colorHex = kitAssignment.kitColorHex {
                    KitColorIndicator(hexColor: colorHex, size: 24)
                        .offset(x: 28, y: -28)
                }
            }

            // Kit name
            Text(kitAssignment.displayName)
                .font(.title2)
                .fontWeight(.bold)

            // Description
            if let kit = kitAssignment.kitTemplate, let description = kit.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Status badges
            HStack(spacing: 12) {
                // Item count
                Label("\(kitAssignment.itemCount) items", systemImage: "cube.box.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Return date or permanent
                if kitAssignment.isOverdue {
                    OverdueBadge(daysOverdue: kitAssignment.daysOverdue)
                } else if kitAssignment.isPermanent {
                    PermanentBadge()
                } else if let returnDate = kitAssignment.expectedReturnDate {
                    ReturnDateBadge(date: returnDate)
                }
            }

            // Tape color reference - supports rainbow
            if let colorHex = kitAssignment.kitColorHex {
                HStack(spacing: 8) {
                    KitColorIndicator(hexColor: colorHex, size: 16)
                    Text("Tape color for physical identification")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    // MARK: - Items Section

    private var kitItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Equipment in Kit")
                .font(.headline)

            // Grouped by category with expand/collapse
            VStack(spacing: 8) {
                ForEach(itemsByCategory, id: \.categoryName) { group in
                    CategorySection(
                        categoryName: group.categoryName,
                        items: group.items,
                        kitColorHex: kitAssignment.kitColorHex,
                        isExpanded: expandedCategories.contains(group.categoryName),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedCategories.contains(group.categoryName) {
                                    expandedCategories.remove(group.categoryName)
                                } else {
                                    expandedCategories.insert(group.categoryName)
                                }
                            }
                        },
                        onItemTap: { item in
                            selectedEquipmentId = item.id
                            showEquipmentDetail = true
                        },
                        onReportDamage: { item in
                            selectedItemForDamage = item
                        }
                    )
                }
            }
        }
        // Categories start collapsed - user taps to expand
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Check in kit button
            Button {
                showCheckInSheet = true
            } label: {
                HStack {
                    Image(systemName: "arrow.down.to.line")
                    Text("Check In Kit")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }

            // Additional info
            if kitAssignment.kitTemplate != nil {
                Text("Checking in will return all \(kitAssignment.itemCount) items in this kit")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Category Section Component

private struct CategorySection: View {
    let categoryName: String
    let items: [EquipmentItem]
    let kitColorHex: String?
    let isExpanded: Bool
    let onToggle: () -> Void
    var onItemTap: ((EquipmentItem) -> Void)? = nil
    var onReportDamage: ((EquipmentItem) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Category header (tap to expand/collapse)
            Button(action: onToggle) {
                HStack {
                    // Category icon
                    Image(systemName: categoryIcon)
                        .foregroundColor(.secondary)
                        .frame(width: 24)

                    // Category name
                    Text(categoryName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    // Item count
                    Text("(\(items.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .cornerRadius(isExpanded ? 10 : 10)
            }
            .buttonStyle(PlainButtonStyle())

            // Items list (shown when expanded)
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        KitItemRow(
                            item: item,
                            kitColorHex: kitColorHex,
                            onTap: { onItemTap?(item) },
                            onReportDamage: { onReportDamage?(item) }
                        )

                        // Divider between items (except last)
                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 65)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .padding(.top, 1)
            }
        }
    }

    // Icon based on category name
    private var categoryIcon: String {
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
}

// MARK: - Preview

struct KitDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            Text("Kit Detail Preview")
        }
    }
}
