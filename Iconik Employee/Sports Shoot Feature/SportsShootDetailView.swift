//
//  SportsShootDetailView.swift
//  Iconik Employee
//
//  Created for iPhone editing of sports shoots
//  Updated for new Supabase-based architecture with realtime sync
//

import SwiftUI
import Combine

struct SportsShootDetailView: View {
    let shootID: UUID

    // State management - now uses separate state for shoot, roster, and groups
    @State private var sportsShoot: SportsShoot?
    @State private var rosterEntries: [RosterEntry] = []
    @State private var groupImages: [GroupImage] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var showingPermissionWarning = false
    @State private var selectedTab = 0 // 0 = Athletes, 1 = Groups

    // PowerSync for offline-first operations
    @StateObject private var powerSync = PowerSyncManager.shared
    @StateObject private var lockManager = LockManager.shared

    // Watch task handles for PowerSync streams
    @State private var rosterWatchTask: Task<Void, Never>?
    @State private var groupWatchTask: Task<Void, Never>?

    // States for roster management
    @State private var showingAddRosterEntry = false
    @State private var showingBatchAdd = false
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
    @State private var currentlyEditingEntryId: UUID? = nil
    @State private var editingValues: [UUID: String] = [:]
    @State private var lastSavedValues: [UUID: String] = [:]

    // Filter states
    @State private var showFilterPanel = false
    @State private var selectedFilters: Set<String> = []
    @State private var selectedSpecialFilters: Set<String> = []
    @State private var imageFilterType: ImageFilterType = .all

    // Autosave states
    @State private var debounceTask: DispatchWorkItem?

    // Sync notification
    @State private var showSyncNotification = false
    @State private var syncNotificationMessage = ""

    // Currently editing entry for protecting from overwrites
    @State private var currentlyEditingImageNumbers: String = ""

    // Environment
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""

    // Focus state for keyboard navigation
    @FocusState private var focusedField: UUID?

    // Current user identifier
    private var currentEditorName: String {
        return "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespaces)
    }

    // Filter options
    let specialFilters = ["Seniors", "8th Graders", "Coaches"]

    enum ImageFilterType {
        case all
        case hasImages
        case noImages
    }

    var body: some View {
        mainContentView
            .overlay(overlayViews)
            .navigationTitle(sportsShoot?.schoolName ?? "Sports Shoot")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar { toolbarContent }
            .task { await performInitialLoad() }
            .onDisappear { handleDisappear() }
            .onChange(of: scenePhase) { handleScenePhaseChange($0) }
            .onChange(of: editingValues) { handleEditingValueChange($0) }
            .alert(isPresented: $showingErrorAlert) { errorAlert }
            .sheet(isPresented: $showingAddRosterEntry) { addRosterEntrySheet }
            .sheet(isPresented: $showingBatchAdd) { batchAddSheet }
            .sheet(isPresented: $showingAddGroupImage) { addGroupImageSheet }
            .sheet(isPresented: $showingImportExport) { importExportSheet }
            .sheet(isPresented: $showingMultiPhotoImport) { multiPhotoImportSheet }
    }

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            leadingToolbarButton
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            trailingToolbarMenu
        }
    }

    @ViewBuilder
    private var leadingToolbarButton: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            Button(action: { toggleSidebar() }) {
                Image(systemName: "sidebar.left")
                    .foregroundColor(.blue)
            }
        }
    }

    private var trailingToolbarMenu: some View {
        Menu {
            Button(action: { showingMultiPhotoImport = true }) {
                Label("Import Paper Rosters", systemImage: "doc.viewfinder")
            }
            Button(action: { showingImportExport = true }) {
                Label("Import/Export CSV", systemImage: "square.and.arrow.up.on.square")
            }
            syncStatusButton
            connectionStatusLabel
        } label: {
            menuLabel
        }
    }

    @ViewBuilder
    private var syncStatusButton: some View {
        if powerSync.isSyncing {
            Button(action: { }) {
                Label("Syncing...", systemImage: "arrow.triangle.2.circlepath.circle.fill")
            }
            .disabled(true)
        }
    }

    @ViewBuilder
    private var syncButtonLabel: some View {
        if powerSync.isSyncing {
            Label("Syncing...", systemImage: "arrow.triangle.2.circlepath.circle.fill")
        } else {
            Label("Synced", systemImage: "checkmark.circle")
        }
    }

    @ViewBuilder
    private var connectionStatusLabel: some View {
        if powerSync.isConnected {
            Label("Online", systemImage: "wifi")
                .foregroundColor(.green)
        } else {
            Label("Offline", systemImage: "wifi.slash")
                .foregroundColor(.orange)
        }
    }

    private var menuLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "ellipsis.circle")
            if powerSync.isSyncing {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .offset(x: 4, y: -4)
            }
        }
    }

    // MARK: - Lifecycle Handlers

    private func performInitialLoad() async {
        // Set current user for lock manager
        if let userId = SupabaseManager.shared.client.auth.currentUser?.id {
            LockManager.shared.setCurrentUser(
                userId: userId,
                userName: "\(storedUserFirstName) \(storedUserLastName)"
            )
        }

        await loadSportsShoot()
        setupPowerSyncWatchers()
    }

    private func handleDisappear() {
        // Cancel PowerSync watch tasks
        rosterWatchTask?.cancel()
        groupWatchTask?.cancel()
        rosterWatchTask = nil
        groupWatchTask = nil

        // Release any locks
        Task {
            if let entryId = currentlyEditingEntryId {
                await lockManager.releaseRosterEntryLock(entryId: entryId)
            }
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .background || newPhase == .inactive {
            lockManager.handleAppBackground()
        } else if newPhase == .active {
            lockManager.handleAppForeground()
        }
    }

    // MARK: - Alert and Sheet Views

    private var errorAlert: Alert {
        Alert(
            title: Text("Error"),
            message: Text(errorMessage),
            dismissButton: .default(Text("OK"))
        )
    }

    private var addRosterEntrySheet: some View {
        AddRosterEntryView(
            shootID: shootID,
            existingEntry: selectedRosterEntry,
            onComplete: { success in
                if success { Task { await refreshRosterEntries() } }
                selectedRosterEntry = nil
            }
        )
    }

    private var batchAddSheet: some View {
        BatchAddAthletesView(
            shootID: shootID,
            onComplete: { success in
                if success { Task { await refreshRosterEntries() } }
            }
        )
    }

    private var addGroupImageSheet: some View {
        AddGroupImageView(
            shootID: shootID,
            existingGroup: selectedGroupImage,
            onComplete: { success in
                if success { Task { await refreshGroupImages() } }
                selectedGroupImage = nil
            }
        )
    }

    private var importExportSheet: some View {
        CSVImportExportView(
            shootID: shootID,
            onComplete: { success in
                if success { Task { await refreshRosterEntries() } }
                showingImportExport = false
            }
        )
    }

    private var multiPhotoImportSheet: some View {
        MultiPhotoRosterImporterView(
            shootID: shootID,
            onComplete: { success in
                if success { Task { await refreshRosterEntries() } }
                showingMultiPhotoImport = false
            }
        )
    }

    // MARK: - Extracted Body Components

    @ViewBuilder
    private var mainContentView: some View {
        ZStack {
            if isLoading {
                loadingView
            } else if let shoot = sportsShoot {
                shootContentView(shoot)
            } else {
                failedToLoadView
            }
        }
    }

    private var loadingView: some View {
        ProgressView("Loading...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shootContentView(_ shoot: SportsShoot) -> some View {
        VStack(spacing: 0) {
            compactHeaderView(shoot)
            tabSelectorView
            if shouldShowFiltersIndicator {
                activeFiltersView
            }
            if selectedTab == 0 {
                rosterListView(shoot)
            } else {
                groupImagesListView(shoot)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var shouldShowFiltersIndicator: Bool {
        (!selectedFilters.isEmpty || !selectedSpecialFilters.isEmpty || imageFilterType != .all) && selectedTab == 0
    }

    private var failedToLoadView: some View {
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
                Task { await loadSportsShoot() }
            }
            .padding(.top)
            .foregroundColor(.blue)
        }
        .padding()
    }

    @ViewBuilder
    private var overlayViews: some View {
        ZStack {
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

            if showSyncNotification {
                syncNotificationView
            }
        }
    }

    private var syncNotificationView: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(syncNotificationMessage)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(10)
            .padding(.bottom, 50)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(), value: showSyncNotification)
    }

    // MARK: - Compact Header View

    private func compactHeaderView(_ shoot: SportsShoot) -> some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shoot.sportName)
                        .font(.headline)
                        .foregroundColor(.blue)

                    HStack(spacing: 8) {
                        if !shoot.location.isEmpty {
                            Text(shoot.location)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(formatDate(shoot.shootDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Status indicators
                HStack(spacing: 8) {
                    // Sync status indicator
                    if powerSync.isSyncing {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    // Connection indicator
                    Image(systemName: powerSync.isConnected ? "wifi" : "wifi.slash")
                        .font(.system(size: 14))
                        .foregroundColor(powerSync.isConnected ? .green : .orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Offline notification banner
            if !powerSync.isConnected {
                HStack {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("Offline - changes will sync when you reconnect")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Tab Selector View

    private var tabSelectorView: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                Text("Athletes (\(rosterEntries.count))").tag(0)
                Text("Groups (\(groupImages.count))").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedTab) { newValue in
                if newValue == 1 {
                    withAnimation { showFilterPanel = false }
                }
            }

            Spacer()

            if selectedTab == 0 {
                Button(action: {
                    withAnimation { showFilterPanel.toggle() }
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

                    ForEach(Array(selectedSpecialFilters), id: \.self) { special in
                        Text(special)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }

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
            // Column headers with sorting
            HStack {
                sortableHeader("Name", field: "lastName")
                sortableHeader("ID", field: "firstName")
                sortableHeader("Special", field: "teacher")
                sortableHeader("Team", field: "groupName")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))

            // Athlete count
            HStack {
                let filteredRoster = filterRoster(rosterEntries)
                let athleteCount = filteredRoster.filter { !$0.lastName.isEmpty }.count
                Text("Athletes: \(athleteCount)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                Spacer()
            }
            .background(Color(.systemGroupedBackground))

            // Roster list
            List {
                ForEach(Array(sortedRoster(filterRoster(rosterEntries)).enumerated()), id: \.element.id) { index, entry in
                    rosterEntryRow(entry: entry, isEven: index % 2 == 0)
                        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(PlainListStyle())

            // Add athlete buttons
            HStack(spacing: 10) {
                Spacer()

                Button(action: {
                    selectedRosterEntry = nil
                    showingAddRosterEntry = true
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

                Button(action: { showingBatchAdd = true }) {
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

    private func rosterEntryRow(entry: RosterEntry, isEven: Bool) -> some View {
        let isCurrentlyEditing = currentlyEditingEntryId == entry.id
        let isLockedByOther = entry.isLocked && entry.lockedBy != lockManager.currentUserId
        let groupColor = colorForGroup(entry.groupName)

        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                // Player info row
                HStack(alignment: .top) {
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
                            .lineLimit(2)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    if !entry.groupName.isEmpty {
                        Text(entry.groupName)
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(groupColor)
                            .cornerRadius(4)
                            .lineLimit(2)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedRosterEntry = entry
                    showingAddRosterEntry = true
                }

                // Image input row
                if isCurrentlyEditing {
                    HStack(spacing: 8) {
                        AutosaveTextField(
                            text: Binding(
                                get: { editingValues[entry.id] ?? entry.imageNumbers },
                                set: { editingValues[entry.id] = $0 }
                            ),
                            placeholder: "",
                            onTapOutside: { },
                            onEnterOrDown: {
                                moveToNextEditableEntry(currentID: entry.id)
                            }
                        )
                        .font(.system(size: 16))
                        .frame(height: 40)
                        .background(Color.blue.opacity(0.3))
                        .cornerRadius(6)

                        Button(action: {
                            Task {
                                await stopEditing(entryId: entry.id)
                            }
                        }) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                        }
                    }
                } else if isLockedByOther {
                    VStack(spacing: 2) {
                        Text(entry.imageNumbers.isEmpty ? "No images recorded" : entry.imageNumbers)
                            .font(.system(size: 14))
                            .foregroundColor(entry.imageNumbers.isEmpty ? .orange : .secondary)
                            .lineLimit(1)

                        if let editorName = entry.lockedByName {
                            Text("Editing: \(editorName)")
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
                        Task {
                            await startEditing(entry: entry)
                        }
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
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)

            Divider()
        }
        .background(isEven ? Color(.systemBackground) : Color(.systemGray6))
        .overlay(isLockedByOther ? Color.red.opacity(0.05) : Color.clear)
        .contextMenu {
            if !isLockedByOther {
                Button(action: {
                    selectedRosterEntry = entry
                    showingAddRosterEntry = true
                }) {
                    Label("Edit", systemImage: "pencil")
                }

                Button(action: {
                    Task { await startEditing(entry: entry) }
                }) {
                    Label("Edit Image Numbers", systemImage: "camera")
                }

                Button(role: .destructive, action: {
                    Task { await deleteRosterEntry(entry) }
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
                ForEach(groupImages) { group in
                    Button(action: {
                        selectedGroupImage = group
                        showingAddGroupImage = true
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.description)
                                .font(.headline)
                                .foregroundColor(.primary)

                            if !group.imageNumbers.isEmpty {
                                Label("Images: \(group.imageNumbers)", systemImage: "camera")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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

                            // Lock indicator
                            if group.isLocked, let editorName = group.lockedByName {
                                Text("Editing: \(editorName)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        if !group.isLocked || group.lockedBy == lockManager.currentUserId {
                            Button(action: {
                                selectedGroupImage = group
                                showingAddGroupImage = true
                            }) {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button(role: .destructive, action: {
                                Task { await deleteGroupImage(group) }
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
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
                Color.black.opacity(isShowing ? 0.3 : 0)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation { isShowing = false }
                    }

                HStack {
                    Spacer()

                    VStack(spacing: 0) {
                        HStack {
                            Text("Filter Athletes")
                                .font(.headline)

                            Spacer()

                            Button(action: {
                                withAnimation { isShowing = false }
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
                                // Special filters
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Special Categories")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                        ForEach(specialFilters, id: \.self) { special in
                                            Button(action: { toggleSpecialFilter(special) }) {
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

                                // Image filters
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

                                // Group filters
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Sport/Team")
                                            .font(.subheadline)
                                            .fontWeight(.medium)

                                        Spacer()

                                        if !selectedFilters.isEmpty {
                                            Button(action: {
                                                withAnimation { selectedFilters.removeAll() }
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
                                                Button(action: { toggleGroupFilter(group) }) {
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
                                withAnimation { isShowing = false }
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

    // MARK: - Data Loading (Offline-First via PowerSync)

    private func loadSportsShoot() async {
        do {
            // Fetch shoot info from SportsShootService (still needed for initial load)
            let shoot = try await SportsShootService.shared.fetchSportsShoot(id: shootID)
            self.sportsShoot = shoot

            // Load roster and groups from PowerSync local DB (instant, works offline)
            self.rosterEntries = try await powerSync.getRosterEntries(forJob: shootID)
            self.groupImages = try await powerSync.getGroupImages(forJob: shootID)

            isLoading = false
            print("SportsShootDetailView: Loaded from PowerSync")
        } catch {
            isLoading = false
            errorMessage = "Failed to load: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func refreshRosterEntries() async {
        // PowerSync watchers auto-update, but we can also manually refresh
        do {
            rosterEntries = try await powerSync.getRosterEntries(forJob: shootID)
        } catch {
            print("Failed to refresh roster: \(error)")
        }
    }

    private func refreshGroupImages() async {
        do {
            groupImages = try await powerSync.getGroupImages(forJob: shootID)
        } catch {
            print("Failed to refresh groups: \(error)")
        }
    }

    /// Set up PowerSync watch streams for real-time updates
    private func setupPowerSyncWatchers() {
        // Cancel any existing watchers
        rosterWatchTask?.cancel()
        groupWatchTask?.cancel()

        // Watch roster entries
        rosterWatchTask = Task {
            do {
                for try await entries in powerSync.watchRosterEntries(forJob: shootID) {
                    // Protect currently editing entry from being overwritten
                    if let editingId = currentlyEditingEntryId,
                       let localEntry = rosterEntries.first(where: { $0.id == editingId }) {
                        var merged = entries
                        if let index = merged.firstIndex(where: { $0.id == editingId }) {
                            // Keep local editing state
                            var preservedEntry = localEntry
                            preservedEntry.imageNumbers = editingValues[editingId] ?? localEntry.imageNumbers
                            merged[index] = preservedEntry
                        }
                        self.rosterEntries = merged
                    } else {
                        self.rosterEntries = entries
                    }
                }
            } catch {
                print("SportsShootDetailView: Roster watch error: \(error)")
            }
        }

        // Watch group images
        groupWatchTask = Task {
            do {
                for try await groups in powerSync.watchGroupImages(forJob: shootID) {
                    self.groupImages = groups
                }
            } catch {
                print("SportsShootDetailView: Groups watch error: \(error)")
            }
        }
    }

    // MARK: - Editing Functions

    private func startEditing(entry: RosterEntry) async {
        // Check if locked by someone else
        if entry.isLocked && entry.lockedBy != lockManager.currentUserId {
            errorMessage = "This entry is being edited by \(entry.lockedByName ?? "another user")"
            showingErrorAlert = true
            return
        }

        // Release previous lock if any
        if let previousId = currentlyEditingEntryId, previousId != entry.id {
            await lockManager.releaseRosterEntryLock(entryId: previousId)
        }

        // Acquire lock
        let acquired = await lockManager.acquireRosterEntryLock(entryId: entry.id)

        if acquired {
            currentlyEditingEntryId = entry.id
            editingValues[entry.id] = entry.imageNumbers
            lastSavedValues[entry.id] = entry.imageNumbers
        } else {
            errorMessage = "Could not acquire lock. Please try again."
            showingErrorAlert = true
        }
    }

    private func stopEditing(entryId: UUID) async {
        // Cancel debounce first
        debounceTask?.cancel()

        // ALWAYS save if there's a value - prevents data loss when switching fields quickly
        if let newValue = editingValues[entryId] {
            await saveEntry(entryId: entryId, imageNumbers: newValue)
        }

        // Clean up state
        editingValues.removeValue(forKey: entryId)
        lastSavedValues.removeValue(forKey: entryId)
        currentlyEditingEntryId = nil
    }

    private func handleEditingValueChange(_ newValues: [UUID: String]) {
        guard let entryId = currentlyEditingEntryId,
              let newValue = newValues[entryId],
              newValue != lastSavedValues[entryId] else { return }

        // Cancel any existing debounce task
        debounceTask?.cancel()

        // Create a new debounce task
        let task = DispatchWorkItem { [self] in
            Task {
                await saveEntry(entryId: entryId, imageNumbers: newValue)
                await MainActor.run {
                    lastSavedValues[entryId] = newValue
                }
            }
        }

        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    private func saveEntry(entryId: UUID, imageNumbers: String) async {
        guard var entry = rosterEntries.first(where: { $0.id == entryId }) else { return }

        entry.imageNumbers = imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.updatedAt = Date()
        entry.updatedBy = SupabaseManager.shared.client.auth.currentUser?.id

        // Update local state immediately
        if let index = rosterEntries.firstIndex(where: { $0.id == entryId }) {
            rosterEntries[index] = entry
        }

        // Save to PowerSync (auto-syncs when online)
        do {
            try await powerSync.saveRosterEntry(entry)
        } catch {
            print("SportsShootDetailView: Failed to save entry: \(error)")
        }
    }

    private func moveToNextEditableEntry(currentID: UUID) {
        let displayedRoster = sortedRoster(filterRoster(rosterEntries))

        guard let currentIndex = displayedRoster.firstIndex(where: { $0.id == currentID }) else { return }

        // Find next unlocked entry
        for index in (currentIndex + 1)..<displayedRoster.count {
            let nextEntry = displayedRoster[index]
            if !nextEntry.isLocked || nextEntry.lockedBy == lockManager.currentUserId {
                Task {
                    await stopEditing(entryId: currentID)
                    await startEditing(entry: nextEntry)
                }
                return
            }
        }

        // Wrap around to beginning
        for index in 0..<currentIndex {
            let nextEntry = displayedRoster[index]
            if !nextEntry.isLocked || nextEntry.lockedBy == lockManager.currentUserId {
                Task {
                    await stopEditing(entryId: currentID)
                    await startEditing(entry: nextEntry)
                }
                return
            }
        }

        // No other entries available, just stop editing
        Task {
            await stopEditing(entryId: currentID)
        }
    }

    // MARK: - Delete Functions

    private func deleteRosterEntry(_ entry: RosterEntry) async {
        // Remove from local state immediately
        rosterEntries.removeAll { $0.id == entry.id }

        // Delete from PowerSync (auto-syncs when online)
        do {
            try await powerSync.deleteRosterEntry(id: entry.id)
        } catch {
            print("SportsShootDetailView: Failed to delete entry: \(error)")
            // Restore on failure
            rosterEntries.append(entry)
        }
    }

    private func deleteGroupImage(_ group: GroupImage) async {
        // Remove from local state immediately
        groupImages.removeAll { $0.id == group.id }

        // Delete from PowerSync (auto-syncs when online)
        do {
            try await powerSync.deleteGroupImage(id: group.id)
        } catch {
            print("SportsShootDetailView: Failed to delete group: \(error)")
            // Restore on failure
            groupImages.append(group)
        }
    }

    // MARK: - Helper Functions

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func toggleSidebar() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            findAndToggleSplitView(from: rootVC)
        }
    }

    private func findAndToggleSplitView(from viewController: UIViewController) {
        if let splitVC = viewController as? UISplitViewController {
            if splitVC.preferredDisplayMode == .oneBesideSecondary || splitVC.preferredDisplayMode == .automatic {
                splitVC.preferredDisplayMode = .secondaryOnly
            } else {
                splitVC.preferredDisplayMode = .oneBesideSecondary
            }
            return
        }

        for child in viewController.children {
            findAndToggleSplitView(from: child)
        }
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
        let allGroups = Set(rosterEntries.map { $0.groupName })
        return Array(allGroups).filter { !$0.isEmpty }.sorted()
    }

    private func filterRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
        var filteredRoster = roster

        if !selectedFilters.isEmpty || !selectedSpecialFilters.isEmpty {
            filteredRoster = roster.filter { entry in
                let matchesGroup = selectedFilters.contains(entry.groupName)
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
            case "groupName":
                result = a.groupName.lowercased() < b.groupName.lowercased()
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
        if group.isEmpty { return Color.gray }

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
        SportsShootDetailView(shootID: UUID())
    }
}
