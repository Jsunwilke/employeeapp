//
//  SportsShootDetailView.swift
//  Iconik Employee
//
//  Created for iPhone editing of sports shoots
//  Updated for new Supabase-based architecture with realtime sync
//

import SwiftUI
import Combine
import UIKit

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

    @State private var showingKiosk = false

    // Multipeer connectivity for kiosk sync
    @StateObject private var multipeerSync = MultipeerRosterSync()
    @State private var showingConnectionDetails = false

    // Focal Point Production sync (iPad ↔ Surface Pro)
    @StateObject private var fpSync = FocalPointSyncClient.shared
    @State private var showingFPSyncSheet = false

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
    @State private var syncNotificationIsConflict = false

    // Lock-lost warning
    @State private var showLockLostWarning = false
    @State private var lockLostMessage = ""

    // Currently editing entry for protecting from overwrites
    @State private var currentlyEditingImageNumbers: String = ""

    // Track deleted IDs so watcher protection doesn't resurrect them
    @State private var recentlyDeletedEntryIds: Set<UUID> = []
    @State private var recentlyDeletedGroupIds: Set<UUID> = []

    // Track previous connectivity for offline→online transition detection
    @State private var wasConnected: Bool = true

    // Search
    @State private var searchText: String = ""

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
            .task {
                // Start browsing for kiosk registration stations
                multipeerSync.startBrowsing(jobId: shootID)
                print("SportsShootDetailView: Started browsing for kiosks for shoot \(shootID)")
            }
            .task {
                // Set up Focal Point Production sync callbacks
                setupFPSyncCallbacks()
            }
            .onDisappear { handleDisappear() }
            .onChange(of: scenePhase) { handleScenePhaseChange($0) }
            .onChange(of: editingValues) { handleEditingValueChange($0) }
            .onChange(of: lockManager.lockLostEvent?.id) { _ in handleLockLostEvent() }
            .onChange(of: powerSync.isConnected) { isConnected in
                // Detect offline → online transition
                if !wasConnected && isConnected {
                    Task { await lockManager.handleNetworkReconnection() }
                    // If PowerSync connected after the view first appeared (slow first sync),
                    // the initial load may have returned empty local SQLite — reload now
                    if rosterEntries.isEmpty || groupImages.isEmpty {
                        Task { await loadSportsShoot() }
                    }
                }
                wasConnected = isConnected
            }
            .alert(isPresented: $showingErrorAlert) { errorAlert }
            .sheet(isPresented: $showingAddRosterEntry) { addRosterEntrySheet }
            .sheet(isPresented: $showingBatchAdd) { batchAddSheet }
            .sheet(isPresented: $showingAddGroupImage) { addGroupImageSheet }
            .sheet(isPresented: $showingImportExport) { importExportSheet }
            .sheet(isPresented: $showingMultiPhotoImport) { multiPhotoImportSheet }
            .sheet(isPresented: $showingFPSyncSheet) { fpSyncSheet }
            .sheet(isPresented: $showingKiosk) {
                KioskLaunchView(
                    sportsJobId: shootID,
                    organizationId: sportsShoot?.organizationId ?? "",
                    schoolName: sportsShoot?.schoolName ?? ""
                )
            }
            .onChange(of: showingKiosk) { isShowingKiosk in
                // Stop browsing when kiosk opens, resume when it closes
                if isShowingKiosk {
                    multipeerSync.stopBrowsing()
                    print("SportsShootDetailView: Stopped browsing (kiosk opened)")
                } else {
                    multipeerSync.startBrowsing(jobId: shootID)
                    print("SportsShootDetailView: Resumed browsing (kiosk closed)")
                }
            }
            .sheet(isPresented: $showingConnectionDetails) {
                connectionDetailsSheet
            }
    }

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            leadingToolbarButton
        }

        // iPad: Show buttons directly in toolbar
        if UIDevice.current.userInterfaceIdiom == .pad {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingKiosk = true }) {
                    Label("Start Kiosk", systemImage: "person.2.fill")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                fpSyncToolbarButton
            }
        } else {
            // iPhone: Show menu button
            ToolbarItem(placement: .navigationBarTrailing) {
                trailingToolbarMenu
            }
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
            Button(action: { showingKiosk = true }) {
                Label("Start Kiosk", systemImage: "person.2.fill")
            }

            Divider()

            Button(action: {
                if fpSync.isConnected {
                    showingFPSyncSheet = true
                } else {
                    guard let shoot = sportsShoot, shoot.galleryId != nil else {
                        errorMessage = "This sports job isn't linked to a Production gallery yet. Sync it from Focal Point Production first."
                        showingErrorAlert = true
                        return
                    }
                    showingFPSyncSheet = true
                }
            }) {
                Label(fpSync.isConnected ? "Production Sync (Connected)" : "Production Sync",
                      systemImage: fpSync.isConnected ? "bolt.fill" : "bolt.slash")
            }

            Divider()

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

    // MARK: - Focal Point Production Sync UI

    @ViewBuilder
    private var fpSyncToolbarButton: some View {
        Button(action: {
            if fpSync.isConnected {
                showingFPSyncSheet = true
            } else {
                // Can only connect if gallery is linked
                guard let shoot = sportsShoot, shoot.galleryId != nil else {
                    errorMessage = "This sports job isn't linked to a Production gallery yet. Link it in Focal Point Production first."
                    showingErrorAlert = true
                    return
                }
                showingFPSyncSheet = true
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: fpSync.isConnected ? "bolt.fill" : "bolt.slash")
                    .foregroundColor(fpSync.isConnected ? .green : .secondary)
                if fpSync.isConnected {
                    Text("Synced")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }

    @ViewBuilder
    private var fpSyncSheet: some View {
        NavigationView {
            List {
                // Connection section
                Section("Production Sync") {
                    if fpSync.isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)

                        if let paired = fpSync.pairedCameraId,
                           let camera = fpSync.devices.first(where: { $0.id == paired }) {
                            Label("Paired: \(camera.name)", systemImage: "camera.fill")
                        }

                        Button(role: .destructive) {
                            fpSync.disconnect()
                            showingFPSyncSheet = false
                        } label: {
                            Label("Disconnect", systemImage: "wifi.slash")
                        }
                    } else {
                        Button {
                            guard let shoot = sportsShoot, let galleryId = shoot.galleryId else { return }
                            fpSync.startDiscovery(galleryId: galleryId)
                        } label: {
                            Label("Connect to Production", systemImage: "wifi")
                        }
                        .disabled(sportsShoot?.galleryId == nil)

                        if fpSync.connectionStatus == .discovering {
                            HStack {
                                ProgressView()
                                Text("Scanning for server...")
                                    .foregroundColor(.secondary)
                            }
                        }

                        if fpSync.connectionStatus == .authFailed {
                            Label("Authentication failed — check PIN", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                        }
                    }
                }

                // Device pairing section (when connected)
                if fpSync.isConnected && fpSync.cameraDevices.count > 1 {
                    Section("Camera Pairing") {
                        ForEach(fpSync.cameraDevices) { device in
                            Button {
                                fpSync.pairWithCamera(deviceId: device.id)
                            } label: {
                                HStack {
                                    Label(device.name, systemImage: "camera")
                                    Spacer()
                                    if device.id == fpSync.pairedCameraId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                // Connected devices
                if fpSync.isConnected && !fpSync.devices.isEmpty {
                    Section("Connected Devices") {
                        ForEach(fpSync.devices) { device in
                            HStack {
                                Image(systemName: device.stationMode == "camera" ? "camera" : (device.stationMode == "ios_roster" ? "ipad" : "desktopcomputer"))
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                        .font(.body)
                                    Text(Self.formatStationMode(device.stationMode))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if device.captureCount > 0 {
                                    Text("\(device.captureCount) photos")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Production Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingFPSyncSheet = false }
                }
            }
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
        // Cancel debounce first to prevent it from firing on destroyed state
        debounceTask?.cancel()
        debounceTask = nil

        // Cancel PowerSync watch tasks
        rosterWatchTask?.cancel()
        groupWatchTask?.cancel()
        rosterWatchTask = nil
        groupWatchTask = nil

        // Dismiss keyboard and save any pending edits
        dismissKeyboard()
        Task {
            if let entryId = currentlyEditingEntryId {
                await stopEditing(entryId: entryId)
                await lockManager.releaseRosterEntryLock(entryId: entryId)
            }
        }

        // Stop browsing for kiosks
        multipeerSync.disconnect()
        print("SportsShootDetailView: Stopped browsing for kiosks")

        // Clear callback to prevent stale state mutations after view disappears
        fpSync.onCaptureCompleted = nil
    }

    // MARK: - Focal Point Production Sync

    private func setupFPSyncCallbacks() {
        // When camera station captures a photo, auto-fill image numbers on this roster entry
        fpSync.onCaptureCompleted = { [self] event in
            guard let rosterEntryId = event.rosterEntryId,
                  let imageNumber = event.imageNumber else { return }

            // Find the roster entry
            if let idx = rosterEntries.firstIndex(where: { $0.id.uuidString.lowercased() == rosterEntryId.lowercased() }) {
                let entryId = rosterEntries[idx].id
                // Skip auto-fill if user is currently editing this entry's image numbers
                if currentlyEditingEntryId == entryId { return }

                var entry = rosterEntries[idx]
                // Append image number to existing comma-separated list
                let existing = entry.imageNumbers.trimmingCharacters(in: .whitespaces)
                if existing.isEmpty {
                    entry.imageNumbers = "\(imageNumber)"
                } else {
                    entry.imageNumbers = "\(existing), \(imageNumber)"
                }
                rosterEntries[idx] = entry

                // Save to PowerSync with retry
                saveEntryWithRetry(entry)

                print("[FPSync] Auto-filled image #\(imageNumber) for \(entry.lastName), \(entry.firstName)")
            }
        }
    }

    /// Save a roster entry with retry logic. Shows error alert on final failure.
    private func saveEntryWithRetry(_ entry: RosterEntry) {
        Task {
            // Wait for PowerSync to be ready if it hasn't initialized yet
            if !PowerSyncManager.shared.isReady {
                await PowerSyncManager.shared.waitForFirstSync()
            }
            var retries = 0
            while retries < 3 {
                do {
                    try await PowerSyncManager.shared.saveRosterEntry(entry)
                    return
                } catch {
                    retries += 1
                    if retries < 3 {
                        try? await Task.sleep(nanoseconds: UInt64(500_000_000 * retries))
                    } else {
                        print("saveEntryWithRetry: Failed after 3 attempts: \(error)")
                        await MainActor.run {
                            errorMessage = "Failed to save changes for \(entry.lastName). Please try again."
                            showingErrorAlert = true
                        }
                    }
                }
            }
        }
    }

    /// Format station mode for display
    private static func formatStationMode(_ mode: String) -> String {
        switch mode {
        case "camera": return "Camera Station"
        case "ios_roster": return "iPad Roster"
        case "poser": return "Poser Station"
        case "kiosk": return "Kiosk"
        case "staff_entry": return "Staff Entry"
        default: return mode
        }
    }

    /// Send subject selection to Production camera station
    private func sendSubjectSelection(entry: RosterEntry) {
        guard fpSync.isConnected else { return }
        guard let subjectId = entry.subjectId else {
            print("[FPSync] Entry \(entry.lastName), \(entry.firstName) has no subject_id — not linked")
            return
        }
        fpSync.selectSubject(
            subjectId: subjectId,
            rosterEntryId: entry.id.uuidString.lowercased(),
            subjectName: "\(entry.lastName), \(entry.firstName)"
        )
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .background {
            // Only release on actual background, not .inactive (which fires for notifications, control center, etc.)
            lockManager.handleAppBackground()
        } else if newPhase == .active {
            lockManager.handleAppForeground()
            // Re-acquire lock if we were editing when app went to background
            if let editingId = currentlyEditingEntryId {
                Task {
                    let reacquired = await lockManager.reacquireLock(entryId: editingId, type: .rosterEntry)
                    if !reacquired {
                        // Lock taken by someone else while we were away
                        lockLostMessage = "Lock lost while app was in background — your edits are still saved locally"
                        withAnimation { showLockLostWarning = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            withAnimation { showLockLostWarning = false }
                        }
                    }
                }
            }
        }
    }

    private func showConflictNotification(_ message: String) {
        syncNotificationMessage = message
        syncNotificationIsConflict = true
        withAnimation { showSyncNotification = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation {
                showSyncNotification = false
                syncNotificationIsConflict = false
            }
        }
    }

    private func handleLockLostEvent() {
        guard let event = lockManager.lockLostEvent else { return }

        // Only show warning if the lost lock matches what we're currently editing
        guard event.entryId == currentlyEditingEntryId else { return }

        let reasonText: String
        switch event.reason {
        case .heartbeatFailed:
            reasonText = "Lock refresh failed — your edits are still saved locally"
        case .expiredWhileOffline:
            reasonText = "Lock expired while offline — another user may edit this entry"
        case .takenByOtherUser:
            reasonText = "Another user took this lock — your edits are still saved locally"
        }

        lockLostMessage = reasonText
        withAnimation { showLockLostWarning = true }

        // Auto-dismiss after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            withAnimation { showLockLostWarning = false }
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
            organizationId: sportsShoot?.organizationId ?? "",
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
            organizationId: sportsShoot?.organizationId ?? "",
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
            organizationId: sportsShoot?.organizationId ?? "",
            onComplete: { success in
                if success { Task { await refreshRosterEntries() } }
                showingImportExport = false
            }
        )
    }

    private var multiPhotoImportSheet: some View {
        MultiPhotoRosterImporterView(
            shootID: shootID,
            organizationId: sportsShoot?.organizationId ?? "",
            onComplete: { success in
                if success { Task { await refreshRosterEntries() } }
                showingMultiPhotoImport = false
            }
        )
    }

    private var connectionDetailsSheet: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(multipeerSync.isConnected ? "Connected" : "Not Connected")
                            .foregroundColor(multipeerSync.isConnected ? .green : .orange)
                    }
                }

                if !multipeerSync.connectedPeers.isEmpty {
                    Section("Connected Kiosks (\(multipeerSync.connectedPeers.count))") {
                        ForEach(multipeerSync.connectedPeers, id: \.displayName) { peer in
                            HStack {
                                Image(systemName: "ipad")
                                    .foregroundColor(.blue)
                                Text(peer.displayName)
                                    .font(.body)
                                Spacer()
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                } else {
                    Section {
                        VStack(alignment: .center, spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text("No kiosks found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Make sure kiosk devices are running and have Bluetooth + WiFi enabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
            }
            .navigationTitle("Photographer Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingConnectionDetails = false
                    }
                }
            }
        }
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

            if showLockLostWarning {
                lockLostWarningView
            }
        }
    }

    private var syncNotificationView: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: syncNotificationIsConflict ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(syncNotificationIsConflict ? .orange : .green)
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

    private var lockLostWarningView: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)

                Text(lockLostMessage)
                    .font(.caption)
                    .foregroundColor(.orange)

                Spacer()

                Button(action: {
                    withAnimation { showLockLostWarning = false }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.15))

            Spacer()
        }
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
                dismissKeyboard()
                // Save and stop editing when switching tabs
                if let editingId = currentlyEditingEntryId {
                    Task {
                        await stopEditing(entryId: editingId)
                        await lockManager.releaseRosterEntryLock(entryId: editingId)
                    }
                }
                if newValue == 1 {
                    withAnimation { showFilterPanel = false }
                }
            }

            Spacer()

            // Multipeer connection status
            Button(action: { showingConnectionDetails = true }) {
                HStack(spacing: 4) {
                    Image(systemName: multipeerSync.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 12))
                        .foregroundColor(multipeerSync.isConnected ? .green : .orange)
                    Text(multipeerSync.isConnected ? "\(multipeerSync.connectedPeers.count) kiosk(s)" : "No kiosks")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            if selectedTab == 0 {
                Button(action: {
                    dismissKeyboard()
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

            // Search bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    TextField("Search by name or ID...", text: $searchText)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color(.systemGroupedBackground))

            // Progress bar + athlete count
            HStack(spacing: 8) {
                let filteredRoster = filterRoster(rosterEntries)
                let totalCount = filteredRoster.count
                let photographedCount = filteredRoster.filter { !$0.imageNumbers.isEmpty }.count

                Text("\(photographedCount)/\(totalCount) photographed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(photographedCount == totalCount && totalCount > 0 ? .green : .secondary)

                ProgressView(value: totalCount > 0 ? Double(photographedCount) / Double(totalCount) : 0)
                    .tint(photographedCount == totalCount && totalCount > 0 ? .green : .blue)
                    .frame(maxWidth: 100)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
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
            .overlay(
                // Add athlete buttons at bottom
                VStack {
                    Spacer()
                    ScrollView(.horizontal, showsIndicators: false) {
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

                Button(action: { showingKiosk = true }) {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text("Kiosk")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                Button(action: {
                    if fpSync.isConnected {
                        showingFPSyncSheet = true
                    } else {
                        guard let shoot = sportsShoot, shoot.galleryId != nil else {
                            errorMessage = "This sports job isn't linked to a Production gallery yet. Sync it from Focal Point Production first."
                            showingErrorAlert = true
                            return
                        }
                        showingFPSyncSheet = true
                    }
                }) {
                    HStack {
                        Image(systemName: fpSync.isConnected ? "bolt.fill" : "bolt.slash")
                        Text(fpSync.isConnected ? "Synced" : "Sync")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(fpSync.isConnected ? Color.green : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                    Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground).opacity(0.95))
                }
            }, alignment: .bottom)
        }
    }

    private func rosterEntryRow(entry: RosterEntry, isEven: Bool) -> some View {
        let isCurrentlyEditing = currentlyEditingEntryId == entry.id
        let isLockedByOther = entry.isLockedByOtherDevice(editorIdentifier: lockManager.currentEditorIdentifier, userId: lockManager.currentUserId)
        let groupColor = colorForGroup(entry.groupName)

        return HStack(spacing: 0) {
            // Status indicator color strip
            Rectangle()
                .fill(!entry.imageNumbers.isEmpty ? Color.green : Color(.systemGray4))
                .frame(width: 4)

            VStack(spacing: 0) {
            VStack(spacing: 8) {
                // Player info row
                HStack(alignment: .top) {
                    // Sync status dot (only when connected to Production)
                    if fpSync.isConnected {
                        Circle()
                            .fill(!entry.imageNumbers.isEmpty ? Color.green : (entry.subjectId != nil ? Color.gray : Color.orange))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(entry.firstName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.blue)

                            if !entry.teacher.isEmpty {
                                Text(specialTranslation(entry.teacher))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(specialBadgeColor(entry.teacher))
                                    .clipShape(Capsule())
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
                    dismissKeyboard()

                    // If connected to Production, send subject selection to camera station
                    if fpSync.isConnected && entry.subjectId != nil {
                        sendSubjectSelection(entry: entry)
                    }

                    Task {
                        if let editingId = currentlyEditingEntryId {
                            await stopEditing(entryId: editingId)
                        }
                        selectedRosterEntry = entry
                        showingAddRosterEntry = true
                    }
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
                            dismissKeyboard()
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
        } // Close outer HStack (status strip + content)
        .background(isEven ? Color(.systemBackground) : Color(.systemGray6))
        .overlay(isLockedByOther ? Color.red.opacity(0.05) : Color.clear)
        .swipeActions(edge: .trailing) {
            if !isLockedByOther {
                Button(role: .destructive) {
                    Task { await deleteRosterEntry(entry) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if !isLockedByOther {
                Button {
                    dismissKeyboard()
                    Task {
                        if let editingId = currentlyEditingEntryId {
                            await stopEditing(entryId: editingId)
                        }
                        selectedRosterEntry = entry
                        showingAddRosterEntry = true
                    }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if !isLockedByOther {
                Button(action: {
                    dismissKeyboard()
                    Task {
                        if let editingId = currentlyEditingEntryId {
                            await stopEditing(entryId: editingId)
                        }
                        selectedRosterEntry = entry
                        showingAddRosterEntry = true
                    }
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
                        if !group.isLockedByOtherDevice(editorIdentifier: lockManager.currentEditorIdentifier, userId: lockManager.currentUserId) {
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
            let shoot = try await SportsShootService.shared.fetchSportsShoot(id: shootID)
            self.sportsShoot = shoot

            // If PowerSync hasn't completed its first sync yet, wait for it.
            // This ensures local SQLite has data before we try to read it.
            if !powerSync.hasSynced {
                await powerSync.waitForFirstSync()
            }

            let entries = try await powerSync.getRosterEntries(forJob: shootID)
            let groups = try await powerSync.getGroupImages(forJob: shootID)

            self.rosterEntries = entries
            self.groupImages = groups

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to load: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func refreshRosterEntries() async {
        // Merge server data with local state — never blindly replace
        do {
            let serverEntries = try await powerSync.getRosterEntries(forJob: shootID)
            var merged = serverEntries

            // Keep local entries that are newer or not yet on server
            for localEntry in rosterEntries {
                guard !recentlyDeletedEntryIds.contains(localEntry.id) else { continue }

                if let index = merged.firstIndex(where: { $0.id == localEntry.id }) {
                    if localEntry.updatedAt > merged[index].updatedAt {
                        merged[index] = localEntry
                    }
                } else {
                    merged.append(localEntry)
                }
            }

            rosterEntries = merged
        } catch {
            print("Failed to refresh roster: \(error)")
        }
    }

    private func refreshGroupImages() async {
        // Merge server data with local state — never blindly replace
        do {
            let serverGroups = try await powerSync.getGroupImages(forJob: shootID)
            var merged = serverGroups

            for localGroup in groupImages {
                guard !recentlyDeletedGroupIds.contains(localGroup.id) else { continue }

                if let index = merged.firstIndex(where: { $0.id == localGroup.id }) {
                    if localGroup.updatedAt > merged[index].updatedAt {
                        merged[index] = localGroup
                    }
                } else {
                    merged.append(localGroup)
                }
            }

            groupImages = merged
        } catch {
            print("Failed to refresh groups: \(error)")
        }
    }

    /// Set up PowerSync watch streams for real-time updates
    private func setupPowerSyncWatchers() {
        // Cancel any existing watchers
        rosterWatchTask?.cancel()
        groupWatchTask?.cancel()

        // Watch roster entries with auto-reconnect
        rosterWatchTask = Task {
            var retryDelay: UInt64 = 1_000_000_000 // 1s
            while !Task.isCancelled {
                do {
                    for try await entries in powerSync.watchRosterEntries(forJob: shootID) {
                        var merged = entries

                        // Protect currently editing entry from being overwritten
                        if let editingId = currentlyEditingEntryId,
                           let localEntry = rosterEntries.first(where: { $0.id == editingId }) {
                            if let index = merged.firstIndex(where: { $0.id == editingId }) {
                                var preservedEntry = localEntry
                                preservedEntry.imageNumbers = editingValues[editingId] ?? localEntry.imageNumbers
                                merged[index] = preservedEntry
                            }
                        }

                        // For every local entry, protect it from stale server data:
                        var conflictDetected = false
                        for localEntry in rosterEntries {
                            // Skip entries we intentionally deleted
                            guard !recentlyDeletedEntryIds.contains(localEntry.id) else { continue }

                            if let index = merged.firstIndex(where: { $0.id == localEntry.id }) {
                                // Entry exists in both — keep whichever is newer
                                if localEntry.updatedAt > merged[index].updatedAt {
                                    merged[index] = localEntry
                                } else if merged[index].updatedAt > localEntry.updatedAt
                                            && merged[index].imageNumbers != localEntry.imageNumbers {
                                    // Server data is newer AND content differs — notify user
                                    conflictDetected = true
                                }
                            } else {
                                // Entry exists locally but NOT in watcher data —
                                // server hasn't received it yet. Keep it.
                                merged.append(localEntry)
                            }
                        }

                        // Clean up deleted IDs once server confirms removal
                        for deletedId in recentlyDeletedEntryIds {
                            if !merged.contains(where: { $0.id == deletedId }) {
                                recentlyDeletedEntryIds.remove(deletedId)
                            }
                        }

                        self.rosterEntries = merged
                        retryDelay = 1_000_000_000 // Reset on success

                        // Show conflict notification if server overwrote local changes
                        if conflictDetected {
                            showConflictNotification("Roster updated by another user")
                        }
                    }
                } catch {
                    if Task.isCancelled { return }
                    print("SportsShootDetailView: Roster watch error, retrying in \(retryDelay / 1_000_000_000)s: \(error)")
                }
                try? await Task.sleep(nanoseconds: retryDelay)
                retryDelay = min(retryDelay * 2, 30_000_000_000) // Cap at 30s
            }
        }

        // Watch group images with auto-reconnect
        groupWatchTask = Task {
            var retryDelay: UInt64 = 1_000_000_000 // 1s
            while !Task.isCancelled {
                do {
                    for try await groups in powerSync.watchGroupImages(forJob: shootID) {
                        var merged = groups

                        // For every local group, protect it from stale server data:
                        var conflictDetected = false
                        for localGroup in groupImages {
                            // Skip groups we intentionally deleted
                            guard !recentlyDeletedGroupIds.contains(localGroup.id) else { continue }

                            if let index = merged.firstIndex(where: { $0.id == localGroup.id }) {
                                // Group exists in both — keep whichever is newer
                                if localGroup.updatedAt > merged[index].updatedAt {
                                    merged[index] = localGroup
                                } else if merged[index].updatedAt > localGroup.updatedAt
                                            && merged[index].imageNumbers != localGroup.imageNumbers {
                                    // Server data is newer AND content differs — notify user
                                    conflictDetected = true
                                }
                            } else {
                                // Group exists locally but NOT in watcher data —
                                // server hasn't received it yet. Keep it.
                                merged.append(localGroup)
                            }
                        }

                        // Clean up deleted IDs once server confirms removal
                        for deletedId in recentlyDeletedGroupIds {
                            if !merged.contains(where: { $0.id == deletedId }) {
                                recentlyDeletedGroupIds.remove(deletedId)
                            }
                        }

                        self.groupImages = merged
                        retryDelay = 1_000_000_000 // Reset on success

                        // Show conflict notification if server overwrote local changes
                        if conflictDetected {
                            showConflictNotification("Group updated by another user")
                        }
                    }
                } catch {
                    if Task.isCancelled { return }
                    print("SportsShootDetailView: Groups watch error, retrying in \(retryDelay / 1_000_000_000)s: \(error)")
                }
                try? await Task.sleep(nanoseconds: retryDelay)
                retryDelay = min(retryDelay * 2, 30_000_000_000) // Cap at 30s
            }
        }
    }

    // MARK: - Editing Functions

    private func startEditing(entry: RosterEntry) async {
        // Check if locked by someone else (uses device-session-aware comparison)
        if entry.isLockedByOtherDevice(editorIdentifier: lockManager.currentEditorIdentifier, userId: lockManager.currentUserId) {
            errorMessage = "This entry is being edited by \(entry.lockedByName ?? "another user")"
            showingErrorAlert = true
            return
        }

        // Save and release previous entry if switching
        if let previousId = currentlyEditingEntryId, previousId != entry.id {
            await stopEditing(entryId: previousId)
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

    /// Dismiss both custom (iPad) and system (iPhone) keyboards
    private func dismissKeyboard() {
        KeyboardManager.shared.hideKeyboard()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func handleEditingValueChange(_ newValues: [UUID: String]) {
        guard let entryId = currentlyEditingEntryId,
              let newValue = newValues[entryId],
              newValue != lastSavedValues[entryId] else { return }

        // Cancel any existing debounce task
        debounceTask?.cancel()

        // Create a new debounce task using DispatchWorkItem
        // Captures entryId and newValue by value so it's safe if view state changes
        let capturedEntryId = entryId
        let capturedValue = newValue
        let task = DispatchWorkItem {
            Task { @MainActor [self] in
                // Verify we're still editing this entry before saving
                guard self.currentlyEditingEntryId == capturedEntryId else { return }
                await self.saveEntry(entryId: capturedEntryId, imageNumbers: capturedValue)
                self.lastSavedValues[capturedEntryId] = capturedValue
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

        // Haptic feedback on save
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Save to PowerSync with retry
        var retries = 0
        while retries < 3 {
            do {
                try await powerSync.saveRosterEntry(entry)
                return
            } catch {
                retries += 1
                print("SportsShootDetailView: Save retry \(retries)/3: \(error)")
                if retries < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * retries))
                }
            }
        }
        print("SportsShootDetailView: Failed to save entry after 3 retries")
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func moveToNextEditableEntry(currentID: UUID) {
        let displayedRoster = sortedRoster(filterRoster(rosterEntries))

        guard let currentIndex = displayedRoster.firstIndex(where: { $0.id == currentID }) else { return }

        // Find next unlocked entry
        for index in (currentIndex + 1)..<displayedRoster.count {
            let nextEntry = displayedRoster[index]
            if !nextEntry.isLockedByOtherDevice(editorIdentifier: lockManager.currentEditorIdentifier, userId: lockManager.currentUserId) {
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
            if !nextEntry.isLockedByOtherDevice(editorIdentifier: lockManager.currentEditorIdentifier, userId: lockManager.currentUserId) {
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
        // Track as deleted so watcher doesn't resurrect it
        recentlyDeletedEntryIds.insert(entry.id)

        // Remove from local state immediately
        rosterEntries.removeAll { $0.id == entry.id }

        // Delete from PowerSync (auto-syncs when online)
        do {
            try await powerSync.deleteRosterEntry(id: entry.id)
        } catch {
            print("SportsShootDetailView: Failed to delete entry: \(error)")
            // Restore on failure
            recentlyDeletedEntryIds.remove(entry.id)
            rosterEntries.append(entry)
        }
    }

    private func deleteGroupImage(_ group: GroupImage) async {
        // Track as deleted so watcher doesn't resurrect it
        recentlyDeletedGroupIds.insert(group.id)

        // Remove from local state immediately
        groupImages.removeAll { $0.id == group.id }

        // Delete from PowerSync (auto-syncs when online)
        do {
            try await powerSync.deleteGroupImage(id: group.id)
        } catch {
            print("SportsShootDetailView: Failed to delete group: \(error)")
            // Restore on failure
            recentlyDeletedGroupIds.remove(group.id)
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
        case "8": return "8th"
        default: return special
        }
    }

    private func specialBadgeColor(_ code: String) -> Color {
        switch code.uppercased() {
        case "C": return .blue
        case "S": return .orange
        case "8": return .green
        default: return .gray
        }
    }

    private func allGroupNames() -> [String] {
        let allGroups = Set(rosterEntries.map { $0.groupName })
        return Array(allGroups).filter { !$0.isEmpty }.sorted()
    }

    private func filterRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
        var filteredRoster = roster

        // Apply search text filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filteredRoster = filteredRoster.filter { entry in
                entry.lastName.lowercased().contains(query) ||
                entry.firstName.lowercased().contains(query) ||
                entry.rosterId.lowercased().contains(query)
            }
        }

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
