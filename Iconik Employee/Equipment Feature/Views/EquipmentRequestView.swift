//
//  EquipmentRequestView.swift
//  Iconik Employee
//
//  Equipment Management Feature - Equipment Request View
//

import SwiftUI

struct EquipmentRequestView: View {
    let equipment: EquipmentItem
    var currentAssignment: EquipmentAssignment?

    @StateObject private var equipmentService = EquipmentService.shared
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @Environment(\.dismiss) private var dismiss

    @State private var requestedDate = Date()
    @State private var requestedReturnDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var feature: Color { FeatureTheme.color(for: "equipment") }

    var body: some View {
        ZStack {
            AmbientBackdrop()
            formBody.scrollContentBackground(.hidden)
        }
        .navigationTitle("Request Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .tint(feature)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Submit") {
                    Task {
                        await submitRequest()
                    }
                }
                .disabled(reason.isEmpty || isSubmitting)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var formBody: some View {
        Form {
            // Equipment info section
            Section("Equipment") {
                HStack(spacing: 12) {
                    EquipmentFormThumbnail(photoPath: equipment.photo_url)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(equipment.name)
                            .font(.headline)

                        if let category = equipment.category {
                            Text(category.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        AmbientBadge(text: equipment.statusEnum.label,
                                     systemImage: equipment.statusEnum.systemImage,
                                     tint: equipment.statusEnum.color)
                    }
                }
            }

            // Current status info
            if let assignment = currentAssignment,
               let user = assignment.assignedToUser {
                Section("Currently Assigned") {
                    HStack {
                        AmbientAvatar(name: user.displayName, size: 28)
                        Text(user.displayName)

                        Spacer()

                        if let returnDate = assignment.expected_return_date {
                            Text("Due: \(formatDate(returnDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Request dates section
            Section("Request Details") {
                DatePicker(
                    "When Needed",
                    selection: $requestedDate,
                    in: Date()...,
                    displayedComponents: .date
                )

                DatePicker(
                    "Return By",
                    selection: $requestedReturnDate,
                    in: requestedDate...,
                    displayedComponents: .date
                )
            }

            // Reason section
            Section("Reason") {
                TextEditor(text: $reason)
                    .frame(minHeight: 80)

                Text("Explain why you need this equipment and what you'll use it for")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Info section
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(feature)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Request Process")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Your request will be reviewed by a manager. You'll be notified when it's approved or denied.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
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

    private func formatDate(_ date: Date) -> String {
        Formatters.mediumDate.string(from: date)
    }

    private func submitRequest() async {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified(),
              !storedUserOrganizationID.isEmpty else {
            errorMessage = "Unable to get user information"
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            let userId = UUID(uuidString: currentUserId.lowercased()) ?? UUID()

            _ = try await equipmentService.createRequest(
                equipmentId: equipment.id,
                requestedBy: userId,
                organizationId: storedUserOrganizationID,
                neededFrom: requestedDate,
                neededUntil: requestedReturnDate,
                requestNotes: reason.isEmpty ? nil : reason,
                sessionId: nil
            )

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}

// MARK: - Preview

struct EquipmentRequestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            Text("Equipment Request Preview")
        }
    }
}
