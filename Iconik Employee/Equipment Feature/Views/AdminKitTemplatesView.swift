//
//  AdminKitTemplatesView.swift
//  Iconik Employee
//
//  Equipment Management Feature - Admin Kit Templates Management
//

import SwiftUI

struct AdminKitTemplatesView: View {
    @StateObject private var equipmentService = EquipmentService.shared
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading kit templates...")
            } else if equipmentService.kitTemplates.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .navigationTitle("Manage Kits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            await loadKitTemplates()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Views

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Kit Templates")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Kit templates are created in the web app.\nThey define which equipment items belong together.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        List {
            ForEach(equipmentService.kitTemplates) { kit in
                KitTemplateRow(kit: kit)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Methods

    private func loadKitTemplates() async {
        guard !storedUserOrganizationID.isEmpty else { return }

        isLoading = true

        do {
            _ = try await equipmentService.getKitTemplates(organizationId: storedUserOrganizationID)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Kit Template Row

struct KitTemplateRow: View {
    let kit: KitTemplate

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator - supports rainbow
            if let colorHex = kit.color {
                KitColorIndicator(hexColor: colorHex, size: 12)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(kit.name)
                    .font(.headline)

                if let description = kit.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text("\(kit.itemCount) item\(kit.itemCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status
            if kit.is_active {
                Text("Active")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("Inactive")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

struct AdminKitTemplatesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AdminKitTemplatesView()
        }
    }
}
