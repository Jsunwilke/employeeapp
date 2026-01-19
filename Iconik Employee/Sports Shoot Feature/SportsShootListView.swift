import SwiftUI
import Supabase
import Combine

// State management class to handle objectWillChange notifications
class SportsShootListViewModel: ObservableObject {
    @Published var sportsShoots: [SportsShoot] = []
    @Published var selectedShoot: SportsShoot? = nil
    @Published var isLoading = true
    @Published var errorMessage = ""
    @Published var showingErrorAlert = false
    @Published var showArchived = false // Toggle between active and archived shoots

    // Network status
    @Published var isOnline = true

    // Roster and Groups data (fetched separately via services)
    @Published var rosterEntries: [RosterEntry] = []
    @Published var groupImages: [GroupImage] = []

    // States for roster management
    @Published var showingAddRosterEntry = false
    @Published var showingBatchAdd = false
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
    @Published var currentlyEditingEntry: UUID? = nil // ID of entry being edited
    @Published var editingImageNumber: String = ""
    @Published var lockedEntries: [UUID: String] = [:] // [entryID: editorName]
    
    // UI state - header collapsed in landscape
    @Published var isHeaderCollapsed = true
    
    // Filter panel state
    @Published var showFilterPanel = false
    @Published var selectedFilters: Set<String> = []
    @Published var selectedSpecialFilters: Set<String> = []
    @Published var imageFilterType: ImageFilterType = .all
    
    // Track if value has changed for save-on-blur
    @Published var hasUnsavedChanges: Bool = false

    // Enum moved from the view to the view model
    enum ImageFilterType {
        case all
        case hasImages
        case noImages
    }
    
    // Computed property to filter shoots based on archive status
    var filteredSportsShoots: [SportsShoot] {
        sportsShoots.filter { shoot in
            showArchived ? shoot.isArchived : !shoot.isArchived
        }
    }
    
    // Method to archive/unarchive a shoot
    func toggleArchiveStatus(for shoot: SportsShoot) {
        Task { @MainActor in
            do {
                if shoot.isArchived {
                    try await SportsShootService.shared.unarchiveSportsShoot(id: shoot.id)
                    // Update local copy
                    if let index = sportsShoots.firstIndex(where: { $0.id == shoot.id }) {
                        sportsShoots[index].isArchived = false
                    }
                    // If we're viewing archived and unarchived the selected shoot, clear selection
                    if showArchived == true && selectedShoot?.id == shoot.id {
                        selectedShoot = nil
                    }
                } else {
                    try await SportsShootService.shared.archiveSportsShoot(id: shoot.id)
                    // Update local copy
                    if let index = sportsShoots.firstIndex(where: { $0.id == shoot.id }) {
                        sportsShoots[index].isArchived = true
                    }
                    // If we're viewing active and archived the selected shoot, clear selection
                    if showArchived == false && selectedShoot?.id == shoot.id {
                        selectedShoot = nil
                    }
                }
            } catch {
                errorMessage = "Failed to \(shoot.isArchived ? "unarchive" : "archive"): \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }
    
    // Method to manually trigger UI updates
    func triggerUpdate() {
        // Only trigger an update when there's actually a change to show
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}

struct SportsShootListView: View {
    // MARK: - Properties
    
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""
    
    // Access TabBarManager to check for selected session
    @ObservedObject private var tabBarManager = TabBarManager.shared
    
    // Device session ID - unique to this app instance
    // Use LockManager's editor identifier for consistency
    private var currentEditorIdentifier: String {
        return LockManager.shared.currentEditorIdentifier
    }
    
    // Use the view model for state management
    @StateObject private var viewModel = SportsShootListViewModel()

    // PowerSync for offline-first operations
    @StateObject private var powerSync = PowerSyncManager.shared

    // Focus state for keyboard navigation
    @FocusState private var focusedField: String?
    
    // Device orientation detection
    @State private var orientation = UIDeviceOrientation.unknown
    
    // Track if view is visible to optimize timers
    @State private var isViewVisible = false

    // Unique subscription ID for this view instance (prevents overwriting other subscribers)
    private let subscriptionId = UUID()

    // Track expanded schools in archived view
    @State private var expandedSchools: Set<String> = []

    // Supabase realtime listener reference
    @State private var shootListener: ListenerRegistrationWrapper?
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    
    // Sync statuses refresh timer - using a longer interval to prevent flickering
    let syncStatusTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // Filter options
    let specialFilters = ["Seniors", "8th Graders", "Coaches"]
    
    // Check if we're on iPhone
    private var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    // Group archived jobs by school for folder display
    private var archivedJobsBySchool: [(school: String, shoots: [SportsShoot])] {
        let grouped = Dictionary(grouping: viewModel.filteredSportsShoots) { $0.schoolName }
        return grouped.map { (school: $0.key.isEmpty ? "No School" : $0.key, shoots: $0.value) }
            .sorted { $0.school < $1.school }
    }

    // MARK: - Helper Functions
    
    // Check if a lock is owned by this device
    private func isOwnLock(_ lockId: UUID) -> Bool {
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
        guard viewModel.selectedShoot != nil else { return [] }

        let allGroups = Set(viewModel.rosterEntries.map { $0.groupName })
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
                let matchesGroup = viewModel.selectedFilters.contains(entry.groupName)
                
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
        .customKeyboardOverlay() // Add custom keyboard support
        .onAppear {
            isViewVisible = true

            // Initialize LockManager with current user
            if let userId = SupabaseManager.shared.client.auth.currentUser?.id {
                LockManager.shared.setCurrentUser(
                    userId: userId,
                    userName: "\(storedUserFirstName) \(storedUserLastName)"
                )
            }

            loadSportsShoots()
            setupNetworkMonitoring()
            setupConflictHandling()
        }
        .onDisappear {
            isViewVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            // Re-load data when app returns to foreground
            loadSportsShoots()
        }
        .onReceive(syncStatusTimer) { _ in
            if isViewVisible {
                viewModel.triggerUpdate()
            }
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
        VStack(spacing: 0) {
            // Segmented control for Active/Archived
            Picker("View", selection: $viewModel.showArchived) {
                Text("Active").tag(false)
                Text("Archived").tag(true)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            List {
                if viewModel.isLoading {
                    ProgressView("Loading sports shoots...")
                        .padding()
                        .listRowBackground(Color.clear)
                } else if viewModel.filteredSportsShoots.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: viewModel.showArchived ? "archivebox" : "camera.on.rectangle")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                            .padding()
                        
                        Text(viewModel.showArchived ? "No Archived Sports Shoots" : "No Active Sports Shoots")
                            .font(.headline)
                        
                        Text(viewModel.showArchived ? "No sports shoots have been archived yet" : "Sports shoots are created via the web interface and will appear here once available")
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
                    if viewModel.showArchived {
                        // Archived: Show grouped by school in collapsible folders
                        ForEach(archivedJobsBySchool, id: \.school) { group in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedSchools.contains(group.school) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedSchools.insert(group.school)
                                        } else {
                                            expandedSchools.remove(group.school)
                                        }
                                    }
                                )
                            ) {
                                ForEach(group.shoots) { sportsShoot in
                                    NavigationLink(destination: SportsShootDetailView(shootID: sportsShoot.id)) {
                                        SportsShootRow(
                                            shoot: sportsShoot,
                                            isSelected: false,
                                            onSelect: { },
                                            onSyncNow: {
                                                Task { try? await powerSync.connect() }
                                            },
                                            onMakeAvailableOffline: {
                                                Task { try? await powerSync.connect() }
                                            },
                                            isInsideNavigationLink: true
                                        )
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(action: {
                                            viewModel.toggleArchiveStatus(for: sportsShoot)
                                        }) {
                                            Label("Unarchive", systemImage: "tray.and.arrow.up")
                                        }
                                        .tint(.green)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.blue)
                                    Text(group.school)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(group.shoots.count)")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                            }
                        }
                    } else {
                        // Active: Show flat list
                        ForEach(viewModel.filteredSportsShoots) { sportsShoot in
                            NavigationLink(destination: SportsShootDetailView(shootID: sportsShoot.id)) {
                                SportsShootRow(
                                    shoot: sportsShoot,
                                    isSelected: false,
                                    onSelect: { },
                                    onSyncNow: {
                                        Task {
                                            try? await powerSync.connect()
                                        }
                                    },
                                    onMakeAvailableOffline: {
                                        Task { try? await powerSync.connect() }
                                    },
                                    isInsideNavigationLink: true
                                )
                            }
                            .swipeActions(edge: .trailing) {
                                Button(action: {
                                    viewModel.toggleArchiveStatus(for: sportsShoot)
                                }) {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
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
            .navigationTitle(viewModel.showArchived ? "Archived Sports Shoots" : "Sports Shoots")
            .refreshable {
                loadSportsShoots()
            }
        }
    }
    
    // MARK: - iPad View (existing implementation)
    
    private var iPadView: some View {
        NavigationView {
            // Left side - List of shoots
            VStack(spacing: 0) {
                // Segmented control for Active/Archived
                Picker("View", selection: $viewModel.showArchived) {
                    Text("Active").tag(false)
                    Text("Archived").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                List {
                if viewModel.isLoading {
                    ProgressView("Loading sports shoots...")
                        .padding()
                        .listRowBackground(Color.clear)
                } else if viewModel.filteredSportsShoots.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: viewModel.showArchived ? "archivebox" : "camera.on.rectangle")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                            .padding()
                        
                        Text(viewModel.showArchived ? "No Archived Sports Shoots" : "No Active Sports Shoots")
                            .font(.headline)
                        
                        Text(viewModel.showArchived ? "No sports shoots have been archived yet" : "Sports shoots are created via the web interface and will appear here once available")
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
                    if viewModel.showArchived {
                        // Archived: Show grouped by school in collapsible folders
                        ForEach(archivedJobsBySchool, id: \.school) { group in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedSchools.contains(group.school) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedSchools.insert(group.school)
                                        } else {
                                            expandedSchools.remove(group.school)
                                        }
                                    }
                                )
                            ) {
                                ForEach(group.shoots) { sportsShoot in
                                    SportsShootRow(
                                        shoot: sportsShoot,
                                        isSelected: viewModel.selectedShoot?.id == sportsShoot.id,
                                        onSelect: {
                                            viewModel.selectedShoot = sportsShoot
                                            collapseSidebarAfterSelection()
                                        },
                                        onSyncNow: {
                                            Task { try? await powerSync.connect() }
                                        },
                                        onMakeAvailableOffline: {
                                            Task { try? await powerSync.connect() }
                                        }
                                    )
                                    .background(viewModel.selectedShoot?.id == sportsShoot.id ? Color.blue.opacity(0.1) : Color.clear)
                                    .cornerRadius(8)
                                    .contextMenu {
                                        Button(action: {
                                            viewModel.toggleArchiveStatus(for: sportsShoot)
                                        }) {
                                            Label("Unarchive", systemImage: "tray.and.arrow.up")
                                        }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(action: {
                                            viewModel.toggleArchiveStatus(for: sportsShoot)
                                        }) {
                                            Label("Unarchive", systemImage: "tray.and.arrow.up")
                                        }
                                        .tint(.green)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.blue)
                                    Text(group.school)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(group.shoots.count)")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                            }
                        }
                    } else {
                        // Active: Show flat list
                        ForEach(viewModel.filteredSportsShoots) { sportsShoot in
                            SportsShootRow(
                                shoot: sportsShoot,
                                isSelected: viewModel.selectedShoot?.id == sportsShoot.id,
                                onSelect: {
                                    viewModel.selectedShoot = sportsShoot
                                    collapseSidebarAfterSelection()
                                },
                                onSyncNow: {
                                    Task {
                                        try? await powerSync.connect()
                                    }
                                },
                                onMakeAvailableOffline: {
                                    Task { try? await powerSync.connect() }
                                }
                            )
                            .background(viewModel.selectedShoot?.id == sportsShoot.id ? Color.blue.opacity(0.1) : Color.clear)
                            .cornerRadius(8)
                            .contextMenu {
                                Button(action: {
                                    viewModel.toggleArchiveStatus(for: sportsShoot)
                                }) {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(action: {
                                    viewModel.toggleArchiveStatus(for: sportsShoot)
                                }) {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                        }
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
                        
                        // Sync button - triggers PowerSync reconnect
                        if viewModel.selectedShoot != nil {
                            Button(action: {
                                Task {
                                    try? await powerSync.connect()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(.blue)
                                    Text("Sync Now")
                                        .foregroundColor(.blue)
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
            }
            .navigationTitle(viewModel.showArchived ? "Archived Sports Shoots" : "Sports Shoots")
            .refreshable {
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
                                    // Sidebar toggle button
                                    Button(action: {
                                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                           let rootVC = windowScene.windows.first?.rootViewController {
                                            if let splitVC = Self.findSplitViewController(from: rootVC) {
                                                splitVC.preferredDisplayMode = 
                                                    splitVC.preferredDisplayMode == .oneBesideSecondary ? 
                                                    .secondaryOnly : .oneBesideSecondary
                                            }
                                        }
                                    }) {
                                        Image(systemName: "sidebar.left")
                                            .font(.system(size: 16))
                                            .foregroundColor(.blue)
                                    }
                                    
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

                    // Set up a real-time listener for updates
                    setupRealtimeListeners()

                    // iPad: Load initial roster data and clean up stale locks
                    // (iPhone does this in SportsShootDetailView)
                    if let shootID = viewModel.selectedShoot?.id {
                        Task {
                            await loadRosterForSelectedShoot(shootID: shootID)
                            try? await RosterEntryService.shared.releaseExpiredLocks(forJob: shootID)
                            try? await GroupImageService.shared.releaseExpiredLocks(forJob: shootID)
                        }
                    }
                }
                .onDisappear {
                    // Remove orientation notification observer
                    NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)

                    // Remove realtime listener
                    shootListener?.remove()
                    shootListener = nil

                    // Unsubscribe from roster entry realtime changes
                    Task {
                        await RosterEntryService.shared.unsubscribe(subscriptionId: subscriptionId)
                    }

                    // Release any locks when leaving the view
                    if let entryID = viewModel.currentlyEditingEntry {
                        saveCurrentEditingEntry()
                        Task {
                            await LockManager.shared.releaseRosterEntryLock(entryId: entryID)
                        }
                    }
                }
                .onChange(of: shoot.id) { newShootID in
                    // When the selected shoot changes, set up listeners for the new shoot
                    setupRealtimeListeners()

                    // Load roster data and clean up stale locks for the new shoot
                    Task {
                        await loadRosterForSelectedShoot(shootID: newShootID)
                        try? await RosterEntryService.shared.releaseExpiredLocks(forJob: newShootID)
                        try? await GroupImageService.shared.releaseExpiredLocks(forJob: newShootID)
                    }
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
            isViewVisible = true
            loadSportsShoots()
            
            // Check if we're navigating from a widget
            if tabBarManager.selectedSportsShoot != nil {
                // We came from widget - collapse sidebar to show detail view only
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    collapseSidebarAfterSelection()
                }
            } else {
                // Normal navigation - show the sidebar
                forceSidebarVisibility()
            }
            
            // Monitor network status
            setupNetworkMonitoring()
            
            // Listen for conflict notifications
            setupConflictHandling()
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
        .sheet(isPresented: $viewModel.showingBatchAdd) {
            if let shoot = viewModel.selectedShoot {
                BatchAddAthletesView(
                    shootID: shoot.id,
                    onComplete: { success in
                        if success {
                            refreshSelectedShoot()
                        }
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

        // Use state to track offline status
        @State private var isFullyCached: Bool = false
        @State private var pendingChangeCount: Int = 0
        @State private var isOnline: Bool = true
        
        var body: some View {
            let content = HStack(alignment: .center, spacing: 6) {
                // Always show sidebar button for testing
                Button(action: {
                    // Show the sidebar
                    showSidebar()
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                
                // School name - takes available space
                Text(shoot.schoolName)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                // Sport and date on the right
                HStack(spacing: 4) {
                    Text(shoot.sportName)
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    
                    Text(formatDate(shoot.shootDate))
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                
                // Sync status badge
                statusBadge
                    .font(.system(size: 14))
            }
            .frame(height: 30)
            .fixedSize(horizontal: false, vertical: true)
            
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
                if pendingChangeCount > 0 {
                    Button(action: onSyncNow) {
                        Label("Sync \(pendingChangeCount) pending change\(pendingChangeCount == 1 ? "" : "s")", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                if isFullyCached {
                    Label("Available Offline", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
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
                if pendingChangeCount > 0 {
                    // Has pending changes - show orange sync indicator
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.orange)
                        .transition(.opacity)
                } else if isFullyCached {
                    // Available offline - show green checkmark
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.green)
                        .transition(.opacity)
                } else if !isOnline {
                    // Not cached and offline - show red indicator
                    Image(systemName: "icloud.slash")
                        .foregroundColor(.red)
                        .transition(.opacity)
                } else {
                    // Not cached but online - no indicator
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isFullyCached) // Add animation to smooth transitions
        }
        
        private func updateStatus() {
            // Get status from PowerSync - data is always available locally
            let newIsFullyCached = true // PowerSync keeps data locally in SQLite
            let newPendingCount = 0
            let newOnline = PowerSyncManager.shared.isConnected

            // Only update if status actually changed to avoid UI flashing
            if isFullyCached != newIsFullyCached || pendingChangeCount != newPendingCount || isOnline != newOnline {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isFullyCached = newIsFullyCached
                    pendingChangeCount = newPendingCount
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
            
        }
        
        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
        
        private func showSidebar() {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                findAndShowSplitView(from: rootVC)
            }
        }
        
        private func findAndShowSplitView(from viewController: UIViewController) {
            if let splitVC = viewController as? UISplitViewController {
                splitVC.preferredDisplayMode = .oneBesideSecondary
                return
            }
            
            for child in viewController.children {
                findAndShowSplitView(from: child)
            }
        }
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        // Use PowerSync's connection status - it handles network monitoring internally
        // Initial sync of status
        viewModel.isOnline = PowerSyncManager.shared.isConnected

        // Listen for PowerSync connection changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PowerSyncConnectionChanged"),
            object: nil,
            queue: .main
        ) { notification in
            if let isConnected = notification.userInfo?["isConnected"] as? Bool {
                self.viewModel.isOnline = isConnected
            }
        }
    }
    
    // MARK: - Conflict Handling
    // NOTE: PowerSync uses last-write-wins conflict resolution, so manual conflict handling is not needed.
    // This method is kept for backwards compatibility but will never trigger the conflict view.

    private func setupConflictHandling() {
        // PowerSync handles conflicts automatically with last-write-wins strategy
        // This notification handler is kept for backwards compatibility but won't be triggered
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SyncConflictsDetected"),
            object: nil,
            queue: .main
        ) { _ in
            // PowerSync handles conflicts automatically - this guard always returns
            guard false else { return }

            // Legacy conflict resolution view (never reached with PowerSync)
            DispatchQueue.main.async {
                let keyWindow = UIApplication.shared.connectedScenes
                    .filter { $0.activationState == .foregroundActive }
                    .compactMap { $0 as? UIWindowScene }
                    .first?.windows
                    .filter { $0.isKeyWindow }.first
                if let rootVC = keyWindow?.rootViewController {
                    let conflictView = ConflictResolutionView(
                        onComplete: { success in
                            if success {
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
                    .padding(.top, 60) // Add padding to avoid navigation bar
                }
                .animation(.spring(), value: isShowing)
            }
            .edgesIgnoringSafeArea(.horizontal)
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
            
            // Athlete count display
            HStack {
                let filteredRoster = filterRoster(viewModel.rosterEntries)
                let athleteCount = filteredRoster.filter { !$0.lastName.isEmpty }.count
                Text("Athletes: \(athleteCount)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            
            // List of roster entries
            List {
                // Sort roster based on current sort field and direction
                ForEach(Array(sortedRoster(filterRoster(viewModel.rosterEntries)).enumerated()), id: \.element.id) { index, entry in
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
            
            // Add athlete buttons
            HStack(spacing: 10) {
                Spacer()
                
                Button(action: {
                    viewModel.selectedRosterEntry = nil
                    viewModel.showingAddRosterEntry = true
                }) {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Add")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    viewModel.showingBatchAdd = true
                }) {
                    HStack {
                        Image(systemName: "person.3.fill")
                        Text("Batch")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
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
        let groupColor = colorForGroup(entry.groupName)
        
        // Determine font size based on group name length
        let fontSize: CGFloat
        if entry.groupName.count < 15 {
            fontSize = 20 // Larger font for short names
        } else if entry.groupName.count < 30 {
            fontSize = 12 // Medium font for medium names
        } else {
            fontSize = 10 // Smaller font for very long names
        }
        
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left side - Name and SubjectId (fixed width)
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
                .contentShape(Rectangle())  // Make entire area tappable
                .onTapGesture {
                    // Open edit view when tapping on name area
                    if !isLockedByOthers {
                        viewModel.selectedRosterEntry = entry
                        viewModel.showingAddRosterEntry = true
                    }
                }
                
                // This keeps the image centered by distributing space evenly
                Spacer(minLength: 20)
                    .contentShape(Rectangle())  // Make spacer area tappable
                    .onTapGesture {
                        // Open edit view when tapping in empty space
                        if !isLockedByOthers {
                            viewModel.selectedRosterEntry = entry
                            viewModel.showingAddRosterEntry = true
                        }
                    }
                
                // Center - Image input box
                if isCurrentlyEditing {
                    AutosaveTextField(
                        text: $viewModel.editingImageNumber,
                        placeholder: "Enter image numbers",
                        context: "\(entry.firstName) - \(entry.lastName)",
                        onTapOutside: {
                            // Just call the centralized save function
                            saveCurrentEditingEntry()
                        },
                        onEnterOrDown: {
                            // Save current entry before moving to next
                            saveCurrentEditingEntry()
                            // Find the next editable entry and start editing it
                            moveToNextEditableEntry(currentID: entry.id)
                        },
                        onEnterOrUp: {
                            // Save current entry before moving to previous
                            saveCurrentEditingEntry()
                            // Find the previous editable entry and start editing it
                            moveToPreviousEditableEntry(currentID: entry.id)
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
                    .buttonStyle(PlainButtonStyle())  // Prevents button from taking over entire tap area
                }
                
                // This keeps the image centered by distributing space evenly
                Spacer(minLength: 20)
                    .contentShape(Rectangle())  // Make spacer area tappable
                    .onTapGesture {
                        // Open edit view when tapping in empty space
                        if !isLockedByOthers {
                            viewModel.selectedRosterEntry = entry
                            viewModel.showingAddRosterEntry = true
                        }
                    }
                
                // Right side - Group/Team tag
                if !entry.groupName.isEmpty {
                    Text(entry.groupName)
                        .font(.system(size: fontSize)) // Dynamic font size
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(groupColor)
                        .cornerRadius(5)
                        .lineLimit(2) // 2 lines max
                        .fixedSize(horizontal: true, vertical: true) // Never truncate
                        .contentShape(Rectangle())  // Make entire area tappable
                        .onTapGesture {
                            // Open edit view when tapping on group tag
                            if !isLockedByOthers {
                                viewModel.selectedRosterEntry = entry
                                viewModel.showingAddRosterEntry = true
                            }
                        }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            
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
                    deleteRosterEntry(entryID: entry.id)
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
                ForEach(viewModel.groupImages) { group in
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
                                                    deleteGroupImage(groupID: group.id)
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
                            private func moveToNextEditableEntry(currentID: UUID) {
                                guard let shoot = viewModel.selectedShoot else { return }
                                
                                // Get the filtered and sorted roster as displayed in the list
                                let displayedRoster = sortedRoster(filterRoster(viewModel.rosterEntries))
                                
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
                            
                            // Function to move to the previous editable entry when pressing Up arrow
                            private func moveToPreviousEditableEntry(currentID: UUID) {
                                guard let shoot = viewModel.selectedShoot else { return }
                                
                                // Get the filtered and sorted roster as displayed in the list
                                let displayedRoster = sortedRoster(filterRoster(viewModel.rosterEntries))
                                
                                // Find the index of the current entry
                                guard let currentIndex = displayedRoster.firstIndex(where: { $0.id == currentID }) else {
                                    return
                                }
                                
                                // Try to find the previous entry that's not locked by others
                                for index in (0..<currentIndex).reversed() {
                                    let prevEntry = displayedRoster[index]
                                    let isLocked = viewModel.lockedEntries[prevEntry.id] != nil && viewModel.lockedEntries[prevEntry.id] != currentEditorIdentifier
                                    
                                    if !isLocked {
                                        // Release current lock
                                        if let currentEntryID = viewModel.currentlyEditingEntry {
                                            releaseLock(shootID: shoot.id, entryID: currentEntryID)
                                        }
                                        
                                        // Start editing the previous entry
                                        startEditing(shootID: shoot.id, entry: prevEntry)
                                        
                                        return
                                    }
                                }
                                
                                // If we reach here, we're at the first entry or all previous entries are locked
                                // Option 1: Loop back to the last entry
                                for index in (currentIndex + 1..<displayedRoster.count).reversed() {
                                    let prevEntry = displayedRoster[index]
                                    let isLocked = viewModel.lockedEntries[prevEntry.id] != nil && viewModel.lockedEntries[prevEntry.id] != currentEditorIdentifier
                                    
                                    if !isLocked {
                                        // Release current lock
                                        if let currentEntryID = viewModel.currentlyEditingEntry {
                                            releaseLock(shootID: shoot.id, entryID: currentEntryID)
                                        }
                                        
                                        // Start editing the entry
                                        startEditing(shootID: shoot.id, entry: prevEntry)
                                        
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
                                    case "groupName":
                                        result = a.groupName.lowercased() < b.groupName.lowercased()
                                    default:
                                        result = a.lastName.lowercased() < b.lastName.lowercased()
                                    }
                                    
                                    return viewModel.sortAscending ? result : !result
                                }
                            }
                            
                            // MARK: - Data Loading and Actions (Offline-First)

                            private func loadSportsShoots() {
                                print("[DEBUG] loadSportsShoots called, storedUserOrganizationID: '\(storedUserOrganizationID)'")
                                guard !storedUserOrganizationID.isEmpty else {
                                    print("[DEBUG] ERROR: storedUserOrganizationID is empty")
                                    viewModel.errorMessage = "No organization ID found. Please sign in again."
                                    viewModel.showingErrorAlert = true
                                    return
                                }

                                // PowerSync handles offline caching - start loading
                                viewModel.isLoading = true

                                // Then refresh from network (service handles caching)
                                Task {
                                    do {
                                        let shoots = try await SportsShootService.shared.fetchAllSportsShoots(forOrganization: storedUserOrganizationID)
                                        await MainActor.run {
                                            self.viewModel.isLoading = false
                                            print("[DEBUG] loadSportsShoots SUCCESS: received \(shoots.count) shoots from network")
                                            self.viewModel.sportsShoots = shoots
                                            print("[DEBUG] viewModel.sportsShoots count = \(self.viewModel.sportsShoots.count)")
                                            print("[DEBUG] viewModel.showArchived = \(self.viewModel.showArchived)")
                                            print("[DEBUG] viewModel.filteredSportsShoots count = \(self.viewModel.filteredSportsShoots.count)")

                                            // Check if we have a selected session from the widget
                                            self.checkForSelectedSession()
                                        }
                                    } catch {
                                        await MainActor.run {
                                            // If we already have cached data displayed, don't show error alert
                                            if !self.viewModel.sportsShoots.isEmpty {
                                                print("[DEBUG] loadSportsShoots: Network refresh failed, continuing with cached data")
                                            } else {
                                                self.viewModel.isLoading = false
                                                print("[DEBUG] loadSportsShoots FAILURE: \(error)")
                                                self.viewModel.errorMessage = "Failed to load sports shoots: \(error.localizedDescription)"
                                                self.viewModel.showingErrorAlert = true
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // MARK: - Session/Shoot Matching
                            
                            private func checkForSelectedSession() {
                                // First check if we have a direct sports shoot selection from the widget
                                if let selectedShoot = tabBarManager.selectedSportsShoot {
                                    defer { tabBarManager.selectedSportsShoot = nil }
                                    
                                    // Find the shoot in our list and select it
                                    if let match = viewModel.sportsShoots.first(where: { $0.id == selectedShoot.id }) {
                                        viewModel.selectedShoot = match
                                    } else {
                                        // If not in list, add it and select it
                                        viewModel.selectedShoot = selectedShoot
                                    }
                                    return
                                }
                                
                                // Fallback: Check if we have a selected session from elsewhere
                                guard let selectedSession = tabBarManager.selectedSportsSession else { return }
                                
                                // Clear the selected session after using it
                                defer { tabBarManager.selectedSportsSession = nil }
                                
                                // Try to find a matching sports shoot
                                let calendar = Calendar.current
                                
                                // Match by school name and date (ignoring time)
                                let matchingShoot = viewModel.sportsShoots.first { shoot in
                                    let schoolMatches = shoot.schoolName.lowercased() == selectedSession.schoolName.lowercased()
                                    
                                    // Compare dates without time
                                    if let sessionDate = selectedSession.startDate {
                                        let sessionDay = calendar.startOfDay(for: sessionDate)
                                        let shootDay = calendar.startOfDay(for: shoot.shootDate)
                                        let dateMatches = sessionDay == shootDay
                                        
                                        return schoolMatches && dateMatches
                                    }
                                    
                                    return false
                                }
                                
                                // If we found a match, select it
                                if let match = matchingShoot {
                                    viewModel.selectedShoot = match
                                } else {
                                }
                            }
                            
                            private func onShootUpdated(_ updatedShootID: UUID, entry: RosterEntry? = nil) {
                                // Only refresh if the updated shoot is the one currently displayed
                                if let currentShoot = viewModel.selectedShoot, currentShoot.id == updatedShootID {
                                    // If we received a specific entry update, apply it immediately
                                    if let updatedEntry = entry {
                                        // Find and replace the updated entry in the viewModel's roster
                                        if let index = viewModel.rosterEntries.firstIndex(where: { $0.id == updatedEntry.id }) {
                                            viewModel.rosterEntries[index] = updatedEntry
                                        }
                                    } else {
                                        // Otherwise refresh the entire shoot data
                                        refreshSelectedShoot()
                                    }
                                }
                            }
                            
                            private func refreshSelectedShoot() {
                                guard let currentShoot = viewModel.selectedShoot else { return }

                                // Load from PowerSync (offline-first - data is always available locally)
                                Task {
                                    do {
                                        // Load from PowerSync local database (instant, works offline)
                                        let entries = try await powerSync.getRosterEntries(forJob: currentShoot.id)
                                        let groups = try await powerSync.getGroupImages(forJob: currentShoot.id)

                                        await MainActor.run {
                                            self.viewModel.rosterEntries = entries
                                            self.viewModel.groupImages = groups
                                        }

                                        // Also try to refresh shoot info from network
                                        let updatedShoot = try await SportsShootService.shared.fetchSportsShoot(id: currentShoot.id)
                                        await MainActor.run {
                                            self.viewModel.selectedShoot = updatedShoot
                                            if let index = self.viewModel.sportsShoots.firstIndex(where: { $0.id == updatedShoot.id }) {
                                                self.viewModel.sportsShoots[index] = updatedShoot
                                            }
                                        }
                                    } catch {
                                        // PowerSync data is always available, network errors are expected offline
                                        print("SportsShootListView: Refresh using PowerSync local data")
                                    }
                                }
                            }
                            
                            private func deleteRosterEntry(entryID: UUID) {
                                guard let entry = viewModel.rosterEntries.first(where: { $0.id == entryID }) else { return }

                                // Remove from local state immediately
                                viewModel.rosterEntries.removeAll { $0.id == entryID }

                                // Delete from PowerSync (auto-syncs when online)
                                Task {
                                    do {
                                        try await powerSync.deleteRosterEntry(id: entry.id)
                                    } catch {
                                        print("SportsShootListView: Failed to delete entry: \(error)")
                                        // Restore on failure
                                        await MainActor.run {
                                            viewModel.rosterEntries.append(entry)
                                        }
                                    }
                                }
                            }
                            
                            private func deleteGroupImage(groupID: UUID) {
                                guard let group = viewModel.groupImages.first(where: { $0.id == groupID }) else { return }

                                // Remove from local state immediately
                                viewModel.groupImages.removeAll { $0.id == groupID }

                                // Delete from PowerSync (auto-syncs when online)
                                Task {
                                    do {
                                        try await powerSync.deleteGroupImage(id: group.id)
                                    } catch {
                                        print("SportsShootListView: Failed to delete group: \(error)")
                                        // Restore on failure
                                        await MainActor.run {
                                            viewModel.groupImages.append(group)
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
                                        let splitVC = Self.findSplitViewController(from: rootVC)
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
                            private static func findSplitViewController(from viewController: UIViewController) -> UISplitViewController? {
                                if let splitVC = viewController as? UISplitViewController {
                                    return splitVC
                                }
                                
                                for child in viewController.children {
                                    if let splitVC = Self.findSplitViewController(from: child) {
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
                            
                            // MARK: - iPad Roster Data Loading

                            /// Loads roster data for the selected shoot on iPad (offline-first via PowerSync)
                            /// iPhone uses SportsShootDetailView which handles this via loadSportsShoot()
                            private func loadRosterForSelectedShoot(shootID: UUID) async {
                                // Load from PowerSync local database (instant, works offline)
                                do {
                                    let entries = try await powerSync.getRosterEntries(forJob: shootID)
                                    let groups = try await powerSync.getGroupImages(forJob: shootID)

                                    await MainActor.run {
                                        viewModel.rosterEntries = entries
                                        viewModel.groupImages = groups
                                    }
                                } catch {
                                    print("SportsShootListView: Failed to load from PowerSync: \(error)")
                                }
                            }

                            // MARK: - Realtime Listeners

                            // Set up Supabase realtime listeners for real-time updates
                            private func setupRealtimeListeners() {
                                // Set up lock listener
                                setupLockListener()
                                
                                // Set up shoot data listener if we have a selected shoot
                                if let shootID = viewModel.selectedShoot?.id {
                                    setupShootListener(shootID: shootID)
                                }
                            }
                            
                            // Set up a real-time listener for shoot data changes
                            private func setupShootListener(shootID: UUID) {
                                // Remove any existing listener first
                                shootListener?.remove()
                                shootListener = nil


                                // Set up Supabase realtime subscription using realtimeV2
                                Task {
                                    let channelKey = "shoot_\(shootID)"
                                    let channel = supabase.realtimeV2.channel(channelKey)

                                    // Listen for changes to this specific sports job
                                    let changeStream = channel.postgresChange(
                                        AnyAction.self,
                                        schema: "public",
                                        table: "sports_jobs",
                                        filter: "id=eq.\(shootID)"
                                    )

                                    // Start listening for changes
                                    Task {
                                        for await _ in changeStream {
                                            // Refetch the shoot data when any change occurs
                                            await self.fetchAndUpdateShoot(shootID: shootID)
                                        }
                                    }

                                    await channel.subscribe()

                                    // Store wrapper for cleanup
                                    await MainActor.run {
                                        shootListener = ListenerRegistrationWrapper {
                                            Task {
                                                await channel.unsubscribe()
                                            }
                                        }
                                    }
                                }
                            }

                            // Helper to fetch and update shoot data
                            private func fetchAndUpdateShoot(shootID: UUID) async {
                                do {
                                    // Fetch the updated shoot and its data from Supabase
                                    let updatedShoot = try await SportsShootService.shared.fetchSportsShoot(id: shootID)
                                    let updatedEntries = try await RosterEntryService.shared.fetchEntries(forJob: shootID)
                                    let updatedGroups = try await GroupImageService.shared.fetchGroups(forJob: shootID)

                                    // Update individual roster entries without disrupting active editing
                                    await MainActor.run {
                                        var needsUpdate = false

                                        // Update roster entries that aren't currently being edited
                                        for updatedEntry in updatedEntries {
                                            // Skip if we're currently editing this entry
                                            if self.viewModel.currentlyEditingEntry == updatedEntry.id {
                                                continue
                                            }

                                            // Find and update the entry in our local roster
                                            if let index = self.viewModel.rosterEntries.firstIndex(where: { $0.id == updatedEntry.id }) {
                                                let currentImageNumbers = self.viewModel.rosterEntries[index].imageNumbers
                                                let updatedImageNumbers = updatedEntry.imageNumbers

                                                if currentImageNumbers != updatedImageNumbers {
                                                    self.viewModel.rosterEntries[index] = updatedEntry
                                                    needsUpdate = true
                                                }
                                            } else {
                                                // New entry, add it
                                                self.viewModel.rosterEntries.append(updatedEntry)
                                                needsUpdate = true
                                            }
                                        }

                                        // Also update group images
                                        if self.viewModel.groupImages != updatedGroups {
                                            self.viewModel.groupImages = updatedGroups
                                            needsUpdate = true
                                        }

                                        // Update shoot metadata
                                        self.viewModel.selectedShoot = updatedShoot
                                        if let listIndex = self.viewModel.sportsShoots.firstIndex(where: { $0.id == shootID }) {
                                            self.viewModel.sportsShoots[listIndex] = updatedShoot
                                        }

                                        // Force UI update if needed
                                        if needsUpdate {
                                            self.viewModel.objectWillChange.send()
                                        }
                                    }
                                } catch {
                                    // Silent failure - realtime updates are best-effort
                                }
                            }
                            
                            // Helper to check if we're currently editing
                            private func isCurrentlyEditing() -> Bool {
                                return viewModel.currentlyEditingEntry != nil
                            }
                            
                            // MARK: - Lock Management
                            
                            private func setupLockListener() {
                                guard let shootID = viewModel.selectedShoot?.id else { return }

                                // Set up realtime subscription to track roster entry locks with unique subscription ID
                                Task {
                                    await RosterEntryService.shared.subscribeToChanges(subscriptionId: subscriptionId, jobId: shootID) { [self] entries in
                                        // Extract locked entries from the realtime update
                                        var locks: [UUID: String] = [:]
                                        for entry in entries {
                                            if let lockedByName = entry.lockedByName, !lockedByName.isEmpty {
                                                locks[entry.id] = lockedByName
                                            }
                                        }
                                        self.viewModel.lockedEntries = locks

                                        // Protect currently editing entry from being overwritten
                                        if let editingId = self.viewModel.currentlyEditingEntry,
                                           let localEntry = self.viewModel.rosterEntries.first(where: { $0.id == editingId }) {
                                            var merged = entries
                                            if let index = merged.firstIndex(where: { $0.id == editingId }) {
                                                // Keep local editing state
                                                var preservedEntry = localEntry
                                                preservedEntry.imageNumbers = self.viewModel.editingImageNumber
                                                merged[index] = preservedEntry
                                            }
                                            self.viewModel.rosterEntries = merged
                                        } else {
                                            // Not editing - accept all server updates
                                            self.viewModel.rosterEntries = entries
                                        }
                                    }
                                }
                            }
                            
                            private func acquireLock(shootID: UUID, entryID: UUID) {
                                Task {
                                    let success = await LockManager.shared.acquireRosterEntryLock(entryId: entryID)
                                    if !success {
                                        await MainActor.run {
                                            self.viewModel.errorMessage = "This entry is being edited by someone else. Please try again later."
                                            self.viewModel.showingErrorAlert = true
                                        }
                                    }
                                }
                            }
                            
                            private func releaseLock(shootID: UUID, entryID: UUID) {
                                Task {
                                    await LockManager.shared.releaseRosterEntryLock(entryId: entryID)
                                    await MainActor.run {
                                        if self.viewModel.currentlyEditingEntry == entryID {
                                            // Save before clearing the editing state
                                            self.saveCurrentEditingEntry()
                                            self.viewModel.currentlyEditingEntry = nil
                                            self.viewModel.editingImageNumber = ""
                                        }
                                    }
                                }
                            }
                            
                            
                            // MARK: - Editing Functions
                            
                            // Save the current editing entry if it has changed
                            private func saveCurrentEditingEntry() {
                                // Check authentication first
                                guard UserManager.shared.getCurrentUserIDUnified() != nil else {
                                    viewModel.errorMessage = "You must be signed in to save changes"
                                    viewModel.showingErrorAlert = true
                                    return
                                }

                                guard let entryID = viewModel.currentlyEditingEntry,
                                      let currentEntry = viewModel.rosterEntries.first(where: { $0.id == entryID }),
                                      viewModel.editingImageNumber != currentEntry.imageNumbers else {
                                    return
                                }

                                var updatedEntry = currentEntry
                                updatedEntry.imageNumbers = viewModel.editingImageNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                                updatedEntry.version = currentEntry.version + 1
                                updatedEntry.updatedAt = Date()
                                updatedEntry.updatedBy = SupabaseManager.shared.client.auth.currentUser?.id

                                // Update local state immediately
                                if let index = viewModel.rosterEntries.firstIndex(where: { $0.id == entryID }) {
                                    viewModel.rosterEntries[index] = updatedEntry
                                }

                                // Save to PowerSync (auto-syncs when online)
                                Task {
                                    do {
                                        try await powerSync.saveRosterEntry(updatedEntry)
                                    } catch {
                                        print("SportsShootListView: Failed to save entry: \(error)")
                                    }
                                }
                            }
                            
                            private func startEditing(shootID: UUID, entry: RosterEntry) {
                                // Check if anyone else is editing this entry
                                if let editor = viewModel.lockedEntries[entry.id], !isOwnLock(entry.id) {
                                    // Entry is locked by someone else - show an alert
                                    viewModel.errorMessage = "This entry is currently being edited by \(editor)"
                                    viewModel.showingErrorAlert = true
                                    return
                                }

                                // Check if we already have a lock on this entry
                                if isOwnLock(entry.id) {
                                    // We already have the lock, just start editing without acquiring a new lock
                                    viewModel.currentlyEditingEntry = entry.id
                                    viewModel.editingImageNumber = entry.imageNumbers
                                    return
                                }

                                // Save and release any previous lock
                                if let previousEntryID = viewModel.currentlyEditingEntry {
                                    saveCurrentEditingEntry()
                                    releaseLock(shootID: shootID, entryID: previousEntryID)
                                }

                                // Set up editing state
                                viewModel.editingImageNumber = entry.imageNumbers
                                viewModel.currentlyEditingEntry = entry.id // Set synchronously to avoid placeholder showing

                                // Acquire lock for this entry
                                acquireLock(shootID: shootID, entryID: entry.id)
                            }
                        }

                        struct SportsShootListView_Previews: PreviewProvider {
                            static var previews: some View {
                                SportsShootListView()
                            }
                        }
