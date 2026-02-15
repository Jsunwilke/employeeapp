//
//  AddGroupImageView.swift
//  Iconik Employee
//
//  Created by administrator on 5/13/25.
//


import SwiftUI

struct AddGroupImageView: View {
    let shootID: UUID
    let existingGroup: GroupImage?
    let onComplete: (Bool) -> Void

    // PowerSync for offline-first operations
    @StateObject private var powerSync = PowerSyncManager.shared
    @StateObject private var lockManager = LockManager.shared

    @State private var description: String = ""
    @State private var imageNumbers: String = ""
    @State private var notes: String = ""
    @State private var selectedSport: String = ""
    @State private var selectedGender: String = ""
    @State private var selectedTeamLevel: String = ""
    @State private var useCustomDescription: Bool = false
    @State private var availableSports: [String] = []
    @State private var isLoadingSports = true

    // Gender options
    let genderOptions = ["Boys", "Girls", "Co-ed"]

    // Team level options
    let teamLevels = ["Varsity", "Junior Varsity (JV)", "C-Team", "Freshman", "Sophomore", "Modified", "Custom"]

    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false

    // Lock state for editing existing groups
    @State private var lockAcquired = false
    @State private var lockError: String?
    @State private var isAcquiringLock = false

    @Environment(\.presentationMode) var presentationMode

    var isEditing: Bool {
        existingGroup != nil
    }

    var body: some View {
        NavigationView {
            // Show lock error if we couldn't get lock
            if let error = lockError {
                lockErrorView(error)
            } else if isAcquiringLock {
                acquiringLockView
            } else {
                formContent
            }
        }
        .task {
            await acquireLockIfNeeded()
        }
        .onDisappear {
            releaseLockIfNeeded()
        }
    }

    // MARK: - Lock Error View

    private func lockErrorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("Cannot Edit")
                .font(.title2)
                .fontWeight(.bold)

            Text(error)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button("Go Back") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
        .navigationBarTitle("Locked", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    // MARK: - Acquiring Lock View

    private var acquiringLockView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Acquiring lock...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitle(isEditing ? "Edit Group" : "Add Group", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    // MARK: - Form Content

    private var formContent: some View {
        Form {
                Section(header: Text("Group Information")) {
                    // Sport selection
                    if isLoadingSports {
                        HStack {
                            Text("Loading sports...")
                                .foregroundColor(.secondary)
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    } else if !availableSports.isEmpty {
                        Picker("Sport/Team", selection: $selectedSport) {
                            Text("Select Sport").tag("")
                            ForEach(availableSports, id: \.self) { sport in
                                Text(sport).tag(sport)
                            }
                        }
                        .onChange(of: selectedSport) { _ in
                            updateDescription()
                        }
                    }

                    // Gender selection
                    if !selectedSport.isEmpty {
                        Picker("Gender", selection: $selectedGender) {
                            Text("Select Gender (Optional)").tag("")
                            ForEach(genderOptions, id: \.self) { gender in
                                Text(gender).tag(gender)
                            }
                        }
                        .onChange(of: selectedGender) { _ in
                            updateDescription()
                        }
                    }

                    // Team level selection
                    if !selectedSport.isEmpty {
                        Picker("Team Level", selection: $selectedTeamLevel) {
                            Text("Select Level").tag("")
                            ForEach(teamLevels, id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                        .onChange(of: selectedTeamLevel) { _ in
                            updateDescription()
                        }
                    }

                    // Description field
                    VStack(alignment: .leading) {
                        Toggle("Custom Description", isOn: $useCustomDescription)
                            .font(.caption)

                        TextField("Description", text: $description)
                            .autocapitalization(.sentences)
                            .disabled(!useCustomDescription && !selectedSport.isEmpty)
                    }
                }

                Section(header: Text("Image Information")) {
                    TextField("Image Numbers", text: $imageNumbers)
                        .keyboardType(.asciiCapable)
                        .autocapitalization(.none)

                    TextView(text: $notes, placeholder: "Notes (optional)")
                        .frame(minHeight: 100)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .navigationBarTitle(isEditing ? "Edit Group" : "Add Group", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Update" : "Save") {
                        saveGroupImage()
                    }
                    .disabled(description.isEmpty)
                }
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                loadExistingGroupData()
                loadAvailableSports()
            }
    }

    // MARK: - Lock Management

    private func acquireLockIfNeeded() async {
        guard let group = existingGroup else {
            // New group - no lock needed
            lockAcquired = true
            return
        }

        isAcquiringLock = true

        // Try to acquire lock
        let acquired = await lockManager.acquireGroupImageLock(groupId: group.id)

        await MainActor.run {
            isAcquiringLock = false
            if acquired {
                lockAcquired = true
            } else {
                // Check who has the lock
                if let lockedByName = group.lockedByName {
                    lockError = "This group is being edited by \(lockedByName). Please try again later."
                } else {
                    lockError = "This group is being edited by another photographer. Please try again later."
                }
            }
        }
    }

    private func releaseLockIfNeeded() {
        guard let group = existingGroup, lockAcquired else { return }

        Task {
            await lockManager.releaseGroupImageLock(groupId: group.id)
        }
    }

    private func loadExistingGroupData() {
        if let group = existingGroup {
            description = group.description
            imageNumbers = group.imageNumbers
            notes = group.notes
            selectedSport = group.sport
            selectedGender = group.gender
            selectedTeamLevel = group.teamLevel
            // Check if description was auto-generated
            useCustomDescription = !isAutoGeneratedDescription()
        }
    }

    private func loadAvailableSports() {
        isLoadingSports = true

        Task {
            do {
                let entries = try await powerSync.getRosterEntries(forJob: shootID)
                let allGroups = Set(entries.map { $0.groupName })
                let sports = Array(allGroups).filter { !$0.isEmpty }.sorted()

                await MainActor.run {
                    self.availableSports = sports
                    self.isLoadingSports = false

                    // For new groups, check if there's only one sport in the roster
                    if existingGroup == nil && sports.count == 1 {
                        selectedSport = sports[0]
                        updateDescription()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSports = false
                }
            }
        }
    }

    // Update description based on selections
    private func updateDescription() {
        guard !useCustomDescription else { return }

        if !selectedSport.isEmpty {
            var components = [selectedSport]

            if !selectedGender.isEmpty {
                components.append(selectedGender)
            }

            if !selectedTeamLevel.isEmpty && selectedTeamLevel != "Custom" {
                components.append(selectedTeamLevel)
            }

            description = components.joined(separator: " - ")
        }
    }

    // Check if current description matches auto-generated format
    private func isAutoGeneratedDescription() -> Bool {
        if selectedSport.isEmpty { return false }

        var components = [selectedSport]

        if !selectedGender.isEmpty {
            components.append(selectedGender)
        }

        if !selectedTeamLevel.isEmpty && selectedTeamLevel != "Custom" {
            components.append(selectedTeamLevel)
        }

        let expectedDescription = components.joined(separator: " - ")
        return description == expectedDescription
    }

    private func saveGroupImage() {
        let group = GroupImage(
            id: existingGroup?.id ?? UUID(),
            sportsJobId: shootID,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            sport: selectedSport,
            gender: selectedGender,
            teamLevel: selectedTeamLevel,
            sortOrder: existingGroup?.sortOrder ?? 0,
            version: (existingGroup?.version ?? 0) + 1,  // Increment version for conflict detection
            updatedAt: Date(),
            updatedBy: existingGroup?.updatedBy,
            lockedBy: existingGroup?.lockedBy,
            lockedByName: existingGroup?.lockedByName,
            lockedAt: existingGroup?.lockedAt,
            createdAt: existingGroup?.createdAt ?? Date()
        )

        // Save to PowerSync with retry (auto-syncs when online)
        Task {
            var retries = 0
            var lastError: Error?
            while retries < 3 {
                do {
                    try await powerSync.saveGroupImage(group)
                    await MainActor.run {
                        onComplete(true)
                        presentationMode.wrappedValue.dismiss()
                    }
                    return
                } catch {
                    lastError = error
                    retries += 1
                    print("AddGroupImageView: Save retry \(retries)/3: \(error)")
                    if retries < 3 {
                        try? await Task.sleep(nanoseconds: UInt64(500_000_000 * retries))
                    }
                }
            }
            await MainActor.run {
                errorMessage = "Failed to save after 3 attempts: \(lastError?.localizedDescription ?? "Unknown error")"
                showingErrorAlert = true
            }
        }
    }
}

struct AddGroupImageView_Previews: PreviewProvider {
    static var previews: some View {
        AddGroupImageView(
            shootID: UUID(),
            existingGroup: nil,
            onComplete: { _ in }
        )
    }
}
