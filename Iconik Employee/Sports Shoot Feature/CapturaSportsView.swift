import SwiftUI
import Supabase
import Combine

// Thumbnail paired with its image number (from capture filename)
struct CaptureThumb: Identifiable {
    let id = UUID()
    let image: UIImage
    let imageNumber: Int?
}

// State management class to handle objectWillChange notifications
class CapturaSportsViewModel: ObservableObject {
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
    @Published var showingKiosk = false
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
    // Baseline for the save guard: editingImageNumber at edit-start / last save.
    // Never compare against rosterEntries — the watch stream copies the live
    // typed text into the array, so an array-compare skips real saves.
    var lastSavedImageNumber: String = ""
    @Published var lockedEntries: [UUID: String] = [:] // [entryID: editorName]
    
    // UI state - header collapsed in landscape
    @Published var isHeaderCollapsed = true

    // Multipeer connectivity for kiosk sync
    @Published var multipeerSync: MultipeerRosterSync?
    @Published var showingConnectionDetails = false

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
                    // Clean up cached thumbnails for this shoot
                    ThumbnailCache.shared.deleteShoot(shootId: shoot.id.uuidString)
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

struct CapturaSportsView: View {
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
    @StateObject private var viewModel = CapturaSportsViewModel()

    // PowerSync for offline-first operations
    // NOTE: Plain reference (not @StateObject) to prevent @Published changes from
    // triggering view rebuilds that collapse NavigationLink push state on wake from sleep.
    private let powerSync = PowerSyncManager.shared

    // Focus state for keyboard navigation
    @FocusState private var focusedField: String?
    
    // Device orientation detection
    @State private var orientation = UIDeviceOrientation.unknown
    
    // Track if view is visible to optimize timers
    @State private var isViewVisible = false

    // Track expanded schools in archived view
    @State private var expandedSchools: Set<String> = []

    // Supabase realtime listener reference
    @State private var shootListener: ListenerRegistrationWrapper?

    // PowerSync watch tasks (replaces Supabase realtime subscription for roster data)
    @State private var rosterWatchTask: Task<Void, Never>?
    @State private var groupWatchTask: Task<Void, Never>?
    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    // Focal Point Production sync (iPad ↔ Surface Pro)
    @StateObject private var fpSync = FocalPointSyncClient.shared
    @State private var showingFPSyncSheet = false
    @State private var manualSyncIP = ""
    @State private var manualSyncPIN = ""

    // Sync state: real-time indicators from Production
    @State private var highlightedEntryId: UUID? = nil          // Flash highlight on reverse select
    @State private var subjectCaptureCounts: [String: Int] = [:] // subject_id -> photo count
    @State private var flaggedSubjects: Set<String> = []         // subject_ids with QC retake flag
    @State private var photographedSubjects: Set<String> = []    // subject_ids that have been shot
    @State private var subjectThumbnails: [String: [CaptureThumb]] = [:] // subject_id -> all thumbnails (newest last)
    @State private var pendingImageNumbers: [String: [Int]] = [:] // subject_id -> image numbers awaiting thumbnail
    @State private var absentSubjects: Set<String> = []          // subject_ids marked absent
    @State private var groupAttendance: [String: Set<String>] = [:] // group description -> set of present roster entry IDs
    @State private var pendingCaptureSaves: [UUID: Task<Void, Never>] = [:] // debounced saves per roster entry
    @State private var lastSyncedEntryId: UUID? = nil // last entry tapped for iPad→Surface sync

    // Photo viewer
    @State private var showPhotoViewer = false
    @State private var photoViewerSubjectId: String = ""
    @State private var photoViewerSubjectName: String = ""
    @State private var photoViewerThumbs: [CaptureThumb] = []

    // Search
    @State private var searchText: String = ""

    // Move image to another athlete
    @State private var showMoveImagePicker = false
    @State private var moveImageNumber: Int = 0
    @State private var moveSearchText: String = ""

    // Scroll position preservation
    @State private var scrollAnchorEntryId: UUID? = nil

    // Batch delete (Edit mode)
    @State private var isEditMode = false
    @State private var selectedEntryIds: Set<UUID> = []
    @State private var showingBatchDeleteConfirm = false

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

    // MARK: - Connection Details Sheet

    @ViewBuilder
    private func connectionDetailsSheet(multipeer: MultipeerRosterSync) -> some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(multipeer.isConnected ? "Connected" : "Not Connected")
                            .foregroundColor(multipeer.isConnected ? .green : .orange)
                    }
                }

                if !multipeer.connectedPeers.isEmpty {
                    Section("Connected Kiosks (\(multipeer.connectedPeers.count))") {
                        ForEach(multipeer.connectedPeers, id: \.displayName) { peer in
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
                        viewModel.showingConnectionDetails = false
                    }
                }
            }
        }
    }

    // MARK: - Focal Point Production Sync UI

    @ViewBuilder
    private var fpSyncSheet: some View {
        NavigationView {
            List {
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
                        // PIN entry — required for both auto and manual connect
                        TextField("4-digit PIN", text: $manualSyncPIN)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.asciiCapableNumberPad)
                            .onChange(of: manualSyncPIN) { newValue in
                                // Auto-dismiss keyboard when 4 digits entered
                                if newValue.count >= 4 {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                            }

                        // Auto-discover: finds server via mDNS, uses PIN above
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            let pin = manualSyncPIN.trimmingCharacters(in: .whitespaces)
                            guard !pin.isEmpty else { return }
                            fpSync.setAuthToken(pin)
                            if let galleryId = viewModel.selectedShoot?.galleryId {
                                fpSync.setGalleryId(galleryId)
                            }
                            guard let shoot = viewModel.selectedShoot, let galleryId = shoot.galleryId else { return }
                            fpSync.startDiscovery(galleryId: galleryId)
                        } label: {
                            Label("Connect", systemImage: "wifi")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualSyncPIN.isEmpty || viewModel.selectedShoot?.galleryId == nil)

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

                        Text("Enter the PIN shown on Production's network panel")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Manual IP override (if auto-discover doesn't find the server)
                if !fpSync.isConnected {
                    Section("Manual IP (optional)") {
                        HStack {
                            TextField("Server IP", text: $manualSyncIP)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            Button("Connect") {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                let ip = manualSyncIP.trimmingCharacters(in: .whitespaces)
                                let pin = manualSyncPIN.trimmingCharacters(in: .whitespaces)
                                guard !ip.isEmpty, !pin.isEmpty else { return }
                                fpSync.setAuthToken(pin)
                                if let galleryId = viewModel.selectedShoot?.galleryId {
                                    fpSync.setGalleryId(galleryId)
                                }
                                fpSync.connect(host: ip, port: 8765)
                            }
                            .disabled(manualSyncIP.isEmpty || manualSyncPIN.isEmpty)
                        }
                        Text("Only needed if auto-connect doesn't find the server")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

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

    /// Format a sorted array of image numbers into range notation: [1456, 1457, 1458, 1462] → "1456-58, 1462"
    /// Set banner image number in the roster entry's notes field
    private func setBannerForSubject(subjectId: String, imageNumber: Int) {
        guard let idx = viewModel.rosterEntries.firstIndex(where: {
            $0.subjectId?.lowercased() == subjectId.lowercased()
        }) else { return }

        var entry = viewModel.rosterEntries[idx]
        var notes = entry.notes

        // Remove any existing "Banner: XXXX" from notes
        if let range = notes.range(of: #"Banner:\s*\d+"#, options: .regularExpression) {
            notes.removeSubrange(range)
            notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Append new banner selection
        let bannerText = "Banner: \(imageNumber)"
        if notes.isEmpty {
            notes = bannerText
        } else {
            notes = notes + "\n" + bannerText
        }

        entry.notes = notes
        entry.version += 1
        entry.updatedAt = Date()
        viewModel.rosterEntries[idx] = entry
        saveEntryWithRetry(entry)
    }

    private func formatImageNumberRanges(_ numbers: [Int]) -> String {
        guard !numbers.isEmpty else { return "" }
        let sorted = numbers.sorted()
        var ranges: [(Int, Int)] = []
        var start = sorted[0], end = sorted[0]

        for i in 1..<sorted.count {
            if sorted[i] == end + 1 {
                end = sorted[i]
            } else {
                ranges.append((start, end))
                start = sorted[i]
                end = sorted[i]
            }
        }
        ranges.append((start, end))

        return ranges.map { (s, e) in
            if s == e {
                return "\(s)"
            } else {
                // Abbreviate end but keep at least 2 digits: 5645-46, not 5645-6
                let startStr = "\(s)"
                let endStr = "\(e)"
                // Find how many leading digits are shared
                let shared = zip(startStr, endStr).prefix(while: { $0 == $1 }).count
                let suffix = String(endStr.dropFirst(shared))
                // Keep at least 2 digits in the suffix for clarity
                if suffix.count >= 2 && shared > 0 {
                    return "\(s)-\(suffix)"
                } else if suffix.count == 1 && shared > 0 && endStr.count >= 2 {
                    // Only 1 digit abbreviated — show last 2 digits instead
                    let twoDigitSuffix = String(endStr.suffix(2))
                    return "\(s)-\(twoDigitSuffix)"
                }
                return "\(s)-\(e)"
            }
        }.joined(separator: ", ")
    }

    /// Parse image numbers field into array of ints (handles "1456-58, 1462" format)
    private func parseImageNumbers(_ field: String) -> [Int] {
        var numbers: [Int] = []
        let parts = field.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if part.contains("-") {
                let rangeParts = part.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
                if rangeParts.count == 2, let start = Int(rangeParts[0]) {
                    let endStr = rangeParts[1]
                    if let end = Int(endStr) {
                        if end > start {
                            // Full range: 1456-1458
                            for n in start...end { numbers.append(n) }
                        } else {
                            // Abbreviated: 1456-58 → 1456-1458
                            let startStr = "\(start)"
                            let prefix = String(startStr.prefix(startStr.count - endStr.count))
                            if let fullEnd = Int(prefix + endStr), fullEnd > start {
                                for n in start...fullEnd { numbers.append(n) }
                            } else {
                                numbers.append(start)
                            }
                        }
                    }
                }
            } else if let n = Int(part) {
                numbers.append(n)
            }
        }
        return numbers
    }

    private func setupFPSyncCallbacks() {
        // Capture completed — auto-fill image numbers
        fpSync.onCaptureCompleted = { event in
            guard let imageNumber = event.imageNumber else { return }

            // Track capture count
            subjectCaptureCounts[event.subjectId, default: 0] += 1
            // Mark as photographed
            photographedSubjects.insert(event.subjectId)
            // Queue image number so the next thumbnail for this subject gets paired with it
            var pending = pendingImageNumbers[event.subjectId] ?? []
            pending.append(imageNumber)
            pendingImageNumbers[event.subjectId] = pending

            // Find matching roster entry: try roster_entry_id, then subject_id, then last-tapped entry
            let idx: Int? = {
                // 1. Direct roster entry ID match
                if let rosterEntryId = event.rosterEntryId,
                   let i = viewModel.rosterEntries.firstIndex(where: { $0.id.uuidString.lowercased() == rosterEntryId.lowercased() }) {
                    return i
                }
                // 2. Match by subjectId (Production subject UUID stored on roster entry via "Sync to iPad")
                if let i = viewModel.rosterEntries.firstIndex(where: { $0.subjectId?.lowercased() == event.subjectId.lowercased() }) {
                    return i
                }
                // 3. Fall back to the last entry tapped on iPad (most common workflow: tap athlete → take photo)
                if let lastId = lastSyncedEntryId,
                   let i = viewModel.rosterEntries.firstIndex(where: { $0.id == lastId }) {
                    return i
                }
                return nil
            }()

            guard let idx = idx else {
                print("[FPSync] No roster entry found for subject \(event.subjectId)")
                return
            }

            let entryId = viewModel.rosterEntries[idx].id

            var entry = viewModel.rosterEntries[idx]
            var numbers = parseImageNumbers(entry.imageNumbers)
            if !numbers.contains(imageNumber) {
                numbers.append(imageNumber)
            }
            let formatted = formatImageNumberRanges(numbers)
            entry.imageNumbers = formatted
            entry.version += 1
            entry.updatedAt = Date()
            viewModel.rosterEntries[idx] = entry

            // If user is editing this entry's image numbers, update the editing text too
            if viewModel.currentlyEditingEntry == entryId {
                viewModel.editingImageNumber = formatted
            }

            // Debounce save — cancel any pending save for this entry, wait 500ms for burst captures
            pendingCaptureSaves[entryId]?.cancel()
            pendingCaptureSaves[entryId] = Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                guard !Task.isCancelled else { return }
                // Re-read the latest entry state after debounce
                if let latestIdx = viewModel.rosterEntries.firstIndex(where: { $0.id == entryId }) {
                    saveEntryWithRetry(viewModel.rosterEntries[latestIdx])
                }
            }

            print("[FPSync] Auto-filled image #\(imageNumber) for \(entry.lastName), \(entry.firstName)")
        }

        // Subject photographed — store thumbnail paired with image number
        fpSync.onSubjectPhotographed = { subjectId, thumbnail, poseNumber in
            photographedSubjects.insert(subjectId)
            if let thumbStr = thumbnail,
               let data = Data(base64Encoded: thumbStr.replacingOccurrences(of: "data:image/jpeg;base64,", with: "")),
               let image = UIImage(data: data) {
                // Pop the oldest pending image number for this subject (FIFO)
                var imgNum: Int? = nil
                if var pending = pendingImageNumbers[subjectId], !pending.isEmpty {
                    imgNum = pending.removeFirst()
                    pendingImageNumbers[subjectId] = pending.isEmpty ? nil : pending
                }
                var thumbs = subjectThumbnails[subjectId] ?? []
                thumbs.append(CaptureThumb(image: image, imageNumber: imgNum))
                // Cap at 20 images per subject to limit memory
                if thumbs.count > 20 {
                    thumbs = Array(thumbs.suffix(20))
                }
                subjectThumbnails[subjectId] = thumbs
                // Cap total subjects with thumbnails at 100
                if subjectThumbnails.count > 100 {
                    let excess = subjectThumbnails.count - 100
                    let keysToRemove = Array(subjectThumbnails.keys.prefix(excess))
                    for key in keysToRemove { subjectThumbnails.removeValue(forKey: key) }
                }
                // Persist to disk
                if let shootId = viewModel.selectedShoot?.id.uuidString {
                    ThumbnailCache.shared.save(shootId: shootId, subjectId: subjectId, imageNumber: imgNum, image: image)
                }
            }
        }

        // Active subject changed — reverse selection (scroll to entry)
        fpSync.onActiveSubjectChanged = { subjectId in
            if let entry = viewModel.rosterEntries.first(where: { $0.subjectId == subjectId }) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    highlightedEntryId = entry.id
                }
                // Clear highlight after 1.5s
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { highlightedEntryId = nil }
                }
            }
        }

        // QC flag changed — show/hide retake indicator
        fpSync.onQCFlagChanged = { subjectId, flagged in
            if flagged {
                flaggedSubjects.insert(subjectId)
            } else {
                flaggedSubjects.remove(subjectId)
            }
        }

        // Absent changed (from another iPad or Production)
        fpSync.onSubjectAbsentChanged = { subjectId, isAbsent in
            if isAbsent {
                absentSubjects.insert(subjectId)
            } else {
                absentSubjects.remove(subjectId)
            }
        }

        // Notes changed (from Production)
        fpSync.onNotesChanged = { subjectId, rosterEntryId, notes in
            if let rid = rosterEntryId,
               let idx = viewModel.rosterEntries.firstIndex(where: { $0.id.uuidString.lowercased() == rid.lowercased() }) {
                var entry = viewModel.rosterEntries[idx]
                entry.notes = notes
                entry.version += 1
                entry.updatedAt = Date()
                viewModel.rosterEntries[idx] = entry
                saveEntryWithRetry(entry)
            }
        }

        // Queue reorder (from Production or another iPad)
        fpSync.onQueueReorder = { orderedSubjectIds in
            // Reorder roster entries to match the new order
            var reordered: [RosterEntry] = []
            for sid in orderedSubjectIds {
                if let entry = viewModel.rosterEntries.first(where: { $0.subjectId == sid }) {
                    reordered.append(entry)
                }
            }
            // Append any entries not in the reorder list (unlinked)
            for entry in viewModel.rosterEntries where !reordered.contains(where: { $0.id == entry.id }) {
                reordered.append(entry)
            }
            viewModel.rosterEntries = reordered
        }

        // Group photo ready (from Production)
        fpSync.onGroupPhotoReady = { groupName, presentSubjectIds, totalInGroup in
            // Update attendance from Production side
            let presentIds = Set(presentSubjectIds)
            let memberIds = viewModel.rosterEntries
                .filter { presentIds.contains($0.subjectId ?? "") }
                .map { $0.id.uuidString }
            groupAttendance[groupName] = Set(memberIds)
            print("[FPSync] Group '\(groupName)' ready: \(presentSubjectIds.count)/\(totalInGroup)")
        }

        fpSync.onSubjectLinked = { rosterEntryId, subjectId in
            // Update DB directly — PowerSync watcher auto-refreshes the @Published array
            guard UUID(uuidString: rosterEntryId) != nil else { return }
            Task {
                do {
                    try await PowerSyncManager.shared.linkRosterEntryToSubject(
                        rosterEntryId: rosterEntryId, subjectId: subjectId
                    )
                    // Also update in-memory for immediate UI feedback
                    if let idx = viewModel.rosterEntries.firstIndex(where: { $0.id == UUID(uuidString: rosterEntryId) }) {
                        viewModel.rosterEntries[idx].subjectId = subjectId
                    }
                    print("[FPSync] Linked roster entry \(rosterEntryId) -> subject \(subjectId)")
                } catch {
                    print("[FPSync] Failed to save subject link: \(error)")
                }
            }
        }

        fpSync.onSubjectsDeleted = { subjectIds in
            // Remove roster entries whose subjectId matches a deleted Production subject
            let deletedSet = Set(subjectIds.map { $0.lowercased() })
            let toDelete = viewModel.rosterEntries.filter { entry in
                guard let sid = entry.subjectId else { return false }
                return deletedSet.contains(sid.lowercased())
            }
            guard !toDelete.isEmpty else { return }
            viewModel.rosterEntries.removeAll { entry in
                guard let sid = entry.subjectId else { return false }
                return deletedSet.contains(sid.lowercased())
            }
            Task {
                do {
                    try await powerSync.deleteBatchRosterEntries(ids: toDelete.map { $0.id })
                    print("[FPSync] Removed \(toDelete.count) roster entries — subjects deleted on Production")
                } catch {
                    print("[FPSync] Failed to delete roster entries from sync: \(error)")
                }
            }
        }

        fpSync.onCaptureReassigned = { [self] imageNumber, oldRosterEntryId, newRosterEntryId in
            // Update image numbers: remove from old entry, add to new entry
            let oldId = oldRosterEntryId.lowercased()
            let newId = newRosterEntryId.lowercased()

            var oldSubjectId: String?
            var newSubjectId: String?

            // Find and update old entry — remove the image number
            if let oldIdx = viewModel.rosterEntries.firstIndex(where: { $0.id.uuidString.lowercased() == oldId }) {
                var entry = viewModel.rosterEntries[oldIdx]
                oldSubjectId = entry.subjectId
                var numbers = entry.imageNumbers
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0 != String(imageNumber) }
                entry.imageNumbers = numbers.joined(separator: ",")
                viewModel.rosterEntries[oldIdx] = entry
                Task {
                    do {
                        try await powerSync.saveRosterEntry(entry)
                        print("[FPSync] Removed image #\(imageNumber) from roster entry \(oldId)")
                    } catch {
                        print("[FPSync] Failed to update old roster entry: \(error)")
                    }
                }
            }

            // Find and update new entry — add the image number
            if let newIdx = viewModel.rosterEntries.firstIndex(where: { $0.id.uuidString.lowercased() == newId }) {
                var entry = viewModel.rosterEntries[newIdx]
                newSubjectId = entry.subjectId
                var numbers = entry.imageNumbers
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                numbers.append(String(imageNumber))
                entry.imageNumbers = numbers.joined(separator: ",")
                viewModel.rosterEntries[newIdx] = entry
                Task {
                    do {
                        try await powerSync.saveRosterEntry(entry)
                        print("[FPSync] Added image #\(imageNumber) to roster entry \(newId)")
                    } catch {
                        print("[FPSync] Failed to update new roster entry: \(error)")
                    }
                }
            }

            // Move the thumbnail between subjects so the image visually moves too
            if let oldSid = oldSubjectId, let newSid = newSubjectId {
                if var oldThumbs = subjectThumbnails[oldSid] {
                    if let thumbIdx = oldThumbs.firstIndex(where: { $0.imageNumber == imageNumber }) {
                        let thumb = oldThumbs.remove(at: thumbIdx)
                        subjectThumbnails[oldSid] = oldThumbs
                        var newThumbs = subjectThumbnails[newSid] ?? []
                        newThumbs.append(thumb)
                        subjectThumbnails[newSid] = newThumbs
                        print("[FPSync] Moved thumbnail for image #\(imageNumber) from \(oldSid) to \(newSid)")
                    }
                }
            }
        }

        // Verification warning — show alert when Production detects QR/face mismatch
        fpSync.onVerificationWarning = { subjectId, subjectName, status, message, qrData in
            let title = status == "mismatch" ? "Assignment Mismatch" : "Verification Warning"
            viewModel.errorMessage = "\(title): \(subjectName) — \(message)"
            viewModel.showingErrorAlert = true
        }
    }

    private func sendSubjectSelection(entry: RosterEntry) {
        // Always track the last-tapped entry for capture_completed matching
        lastSyncedEntryId = entry.id

        guard fpSync.isConnected else { return }
        // Use subjectId if linked, otherwise use roster entry ID as the identifier
        let subjectId = entry.subjectId ?? entry.id.uuidString.lowercased()
        fpSync.selectSubject(
            subjectId: subjectId,
            rosterEntryId: entry.id.uuidString.lowercased(),
            subjectName: "\(entry.lastName), \(entry.firstName)"
        )
    }

    /// Inline Special dropdown — tap to select C/S/8/blank without opening detail sheet
    @ViewBuilder
    private func specialDropdown(entry: RosterEntry) -> some View {
        Menu {
            Button("— None") {
                updateSpecial(entry: entry, value: "")
            }
            Button("C — Coach") {
                updateSpecial(entry: entry, value: "C")
            }
            Button("S — Senior") {
                updateSpecial(entry: entry, value: "S")
            }
            Button("8 — 8th Grader") {
                updateSpecial(entry: entry, value: "8")
            }
        } label: {
            if entry.teacher.isEmpty {
                Image(systemName: "tag")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            } else {
                Text(specialLabel(entry.teacher))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(specialColor(entry.teacher))
                    .clipShape(Capsule())
            }
        }
        .frame(minWidth: 44, minHeight: 44)
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
                            viewModel.errorMessage = "Failed to save changes for \(entry.lastName). Please try again."
                            viewModel.showingErrorAlert = true
                        }
                    }
                }
            }
        }
    }

    private func updateSpecial(entry: RosterEntry, value: String) {
        if let idx = viewModel.rosterEntries.firstIndex(where: { $0.id == entry.id }) {
            var updated = viewModel.rosterEntries[idx]
            updated.teacher = value
            viewModel.rosterEntries[idx] = updated
            saveEntryWithRetry(updated)
        }
    }

    private func specialColor(_ code: String) -> Color {
        switch code {
        case "C": return .blue
        case "S": return .orange
        case "8": return .green
        default: return .gray
        }
    }

    private func specialLabel(_ code: String) -> String {
        switch code.uppercased() {
        case "C": return "Coach"
        case "S": return "Senior"
        case "8": return "8th"
        default: return code
        }
    }

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
    
    // Filter roster based on selected filters and search text
    private func filterRoster(_ roster: [RosterEntry]) -> [RosterEntry] {
        // Apply filters in sequence

        // First, apply search text filter
        var filteredRoster = roster
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filteredRoster = filteredRoster.filter { entry in
                entry.lastName.lowercased().contains(query) ||
                entry.firstName.lowercased().contains(query) ||
                entry.rosterId.lowercased().contains(query)
            }
        }
        
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
        ZStack {
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
            isViewVisible = true
            // Hide tab bar when in roster view (iPad) to maximize vertical space
            if UIDevice.current.userInterfaceIdiom == .pad {
                TabBarManager.shared.isFullScreenOverlayActive = true
            }

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
            // Restore tab bar when leaving roster view
            if UIDevice.current.userInterfaceIdiom == .pad {
                TabBarManager.shared.isFullScreenOverlayActive = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            // Re-load shoots list and roster for currently-selected shoot when returning to foreground.
            // Supabase realtime subscriptions are stopped on background, so data may be stale.
            loadSportsShoots()
            if let shootID = viewModel.selectedShoot?.id {
                Task { await loadRosterForSelectedShoot(shootID: shootID) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PowerSyncDidConnect"))) { _ in
            // PowerSync connected (possibly late, after view appeared with empty local SQLite).
            // Re-fetch roster if it was empty due to sync not yet completing on first load.
            if let shootID = viewModel.selectedShoot?.id, viewModel.rosterEntries.isEmpty {
                Task { await loadRosterForSelectedShoot(shootID: shootID) }
            }
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
        .alert("Delete \(selectedEntryIds.count) athletes?", isPresented: $showingBatchDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { batchDeleteRosterEntries() }
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showMoveImagePicker) {
            NavigationView {
                List {
                    let filtered = viewModel.rosterEntries.filter { entry in
                        // Exclude current subject
                        guard entry.subjectId != photoViewerSubjectId else { return false }
                        if moveSearchText.isEmpty { return true }
                        let q = moveSearchText.lowercased()
                        return entry.firstName.lowercased().contains(q)
                            || entry.lastName.lowercased().contains(q)
                            || entry.rosterId.lowercased().contains(q)
                            || entry.groupName.lowercased().contains(q)
                    }
                    ForEach(filtered) { entry in
                        Button(action: {
                            // Find source roster entry
                            let sourceEntry = viewModel.rosterEntries.first(where: { $0.subjectId?.lowercased() == photoViewerSubjectId.lowercased() })
                            fpSync.sendMoveCapture(
                                imageNumber: moveImageNumber,
                                fromSubjectId: photoViewerSubjectId,
                                toSubjectId: entry.subjectId ?? "",
                                fromRosterEntryId: sourceEntry?.id.uuidString.lowercased() ?? "",
                                toRosterEntryId: entry.id.uuidString.lowercased()
                            )
                            showMoveImagePicker = false
                            showPhotoViewer = false
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(entry.firstName) \(entry.lastName)")
                                        .font(.headline)
                                    if !entry.rosterId.isEmpty {
                                        Text("ID: \(entry.rosterId)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if !entry.groupName.isEmpty {
                                    Text(entry.groupName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .searchable(text: $moveSearchText, prompt: "Search athletes")
                .navigationTitle("Move Image #\(moveImageNumber) to...")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { showMoveImagePicker = false }
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showingCreateSportsShoot) {
            CreateSportsShootView(onComplete: { success in
                if success {
                    loadSportsShoots()
                }
                viewModel.showingCreateSportsShoot = false
            })
        }

            // Photo viewer — ZStack overlay, covers everything instantly
            if showPhotoViewer && !photoViewerThumbs.isEmpty {
                CapturePhotoViewer(
                    subjectName: photoViewerSubjectName,
                    thumbs: photoViewerThumbs,
                    isPresented: $showPhotoViewer,
                    onBannerSelected: { imageNumber in
                        setBannerForSubject(subjectId: photoViewerSubjectId, imageNumber: imageNumber)
                    },
                    onMoveRequested: fpSync.isConnected ? { imageNumber in
                        moveImageNumber = imageNumber
                        moveSearchText = ""
                        showMoveImagePicker = true
                    } : nil
                )
                .ignoresSafeArea()
                .statusBarHidden(true)
                .zIndex(999)
            }
        } // ZStack
        .onChange(of: showPhotoViewer) { newValue in
            TabBarManager.shared.isFullScreenOverlayActive = newValue
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
                                    NavigationLink(destination: CapturaSportsRosterView_iPhone(shootID: sportsShoot.id)) {
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
                            NavigationLink(destination: CapturaSportsRosterView_iPhone(shootID: sportsShoot.id)) {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        TabBarManager.shared.isFullScreenOverlayActive = false
                        TabBarManager.shared.selectedTab = "home"
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                            Text("Home")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
            }
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

                            // Multipeer connection status
                            if let multipeer = viewModel.multipeerSync {
                                Button(action: { viewModel.showingConnectionDetails = true }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: multipeer.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                                            .font(.system(size: 12))
                                            .foregroundColor(multipeer.isConnected ? .green : .orange)
                                        Text(multipeer.isConnected ? "\(multipeer.connectedPeers.count) kiosk(s)" : "No kiosks")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                            }

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
                            Text("Roster ID + Name + Special + Team")
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
                .customKeyboardOverlay()
                // Hide original navigation toolbar
                .navigationBarHidden(true)
                .onAppear {
                    setupOrientationNotification()

                    // Set up shoot metadata listener + PowerSync watch streams
                    if let shootID = viewModel.selectedShoot?.id {
                        setupShootListener(shootID: shootID)

                        // Load data FIRST, then start watchers to avoid race condition
                        Task {
                            await loadRosterForSelectedShoot(shootID: shootID)
                            setupPowerSyncWatchers()
                            try? await RosterEntryService.shared.releaseExpiredLocks(forJob: shootID)
                            try? await GroupImageService.shared.releaseExpiredLocks(forJob: shootID)
                        }

                        // Start browsing for kiosk registration stations
                        Task { @MainActor in
                            if viewModel.multipeerSync == nil {
                                viewModel.multipeerSync = MultipeerRosterSync()
                            }
                            viewModel.multipeerSync?.startBrowsing(jobId: shootID)
                            print("CapturaSportsView: Started browsing for kiosks for shoot \(shootID)")
                        }

                        // Set up Focal Point Production sync callbacks
                        setupFPSyncCallbacks()
                    }
                }
                .onDisappear {
                    // Remove orientation notification observer
                    NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)

                    // Remove realtime listener
                    shootListener?.remove()
                    shootListener = nil

                    // Cancel PowerSync watch tasks
                    rosterWatchTask?.cancel()
                    groupWatchTask?.cancel()

                    // Release any locks when leaving the view
                    if let entryID = viewModel.currentlyEditingEntry {
                        saveCurrentEditingEntry()
                        Task {
                            await LockManager.shared.releaseRosterEntryLock(entryId: entryID)
                        }
                    }

                    // Stop browsing for kiosks
                    Task { @MainActor in
                        viewModel.multipeerSync?.disconnect()
                        print("CapturaSportsView: Stopped browsing for kiosks")
                    }

                    // Clear FP sync callbacks
                    fpSync.onCaptureCompleted = nil
                    fpSync.onSubjectPhotographed = nil
                    fpSync.onActiveSubjectChanged = nil
                    fpSync.onQCFlagChanged = nil
                    fpSync.onSubjectAbsentChanged = nil
                    fpSync.onNotesChanged = nil
                    fpSync.onQueueReorder = nil
                    fpSync.onGroupPhotoReady = nil
                    fpSync.onSubjectLinked = nil
                    fpSync.onSubjectsDeleted = nil
                    fpSync.onCaptureReassigned = nil
                    fpSync.onVerificationWarning = nil
                    // Reset sync state
                    subjectCaptureCounts = [:]
                    flaggedSubjects = []
                    photographedSubjects = []
                    subjectThumbnails = [:]
                    pendingImageNumbers = [:]
                    absentSubjects = []
                    highlightedEntryId = nil
                    groupAttendance = [:]
                    pendingCaptureSaves.values.forEach { $0.cancel() }
                    pendingCaptureSaves = [:]
                }
                .onChange(of: shoot.id) { newShootID in
                    // Cancel old watchers and set up new ones for the new shoot
                    rosterWatchTask?.cancel()
                    groupWatchTask?.cancel()
                    shootListener?.remove()
                    shootListener = nil

                    setupShootListener(shootID: newShootID)

                    // Load data FIRST, then start watchers to avoid race condition
                    Task {
                        await loadRosterForSelectedShoot(shootID: newShootID)
                        setupPowerSyncWatchers()
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
                    organizationId: shoot.organizationId,
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
                    organizationId: shoot.organizationId,
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
                    organizationId: shoot.organizationId,
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
        .sheet(isPresented: $viewModel.showingKiosk) {
            if let shoot = viewModel.selectedShoot {
                KioskLaunchView(
                    sportsJobId: shoot.id,
                    organizationId: shoot.organizationId,
                    schoolName: shoot.schoolName
                )
            }
        }
        .onChange(of: viewModel.showingKiosk) { isShowingKiosk in
            // Stop browsing when kiosk opens, resume when it closes
            if isShowingKiosk {
                viewModel.multipeerSync?.stopBrowsing()
                print("CapturaSportsView: Stopped browsing (kiosk opened)")
            } else if let shootID = viewModel.selectedShoot?.id {
                viewModel.multipeerSync?.startBrowsing(jobId: shootID)
                print("CapturaSportsView: Resumed browsing (kiosk closed)")
            }
        }
        .sheet(isPresented: $viewModel.showingConnectionDetails) {
            if let multipeer = viewModel.multipeerSync {
                connectionDetailsSheet(multipeer: multipeer)
            }
        }
        .sheet(isPresented: $showingFPSyncSheet) {
            fpSyncSheet
        }
        .sheet(isPresented: $viewModel.showingImportExport) {
            if let shoot = viewModel.selectedShoot {
                CSVImportExportView(
                    shootID: shoot.id,
                    organizationId: shoot.organizationId,
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
                    organizationId: shoot.organizationId,
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
        @Binding var imageFilterType: CapturaSportsViewModel.ImageFilterType
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
                sortableHeader("Roster ID", field: "roster_id")
                sortableHeader("Special", field: "teacher")
                sortableHeader("Sport/Team", field: "groupName")
                
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
                let filteredRoster = filterRoster(viewModel.rosterEntries)
                let namedRoster = filteredRoster.filter { !$0.lastName.trimmingCharacters(in: .whitespaces).isEmpty }
                let totalCount = namedRoster.count
                let photographedCount = namedRoster.filter { !$0.imageNumbers.isEmpty }.count
                let absentCount = filteredRoster.filter { entry in
                    guard let sid = entry.subjectId else { return false }
                    return absentSubjects.contains(sid)
                }.count

                Text("\(photographedCount)/\(totalCount) photographed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(photographedCount == totalCount && totalCount > 0 ? .green : .secondary)

                ProgressView(value: totalCount > 0 ? Double(photographedCount) / Double(totalCount) : 0)
                    .tint(photographedCount == totalCount && totalCount > 0 ? .green : .blue)
                    .frame(maxWidth: 120)

                if absentCount > 0 {
                    Text("· \(absentCount) absent")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color(.systemGroupedBackground))
            
            // List of roster entries with ScrollViewReader for reverse selection
            ScrollViewReader { scrollProxy in
                List {
                    ForEach(Array(sortedRoster(filterRoster(viewModel.rosterEntries)).enumerated()), id: \.element.id) { index, entry in
                        rosterEntryRow(shoot: shoot, entry: entry, isEven: index % 2 == 0)
                            .listRowInsets(EdgeInsets(
                                top: 4,
                                leading: 10,
                                bottom: 4,
                                trailing: 10
                            ))
                            .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        var reordered = sortedRoster(filterRoster(viewModel.rosterEntries))
                        reordered.move(fromOffsets: source, toOffset: destination)
                        let orderedIds = reordered.compactMap { $0.subjectId }.filter { !$0.isEmpty }
                        if !orderedIds.isEmpty {
                            fpSync.sendQueueReorder(orderedSubjectIds: orderedIds)
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .onChange(of: highlightedEntryId) { entryId in
                    if let entryId = entryId {
                        withAnimation {
                            scrollProxy.scrollTo(entryId, anchor: .center)
                        }
                    }
                }
                .onChange(of: viewModel.currentlyEditingEntry) { entryId in
                    if let entryId = entryId {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(entryId, anchor: .center)
                        }
                    }
                }
                .onChange(of: scrollAnchorEntryId) { entryId in
                    if let entryId = entryId {
                        scrollProxy.scrollTo(entryId, anchor: .center)
                    }
                }
            }
            
            // Batch action bar (visible in edit mode)
            if isEditMode {
                HStack(spacing: 12) {
                    Button(action: {
                        if selectedEntryIds.count == sortedRoster(filterRoster(viewModel.rosterEntries)).count {
                            selectedEntryIds.removeAll()
                        } else {
                            let locked = Set(viewModel.lockedEntries.keys)
                            selectedEntryIds = Set(sortedRoster(filterRoster(viewModel.rosterEntries))
                                .filter { !locked.contains($0.id) }
                                .map { $0.id })
                        }
                    }) {
                        Text(selectedEntryIds.count == sortedRoster(filterRoster(viewModel.rosterEntries)).count ? "Deselect All" : "Select All")
                            .font(.system(size: 14, weight: .medium))
                    }

                    Text("\(selectedEntryIds.count) selected")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Spacer()

                    if !selectedEntryIds.isEmpty {
                        Button(action: { showingBatchDeleteConfirm = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.systemGroupedBackground))
            }

            // Add athlete buttons
            HStack(spacing: 10) {
                    Spacer()

                    Button(action: {
                        withAnimation {
                            isEditMode.toggle()
                            if !isEditMode { selectedEntryIds.removeAll() }
                        }
                    }) {
                    HStack {
                        Image(systemName: isEditMode ? "checkmark" : "pencil")
                        Text(isEditMode ? "Done" : "Edit")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isEditMode ? Color.gray : Color(.systemGray3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

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

                Button(action: { viewModel.showingKiosk = true }) {
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
                        guard let shoot = viewModel.selectedShoot, shoot.galleryId != nil else {
                            viewModel.errorMessage = "This sports job isn't linked to a Production gallery yet. Sync it from Focal Point Production first."
                            viewModel.showingErrorAlert = true
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
            fontSize = 20
        } else if entry.groupName.count < 30 {
            fontSize = 12
        } else {
            fontSize = 10
        }

        // Sync state for this entry
        let subjectId = entry.subjectId ?? ""
        let isAbsent = absentSubjects.contains(subjectId)
        let isFlagged = flaggedSubjects.contains(subjectId)
        let isPhotographed = photographedSubjects.contains(subjectId)
        let captureCount = subjectCaptureCounts[subjectId] ?? 0
        let thumbs = subjectThumbnails[subjectId]
        let thumbnail = thumbs?.last?.image
        let isHighlighted = highlightedEntryId == entry.id

        return HStack(spacing: 0) {
            // Edit mode checkbox
            if isEditMode {
                Button(action: {
                    if selectedEntryIds.contains(entry.id) {
                        selectedEntryIds.remove(entry.id)
                    } else if !isLockedByOthers {
                        selectedEntryIds.insert(entry.id)
                    }
                }) {
                    Image(systemName: selectedEntryIds.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(selectedEntryIds.contains(entry.id) ? .blue : (isLockedByOthers ? .gray.opacity(0.3) : .gray))
                        .frame(width: 44, height: 44)
                }
                .disabled(isLockedByOthers)
            }

            // Status indicator color strip (leading edge)
            Rectangle()
                .fill(
                    isAbsent ? Color.gray :
                    !entry.imageNumbers.isEmpty ? Color.green :
                    Color(.systemGray4)
                )
                .frame(width: 4)

            VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Sync status indicators (only when connected to Production)
                if fpSync.isConnected {
                    VStack(spacing: 3) {
                        // Photographed checkmark OR sync dot
                        if isPhotographed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        } else {
                            Circle()
                                .fill(!entry.imageNumbers.isEmpty ? Color.green : (entry.subjectId != nil ? Color.gray : Color.orange))
                                .frame(width: 8, height: 8)
                        }
                        // QC retake flag
                        if isFlagged {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                    }
                    .frame(width: 20)
                    .padding(.trailing, 4)
                }

                // Thumbnail (if available from Production) — tap to view full photo
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.trailing, 8)
                        .onTapGesture {
                            photoViewerSubjectId = subjectId
                            photoViewerSubjectName = "\(entry.firstName) \(entry.lastName)".trimmingCharacters(in: .whitespaces)
                            photoViewerThumbs = thumbs ?? [CaptureThumb(image: thumb, imageNumber: nil)]
                            showPhotoViewer = true
                        }
                }

                // Left side - Roster ID + Name (fixed width)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        // Roster ID (new field) or firstName as fallback
                        Text(entry.rosterId.isEmpty ? entry.firstName : entry.rosterId)
                            .font(.system(size: 20))
                            .foregroundColor(.primary)

                        // Special dropdown (inline, replaces text display)
                        specialDropdown(entry: entry)
                    }

                    // Full name
                    if entry.rosterId.isEmpty {
                        // Legacy mode: lastName only (firstName is used as roster ID)
                        Text(entry.lastName)
                            .font(.system(size: 20, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // New mode: full name
                        Text("\(entry.firstName) \(entry.lastName)")
                            .font(.system(size: 20, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isEditMode {
                        if !isLockedByOthers {
                            if selectedEntryIds.contains(entry.id) {
                                selectedEntryIds.remove(entry.id)
                            } else {
                                selectedEntryIds.insert(entry.id)
                            }
                        }
                    } else if !isLockedByOthers {
                        viewModel.selectedRosterEntry = entry
                        viewModel.showingAddRosterEntry = true
                    }
                }

                // Center - Image input box + capture count badge
                HStack(spacing: 4) {
                    if isCurrentlyEditing {
                        AutosaveTextField(
                            text: $viewModel.editingImageNumber,
                            placeholder: "Enter image numbers",
                            context: "\(entry.firstName) - \(entry.lastName)",
                            onTapOutside: {
                                saveCurrentEditingEntry()
                            },
                            onEnterOrDown: {
                                saveCurrentEditingEntry()
                                moveToNextEditableEntry(currentID: entry.id)
                            },
                            onEnterOrUp: {
                                saveCurrentEditingEntry()
                                moveToPreviousEditableEntry(currentID: entry.id)
                            }
                        )
                        .font(.system(size: 20))
                        .frame(width: 150, height: 50)
                        .multilineTextAlignment(.center)
                        .background(Color.blue.opacity(0.3))
                        .cornerRadius(6)
                    } else if isLockedByOthers {
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
                            if isEditMode {
                                if !isLockedByOthers {
                                    if selectedEntryIds.contains(entry.id) {
                                        selectedEntryIds.remove(entry.id)
                                    } else {
                                        selectedEntryIds.insert(entry.id)
                                    }
                                }
                            } else {
                                startEditing(shootID: shoot.id, entry: entry)
                            }
                        }) {
                            Text(entry.imageNumbers.isEmpty ? "Image #" : entry.imageNumbers)
                                .font(.system(size: 20))
                                .fontWeight(.medium)
                                .frame(width: 150, height: 50)
                                .multilineTextAlignment(.center)
                                .background(isEven ? Color.blue.opacity(0.3) : Color.blue.opacity(0.4))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Capture count badge
                    if fpSync.isConnected && captureCount > 0 {
                        Text("\(captureCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.gray)
                            .clipShape(Circle())
                    }
                }

                Spacer(minLength: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isEditMode {
                            if !isLockedByOthers {
                                if selectedEntryIds.contains(entry.id) {
                                    selectedEntryIds.remove(entry.id)
                                } else {
                                    selectedEntryIds.insert(entry.id)
                                }
                            }
                        } else if !isLockedByOthers {
                            viewModel.selectedRosterEntry = entry
                            viewModel.showingAddRosterEntry = true
                        }
                    }

                // Right side - Group/Team tag
                if !entry.groupName.isEmpty {
                    Text(entry.groupName)
                        .font(.system(size: fontSize))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(groupColor)
                        .cornerRadius(5)
                        .lineLimit(2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isEditMode {
                                if !isLockedByOthers {
                                    if selectedEntryIds.contains(entry.id) {
                                        selectedEntryIds.remove(entry.id)
                                    } else {
                                        selectedEntryIds.insert(entry.id)
                                    }
                                }
                            } else if !isLockedByOthers {
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
        } // Close outer HStack (status strip + content)
        .background(
            isEditMode && selectedEntryIds.contains(entry.id) ? Color.blue.opacity(0.15) :
            isHighlighted ? Color.blue.opacity(0.2) :
            (isEven ? Color(.systemBackground) : Color(.systemGray4))
        )
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .opacity(isAbsent ? 0.4 : 1.0)
        .overlay(
            isLockedByOthers && !isEditMode ?
                Color.red.opacity(0.05) :
                Color.clear
        )
        .overlay(
            // In edit mode: full-row tap overlay captures all taps for selection
            isEditMode ?
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isLockedByOthers else { return }
                        if selectedEntryIds.contains(entry.id) {
                            selectedEntryIds.remove(entry.id)
                        } else {
                            selectedEntryIds.insert(entry.id)
                        }
                    }
                : nil
        )
        .swipeActions(edge: .trailing) {
            if let sid = entry.subjectId {
                Button(isAbsent ? "Present" : "Absent") {
                    if isAbsent {
                        absentSubjects.remove(sid)
                    } else {
                        absentSubjects.insert(sid)
                    }
                    fpSync.markSubjectAbsent(subjectId: sid, rosterEntryId: entry.id.uuidString.lowercased(), isAbsent: !isAbsent)
                }
                .tint(isAbsent ? .green : .orange)
            }

            if !isLockedByOthers {
                Button(role: .destructive) {
                    deleteRosterEntry(entryID: entry.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if !isLockedByOthers {
                Button {
                    viewModel.selectedRosterEntry = entry
                    viewModel.showingAddRosterEntry = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .id(entry.id)
        .onLongPressGesture {
            if !isEditMode && !isLockedByOthers {
                withAnimation {
                    isEditMode = true
                    selectedEntryIds = [entry.id]
                }
            }
        }
        .contextMenu {
            if !isLockedByOthers && !isEditMode {
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
                    Section {
                        // Group header row (tappable to edit)
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

                        // Attendance toggles — athletes in this group
                        let groupMembers = viewModel.rosterEntries.filter { $0.groupName == group.description }
                        if !groupMembers.isEmpty {
                            let presentIds = groupAttendance[group.description] ?? []

                            ForEach(groupMembers) { member in
                                HStack {
                                    Image(systemName: presentIds.contains(member.id.uuidString) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(presentIds.contains(member.id.uuidString) ? .green : .gray)
                                        .font(.system(size: 20))

                                    Text(!member.rosterId.isEmpty ? member.rosterId : member.firstName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, alignment: .leading)

                                    Text("\(member.firstName) \(member.lastName)".trimmingCharacters(in: .whitespaces))
                                        .font(.subheadline)

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .frame(minHeight: 44)
                                .onTapGesture {
                                    var current = groupAttendance[group.description] ?? []
                                    if current.contains(member.id.uuidString) {
                                        current.remove(member.id.uuidString)
                                    } else {
                                        current.insert(member.id.uuidString)
                                    }
                                    groupAttendance[group.description] = current
                                }
                            }

                            // "Ready" button — sends group_photo_ready to Production
                            Button(action: {
                                let presentIds = Array(groupAttendance[group.description] ?? [])
                                // Map roster entry IDs to subject IDs for Production
                                let presentSubjectIds = groupMembers
                                    .filter { presentIds.contains($0.id.uuidString) }
                                    .compactMap { $0.subjectId }
                                    .filter { !$0.isEmpty }
                                fpSync.sendGroupPhotoReady(
                                    groupName: group.description,
                                    presentSubjectIds: presentSubjectIds,
                                    totalInGroup: groupMembers.count
                                )
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.seal.fill")
                                    Text("Ready (\(presentIds.count)/\(groupMembers.count))")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                                .background(presentIds.count > 0 ? Color.green : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .disabled(presentIds.isEmpty)
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
                                    case "roster_id", "rosterId":
                                        // Use rosterId if present, fall back to firstName (Captura legacy)
                                        let aVal = a.rosterId.isEmpty ? a.firstName : a.rosterId
                                        let bVal = b.rosterId.isEmpty ? b.firstName : b.rosterId
                                        let aNum = Int(aVal)
                                        let bNum = Int(bVal)
                                        if let an = aNum, let bn = bNum {
                                            result = an < bn
                                        } else if aNum != nil {
                                            result = true  // numbers before non-numbers
                                        } else if bNum != nil {
                                            result = false
                                        } else {
                                            result = aVal.localizedStandardCompare(bVal) == .orderedAscending
                                        }
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

                                viewModel.isLoading = true

                                Task {
                                    // Step 1: Load from local PowerSync SQLite first — instant, works offline.
                                    // sports_jobs are in the by_org bucket so they're always synced.
                                    do {
                                        let localShoots = try await powerSync.getSportsJobs(forOrg: storedUserOrganizationID)
                                        await MainActor.run {
                                            if !localShoots.isEmpty {
                                                self.viewModel.isLoading = false
                                                self.viewModel.sportsShoots = localShoots.filter { $0.galleryId == nil }
                                                self.checkForSelectedSession()
                                                print("[DEBUG] loadSportsShoots: loaded \(localShoots.count) shoots from local SQLite")
                                            }
                                        }
                                    } catch {
                                        print("[DEBUG] loadSportsShoots: local SQLite read failed: \(error)")
                                    }

                                    // Step 2: Refresh from network in background — keeps data fresh when online.
                                    // If offline this silently fails; local data stays displayed.
                                    do {
                                        let shoots = try await SportsShootService.shared.fetchAllSportsShoots(forOrganization: storedUserOrganizationID)
                                        await MainActor.run {
                                            self.viewModel.isLoading = false
                                            self.viewModel.sportsShoots = shoots.filter { $0.galleryId == nil }
                                            self.checkForSelectedSession()
                                            print("[DEBUG] loadSportsShoots: refreshed \(shoots.count) shoots from network")
                                        }
                                    } catch {
                                        await MainActor.run {
                                            self.viewModel.isLoading = false
                                            // Only show error if local SQLite also had nothing
                                            if self.viewModel.sportsShoots.isEmpty {
                                                print("[DEBUG] loadSportsShoots FAILURE: \(error)")
                                                self.viewModel.errorMessage = "Failed to load sports shoots: \(error.localizedDescription)"
                                                self.viewModel.showingErrorAlert = true
                                            } else {
                                                print("[DEBUG] loadSportsShoots: network refresh failed, showing cached data")
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

                                Task {
                                    do {
                                        let entries = try await powerSync.getRosterEntries(forJob: currentShoot.id)
                                        let groups = try await powerSync.getGroupImages(forJob: currentShoot.id)

                                        await MainActor.run {
                                            self.viewModel.rosterEntries = entries
                                            self.viewModel.groupImages = groups
                                        }

                                        let updatedShoot = try await SportsShootService.shared.fetchSportsShoot(id: currentShoot.id)
                                        await MainActor.run {
                                            self.viewModel.selectedShoot = updatedShoot
                                            if let index = self.viewModel.sportsShoots.firstIndex(where: { $0.id == updatedShoot.id }) {
                                                self.viewModel.sportsShoots[index] = updatedShoot
                                            }
                                        }
                                    } catch {
                                        print("CapturaSportsView: Refresh using PowerSync local data")
                                    }
                                }
                            }
                            
                            private func batchDeleteRosterEntries() {
                                let ids = selectedEntryIds
                                guard !ids.isEmpty else { return }

                                // Save entries for restore on failure
                                let entriesToDelete = viewModel.rosterEntries.filter { ids.contains($0.id) }

                                // Remove from local state immediately
                                viewModel.rosterEntries.removeAll { ids.contains($0.id) }
                                selectedEntryIds.removeAll()
                                withAnimation { isEditMode = false }

                                // Delete from PowerSync + broadcast
                                Task {
                                    do {
                                        try await powerSync.deleteBatchRosterEntries(ids: Array(ids))
                                        let idStrings = entriesToDelete.map { $0.id.uuidString.lowercased() }
                                        fpSync.broadcastEntriesDeleted(rosterEntryIds: idStrings)
                                        print("[CapturaSportsView] Batch deleted \(ids.count) entries")
                                    } catch {
                                        print("[CapturaSportsView] Batch delete failed: \(error)")
                                        await MainActor.run {
                                            viewModel.rosterEntries.append(contentsOf: entriesToDelete)
                                        }
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
                                        print("CapturaSportsView: Failed to delete entry: \(error)")
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
                                        print("CapturaSportsView: Failed to delete group: \(error)")
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
                            /// iPhone uses CapturaSportsRosterView_iPhone which handles this via loadSportsShoot()
                            private func loadRosterForSelectedShoot(shootID: UUID) async {
                                // If PowerSync hasn't completed its first sync yet, wait for it.
                                // This ensures local SQLite has data before we try to read it.
                                if !powerSync.hasSynced {
                                    await powerSync.waitForFirstSync()
                                }

                                do {
                                    let entries = try await powerSync.getRosterEntries(forJob: shootID)
                                    let groups = try await powerSync.getGroupImages(forJob: shootID)

                                    // Load cached thumbnails from disk
                                    let shootIdStr = shootID.uuidString
                                    let cached = await Task.detached(priority: .utility) {
                                        ThumbnailCache.shared.loadAll(shootId: shootIdStr)
                                    }.value

                                    await MainActor.run {
                                        viewModel.rosterEntries = entries
                                        viewModel.groupImages = groups
                                        // Restore cached thumbnails + mark photographed subjects
                                        if !cached.isEmpty {
                                            subjectThumbnails = cached
                                            for subjectId in cached.keys {
                                                photographedSubjects.insert(subjectId)
                                            }
                                        }
                                    }
                                } catch {
                                    print("CapturaSportsView: Failed to load roster: \(error)")
                                }
                            }

                            // MARK: - Realtime Listeners

                            // Set up PowerSync watch streams for real-time roster/group updates
                            // This replaces the old Supabase realtime subscription that conflicted with PowerSync
                            private func setupPowerSyncWatchers() {
                                guard let shootID = viewModel.selectedShoot?.id else { return }

                                rosterWatchTask?.cancel()
                                groupWatchTask?.cancel()

                                rosterWatchTask = Task {
                                    var retryDelay: UInt64 = 1_000_000_000 // 1s
                                    while !Task.isCancelled {
                                        do {
                                            for try await entries in powerSync.watchRosterEntries(forJob: shootID) {
                                                var merged = entries

                                                // Extract lock info from the entries
                                                var locks: [UUID: String] = [:]
                                                for entry in entries {
                                                    if let lockedByName = entry.lockedByName, !lockedByName.isEmpty {
                                                        locks[entry.id] = lockedByName
                                                    }
                                                }
                                                viewModel.lockedEntries = locks

                                                // Protect currently-editing entry with live typed value
                                                if let editingId = viewModel.currentlyEditingEntry,
                                                   let index = merged.firstIndex(where: { $0.id == editingId }) {
                                                    merged[index].imageNumbers = viewModel.editingImageNumber
                                                }

                                                // Protect recently-saved entries from being overwritten
                                                // by stale SQLite data (async save may not have completed yet)
                                                for localEntry in viewModel.rosterEntries {
                                                    if let index = merged.firstIndex(where: { $0.id == localEntry.id }),
                                                       localEntry.updatedAt > merged[index].updatedAt {
                                                        merged[index] = localEntry
                                                    }
                                                }

                                                // Don't overwrite populated data with empty
                                                if merged.isEmpty && !viewModel.rosterEntries.isEmpty {
                                                    continue
                                                }

                                                // Diff-merge: only update if data actually changed (prevents scroll jump)
                                                let current = viewModel.rosterEntries
                                                let mergedIds = merged.map { $0.id }
                                                let currentIds = current.map { $0.id }

                                                if mergedIds == currentIds {
                                                    // Same entries in same order — update only changed items
                                                    var anyChanged = false
                                                    for i in merged.indices {
                                                        if merged[i] != current[i] {
                                                            viewModel.rosterEntries[i] = merged[i]
                                                            anyChanged = true
                                                        }
                                                    }
                                                    // If nothing changed, skip entirely
                                                    if !anyChanged {
                                                        retryDelay = 1_000_000_000
                                                        continue
                                                    }
                                                } else {
                                                    // Count or order changed — full replacement needed
                                                    // Remember anchor for scroll-restore
                                                    let anchor = viewModel.currentlyEditingEntry ?? lastSyncedEntryId
                                                    viewModel.rosterEntries = merged
                                                    // Restore scroll position after SwiftUI re-renders
                                                    if let anchorId = anchor, merged.contains(where: { $0.id == anchorId }) {
                                                        scrollAnchorEntryId = nil
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                            scrollAnchorEntryId = anchorId
                                                        }
                                                    }
                                                }
                                                retryDelay = 1_000_000_000 // Reset on success
                                            }
                                        } catch {
                                            if Task.isCancelled { return }
                                            print("CapturaSportsView: Roster watch error, retrying in \(retryDelay / 1_000_000_000)s: \(error)")
                                        }
                                        try? await Task.sleep(nanoseconds: retryDelay)
                                        retryDelay = min(retryDelay * 2, 30_000_000_000) // Cap at 30s
                                    }
                                }

                                groupWatchTask = Task {
                                    var retryDelay: UInt64 = 1_000_000_000 // 1s
                                    while !Task.isCancelled {
                                        do {
                                            for try await groups in powerSync.watchGroupImages(forJob: shootID) {
                                                if groups.isEmpty && !viewModel.groupImages.isEmpty {
                                                    continue
                                                }
                                                viewModel.groupImages = groups
                                                retryDelay = 1_000_000_000 // Reset on success
                                            }
                                        } catch {
                                            if Task.isCancelled { return }
                                            print("CapturaSportsView: Group watch error, retrying in \(retryDelay / 1_000_000_000)s: \(error)")
                                        }
                                        try? await Task.sleep(nanoseconds: retryDelay)
                                        retryDelay = min(retryDelay * 2, 30_000_000_000) // Cap at 30s
                                    }
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

                            // Helper to fetch and update shoot metadata only
                            // Roster entries and group images are handled by PowerSync watch streams
                            private func fetchAndUpdateShoot(shootID: UUID) async {
                                do {
                                    let updatedShoot = try await SportsShootService.shared.fetchSportsShoot(id: shootID)

                                    await MainActor.run {
                                        self.viewModel.selectedShoot = updatedShoot
                                        if let listIndex = self.viewModel.sportsShoots.firstIndex(where: { $0.id == shootID }) {
                                            self.viewModel.sportsShoots[listIndex] = updatedShoot
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
                                      viewModel.editingImageNumber != viewModel.lastSavedImageNumber else {
                                    return
                                }

                                var updatedEntry = currentEntry
                                updatedEntry.imageNumbers = viewModel.editingImageNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                                updatedEntry.version = currentEntry.version + 1
                                updatedEntry.updatedAt = Date()
                                updatedEntry.updatedBy = SupabaseManager.shared.client.auth.currentUser?.id

                                viewModel.lastSavedImageNumber = viewModel.editingImageNumber

                                // Update local state immediately
                                if let index = viewModel.rosterEntries.firstIndex(where: { $0.id == entryID }) {
                                    viewModel.rosterEntries[index] = updatedEntry
                                }

                                // Haptic feedback on save
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                                // Save to PowerSync (writes to local SQLite, auto-syncs to Supabase)
                                Task {
                                    var retries = 0
                                    while retries < 3 {
                                        do {
                                            try await powerSync.saveRosterEntry(updatedEntry)
                                            return
                                        } catch {
                                            retries += 1
                                            print("CapturaSportsView: Save retry \(retries)/3: \(error)")
                                            if retries < 3 {
                                                try? await Task.sleep(nanoseconds: UInt64(500_000_000 * retries))
                                            }
                                        }
                                    }
                                    print("CapturaSportsView: Failed to save entry after 3 retries")
                                    await MainActor.run {
                                        UINotificationFeedbackGenerator().notificationOccurred(.error)
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
                                    viewModel.lastSavedImageNumber = entry.imageNumbers
                                    return
                                }

                                // Save and release any previous lock
                                if let previousEntryID = viewModel.currentlyEditingEntry {
                                    saveCurrentEditingEntry()
                                    releaseLock(shootID: shootID, entryID: previousEntryID)
                                }

                                // Set up editing state
                                viewModel.editingImageNumber = entry.imageNumbers
                                viewModel.lastSavedImageNumber = entry.imageNumbers
                                viewModel.currentlyEditingEntry = entry.id // Set synchronously to avoid placeholder showing

                                // Acquire lock for this entry
                                acquireLock(shootID: shootID, entryID: entry.id)

                                // Send subject selection to Production camera station
                                sendSubjectSelection(entry: entry)
                            }
                        }

                        struct CapturaSportsView_Previews: PreviewProvider {
                            static var previews: some View {
                                CapturaSportsView()
                            }
                        }
