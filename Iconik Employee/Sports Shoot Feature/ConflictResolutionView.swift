//
//  ConflictResolutionView.swift
//  Iconik Employee
//
//  Updated to use SyncEngine for conflict resolution
//

import SwiftUI

struct ConflictResolutionView: View {
    let onComplete: (Bool) -> Void

    @ObservedObject private var syncEngine = SyncEngine.shared
    @State private var isResolving = false
    @State private var selectedResolutions: [UUID: ConflictResolution] = [:]

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                if syncEngine.activeConflicts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("No Conflicts")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("All data is synchronized.")
                            .foregroundColor(.secondary)

                        Button("Done") {
                            onComplete(true)
                            presentationMode.wrappedValue.dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    List {
                        // Header explaining the conflict
                        Section(header: Text("Conflicts Detected")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Changes were made both offline and online.")
                                    .font(.headline)

                                Text("Please select which version to keep for each conflicting item.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }

                        // Conflicts
                        Section(header: Text("Conflicting Items (\(syncEngine.activeConflicts.count))")) {
                            ForEach(syncEngine.activeConflicts) { conflict in
                                conflictRow(conflict)
                            }
                        }

                        // Quick resolution buttons
                        Section(header: Text("Quick Resolution")) {
                            Button(action: {
                                useLocalForAll()
                            }) {
                                Label("Keep All Local Changes", systemImage: "iphone")
                                    .foregroundColor(.blue)
                            }

                            Button(action: {
                                useServerForAll()
                            }) {
                                Label("Keep All Server Changes", systemImage: "cloud")
                                    .foregroundColor(.blue)
                            }
                        }

                        // Submit button
                        Section {
                            Button(action: {
                                resolveAllConflicts()
                            }) {
                                HStack {
                                    Spacer()
                                    Text("Apply Resolution")
                                        .fontWeight(.bold)
                                    Spacer()
                                }
                            }
                            .disabled(!allConflictsResolved())
                        }
                    }
                }

                if isResolving {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(
                            VStack {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .padding()

                                Text("Resolving conflicts...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        )
                }
            }
            .navigationTitle("Resolve Conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    // Row for a single conflict
    private func conflictRow(_ conflict: ConflictInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Item info
            HStack {
                VStack(alignment: .leading) {
                    Text(itemTitle(for: conflict))
                        .font(.headline)
                    Text(conflict.itemType == .rosterEntry ? "Athlete" : "Group")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("v\(conflict.localVersion)")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("vs v\(conflict.serverVersion)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            // Resolution options
            HStack(spacing: 12) {
                // Keep Local button
                Button(action: {
                    selectedResolutions[conflict.id] = .keepLocal
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: selectedResolutions[conflict.id] == .keepLocal ? "checkmark.circle.fill" : "iphone")
                            .font(.title2)
                        Text("Keep Local")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedResolutions[conflict.id] == .keepLocal ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedResolutions[conflict.id] == .keepLocal ? Color.green : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Keep Server button
                Button(action: {
                    selectedResolutions[conflict.id] = .keepServer
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: selectedResolutions[conflict.id] == .keepServer ? "checkmark.circle.fill" : "cloud")
                            .font(.title2)
                        Text("Keep Server")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedResolutions[conflict.id] == .keepServer ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedResolutions[conflict.id] == .keepServer ? Color.blue : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Show differences if available
            if let localEntry = conflict.localData as? RosterEntry,
               let serverEntry = conflict.serverData as? RosterEntry {
                VStack(alignment: .leading, spacing: 4) {
                    if localEntry.imageNumbers != serverEntry.imageNumbers {
                        HStack {
                            Text("Images:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Local: \(localEntry.imageNumbers.isEmpty ? "(empty)" : localEntry.imageNumbers)")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Server: \(serverEntry.imageNumbers.isEmpty ? "(empty)" : serverEntry.imageNumbers)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // Get title for conflict item
    private func itemTitle(for conflict: ConflictInfo) -> String {
        if let entry = conflict.localData as? RosterEntry {
            return entry.lastName.isEmpty ? "ID: \(entry.firstName)" : entry.lastName
        } else if let group = conflict.localData as? GroupImage {
            return group.description
        }
        return "Unknown Item"
    }

    // Use local version for all conflicts
    private func useLocalForAll() {
        for conflict in syncEngine.activeConflicts {
            selectedResolutions[conflict.id] = .keepLocal
        }
    }

    // Use server version for all conflicts
    private func useServerForAll() {
        for conflict in syncEngine.activeConflicts {
            selectedResolutions[conflict.id] = .keepServer
        }
    }

    // Check if all conflicts have been resolved
    private func allConflictsResolved() -> Bool {
        syncEngine.activeConflicts.allSatisfy { conflict in
            selectedResolutions[conflict.id] != nil
        }
    }

    // Resolve all conflicts
    private func resolveAllConflicts() {
        isResolving = true

        Task {
            for conflict in syncEngine.activeConflicts {
                if let resolution = selectedResolutions[conflict.id] {
                    await syncEngine.resolveConflict(conflictId: conflict.id, resolution: resolution)
                }
            }

            await MainActor.run {
                isResolving = false

                if syncEngine.activeConflicts.isEmpty {
                    onComplete(true)
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
}

struct ConflictResolutionView_Previews: PreviewProvider {
    static var previews: some View {
        ConflictResolutionView(onComplete: { _ in })
    }
}
