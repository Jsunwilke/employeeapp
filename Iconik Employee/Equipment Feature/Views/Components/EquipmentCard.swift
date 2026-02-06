//
//  EquipmentCard.swift
//  Iconik Employee
//
//  Equipment Management Feature - Equipment Card Component
//

import SwiftUI

// MARK: - Equipment Card (for list views)

struct EquipmentCard: View {
    let item: EquipmentItem
    var kitColor: String? = nil
    var showAssignee: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Kit color indicator (left border)
            if let colorHex = kitColor {
                KitColorBorder(hexColor: colorHex, width: 4)
            }

            HStack(spacing: 12) {
                // Equipment photo or placeholder
                if let photoPath = item.photo_url, !photoPath.isEmpty {
                    SupabaseImageView(
                        storageURL: photoPath,
                        bucket: "equipment-photos",
                        width: 60,
                        height: 60,
                        contentMode: .fill,
                        cornerRadius: 8
                    )
                } else {
                    photoPlaceholder
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
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

                    // Show "Checked Out" indicator if applicable
                    if showAssignee && item.statusEnum == .checkedOut {
                        Text("Currently checked out")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Status badge
                EquipmentStatusBadge(status: item.statusEnum)
            }
            .padding(.horizontal, kitColor != nil ? 8 : 12)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(width: 60, height: 60)
            .cornerRadius(8)
            .overlay(
                Image(systemName: "camera")
                    .foregroundColor(.gray)
            )
    }
}

// MARK: - Compact Equipment Card (for smaller lists)

struct CompactEquipmentCard: View {
    let item: EquipmentItem

    var body: some View {
        HStack(spacing: 10) {
            // Small photo or icon
            if let photoPath = item.photo_url, !photoPath.isEmpty {
                SupabaseImageView(
                    storageURL: photoPath,
                    bucket: "equipment-photos",
                    width: 40,
                    height: 40,
                    contentMode: .fill,
                    cornerRadius: 6
                )
            } else {
                smallPlaceholder
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let category = item.category {
                    Text(category.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Condition indicator
            Circle()
                .fill(item.conditionEnum.color)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }

    private var smallPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(width: 40, height: 40)
            .cornerRadius(6)
            .overlay(
                Image(systemName: "camera")
                    .font(.caption)
                    .foregroundColor(.gray)
            )
    }
}

// MARK: - Equipment Selection Card (for checkout)

struct EquipmentSelectionCard: View {
    let item: EquipmentItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title3)

                // Photo
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
                    selectionPlaceholder
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let category = item.category {
                            Text(category.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        EquipmentConditionBadge(condition: item.conditionEnum)
                    }
                }

                Spacer()

                // Status
                EquipmentStatusBadge(status: item.statusEnum)
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var selectionPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(width: 50, height: 50)
            .cornerRadius(8)
            .overlay(
                Image(systemName: "camera")
                    .foregroundColor(.gray)
            )
    }
}

// MARK: - Equipment Assignment Row (for history)

struct EquipmentAssignmentRow: View {
    let assignment: EquipmentAssignment

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // User and dates
            HStack {
                if let user = assignment.assignedToUser {
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.blue)
                        Text(user.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }

                Spacer()

                if assignment.isActive {
                    Text("Current")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
            }

            // Dates
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Checked Out")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(dateFormatter.string(from: assignment.checked_out_at))
                        .font(.caption)
                }

                if let checkedInAt = assignment.checked_in_at {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Returned")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(dateFormatter.string(from: checkedInAt))
                            .font(.caption)
                    }
                } else if let expectedReturn = assignment.expected_return_date {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Expected Return")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(dateFormatter.string(from: expectedReturn))
                            .font(.caption)
                            .foregroundColor(assignment.isOverdue ? .red : .primary)
                    }
                }
            }

            // Check-in notes
            if let notes = assignment.checkin_notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Return condition
            if let returnCondition = assignment.condition_at_checkin,
               let condition = EquipmentCondition(rawValue: returnCondition) {
                HStack(spacing: 4) {
                    Text("Return condition:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    EquipmentConditionBadge(condition: condition)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Preview

struct EquipmentCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            Text("Equipment Card")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Compact Equipment Card")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
