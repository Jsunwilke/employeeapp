import SwiftUI

struct BatchAddAthletesView: View {
    let shootID: UUID
    let organizationId: String
    let onComplete: (Bool) -> Void

    // PowerSync for offline-first operations
    @StateObject private var powerSync = PowerSyncManager.shared

    @State private var sportName: String = ""
    @State private var numberOfAthletes: String = "10"
    @State private var startingSubjectID: Int = 101
    @State private var specialField: String = ""

    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var isLoadingExisting = true

    @Environment(\.presentationMode) var presentationMode

    // Computed property for preview entries
    private var previewEntries: [PreviewEntry] {
        guard let count = Int(numberOfAthletes),
              count > 0,
              count <= 100 else { return [] }

        return (0..<count).map { index in
            PreviewEntry(
                id: UUID(),
                subjectID: "\(startingSubjectID + index)",
                groupName: sportName.uppercased(),
                teacher: specialField
            )
        }
    }

    // Simple preview struct for display
    private struct PreviewEntry: Identifiable {
        let id: UUID
        let subjectID: String
        let groupName: String
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
                        Text("Starting Subject ID")
                        Spacer()
                        if isLoadingExisting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("\(startingSubjectID)")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }

                Section(header: Text("Preview (\(previewEntries.count) athletes)")) {
                    if previewEntries.isEmpty {
                        Text("Enter valid number of athletes (1-100)")
                            .foregroundColor(.secondary)
                            .italic()
                    } else if previewEntries.count > 20 {
                        // Show first 5 and last 5 for large batches
                        ForEach(previewEntries.prefix(5)) { entry in
                            previewRow(for: entry)
                        }

                        HStack {
                            Spacer()
                            Text("... \(previewEntries.count - 10) more entries ...")
                                .foregroundColor(.secondary)
                                .italic()
                            Spacer()
                        }
                        .padding(.vertical, 4)

                        ForEach(previewEntries.suffix(5)) { entry in
                            previewRow(for: entry)
                        }
                    } else {
                        ForEach(previewEntries) { entry in
                            previewRow(for: entry)
                        }
                    }
                }

                Section(header: Text("Notes")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Athletes will be created with blank names")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("• Subject IDs will auto-increment from \(startingSubjectID)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("• You can edit individual athletes after creation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Creating athletes...")
                        Spacer()
                    }
                }
            }
            .navigationBarTitle("Batch Add Athletes", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Athletes") {
                        batchAddAthletes()
                    }
                    .fontWeight(.semibold)
                    .disabled(sportName.isEmpty || previewEntries.isEmpty || isLoading)
                }
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .onAppear {
            loadHighestSubjectID()
        }
    }

    @ViewBuilder
    private func previewRow(for entry: PreviewEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("ID: \(entry.subjectID)")
                    .font(.headline)
                    .foregroundColor(.blue)

                Spacer()

                if !entry.groupName.isEmpty {
                    Text(entry.groupName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            if !entry.teacher.isEmpty {
                Text("Special: \(entry.teacher)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("(Name to be added later)")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(.vertical, 2)
    }

    private func loadHighestSubjectID() {
        isLoadingExisting = true

        Task {
            do {
                let entries = try await powerSync.getRosterEntries(forJob: shootID)

                // Find the highest Subject ID value
                let highestID = entries.compactMap { entry -> Int? in
                    return Int(entry.firstName)
                }.max() ?? 100

                await MainActor.run {
                    self.startingSubjectID = highestID + 1
                    self.isLoadingExisting = false
                }
            } catch {
                await MainActor.run {
                    // Use default starting ID
                    self.startingSubjectID = 101
                    self.isLoadingExisting = false
                }
            }
        }
    }

    private func batchAddAthletes() {
        guard !sportName.isEmpty,
              let count = Int(numberOfAthletes),
              count > 0,
              count <= 100 else {
            errorMessage = "Please enter valid sport name and number of athletes (1-100)"
            showingErrorAlert = true
            return
        }

        isLoading = true

        Task {
            var allSuccess = true

            // Save all entries to PowerSync (auto-syncs when online)
            for index in 0..<count {
                let entry = RosterEntry(
                    id: UUID(),
                    sportsJobId: shootID,
                    organizationId: organizationId,
                    lastName: "",
                    firstName: "\(startingSubjectID + index)",
                    teacher: specialField,
                    groupName: sportName.uppercased(),
                    email: "",
                    phone: "",
                    imageNumbers: "",
                    notes: "",
                    sortOrder: index,
                    version: 1,
                    updatedAt: Date(),
                    updatedBy: nil,
                    lockedBy: nil,
                    lockedByName: nil,
                    lockedAt: nil,
                    createdAt: Date()
                )

                var saved = false
                for attempt in 1...3 {
                    do {
                        try await powerSync.saveRosterEntry(entry)
                        saved = true
                        break
                    } catch {
                        print("BatchAddAthletesView: Save attempt \(attempt)/3 for entry \(index + 1): \(error)")
                        if attempt < 3 {
                            try? await Task.sleep(nanoseconds: UInt64(500_000_000 * attempt))
                        }
                    }
                }
                if !saved {
                    allSuccess = false
                }
            }

            await MainActor.run {
                isLoading = false
                onComplete(allSuccess)
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

// Preview
struct BatchAddAthletesView_Previews: PreviewProvider {
    static var previews: some View {
        BatchAddAthletesView(shootID: UUID(), organizationId: "") { _ in }
    }
}
