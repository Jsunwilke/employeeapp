//
//  EquipmentCheckInView.swift
//  Iconik Employee
//
//  Equipment Management Feature - Check In View
//

import SwiftUI

struct EquipmentCheckInView: View {
    let assignments: [EquipmentAssignment]
    let items: [EquipmentItem]
    var kitName: String?

    @StateObject private var equipmentService = EquipmentService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var returnConditions: [UUID: EquipmentCondition] = [:]
    @State private var returnNotes = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var feature: Color { FeatureTheme.color(for: "equipment") }

    var body: some View {
        ZStack {
            AmbientBackdrop()
            formBody.scrollContentBackground(.hidden)
        }
        .navigationTitle("Check In")
        .navigationBarTitleDisplayMode(.inline)
        .tint(feature)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Check In") {
                    Task {
                        await checkIn()
                    }
                }
                .disabled(isSubmitting)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .onAppear {
            // Initialize return conditions with current conditions
            for item in items {
                returnConditions[item.id] = item.conditionEnum
            }
        }
    }

    private var formBody: some View {
        Form {
            // Header section
            if let kitName = kitName {
                Section {
                    HStack {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(feature)
                        Text("Returning Kit: \(kitName)")
                            .font(.headline)
                    }
                }
            }

            // Items section
            Section("Items to Return (\(items.count))") {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        // Item info
                        HStack(spacing: 12) {
                            EquipmentFormThumbnail(photoPath: item.photo_url, side: 50)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                if let category = item.category {
                                    Text(category.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Return condition picker
                        Picker("Return Condition", selection: conditionBinding(for: item.id)) {
                            ForEach(EquipmentCondition.allCases, id: \.self) { condition in
                                HStack {
                                    Circle()
                                        .fill(condition.color)
                                        .frame(width: 8, height: 8)
                                    Text(condition.label)
                                }
                                .tag(condition)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Notes section
            Section("Return Notes") {
                TextEditor(text: $returnNotes)
                    .frame(minHeight: 80)

                Text("Add any notes about the condition or issues with the returned equipment")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Error message
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Methods

    private func conditionBinding(for itemId: UUID) -> Binding<EquipmentCondition> {
        Binding(
            get: { returnConditions[itemId] ?? .good },
            set: { returnConditions[itemId] = $0 }
        )
    }

    private func checkIn() async {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified(),
              let checkedInByUUID = UUID(uuidString: currentUserId.lowercased()) else {
            errorMessage = "Unable to get user information"
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            if kitName != nil {
                // Check in all items as a kit
                try await equipmentService.checkInKit(
                    assignments: assignments,
                    checkedInBy: checkedInByUUID,
                    returnConditions: returnConditions,
                    checkinNotes: returnNotes.isEmpty ? nil : returnNotes
                )
            } else {
                // Check in individual items
                for assignment in assignments {
                    try await equipmentService.checkInEquipment(
                        assignmentId: assignment.id,
                        equipmentId: assignment.equipment_id,
                        checkedInBy: checkedInByUUID,
                        returnCondition: returnConditions[assignment.equipment_id],
                        checkinNotes: returnNotes.isEmpty ? nil : returnNotes
                    )
                }
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}

// MARK: - Preview

struct EquipmentCheckInView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            Text("Check In Preview")
        }
    }
}
