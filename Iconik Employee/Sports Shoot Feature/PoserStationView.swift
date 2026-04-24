//
//  PoserStationView.swift
//  Iconik Employee
//
//  iPad poser station for spring/underclass portrait shoots.
//  Full roster with grade/teacher filters, tap to select on camera,
//  view/edit subject info, show captured images with live thumbnails.
//

import SwiftUI

struct PoserStationView: View {
    let gallery: SportsShoot

    private let powerSync = PowerSyncManager.shared
    @StateObject private var fpSync = FocalPointSyncClient.shared
    @ObservedObject private var lockManager = LockManager.shared

    // Subjects
    @State private var subjects: [FPSubject] = []
    @State private var subjectWatchTask: Task<Void, Never>?
    @State private var isLoading = true

    // Selection
    @State private var selectedSubjectId: UUID?
    @State private var activeSubjectId: String?
    @State private var scrollTargetId: UUID?
    @AppStorage("captureAutoSelect") private var autoSelectEnabled: Bool = false  // Toggle: tap auto-selects on Surface
    @AppStorage("capturePreviewEnabled") private var previewEnabled: Bool = true  // Toggle: show capture preview popup

    // Photo tracking (WebSocket thumbnails — same pipeline as sports)
    @State private var subjectThumbnails: [String: [CaptureThumb]] = [:]
    @State private var pendingImageNumbers: [String: [Int]] = [:]
    @State private var photoCountMap: [String: Int] = [:]
    // Per-subject debounce for capture-driven saves. Image numbers append
    // to the in-memory subject immediately on every onCaptureCompleted (no
    // capture lost). The PowerSync write + WebSocket broadcast is batched
    // per-subject — 500ms after the last capture for that subject, ONE
    // save fires carrying ALL accumulated image numbers. This is what
    // makes burst-firing safe.
    @State private var pendingCaptureSaves: [UUID: Task<Void, Never>] = [:]

    // Groups (sports only) — team/squad photos, separate from per-subject
    // photos. Lives under a "Groups" tab alongside the roster. Data flows
    // through the same PowerSync + Surface-broadcast pipeline as subjects.
    @State private var groupImages: [GroupImage] = []
    @State private var groupWatchTask: Task<Void, Never>?
    @State private var showingAddGroupImage = false
    @State private var selectedGroupImage: GroupImage? = nil
    @State private var selectedTab: Int = 0  // 0 = Roster, 1 = Groups
    // groupName -> set of present subject id strings, populated from
    // onGroupPhotoReady broadcasts. Currently informational (available for
    // future UI); mirrors FP Sports' groupAttendance dictionary.
    @State private var groupAttendance: [String: Set<String>] = [:]
    // Per-group debounce for capture-driven saves — same pattern as
    // pendingCaptureSaves on subjects. Burst group captures collapse into
    // one save per group after 500ms of quiet.
    @State private var pendingGroupCaptureSaves: [UUID: Task<Void, Never>] = [:]

    // Image-state filter (chips next to Filter / Sort in the toolbar).
    // Matches FP Sports' ImageFilterType — lets the operator triage who
    // they have not shot yet, late in a shoot. .all is the default and
    // means "no filter."
    @State private var imageFilterType: ImageFilterType = .all

    // Lock state — [subject.id : editor name] for any subject in the
    // roster that's currently locked by another device. Populated from
    // the subjects watch stream (each tick scans subject.lockedByName)
    // so it reflects the same source of truth the lock RPC writes to.
    // Empty entry means not locked.
    @State private var lockedEntries: [UUID: String] = [:]

    // Inline image-number editing on the row. Tap an existing image-#
    // cell to put it into edit mode without opening the detail panel —
    // the most frequent edit on a sports shoot. Mirrors FP Sports'
    // currentlyEditingEntry / editingImageNumber / originalImageNumber
    // trio so behavior matches across views.
    // currentlyEditingEntry — id of the row in edit mode, or nil
    // editingImageNumber  — live buffer the AutosaveTextField writes to
    // originalImageNumber — value when editing started, used by the
    //   save guard to avoid spurious saves from watch-stream merges
    //   that didn't actually change the value.
    @State private var currentlyEditingEntry: UUID? = nil
    @State private var editingImageNumber: String = ""
    @State private var originalImageNumber: String = ""

    // Photo viewer
    @State private var showPhotoViewer = false
    @State private var photoViewerSubjectName = ""
    @State private var photoViewerSubjectId = ""
    @State private var photoViewerThumbs: [CaptureThumb] = []

    // Capture preview popup (auto-dismiss after 3s)
    @State private var previewImage: UIImage?
    @State private var previewDismissTimer: DispatchWorkItem?

    // Move photo to another subject
    @State private var showMoveImagePicker = false
    @State private var moveImageNumber: Int = 0
    @State private var moveSearchText = ""

    // Filters
    @State private var searchText = ""
    @State private var activeFilters: [String: Set<String>] = [:]  // field_key -> selected values (multiple fields, AND logic)
    @State private var sortField: String = "last_name"  // overridden in onAppear when shoot is sports
    @State private var showFilterPopover: Bool = false

    // Layout
    @State private var detailPanelVisible = true
    @State private var isLandscape = false

    // Settings
    @State private var showCaptureSettings = false

    // Add subject
    @State private var showingAddSubject = false

    // US Card scan flow
    @State private var showingUSCardQRScan = false
    @State private var usCardSubject: FPSubject?
    @State private var showingUSCardDocScan = false
    @State private var scanProcessing = false
    @State private var scanError: String?

    // Selection confirmation from Surface Pro
    @State private var confirmedSubjectId: String?
    @State private var confirmedSubjectName: String?

    // Move confirmation from Surface Pro
    @State private var moveConfirmationMessage: String?
    @State private var moveConfirmationIsError = false
    @State private var pendingMoveTimer: DispatchWorkItem?

    // Verification warning from Surface Pro
    @State private var verificationWarning: String?
    @State private var verificationSubjectId: String?
    @State private var verificationDismissTimer: DispatchWorkItem?

    // Sync
    @State private var showingSyncSheet = false

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Computed

    var galleryId: String {
        gallery.galleryId ?? gallery.id.uuidString.lowercased()
    }

    /// All possible filterable fields — dynamically shows any that have data
    static let allFilterFields: [(key: String, label: String)] = [
        ("last_name", "Last Name"),
        ("first_name", "First Name"),
        ("grade", "Grade"),
        ("teacher", "Teacher"),
        ("organization_name", "Organization"),
        ("homeroom", "Homeroom"),
        ("sport", "Sport"),
        ("email", "Email"),
        ("student_id", "Student ID"),
        ("roster_id", "Roster ID"),
        ("jersey_number", "Jersey #"),
        ("position", "Position"),
    ]

    /// Get unique non-empty values for a given field key
    func uniqueValues(for field: String) -> [String] {
        let values: [String] = subjects.compactMap { subject in
            let val = fieldValue(subject, field)
            return val.isEmpty ? nil : val
        }
        return Array(Set(values)).sorted()
    }

    /// Only show fields that actually have data in this gallery
    var availableFilterFields: [(key: String, label: String)] {
        let nonEmpty = Self.allFilterFields.filter { !uniqueValues(for: $0.key).isEmpty }
        // For sports galleries, hoist "Sport" to the top of the list — it's
        // the operator's primary segmentation (filter to football, basketball,
        // etc.) and shouldn't be buried mid-list.
        if gallery.shootType == "sports" {
            let sport = nonEmpty.filter { $0.key == "sport" }
            let rest = nonEmpty.filter { $0.key != "sport" }
            return sport + rest
        }
        return nonEmpty
    }

    /// Sort menu options. Sports adds Roster ID (at top, since it's the
    /// default and the operator's primary sort). Non-sports keeps the legacy
    /// list with Last Name as default.
    var sortOptions: [(String, String)] {
        if gallery.shootType == "sports" {
            return [
                ("roster_id", "Roster ID"),
                ("last_name", "Last Name"),
                ("first_name", "First Name"),
                ("grade", "Grade"),
            ]
        }
        return [
            ("last_name", "Last Name"),
            ("first_name", "First Name"),
            ("organization_name", "Organization"),
            ("grade", "Grade"),
            ("teacher", "Teacher"),
        ]
    }

    /// Count of subjects per value for a field
    func valueCounts(for field: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for subject in subjects {
            let val = fieldValue(subject, field)
            if !val.isEmpty { counts[val, default: 0] += 1 }
        }
        return counts
    }

    /// Get a subject's value for a given field key
    private func fieldValue(_ subject: FPSubject, _ field: String) -> String {
        switch field {
        case "first_name": return subject.firstName
        case "last_name": return subject.lastName
        case "grade": return subject.grade
        case "teacher": return subject.teacher
        case "organization_name": return subject.organizationName
        case "homeroom": return subject.homeroom
        case "sport": return subject.sport
        case "email": return subject.email
        case "student_id": return subject.studentId
        case "roster_id": return subject.rosterId
        case "jersey_number": return subject.jerseyNumber
        case "position": return subject.position
        default: return ""
        }
    }

    /// Three-way image-state filter shown as chips in the toolbar.
    /// `all` means no filter; `hasImages` and `noImages` apply on top
    /// of the existing filter and search. Same enum shape as FP Sports'
    /// ImageFilterType so behavior parity is exact.
    enum ImageFilterType {
        case all
        case hasImages
        case noImages
    }

    var hasActiveFilters: Bool {
        !activeFilters.isEmpty || !searchText.isEmpty || imageFilterType != .all
    }

    var filteredSubjects: [FPSubject] {
        var list = subjects
        // Apply all active filters (AND logic — must match every field)
        for (field, values) in activeFilters {
            if !values.isEmpty {
                list = list.filter { values.contains(fieldValue($0, field)) }
            }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.firstName.lowercased().contains(q) ||
                $0.lastName.lowercased().contains(q) ||
                $0.studentId.lowercased().contains(q) ||
                $0.rosterId.lowercased().contains(q) ||
                $0.organizationName.lowercased().contains(q)
            }
        }
        // Image-state filter — applied AFTER the field/search filters so
        // chip toggles compose with whatever else is active. Uses the
        // same shot-test as `shotCount` (line 282-ish) so a row counted
        // as "shot" for the filmstrip is also "shot" for this filter.
        switch imageFilterType {
        case .all:
            break
        case .hasImages:
            list = list.filter { subject in
                let sid = subject.id.uuidString.lowercased()
                return subject.isPhotographed || (photoCountMap[sid] ?? 0) > 0
            }
        case .noImages:
            list = list.filter { subject in
                let sid = subject.id.uuidString.lowercased()
                return !subject.isPhotographed && (photoCountMap[sid] ?? 0) == 0
            }
        }
        return list.sorted {
            // Blanks-last logic only applies when sorting BY a name field.
            // For roster_id (and other non-name sorts), the chosen sort key
            // is the source of truth — a blank-named subject with roster_id
            // "120" should appear between "119" and "121", not pushed to the
            // bottom. Only TRUE blanks (no name AND no value for the sort
            // key) sort last.
            let a_name_blank = $0.firstName.trimmingCharacters(in: .whitespaces).isEmpty && $0.lastName.trimmingCharacters(in: .whitespaces).isEmpty
            let b_name_blank = $1.firstName.trimmingCharacters(in: .whitespaces).isEmpty && $1.lastName.trimmingCharacters(in: .whitespaces).isEmpty

            switch sortField {
            case "first_name":
                if a_name_blank != b_name_blank { return !a_name_blank }
                return $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending
            case "organization_name":
                if a_name_blank != b_name_blank { return !a_name_blank }
                return $0.organizationName.localizedCaseInsensitiveCompare($1.organizationName) == .orderedAscending
            case "grade":
                if a_name_blank != b_name_blank { return !a_name_blank }
                return $0.grade < $1.grade
            case "teacher":
                if a_name_blank != b_name_blank { return !a_name_blank }
                return $0.teacher < $1.teacher
            case "roster_id":
                // Sort by roster_id regardless of name. Subjects with NO
                // roster_id go last. Numeric-aware compare so "2" < "10".
                let a_no_id = $0.rosterId.trimmingCharacters(in: .whitespaces).isEmpty
                let b_no_id = $1.rosterId.trimmingCharacters(in: .whitespaces).isEmpty
                if a_no_id != b_no_id { return !a_no_id }
                return $0.rosterId.compare($1.rosterId, options: .numeric) == .orderedAscending
            default:
                if a_name_blank != b_name_blank { return !a_name_blank }
                return $0.lastName.localizedCaseInsensitiveCompare($1.lastName) == .orderedAscending
            }
        }
    }

    var selectedSubject: FPSubject? {
        guard let id = selectedSubjectId else { return nil }
        return subjects.first { $0.id == id }
    }

    /// Subjects with actual names (excludes blanks from counts)
    var namedFilteredSubjects: [FPSubject] {
        filteredSubjects.filter { !$0.firstName.trimmingCharacters(in: .whitespaces).isEmpty || !$0.lastName.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var shotCount: Int {
        namedFilteredSubjects.filter { $0.isPhotographed || (photoCountMap[$0.id.uuidString.lowercased()] ?? 0) > 0 }.count
    }

    // MARK: - Filmstrip Segments

    var filmstripSegments: [FilmstripSegment] {
        subjectThumbnails
            .filter { !$0.value.isEmpty }
            .map { (sid, thumbs) in
                let subject = subjects.first { $0.id.uuidString.lowercased() == sid }
                let name = subject.map { "\($0.firstName) \($0.lastName)".trimmingCharacters(in: .whitespaces) } ?? "Unknown"
                return FilmstripSegment(
                    id: sid,
                    subjectName: name.isEmpty ? "Unnamed" : name,
                    photoCount: thumbs.count,
                    thumbnails: thumbs
                )
            }
            .sorted { ($0.thumbnails.last?.imageNumber ?? 0) > ($1.thumbnails.last?.imageNumber ?? 0) }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
        VStack(spacing: 0) {
            headerBar
            // Tab selector between the roster and group photos. Groups
            // map to team/squad photos for sports, class groups for
            // spring / underclass portraits, clubs for events, etc. The
            // selector renders for every shoot type — the AddGroupImageView
            // form adapts its fields based on shootType so non-sports
            // shoots get a simpler create/edit flow.
            groupsTabSelector

            if selectedTab == 1 {
                groupsView
            } else {
            filterBar

            if isLoading {
                ProgressView("Loading roster...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    subjectList
                        .frame(maxWidth: .infinity)

                    if detailPanelVisible {
                        Rectangle().fill(Color(.separator)).frame(width: 1)
                    }

                    if detailPanelVisible, let subject = selectedSubject {
                        let lockerName = lockedEntries[subject.id]
                        let isLockedByOther = lockerName != nil && lockerName != lockManager.currentEditorIdentifier
                        SubjectDetailPanel(
                            subject: subject,
                            thumbnails: subjectThumbnails[subject.id.uuidString.lowercased()] ?? [],
                            photoCount: photoCountMap[subject.id.uuidString.lowercased()] ?? 0,
                            galleryId: galleryId,
                            isSports: gallery.shootType == "sports",
                            isLockedByOther: isLockedByOther,
                            lockedByName: lockerName,
                            onSave: { updated in saveSubject(updated) },
                            onSelect: { selectOnCamera(subject) },
                            onViewPhotos: { name, thumbs in
                                photoViewerSubjectName = name
                                photoViewerSubjectId = subject.id.uuidString.lowercased()
                                photoViewerThumbs = thumbs
                                showPhotoViewer = true
                            }
                        )
                        .frame(width: isLandscape ? 320 : 360)
                    } else if detailPanelVisible {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.rectangle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Select a student")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxHeight: .infinity)
                        .frame(width: isLandscape ? 320 : 360)
                        .background(Color(.secondarySystemBackground))
                    }

                    // Filmstrip — landscape only
                    if isLandscape {
                        Rectangle().fill(Color(.separator)).frame(width: 1)
                        CaptureFilmstripPanel(
                            segments: filmstripSegments,
                            activeSubjectName: selectedSubject.map { "\($0.firstName) \($0.lastName)".trimmingCharacters(in: .whitespaces) },
                            onTapPhoto: { subjectId, name, thumbs in
                                photoViewerSubjectId = subjectId
                                photoViewerSubjectName = name
                                photoViewerThumbs = thumbs
                                showPhotoViewer = true
                            },
                            onMoveImage: { fromSubjectId, toSubjectId, imageNumber in
                                // Send move request to Production via WebSocket
                                fpSync.sendMoveCapture(
                                    imageNumber: imageNumber,
                                    fromSubjectId: fromSubjectId,
                                    toSubjectId: toSubjectId,
                                    fromRosterEntryId: fromSubjectId,
                                    toRosterEntryId: toSubjectId
                                )
                                // Move thumbnail locally for instant UI update
                                if var fromThumbs = subjectThumbnails[fromSubjectId] {
                                    if let idx = fromThumbs.firstIndex(where: { $0.imageNumber == imageNumber }) {
                                        let moved = fromThumbs.remove(at: idx)
                                        subjectThumbnails[fromSubjectId] = fromThumbs.isEmpty ? nil : fromThumbs
                                        var toThumbs = subjectThumbnails[toSubjectId] ?? []
                                        toThumbs.append(moved)
                                        subjectThumbnails[toSubjectId] = toThumbs
                                    }
                                }
                                // Start 5-second timeout for confirmation
                                pendingMoveTimer?.cancel()
                                let timer = DispatchWorkItem {
                                    if moveConfirmationMessage == nil {
                                        moveConfirmationMessage = "Move failed — no confirmation from Surface Pro"
                                        moveConfirmationIsError = true
                                        let generator = UINotificationFeedbackGenerator()
                                        generator.notificationOccurred(.error)
                                    }
                                }
                                pendingMoveTimer = timer
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timer)
                            }
                        )
                        .transition(.move(edge: .trailing))
                    }
                }
            }
            } // Roster-tab branch (else of groupsView)
        }
        .onChange(of: geo.size) { newSize in
            withAnimation(.easeInOut(duration: 0.25)) {
                let screen = UIScreen.main.bounds
                isLandscape = screen.width > screen.height
            }
        }
        .onAppear {
            let screen = UIScreen.main.bounds
            isLandscape = screen.width > screen.height
            // For sports galleries, default the sort to Roster ID. The
            // operator's primary mental model on a sports shoot is "next
            // jersey number up," not alphabetical name. Only flips on
            // first appear so a manual sort change persists if the user
            // navigates away and back.
            if gallery.shootType == "sports" && sortField == "last_name" {
                sortField = "roster_id"
            }
        }
        } // GeometryReader
        .navigationTitle("")
        .navigationBarHidden(true)
        .task {
            // Pin the gallery so PowerSync syncs its subjects to this user's device.
            // Matches the pattern used by FPSportsRosterView_iPad and the Production
            // app's sync_gallery. Without this, users who haven't previously opened
            // this gallery (via Production or FP Sports) get an empty roster.
            if let userIdString = UserManager.shared.getCurrentUserIDUnified() {
                try? await powerSync.pinGallery(
                    userId: userIdString,
                    galleryId: galleryId,
                    organizationId: storedUserOrganizationID
                )
                // Initialize the lock manager so any acquire/release call
                // from the SubjectDetailPanel's focus handler has a user
                // identity to attach. Mirrors FPSportsRosterView_iPad's
                // setup at line 1364 — UUID from Supabase auth, name
                // from the @AppStorage first/last name pair.
                if let authUUID = SupabaseManager.shared.client.auth.currentUser?.id {
                    let fullName = "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespaces)
                    LockManager.shared.setCurrentUser(
                        userId: authUUID,
                        userName: fullName.isEmpty ? userIdString : fullName
                    )
                }
            }
            await loadSubjects()
            await loadCachedThumbnails()
            startWatching()
            setupSyncCallbacks()
            // Prime the groups list and clear any stale locks from a
            // previous session for every shoot type — class groups and
            // clubs live inside spring / underclass galleries too.
            await loadGroupImages()
            startWatchingGroups()
            try? await GroupImageService.shared.releaseExpiredLocks(forJob: gallery.id)
        }
        .onDisappear {
            subjectWatchTask?.cancel()
            groupWatchTask?.cancel()
            // Null the group-photo fpSync callbacks we installed in
            // setupSyncCallbacks. FocalPointSyncClient is a process-wide
            // singleton — if we leave our closures assigned, a later firing
            // of the WS event mutates @State on a view that's gone, and
            // whatever view appears next inherits stale handlers. Subject
            // callbacks aren't nulled here because they predate this file
            // and their lifecycle has been stable; groups are new plumbing
            // we own end-to-end.
            fpSync.onGroupPhotoReady = nil
            fpSync.onGroupCaptureCompleted = nil
            fpSync.onGroupUpdated = nil
            fpSync.onGroupDeleted = nil
            // End any in-flight inline image-# edit so the value the
            // user typed gets persisted and the lock gets released
            // before the view goes away.
            endEditingImageNumber()
            // Flush any pending capture-driven saves so burst-shoot-then-
            // leave doesn't lose the trailing image numbers. Same pattern
            // for subjects and groups.
            for (entryId, task) in pendingCaptureSaves {
                task.cancel()
                if let latest = subjects.first(where: { $0.id == entryId }) {
                    saveSubject(latest)
                }
            }
            pendingCaptureSaves.removeAll()
            for (groupId, task) in pendingGroupCaptureSaves {
                task.cancel()
                if let latest = groupImages.first(where: { $0.id == groupId }) {
                    saveGroupImage(latest)
                }
            }
            pendingGroupCaptureSaves.removeAll()
        }
        .onChange(of: scenePhase) { newPhase in
            // Same flush on app backgrounding (home button, lock, switcher).
            // iOS may suspend the debounce Task before it fires.
            if newPhase != .active {
                for (entryId, task) in pendingCaptureSaves {
                    task.cancel()
                    if let latest = subjects.first(where: { $0.id == entryId }) {
                        saveSubject(latest)
                    }
                }
                pendingCaptureSaves.removeAll()
                for (groupId, task) in pendingGroupCaptureSaves {
                    task.cancel()
                    if let latest = groupImages.first(where: { $0.id == groupId }) {
                        saveGroupImage(latest)
                    }
                }
                pendingGroupCaptureSaves.removeAll()
                // End any in-flight inline image-# edit so the value
                // persists before iOS suspends the app.
                endEditingImageNumber()
            }
        }
        .onChange(of: lockManager.lockLostEvent?.id) { _ in
            // Lock yanked out from under us — likely another device
            // grabbed it after our TTL or via the takenByOtherUser path.
            // Save whatever's in the buffer (better than dropping the
            // user's typing) and unwind the edit state.
            if let lost = lockManager.lockLostEvent,
               currentlyEditingEntry == lost.entryId {
                saveCurrentEditingEntry()
                currentlyEditingEntry = nil
                editingImageNumber = ""
                originalImageNumber = ""
            }
        }
        .sheet(isPresented: $showingSyncSheet) { syncSheet }
        .sheet(isPresented: $showCaptureSettings) { captureSettingsSheet }
        .sheet(isPresented: $showingAddSubject) { addSubjectSheet }
        .sheet(isPresented: $showingUSCardQRScan) { usCardQRSheet }
        .sheet(isPresented: $showingUSCardDocScan) { usCardDocScanSheet }
        .sheet(isPresented: $showingAddGroupImage, onDismiss: {
            // Sheet dismissed — whether saved or cancelled, clear the edit
            // pointer so a subsequent "+ Add Group" tap starts fresh.
            selectedGroupImage = nil
        }) {
            AddGroupImageView(
                shootID: gallery.id,
                organizationId: storedUserOrganizationID,
                existingGroup: selectedGroupImage,
                shootType: gallery.shootType ?? ""
            ) { _ in
                showingAddGroupImage = false
                // PowerSync watch stream will refresh groupImages on its
                // own — no manual reload needed.
            }
        }
        .overlay(alignment: .top) {
            if let error = scanError {
                Text(error)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(error.contains("on-device") ? Color.orange : Color.red)
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            withAnimation { scanError = nil }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            CapturePhotoViewer(
                subjectName: photoViewerSubjectName,
                thumbs: photoViewerThumbs,
                isPresented: $showPhotoViewer,
                onMoveRequested: fpSync.isConnected ? { imageNumber in
                    moveImageNumber = imageNumber
                    moveSearchText = ""
                    showMoveImagePicker = true
                } : nil
            )
        }
        .overlay {
            // Capture preview popup — shows non-card photos for 3 seconds
            if let img = previewImage {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        previewDismissTimer?.cancel()
                        withAnimation(.easeInOut(duration: 0.2)) { previewImage = nil }
                    }
                    .overlay {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 20)
                            .padding(40)
                            .transition(.opacity)
                    }
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showMoveImagePicker) {
            NavigationView {
                List {
                    let filtered = subjects.filter { entry in
                        guard entry.id.uuidString.lowercased() != photoViewerSubjectId else { return false }
                        if moveSearchText.isEmpty { return true }
                        let q = moveSearchText.lowercased()
                        return entry.firstName.lowercased().contains(q)
                            || entry.lastName.lowercased().contains(q)
                            || entry.rosterId.lowercased().contains(q)
                    }
                    ForEach(filtered) { entry in
                        Button(action: {
                            let targetId = entry.id.uuidString.lowercased()
                            fpSync.sendMoveCapture(
                                imageNumber: moveImageNumber,
                                fromSubjectId: photoViewerSubjectId,
                                toSubjectId: targetId,
                                fromRosterEntryId: photoViewerSubjectId,
                                toRosterEntryId: targetId
                            )
                            // Move thumbnail locally for instant UI update
                            if var fromThumbs = subjectThumbnails[photoViewerSubjectId] {
                                if let idx = fromThumbs.firstIndex(where: { $0.imageNumber == moveImageNumber }) {
                                    let moved = fromThumbs.remove(at: idx)
                                    subjectThumbnails[photoViewerSubjectId] = fromThumbs.isEmpty ? nil : fromThumbs
                                    var toThumbs = subjectThumbnails[targetId] ?? []
                                    toThumbs.append(moved)
                                    subjectThumbnails[targetId] = toThumbs
                                }
                            }
                            // Start timeout — if no confirmation in 5 seconds, show failure
                            pendingMoveTimer?.cancel()
                            let timer = DispatchWorkItem {
                                if moveConfirmationMessage == nil {
                                    moveConfirmationMessage = "Move failed — no confirmation from Surface Pro"
                                    moveConfirmationIsError = true
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.error)
                                }
                            }
                            pendingMoveTimer = timer
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timer)
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
                                if !entry.grade.isEmpty {
                                    Text(entry.grade)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .searchable(text: $moveSearchText, prompt: "Search subjects")
                .navigationTitle("Move Image #\(moveImageNumber) to...")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { showMoveImagePicker = false }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gallery.schoolName)
                        .font(.headline).fontWeight(.bold)
                    Text("\(shotCount) of \(namedFilteredSubjects.count) photographed")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()

                Button(action: { showingUSCardQRScan = true }) {
                    Label("Scan US Card", systemImage: "qrcode.viewfinder")
                        .font(.subheadline).fontWeight(.medium)
                }
                .buttonStyle(.bordered).tint(.orange)

                Button(action: { showingAddSubject = true }) {
                    Label("Add Student", systemImage: "person.badge.plus")
                        .font(.subheadline).fontWeight(.medium)
                }
                .buttonStyle(.bordered).tint(.blue)

                // Toggle detail panel
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { detailPanelVisible.toggle() } }) {
                    Image(systemName: detailPanelVisible ? "sidebar.trailing" : "sidebar.leading")
                        .font(.title3).foregroundColor(.secondary)
                }
                .frame(width: 44, height: 44)

                // Capture settings
                Button(action: { showCaptureSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(width: 44, height: 44)

                // Paired station battery level
                if let pairedId = fpSync.pairedCameraId,
                   let pairedDevice = fpSync.devices.first(where: { $0.id == pairedId }),
                   let level = pairedDevice.batteryLevel {
                    HStack(spacing: 2) {
                        Image(systemName: batteryIconName(level: level, charging: pairedDevice.batteryCharging ?? false))
                            .font(.system(size: 12))
                            .foregroundColor(batteryColor(level: level))
                        Text("\(level)%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(batteryColor(level: level))
                    }
                }

                Button(action: { showingSyncSheet = true }) {
                    Image(systemName: fpSync.isConnected ? "wifi" : "wifi.slash")
                        .font(.title3)
                        .foregroundColor(fpSync.isConnected ? .green : .secondary)
                }
                .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)

            // Progress bar
            GeometryReader { geo in
                let progress = namedFilteredSubjects.isEmpty ? 0.0 : Double(shotCount) / Double(namedFilteredSubjects.count)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(.systemGray5)).frame(height: 4)
                    Rectangle().fill(Color.green).frame(width: geo.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Filter Bar

    /// Toolbar chip for an image-state filter. Active state uses the
    /// same blue tint as the Filter button so the toolbar treats them
    /// as part of the same filter family.
    @ViewBuilder
    private func imageStateChip(label: String, systemImage: String, isActive: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption)
                Text(label).font(.subheadline)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isActive ? Color.blue.opacity(0.12) : Color(.systemGray6))
            .foregroundColor(isActive ? .blue : .primary)
            .cornerRadius(8)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain).font(.subheadline)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(.systemGray6)).cornerRadius(8)
                .frame(width: 180)

                // Filter — popover stays open for multi-select
                Button(action: { showFilterPopover.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease").font(.caption)
                        Text("Filter").font(.subheadline)
                        if !activeFilters.isEmpty {
                            Text("\(activeFilters.count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(99)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(!activeFilters.isEmpty ? Color.blue.opacity(0.12) : Color(.systemGray6))
                    .foregroundColor(!activeFilters.isEmpty ? .blue : .primary)
                    .cornerRadius(8)
                }
                .popover(isPresented: $showFilterPopover) {
                    filterPopoverContent
                        .frame(width: 320, height: 600)
                }

                // Sort. Sports gets Roster ID at the top of the list (and
                // it's the default — set in .onAppear). Non-sports keeps
                // Last Name as the default and doesn't expose Roster ID.
                Menu {
                    ForEach(sortOptions, id: \.0) { key, label in
                        Button(action: { sortField = key }) {
                            Label(label, systemImage: sortField == key ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down").font(.caption)
                        Text("Sort").font(.subheadline)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }

                // Image-state chips: tap once to filter to that state,
                // tap again to clear. Mutually exclusive — picking one
                // resets the other to .all. Mirrors FP Sports'
                // ImageFilterButton behavior in the FilterPanelView.
                imageStateChip(
                    label: "Has Photos",
                    systemImage: "photo.fill",
                    isActive: imageFilterType == .hasImages,
                    onTap: { imageFilterType = imageFilterType == .hasImages ? .all : .hasImages }
                )
                imageStateChip(
                    label: "No Photos",
                    systemImage: "photo",
                    isActive: imageFilterType == .noImages,
                    onTap: { imageFilterType = imageFilterType == .noImages ? .all : .noImages }
                )

                if hasActiveFilters {
                    Button("Clear") {
                        activeFilters.removeAll()
                        searchText = ""
                        imageFilterType = .all
                    }
                    .font(.subheadline).foregroundColor(.red)
                }

                Spacer()

                Text("\(filteredSubjects.count) student\(filteredSubjects.count == 1 ? "" : "s")")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(.separator)), alignment: .bottom)
    }

    // MARK: - Groups Tab (sports only)

    /// Segmented picker between Roster and Groups. Shown only on sports
    /// galleries — non-sports shoots never have groups. No bottom
    /// separator here because the downstream content (filterBar on the
    /// Roster tab, groupsView's header bar on the Groups tab) already
    /// owns its own top-of-content separator; adding one here creates a
    /// doubled 1pt line.
    private var groupsTabSelector: some View {
        Picker("", selection: $selectedTab) {
            Text("Roster").tag(0)
            Text("Groups").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    /// Full Groups-tab content — header bar with count and Add button,
    /// then the list of groups or an empty state. Edit/delete happen
    /// through tap (opens AddGroupImageView) and context menu respectively.
    /// Expands to fill the remaining vertical space in the parent VStack
    /// so the empty state and the scrollable list both anchor correctly.
    private var groupsView: some View {
        VStack(spacing: 0) {
            // Header bar — count + Add Group button.
            HStack {
                Text("\(groupImages.count) group\(groupImages.count == 1 ? "" : "s")")
                    .font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Button {
                    selectedGroupImage = nil
                    showingAddGroupImage = true
                } label: {
                    Label("Add Group", systemImage: "person.3.fill")
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color(.systemBackground))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color(.separator)), alignment: .bottom)

            if groupImages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No groups yet")
                        .font(.headline).foregroundColor(.secondary)
                    Text("Tap Add Group to create your first group.")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(groupImages.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { group in
                            groupRow(group)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Single group row — name + metadata badges + image-number pill +
    /// optional lock badge (when another user is editing). Tap to edit,
    /// context-menu delete.
    private func groupRow(_ group: GroupImage) -> some View {
        let currentUser = UserManager.shared.getCurrentUserIDUnified()
        let lockedByOther: Bool = {
            guard let lockedBy = group.lockedBy else { return false }
            guard let currentUser = currentUser else { return true }
            return lockedBy.uuidString.lowercased() != currentUser.lowercased()
        }()

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.description.isEmpty ? "(Unnamed group)" : group.description)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)

                // Metadata badges — sport gets the same size-9 bold
                // UPPERCASE colored badge as the subject row so the
                // visual grammar is identical across tabs. teamLevel
                // and gender stay as plain secondary text.
                HStack(spacing: 6) {
                    if !group.sport.isEmpty {
                        Text(group.sport.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(sportBadgeColor(group.sport))
                            .cornerRadius(4)
                    }
                    if !group.teamLevel.isEmpty {
                        Text(group.teamLevel)
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if !group.gender.isEmpty {
                        Text(group.gender)
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if !group.imageNumbers.isEmpty {
                Text(group.imageNumbers)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(6)
            } else {
                Text("No photos")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        // Lock-by-other badge floats top-trailing as an overlay —
        // matches the subject row's teacher badge placement so state
        // alerts live in the same visual slot across both tabs.
        .overlay(alignment: .topTrailing) {
            if lockedByOther, let name = group.lockedByName, !name.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text(name).font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange)
                .cornerRadius(4)
                .padding(.top, 6)
                .padding(.trailing, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedGroupImage = group
            showingAddGroupImage = true
        }
        .contextMenu {
            // Primary action first — iOS convention — even though tapping
            // the row also opens edit, having it in the menu aids
            // discoverability.
            Button {
                selectedGroupImage = group
                showingAddGroupImage = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: { deleteGroup(group) }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Subject List

    private var subjectList: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Confirmation banner — shows when Surface Pro confirms subject selection
                if let name = confirmedSubjectName {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .bold))
                        Text("Selected on Camera: \(name)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: confirmedSubjectName)
                }

                // Move confirmation banner
                if let msg = moveConfirmationMessage {
                    HStack(spacing: 8) {
                        Image(systemName: moveConfirmationIsError ? "exclamationmark.circle.fill" : "arrow.right.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .bold))
                        Text(msg)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { moveConfirmationMessage = nil }) {
                            Image(systemName: "xmark").foregroundColor(.white.opacity(0.8)).font(.caption)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(moveConfirmationIsError ? Color.red : Color.blue)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: moveConfirmationMessage)
                }

                // Verification warning banner
                if let warning = verificationWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .bold))
                        Text(warning)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            verificationDismissTimer?.cancel()
                            if let sid = verificationSubjectId { fpSync.sendVerificationResponse(subjectId: sid, confirmed: true) }
                            verificationWarning = nil
                            verificationSubjectId = nil
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill.checkmark")
                                    .font(.system(size: 12))
                                Text("Same Subject")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.25))
                            .cornerRadius(6)
                        }
                        Button(action: {
                            verificationDismissTimer?.cancel()
                            if let sid = verificationSubjectId { fpSync.sendVerificationResponse(subjectId: sid, confirmed: false) }
                            verificationWarning = nil
                            verificationSubjectId = nil
                        }) {
                            Image(systemName: "xmark").foregroundColor(.white.opacity(0.8)).font(.caption)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: verificationWarning)
                }

                List {
                    ForEach(filteredSubjects) { subject in
                        subjectRow(subject)
                    }
                }
                .listStyle(.plain)
            }
            .onChange(of: scrollTargetId) { target in
                if let target = target {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    scrollTargetId = nil
                }
            }
        }
    }

    @ViewBuilder
    private func subjectRow(_ subject: FPSubject) -> some View {
        let sid = subject.id.uuidString.lowercased()
        let isSelected = selectedSubjectId == subject.id
        let isActive = activeSubjectId == sid
        let hasPhotos = subject.isPhotographed || (photoCountMap[sid] ?? 0) > 0
        let latestThumb = subjectThumbnails[sid]?.last?.image
        let count = photoCountMap[sid] ?? 0
        let isSports = gallery.shootType == "sports"

        HStack(spacing: 12) {
            if let thumb = latestThumb {
                Image(uiImage: thumb)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(initialsDisplay(subject))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                if isSports {
                    // Sport as a small badge above the name line. Color is
                    // a deterministic hash of the sport name (same algorithm
                    // FP Sports view uses) so "Football" is always the same
                    // color across views and across app launches.
                    if !subject.sport.isEmpty {
                        Text(subject.sport.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(sportBadgeColor(subject.sport))
                            .cornerRadius(4)
                    }
                    Text(sportsPrimaryLine(subject))
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    Text(primaryDisplay(subject))
                        .font(.system(size: 16, weight: .semibold))
                    let info = secondaryDisplay(subject)
                    if !info.isEmpty {
                        Text(info).font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            if subject.isAbsent {
                Text("ABSENT").font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red).cornerRadius(4)
            }
            if subject.needsRetake {
                Text("RETAKE").font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange).cornerRadius(4)
            }
            // Lock badge — visible when another device holds the
            // subject's lock. Lets the operator see at a glance which
            // rows are being edited elsewhere without opening the panel.
            if let locker = lockedEntries[subject.id], locker != lockManager.currentEditorIdentifier {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text(locker).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange)
                .cornerRadius(4)
            }

            Spacer()

            if !detailPanelVisible && !isSports {
                if !subject.grade.isEmpty { Text(subject.grade).font(.caption).foregroundColor(.secondary) }
                if !subject.teacher.isEmpty { Text(subject.teacher).font(.caption).foregroundColor(.secondary) }
            }

            if count > 0 {
                Text("+\(count)").font(.caption).fontWeight(.bold)
                    .foregroundColor(.green).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.green.opacity(0.12)).cornerRadius(99)
            }

            // Sports: inline image-number cell next to the count chip.
            // Either a tap-to-edit display of the current imageNumbers
            // value, or an AutosaveTextField when this row is in edit
            // mode. Shape mirrors FP Sports: 120pt wide, blue 0.25
            // background, 16pt medium so the operator recognizes it as
            // the same control they use in FP Sports.
            if isSports {
                let isCurrentlyEditing = currentlyEditingEntry == subject.id
                let lockedByOther = lockedEntries[subject.id] != nil
                    && lockedEntries[subject.id] != lockManager.currentEditorIdentifier
                if isCurrentlyEditing {
                    AutosaveTextField(
                        text: $editingImageNumber,
                        placeholder: "Image #",
                        context: "\(subject.firstName) - \(subject.lastName)",
                        onTapOutside: { endEditingImageNumber() },
                        onEnterOrDown: {
                            saveCurrentEditingEntry()
                            moveToNextEditableEntry(currentID: subject.id)
                        },
                        onEnterOrUp: {
                            saveCurrentEditingEntry()
                            moveToPreviousEditableEntry(currentID: subject.id)
                        }
                    )
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 120, height: 36)
                    .multilineTextAlignment(.center)
                    .background(Color.blue.opacity(0.25))
                    .cornerRadius(8)
                } else {
                    Button(action: { startEditingImageNumber(subject) }) {
                        Text(subject.imageNumbers.isEmpty ? "Image #" : subject.imageNumbers)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 120, height: 32)
                            .multilineTextAlignment(.center)
                            .background(Color.blue.opacity(lockedByOther ? 0.08 : 0.15))
                            .foregroundColor(subject.imageNumbers.isEmpty ? Color(.systemGray2) : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.borderless)
                    .disabled(lockedByOther)
                }
            }

            if hasPhotos {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.green.opacity(0.12) :
                      isSelected ? Color.blue.opacity(0.08) :
                      subject.isAbsent ? Color.red.opacity(0.04) :
                      Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.green.opacity(0.4) :
                        isSelected ? Color.blue.opacity(0.3) :
                        Color.clear, lineWidth: 2)
        )
        // Sports: teacher dropdown floats in the top-right corner of the row.
        // Tap to set the sports code (None / Coach / Senior / 8th Grader)
        // inline without opening the detail panel — the most frequent edit
        // during a sports shoot. Empty-state shows a tag icon so operators
        // can set a code on subjects that don't have one yet. Menu consumes
        // the tap so the row's subject-select gesture does not fire.
        .overlay(alignment: .topTrailing) {
            if isSports {
                Menu {
                    Button("— None") { updateTeacherCode(subject, value: "") }
                    Button("C — Coach") { updateTeacherCode(subject, value: "c") }
                    Button("S — Senior") { updateTeacherCode(subject, value: "s") }
                    Button("8 — 8th Grader") { updateTeacherCode(subject, value: "8") }
                } label: {
                    if subject.teacher.isEmpty {
                        Image(systemName: "tag")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    } else {
                        Text(decodeSportsTeacherCodeShort(subject.teacher).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(sportsTeacherBadgeColor(subject.teacher))
                            .cornerRadius(4)
                    }
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                .padding(.top, 2)
                .padding(.trailing, 4)
            }
        }
        .opacity(subject.isAbsent ? 0.4 : (hasPhotos && !isSelected && !isActive ? 0.5 : 1.0))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSubjectId = subject.id
            confirmedSubjectId = nil
            confirmedSubjectName = nil
            if autoSelectEnabled && fpSync.isConnected && fpSync.pairedCameraId != nil {
                selectOnCamera(subject)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(subject.isAbsent ? "Present" : "Absent") {
                toggleAbsent(subject)
            }
            .tint(subject.isAbsent ? .green : .red)
        }
        .id(subject.id)
    }

    // MARK: - Helpers

    // Parse display_config JSON or fall back to shoot_type defaults
    private var displayPrimary: String {
        if let json = gallery.displayConfig, let data = json.data(using: .utf8),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let primary = config["primary"], !primary.isEmpty { return primary }
        let st = gallery.shootType ?? ""
        if st == "events" || st == "event" { return "organization_name" }
        if st == "faculty" { return "name" }
        return "name"
    }

    private var displaySecondary: String {
        if let json = gallery.displayConfig, let data = json.data(using: .utf8),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let secondary = config["secondary"], !secondary.isEmpty { return secondary }
        let st = gallery.shootType ?? ""
        if st == "events" || st == "event" { return "name" }
        if st == "faculty" { return "title" }
        return "grade_teacher"
    }

    private func resolveField(_ subject: FPSubject, _ key: String) -> String {
        switch key {
        case "name":
            let n = "\(subject.firstName) \(subject.lastName)".trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? (subject.rosterId.isEmpty ? "(no name)" : subject.rosterId) : n
        case "roster_name":
            let prefix = subject.rosterId.isEmpty ? "" : "\(subject.rosterId) "
            return "\(prefix)\(subject.firstName) \(subject.lastName)".trimmingCharacters(in: .whitespaces)
        case "organization_name": return subject.organizationName.isEmpty ? "(no org)" : subject.organizationName
        case "grade_teacher": return subjectInfo(subject)
        case "sport": return subject.sport
        case "grade": return subject.grade
        case "teacher": return subject.teacher
        case "email": return subject.email
        case "title": return subject.homeroom // title maps to homeroom field
        case "homeroom": return subject.homeroom
        case "student_id": return subject.studentId
        case "roster_id": return subject.rosterId
        default: return ""
        }
    }

    /// Sports card primary line: "[123] First Last" or "First Last" if no roster id.
    private func sportsPrimaryLine(_ subject: FPSubject) -> String {
        let name = "\(subject.firstName) \(subject.lastName)".trimmingCharacters(in: .whitespaces)
        if !subject.rosterId.isEmpty {
            return "[\(subject.rosterId)] \(name)"
        }
        return name.isEmpty ? "(unnamed)" : name
    }

    private func primaryDisplay(_ subject: FPSubject) -> String {
        return resolveField(subject, displayPrimary)
    }

    private func secondaryDisplay(_ subject: FPSubject) -> String {
        let value = resolveField(subject, displaySecondary)
        // If secondary is "name" and primary is also name-based, add teacher
        if displaySecondary == "name" && displayPrimary != "name" && !subject.teacher.isEmpty {
            return value.isEmpty ? subject.teacher : "\(value) \u{00B7} \(subject.teacher)"
        }
        return value
    }

    private func initialsDisplay(_ subject: FPSubject) -> String {
        let primary = resolveField(subject, displayPrimary)
        let words = primary.split(separator: " ")
        if words.count >= 2 { return "\(words[0].prefix(1))\(words[1].prefix(1))" }
        return String(primary.prefix(2)).uppercased()
    }

    private func subjectInfo(_ subject: FPSubject) -> String {
        if !subject.homeroom.isEmpty { return subject.homeroom }
        var parts: [String] = []
        if !subject.grade.isEmpty { parts.append(subject.grade) }
        if !subject.teacher.isEmpty { parts.append(subject.teacher) }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Filter Popover

    private var filterPopoverContent: some View {
        NavigationView {
            List {
                ForEach(availableFilterFields, id: \.key) { field in
                    let selected = activeFilters[field.key] ?? []
                    let valueCount = uniqueValues(for: field.key).count
                    NavigationLink {
                        filterFieldDetail(field: field)
                    } label: {
                        HStack {
                            Text(field.label)
                                .foregroundColor(.primary)
                            Spacer()
                            if !selected.isEmpty {
                                Text("\(selected.count) of \(valueCount)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            } else {
                                Text("\(valueCount)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !activeFilters.isEmpty {
                        Button("Clear All") { activeFilters.removeAll() }
                            .foregroundColor(.red)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showFilterPopover = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func filterFieldDetail(field: (key: String, label: String)) -> some View {
        let values = uniqueValues(for: field.key)
        let counts = valueCounts(for: field.key)
        let selected = activeFilters[field.key] ?? []

        return List {
            ForEach(values, id: \.self) { value in
                Button(action: {
                    var current = activeFilters[field.key] ?? []
                    if current.contains(value) {
                        current.remove(value)
                        if current.isEmpty { activeFilters.removeValue(forKey: field.key) }
                        else { activeFilters[field.key] = current }
                    } else {
                        current.insert(value)
                        activeFilters[field.key] = current
                    }
                }) {
                    HStack {
                        Image(systemName: selected.contains(value) ? "checkmark.square.fill" : "square")
                            .foregroundColor(selected.contains(value) ? .blue : .secondary)
                        Text(value)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(counts[value] ?? 0)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(field.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(selected.count == values.count ? "None" : "All") {
                    if selected.count == values.count {
                        activeFilters.removeValue(forKey: field.key)
                    } else {
                        activeFilters[field.key] = Set(values)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleAbsent(_ subject: FPSubject) {
        var updated = subject
        updated.isAbsent = !subject.isAbsent
        updated.updatedAt = Date()
        Task {
            do {
                try await powerSync.saveSubject(updated)
                let sid = subject.id.uuidString.lowercased()
                fpSync.markSubjectAbsent(subjectId: sid, rosterEntryId: nil, isAbsent: updated.isAbsent)
            } catch { print("Toggle absent failed: \(error)") }
        }
    }

    /// Inline teacher-code update from the per-row dropdown. Writes the
    /// short sports code ("c" / "s" / "8") or empty to clear, then routes
    /// through the standard save path so PowerSync + Surface broadcast
    /// both pick it up. Lowercase matches the SIS-import canonical form
    /// documented in SportsCodes.swift; decoders are case-insensitive so
    /// mixed-case legacy values from FP Sports also render correctly.
    /// Re-reads from the live `subjects` array before mutating so a
    /// capture-driven watch update that landed between render and tap
    /// cannot be overwritten with a stale `imageNumbers` value.
    private func updateTeacherCode(_ subject: FPSubject, value: String) {
        guard let idx = subjects.firstIndex(where: { $0.id == subject.id }) else { return }
        var updated = subjects[idx]
        updated.teacher = value
        updated.updatedAt = Date()
        saveSubject(updated)
    }

    private func triggerCaptureHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func selectOnCamera(_ subject: FPSubject) {
        let sid = subject.id.uuidString.lowercased()
        activeSubjectId = sid
        fpSync.selectSubject(subjectId: sid, rosterEntryId: nil, subjectName: "\(subject.firstName) \(subject.lastName)")
    }

    /// Schedule a per-subject debounced save for capture-driven imageNumbers
    /// updates. Cancels any in-flight task for the same subject; the latest
    /// in-memory state is what eventually saves. Burst captures all share
    /// the same trailing save.
    private func scheduleCaptureSave(for entryId: UUID) {
        pendingCaptureSaves[entryId]?.cancel()
        pendingCaptureSaves[entryId] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if Task.isCancelled { return }
            if let latest = subjects.first(where: { $0.id == entryId }) {
                saveSubject(latest)
            }
            pendingCaptureSaves[entryId] = nil
        }
    }

    private func saveSubject(_ updated: FPSubject) {
        // Update in-memory list immediately so the UI reflects the change.
        if let idx = subjects.firstIndex(where: { $0.id == updated.id }) {
            subjects[idx] = updated
        }
        // Always write to local PowerSync for durability — even when Surface
        // is connected. Previously skipped to avoid "dual-write race", but the
        // audit caught a data-loss case: if Surface receives the broadcast but
        // crashes before its Supabase write commits AND the iPad subsequently
        // goes offline, the edit is permanently lost. PowerSync handles the
        // dual-upload via last-write-wins on updated_at.
        Task {
            do {
                try await powerSync.saveSubject(updated)
            } catch {
                print("Save subject failed: \(error)")
            }
            // Best-effort broadcast — fast UI sync to Surface independent of
            // the cloud round-trip.
            await MainActor.run { fpSync.sendSubjectFullUpdate(updated) }
        }
    }

    // MARK: - Inline image-number editing

    /// Begin inline editing of `subject`'s image-numbers cell. Acquires
    /// the subject lock first so two devices can't edit simultaneously
    /// (acquisition is async — if it fails, surface a toast and bail).
    /// If a previous row was being edited, save it before switching.
    private func startEditingImageNumber(_ subject: FPSubject) {
        // Locked by another editor — refuse and tell the user.
        if let editor = lockedEntries[subject.id], editor != lockManager.currentEditorIdentifier {
            // Use the existing scanError overlay to surface the message
            // (same pattern QR-scan errors already use, so the toast
            // styling and dismiss timing are familiar to operators).
            scanError = "Locked by \(editor)"
            return
        }
        // Save and end any prior in-flight inline edit first.
        if let priorId = currentlyEditingEntry, priorId != subject.id {
            saveCurrentEditingEntry()
            Task { await lockManager.releaseSubjectLock(subjectId: priorId) }
        }
        // Seed the buffer + originalImageNumber synchronously so the
        // text field shows the current value with no flicker.
        editingImageNumber = subject.imageNumbers
        originalImageNumber = subject.imageNumbers
        currentlyEditingEntry = subject.id
        // Acquire the lock async. If it fails (another device snuck in
        // between the check above and now), unwind the edit state.
        let target = subject.id
        Task {
            let acquired = await lockManager.acquireSubjectLock(subjectId: target)
            await MainActor.run {
                if !acquired && currentlyEditingEntry == target {
                    currentlyEditingEntry = nil
                    editingImageNumber = ""
                    originalImageNumber = ""
                }
            }
        }
    }

    /// Save the currently-edited image-numbers value. Short-circuits
    /// when nothing changed (the watch stream merge can re-call this
    /// without an actual user edit). Routes through saveSubject so the
    /// PowerSync write + Surface broadcast pipeline is shared.
    private func saveCurrentEditingEntry() {
        guard let entryId = currentlyEditingEntry,
              let idx = subjects.firstIndex(where: { $0.id == entryId }) else { return }
        // Same-content guard — protects against the watch stream looping
        // a no-op update through this path.
        guard editingImageNumber != originalImageNumber else { return }
        var updated = subjects[idx]
        updated.imageNumbers = editingImageNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()
        // Mark saved so the next watch tick doesn't re-trigger the save.
        originalImageNumber = editingImageNumber
        saveSubject(updated)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// End the inline edit session — flush save, release the lock, and
    /// clear all edit state. Called from the AutosaveTextField's
    /// onTapOutside path and from anywhere we need to bail (subject
    /// switch, lock-lost, panel disappear).
    private func endEditingImageNumber() {
        if let entryId = currentlyEditingEntry {
            saveCurrentEditingEntry()
            Task { await lockManager.releaseSubjectLock(subjectId: entryId) }
        }
        currentlyEditingEntry = nil
        editingImageNumber = ""
        originalImageNumber = ""
    }

    /// Move inline editing to the next row in the displayed list. Used
    /// by AutosaveTextField's onEnterOrDown — Enter/Down keyboard nav
    /// jumps to the next editable subject. Skips rows locked by other
    /// devices and wraps to the top if we're at the bottom.
    private func moveToNextEditableEntry(currentID: UUID) {
        let displayed = filteredSubjects
        guard let idx = displayed.firstIndex(where: { $0.id == currentID }) else { return }
        // Forward sweep first.
        for i in (idx + 1)..<displayed.count {
            let candidate = displayed[i]
            let lockedByOther = lockedEntries[candidate.id] != nil
                && lockedEntries[candidate.id] != lockManager.currentEditorIdentifier
            if !lockedByOther {
                startEditingImageNumber(candidate)
                scrollTargetId = candidate.id
                return
            }
        }
        // Wrap to top.
        for i in 0..<idx {
            let candidate = displayed[i]
            let lockedByOther = lockedEntries[candidate.id] != nil
                && lockedEntries[candidate.id] != lockManager.currentEditorIdentifier
            if !lockedByOther {
                startEditingImageNumber(candidate)
                scrollTargetId = candidate.id
                return
            }
        }
        // Nothing editable — just end the current edit.
        endEditingImageNumber()
    }

    /// Move inline editing to the previous editable row. Mirror of
    /// moveToNextEditableEntry — Enter/Up keyboard nav jumps backward,
    /// wraps to the bottom if at the top.
    private func moveToPreviousEditableEntry(currentID: UUID) {
        let displayed = filteredSubjects
        guard let idx = displayed.firstIndex(where: { $0.id == currentID }) else { return }
        for i in (0..<idx).reversed() {
            let candidate = displayed[i]
            let lockedByOther = lockedEntries[candidate.id] != nil
                && lockedEntries[candidate.id] != lockManager.currentEditorIdentifier
            if !lockedByOther {
                startEditingImageNumber(candidate)
                scrollTargetId = candidate.id
                return
            }
        }
        for i in (idx + 1..<displayed.count).reversed() {
            let candidate = displayed[i]
            let lockedByOther = lockedEntries[candidate.id] != nil
                && lockedEntries[candidate.id] != lockManager.currentEditorIdentifier
            if !lockedByOther {
                startEditingImageNumber(candidate)
                scrollTargetId = candidate.id
                return
            }
        }
        endEditingImageNumber()
    }

    // MARK: - Groups (sports)

    /// Schedule a per-group debounced save for capture-driven imageNumbers
    /// updates. Same pattern as scheduleCaptureSave on subjects — burst
    /// group captures collapse into one save after 500ms of quiet.
    /// Marked @MainActor so the dictionary mutation is actor-isolated
    /// regardless of caller context.
    @MainActor
    private func scheduleGroupCaptureSave(for groupId: UUID) {
        pendingGroupCaptureSaves[groupId]?.cancel()
        pendingGroupCaptureSaves[groupId] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if Task.isCancelled { return }
            if let latest = groupImages.first(where: { $0.id == groupId }) {
                saveGroupImage(latest)
            }
            pendingGroupCaptureSaves[groupId] = nil
        }
    }

    /// Persist a GroupImage create or edit. Increments `version` so
    /// PowerSync's last-write-wins on `updated_at` also records a
    /// monotonic version for any future optimistic-concurrency checks.
    /// Broadcasts the full row over the LAN WebSocket so Surface and
    /// other iPads apply it directly to local PowerSync — required
    /// for offline shoots where the LAN is the only path between
    /// devices. PowerSync's CRDT dedups when both sides eventually
    /// reach the cloud (LWW by updated_at).
    private func saveGroupImage(_ updated: GroupImage) {
        var toSave = updated
        toSave.version += 1
        toSave.updatedAt = Date()
        if let idx = groupImages.firstIndex(where: { $0.id == toSave.id }) {
            groupImages[idx] = toSave
        }
        Task {
            do {
                try await powerSync.saveGroupImage(toSave)
            } catch {
                print("Save group image failed: \(error)")
            }
            // Fast-path broadcast — Surface and other iPads refresh
            // instantly without waiting for the PowerSync cloud sync.
            // Mirrors how saveSubject broadcasts subject edits.
            await MainActor.run { fpSync.sendGroupFullUpdate(toSave) }
        }
    }

    private func loadGroupImages() async {
        do {
            groupImages = try await powerSync.getGroupImages(forJob: gallery.id)
        } catch {
            print("Failed to load group images: \(error)")
        }
    }

    private func startWatchingGroups() {
        groupWatchTask?.cancel()
        groupWatchTask = Task {
            do {
                for try await updated in powerSync.watchGroupImages(forJob: gallery.id) {
                    if !Task.isCancelled {
                        groupImages = updated
                    }
                }
            } catch {
                if !Task.isCancelled { print("Group watch error: \(error)") }
            }
        }
    }

    private func deleteGroup(_ group: GroupImage) {
        Task {
            do {
                try await powerSync.deleteGroupImage(id: group.id)
                // Fast-path: broadcast the delete to LAN-connected
                // Surfaces / iPads so they remove the row immediately,
                // even with no internet at the shoot.
                await MainActor.run { fpSync.sendGroupDeleted(groupId: group.id) }
            } catch {
                print("Failed to delete group image: \(error)")
            }
        }
    }

    // MARK: - Data Loading

    private func loadSubjects() async {
        isLoading = true
        do { subjects = try await powerSync.getSubjects(forGalleryId: galleryId) }
        catch { print("Failed to load subjects: \(error)") }
        isLoading = false
    }

    private func loadCachedThumbnails() async {
        let shootId = galleryId
        let cached = await Task.detached(priority: .utility) {
            ThumbnailCache.shared.loadAll(shootId: shootId)
        }.value
        if !cached.isEmpty {
            subjectThumbnails = cached
            // Update photo counts from cached data
            for (sid, thumbs) in cached {
                photoCountMap[sid] = thumbs.count
            }
        }
    }

    private func startWatching() {
        subjectWatchTask?.cancel()
        subjectWatchTask = Task {
            let stream = powerSync.watchSubjects(forGalleryId: galleryId)
            do {
                for try await updated in stream {
                    if !Task.isCancelled {
                        subjects = updated
                        // Rebuild the lock map from each watch tick so the
                        // row-level lock badge reflects the current source
                        // of truth (subject.lockedByName, written by the
                        // acquire_lock RPC). Mirrors the FP Sports
                        // pattern at FPSportsRosterView_iPad line 4819.
                        var nextLocks: [UUID: String] = [:]
                        for entry in updated {
                            if let name = entry.lockedByName, !name.isEmpty {
                                nextLocks[entry.id] = name
                            }
                        }
                        lockedEntries = nextLocks
                        if isLoading { isLoading = false }
                    }
                }
            } catch {
                if !Task.isCancelled { print("Subject watch error: \(error)") }
            }
        }
    }

    // MARK: - Sync Callbacks

    private func setupSyncCallbacks() {
        // When camera station selects a subject: auto-select + scroll on iPad + confirm
        fpSync.onActiveSubjectChanged = { (subjectId: String) in
            DispatchQueue.main.async {
                activeSubjectId = subjectId
                // Auto-select and scroll to the subject
                if let subject = subjects.first(where: { $0.id.uuidString.lowercased() == subjectId.lowercased() }) {
                    selectedSubjectId = subject.id
                    scrollTargetId = subject.id
                    // Confirm selection — shows banner + haptic
                    confirmedSubjectId = subjectId
                    confirmedSubjectName = "\(subject.firstName) \(subject.lastName)"
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        }

        // Stage 1: capture completed — queue the image number + haptic, clear selection confirmation
        fpSync.onCaptureCompleted = { (event: FPCaptureEvent) in
            DispatchQueue.main.async {
                let sid = event.subjectId
                photoCountMap[sid] = (photoCountMap[sid] ?? 0) + 1
                if let imgNum = event.imageNumber {
                    var pending = pendingImageNumbers[sid] ?? []
                    pending.append(imgNum)
                    pendingImageNumbers[sid] = pending

                    // Sports: append the image number to the subject's
                    // imageNumbers field IMMEDIATELY (in-memory) so no
                    // capture is ever lost. The save (PowerSync write +
                    // WebSocket broadcast) is debounced per-subject so
                    // burst-firing doesn't spam the CRUD queue.
                    if gallery.shootType == "sports",
                       let idx = subjects.firstIndex(where: { $0.id.uuidString.lowercased() == sid.lowercased() }) {
                        var entry = subjects[idx]
                        var nums = parseImageNumberRanges(entry.imageNumbers)
                        if !nums.contains(imgNum) {
                            nums.append(imgNum)
                            entry.imageNumbers = formatImageNumberRanges(nums)
                            entry.updatedAt = Date()
                            subjects[idx] = entry
                            scheduleCaptureSave(for: entry.id)
                            // If this row is being inline-edited right now,
                            // mirror the new image-numbers value into the
                            // edit buffer + originalImageNumber so the user
                            // sees the live append in the field they're
                            // typing in, and the next save guard doesn't
                            // think they changed something they didn't.
                            if currentlyEditingEntry == entry.id {
                                editingImageNumber = entry.imageNumbers
                                originalImageNumber = entry.imageNumbers
                            }
                        }
                    }
                }
                confirmedSubjectId = nil
                confirmedSubjectName = nil
                triggerCaptureHaptic()
            }
        }

        // Stage 2: thumbnail arrives — decode base64, pair with queued image number
        fpSync.onSubjectPhotographed = { (subjectId: String, thumbnail: String?, _: Int?) in
            DispatchQueue.main.async {
                guard let thumbStr = thumbnail, !thumbStr.isEmpty else { return }

                // Strip data URI prefix if present
                let base64 = thumbStr.replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
                    .replacingOccurrences(of: "data:image/webp;base64,", with: "")

                guard let data = Data(base64Encoded: base64),
                      let image = UIImage(data: data) else { return }

                // Pop oldest pending image number
                var imgNum: Int? = nil
                if var pending = pendingImageNumbers[subjectId], !pending.isEmpty {
                    imgNum = pending.removeFirst()
                    pendingImageNumbers[subjectId] = pending.isEmpty ? nil : pending
                }

                // Append thumbnail
                let existingCount = subjectThumbnails[subjectId]?.count ?? 0
                var thumbs = subjectThumbnails[subjectId] ?? []
                thumbs.append(CaptureThumb(image: image, imageNumber: imgNum))
                if thumbs.count > 20 { thumbs = Array(thumbs.suffix(20)) }
                subjectThumbnails[subjectId] = thumbs

                // Save to disk cache
                ThumbnailCache.shared.save(shootId: galleryId, subjectId: subjectId, imageNumber: imgNum, image: image)

                // Show capture preview popup for non-card photos.
                // Card photo = first photo for a subject on a non-sports shoot.
                let isSports = gallery.shootType == "sports"
                let isCardPhoto = existingCount == 0 && !isSports
                if !isCardPhoto && previewEnabled {
                    previewDismissTimer?.cancel()
                    withAnimation(.easeInOut(duration: 0.2)) { previewImage = image }
                    let timer = DispatchWorkItem {
                        withAnimation(.easeInOut(duration: 0.3)) { previewImage = nil }
                    }
                    previewDismissTimer = timer
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timer)
                }
            }
        }

        // Verification warning — show banner when Surface detects face/QR mismatch
        fpSync.onVerificationWarning = { subjectId, subjectName, status, message, qrData in
            DispatchQueue.main.async {
                let prefix = status == "mismatch" ? "⚠ Mismatch" : "⚠ Warning"
                verificationWarning = "\(prefix): \(subjectName) — \(message)"
                verificationSubjectId = subjectId
                // Auto-dismiss after 20 seconds
                verificationDismissTimer?.cancel()
                let sid = subjectId
                let timer = DispatchWorkItem { fpSync.sendVerificationResponse(subjectId: sid, confirmed: false); verificationWarning = nil; verificationSubjectId = nil }
                verificationDismissTimer = timer
                DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timer)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            }
        }

        // Subject name/field updated on another device (Surface) — patch the
        // local in-memory subject so the panel and roster reflect the change
        // immediately, without waiting for a cloud round-trip.
        fpSync.onSubjectUpdated = { (rosterEntryId: String, _: String?, firstName: String, lastName: String, rosterId: String, _: String) in
            DispatchQueue.main.async {
                guard let idx = subjects.firstIndex(where: { $0.id.uuidString.lowercased() == rosterEntryId.lowercased() }) else { return }
                var entry = subjects[idx]
                entry.firstName = firstName
                entry.lastName = lastName
                entry.rosterId = rosterId
                entry.updatedAt = Date()
                subjects[idx] = entry
            }
        }

        // New subject created on another device — add to local list
        fpSync.onSubjectCreated = { (rosterEntryId: String, firstName: String, lastName: String, rosterId: String, grade: String, groupName: String) in
            DispatchQueue.main.async {
                // Skip if we already have this subject
                guard !subjects.contains(where: { $0.id.uuidString.lowercased() == rosterEntryId.lowercased() }) else { return }
                if let uuid = UUID(uuidString: rosterEntryId) {
                    var newSubject = FPSubject(id: uuid, galleryId: galleryId)
                    newSubject.firstName = firstName
                    newSubject.lastName = lastName
                    newSubject.rosterId = rosterId
                    newSubject.grade = grade
                    newSubject.sport = groupName
                    subjects.append(newSubject)
                    subjects.sort { $0.lastName.localizedCaseInsensitiveCompare($1.lastName) == .orderedAscending }
                }
            }
        }

        // Move photo confirmed by Surface Pro — update local thumbnails + confirm
        fpSync.onCaptureReassigned = { (imageNumber: Int, oldSubjectId: String, newSubjectId: String) in
            DispatchQueue.main.async {
                if var fromThumbs = subjectThumbnails[oldSubjectId] {
                    if let idx = fromThumbs.firstIndex(where: { $0.imageNumber == imageNumber }) {
                        let moved = fromThumbs.remove(at: idx)
                        subjectThumbnails[oldSubjectId] = fromThumbs.isEmpty ? nil : fromThumbs
                        var toThumbs = subjectThumbnails[newSubjectId] ?? []
                        toThumbs.append(moved)
                        subjectThumbnails[newSubjectId] = toThumbs

                        // Update photo counts
                        photoCountMap[newSubjectId] = toThumbs.count
                        photoCountMap[oldSubjectId] = fromThumbs.count
                    }
                }
                // Cancel failure timeout and show success
                pendingMoveTimer?.cancel()
                pendingMoveTimer = nil
                let targetName = subjects.first(where: { $0.id.uuidString.lowercased() == newSubjectId.lowercased() })
                    .map { "\($0.firstName) \($0.lastName)" } ?? "subject"
                moveConfirmationMessage = "Image #\(imageNumber) moved to \(targetName)"
                moveConfirmationIsError = false
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                // Auto-dismiss success after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if moveConfirmationIsError == false { moveConfirmationMessage = nil }
                }
            }
        }

        // Group photo ready — fires when Surface has finished verifying the
        // group's member attendance. Stores the present-member set by group
        // name. Matches FP Sports' pattern; currently informational.
        fpSync.onGroupPhotoReady = { (groupName: String, presentSubjectIds: [String], _: Int) in
            DispatchQueue.main.async {
                let present = Set(presentSubjectIds.map { $0.lowercased() })
                let memberIds = subjects
                    .filter { present.contains($0.id.uuidString.lowercased()) }
                    .map { $0.id.uuidString }
                groupAttendance[groupName] = Set(memberIds)
            }
        }

        // Group capture completed — Surface tethered a capture tagged for a
        // group. Append the image number to the group's imageNumbers field
        // in memory immediately (no capture lost), then save via the
        // per-group debounce so burst group captures collapse into one
        // PowerSync write. FP Sports never wired this callback — this is
        // new behavior in the capture view.
        fpSync.onGroupCaptureCompleted = { (groupId: String, imageNumber: Int, _: String) in
            DispatchQueue.main.async {
                guard let uuid = UUID(uuidString: groupId),
                      let idx = groupImages.firstIndex(where: { $0.id == uuid }) else { return }
                var group = groupImages[idx]
                var nums = parseImageNumberRanges(group.imageNumbers)
                if !nums.contains(imageNumber) {
                    nums.append(imageNumber)
                    group.imageNumbers = formatImageNumberRanges(nums)
                    group.updatedAt = Date()
                    groupImages[idx] = group
                    scheduleGroupCaptureSave(for: group.id)
                }
                triggerCaptureHaptic()
            }
        }

        // Group row was created or edited on another device (Surface or
        // another iPad). Apply the FULL row directly to local PowerSync
        // so the change is visible offline — required because PowerSync
        // cloud sync needs internet, and the LAN may be the only path
        // between devices at a shoot. PowerSync's CRDT dedups when both
        // sides eventually reach the cloud (LWW by updated_at).
        fpSync.onGroupUpdated = { (_: String, _: String, row: RemoteGroupRow) in
            Task { @MainActor in
                guard let gid = UUID(uuidString: row.id),
                      let galleryUuid = UUID(uuidString: row.galleryId) else { return }
                let isoFormatter = ISO8601DateFormatter()
                let updatedDate = isoFormatter.date(from: row.updatedAt) ?? Date()
                let createdDate = isoFormatter.date(from: row.createdAt) ?? Date()
                let lockedDate = row.lockedAt.flatMap { isoFormatter.date(from: $0) }
                let updatedByUuid = row.updatedBy.flatMap { UUID(uuidString: $0) }
                let lockedByUuid = row.lockedBy.flatMap { UUID(uuidString: $0) }
                let group = GroupImage(
                    id: gid,
                    sportsJobId: galleryUuid,
                    organizationId: row.organizationId,
                    description: row.description,
                    imageNumbers: row.imageNumbers,
                    notes: row.notes,
                    sport: row.sport,
                    gender: row.gender,
                    teamLevel: row.teamLevel,
                    sortOrder: row.sortOrder,
                    version: row.version,
                    updatedAt: updatedDate,
                    updatedBy: updatedByUuid,
                    lockedBy: lockedByUuid,
                    lockedByName: row.lockedByName,
                    lockedAt: lockedDate,
                    createdAt: createdDate,
                    photographerId: row.photographerId
                )
                do {
                    try await powerSync.saveGroupImage(group)
                    await loadGroupImages()
                } catch {
                    print("PoserStationView: remote group_updated apply failed: \(error)")
                }
            }
        }

        // Group row was hard-deleted on another device. Apply the same
        // delete locally so it's visible offline. PowerSync propagates
        // the delete to Supabase when this iPad next has internet.
        fpSync.onGroupDeleted = { (groupId: String) in
            Task { @MainActor in
                guard let gid = UUID(uuidString: groupId) else { return }
                do {
                    try await powerSync.deleteGroupImage(id: gid)
                    await loadGroupImages()
                } catch {
                    print("PoserStationView: remote group_deleted apply failed: \(error)")
                }
            }
        }
    }

    // MARK: - Sync Sheet

    private var syncSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: fpSync.isConnected ? "wifi" : "wifi.slash")
                    .font(.system(size: 48))
                    .foregroundColor(fpSync.isConnected ? .green : .secondary)
                Text(fpSync.isConnected ? "Connected to Surface Pro" : "Not Connected")
                    .font(.headline)
                if !fpSync.isConnected {
                    Text("Make sure the Surface Pro has networking started and both devices are on the same WiFi.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                    Button("Connect") { fpSync.startDiscovery(galleryId: galleryId, authToken: nil) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Disconnect") { fpSync.disconnect() }
                        .buttonStyle(.bordered).tint(.red)
                }

                if fpSync.isConnected && fpSync.cameraDevices.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Camera Pairing")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
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
                    .padding(.horizontal)
                }

                if fpSync.isConnected && !fpSync.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connected Devices")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        ForEach(fpSync.devices) { device in
                            HStack {
                                Image(systemName: device.stationMode == "camera" ? "camera" : (device.stationMode == "ios_roster" ? "ipad" : "desktopcomputer"))
                                VStack(alignment: .leading) {
                                    Text(device.name).font(.body)
                                    Text(device.stationMode.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if device.captureCount > 0 {
                                    Text("\(device.captureCount) photos")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Sync Connection").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingSyncSheet = false } } }
        }
    }

    // MARK: - US Card QR Scan Sheet

    private var usCardQRSheet: some View {
        NavigationView {
            QRScannerCameraView(
                isScanning: .constant(true),
                torchOn: .constant(false),
                onCodeScanned: { code in
                    // Find matching subject by qr_code, roster_id, or student_id
                    if let match = subjects.first(where: {
                        $0.rosterId == code || $0.studentId == code ||
                        $0.id.uuidString.lowercased() == code.lowercased()
                    }) {
                        usCardSubject = match
                        showingUSCardQRScan = false
                        // Small delay to let the QR sheet dismiss before presenting doc scan
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showingUSCardDocScan = true
                        }
                    } else {
                        scanError = "No matching US card found for code: \(code)"
                    }
                }
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if let error = scanError {
                    Text(error)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.red.cornerRadius(10))
                        .padding(.top, 60)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { scanError = nil }
                        }
                }
            }
            .navigationTitle("Scan US Card QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingUSCardQRScan = false; scanError = nil }
                }
            }
        }
    }

    // MARK: - US Card Document Scan Sheet

    private var usCardDocScanSheet: some View {
        Group {
            if scanProcessing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Reading handwritten card...")
                        .font(.headline)
                    if let name = usCardSubject.map({ "\($0.firstName) \($0.lastName)".trimmingCharacters(in: .whitespaces) }),
                       !name.isEmpty, name != " " {
                        Text("Updating: \(name)")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DocumentScannerView(onScan: { images in
                    guard let image = images.first, let usSubject = usCardSubject else {
                        showingUSCardDocScan = false
                        return
                    }
                    scanProcessing = true
                    ClaudeRosterService.shared.extractPortraitCard(
                        image,
                        galleryId: galleryId,
                        organizationId: storedUserOrganizationID
                    ) { result in
                        scanProcessing = false
                        switch result {
                        case .success(let cardResult):
                            let extracted = cardResult.subject
                            // Update the US subject with extracted fields
                            var updated = usSubject
                            if !extracted.firstName.isEmpty { updated.firstName = extracted.firstName }
                            if !extracted.lastName.isEmpty { updated.lastName = extracted.lastName }
                            if !extracted.grade.isEmpty { updated.grade = extracted.grade }
                            if !extracted.teacher.isEmpty { updated.teacher = extracted.teacher }
                            if !extracted.studentId.isEmpty { updated.studentId = extracted.studentId }
                            updated.updatedAt = Date()

                            saveSubject(updated)
                            selectedSubjectId = updated.id
                            showingUSCardDocScan = false
                            usCardSubject = nil

                            if cardResult.usedOnDeviceOCR {
                                scanError = "Used on-device OCR (offline) — please verify the scanned info"
                            }
                        case .failure(let error):
                            scanError = "Card scan failed: \(error.localizedDescription)"
                            showingUSCardDocScan = false
                            usCardSubject = nil
                        }
                    }
                })
            }
        }
    }

    // MARK: - Capture Settings Sheet

    private var captureSettingsSheet: some View {
        NavigationView {
            List {
                Section(header: Text("Capture")) {
                    Toggle("Auto-select on camera", isOn: $autoSelectEnabled)
                    Text("When enabled, tapping a subject on iPad selects them on the Surface Pro camera")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section(header: Text("Display")) {
                    Toggle("Show capture preview", isOn: $previewEnabled)
                    Text("Briefly shows each photo full-screen when it arrives from the camera")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Capture Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showCaptureSettings = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Add Subject Sheet

    private var addSubjectSheet: some View {
        AddSubjectSheet(galleryId: galleryId, organizationId: storedUserOrganizationID, subjects: subjects) { newSubject in
            Task {
                do {
                    try await powerSync.saveSubject(newSubject)
                    let sid = newSubject.id.uuidString.lowercased()
                    fpSync.broadcastSubjectCreated(rosterEntryId: sid, firstName: newSubject.firstName, lastName: newSubject.lastName, rosterId: newSubject.rosterId, grade: newSubject.grade, groupName: newSubject.sport.isEmpty ? newSubject.homeroom : newSubject.sport)
                    showingAddSubject = false
                } catch { print("Add subject failed: \(error)") }
            }
        }
    }

    // MARK: - Battery Helpers

    private func batteryIconName(level: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.25" }
        return "battery.0"
    }

    private func batteryColor(level: Int) -> Color {
        if level <= 15 { return .red }
        if level <= 30 { return .orange }
        return .green
    }
}

// MARK: - Subject Detail Panel

struct SubjectDetailPanel: View {
    let subject: FPSubject
    let thumbnails: [CaptureThumb]
    let photoCount: Int
    let galleryId: String
    let isSports: Bool
    /// True when another device currently holds the lock on this
    /// subject. Render-only flag — the panel reads this to surface a
    /// "locked by …" banner and disable inputs. Lock acquisition for
    /// THIS device is owned by the panel itself via lockManager.
    let isLockedByOther: Bool
    /// Display name of the user holding the lock (when isLockedByOther).
    let lockedByName: String?
    let onSave: (FPSubject) -> Void
    let onSelect: () -> Void
    let onViewPhotos: (String, [CaptureThumb]) -> Void

    @State private var draft: FPSubject?
    /// Tracks whether THIS panel currently holds a lock on the visible
    /// subject. Acquired on first focus, released on focus-out / panel
    /// close / subject change. We track it so we don't re-acquire on
    /// every focus toggle within the same edit session.
    @State private var lockAcquired: Bool = false
    /// Subject id whose lock we hold (or null). Used to release the
    /// correct lock when the visible subject changes between panel
    /// opens without an explicit close.
    @State private var lockedSubjectId: UUID?
    // Debounce: 10-second fallback after the last keystroke. Real commit
    // triggers (focus-loss, subject-change, scene-phase, disappear) cover
    // every case where the user signals "done." The timer is just a last-
    // resort flush for the genuinely odd case where the user types in a
    // field and never leaves it. Long enough that a first grader spelling
    // their name slowly doesn't trigger mid-word.
    @State private var saveDebounceTask: Task<Void, Never>?
    private let saveDebounceNanos: UInt64 = 10_000_000_000  // 10 seconds
    @FocusState private var focusedField: String?
    // Scene-phase observation: home button / app switcher / screen lock all
    // suspend the app and can kill the in-flight debounce Task before it
    // fires. Flush on transition out of .active so partial edits don't get
    // stranded if iOS later kills the app for memory pressure.
    @Environment(\.scenePhase) private var scenePhase

    private var editing: FPSubject { draft ?? subject }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Locked-by-other banner. Surfaces above everything else
                // when another device holds the lock so the operator
                // sees it before they start typing. Inputs below stay
                // disabled while the lock is held by someone else.
                if isLockedByOther {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                        Text("Being edited by \(lockedByName ?? "another user")")
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(6)
                }

                // Header + select button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(subject.firstName) \(subject.lastName)")
                            .font(.title3).fontWeight(.bold)
                        if photoCount > 0 {
                            Text("\(photoCount) photo\(photoCount == 1 ? "" : "s")")
                                .font(.caption).foregroundColor(.green)
                        }
                    }
                    Spacer()
                    Button(action: onSelect) {
                        Label("Select", systemImage: "camera")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Sports: image-numbers field at the top, auto-fills as the
                // Surface broadcasts capture_completed events. Visual style
                // mirrors FP Sports view: blue 0.25 background, 16pt medium,
                // 44pt height — operators recognize the field consistently.
                if isSports {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("IMAGE NUMBERS")
                            .font(.caption).fontWeight(.bold).foregroundColor(.secondary).textCase(.uppercase)
                        TextField("Image #", text: binding(\.imageNumbers))
                            .font(.system(size: 16, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .multilineTextAlignment(.center)
                            .background(Color.blue.opacity(0.25))
                            .cornerRadius(8)
                            .focused($focusedField, equals: "imageNumbers")
                            .onChange(of: editing.imageNumbers) { _ in
                                scheduleDebouncedSave()
                            }
                    }
                }

                // Thumbnail grid
                if !thumbnails.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PHOTOS")
                            .font(.caption).fontWeight(.bold).foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
                            ForEach(thumbnails) { thumb in
                                Image(uiImage: thumb.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture {
                                        onViewPhotos("\(subject.firstName) \(subject.lastName)", thumbnails)
                                    }
                            }
                        }
                    }
                }

                Divider()

                // Editable fields
                Group {
                    fieldRow("First Name", value: binding(\.firstName))
                    fieldRow("Last Name", value: binding(\.lastName))
                    fieldRow("Grade", value: binding(\.grade))
                    if isSports {
                        // Teacher field on sports rosters is always one of
                        // the four codes (empty/c/s/8). A picker prevents
                        // typos and reinforces the contract.
                        teacherPicker
                    } else {
                        fieldRow("Teacher", value: binding(\.teacher))
                    }
                    fieldRow("Homeroom", value: binding(\.homeroom))
                    fieldRow("Student ID", value: binding(\.studentId))
                    fieldRow("Roster ID", value: binding(\.rosterId))
                }

                Divider()

                Group {
                    fieldRow("Email", value: binding(\.email))
                    fieldRow("Phone", value: binding(\.phone))
                    fieldRow("Notes", value: binding(\.notes))
                }

                if !subject.jerseyNumber.isEmpty || !subject.sport.isEmpty {
                    Divider()
                    Group {
                        fieldRow("Jersey #", value: binding(\.jerseyNumber))
                        fieldRow("Sport", value: binding(\.sport))
                        fieldRow("Position", value: binding(\.position))
                    }
                }

                Divider()
                HStack(spacing: 20) {
                    Toggle("Absent", isOn: absentBinding).toggleStyle(.switch)
                    Toggle("Retake", isOn: retakeBinding).toggleStyle(.switch)
                }
                .font(.subheadline)

                Spacer(minLength: 40)
            }
            .padding(20)
            // Disable interactive controls when another device holds the
            // lock. Inputs reject focus, save buttons reject taps. Banner
            // above stays visible (text/icon, no interactivity to disable)
            // so the user knows why the panel feels frozen.
            .disabled(isLockedByOther)
        }
        .background(Color(.secondarySystemBackground))
        .onChange(of: subject.id) { newId in
            // Switching to a different subject: flush any pending edit on the
            // outgoing subject FIRST so the keystrokes don't get lost, then
            // reset draft for the incoming subject. Also release any lock
            // we hold on the prior subject — the new subject will acquire
            // its own when the user touches a field there.
            flushPendingSave()
            draft = nil
            if let prior = lockedSubjectId, prior != newId {
                Task { await LockManager.shared.releaseSubjectLock(subjectId: prior) }
                lockedSubjectId = nil
                lockAcquired = false
            }
        }
        .onChange(of: focusedField) { newValue in
            // Primary commit trigger: the user clicked out of a field (or
            // into a different one). Flush whatever's in the draft now —
            // no waiting on the debounce timer.
            flushPendingSave()
            // Lock lifecycle. Acquire on first focus per subject (gated
            // by lockAcquired so we don't re-RPC on every Tab between
            // fields). Release when focus leaves the panel entirely
            // (focusedField == nil) so other devices can pick up the
            // subject as soon as we look away.
            if newValue != nil {
                if !lockAcquired || lockedSubjectId != subject.id {
                    let target = subject.id
                    Task {
                        let acquired = await LockManager.shared.acquireSubjectLock(subjectId: target)
                        await MainActor.run {
                            if acquired {
                                lockAcquired = true
                                lockedSubjectId = target
                            } else {
                                // Couldn't acquire (held by another). Drop
                                // focus so the user isn't typing into a
                                // field that won't save, and surface the
                                // banner via the parent's lockedEntries
                                // refresh on the next watch tick.
                                focusedField = nil
                            }
                        }
                    }
                }
            } else if lockAcquired, let held = lockedSubjectId {
                Task { await LockManager.shared.releaseSubjectLock(subjectId: held) }
                lockedSubjectId = nil
                lockAcquired = false
            }
        }
        .onDisappear {
            // Panel closed: flush any pending edit so partial keystrokes
            // don't sit in a cancelled debounce.
            flushPendingSave()
            // Release any lock we still hold so other devices aren't
            // blocked waiting for the TTL to expire.
            if let held = lockedSubjectId {
                Task { await LockManager.shared.releaseSubjectLock(subjectId: held) }
                lockedSubjectId = nil
                lockAcquired = false
            }
        }
        .onChange(of: scenePhase) { newPhase in
            // App backgrounded / inactive (home button, app switcher, lock
            // screen, incoming call). Flush before iOS suspends the
            // debounce task — otherwise the edit can be lost if the app
            // gets killed for memory pressure while in the background.
            // Also release the lock — iOS will give us a small window to
            // finish the RPC; if we miss it the lock TTL takes over.
            if newPhase != .active {
                flushPendingSave()
                if let held = lockedSubjectId {
                    Task { await LockManager.shared.releaseSubjectLock(subjectId: held) }
                    lockedSubjectId = nil
                    lockAcquired = false
                }
            }
        }
    }

    /// Picker for the sports teacher-code field. Maps the four valid states
    /// (empty / c / s / 8) to human labels (None / Coach / Senior / 8th
    /// Grader). Selection writes the code value back through the same
    /// draft binding the text fields use, so save/flush plumbing is shared.
    private var teacherPicker: some View {
        let options: [(code: String, label: String)] = [
            ("", "None"),
            ("c", "Coach"),
            ("s", "Senior"),
            ("8", "8th Grader"),
        ]
        return VStack(alignment: .leading, spacing: 4) {
            Text("Teacher").font(.caption).fontWeight(.semibold).foregroundColor(.secondary).textCase(.uppercase)
            Picker("Teacher", selection: binding(\.teacher)) {
                ForEach(options, id: \.code) { opt in
                    Text(opt.label).tag(opt.code)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .onChange(of: editing.teacher) { _ in scheduleDebouncedSave() }
        }
    }

    private func fieldRow(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).fontWeight(.semibold).foregroundColor(.secondary).textCase(.uppercase)
            TextField(label, text: value)
                .textFieldStyle(.roundedBorder).font(.body)
                .focused($focusedField, equals: label)
                .onChange(of: value.wrappedValue) { _ in
                    scheduleDebouncedSave()
                }
        }
    }

    /// Cancel any pending debounce and fire the save immediately (if there's
    /// a draft). Used by focus-change, subject-change, and panel-disappear
    /// to avoid waiting the full 2 seconds when the user signals "done."
    private func flushPendingSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        if let d = draft { onSave(d) }
    }

    /// Cancel any in-flight debounce timer and start a new one. The save
    /// fires once, after the user has been idle for `saveDebounceNanos`,
    /// carrying the FULL current draft — not one WebSocket message per
    /// keystroke.
    private func scheduleDebouncedSave() {
        saveDebounceTask?.cancel()
        let delay = saveDebounceNanos
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }
            if let d = draft { onSave(d) }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<FPSubject, String>) -> Binding<String> {
        Binding(
            get: { editing[keyPath: keyPath] },
            set: { newValue in
                if draft == nil { draft = subject }
                draft![keyPath: keyPath] = newValue
            }
        )
    }

    private var absentBinding: Binding<Bool> {
        Binding(get: { editing.isAbsent }, set: { v in
            if draft == nil { draft = subject }
            draft!.isAbsent = v; onSave(draft!)
        })
    }

    private var retakeBinding: Binding<Bool> {
        Binding(get: { editing.needsRetake }, set: { v in
            if draft == nil { draft = subject }
            draft!.needsRetake = v; onSave(draft!)
        })
    }
}

// MARK: - Add Subject Sheet

struct AddSubjectSheet: View {
    let galleryId: String
    let organizationId: String
    let subjects: [FPSubject]
    let onAdd: (FPSubject) -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var grade = ""
    @State private var teacher = ""
    @State private var homeroom = ""
    @State private var studentId = ""
    @State private var showingCardScan = false
    @State private var scanProcessing = false
    @State private var ocrWarning: String?
    @Environment(\.dismiss) private var dismiss

    private var showGrade: Bool { subjects.contains { !$0.grade.isEmpty } }
    private var showTeacher: Bool { subjects.contains { !$0.teacher.isEmpty } }
    private var showHomeroom: Bool { subjects.contains { !$0.homeroom.isEmpty } }
    private var showStudentId: Bool { subjects.contains { !$0.studentId.isEmpty } }

    var body: some View {
        NavigationView {
            Form {
                // Scan Card option
                Section {
                    if scanProcessing {
                        HStack {
                            ProgressView()
                            Text("Reading card...").foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: { showingCardScan = true }) {
                            Label("Scan Handwritten Card", systemImage: "doc.viewfinder")
                        }
                    }
                }

                if let warning = ocrWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                }

                Section("Name") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                }
                if showGrade || showTeacher || showHomeroom || showStudentId {
                    Section("Info") {
                        if showGrade { TextField("Grade", text: $grade) }
                        if showTeacher { TextField("Teacher", text: $teacher) }
                        if showHomeroom { TextField("Homeroom", text: $homeroom) }
                        if showStudentId { TextField("Student ID", text: $studentId) }
                    }
                }
            }
            .navigationTitle("Add Student").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let subject = FPSubject(galleryId: galleryId, organizationId: organizationId, firstName: firstName.trimmingCharacters(in: .whitespaces), lastName: lastName.trimmingCharacters(in: .whitespaces), grade: grade, teacher: teacher, homeroom: homeroom, studentId: studentId)
                        onAdd(subject)
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingCardScan) {
                DocumentScannerView(onScan: { images in
                    guard let image = images.first else { return }
                    scanProcessing = true
                    ClaudeRosterService.shared.extractPortraitCard(
                        image,
                        galleryId: galleryId,
                        organizationId: organizationId
                    ) { result in
                        scanProcessing = false
                        if case .success(let cardResult) = result {
                            let extracted = cardResult.subject
                            if !extracted.firstName.isEmpty { firstName = extracted.firstName }
                            if !extracted.lastName.isEmpty { lastName = extracted.lastName }
                            if !extracted.grade.isEmpty { grade = extracted.grade }
                            if !extracted.teacher.isEmpty { teacher = extracted.teacher }
                            if !extracted.studentId.isEmpty { studentId = extracted.studentId }
                            if cardResult.usedOnDeviceOCR {
                                ocrWarning = "Used on-device OCR (offline) — please verify"
                            }
                        }
                    }
                })
            }
        }
    }
}
