//
//  KitCard.swift
//  Iconik Employee
//
//  Equipment Management Feature - Kit Card Component
//

import SwiftUI

// MARK: - Kit Card (for My Kits view)

struct KitCard: View {
    let kitAssignment: UserKitAssignment

    var body: some View {
        HStack(spacing: 0) {
            // Kit color indicator (left border) - supports rainbow
            if let colorHex = kitAssignment.kitColorHex {
                KitColorBorder(hexColor: colorHex, width: 4)
            }

            HStack(spacing: 12) {
                // Kit icon with color dot
                ZStack(alignment: .topLeading) {
                    Image(systemName: kitAssignment.kitTemplate != nil ? "shippingbox.fill" : "cube.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                    // Color dot overlay (if kit has a color) - supports rainbow
                    if let colorHex = kitAssignment.kitColorHex {
                        KitColorIndicator(hexColor: colorHex, size: 14)
                            .offset(x: -4, y: -4)
                    }
                }

                // Kit info
                VStack(alignment: .leading, spacing: 4) {
                    Text(kitAssignment.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if let kit = kitAssignment.kitTemplate, let description = kit.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    // Item count and return date
                    HStack(spacing: 8) {
                        ItemCountBadge(count: kitAssignment.itemCount)

                        if kitAssignment.isOverdue {
                            OverdueBadge(daysOverdue: kitAssignment.daysOverdue)
                        } else if kitAssignment.isPermanent {
                            PermanentBadge()
                        } else if let returnDate = kitAssignment.expectedReturnDate {
                            ReturnDateBadge(date: returnDate)
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Kit Template Card (for admin/browse view)

struct KitTemplateCard: View {
    let kit: KitTemplate
    var showCheckoutButton: Bool = false
    var onCheckout: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Kit icon with color dot
            ZStack(alignment: .topLeading) {
                Image(systemName: "shippingbox.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                // Color dot overlay (if kit has a color) - supports rainbow
                if let colorHex = kit.color {
                    KitColorIndicator(hexColor: colorHex, size: 14)
                        .offset(x: -4, y: -4)
                }
            }

            // Kit info
            VStack(alignment: .leading, spacing: 4) {
                Text(kit.name)
                    .font(.headline)
                    .lineLimit(1)

                if let description = kit.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Item count and color info
                HStack(spacing: 8) {
                    ItemCountBadge(count: kit.itemCount)

                    if let colorHex = kit.color {
                        HStack(spacing: 4) {
                            KitColorIndicator(hexColor: colorHex, size: 10)
                            Text("Tape color")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            if showCheckoutButton, let onCheckout = onCheckout {
                Button(action: onCheckout) {
                    Text("Check Out")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            } else {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Kit Items List (for kit detail)

struct KitItemsList: View {
    let items: [EquipmentItem]
    let kitColorHex: String?
    var onItemTap: ((EquipmentItem) -> Void)? = nil
    var onReportDamage: ((EquipmentItem) -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                KitItemRow(
                    item: item,
                    kitColorHex: kitColorHex,
                    onTap: { onItemTap?(item) },
                    onReportDamage: { onReportDamage?(item) }
                )
            }
        }
    }
}

// MARK: - Kit Item Row

struct KitItemRow: View {
    let item: EquipmentItem
    let kitColorHex: String?
    var onTap: (() -> Void)? = nil
    var onReportDamage: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Kit color indicator (left border) - supports rainbow
            if let hexColor = kitColorHex {
                KitColorBorder(hexColor: hexColor, width: 3)
            }

            HStack(spacing: 12) {
                // Equipment photo or placeholder
                if let photoPath = item.photo_url, !photoPath.isEmpty {
                    SupabaseImageView(
                        storageURL: photoPath,
                        bucket: "equipment-photos",
                        width: 50,
                        height: 50,
                        contentMode: .fill,
                        cornerRadius: 8
                    )
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 50, height: 50)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "camera")
                                .foregroundColor(.gray)
                        )
                }

                // Item info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let category = item.category {
                            Text(category.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        EquipmentConditionBadge(condition: item.conditionEnum)
                    }

                    if let serial = item.serial_number, !serial.isEmpty {
                        Text("SN: \(serial)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Actions
                if item.statusEnum == .checkedOut {
                    Menu {
                        Button {
                            onTap?()
                        } label: {
                            Label("View Details", systemImage: "info.circle")
                        }

                        Button {
                            onReportDamage?()
                        } label: {
                            Label("Report Damage", systemImage: "exclamationmark.triangle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.secondary)
                            .padding(8)
                    }
                } else {
                    EquipmentStatusBadge(status: item.statusEnum)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Preview

struct KitCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Sample kit assignment card
            Text("Kit Card")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Sample kit template card
            Text("Kit Template Card")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
