//
//  EquipmentCheckOutView.swift
//  Iconik Employee
//
//  Equipment Management Feature - Check Out View (Single Item)
//

import SwiftUI

struct EquipmentCheckOutView: View {
    let equipment: EquipmentItem

    @StateObject private var equipmentService = EquipmentService.shared
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @AppStorage("userRole") private var storedUserRole: String = ""
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEmployee: EquipmentUser?
    @State private var expectedReturnDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var isPermanent = false
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var feature: Color { FeatureTheme.color(for: "equipment") }

    var body: some View {
        ZStack {
            AmbientBackdrop()
            formBody.scrollContentBackground(.hidden)
        }
        .navigationTitle("Check Out")
        .navigationBarTitleDisplayMode(.inline)
        .tint(feature)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm") {
                    Task {
                        await checkOut()
                    }
                }
                .disabled(isSubmitting)
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

                        if let serial = equipment.serial_number {
                            Text("SN: \(serial)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        AmbientBadge(text: equipment.conditionEnum.label,
                                     tint: equipment.conditionEnum.color)
                    }
                }
            }

            // Assign to section (admin/manager only)
            if canCheckOutForOthers {
                Section("Assign To") {
                    NavigationLink {
                        EmployeePickerView(selection: $selectedEmployee)
                    } label: {
                        HStack {
                            Text("Employee")
                            Spacer()
                            Text(selectedEmployee?.displayName ?? "Me")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Return date section
            Section("Return Date") {
                Toggle("Permanent Assignment", isOn: $isPermanent)

                if !isPermanent {
                    DatePicker(
                        "Expected Return",
                        selection: $expectedReturnDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                }
            }

            // Notes section
            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
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

    // MARK: - Computed Properties

    private var canCheckOutForOthers: Bool {
        // Phase 7 RBAC — equipment edit covers checking out for other users
        Permissions.has("equipment", level: .edit)
    }

    // MARK: - Methods

    private func checkOut() async {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified(),
              !storedUserOrganizationID.isEmpty else {
            errorMessage = "Unable to get user information"
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            let assignedTo = selectedEmployee?.id ?? UUID(uuidString: currentUserId.lowercased()) ?? UUID()
            let assignedBy = UUID(uuidString: currentUserId.lowercased()) ?? UUID()

            _ = try await equipmentService.checkOutEquipment(
                equipmentId: equipment.id,
                assignedTo: assignedTo,
                assignedBy: assignedBy,
                organizationId: storedUserOrganizationID,
                expectedReturnDate: isPermanent ? nil : expectedReturnDate,
                conditionAtCheckout: equipment.conditionEnum,
                sessionId: nil
            )

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}

// MARK: - Employee Picker View

struct EmployeePickerView: View {
    @Binding var selection: EquipmentUser?
    @Environment(\.dismiss) private var dismiss

    @State private var employees: [EquipmentUser] = []
    @State private var searchText = ""
    @State private var isLoading = true

    var filteredEmployees: [EquipmentUser] {
        if searchText.isEmpty {
            return employees
        }
        return employees.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            ForEach(filteredEmployees) { employee in
                Button {
                    selection = employee
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(employee.displayName)
                                .font(.subheadline)
                            Text(employee.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if selection?.id == employee.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        }
        .searchable(text: $searchText, prompt: "Search employees...")
        .navigationTitle("Select Employee")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task {
            await loadEmployees()
        }
    }

    private func loadEmployees() async {
        // In real implementation, fetch employees from Supabase
        // For now, this is a placeholder
        isLoading = false
    }
}

// MARK: - Preview

struct EquipmentCheckOutView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            Text("Check Out Preview")
        }
    }
}
