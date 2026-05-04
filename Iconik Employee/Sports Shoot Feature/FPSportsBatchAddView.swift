//
//  FPSportsBatchAddView.swift
//  Iconik Employee
//
//  Batch add blank FPSubject entries for FP Sports.
//  Parallel to BatchAddAthletesView but writes to Production subjects table.
//

import SwiftUI

struct FPSportsBatchAddView: View {
    let galleryId: String
    let organizationId: String
    /// Called on save complete. Second arg is the list of optimistic subjects
    /// the caller can splice into its in-memory list so the UI shows the new
    /// rows immediately (without waiting for Surface→Supabase→PowerSync
    /// round-trip). Empty on cancel/failure.
    let onComplete: (Bool, [FPSubject]) -> Void

    private let powerSync = PowerSyncManager.shared

    @State private var sportName: String = ""
    @State private var numberOfAthletes: String = "10"
    @State private var startingRosterId: Int = 101
    @State private var specialField: String = ""

    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var isLoadingExisting = true
    @State private var existingSubjects: [FPSubject] = []

    // Duplicate roster ID warning
    @State private var showingDuplicateWarning = false
    @State private var duplicateRosterIds: [String] = []
    @State private var pendingBatchSubjects: [FPSubject] = []

    @Environment(\.presentationMode) var presentationMode

    private var previewEntries: [PreviewEntry] {
        guard let count = Int(numberOfAthletes), count > 0, count <= 100 else { return [] }
        return (0..<count).map { index in
            PreviewEntry(id: UUID(), rosterId: "\(startingRosterId + index)", sport: sportName.uppercased(), teacher: specialField)
        }
    }

    private struct PreviewEntry: Identifiable {
        let id: UUID
        let rosterId: String
        let sport: String
        let teacher: String
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Batch Configuration")) {
                    TextField("Sport/Team Name", text: $sportName)
                        .autocapitalization(.words)

                    HStack {
                        Text("Number of Athletes")
                        Spacer()
                        TextField("10", text: $numberOfAthletes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }

                    TextField("Grade/Special (optional)", text: $specialField)
                        .autocapitalization(.words)

                    HStack {
                        Text("Starting Roster ID")
                        Spacer()
                        if isLoadingExisting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("\(startingRosterId)")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }

                Section(header: Text("Preview (\(previewEntries.count) athletes)")) {
                    if previewEntries.isEmpty {
                        Text("Enter valid number of athletes (1-100)")
                            .foregroundColor(.secondary).italic()
                    } else if previewEntries.count > 20 {
                        ForEach(previewEntries.prefix(5)) { entry in previewRow(for: entry) }
                        HStack {
                            Spacer()
                            Text("... \(previewEntries.count - 10) more entries ...")
                                .foregroundColor(.secondary).italic()
                            Spacer()
                        }.padding(.vertical, 4)
                        ForEach(previewEntries.suffix(5)) { entry in previewRow(for: entry) }
                    } else {
                        ForEach(previewEntries) { entry in previewRow(for: entry) }
                    }
                }

                Section(header: Text("Notes")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Athletes will be created with blank names").font(.caption).foregroundColor(.secondary)
                        Text("• Roster IDs will auto-increment from \(startingRosterId)").font(.caption).foregroundColor(.secondary)
                        Text("• You can edit individual athletes after creation").font(.caption).foregroundColor(.secondary)
                    }.padding(.vertical, 4)
                }

                if isLoading {
                    HStack { Spacer(); ProgressView("Creating athletes..."); Spacer() }
                }
            }
            .navigationBarTitle("Batch Add Athletes", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Athletes") { batchAdd() }
                        .fontWeight(.semibold)
                        .disabled(sportName.isEmpty || previewEntries.isEmpty || isLoading)
                }
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
            .alert(isPresented: $showingDuplicateWarning) {
                Alert(
                    title: Text("Duplicate Roster IDs"),
                    message: Text("These roster IDs already exist: \(duplicateRosterIds.joined(separator: ", ")). Continue anyway?"),
                    primaryButton: .default(Text("Continue")) {
                        executeBatchInsert(pendingBatchSubjects)
                        pendingBatchSubjects = []
                        duplicateRosterIds = []
                    },
                    secondaryButton: .cancel {
                        pendingBatchSubjects = []
                        duplicateRosterIds = []
                    }
                )
            }
        }
        .onAppear { loadHighestRosterId() }
    }

    @ViewBuilder
    private func previewRow(for entry: PreviewEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("ID: \(entry.rosterId)").font(.headline).foregroundColor(.blue)
                Spacer()
                if !entry.sport.isEmpty {
                    Text(entry.sport).font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1)).cornerRadius(4)
                }
            }
            if !entry.teacher.isEmpty {
                Text("Special: \(entry.teacher)").font(.caption).foregroundColor(.secondary)
            }
            Text("(Name to be added later)").font(.caption).foregroundColor(.secondary).italic()
        }.padding(.vertical, 2)
    }

    private func loadHighestRosterId() {
        isLoadingExisting = true
        Task {
            do {
                let subjects = try await powerSync.getSubjects(forGalleryId: galleryId)
                let highestID = subjects.compactMap { Int($0.rosterId) }.max() ?? 100
                await MainActor.run {
                    existingSubjects = subjects
                    startingRosterId = highestID + 1
                    isLoadingExisting = false
                }
            } catch {
                await MainActor.run {
                    startingRosterId = 101
                    isLoadingExisting = false
                }
            }
        }
    }

    private func batchAdd() {
        guard !sportName.isEmpty,
              let count = Int(numberOfAthletes), count > 0, count <= 100 else {
            errorMessage = "Please enter valid sport name and number of athletes (1-100)"
            showingErrorAlert = true
            return
        }

        // Collect all subjects first
        var subjects: [FPSubject] = []
        for index in 0..<count {
            subjects.append(FPSubject(
                galleryId: galleryId,
                organizationId: organizationId,
                firstName: "",
                lastName: "",
                grade: "",
                teacher: specialField,
                homeroom: "",
                studentId: "",
                rosterId: "\(startingRosterId + index)",
                jerseyNumber: "",
                sport: sportName.uppercased(),
                position: "",
                email: "",
                phone: "",
                updatedAt: Date()
            ))
        }

        // Check for duplicate roster IDs against existing subjects
        let existingRosterIds = Set(existingSubjects.compactMap { $0.rosterId.isEmpty ? nil : $0.rosterId })
        let newRosterIds = subjects.map { $0.rosterId }
        let dupes = newRosterIds.filter { existingRosterIds.contains($0) }
        if !dupes.isEmpty {
            pendingBatchSubjects = subjects
            duplicateRosterIds = dupes
            showingDuplicateWarning = true
            return
        }

        executeBatchInsert(subjects)
    }

    private func executeBatchInsert(_ subjects: [FPSubject]) {
        isLoading = true
        Task {
            // Phase C C.4: route through SubjectSyncService.batchCreateSubjects.
            // Connected branch sends one insert_subjects command (Surface
            // owns the cloud writes); fallback path falls back to per-row
            // createSubject so a transient write failure on one row no
            // longer cascades. The previous per-row 3-retry +
            // optimisticSubjects-of-the-successful-rows pattern collapses:
            // batch-side failures from the connected ack are now
            // all-or-nothing (ack rejects → none acked → fallback path
            // retries each row). Failure UX simplifies to a generic
            // "no batch ack" path; per-row IDs in the failure message are
            // sacrificed alongside the alert when SubjectSyncEvents
            // becomes the failure surface (Phase J restores the visible
            // alert via event subscription).
            _ = await SubjectSyncService.shared.batchCreateSubjects(
                subjects,
                sourcePath: "FPSportsBatchAddView.executeBatchInsert"
            )
            await MainActor.run {
                isLoading = false
                onComplete(true, subjects)
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}
