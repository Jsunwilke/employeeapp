import SwiftUI
import Firebase
import FirebaseFirestore

struct ConflictResolutionView: View {
    let shootID: String
    let entryConflicts: [OfflineManager.EntryConflict]
    let groupConflicts: [OfflineManager.GroupConflict]
    let localShoot: SportsShoot
    let remoteShoot: SportsShoot
    let onComplete: (Bool) -> Void
    
    @State private var useLocalEntries: Set<String> = []
    @State private var useRemoteEntries: Set<String> = []
    @State private var useLocalGroups: Set<String> = []
    @State private var useRemoteGroups: Set<String> = []
    @State private var isResolving = false
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                List {
                    // Header explaining the conflict
                    Section(header: Text("Conflicts Detected")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Changes were made to this shoot both offline and online.")
                                .font(.headline)
                            
                            Text("Please select which version to keep for each conflicting item.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Entry conflicts
                    if !entryConflicts.isEmpty {
                        Section(header: Text("Athlete Conflicts")) {
                            ForEach(entryConflicts, id: \.localEntry.id) { conflict in
                                entryConflictRow(conflict)
                            }
                        }
                    }
                    
                    // Group conflicts
                    if !groupConflicts.isEmpty {
                        Section(header: Text("Group Conflicts")) {
                            ForEach(groupConflicts, id: \.localGroup.id) { conflict in
                                groupConflictRow(conflict)
                            }
                        }
                    }
                    
                    // Quick resolution buttons
                    Section(header: Text("Quick Resolution")) {
                        Button(action: {
                            useLocalForAll()
                        }) {
                            Text("Use All Local Changes")
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            useRemoteForAll()
                        }) {
                            Text("Use All Server Changes")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Submit button
                    Section {
                        Button(action: {
                            resolveConflicts()
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
    
    // Row for entry conflict
    private func entryConflictRow(_ conflict: OfflineManager.EntryConflict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(conflict.localEntry.lastName)
                        .font(.headline)
                    Text("ID: \(conflict.localEntry.firstName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("Choose Version")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                // Local version button
                Button(action: {
                    toggleLocalEntry(conflict.localEntry.id)
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Your Device")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if useLocalEntries.contains(conflict.localEntry.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Text("Images: \(conflict.localEntry.imageNumbers)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(useLocalEntries.contains(conflict.localEntry.id) ? Color.green : Color.gray, lineWidth: 1)
                    )
                }
                
                // Remote version button
                Button(action: {
                    toggleRemoteEntry(conflict.remoteEntry.id)
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Server")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if useRemoteEntries.contains(conflict.remoteEntry.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Text("Images: \(conflict.remoteEntry.imageNumbers)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(useRemoteEntries.contains(conflict.remoteEntry.id) ? Color.green : Color.gray, lineWidth: 1)
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // Row for group conflict
    private func groupConflictRow(_ conflict: OfflineManager.GroupConflict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(conflict.localGroup.description)
                    .font(.headline)
                
                Spacer()
                
                Text("Choose Version")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                // Local version button
                Button(action: {
                    toggleLocalGroup(conflict.localGroup.id)
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Your Device")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if useLocalGroups.contains(conflict.localGroup.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Text("Images: \(conflict.localGroup.imageNumbers)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(useLocalGroups.contains(conflict.localGroup.id) ? Color.green : Color.gray, lineWidth: 1)
                    )
                }
                
                // Remote version button
                Button(action: {
                    toggleRemoteGroup(conflict.localGroup.id)
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Server")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if useRemoteGroups.contains(conflict.localGroup.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Text("Images: \(conflict.remoteGroup.imageNumbers)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(useRemoteGroups.contains(conflict.localGroup.id) ? Color.green : Color.gray, lineWidth: 1)
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // Toggle local entry selection
    private func toggleLocalEntry(_ id: String) {
        // If selecting local, deselect remote
        if useRemoteEntries.contains(id) {
            useRemoteEntries.remove(id)
        }
        
        // Toggle local
        if useLocalEntries.contains(id) {
            useLocalEntries.remove(id)
        } else {
            useLocalEntries.insert(id)
        }
    }
    
    // Toggle remote entry selection
    private func toggleRemoteEntry(_ id: String) {
        // If selecting remote, deselect local
        if useLocalEntries.contains(id) {
            useLocalEntries.remove(id)
        }
        
        // Toggle remote
        if useRemoteEntries.contains(id) {
            useRemoteEntries.remove(id)
        } else {
            useRemoteEntries.insert(id)
        }
    }
    
    // Toggle local group selection
    private func toggleLocalGroup(_ id: String) {
        // If selecting local, deselect remote
        if useRemoteGroups.contains(id) {
            useRemoteGroups.remove(id)
        }
        
        // Toggle local
        if useLocalGroups.contains(id) {
            useLocalGroups.remove(id)
        } else {
            useLocalGroups.insert(id)
        }
    }
    
    // Toggle remote group selection
    private func toggleRemoteGroup(_ id: String) {
        // If selecting remote, deselect local
        if useLocalGroups.contains(id) {
            useLocalGroups.remove(id)
        }
        
        // Toggle remote
        if useRemoteGroups.contains(id) {
            useRemoteGroups.remove(id)
        } else {
            useRemoteGroups.insert(id)
        }
    }
    
    // Use local version for all conflicts
    private func useLocalForAll() {
        // Clear existing selections
        useRemoteEntries.removeAll()
        useRemoteGroups.removeAll()
        
        // Select all local entries
        for conflict in entryConflicts {
            useLocalEntries.insert(conflict.localEntry.id)
        }
        
        // Select all local groups
        for conflict in groupConflicts {
            useLocalGroups.insert(conflict.localGroup.id)
        }
    }
    
    // Use remote version for all conflicts
    private func useRemoteForAll() {
        // Clear existing selections
        useLocalEntries.removeAll()
        useLocalGroups.removeAll()
        
        // Select all remote entries
        for conflict in entryConflicts {
            useRemoteEntries.insert(conflict.remoteEntry.id)
        }
        
        // Select all remote groups
        for conflict in groupConflicts {
            useRemoteGroups.insert(conflict.remoteGroup.id)
        }
    }
    
    // Check if all conflicts have been resolved
    private func allConflictsResolved() -> Bool {
        // All entry conflicts resolved
        let entriesResolved = entryConflicts.allSatisfy { conflict in
            useLocalEntries.contains(conflict.localEntry.id) || useRemoteEntries.contains(conflict.remoteEntry.id)
        }
        
        // All group conflicts resolved
        let groupsResolved = groupConflicts.allSatisfy { conflict in
            useLocalGroups.contains(conflict.localGroup.id) || useRemoteGroups.contains(conflict.remoteGroup.id)
        }
        
        return entriesResolved && groupsResolved
    }
    
    // Resolve conflicts and save
    private func resolveConflicts() {
        isResolving = true
        
        OfflineManager.shared.resolveConflicts(
            shootID: shootID,
            useLocalEntries: Array(useLocalEntries),
            useRemoteEntries: Array(useRemoteEntries),
            useLocalGroups: Array(useLocalGroups),
            useRemoteGroups: Array(useRemoteGroups)
        ) { success in
            isResolving = false
            
            if success {
                onComplete(true)
                presentationMode.wrappedValue.dismiss()
            } else {
                // Handle error
                // In a real app, you might want to show an alert
            }
        }
    }
}