//
//  SportsShootDetailView.swift
//  Iconik Employee
//
//  Created for iPhone editing of sports shoots
//

import SwiftUI
import Firebase
import FirebaseFirestore
import Combine

struct SportsShootDetailView: View {
    let shootID: String
    
    // State management
    @State private var sportsShoot: SportsShoot?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var selectedTab = 0 // 0 = Athletes, 1 = Groups
    
    // Network status
    @State private var isOnline = true
    
    // States for roster management
    @State private var showingAddRosterEntry = false
    @State private var showingAddGroupImage = false
    @State private var selectedRosterEntry: RosterEntry?
    @State private var selectedGroupImage: GroupImage?
    
    // Sort states
    @State private var sortField: String = "firstName" // Default to sort by Subject ID
    @State private var sortAscending: Bool = true
    
    // Import/Export state
    @State private var showingImportExport = false
    @State private var showingMultiPhotoImport = false
    
    // Field editing state
    @State private var currentlyEditingEntry: String? = nil // ID of entry being edited
    @State private var editingImageNumber: String = ""
    @State private var lockedEntries: [String: String] = [:] // [entryID: editorName]
    
    // Filter states
    @State private var showFilterPanel = false
    @State private var selectedFilters: Set<String> = []
    @State private var selectedSpecialFilters: Set<String> = []
    @State private var imageFilterType: ImageFilterType = .all
    
    // Autosave states
    var debounceTask: DispatchWorkItem?
    var lastSavedValue: String = ""
    
    // Environment
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""
    
    // Device session ID - unique to this app instance
    private static let deviceSessionID = UUID().uuidString
    
    // Current user identifier combines name and device
    private var currentEditorIdentifier: String {
        return "\(storedUserFirstName) \(storedUserLastName) (\(Self.deviceSessionID.prefix(8)))"
    }
    
    // Focus state for keyboard navigation
    @FocusState private var focusedField: String?
    
    // Timer for refreshing locked entries
    let lockRefreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    // Filter options
    let specialFilters = ["Seniors", "8th Graders", "Coaches"]
    
    enum ImageFilterType {
        case all
        case hasImages
        case noImages
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let shoot = sportsShoot {
                    VStack(spacing: 0) {
                        // Header with shoot info
                        shootHeaderView(shoot)
                        
                        // Tab selector
                        tabSelectorView
                        
                        // Active filters indicator
                        if (!selectedFilters.isEmpty || !selectedSpecialFilters.isEmpty || imageFilterType != .all) && selectedTab == 0 {
                            activeFiltersView
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
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("Failed to Load")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        Text("Unable to load this sports shoot. Please try again.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            loadSportsShoot()
                        }
                        .padding(.top)
                        .foregroundColor(.blue)
                    }
                    .padding()
                }
                
                // Filter panel (slides out from right side)
                if selectedTab == 0 {
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
            }
            .navigationTitle(sportsShoot?.schoolName ?? "Sports Shoot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            showingMultiPhotoImport = true
                        }) {
                            Label("Import Paper Rosters", systemImage: "doc.viewfinder")
                        }
                        
                        Button(action: {
                            showingImportExport = true
                        }) {
                            Label("Import/Export CSV", systemImage: "square.and.arrow.up.on.square")
                        }
                        
                        if let shoot = sportsShoot {
                            if OfflineManager.shared.isShootCached(id: shoot.id) {
                                Button(action: {
                                    OfflineManager.shared.syncShoot(shootID: shoot.id)
                                }) {
                                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                }
                            } else {
                                Button(action: {
                                    cacheShootForOffline()
                                }) {
                                    Label("Make Available Offline", systemImage: "arrow.down.to.line")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Force stack style for iPhone
        .onAppear {
            loadSportsShoot()
            setupNetworkMonitoring()
            setupFirestoreListeners()
        }
        .onReceive(lockRefreshTimer) { _ in
            refreshLocks()
        }
        .onChange(of: editingImageNumber) { newValue in
            // Auto-save when the text changes
            if let entryID = currentlyEditingEntry,
               let shoot = sportsShoot,
               let entry = shoot.roster.first(where: { $0.id == entryID }),
               newValue != lastSavedValue {
                
                // Cancel any existing debounce task
                debounceTask?.cancel()
                
                // Create a new debounce task with a 0.5-second delay
                let task = DispatchWorkItem {
                    var updatedEntry = entry
                    updatedEntry.imageNumbers = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    SportsShootService.shared.updateRosterEntry(shootID: shoot.id, entry: updatedEntry) { result in
                        switch result {
                        case .success:
                            // Update the lastSavedValue to prevent redundant saves
                            self.lastSavedValue = newValue
                            
                            // Refresh the shoot data
                            self.refreshSportsShoot()
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
            if let shoot = sportsShoot {
                AddRosterEntryView(
                    shootID: shoot.id,
                    existingEntry: selectedRosterEntry,
                    onComplete: { success in
                        if success {
                            refreshSportsShoot()
                        }
                        selectedRosterEntry = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddGroupImage) {
            if let shoot = sportsShoot {
                AddGroupImageView(
                    shootID: shoot.id,
                    existingGroup: selectedGroupImage,
                    onComplete: { success in
                        if success {
                            refreshSportsShoot()
                        }
                        selectedGroupImage = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingImportExport) {
            if let shoot = sportsShoot {
                CSVImportExportView(
                    shootID: shoot.id,
                    onComplete: { success in
                        if success {
                            refreshSportsShoot()
                        }
                        showingImportExport = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingMultiPhotoImport) {
            if let shoot = sportsShoot {
                MultiPhotoRosterImporterView(
                    shootID: shoot.id,
                    onComplete: { success in
                        if success {
                            refreshSportsShoot()
                        }
                        showingMultiPhotoImport = false
                    }
                )
            }
        }
    }
    
    // MARK: - Header View
    
    private func shootHeaderView(_ shoot: SportsShoot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shoot.schoolName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text(shoot.sportName)
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        Spacer()
                        
                        // Sync status badge
                        SyncStatusBadge(shootID: shoot.id)
                            .font(.system(size: 16))
                        
                        // Connection status
                        CompactConnectionIndicator()
                    }
                }
            }
            
            HStack {
                if !shoot.location.isEmpty {
                    Label(shoot.location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(formatDate(shoot.shootDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !shoot.photographer.isEmpty {
                Label(shoot.photographer, systemImage: "person.crop.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Offline notification banner
            if !isOnline {
                HStack {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.orange)
                    
                    Text("You're offline - changes will sync when you reconnect")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    // MARK: - Tab Selector View
    
    private var tabSelectorView: some View {
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
            
            Spacer()
            
            // Filter button (only for Athletes tab)
            if selectedTab == 0 {
                Button(action: {
                    withAnimation {
                        showFilterPanel.toggle()
                    }
                }) {
                    Image(systemName: "line.horizontal.3.decrease.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Active Filters View
    
    private var activeFiltersView: some View {
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
    
    // MARK: - Roster List View
    
    private func rosterListView(_ shoot: SportsShoot) -> some View {
        VStack(spacing: 0) {
            // Column headers with sorting functionality
            HStack {
                sortableHeader("Name", field: "lastName")
                sortableHeader("ID", field: "firstName")
                sortableHeader("Special", field: "teacher")
                sortableHeader("Team", field: "group")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            
            // List of roster entries
            List {
                ForEach(Array(sortedRoster(filterRoster(shoot.roster)).enumerated()), id: \.element.id) { index, entry in
                    rosterEntryRow(shoot: shoot, entry: entry, isEven: index % 2 == 0)
                        .listRowInsets(EdgeInsets(
                            top: 4,
                            leading: 10,
                            bottom: 4,
                            trailing: 10
                        ))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(PlainListStyle())
            
            // Add athlete button
            Button(action: {
                selectedRosterEntry = nil
                showingAddRosterEntry = true
            }) {
                Label("Add Athlete", systemImage: "person.badge.plus")
                    .font(.headline)
                    .padding(.vertical, 12)
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
        let isOwnLock = isOwnLock(entry.id)
        let isLockedByOthers = lockedEntries[entry.id] != nil && !isOwnLock
        let isCurrentlyEditing = currentlyEditingEntry == entry.id
        let groupColor = colorForGroup(entry.group)
        
        return VStack(spacing: 0) {
            // Main content row
            VStack(spacing: 8) {
                // Top row - Name and ID
                HStack {
                    Button(action: {
                        if !isLockedByOthers {
                            selectedRosterEntry = entry
                            showingAddRosterEntry = true
                        }
                    }) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(entry.firstName)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.blue)
                                
                                if !entry.teacher.isEmpty {
                                    Text(specialTranslation(entry.teacher))
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Text(entry.lastName)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isLockedByOthers)
                    
                    Spacer()
                    
                    // Group/Team tag
                    if !entry.group.isEmpty {
                        Button(action: {
                            if !isLockedByOthers {
                                selectedRosterEntry = entry
                                showingAddRosterEntry = true
                            }
                        }) {
                            Text(entry.group)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(groupColor)
                                .cornerRadius(4)
                                .lineLimit(1)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isLockedByOthers)
                    }
                }
                
                // Bottom row - Image input
                if isCurrentlyEditing {
                    AutosaveTextField(
                        text: $editingImageNumber,
                        placeholder: "Enter image numbers",
                        onTapOutside: {
                            // Field autosaves on text change
                        }
                    )
                    .font(.system(size: 16))
                    .frame(height: 40)
                    .background(Color.blue.opacity(0.3))
                    .cornerRadius(6)
                } else if isLockedByOthers {
                    VStack(spacing: 2) {
                        Text(entry.imageNumbers.isEmpty ? "No images recorded" : entry.imageNumbers)
                            .font(.system(size: 14))
                            .foregroundColor(entry.imageNumbers.isEmpty ? .orange : .secondary)
                            .lineLimit(1)
                        
                        if let editor = lockedEntries[entry.id] {
                            Text("Editing: \(editor)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
                } else {
                    Button(action: {
                        startEditing(shootID: shoot.id, entry: entry)
                    }) {
                        Text(entry.imageNumbers.isEmpty ? "Tap to add image #" : entry.imageNumbers)
                            .font(.system(size: 16))
                            .fontWeight(.medium)
                            .frame(height: 40)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .background(isEven ? Color.blue.opacity(0.3) : Color.blue.opacity(0.4))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            
            Divider()
        }
        .background(
            isEven ?
                Color(.systemBackground) :
                Color(.systemGray6)
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
    
    // MARK: - Group Images List View
    
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
                                .foregroundColor(.primary)
                            
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
                // Background overlay
                Color.black.opacity(isShowing ? 0.3 : 0)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation {
                            isShowing = false
                        }
                    }
                
                // Filter panel
                HStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
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
                        .padding()
                        
                        Divider()
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // Special filters section
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Special Categories")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                        ForEach(specialFilters, id: \.self) { special in
                                            Button(action: {
                                                toggleSpecialFilter(special)
                                            }) {
                                                Text(special)
                                                    .font(.system(size: 14))
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(selectedSpecialFilters.contains(special) ? Color.purple : Color.gray.opacity(0.2))
                                                    .foregroundColor(selectedSpecialFilters.contains(special) ? .white : .primary)
                                                    .cornerRadius(8)
                                            }
                                        }
                                    }
                                }
                                
                                Divider()
                                
                                // Image filters section
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Image Status")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    HStack(spacing: 8) {
                                        Button(action: {
                                            imageFilterType = imageFilterType == .hasImages ? .all : .hasImages
                                        }) {
                                            Text("Has Images")
                                                .font(.system(size: 14))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(imageFilterType == .hasImages ? Color.green : Color.gray.opacity(0.2))
                                                .foregroundColor(imageFilterType == .hasImages ? .white : .primary)
                                                .cornerRadius(8)
                                        }
                                        
                                        Button(action: {
                                            imageFilterType = imageFilterType == .noImages ? .all : .noImages
                                        }) {
                                            Text("No Images")
                                                .font(.system(size: 14))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(imageFilterType == .noImages ? Color.green : Color.gray.opacity(0.2))
                                                .foregroundColor(imageFilterType == .noImages ? .white : .primary)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                
                                Divider()
                                
                                // Group filters section
                                VStack(alignment: .leading, spacing: 8) {
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
                                    
                                    if groupNames.isEmpty {
                                        Text("No groups available")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                                            ForEach(groupNames, id: \.self) { group in
                                                Button(action: {
                                                    toggleGroupFilter(group)
                                                }) {
                                                    HStack {
                                                        Text(group)
                                                            .font(.system(size: 14))
                                                            .foregroundColor(.white)
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 4)
                                                            .background(colorForGroup(group))
                                                            .cornerRadius(4)
                                                        
                                                        Spacer()
                                                        
                                                        if selectedFilters.contains(group) {
                                                            Image(systemName: "checkmark")
                                                                .foregroundColor(.blue)
                                                                .font(.system(size: 14, weight: .bold))
                                                        }
                                                    }
                                                    .padding(.vertical, 4)
                                                    .padding(.horizontal, 8)
                                                    .background(selectedFilters.contains(group) ? Color.gray.opacity(0.1) : Color.clear)
                                                    .cornerRadius(8)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        
                        // Clear all and done buttons
                        VStack(spacing: 8) {
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
                            }
                            
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
                        }
                        .padding()
                    }
                    .frame(width: min(UIScreen.main.bounds.width * 0.85, 320))
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: -5, y: 0)
                    .offset(x: isShowing ? 0 : 400)
                }
                .animation(.spring(), value: isShowing)
            }
            .opacity(isShowing ? 1 : 0)
        }
        
        private func toggleSpecialFilter(_ filter: String) {
            withAnimation {
                if selectedSpecialFilters.contains(filter) {
                    selectedSpecialFilters.remove(filter)
                } else {
                    selectedSpecialFilters.insert(filter)
                }
            }
        }
        
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
    
    // MARK: - Helper Functions
    
    private func loadSportsShoot() {
        isLoading = true
        
        SportsShootService.shared.fetchSportsShoot(id: shootID) { result in
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
    
    private func refreshSportsShoot() {
        SportsShootService.shared.fetchSportsShoot(id: shootID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updatedShoot):
                    self.sportsShoot = updatedShoot
                case .failure(let error):
                    self.errorMessage = "Failed to refresh: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func setupNetworkMonitoring() {
        let networkMonitor = NetworkMonitor.shared
        networkMonitor.startMonitoring { isConnected in
            DispatchQueue.main.async {
                self.isOnline = isConnected
            }
        }
    }
    
    private func setupFirestoreListeners() {
        setupLockListener()
    }
    
    private func setupLockListener() {
        EntryLockManager.shared.listenForLocks(shootID: shootID) { locks in
            DispatchQueue.main.async {
                self.lockedEntries = locks
            }
        }
    }
    
    private func refreshLocks() {
        EntryLockManager.shared.cleanupStaleLocks(shootID: shootID)
    }
    
    private func cacheShootForOffline() {
        SportsShootService.shared.cacheShootForOffline(id: shootID) { success in
            DispatchQueue.main.async {
                if success {
                    self.errorMessage = "This shoot is now available offline"
                } else {
                    self.errorMessage = "Failed to save for offline use. Please try again."
                }
                self.showingErrorAlert = true
            }
        }
    }
    
    // MARK: - Editing Functions
    
    private func isOwnLock(_ lockId: String) -> Bool {
        return lockedEntries[lockId] == currentEditorIdentifier
    }
    
    private func startEditing(shootID: String, entry: RosterEntry) {
        // Check if anyone else is editing this entry
        if let editor = lockedEntries[entry.id], !isOwnLock(entry.id) {
            errorMessage = "This entry is currently being edited by \(editor)"
            showingErrorAlert = true
            return
        }
        
        // Check if we already have a lock on this entry
        if isOwnLock(entry.id) {
            currentlyEditingEntry = entry.id
            editingImageNumber = entry.imageNumbers
            lastSavedValue = entry.imageNumbers
            return
        }
        
        // Release any previous lock
        if let previousEntryID = currentlyEditingEntry {
            releaseLock(shootID: shootID, entryID: previousEntryID)
        }
        
        // Set up editing state
        editingImageNumber = entry.imageNumbers
        lastSavedValue = entry.imageNumbers
        
        // Acquire lock for this entry
        acquireLock(shootID: shootID, entryID: entry.id)
    }
    
    private func acquireLock(shootID: String, entryID: String) {
        let editorID = Auth.auth().currentUser?.uid ?? UUID().uuidString
        let editorName = currentEditorIdentifier
        
        EntryLockManager.shared.acquireLock(shootID: shootID, entryID: entryID, editorID: editorID, editorName: editorName) { success in
            if success {
                DispatchQueue.main.async {
                    self.currentlyEditingEntry = entryID
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "This entry is being edited by someone else. Please try again later."
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func releaseLock(shootID: String, entryID: String) {
        let editorID = Auth.auth().currentUser?.uid ?? ""
        
        EntryLockManager.shared.releaseLock(shootID: shootID, entryID: entryID, editorID: editorID) { success in
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
    
    // MARK: - Delete Functions
    
    private func deleteRosterEntry(shoot: SportsShoot, id: String) {
        SportsShootService.shared.deleteRosterEntry(shootID: shoot.id, entryID: id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.refreshSportsShoot()
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
                    self.refreshSportsShoot()
                case .failure(let error):
                    self.errorMessage = "Failed to delete group: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    // MARK: - Utility Functions
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func specialTranslation(_ special: String) -> String {
        switch special.lowercased() {
        case "c": return "Coach"
        case "s": return "Senior"
        case "8": return "8th Grader"
        default: return special
        }
    }
    
    private func allGroupNames() -> [String] {
        guard let shoot = sportsShoot else { return [] }
        let allGroups = Set(shoot.roster.map { $0.group })
        return Array(allGroups).filter { !$0.isEmpty }.sorted()
    }
    
    private func filterRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
        var filteredRoster = roster
        
        // Apply group and special filters
        if !selectedFilters.isEmpty || !selectedSpecialFilters.isEmpty {
            filteredRoster = roster.filter { entry in
                let matchesGroup = selectedFilters.contains(entry.group)
                let matchesSpecial = (selectedSpecialFilters.contains("Seniors") && entry.teacher.lowercased() == "s") ||
                                    (selectedSpecialFilters.contains("8th Graders") && entry.teacher.lowercased() == "8") ||
                                    (selectedSpecialFilters.contains("Coaches") && entry.teacher.lowercased() == "c")
                
                if !selectedFilters.isEmpty && !selectedSpecialFilters.isEmpty {
                    return matchesGroup && matchesSpecial
                } else if !selectedFilters.isEmpty {
                    return matchesGroup
                } else {
                    return matchesSpecial
                }
            }
        }
        
        // Apply image filter
        switch imageFilterType {
        case .all:
            return filteredRoster
        case .hasImages:
            return filteredRoster.filter { !$0.imageNumbers.isEmpty }
        case .noImages:
            return filteredRoster.filter { $0.imageNumbers.isEmpty }
        }
    }
    
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
                    .font(.caption)
                    .lineLimit(1)
                
                Image(systemName: sortField == field
                      ? (sortAscending ? "chevron.up" : "chevron.down")
                      : "arrow.up.arrow.down")
                    .font(.system(size: 8))
                    .foregroundColor(sortField == field ? .blue : .gray)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(sortField == field ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            )
        }
    }
    
    private func colorForGroup(_ group: String) -> Color {
        if group.isEmpty {
            return Color.gray
        }
        
        let hash = abs(group.hashValue)
        let colors: [Color] = [
            Color.blue, Color.green, Color(red: 0.0, green: 0.6, blue: 0.4),
            Color.purple, Color.pink, Color.teal, Color.indigo, Color.red,
            Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.1, green: 0.6, blue: 0.4),
            Color(red: 0.8, green: 0.4, blue: 0.0), Color(red: 0.5, green: 0.1, blue: 0.7),
            Color(red: 0.9, green: 0.2, blue: 0.5)
        ]
        
        return colors[hash % colors.count]
    }
}

struct SportsShootDetailView_Previews: PreviewProvider {
    static var previews: some View {
        SportsShootDetailView(shootID: "preview-id")
    }
}