import SwiftUI
import Firebase
import FirebaseFirestore
import Combine

struct SportsShootListView: View {
    // MARK: - Properties
    
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""
    
    // Device session ID - unique to this app instance
    private static let deviceSessionID = UUID().uuidString
    
    // Current user identifier combines name and device
    private var currentEditorIdentifier: String {
        return "\(storedUserFirstName) \(storedUserLastName) (\(Self.deviceSessionID.prefix(8)))"
    }
    
    @State private var sportsShoots: [SportsShoot] = []
    @State private var selectedShoot: SportsShoot? = nil
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    
    // States for roster management
    @State private var showingAddRosterEntry = false
    @State private var showingAddGroupImage = false
    @State private var selectedRosterEntry: RosterEntry?
    @State private var selectedGroupImage: GroupImage?
    @State private var selectedTab = 0 // 0 = Athletes, 1 = Groups
    
    // Sort states
    @State private var sortField: String = "firstName" // Default to sort by Subject ID
    @State private var sortAscending: Bool = true
    
    // Import/Export state
    @State private var showingImportExport = false
    
    // Field editing state
    @State private var currentlyEditingEntry: String? = nil // ID of entry being edited
    @State private var editingImageNumber: String = ""
    @State private var lockedEntries: [String: String] = [:] // [entryID: editorName]
    
    // Autosave states
    @State private var debounceTask: DispatchWorkItem?
    @State private var lastSavedValue: String = ""
    
    // UI state - header collapsed in landscape
    @State private var isHeaderCollapsed = false
    
    // Focus state for keyboard navigation
    @FocusState private var focusedField: String?
    
    // Device orientation detection
    @State private var orientation = UIDeviceOrientation.unknown
    
    // Timer for refreshing locked entries
    let lockRefreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    // Filter panel state
    @State private var showFilterPanel = false
    @State private var selectedFilters: Set<String> = []
    @State private var selectedSpecialFilters: Set<String> = []
    @State private var imageFilterType: ImageFilterType = .all
    
    // Filter options
    let specialFilters = ["Seniors", "8th Graders", "Coaches"]
    
    // Image filter options
    enum ImageFilterType {
        case all
        case hasImages
        case noImages
    }
    
    // MARK: - Helper Functions
    
    // Check if a lock is owned by this device
    private func isOwnLock(_ lockId: String) -> Bool {
        return lockedEntries[lockId] == currentEditorIdentifier
    }
    
    // Helper function to translate special codes
    private func specialTranslation(_ special: String) -> String {
        switch special.lowercased() {
        case "c": return "Coach"
        case "s": return "Senior"
        case "8": return "8th Grader"
        default: return special // Return as is if not one of the special codes
        }
    }
    
    // Function to get all unique group names from the current roster
    private func allGroupNames() -> [String] {
        guard let shoot = selectedShoot else { return [] }
        
        let allGroups = Set(shoot.roster.map { $0.group })
        return Array(allGroups).filter { !$0.isEmpty }.sorted()
    }
    
    // Filter roster based on selected filters
    private func filterRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
        // Apply filters in sequence
        
        // First, filter by group and special categories
        var filteredRoster = roster
        
        // If group or special filters are selected
        if !selectedFilters.isEmpty || !selectedSpecialFilters.isEmpty {
            filteredRoster = roster.filter { entry in
                // Check if entry matches any selected group filter
                let matchesGroup = selectedFilters.contains(entry.group)
                
                // Check if entry matches any selected special filter
                let matchesSpecial = (selectedSpecialFilters.contains("Seniors") && entry.teacher.lowercased() == "s") ||
                                    (selectedSpecialFilters.contains("8th Graders") && entry.teacher.lowercased() == "8") ||
                                    (selectedSpecialFilters.contains("Coaches") && entry.teacher.lowercased() == "c")
                
                // If both filter types are applied, match entries that satisfy BOTH conditions
                if !selectedFilters.isEmpty && !selectedSpecialFilters.isEmpty {
                    return matchesGroup && matchesSpecial
                }
                // If only group filters are applied
                else if !selectedFilters.isEmpty {
                    return matchesGroup
                }
                // If only special filters are applied
                else {
                    return matchesSpecial
                }
            }
        }
        
        // Then, apply image filter if set
        switch imageFilterType {
        case .all:
            // No additional filtering needed
            return filteredRoster
        case .hasImages:
            // Filter for entries with image numbers
            return filteredRoster.filter { !$0.imageNumbers.isEmpty }
        case .noImages:
            // Filter for entries without image numbers
            return filteredRoster.filter { $0.imageNumbers.isEmpty }
        }
    }
    
    var body: some View {
        NavigationView {
            // Left side - List of shoots
            List {
                if isLoading {
                    ProgressView("Loading sports shoots...")
                        .padding()
                        .listRowBackground(Color.clear)
                } else if sportsShoots.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "camera.on.rectangle")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                            .padding()
                        
                        Text("No Sports Shoots Available")
                            .font(.headline)
                        
                        Text("Sports shoots are created via the web interface and will appear here once available")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                    }
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    // Sports shoots list
                    ForEach(sportsShoots) { sportsShoot in
                        Button(action: {
                            selectedShoot = sportsShoot
                            // Collapse sidebar when an item is selected
                            collapseSidebarAfterSelection()
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(sportsShoot.schoolName)
                                        .font(.headline)
                                    Spacer()
                                    Text(sportsShoot.sportName)
                                        .font(.subheadline)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(4)
                                }
                                
                                Text(formatDate(sportsShoot.shootDate))
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                
                                HStack {
                                    Label("\(sportsShoot.roster.count) Athletes", systemImage: "person.3")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Label("\(sportsShoot.groupImages.count) Groups", systemImage: "person.3.sequence")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .background(selectedShoot?.id == sportsShoot.id ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 320)
            .navigationTitle("Sports Shoots")
            .refreshable {
                loadSportsShoots()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        loadSportsShoots()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            
            // Right side - Detail view
            if let shoot = selectedShoot {
                ZStack {
                    // Main content
                    VStack(spacing: 0) {
                        // Compact header (always shown, no expanding)
                        HStack {
                            // School and sport name
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 4) {
                                    Text(shoot.schoolName)
                                        .font(.headline)
                                        .lineLimit(1)
                                    
                                    Text("•")
                                        .foregroundColor(.gray)
                                    
                                    Text(shoot.sportName)
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                        .lineLimit(1)
                                }
                                
                                // Secondary info in a row (date, location, photographer)
                                HStack(spacing: 12) {
                                    Text(formatDate(shoot.shootDate))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    if !shoot.location.isEmpty {
                                        HStack(spacing: 2) {
                                            Image(systemName: "mappin.and.ellipse")
                                                .font(.system(size: 9))
                                            Text(shoot.location)
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                    
                                    if !shoot.photographer.isEmpty {
                                        HStack(spacing: 2) {
                                            Image(systemName: "person.crop.circle")
                                                .font(.system(size: 9))
                                            Text(shoot.photographer)
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.top, 2)
                            }
                            
                            Spacer()
                            
                            // Right side items
                            HStack(spacing: 8) {
                                // Filter button
                                Button(action: {
                                    withAnimation {
                                        showFilterPanel.toggle()
                                    }
                                }) {
                                    Image(systemName: "line.3.horizontal.decrease.circle\(showFilterPanel ? ".fill" : "")")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                }
                                .frame(width: 24, height: 24)
                                .opacity(selectedTab == 0 ? 1 : 0.5) // Only active for Athletes tab
                                .disabled(selectedTab != 0)
                                
                                // Import/Export button
                                Button(action: {
                                    showingImportExport = true
                                }) {
                                    Image(systemName: "square.and.arrow.up.on.square")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .frame(width: 24, height: 24)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground))
                        
                        // Notes (if any, in a collapsible section)
                        if !shoot.additionalNotes.isEmpty {
                            // Show notes in collapsed format
                            HStack {
                                Text(shoot.additionalNotes)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemGroupedBackground))
                        }
                        
                        // Tab selector - more compact
                        HStack {
                            Picker("", selection: $selectedTab) {
                                Text("Athletes").tag(0)
                                Text("Groups").tag(1)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .onChange(of: selectedTab) { newValue in
                                // Close filter panel when switching to Groups tab
                                if newValue == 1 {
                                    withAnimation {
                                        showFilterPanel = false
                                    }
                                }
                            }
                            
                            // Show field mapping info beside the tabs
                            Text("Field Map: Last→Name, First→SubjectID")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        
                        // Active filters indicator (only shown when filters active)
                        if (!selectedFilters.isEmpty || !selectedSpecialFilters.isEmpty || imageFilterType != .all) && selectedTab == 0 {
                            HStack {
                                Text("Filtered by: ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) {
                                        // Show image filter indicator if active
                                        if imageFilterType == .hasImages {
                                            Text("Has Images")
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.2))
                                                .foregroundColor(.green)
                                                .cornerRadius(4)
                                        } else if imageFilterType == .noImages {
                                            Text("No Images")
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.2))
                                                .foregroundColor(.green)
                                                .cornerRadius(4)
                                        }
                                        
                                        // Show special filter indicators
                                        ForEach(Array(selectedSpecialFilters), id: \.self) { special in
                                            Text(special)
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.purple.opacity(0.2))
                                                .foregroundColor(.purple)
                                                .cornerRadius(4)
                                        }
                                        
                                        // Show group filter indicators
                                        ForEach(Array(selectedFilters), id: \.self) { group in
                                            Text(group)
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(colorForGroup(group).opacity(0.2))
                                                .foregroundColor(colorForGroup(group))
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    withAnimation {
                                        selectedFilters.removeAll()
                                        selectedSpecialFilters.removeAll()
                                        imageFilterType = .all
                                    }
                                }) {
                                    Text("Clear")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
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
                    
                    // Filter panel (slides out from right side)
                    FilterPanelView(
                        isShowing: $showFilterPanel,
                        selectedFilters: $selectedFilters,
                        selectedSpecialFilters: $selectedSpecialFilters,
                        imageFilterType: $imageFilterType,
                        groupNames: allGroupNames(),
                        specialFilters: specialFilters,
                        colorForGroup: colorForGroup
                    )
                }
                // Hide original navigation toolbar
                .navigationBarHidden(true)
                .onAppear {
                    setupOrientationNotification()
                    
                    // Set up a real-time listener for Firestore updates
                    setupFirestoreListeners()
                }
                .onDisappear {
                    // Remove orientation notification observer
                    NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
                    
                    // Release any locks when leaving the view
                    if let entryID = currentlyEditingEntry, let shootID = selectedShoot?.id {
                        releaseLock(shootID: shootID, entryID: entryID)
                    }
                    
                    // Cancel any pending autosave tasks
                    debounceTask?.cancel()
                }
            } else {
                // Initial detail view (secondary/detail view) when no item is selected
                VStack {
                    Spacer()
                    Image(systemName: "arrow.left.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("Select a Sports Shoot")
                        .font(.title)
                        .padding()
                    
                    Text("Choose a sports shoot from the list on the left to view details and manage rosters.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 50)
                    Spacer()
                }
            }
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
        .onAppear {
            loadSportsShoots()
            // Force the sidebar to be visible on first appear and ensure it stays visible
            forceSidebarVisibility()
        }
        .onReceive(lockRefreshTimer) { _ in
            // Refresh the locks periodically
            refreshLocks()
        }
        .onChange(of: editingImageNumber) { newValue in
            // Auto-save when the text changes
            if let entryID = currentlyEditingEntry,
               let shootID = selectedShoot?.id,
               let entry = selectedShoot?.roster.first(where: { $0.id == entryID }),
               newValue != lastSavedValue {
                
                // Cancel any existing debounce task
                debounceTask?.cancel()
                
                // Create a new debounce task with a 0.5-second delay
                let task = DispatchWorkItem {
                    var updatedEntry = entry
                    updatedEntry.imageNumbers = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    SportsShootService.shared.updateRosterEntry(shootID: shootID, entry: updatedEntry) { result in
                        switch result {
                        case .success:
                            // Update the lastSavedValue to prevent redundant saves
                            self.lastSavedValue = newValue
                            
                            // Trigger a partial update to notify other devices of changes
                            // This notifies listeners that a specific entry has been updated
                            self.onShootUpdated(shootID, entry: updatedEntry)
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
            if let shoot = selectedShoot {
                AddRosterEntryView(
                    shootID: shoot.id,
                    existingEntry: selectedRosterEntry,
                    onComplete: { success in
                        if success {
                            refreshSelectedShoot()
                        }
                        selectedRosterEntry = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddGroupImage) {
            if let shoot = selectedShoot {
                AddGroupImageView(
                    shootID: shoot.id,
                    existingGroup: selectedGroupImage,
                    onComplete: { success in
                        if success {
                            refreshSelectedShoot()
                        }
                        selectedGroupImage = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingImportExport) {
            if let shoot = selectedShoot {
                CSVImportExportView(
                    shootID: shoot.id,
                    onComplete: { success in
                        if success {
                            refreshSelectedShoot()
                        }
                        showingImportExport = false
                    }
                )
            }
        }
    }
    
    // MARK: - Filter Panel View
    
    struct FilterPanelView: View {
        @Binding var isShowing: Bool
        @Binding var selectedFilters: Set<String>
        @Binding var selectedSpecialFilters: Set<String>
        @Binding var imageFilterType: ImageFilterType
        var groupNames: [String]
        var specialFilters: [String]
        var colorForGroup: (String) -> Color
        
        var body: some View {
            ZStack {
                // Semi-transparent background for tapping to dismiss
                Color.black.opacity(isShowing ? 0.1 : 0)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation {
                            isShowing = false
                        }
                    }
                
                // Actual panel content
                HStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        // Panel content
                        VStack(alignment: .leading, spacing: 12) {
                            // Header
                            HStack {
                                Text("Filter Athletes")
                                    .font(.headline)
                                
                                Spacer()
                                
                                Button(action: {
                                    withAnimation {
                                        isShowing = false
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.title3)
                                }
                            }
                            .padding(.bottom, 4)
                            
                            Divider()
                            
                            // Special filters section
                            Text("Special Categories")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 8) {
                                ForEach(specialFilters, id: \.self) { special in
                                    SpecialFilterButton(
                                        title: special,
                                        isSelected: selectedSpecialFilters.contains(special),
                                        action: {
                                            toggleSpecialFilter(special)
                                        }
                                    )
                                }
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                                
                            // Image filters section
                            Text("Image Status")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                
                            HStack(spacing: 8) {
                                ImageFilterButton(
                                    title: "Has Images",
                                    isSelected: imageFilterType == .hasImages,
                                    action: {
                                        imageFilterType = imageFilterType == .hasImages ? .all : .hasImages
                                    }
                                )
                                
                                ImageFilterButton(
                                    title: "No Images",
                                    isSelected: imageFilterType == .noImages,
                                    action: {
                                        imageFilterType = imageFilterType == .noImages ? .all : .noImages
                                    }
                                )
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Group filters section
                            HStack {
                                Text("Sport/Team")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                if !selectedFilters.isEmpty {
                                    Button(action: {
                                        withAnimation {
                                            selectedFilters.removeAll()
                                        }
                                    }) {
                                        Text("Clear")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        .padding()
                        
                        // Group list - now in a separate ScrollView that can fill the remaining space
                        if groupNames.isEmpty {
                            Text("No groups available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(groupNames, id: \.self) { group in
                                        GroupFilterRow(
                                            groupName: group,
                                            isSelected: selectedFilters.contains(group),
                                            color: colorForGroup(group),
                                            action: {
                                                toggleGroupFilter(group)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        
                        // Button to clear all filters
                        if !selectedFilters.isEmpty || !selectedSpecialFilters.isEmpty || imageFilterType != .all {
                            Button(action: {
                                withAnimation {
                                    selectedFilters.removeAll()
                                    selectedSpecialFilters.removeAll()
                                    imageFilterType = .all
                                }
                            }) {
                                Text("Clear All Filters")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(8)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                        }
                        
                        // Done button - now at the bottom after the scrollview
                        Button(action: {
                            withAnimation {
                                isShowing = false
                            }
                        }) {
                            Text("Done")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        .padding()
                    }
                    .frame(width: 300)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: -5, y: 0)
                    .offset(x: isShowing ? 0 : 300)
                }
                .animation(.spring(), value: isShowing)
            }
            .edgesIgnoringSafeArea(.all)
            .opacity(isShowing ? 1 : 0)
        }
        
        // Toggle special filter selection
        private func toggleSpecialFilter(_ filter: String) {
            withAnimation {
                if selectedSpecialFilters.contains(filter) {
                    selectedSpecialFilters.remove(filter)
                } else {
                    selectedSpecialFilters.insert(filter)
                }
            }
        }
        
        // Toggle group filter selection
        private func toggleGroupFilter(_ group: String) {
            withAnimation {
                if selectedFilters.contains(group) {
                    selectedFilters.remove(group)
                } else {
                    selectedFilters.insert(group)
                }
            }
        }
    }
    
    // Special filter button component
    struct SpecialFilterButton: View {
        var title: String
        var isSelected: Bool
        var action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.purple : Color.gray.opacity(0.2))
                    .foregroundColor(isSelected ? .white : .primary)
                    .cornerRadius(16)
            }
        }
    }
    
    // Image filter button component
    struct ImageFilterButton: View {
        var title: String
        var isSelected: Bool
        var action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.green : Color.gray.opacity(0.2))
                    .foregroundColor(isSelected ? .white : .primary)
                    .cornerRadius(16)
            }
        }
    }
    
    // Group filter row component
    struct GroupFilterRow: View {
        var groupName: String
        var isSelected: Bool
        var color: Color
        var action: () -> Void
        
        var body: some View {
            Button(action: action) {
                HStack {
                    Text(groupName)
                        .font(.system(size: 15))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(color)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(isSelected ? Color.gray.opacity(0.1) : Color.clear)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Roster List View
    
    private func rosterListView(_ shoot: SportsShoot) -> some View {
        VStack(spacing: 0) {
            // Column headers with sorting functionality
            HStack {
                sortableHeader("Name", field: "lastName")
                sortableHeader("Subject ID", field: "firstName")
                sortableHeader("Special", field: "teacher")
                sortableHeader("Sport/Team", field: "group")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground))
            
            // List of roster entries
            List {
                // Sort roster based on current sort field and direction
                ForEach(Array(sortedRoster(filterRoster(shoot.roster)).enumerated()), id: \.element.id) { index, entry in
                    rosterEntryRow(shoot: shoot, entry: entry, isEven: index % 2 == 0)
                        .listRowInsets(EdgeInsets(
                            top: 4,
                            leading: 10,
                            bottom: 4,
                            trailing: 10
                        ))
                        .listRowBackground(Color.clear) // Clear default background
                }
            }
            .listStyle(PlainListStyle()) // More compact style
            
            // Add athlete button
            Button(action: {
                selectedRosterEntry = nil
                showingAddRosterEntry = true
            }) {
                Label("Add Athlete", systemImage: "person.badge.plus")
                    .font(.headline)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }
    
    private func rosterEntryRow(shoot: SportsShoot, entry: RosterEntry, isEven: Bool) -> some View {
        // Check if current user on this device is editing this entry
        let isOwnLock = isOwnLock(entry.id)
        
        // Entry is locked by someone else (not us)
        let isLockedByOthers = lockedEntries[entry.id] != nil && !isOwnLock
        
        // We are currently editing this entry
        let isCurrentlyEditing = currentlyEditingEntry == entry.id
        
        // Generate a consistent color for each group
        let groupColor = colorForGroup(entry.group)
        
        // Determine font size based on group name length
        let fontSize: CGFloat
        if entry.group.count < 15 {
            fontSize = 20 // Larger font for short names
        } else if entry.group.count < 30 {
            fontSize = 12 // Medium font for medium names
        } else {
            fontSize = 10 // Smaller font for very long names
        }
        
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left side - Name and SubjectId (fixed width)
                Button(action: {
                    if !isLockedByOthers {
                        selectedRosterEntry = entry
                        showingAddRosterEntry = true
                    }
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Subject ID (firstName) with special info
                        HStack(spacing: 4) {
                            Text(entry.firstName)
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                            
                            if !entry.teacher.isEmpty {
                                Text(specialTranslation(entry.teacher))
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Name (lastName)
                        Text(entry.lastName)
                            .font(.system(size: 20, weight: .bold))
                    }
                    .frame(width: 200, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isLockedByOthers)
                
                // This keeps the image centered by distributing space evenly
                Spacer(minLength: 20)
                
                // Center - Image input box
                if isCurrentlyEditing {
                    AutosaveTextField(
                        text: $editingImageNumber,
                        placeholder: "Enter image numbers",
                        onTapOutside: {
                            // Field autosaves on text change
                        }
                    )
                    .font(.system(size: 20))
                    .frame(width: 150, height: 50)
                    .multilineTextAlignment(.center)
                    .background(Color.blue.opacity(0.3))
                    .cornerRadius(6)
                } else if isLockedByOthers {
                    // Show who is editing if locked by others
                    VStack(spacing: 2) {
                        Text(entry.imageNumbers.isEmpty ? "No images recorded" : entry.imageNumbers)
                            .font(.system(size: 16))
                            .foregroundColor(entry.imageNumbers.isEmpty ? .orange : .secondary)
                            .lineLimit(1)
                        
                        if let editor = lockedEntries[entry.id] {
                            Text("Editing: \(editor)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .frame(width: 150, height: 50)
                    .padding(.horizontal, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
                } else {
                    Button(action: {
                        startEditing(shootID: shoot.id, entry: entry)
                    }) {
                        // Use standard colors that work in both light and dark mode
                        Text(entry.imageNumbers.isEmpty ? "Image #" : entry.imageNumbers)
                            .font(.system(size: 20))
                            .fontWeight(.medium) // Make text slightly bolder
                            .frame(width: 150, height: 50)
                            .multilineTextAlignment(.center)
                            .background(isEven ? Color.blue.opacity(0.3) : Color.blue.opacity(0.4))
                            .foregroundColor(.white) // White text for better contrast in both modes
                            .cornerRadius(6)
                    }
                }
                
                // This keeps the image centered by distributing space evenly
                Spacer(minLength: 20)
                
                // Right side - Group name with adaptive behavior
                if !entry.group.isEmpty {
                    Button(action: {
                        if !isLockedByOthers {
                            selectedRosterEntry = entry
                            showingAddRosterEntry = true
                        }
                    }) {
                        Text(entry.group)
                            .font(.system(size: fontSize)) // Dynamic font size
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(groupColor)
                            .cornerRadius(5)
                            .lineLimit(2) // 2 lines max
                            .fixedSize(horizontal: true, vertical: true) // Never truncate
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isLockedByOthers)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            
            Divider()
        }
        .background(
            // Apply alternating background colors with different colors for light/dark mode
            isEven ?
                Color(.systemBackground) :
                Color(.systemGray4) // Using systemGray4 as requested
        )
        .overlay(
            isLockedByOthers ?
                Color.red.opacity(0.05) :
                Color.clear
        )
        .contextMenu {
            if !isLockedByOthers {
                Button(action: {
                    selectedRosterEntry = entry
                    showingAddRosterEntry = true
                }) {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(action: {
                    startEditing(shootID: shoot.id, entry: entry)
                }) {
                    Label("Edit Image Numbers", systemImage: "camera")
                }
                
                Button(role: .destructive, action: {
                    deleteRosterEntry(shoot: shoot, id: entry.id)
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    // Generate a consistent color for each group name
    private func colorForGroup(_ group: String) -> Color {
        if group.isEmpty {
            return Color.gray
        }
        
        // Hash the group name to generate a consistent color
        let hash = abs(group.hashValue)
        
        // Define a set of distinct, visually appealing colors
        let colors: [Color] = [
            Color.blue,
            Color.green,
            Color(red: 0.0, green: 0.6, blue: 0.4), // Teal green
            Color.purple,
            Color.pink,
            Color.teal,
            Color.indigo,
            Color.red,
            Color(red: 0.2, green: 0.5, blue: 0.9), // Light blue
            Color(red: 0.1, green: 0.6, blue: 0.4), // Forest green
            Color(red: 0.8, green: 0.4, blue: 0.0), // Amber
            Color(red: 0.5, green: 0.1, blue: 0.7), // Violet
            Color(red: 0.9, green: 0.2, blue: 0.5)  // Rose
        ]
        
        // Return a consistent color based on the hash of the group name
        return colors[hash % colors.count]
    }
    
    // Start editing image numbers
    private func startEditing(shootID: String, entry: RosterEntry) {
        print("Attempting to start editing entry: \(entry.id)")
        
        // Show who is editing this entry (for debugging)
        if let editor = lockedEntries[entry.id] {
            print("Entry is locked by: \(editor)")
        } else {
            print("Entry is not currently locked")
        }
        
        // Check if anyone else is editing this entry
        if let editor = lockedEntries[entry.id], !isOwnLock(entry.id) {
            // Entry is locked by someone else - show an alert
            errorMessage = "This entry is currently being edited by \(editor)"
            showingErrorAlert = true
            return
        }
        
        // Check if we already have a lock on this entry
        if isOwnLock(entry.id) {
            print("Already have a lock on this entry - resuming edit")
            // We already have the lock, just start editing without acquiring a new lock
            self.currentlyEditingEntry = entry.id
            self.editingImageNumber = entry.imageNumbers
            self.lastSavedValue = entry.imageNumbers
            return
        }
        
        // Release any previous lock
        if let previousEntryID = currentlyEditingEntry {
            releaseLock(shootID: shootID, entryID: previousEntryID)
        }
        
        // Set up editing state
        editingImageNumber = entry.imageNumbers
        lastSavedValue = entry.imageNumbers // Set initial saved value
        
        // Acquire lock for this entry
        acquireLock(shootID: shootID, entryID: entry.id)
    }
    
    // Save the image number (called by the save button)
    private func saveImageNumber(shootID: String, entry: RosterEntry) {
        guard currentlyEditingEntry == entry.id else { return }
        
        // Create updated entry with new image number
        var updatedEntry = entry
        updatedEntry.imageNumbers = editingImageNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Update in Firestore
        SportsShootService.shared.updateRosterEntry(shootID: shootID, entry: updatedEntry) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Release the lock
                    self.releaseLock(shootID: shootID, entryID: entry.id)
                    // Refresh shoot data
                    self.refreshSelectedShoot()
                case .failure(let error):
                    self.errorMessage = "Failed to update image numbers: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    // Cancel editing
    private func cancelEditing() {
        if let entryID = currentlyEditingEntry, let shootID = selectedShoot?.id {
            releaseLock(shootID: shootID, entryID: entryID)
        }
    }
    
    // Sort button for roster columns with updated display names
    private func sortableHeader(_ title: String, field: String) -> some View {
        Button(action: {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = true
            }
        }) {
            HStack(spacing: 1) {
                Text(title)
                    .font(isHeaderCollapsed ? .system(size: 9) : .caption)
                    .lineLimit(1)
                
                Image(systemName: sortField == field
                      ? (sortAscending ? "chevron.up" : "chevron.down")
                      : "arrow.up.arrow.down")
                    .font(.system(size: isHeaderCollapsed ? 7 : 8))
                    .foregroundColor(sortField == field ? .blue : .gray)
            }
            .padding(.vertical, isHeaderCollapsed ? 2 : 4)
            .padding(.horizontal, isHeaderCollapsed ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(sortField == field ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            )
        }
    }
    
    // Sort roster entries
    private func sortedRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
        return roster.sorted { (a, b) -> Bool in
            let result: Bool
            
            switch sortField {
            case "lastName":
                result = a.lastName.lowercased() < b.lastName.lowercased()
            case "firstName":
                result = a.firstName.lowercased() < b.firstName.lowercased()
            case "teacher":
                result = a.teacher.lowercased() < b.teacher.lowercased()
            case "group":
                result = a.group.lowercased() < b.group.lowercased()
            default:
                result = a.lastName.lowercased() < b.lastName.lowercased()
            }
            
            return sortAscending ? result : !result
        }
    }
    
    // MARK: - Group Images List View
    
    private func groupImagesListView(_ shoot: SportsShoot) -> some View {
        VStack {
            List {
                ForEach(shoot.groupImages) { group in
                    Button(action: {
                        selectedGroupImage = group
                        showingAddGroupImage = true
                    }) {
                        VStack(alignment: .leading, spacing: isHeaderCollapsed ? 2 : 4) {
                            Text(group.description)
                                .font(.headline)
                            
                            if !group.imageNumbers.isEmpty {
                                HStack {
                                    Label("Images: \(group.imageNumbers)", systemImage: "camera")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, isHeaderCollapsed ? 1 : 2)
                            } else {
                                Text("No images recorded")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.top, isHeaderCollapsed ? 1 : 2)
                            }
                            
                            if !isHeaderCollapsed && !group.notes.isEmpty {
                                Text("Notes: \(group.notes)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, isHeaderCollapsed ? 2 : 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        Button(action: {
                            selectedGroupImage = group
                            showingAddGroupImage = true
                        }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive, action: {
                            deleteGroupImage(shoot: shoot, id: group.id)
                        }) {
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
    
    // MARK: - Data Loading and Actions
    
    private func loadSportsShoots() {
        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "No organization ID found. Please sign in again."
            showingErrorAlert = true
            return
        }
        
        isLoading = true
        print("Fetching sports shoots with organization ID: \(storedUserOrganizationID)")
        
        SportsShootService.shared.fetchAllSportsShoots(forOrganization: storedUserOrganizationID) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let shoots):
                    print("Successfully fetched \(shoots.count) sports shoots")
                    self.sportsShoots = shoots
                    
                    // Do not auto-select any item - let user choose explicitly
                    // selectedShoot remains nil until user makes a selection
                    
                case .failure(let error):
                    print("Error loading sports shoots: \(error.localizedDescription)")
                    self.errorMessage = "Failed to load sports shoots: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func onShootUpdated(_ updatedShootID: String, entry: RosterEntry? = nil) {
        // Only refresh if the updated shoot is the one currently displayed
        if let currentShoot = selectedShoot, currentShoot.id == updatedShootID {
            // If we received a specific entry update, apply it immediately
            if let updatedEntry = entry {
                if var currentRoster = selectedShoot?.roster {
                    // Find and replace the updated entry
                    if let index = currentRoster.firstIndex(where: { $0.id == updatedEntry.id }) {
                        currentRoster[index] = updatedEntry
                        selectedShoot?.roster = currentRoster
                    }
                }
            } else {
                // Otherwise refresh the entire shoot data
                refreshSelectedShoot()
            }
        }
    }
    
    private func refreshSelectedShoot() {
        guard let currentShoot = selectedShoot else { return }
        
        SportsShootService.shared.fetchSportsShoot(id: currentShoot.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updatedShoot):
                    // Update the selected shoot
                    self.selectedShoot = updatedShoot
                    
                    // Also update this shoot in the list
                    if let index = self.sportsShoots.firstIndex(where: { $0.id == updatedShoot.id }) {
                        self.sportsShoots[index] = updatedShoot
                    }
                    
                case .failure(let error):
                    self.errorMessage = "Failed to refresh: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func deleteRosterEntry(shoot: SportsShoot, id: String) {
        SportsShootService.shared.deleteRosterEntry(shootID: shoot.id, entryID: id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    refreshSelectedShoot()
                case .failure(let error):
                    self.errorMessage = "Failed to delete athlete: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func deleteGroupImage(shoot: SportsShoot, id: String) {
        SportsShootService.shared.deleteGroupImage(shootID: shoot.id, groupID: id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    refreshSelectedShoot()
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
        
        // Additional UI optimizations for landscape mode
        if deviceOrientation.isLandscape {
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    
                    // Find navigation controller and make it use less space
                    func findNavController(in controller: UIViewController) {
                        if let navController = controller as? UINavigationController {
                            // Make navigation bar more compact
                            navController.navigationBar.prefersLargeTitles = false
                        }
                        
                        for child in controller.children {
                            findNavController(in: child)
                        }
                    }
                    
                    findNavController(in: rootVC)
                }
            }
        } else if deviceOrientation.isPortrait {
            // Restore navigation bar to normal in portrait
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    
                    // Find navigation controller and restore it
                    func findNavController(in controller: UIViewController) {
                        if let navController = controller as? UINavigationController {
                            // Restore navigation bar to normal
                            navController.setNavigationBarHidden(false, animated: true)
                        }
                        
                        for child in controller.children {
                            findNavController(in: child)
                        }
                    }
                    
                    findNavController(in: rootVC)
                }
            }
        }
    }
    
    // Force the UISplitViewController to show the sidebar
    private func forceSidebarVisibility() {
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                // Find split view controller in hierarchy
                let splitVC = findSplitViewController(from: rootVC)
                if let splitVC = splitVC {
                    // Force sidebar to be visible with focus on the sidebar (primaryOverlay)
                    splitVC.preferredDisplayMode = .oneBesideSecondary
                    splitVC.preferredSplitBehavior = .displace
                    
                    // On iOS 14 and later, ensure the sidebar is not collapsed
                    if #available(iOS 14.0, *) {
                        splitVC.preferredPrimaryColumnWidth = 320
                        splitVC.displayModeButtonVisibility = .always
                    }
                }
            }
        }
    }
    
    // Helper method to find UISplitViewController in view hierarchy
    private func findSplitViewController(from viewController: UIViewController) -> UISplitViewController? {
        if let splitVC = viewController as? UISplitViewController {
            return splitVC
        }
        
        for child in viewController.children {
            if let splitVC = findSplitViewController(from: child) {
                return splitVC
            }
        }
        
        return nil
    }
    
    // Force the sidebar to collapse (useful after selection)
    private func collapseSidebarAfterSelection() {
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                // Recursive function to find the split view controller
                func findSplitVC(in controller: UIViewController) -> UISplitViewController? {
                    if let splitVC = controller as? UISplitViewController {
                        return splitVC
                    }
                    for child in controller.children {
                        if let found = findSplitVC(in: child) {
                            return found
                        }
                    }
                    return nil
                }
                
                if let splitVC = findSplitVC(in: rootVC) {
                    // On iOS 14+ we can use column visibility
                    if #available(iOS 14.0, *) {
                        // This hides the primary column and shows only the detail view
                        splitVC.preferredDisplayMode = .secondaryOnly
                    } else {
                        // On earlier iOS versions
                        splitVC.preferredDisplayMode = .primaryHidden
                    }
                }
            }
        }
    }
    
    // MARK: - Firestore Listeners
    
    // Set up Firestore listeners for real-time updates
    private func setupFirestoreListeners() {
        // Set up lock listener
        setupLockListener()
        
        // Set up shoot data listener if we have a selected shoot
        if let shootID = selectedShoot?.id {
            setupShootListener(shootID: shootID)
        }
    }
    
    // Set up a real-time listener for shoot data changes
    private func setupShootListener(shootID: String) {
        let db = Firestore.firestore()
        
        // Listen for changes to the roster collection
        db.collection("sportsJobs").document(shootID)
            .addSnapshotListener { documentSnapshot, error in
                guard let document = documentSnapshot else {
                    print("Error fetching shoot document: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                guard document.exists else {
                    print("Document no longer exists")
                    return
                }
                
                // Only refresh if this is not our own change (avoid constant refreshes)
                if !self.isCurrentlyEditing() {
                    self.refreshSelectedShoot()
                }
            }
    }
    
    // Helper to check if we're currently editing
    private func isCurrentlyEditing() -> Bool {
        return currentlyEditingEntry != nil
    }
    
    // MARK: - Lock Management
    
    private func setupLockListener() {
        guard let shootID = selectedShoot?.id else { return }
        
        // Set up a real-time listener for locks
        // Use SnapshotListener instead of a direct query to get real-time updates
        EntryLockManager.shared.listenForLocks(shootID: shootID) { locks in
            DispatchQueue.main.async {
                self.lockedEntries = locks
                
                // Debug info
                print("Lock update received: \(locks)")
            }
        }
    }
    
    private func acquireLock(shootID: String, entryID: String) {
        let editorID = Auth.auth().currentUser?.uid ?? UUID().uuidString
        let editorName = currentEditorIdentifier // Uses device-specific identifier
        
        print("Attempting to acquire lock: \(entryID)")
        EntryLockManager.shared.acquireLock(shootID: shootID, entryID: entryID, editorID: editorID, editorName: editorName) { success in
            if success {
                DispatchQueue.main.async {
                    print("Lock acquired successfully for: \(entryID)")
                    self.currentlyEditingEntry = entryID
                }
            } else {
                // Show error if lock acquisition fails
                DispatchQueue.main.async {
                    print("Failed to acquire lock for: \(entryID)")
                    self.errorMessage = "This entry is being edited by someone else. Please try again later."
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func releaseLock(shootID: String, entryID: String) {
        let editorID = Auth.auth().currentUser?.uid ?? ""
        
        print("Attempting to release lock: \(entryID)")
        EntryLockManager.shared.releaseLock(shootID: shootID, entryID: entryID, editorID: editorID) { success in
            DispatchQueue.main.async {
                if success {
                    print("Lock released successfully for: \(entryID)")
                } else {
                    print("Failed to release lock for: \(entryID)")
                }
                
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
        guard let shootID = selectedShoot?.id else { return }
        EntryLockManager.shared.cleanupStaleLocks(shootID: shootID)
    }
}

struct SportsShootListView_Previews: PreviewProvider {
    static var previews: some View {
        SportsShootListView()
    }
}
