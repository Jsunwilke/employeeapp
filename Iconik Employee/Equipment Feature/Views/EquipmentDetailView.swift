//
//  EquipmentDetailView.swift
//  Iconik Employee
//
//  Equipment Management Feature - Equipment Detail View
//

import SwiftUI

struct EquipmentDetailView: View {
    let equipmentId: UUID

    @StateObject private var equipmentService = EquipmentService.shared

    @State private var equipment: EquipmentItem?
    @State private var assignmentHistory: [EquipmentAssignment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var showCheckOut = false
    @State private var showDamageReport = false
    @State private var showRequestForm = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let equipment = equipment {
                contentView(equipment: equipment)
            } else {
                errorView
            }
        }
        .task {
            await loadData()
        }
        .navigationTitle(equipment?.name ?? "Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheckOut) {
            if let equipment = equipment {
                NavigationStack {
                    EquipmentCheckOutView(equipment: equipment)
                }
            }
        }
        .sheet(isPresented: $showDamageReport) {
            if let equipment = equipment {
                NavigationStack {
                    DamageReportView(
                        equipment: equipment,
                        assignmentId: currentAssignment?.id
                    )
                }
            }
        }
        .sheet(isPresented: $showRequestForm) {
            if let equipment = equipment {
                NavigationStack {
                    EquipmentRequestView(equipment: equipment, currentAssignment: currentAssignment)
                }
            }
        }
    }

    // MARK: - Content View

    private func contentView(equipment: EquipmentItem) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Photo section
                photoSection(equipment: equipment)

                // Info section
                infoSection(equipment: equipment)

                // Current assignment section
                if equipment.statusEnum == .checkedOut, let assignment = currentAssignment {
                    currentAssignmentSection(assignment: assignment)
                }

                // Actions section
                actionsSection(equipment: equipment)

                // History section
                if !assignmentHistory.isEmpty {
                    historySection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Equipment Not Found")
                .font(.headline)

            if let error = errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Photo Section

    private func photoSection(equipment: EquipmentItem) -> some View {
        VStack {
            if let photoPath = equipment.photo_url, !photoPath.isEmpty {
                SupabaseImageView(
                    storageURL: photoPath,
                    bucket: "equipment-photos",
                    width: nil,
                    height: 250,
                    contentMode: .fit,
                    cornerRadius: 12
                )
                .frame(maxWidth: .infinity)
            } else {
                photoPlaceholder
            }
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(height: 200)
            .cornerRadius(12)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "camera")
                        .font(.system(size: 40))
                    Text("No Photo")
                        .font(.caption)
                }
                .foregroundColor(.gray)
            )
    }

    // MARK: - Info Section

    private func infoSection(equipment: EquipmentItem) -> some View {
        VStack(spacing: 16) {
            // Status and condition row
            HStack(spacing: 12) {
                EquipmentStatusBadge(status: equipment.statusEnum)
                EquipmentConditionBadge(condition: equipment.conditionEnum)
                Spacer()
            }

            // Info rows
            VStack(alignment: .leading, spacing: 12) {
                if let category = equipment.category {
                    infoRow(label: "Category", value: category.name, icon: "folder")
                }

                if let serial = equipment.serial_number, !serial.isEmpty {
                    infoRow(label: "Serial Number", value: serial, icon: "number")
                }

                if let description = equipment.description, !description.isEmpty {
                    infoRow(label: "Description", value: description, icon: "text.alignleft")
                }

                if let notes = equipment.notes, !notes.isEmpty {
                    infoRow(label: "Notes", value: notes, icon: "note.text")
                }

                if let purchasePrice = equipment.purchase_price {
                    infoRow(label: "Purchase Price", value: String(format: "$%.2f", purchasePrice), icon: "dollarsign.circle")
                }

                if let purchaseDate = equipment.purchase_date {
                    infoRow(label: "Purchase Date", value: formatDate(purchaseDate), icon: "calendar")
                }
            }

            // Kit membership
            if let kitName = getKitMembership(for: equipment) {
                HStack {
                    Image(systemName: "shippingbox.fill")
                        .foregroundColor(.blue)
                    Text("Part of kit: \(kitName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
            }

            Spacer()
        }
    }

    // MARK: - Current Assignment Section

    private func currentAssignmentSection(assignment: EquipmentAssignment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Assignment")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                if let user = assignment.assignedToUser {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.blue)
                        Text("Assigned to: \(user.displayName)")
                            .font(.subheadline)
                    }
                }

                if assignment.isPermanent {
                    HStack {
                        Image(systemName: "infinity")
                            .foregroundColor(.purple)
                        Text("Permanent assignment")
                            .font(.subheadline)
                    }
                } else if let returnDate = assignment.expected_return_date {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(assignment.isOverdue ? .red : .secondary)
                        Text("Due: \(formatDate(returnDate))")
                            .font(.subheadline)
                            .foregroundColor(assignment.isOverdue ? .red : .primary)
                    }
                }

                if let notes = assignment.checkin_notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Actions Section

    private func actionsSection(equipment: EquipmentItem) -> some View {
        VStack(spacing: 12) {
            // Check out button (if available)
            if equipment.statusEnum == .available && canCheckOutForSelf {
                Button {
                    showCheckOut = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.to.line")
                        Text("Check Out")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }

            // Request button (if checked out by someone else)
            if equipment.statusEnum == .checkedOut && !isAssignedToCurrentUser(equipment: equipment) {
                Button {
                    showRequestForm = true
                } label: {
                    HStack {
                        Image(systemName: "hand.raised")
                        Text("Request Equipment")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
            }

            // Report damage button
            Button {
                showDamageReport = true
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Report Damage")
                }
                .font(.subheadline)
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assignment History")
                .font(.headline)

            ForEach(assignmentHistory) { assignment in
                EquipmentAssignmentRow(assignment: assignment)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Helper Methods

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            equipment = try await equipmentService.getEquipmentItem(id: equipmentId)
            assignmentHistory = try await equipmentService.getEquipmentHistory(equipmentId: equipmentId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private var canCheckOutForSelf: Bool {
        true // All users can check out for themselves
    }

    /// Get current (active) assignment from history
    private var currentAssignment: EquipmentAssignment? {
        assignmentHistory.first { $0.isActive }
    }

    private func isAssignedToCurrentUser(equipment: EquipmentItem) -> Bool {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified(),
              let assignment = currentAssignment else {
            return false
        }
        return assignment.assigned_to.uuidString.lowercased() == currentUserId.lowercased()
    }

    private func getKitMembership(for equipment: EquipmentItem) -> String? {
        for kit in equipmentService.kitTemplates {
            if kit.equipmentIds.contains(equipment.id) {
                return kit.name
            }
        }
        return nil
    }
}

// MARK: - Preview

struct EquipmentDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EquipmentDetailView(equipmentId: UUID())
        }
    }
}
