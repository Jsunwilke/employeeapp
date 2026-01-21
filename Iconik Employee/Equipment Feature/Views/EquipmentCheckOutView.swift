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

    var body: some View {
        Form {
            // Equipment info section
            Section("Equipment") {
                HStack(spacing: 12) {
                    if let photoPath = equipment.photo_url, !photoPath.isEmpty {
                        SupabaseImageView(
                            storageURL: photoPath,
                            bucket: "equipment-photos",
                            width: 60,
                            height: 60,
                            contentMode: .fill,
                            cornerRadius: 8
                        )
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .overlay(
                                Image(systemName: "camera")
                                    .foregroundColor(.gray)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(equipment.name)
                            .font(.headline)

                        if let serial = equipment.serial_number {
                            Text("SN: \(serial)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        EquipmentConditionBadge(condition: equipment.conditionEnum)
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
        .navigationTitle("Check Out")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Computed Properties

    private var canCheckOutForOthers: Bool {
        guard !storedUserRole.isEmpty else { return false }
        return ["admin", "manager"].contains(storedUserRole.lowercased())
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
