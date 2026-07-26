//
//  DamageReportView.swift
//  Iconik Employee
//
//  Equipment Management Feature - Damage Report View
//

import SwiftUI
import PhotosUI
import UIKit

struct DamageReportView: View {
    let equipment: EquipmentItem
    var assignmentId: UUID?

    @StateObject private var equipmentService = EquipmentService.shared
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var severity: DamageSeverity = .minor
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoData: [Data] = []
    @State private var isLoadingPhotos = false
    @State private var isSubmitting = false
    @State private var submitProgress: String = ""
    @State private var errorMessage: String?

    private var feature: Color { FeatureTheme.color(for: "equipment") }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature)
            formBody.scrollContentBackground(.hidden)
        }
        .navigationTitle("Report Damage")
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
                        await submitReport()
                    }
                }
                .disabled(description.isEmpty || isSubmitting)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .overlay {
            if isSubmitting {
                submittingOverlay
            }
        }
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

                        AmbientBadge(text: equipment.statusEnum.label,
                                     systemImage: equipment.statusEnum.systemImage,
                                     tint: equipment.statusEnum.color)
                    }
                }
            }

            // Damage description section
            Section("Damage Description") {
                TextEditor(text: $description)
                    .frame(minHeight: 100)

                Text("Describe the damage in detail. What happened? Where is the damage located?")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Severity section
            Section("Severity") {
                Picker("Damage Severity", selection: $severity) {
                    ForEach(DamageSeverity.allCases, id: \.self) { level in
                        HStack {
                            Circle()
                                .fill(level.color)
                                .frame(width: 12, height: 12)
                            Text(level.label)
                        }
                        .tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                // Severity description
                Text(severity.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Photos section
            Section("Photos (Optional)") {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Select Photos")
                    }
                }
                .onChange(of: selectedPhotos) { newPhotos in
                    Task {
                        await loadPhotos(from: newPhotos)
                    }
                }

                if isLoadingPhotos {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading photos...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !photoData.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(photoData.indices, id: \.self) { index in
                                if let uiImage = UIImage(data: photoData[index]) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 80, height: 80)
                                            .cornerRadius(8)
                                            .clipped()

                                        Button {
                                            withAnimation {
                                                photoData.remove(at: index)
                                                if index < selectedPhotos.count {
                                                    selectedPhotos.remove(at: index)
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.black.opacity(0.5)))
                                        }
                                        .offset(x: 4, y: -4)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 90)
                }

                Text("Add up to 5 photos showing the damage")
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

    /// The per-photo progress overlay, kept: uploading five photos on a bad
    /// connection is the one place in this feature where the user needs to be told
    /// what is happening.
    private var submittingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text(submitProgress)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .ambientCard(density: .hero, state: .highlighted)
        }
    }

    // MARK: - Methods

    @MainActor
    private func loadPhotos(from items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        photoData.removeAll()

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                photoData.append(data)
            }
        }

        isLoadingPhotos = false
    }

    @MainActor
    private func submitReport() async {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified(),
              !storedUserOrganizationID.isEmpty else {
            errorMessage = "Unable to get user information"
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            let userId = UUID(uuidString: currentUserId.lowercased()) ?? UUID()

            // Use a consistent ID for all photos in this report
            let reportId = UUID()
            var photoUrls: [String] = []

            // Upload photos first (if any)
            if !photoData.isEmpty {
                submitProgress = "Uploading photos..."
                for (index, data) in photoData.enumerated() {
                    submitProgress = "Uploading photo \(index + 1) of \(photoData.count)..."
                    let path = try await equipmentService.uploadDamagePhoto(
                        damageReportId: reportId,
                        organizationId: storedUserOrganizationID,
                        imageData: data
                    )
                    photoUrls.append(path)
                }
            }

            // Create damage report
            submitProgress = "Submitting report..."
            _ = try await equipmentService.createDamageReport(
                equipmentId: equipment.id,
                reportedBy: userId,
                organizationId: storedUserOrganizationID,
                description: description,
                severity: severity,
                photoUrls: photoUrls.isEmpty ? nil : photoUrls,
                assignmentId: assignmentId
            )

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}

// MARK: - Preview

struct DamageReportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            Text("Damage Report Preview")
        }
    }
}
