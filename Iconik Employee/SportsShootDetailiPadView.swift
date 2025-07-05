import SwiftUI
import Firebase
import FirebaseFirestore
import Combine

struct SportsShootDetailiPadView: View {
    let sportsShootID: String
    
    @State private var sportsShoot: SportsShoot?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var selectedTab = 0
    
    // Edit states
    @State private var showingAddRosterEntry = false
    @State private var showingAddGroupImage = false
    @State private var selectedRosterEntry: RosterEntry?
    @State private var selectedGroupImage: GroupImage?
    
    // Sort states
    @State private var sortField: String = "lastName"
    @State private var sortAscending: Bool = true
    
    // Editing states for inline image numbers
    @State private var currentlyEditingEntry: String? = nil
    @State private var editingImageNumber: String = ""
    @State private var lockedEntries: [String: String] = [:]
    
    // Autosave states
    @State private var debounceTask: DispatchWorkItem?
    @State private var lastSavedValue: String = ""
    
    // Focus state for keyboard navigation
    @FocusState private var focusedField: String?
    
    // UI state - header collapsed in landscape
    @State private var isHeaderCollapsed = false
    
    // Timer for refreshing locked entries
    let lockRefreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    // User info for locking
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""
    
    // Device orientation detection
    @State private var orientation = UIDeviceOrientation.unknown
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading sports shoot...")
                    .padding()
            } else if let shoot = sportsShoot {
                VStack(spacing: 0) {
                    // Collapsible header view
                    if isHeaderCollapsed {
                        // Compressed header - just essential info in a single line
                        HStack {
                            Text(shoot.schoolName)
                                .font(.headline)
                            
                            Text(" • ")
                                .foregroundColor(.gray)
                            
                            Text(shoot.sportName)
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            
                            Spacer()
                            
                            Text(formatDate(shoot.shootDate))
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isHeaderCollapsed.toggle()
                                }
                            }) {
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(.leading, 8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground))
                    } else {
                        // Full header
                        headerView(shoot)
                            .transition(.opacity)
                        
                        // Toggle button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isHeaderCollapsed.toggle()
                            }
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: "chevron.up")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .background(Color(.systemGroupedBackground))
                        }
                    }
                    
                    // Tab selector
                    Picker("", selection: $selectedTab) {
                        Text("Athletes").tag(0)
                        Text("Groups").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.vertical, 4) // Reduced padding
                    
                    // Field mapping info - only show when header is collapsed
                    if isHeaderCollapsed {
                        HStack {
                            Text("Field Mapping: Last Name → Name, First Name → Subject ID, Teacher → Special, Group → Sport/Team")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.bottom, 4)
                            Spacer()
                        }
                        .background(Color(.systemGroupedBackground))
                    }
                    
                    // Tab content
                    if selectedTab == 0 {
                        rosterListView(shoot)
                    } else {
                        groupImagesListView(shoot)
                    }
                }
                .background(Color(.systemGroupedBackground))
            } else {
                Text("Failed to load sports shoot")
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .navigationTitle(sportsShoot?.schoolName ?? "Sports Shoot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    loadSportsShoot()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            loadSportsShoot()
            setupLockListener()
            setupOrientationNotification()
        }
        .onDisappear {
            // Release any locks when leaving the view
            if let entryID = currentlyEditingEntry {
                releaseLock(entryID: entryID)
            }
            
            // Cancel any pending autosave tasks
            debounceTask?.cancel()
            
            // Remove orientation notification observer
            NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        }
        .onReceive(lockRefreshTimer) { _ in
            refreshLocks()
        }
        .onChange(of: editingImageNumber) { newValue in
            // Auto-save when the text changes
            if let entryID = currentlyEditingEntry,
               let entry = sportsShoot?.roster.first(where: { $0.id == entryID }),
               newValue != lastSavedValue {
                
                // Cancel any existing debounce task
                debounceTask?.cancel()
                
                // Create a new debounce task with a 0.5-second delay
                let task = DispatchWorkItem {
                    var updatedEntry = entry
                    updatedEntry.imageNumbers = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    SportsShootService.shared.updateRosterEntry(shootID: sportsShootID, entry: updatedEntry) { result in
                        switch result {
                        case .success:
                            // Update the lastSavedValue to prevent redundant saves
                            self.lastSavedValue = newValue
                            // Refresh the data
                            self.loadSportsShoot()
                        case .failure(let error):
                            print("Autosave error: \(error.localizedDescription)")
                        }
                    }
                }
                
                // Schedule the new task
                debounceTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
            }
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingAddRosterEntry) {
            AddRosterEntryView(
                shootID: sportsShootID,
                existingEntry: selectedRosterEntry,
                onComplete: { success in
                    if success {
                        loadSportsShoot()
                    }
                    selectedRosterEntry = nil
                }
            )
        }
        .sheet(isPresented: $showingAddGroupImage) {
            AddGroupImageView(
                shootID: sportsShootID,
                existingGroup: selectedGroupImage,
                onComplete: { success in
                    if success {
                        loadSportsShoot()
                    }
                    selectedGroupImage = nil
                }
            )
        }
    }
    
    // MARK: - Orientation Management
    
    private func setupOrientationNotification() {
        // Get the current orientation
        updateOrientation()
        
        // Set up notification for orientation changes
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main) { _ in
                self.updateOrientation()
            }
    }
    
    private func updateOrientation() {
        let deviceOrientation = UIDevice.current.orientation
        self.orientation = deviceOrientation
        
        // Auto-collapse header in landscape
        if deviceOrientation.isLandscape {
            withAnimation {
                self.isHeaderCollapsed = true
            }
        } else if deviceOrientation.isPortrait {
            withAnimation {
                self.isHeaderCollapsed = false
            }
        }
    }
    
    // MARK: - Lock Management
    
    private func setupLockListener() {
        EntryLockManager.shared.listenForLocks(shootID: sportsShootID) { locks in
            self.lockedEntries = locks
        }
    }
    
    private func acquireLock(entryID: String) {
        let editorID = Auth.auth().currentUser?.uid ?? UUID().uuidString
        let editorName = "\(storedUserFirstName) \(storedUserLastName)"
        
        EntryLockManager.shared.acquireLock(shootID: sportsShootID, entryID: entryID, editorID: editorID, editorName: editorName) { success in
            if success {
                DispatchQueue.main.async {
                    self.currentlyEditingEntry = entryID
                }
            }
        }
    }
    
    private func releaseLock(entryID: String) {
        let editorID = Auth.auth().currentUser?.uid ?? ""
        
        EntryLockManager.shared.releaseLock(shootID: sportsShootID, entryID: entryID, editorID: editorID) { _ in
            DispatchQueue.main.async {
                if self.currentlyEditingEntry == entryID {
                    self.currentlyEditingEntry = nil
                    self.editingImageNumber = ""
                    self.lastSavedValue = ""
                    self.debounceTask?.cancel()
                }
            }
        }
    }
    
    private func refreshLocks() {
        EntryLockManager.shared.cleanupStaleLocks(shootID: sportsShootID)
    }
    
    private func headerView(_ shoot: SportsShoot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shoot.schoolName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text(shoot.sportName)
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Text(formatDate(shoot.shootDate))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            if !shoot.location.isEmpty {
                Label(shoot.location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if !shoot.photographer.isEmpty {
                Label(shoot.photographer, systemImage: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if !shoot.additionalNotes.isEmpty {
                Text(shoot.additionalNotes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    private func rosterListView(_ shoot: SportsShoot) -> some View {
        VStack {
            // Column headers with sorting functionality - make more compact when collapsed
            HStack {
                sortableHeader("Name", field: "lastName")
                sortableHeader("Subject ID", field: "firstName")
                sortableHeader("Special", field: "teacher")
                sortableHeader("Sport/Team", field: "group")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, isHeaderCollapsed ? 4 : 8)
            .padding(.bottom, isHeaderCollapsed ? 2 : 4)
            .background(Color(.secondarySystemGroupedBackground))
            
            // Field mapping info shown in header when collapsed, not needed here
            
            List {
                // Sort roster based on current sort field and direction
                ForEach(sortedRoster(shoot.roster)) { entry in
                    rosterEntryRow(entry: entry)
                        .listRowInsets(EdgeInsets(
                            top: isHeaderCollapsed ? 6 : 10,
                            leading: 16,
                            bottom: isHeaderCollapsed ? 6 : 10,
                            trailing: 16
                        ))
                }
            }
            .listStyle(InsetGroupedListStyle())
            
            Button(action: {
                selectedRosterEntry = nil
                showingAddRosterEntry = true
            }) {
                Label("Add Athlete", systemImage: "person.badge.plus")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
    }
    
    private func rosterEntryRow(entry: RosterEntry) -> some View {
        let isLockedByOthers = lockedEntries[entry.id] != nil && lockedEntries[entry.id] != "\(storedUserFirstName) \(storedUserLastName)"
        let isCurrentlyEditing = currentlyEditingEntry == entry.id
        
        return VStack(spacing: isHeaderCollapsed ? 2 : 4) {
            HStack {
                Button(action: {
                    if !isLockedByOthers {
                        selectedRosterEntry = entry
                        showingAddRosterEntry = true
                    }
                }) {
                    VStack(alignment: .leading, spacing: isHeaderCollapsed ? 2 : 4) {
                        HStack {
                            Text(entry.lastName.isEmpty ? "(No Name)" : "\(entry.lastName), \(entry.firstName)")
                                .font(.headline)
                            
                            Spacer()
                            
                            if !entry.group.isEmpty {
                                Text(entry.group)
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        
                        // Only show teacher info if not in collapsed mode or if editing
                        if (!isHeaderCollapsed || isCurrentlyEditing) && !entry.teacher.isEmpty {
                            Text("Special: \(entry.teacher)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if isLockedByOthers, let editorName = lockedEntries[entry.id] {
                            Text("Being edited by \(editorName)")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 2)
                        }
                        
                        // Only show notes if not in collapsed mode or if editing
                        if (!isHeaderCollapsed || isCurrentlyEditing) && !entry.notes.isEmpty {
                            Text("Notes: \(entry.notes)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, isHeaderCollapsed ? 2 : 4)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isLockedByOthers)
            }
            
            // Inline image number editing field
            HStack {
                Text("Images:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isCurrentlyEditing {
                    // Editable text field with numerical keyboard and autosave
                    AutosaveTextField(
                        text: $editingImageNumber,
                        placeholder: "Enter image numbers",
                        onTapOutside: {
                            // Field will autosave on text change, no need to explicitly save here
                        }
                    )
                    .font(.body) // Larger font
                    .padding(.vertical, isHeaderCollapsed ? 4 : 6)
                    .frame(minHeight: 44) // Taller for better touch target
                    .frame(maxWidth: .infinity) // Take up all available width
                } else if isLockedByOthers {
                    // Read-only when locked by others
                    Text(entry.imageNumbers.isEmpty ? "No images recorded" : entry.imageNumbers)
                        .font(.body) // Larger font
                        .foregroundColor(entry.imageNumbers.isEmpty ? .orange : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, isHeaderCollapsed ? 8 : 12)
                        .frame(minHeight: isHeaderCollapsed ? 36 : 44) // Adjust height based on collapse state
                        .frame(maxWidth: .infinity, alignment: .leading) // Full width
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                } else {
                    // Clickable field when not editing
                    Button(action: {
                        startEditing(entry: entry)
                    }) {
                        Text(entry.imageNumbers.isEmpty ? "Click to add images" : entry.imageNumbers)
                            .font(.body) // Larger font
                            .padding(.horizontal, 12)
                            .padding(.vertical, isHeaderCollapsed ? 8 : 12)
                            .frame(minHeight: isHeaderCollapsed ? 36 : 44) // Adjust height based on collapse state
                            .frame(maxWidth: .infinity, alignment: .leading) // Full width
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(entry.imageNumbers.isEmpty ? .blue : .primary)
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.bottom, isHeaderCollapsed ? 2 : 4)
        }
        .padding(.vertical, isHeaderCollapsed ? 2 : 4)
        .background(isLockedByOthers ? Color.red.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .swipeActions(edge: .trailing) {
            if !isLockedByOthers {
                Button(role: .destructive) {
                    deleteRosterEntry(id: entry.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    // Start editing image numbers
    private func startEditing(entry: RosterEntry) {
        // Release any previous lock
        if let previousEntryID = currentlyEditingEntry {
            releaseLock(entryID: previousEntryID)
        }
        
        // Set up editing state
        editingImageNumber = entry.imageNumbers
        lastSavedValue = entry.imageNumbers // Set initial saved value
        
        // Acquire lock for this entry - don't wait for a second tap
        currentlyEditingEntry = entry.id // Set this immediately
        acquireLock(entryID: entry.id)
        
        // Focus is now handled automatically in the AutosaveTextField
    }
    
    // Cancel editing
    private func cancelEditing() {
        if let entryID = currentlyEditingEntry {
            releaseLock(entryID: entryID)
        }
    }
    
    // Create a sortable header for roster columns with updated display names
    private func sortableHeader(_ title: String, field: String) -> some View {
        Button(action: {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = true
            }
        }) {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Image(systemName: getSortDirectionIcon(field))
                    .font(.system(size: 12))
                    .foregroundColor(sortField == field ? .blue : .gray.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // Get sort icon based on current sort field and direction
    private func getSortDirectionIcon(_ field: String) -> String {
        if sortField == field {
            return sortAscending ? "chevron.up" : "chevron.down"
        } else {
            return "chevron.up.chevron.down"
        }
    }
    
    // Sort roster based on current sort settings
    private func sortedRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
        return roster.sorted { first, second in
            var result = false
            
            // Get values to compare based on sort field
            switch sortField {
            case "lastName":
                result = first.lastName.lowercased() < second.lastName.lowercased()
            case "firstName":
                result = first.firstName.lowercased() < second.firstName.lowercased()
            case "teacher":
                result = first.teacher.lowercased() < second.teacher.lowercased()
            case "group":
                result = first.group.lowercased() < second.group.lowercased()
            default:
                result = first.lastName.lowercased() < second.lastName.lowercased()
            }
            
            // Apply sort direction
            return sortAscending ? result : !result
        }
    }
    
    private func groupImagesListView(_ shoot: SportsShoot) -> some View {
        VStack {
            List {
                ForEach(shoot.groupImages) { group in
                    Button(action: {
                        selectedGroupImage = group
                        showingAddGroupImage = true
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.description)
                                .font(.headline)
                            
                            if !group.imageNumbers.isEmpty {
                                HStack {
                                    Label("Images: \(group.imageNumbers)", systemImage: "camera")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 2)
                            } else {
                                Text("No images recorded")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.top, 2)
                            }
                            
                            if !group.notes.isEmpty {
                                Text("Notes: \(group.notes)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteGroupImage(id: group.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            
            Button(action: {
                selectedGroupImage = nil
                showingAddGroupImage = true
            }) {
                Label("Add Group", systemImage: "person.3.sequence.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
    }
    
    private func loadSportsShoot() {
        isLoading = true
        
        SportsShootService.shared.fetchSportsShoot(id: sportsShootID) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let shoot):
                    self.sportsShoot = shoot
                case .failure(let error):
                    self.errorMessage = "Failed to load sports shoot: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func deleteRosterEntry(id: String) {
        SportsShootService.shared.deleteRosterEntry(shootID: sportsShootID, entryID: id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    loadSportsShoot()
                case .failure(let error):
                    self.errorMessage = "Failed to delete athlete: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func deleteGroupImage(id: String) {
        SportsShootService.shared.deleteGroupImage(shootID: sportsShootID, groupID: id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    loadSportsShoot()
                case .failure(let error):
                    self.errorMessage = "Failed to delete group: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct SportsShootDetailiPadView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SportsShootDetailiPadView(sportsShootID: "previewID")
        }
    }
}
