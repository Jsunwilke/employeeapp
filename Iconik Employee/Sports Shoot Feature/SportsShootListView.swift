import SwiftUI
import Firebase
import FirebaseFirestore
import Combine

// State management class to handle objectWillChange notifications
class SportsShootListViewModel: ObservableObject {
    @Published var sportsShoots: [SportsShoot] = []
    @Published var selectedShoot: SportsShoot? = nil
    @Published var isLoading = true
    @Published var errorMessage = ""
    @Published var showingErrorAlert = false
    
    // Network status
    @Published var isOnline = true
    
    // States for roster management
    @Published var showingAddRosterEntry = false
    @Published var showingAddGroupImage = false
    @Published var selectedRosterEntry: RosterEntry?
    @Published var selectedGroupImage: GroupImage?
    @Published var selectedTab = 0 // 0 = Athletes, 1 = Groups
    
    // Sort states
    @Published var sortField: String = "firstName" // Default to sort by Subject ID
    @Published var sortAscending: Bool = true
    
    // Import/Export state
    @Published var showingImportExport = false
    @Published var showingMultiPhotoImport = false // New state for paper roster import
    
    // Create Sports Shoot state
    @Published var showingCreateSportsShoot = false // New state for creating sports shoot
    
    // Field editing state
    @Published var currentlyEditingEntry: String? = nil // ID of entry being edited
    @Published var editingImageNumber: String = ""
    @Published var lockedEntries: [String: String] = [:] // [entryID: editorName]
    
    // UI state - header collapsed in landscape
    @Published var isHeaderCollapsed = false
    
    // Filter panel state
    @Published var showFilterPanel = false
    @Published var selectedFilters: Set<String> = []
    @Published var selectedSpecialFilters: Set<String> = []
    @Published var imageFilterType: ImageFilterType = .all
    
    // Autosave states
    var debounceTask: DispatchWorkItem?
    var lastSavedValue: String = ""
    
    // Shoot status cache to avoid unnecessary UI updates
    private var shootStatusCache: [String: OfflineManager.CacheStatus] = [:]
    
    // Enum moved from the view to the view model
    enum ImageFilterType {
        case all
        case hasImages
        case noImages
    }
    
    // Method to manually trigger UI updates
    func triggerUpdate() {
        // Only trigger an update when there's actually a change to show
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    // Get sync status with caching to avoid unnecessary UI updates
    func syncStatusForShoot(id: String) -> OfflineManager.CacheStatus {
        let newStatus = OfflineManager.shared.cacheStatusForShoot(id: id)
        
        // Only trigger UI updates when status changes
        if shootStatusCache[id] != newStatus {
            shootStatusCache[id] = newStatus
            // No need to explicitly trigger update here as the view will use this value directly
        }
        
        return newStatus
    }
    
    // Clear cache for a specific shoot when needed
    func clearStatusCache(for shootID: String) {
        shootStatusCache.removeValue(forKey: shootID)
    }
    
    // Clear all status caches when needed
    func clearAllStatusCaches() {
        shootStatusCache.removeAll()
    }
}

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
    
    // Use the view model for state management
    @StateObject private var viewModel = SportsShootListViewModel()
    
    // Focus state for keyboard navigation
    @FocusState private var focusedField: String?
    
    // Device orientation detection
    @State private var orientation = UIDeviceOrientation.unknown
    
    // Timer for refreshing locked entries - using a longer interval to prevent flickering
    let lockRefreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    // Sync statuses refresh timer - using a longer interval to prevent flickering
    let syncStatusTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    // Filter options
    let specialFilters = ["Seniors", "8th Graders", "Coaches"]
    
    // Check if we're on iPhone
    private var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    
    // MARK: - Helper Functions
    
    // Check if a lock is owned by this device
    private func isOwnLock(_ lockId: String) -> Bool {
        return viewModel.lockedEntries[lockId] == currentEditorIdentifier
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
        guard let shoot = viewModel.selectedShoot else { return [] }
        
        let allGroups = Set(shoot.roster.map { $0.group })
        return Array(allGroups).filter { !$0.isEmpty }.sorted()
    }
    
    // Filter roster based on selected filters
    private func filterRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
        // Apply filters in sequence
        
        // First, filter by group and special categories
        var filteredRoster = roster
        
        // If group or special filters are selected
        if !viewModel.selectedFilters.isEmpty || !viewModel.selectedSpecialFilters.isEmpty {
            filteredRoster = roster.filter { entry in
                // Check if entry matches any selected group filter
                let matchesGroup = viewModel.selectedFilters.contains(entry.group)
                
                // Check if entry matches any selected special filter
                let matchesSpecial = (viewModel.selectedSpecialFilters.contains("Seniors") && entry.teacher.lowercased() == "s") ||
                                    (viewModel.selectedSpecialFilters.contains("8th Graders") && entry.teacher.lowercased() == "8") ||
                                    (viewModel.selectedSpecialFilters.contains("Coaches") && entry.teacher.lowercased() == "c")
                
                // If both filter types are applied, match entries that satisfy BOTH conditions
                if !viewModel.selectedFilters.isEmpty && !viewModel.selectedSpecialFilters.isEmpty {
                    return matchesGroup && matchesSpecial
                }
                // If only group filters are applied
                else if !viewModel.selectedFilters.isEmpty {
                    return matchesGroup
                }
                // If only special filters are applied
                else {
                    return matchesSpecial
                }
            }
        }
        
        // Then, apply image filter if set
        switch viewModel.imageFilterType {
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
        Group {
            if isIPhone {
                // iPhone: Use NavigationView with list and navigation links
                iPhoneView
            } else {
                // iPad: Use the existing sidebar layout
                iPadView
            }
        }
        .onAppear {
            loadSportsShoots()
            setupNetworkMonitoring()
            setupConflictHandling()
        }
        .onReceive(lockRefreshTimer) { _ in
            refreshLocks()
        }
        .onReceive(syncStatusTimer) { _ in
            viewModel.triggerUpdate()
        }
        .alert(isPresented: $viewModel.showingErrorAlert) {
            Alert(
                title: Text("Error"),
                message: Text(viewModel.errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $viewModel.showingCreateSportsShoot) {
            CreateSportsShootView(onComplete: { success in
                if success {
                    loadSportsShoots()
                }
                viewModel.showingCreateSportsShoot = false
            })
        }
    }
    
    // MARK: - iPhone View
    
    private var iPhoneView: some View {
        NavigationView {
            List {
                if viewModel.isLoading {
                    ProgressView("Loading sports shoots...")
                        .padding()
                        .listRowBackground(Color.clear)
                } else if viewModel.sportsShoots.isEmpty {
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
                        
                        Button(action: {
                            viewModel.showingCreateSportsShoot = true
                        }) {
                            Label("Create Sports Shoot", systemImage: "plus.circle")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        .padding(.top)
                    }
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    // Sports shoots list with NavigationLinks for iPhone
                    ForEach(viewModel.sportsShoots) { sportsShoot in
                        NavigationLink(destination: SportsShootDetailView(shootID: sportsShoot.id)) {
                            SportsShootRow(
                                shoot: sportsShoot,
                                isSelected: false,
                                onSelect: { },
                                onSyncNow: {
                                    OfflineManager.shared.syncShoot(shootID: sportsShoot.id)
                                    viewModel.clearStatusCache(for: sportsShoot.id)
                                },
                                onMakeAvailableOffline: {
                                    cacheShootForOffline(id: sportsShoot.id)
                                },
                                isInsideNavigationLink: true // Tell the row it's inside a NavigationLink
                            )
                        }
                    }
                    
                    // Quick tools section
                    Section(header: Text("Quick Tools")) {
                        Button(action: {
                            viewModel.showingCreateSportsShoot = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                Text("Create Sports Shoot")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    // Network status indicator
                    Section(header: Text("Connection Status")) {
                        ConnectionStatusIndicator()
                            .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Sports Shoots")
            .refreshable {
                viewModel.clearAllStatusCaches()
                loadSportsShoots()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - iPad View (existing implementation)
    
    private var iPadView: some View {
        NavigationView {
            // Left side - List of shoots
            List {
                if viewModel.isLoading {
                    ProgressView("Loading sports shoots...")
                        .padding()
                        .listRowBackground(Color.clear)
                } else if viewModel.sportsShoots.isEmpty {
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
                        
                        // Add a button to create new sports shoot
                        Button(action: {
                            viewModel.showingCreateSportsShoot = true
                        }) {
                            Label("Create Sports Shoot", systemImage: "plus.circle")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        .padding(.top)
                    }
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    // Sports shoots list
                    ForEach(viewModel.sportsShoots) { sportsShoot in
                        SportsShootRow(
                            shoot: sportsShoot,
                            isSelected: viewModel.selectedShoot?.id == sportsShoot.id,
                            onSelect: {
                                viewModel.selectedShoot = sportsShoot
                                // Collapse sidebar when an item is selected
                                collapseSidebarAfterSelection()
                            },
                            onSyncNow: {
                                OfflineManager.shared.syncShoot(shootID: sportsShoot.id)
                                // Clear status cache for this shoot to ensure UI updates
                                viewModel.clearStatusCache(for: sportsShoot.id)
                            },
                            onMakeAvailableOffline: {
                                cacheShootForOffline(id: sportsShoot.id)
                            }
                        )
                        .background(viewModel.selectedShoot?.id == sportsShoot.id ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                    }
                    
                    // Quick tools section for all actions
                    Section(header: Text("Quick Tools")) {
                        Button(action: {
                            viewModel.showingCreateSportsShoot = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                Text("Create Sports Shoot")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Button(action: {
                            if let shoot = viewModel.selectedShoot {
                                viewModel.showingMultiPhotoImport = true
                            } else {
                                viewModel.errorMessage = "Please select a sports shoot first"
                                viewModel.showingErrorAlert = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "doc.viewfinder")
                                    .foregroundColor(.blue)
                                Text("Import Paper Rosters")
                                    .foregroundColor(.blue)
                            }
                        }
                        .disabled(viewModel.selectedShoot == nil)
                        .opacity(viewModel.selectedShoot == nil ? 0.5 : 1.0)
                        
                        Button(action: {
                            if let shoot = viewModel.selectedShoot {
                                viewModel.showingImportExport = true
                            } else {
                                viewModel.errorMessage = "Please select a sports shoot first"
                                viewModel.showingErrorAlert = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up.on.square")
                                    .foregroundColor(.blue)
                                Text("Import/Export CSV")
                                    .foregroundColor(.blue)
                            }
                        }
                        .disabled(viewModel.selectedShoot == nil)
                        .opacity(viewModel.selectedShoot == nil ? 0.5 : 1.0)
                        
                        // New offline functionality section
                        if let shoot = viewModel.selectedShoot {
                            if OfflineManager.shared.isShootCached(id: shoot.id) {
                                Button(action: {
                                    OfflineManager.shared.syncShoot(shootID: shoot.id)
                                    viewModel.clearStatusCache(for: shoot.id)
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .foregroundColor(.blue)
                                        Text("Sync Now")
                                            .foregroundColor(.blue)
                                    }
                                }
                            } else {
                                Button(action: {
                                    cacheShootForOffline(id: shoot.id)
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.down.to.line")
                                            .foregroundColor(.blue)
                                        Text("Make Available Offline")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Network status indicator
                    Section(header: Text("Connection Status")) {
                        ConnectionStatusIndicator()
                            .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 320)
            .navigationTitle("Sports Shoots")
            .refreshable {
                viewModel.clearAllStatusCaches() // Clear all caches on refresh
                loadSportsShoots()
            }
            
            // Right side - Detail view
            if let shoot = viewModel.selectedShoot {
                ZStack {
                    // Main content
                    VStack(spacing: 0) {
                        // Use the new header component that includes connection status
                        VStack(alignment: .leading, spacing: 0) {
                            if viewModel.isHeaderCollapsed {
                                // Compressed header with connection status and cache status
                                HStack {
                                    // Back button for returning to master view
                                    Button(action: {
                                        // This action will show the primary/master view (sidebar)
                                        withAnimation {
                                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                               let rootVC = windowScene.windows.first?.rootViewController {
                                                if let splitVC = findSplitViewController(from: rootVC) {
                                                    splitVC.preferredDisplayMode = .oneBesideSecondary
                                                }
                                            }
                                        }
                                    }) {
                                        Image(systemName: "sidebar.left")
                                            .font(.system(size: 16))
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.trailing, 4)
                                    
                                    Text(shoot.schoolName)
                                        .font(.headline)
                                        .lineLimit(1)
                                    
                                    Text(" • ")
                                        .foregroundColor(.gray)
                                    
                                    Text(shoot.sportName)
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    // Add the cache status badge
                                    SyncStatusBadge(shootID: shoot.id)
                                        .font(.system(size: 18))
                                        .padding(.horizontal, 2)
                                    
                                    // Add the connection status indicator
                                    CompactConnectionIndicator()
                                        .padding(.horizontal, 2)
                                    
                                    Text(formatDate(shoot.shootDate))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemGroupedBackground))
                            } else {
                                // Full header with connection status and cache status
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        // Back button for returning to master view
                                        Button(action: {
                                            // This action will show the primary/master view (sidebar)
                                            withAnimation {
                                                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                                   let rootVC = windowScene.windows.first?.rootViewController {
                                                    if let splitVC = findSplitViewController(from: rootVC) {
                                                        splitVC.preferredDisplayMode = .oneBesideSecondary
                                                    }
                                                }
                                            }
                                        }) {
                                            Image(systemName: "sidebar.left")
                                                .font(.system(size: 18))
                                                .foregroundColor(.blue)
                                        }
                                        .padding(.trailing, 8)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(shoot.schoolName)
                                                .font(.title2)
                                                .fontWeight(.bold)
                                            
                                            HStack {
                                                Text(shoot.sportName)
                                                    .font(.headline)
                                                    .foregroundColor(.blue)
                                                
                                                Spacer()
                                                
                                                // Add the cache status badge
                                                SyncStatusBadge(shootID: shoot.id)
                                                    .font(.system(size: 18))
                                                    .padding(.horizontal, 2)
                                                
                                                // Add connection status indicator
                                                ConnectionStatusIndicator()
                                                    .padding(.horizontal, 2)
                                                
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
                        }
                        
                        // Toggle button for collapsing/expanding header
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.isHeaderCollapsed.toggle()
                            }
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: viewModel.isHeaderCollapsed ? "chevron.down" : "chevron.up")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .background(Color(.systemGroupedBackground))
                        }
                        
                        // Offline notification banner (if applicable)
                        if !viewModel.isOnline {
                            HStack {
                                Image(systemName: "wifi.slash")
                                    .foregroundColor(.orange)
                                
                                Text("You're offline - changes will sync when you reconnect")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
                        }
                        
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
                            Picker("", selection: $viewModel.selectedTab) {
                                Text("Athletes").tag(0)
                                Text("Groups").tag(1)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .onChange(of: viewModel.selectedTab) { newValue in
                                // Close filter panel when switching to Groups tab
                                if newValue == 1 {
                                    withAnimation {
                                        viewModel.showFilterPanel = false
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // Quick action buttons in header
                            HStack(spacing: 12) {
                                Button(action: {
                                    viewModel.showingMultiPhotoImport = true
                                }) {
                                    Image(systemName: "doc.viewfinder")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                }
                                
                                Button(action: {
                                    viewModel.showingImportExport = true
                                }) {
                                    Image(systemName: "square.and.arrow.up.on.square")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            // Show field mapping info
                            Text("Field Map: Last→Name, First→SubjectID")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .padding(.leading, 8)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        
                        // Active filters indicator (only shown when filters active)
                        if (!viewModel.selectedFilters.isEmpty || !viewModel.selectedSpecialFilters.isEmpty || viewModel.imageFilterType != .all) && viewModel.selectedTab == 0 {
                            HStack {
                                Text("Filtered by: ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) {
                                        // Show image filter indicator if active
                                        if viewModel.imageFilterType == .hasImages {
                                            Text("Has Images")
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.2))
                                                .foregroundColor(.green)
                                                .cornerRadius(4)
                                        } else if viewModel.imageFilterType == .noImages {
                                            Text("No Images")
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.2))
                                                .foregroundColor(.green)
                                                .cornerRadius(4)
                                        }
                                        
                                        // Show special filter indicators
                                        ForEach(Array(viewModel.selectedSpecialFilters), id: \.self) { special in
                                            Text(special)
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.purple.opacity(0.2))
                                                .foregroundColor(.purple)
                                                .cornerRadius(4)
                                        }
                                        
                                        // Show group filter indicators
                                        ForEach(Array(viewModel.selectedFilters), id: \.self) { group in
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
                                        viewModel.selectedFilters.removeAll()
                                        viewModel.selectedSpecialFilters.removeAll()
                                        viewModel.imageFilterType = .all
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
                        if viewModel.selectedTab == 0 {
                            rosterListView(shoot)
                        } else {
                            groupImagesListView(shoot)
                        }
                    }
                    .background(Color(.systemGroupedBackground))
                    
                    // Filter panel (slides out from right side)
                    FilterPanelView(
                        isShowing: $viewModel.showFilterPanel,
                        selectedFilters: $viewModel.selectedFilters,
                        selectedSpecialFilters: $viewModel.selectedSpecialFilters,
                        imageFilterType: $viewModel.imageFilterType,
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
                    if let entryID = viewModel.currentlyEditingEntry, let shootID = viewModel.selectedShoot?.id {
                        releaseLock(shootID: shootID, entryID: entryID)
                    }
                    
                    // Cancel any pending autosave tasks
                    viewModel.debounceTask?.cancel()
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
            
            // Monitor network status
            setupNetworkMonitoring()
            
            // Listen for conflict notifications
            setupConflictHandling()
        }
        .onChange(of: viewModel.editingImageNumber) { newValue in
            // Auto-save when the text changes
            if let entryID = viewModel.currentlyEditingEntry,
               let shootID = viewModel.selectedShoot?.id,
               let entry = viewModel.selectedShoot?.roster.first(where: { $0.id == entryID }),
               newValue != viewModel.lastSavedValue {
                
                // Cancel any existing debounce task
                viewModel.debounceTask?.cancel()
                
                // Create a new debounce task with a 0.5-second delay
                let task = DispatchWorkItem {
                    var updatedEntry = entry
                    updatedEntry.imageNumbers = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    SportsShootService.shared.updateRosterEntry(shootID: shootID, entry: updatedEntry) { result in
                        switch result {
                        case .success:
                            // Update the lastSavedValue to prevent redundant saves
                            viewModel.lastSavedValue = newValue
                            
                            // Trigger a partial update to notify other devices of changes
                            // This notifies listeners that a specific entry has been updated
                            onShootUpdated(shootID, entry: updatedEntry)
                        case .failure(let error):
                            print("Autosave error: \(error.localizedDescription)")
                        }
                    }
                }
                
                // Schedule the new task
                viewModel.debounceTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
            }
        }
        .sheet(isPresented: $viewModel.showingAddRosterEntry) {
            if let shoot = viewModel.selectedShoot {
                AddRosterEntryView(
                    shootID: shoot.id,
                    existingEntry: viewModel.selectedRosterEntry,
                    onComplete: { success in
                        if success {
                            refreshSelectedShoot()
                        }
                        viewModel.selectedRosterEntry = nil
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.showingAddGroupImage) {
            if let shoot = viewModel.selectedShoot {
                AddGroupImageView(
                    shootID: shoot.id,
                    existingGroup: viewModel.selectedGroupImage,
                    onComplete: { success in
                        if success {
                            refreshSelectedShoot()
                        }
                        viewModel.selectedGroupImage = nil
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.showingImportExport) {
            if let shoot = viewModel.selectedShoot {
                CSVImportExportView(
                    shootID: shoot.id,
                    onComplete: { success in
                        if success {
                            refreshSelectedShoot()
                        }
                        viewModel.showingImportExport = false
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.showingMultiPhotoImport) {
            if let shoot = viewModel.selectedShoot {
                MultiPhotoRosterImporterView(
                    shootID: shoot.id,
                    onComplete: { success in
                        if success {
                            refreshSelectedShoot()
                        }
                        viewModel.showingMultiPhotoImport = false
                    }
                )
            }
        }
    }
    
    // MARK: - SportsShootRow Component
    
    struct SportsShootRow: View {
        let shoot: SportsShoot
        let isSelected: Bool
        let onSelect: () -> Void
        let onSyncNow: () -> Void
        let onMakeAvailableOffline: () -> Void
        var isInsideNavigationLink: Bool = false // New parameter to control Button wrapper
        
        // Use state to avoid redrawing the entire row on every status check
        @State private var syncStatus: OfflineManager.CacheStatus = .notCached
        @State private var isOnline: Bool = true
        
        var body: some View {
            let content = HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(shoot.schoolName)
                            .font(.headline)
                        Spacer()
                        Text(shoot.sportName)
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    Text(formatDate(shoot.shootDate))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    HStack {
                        Label("\(shoot.roster.count) Athletes", systemImage: "person.3")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Label("\(shoot.groupImages.count) Groups", systemImage: "person.3.sequence")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
                
                // Sync status badge - moved to a separate component
                statusBadge
                    .font(.system(size: 18))
                    .padding(.leading, 4)
            }
            .padding(.vertical, 4)
            
            // Conditionally wrap in Button based on isInsideNavigationLink
            Group {
                if isInsideNavigationLink {
                    // When inside NavigationLink, don't wrap in Button
                    content
                        .contentShape(Rectangle())
                } else {
                    // When not inside NavigationLink (iPad), wrap in Button
                    Button(action: onSelect) {
                        content
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle())
                }
            }
            .contextMenu {
                // Offline related options in context menu
                if OfflineManager.shared.isShootCached(id: shoot.id) {
                    Button(action: onSyncNow) {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                } else {
                    Button(action: onMakeAvailableOffline) {
                        Label("Make Available Offline", systemImage: "arrow.down.to.line")
                    }
                }
                
                // Standard options
                Button(action: onSelect) {
                    Label("View Details", systemImage: "eye")
                }
            }
            .onAppear {
                // Initial status update
                updateStatus()
                
                // Listen for network status changes
                setupNetworkStatusObserver()
            }
        }
        
        private var statusBadge: some View {
            Group {
                switch syncStatus {
                case .notCached:
                    if isOnline {
                        EmptyView()  // No badge for uncached shoots when online
                    } else {
                        // When offline, show that this shoot is not available
                        Image(systemName: "icloud.slash")
                            .foregroundColor(.red)
                            .transition(.opacity) // Smooth transition
                    }
                case .cached:
                    Image(systemName: "icloud.and.arrow.down.fill")
                        .foregroundColor(.blue)
                        .transition(.opacity)
                case .modified:
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundColor(.orange)
                        .transition(.opacity)
                case .syncing:
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.green)
                        .transition(.opacity)
                case .error:
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: syncStatus) // Add animation to smooth transitions
        }
        
        private func updateStatus() {
            // Get status from the offline manager
            let newStatus = OfflineManager.shared.cacheStatusForShoot(id: shoot.id)
            let newOnline = OfflineManager.shared.isDeviceOnline()
            
            // Only update if status actually changed to avoid UI flashing
            if syncStatus != newStatus || isOnline != newOnline {
                withAnimation(.easeInOut(duration: 0.3)) {
                    syncStatus = newStatus
                    isOnline = newOnline
                }
            }
        }
        
        private func setupNetworkStatusObserver() {
            // Listen for network status changes
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("NetworkStatusChanged"),
                object: nil,
                queue: .main
            ) { notification in
                if let isConnected = notification.userInfo?["isConnected"] as? Bool {
                    self.updateStatus()
                }
            }
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("OfflineManagerNetworkStatusChanged"),
                object: nil,
                queue: .main
            ) { notification in
                if let isConnected = notification.userInfo?["isOnline"] as? Bool {
                    self.updateStatus()
                }
            }
        }
        
        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        let networkMonitor = NetworkMonitor.shared
        networkMonitor.startMonitoring { isConnected in
            DispatchQueue.main.async {
                self.viewModel.isOnline = isConnected
                
                // If we just came back online, try to sync any modified shoots
                if isConnected {
                    OfflineManager.shared.syncModifiedShoots()
                }
            }
        }
    }
    
    // MARK: - Conflict Handling
    
    private func setupConflictHandling() {
        // Listen for sync conflict notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SyncConflictsDetected"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let shootID = userInfo["shootID"] as? String,
                  let entryConflicts = userInfo["entryConflicts"] as? [OfflineManager.EntryConflict],
                  let groupConflicts = userInfo["groupConflicts"] as? [OfflineManager.GroupConflict],
                  let localShoot = userInfo["localShoot"] as? SportsShoot,
                  let remoteShoot = userInfo["remoteShoot"] as? SportsShoot else {
                return
            }
            
            // Show conflict resolution view
            DispatchQueue.main.async {
                // Present conflict resolution view
                let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
                if let rootVC = keyWindow?.rootViewController {
                    // Create and present the conflict resolution view
                    let conflictView = ConflictResolutionView(
                        shootID: shootID,
                        entryConflicts: entryConflicts,
                        groupConflicts: groupConflicts,
                        localShoot: localShoot,
                        remoteShoot: remoteShoot,
                        onComplete: { success in
                            if success {
                                // Refresh data after conflict resolution
                                self.refreshSelectedShoot()
                            }
                        }
                    )
                    
                    let hostingController = UIHostingController(rootView: conflictView)
                    rootVC.present(hostingController, animated: true)
                }
            }
        }
    }
    
    // MARK: - Filter Panel View
    
    struct FilterPanelView: View {
        @Binding var isShowing: Bool
        @Binding var selectedFilters: Set<String>
        @Binding var selectedSpecialFilters: Set<String>
        @Binding var imageFilterType: SportsShootListViewModel.ImageFilterType
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
    
    // MARK: - Roster List View (iPad only)
    
    private func rosterListView(_ shoot: SportsShoot) -> some View {
        VStack(spacing: 0) {
            // Column headers with sorting functionality and filter button
            HStack {
                sortableHeader("Name", field: "lastName")
                sortableHeader("Subject ID", field: "firstName")
                sortableHeader("Special", field: "teacher")
                sortableHeader("Sport/Team", field: "group")
                
                Spacer()
                
                // Add filter button
                Button(action: {
                    withAnimation {
                        viewModel.showFilterPanel.toggle()
                    }
                }) {
                    Image(systemName: "line.horizontal.3.decrease.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                }
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
                viewModel.selectedRosterEntry = nil
                viewModel.showingAddRosterEntry = true
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
        let isLockedByOthers = viewModel.lockedEntries[entry.id] != nil && !isOwnLock
        
        // We are currently editing this entry
        let isCurrentlyEditing = viewModel.currentlyEditingEntry == entry.id
        
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
                        viewModel.selectedRosterEntry = entry
                        viewModel.showingAddRosterEntry = true
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
                            .fixedSize(horizontal: false, vertical: true)
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
                        text: $viewModel.editingImageNumber,
                        placeholder: "Enter image numbers",
                        onTapOutside: {
                            // Field autosaves on text change
                        },
                        onEnterOrDown: {
                            // Find the next editable entry and start editing it
                            moveToNextEditableEntry(currentID: entry.id)
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
                        
                        if let editor = viewModel.lockedEntries[entry.id] {
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
                
                // Right side - Group/Team tag
                if !entry.group.isEmpty {
                    Button(action: {
                        if !isLockedByOthers {
                            viewModel.selectedRosterEntry = entry
                            viewModel.showingAddRosterEntry = true
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
                    viewModel.selectedRosterEntry = entry
                    viewModel.showingAddRosterEntry = true
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
    
    // MARK: - Group Images List View
    
    private func groupImagesListView(_ shoot: SportsShoot) -> some View {
        VStack {
            List {
                ForEach(shoot.groupImages) { group in
                    Button(action: {
                        viewModel.selectedGroupImage = group
                        viewModel.showingAddGroupImage = true
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
                                            .contextMenu {
                                                Button(action: {
                                                    viewModel.selectedGroupImage = group
                                                    viewModel.showingAddGroupImage = true
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
                                        viewModel.selectedGroupImage = nil
                                        viewModel.showingAddGroupImage = true
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
                            
                            // Function to move to the next editable entry when pressing Enter or Down arrow
                            private func moveToNextEditableEntry(currentID: String) {
                                guard let shoot = viewModel.selectedShoot else { return }
                                
                                // Get the filtered and sorted roster as displayed in the list
                                let displayedRoster = sortedRoster(filterRoster(shoot.roster))
                                
                                // Find the index of the current entry
                                guard let currentIndex = displayedRoster.firstIndex(where: { $0.id == currentID }) else {
                                    return
                                }
                                
                                // Try to find the next entry that's not locked by others
                                for index in (currentIndex + 1)..<displayedRoster.count {
                                    let nextEntry = displayedRoster[index]
                                    let isLocked = viewModel.lockedEntries[nextEntry.id] != nil && viewModel.lockedEntries[nextEntry.id] != currentEditorIdentifier
                                    
                                    if !isLocked {
                                        // Release current lock
                                        if let currentEntryID = viewModel.currentlyEditingEntry {
                                            releaseLock(shootID: shoot.id, entryID: currentEntryID)
                                        }
                                        
                                        // Start editing the next entry
                                        startEditing(shootID: shoot.id, entry: nextEntry)
                                        
                                        // Optionally scroll to make the entry visible
                                        // This would require additional changes to track scroll position
                                        
                                        return
                                    }
                                }
                                
                                // If we reach here, we're at the last entry or all remaining entries are locked
                                // Option 1: Loop back to the first entry
                                for index in 0..<currentIndex {
                                    let nextEntry = displayedRoster[index]
                                    let isLocked = viewModel.lockedEntries[nextEntry.id] != nil && viewModel.lockedEntries[nextEntry.id] != currentEditorIdentifier
                                    
                                    if !isLocked {
                                        // Release current lock
                                        if let currentEntryID = viewModel.currentlyEditingEntry {
                                            releaseLock(shootID: shoot.id, entryID: currentEntryID)
                                        }
                                        
                                        // Start editing the entry
                                        startEditing(shootID: shoot.id, entry: nextEntry)
                                        return
                                    }
                                }
                                
                                // Option 2: Just release the current lock if no other entries are available
                                if let currentEntryID = viewModel.currentlyEditingEntry {
                                    releaseLock(shootID: shoot.id, entryID: currentEntryID)
                                }
                            }
                            
                            // Generate a consistent color for each group
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
                            
                            // Sort button for roster columns with updated display names
                            private func sortableHeader(_ title: String, field: String) -> some View {
                                Button(action: {
                                    if viewModel.sortField == field {
                                        viewModel.sortAscending.toggle()
                                    } else {
                                        viewModel.sortField = field
                                        viewModel.sortAscending = true
                                    }
                                }) {
                                    HStack(spacing: 1) {
                                        Text(title)
                                            .font(viewModel.isHeaderCollapsed ? .system(size: 9) : .caption)
                                            .lineLimit(1)
                                        
                                        Image(systemName: viewModel.sortField == field
                                              ? (viewModel.sortAscending ? "chevron.up" : "chevron.down")
                                              : "arrow.up.arrow.down")
                                            .font(.system(size: viewModel.isHeaderCollapsed ? 7 : 8))
                                            .foregroundColor(viewModel.sortField == field ? .blue : .gray)
                                    }
                                    .padding(.vertical, viewModel.isHeaderCollapsed ? 2 : 4)
                                    .padding(.horizontal, viewModel.isHeaderCollapsed ? 4 : 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(viewModel.sortField == field ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                    )
                                }
                            }
                            
                            // Sort roster entries
                            private func sortedRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
                                return roster.sorted { (a, b) -> Bool in
                                    let result: Bool
                                    
                                    switch viewModel.sortField {
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
                                    
                                    return viewModel.sortAscending ? result : !result
                                }
                            }
                            
                            // MARK: - Data Loading and Actions
                            
                            private func loadSportsShoots() {
                                guard !storedUserOrganizationID.isEmpty else {
                                    viewModel.errorMessage = "No organization ID found. Please sign in again."
                                    viewModel.showingErrorAlert = true
                                    return
                                }
                                
                                viewModel.isLoading = true
                                print("Fetching sports shoots with organization ID: \(storedUserOrganizationID)")
                                
                                SportsShootService.shared.fetchAllSportsShoots(forOrganization: storedUserOrganizationID) { result in
                                    DispatchQueue.main.async {
                                        self.viewModel.isLoading = false
                                        
                                        switch result {
                                        case .success(let shoots):
                                            print("Successfully fetched \(shoots.count) sports shoots")
                                            self.viewModel.sportsShoots = shoots
                                            
                                            // Do not auto-select any item - let user choose explicitly
                                            // selectedShoot remains nil until user makes a selection
                                            
                                        case .failure(let error):
                                            print("Error loading sports shoots: \(error.localizedDescription)")
                                            self.viewModel.errorMessage = "Failed to load sports shoots: \(error.localizedDescription)"
                                            self.viewModel.showingErrorAlert = true
                                        }
                                    }
                                }
                            }
                            
                            private func onShootUpdated(_ updatedShootID: String, entry: RosterEntry? = nil) {
                                // Only refresh if the updated shoot is the one currently displayed
                                if let currentShoot = viewModel.selectedShoot, currentShoot.id == updatedShootID {
                                    // If we received a specific entry update, apply it immediately
                                    if let updatedEntry = entry {
                                        if var currentRoster = viewModel.selectedShoot?.roster {
                                            // Find and replace the updated entry
                                            if let index = currentRoster.firstIndex(where: { $0.id == updatedEntry.id }) {
                                                currentRoster[index] = updatedEntry
                                                viewModel.selectedShoot?.roster = currentRoster
                                            }
                                        }
                                    } else {
                                        // Otherwise refresh the entire shoot data
                                        refreshSelectedShoot()
                                    }
                                }
                            }
                            
                            private func refreshSelectedShoot() {
                                guard let currentShoot = viewModel.selectedShoot else { return }
                                
                                SportsShootService.shared.fetchSportsShoot(id: currentShoot.id) { result in
                                    DispatchQueue.main.async {
                                        switch result {
                                        case .success(let updatedShoot):
                                            // Update the selected shoot
                                            self.viewModel.selectedShoot = updatedShoot
                                            
                                            // Also update this shoot in the list
                                            if let index = self.viewModel.sportsShoots.firstIndex(where: { $0.id == updatedShoot.id }) {
                                                self.viewModel.sportsShoots[index] = updatedShoot
                                            }
                                            
                                        case .failure(let error):
                                            self.viewModel.errorMessage = "Failed to refresh: \(error.localizedDescription)"
                                            self.viewModel.showingErrorAlert = true
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
                                            self.viewModel.errorMessage = "Failed to delete athlete: \(error.localizedDescription)"
                                            self.viewModel.showingErrorAlert = true
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
                                            self.viewModel.errorMessage = "Failed to delete group: \(error.localizedDescription)"
                                            self.viewModel.showingErrorAlert = true
                                        }
                                    }
                                }
                            }
                            
                            private func formatDate(_ date: Date) -> String {
                                let formatter = DateFormatter()
                                formatter.dateStyle = .medium
                                return formatter.string(from: date)
                            }
                            
                            // MARK: - Offline Features
                            
                            // Cache a shoot for offline use
                            private func cacheShootForOffline(id: String) {
                                SportsShootService.shared.cacheShootForOffline(id: id) { success in
                                    DispatchQueue.main.async {
                                        if success {
                                            // Refresh the UI to show the updated sync status
                                            self.viewModel.triggerUpdate()
                                            viewModel.clearStatusCache(for: id)
                                            
                                            // Show success message
                                            self.viewModel.errorMessage = "This shoot is now available offline"
                                            self.viewModel.showingErrorAlert = true
                                        } else {
                                            // Show error message
                                            self.viewModel.errorMessage = "Failed to save for offline use. Please try again."
                                            self.viewModel.showingErrorAlert = true
                                        }
                                    }
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
                                if let shootID = viewModel.selectedShoot?.id {
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
                                return viewModel.currentlyEditingEntry != nil
                            }
                            
                            // MARK: - Lock Management
                            
                            private func setupLockListener() {
                                guard let shootID = viewModel.selectedShoot?.id else { return }
                                
                                // Set up a real-time listener for locks
                                // Use SnapshotListener instead of a direct query to get real-time updates
                                EntryLockManager.shared.listenForLocks(shootID: shootID) { locks in
                                    DispatchQueue.main.async {
                                        self.viewModel.lockedEntries = locks
                                        
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
                                            self.viewModel.currentlyEditingEntry = entryID
                                        }
                                    } else {
                                        // Show error if lock acquisition fails
                                        DispatchQueue.main.async {
                                            print("Failed to acquire lock for: \(entryID)")
                                            self.viewModel.errorMessage = "This entry is being edited by someone else. Please try again later."
                                            self.viewModel.showingErrorAlert = true
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
                                        
                                        if self.viewModel.currentlyEditingEntry == entryID {
                                            self.viewModel.currentlyEditingEntry = nil
                                            self.viewModel.editingImageNumber = ""
                                            self.viewModel.lastSavedValue = ""
                                            self.viewModel.debounceTask?.cancel()
                                        }
                                    }
                                }
                            }
                            
                            private func refreshLocks() {
                                guard let shootID = viewModel.selectedShoot?.id else { return }
                                EntryLockManager.shared.cleanupStaleLocks(shootID: shootID)
                            }
                            
                            // MARK: - Editing Functions
                            
                            private func startEditing(shootID: String, entry: RosterEntry) {
                                print("Attempting to start editing entry: \(entry.id)")
                                
                                // Show who is editing this entry (for debugging)
                                if let editor = viewModel.lockedEntries[entry.id] {
                                    print("Entry is locked by: \(editor)")
                                } else {
                                    print("Entry is not currently locked")
                                }
                                
                                // Check if anyone else is editing this entry
                                if let editor = viewModel.lockedEntries[entry.id], !isOwnLock(entry.id) {
                                    // Entry is locked by someone else - show an alert
                                    viewModel.errorMessage = "This entry is currently being edited by \(editor)"
                                    viewModel.showingErrorAlert = true
                                    return
                                }
                                
                                // Check if we already have a lock on this entry
                                if isOwnLock(entry.id) {
                                    print("Already have a lock on this entry - resuming edit")
                                    // We already have the lock, just start editing without acquiring a new lock
                                    viewModel.currentlyEditingEntry = entry.id
                                    viewModel.editingImageNumber = entry.imageNumbers
                                    viewModel.lastSavedValue = entry.imageNumbers
                                    return
                                }
                                
                                // Release any previous lock
                                if let previousEntryID = viewModel.currentlyEditingEntry {
                                    releaseLock(shootID: shootID, entryID: previousEntryID)
                                }
                                
                                // Set up editing state
                                viewModel.editingImageNumber = entry.imageNumbers
                                viewModel.lastSavedValue = entry.imageNumbers // Set initial saved value
                                
                                // Acquire lock for this entry
                                acquireLock(shootID: shootID, entryID: entry.id)
                            }
                        }

                        struct SportsShootListView_Previews: PreviewProvider {
                            static var previews: some View {
                                SportsShootListView()
                            }
                        }
