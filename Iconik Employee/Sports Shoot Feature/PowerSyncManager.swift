//
//  PowerSyncManager.swift
//  Iconik Employee
//
//  Main manager for PowerSync offline-first sync
//  Replaces SyncEngine for roster entries and group images
//

import Foundation
import PowerSync
import Supabase
import Combine
import Network

/// Errors specific to PowerSync operations
enum PowerSyncManagerError: Error {
    case notInitialized
    case notConnected
    case invalidData
    /// Phase G G.5 (Layer 2 wrapper). The iPad attempted a direct write
    /// to subjects / subject_images / capture_images for a gallery that
    /// is currently in an active FP capture session. Surface owns
    /// gallery-scoped writes during a shoot per FROM_SCRATCH_ARCHITECTURE.md
    /// §3 and §13 Phase G; iPad must route through SubjectSyncService
    /// (which sends a wire command to Surface and Surface owns the
    /// cloud write). The wrapper fires fast in iPad code with this typed
    /// error before the network round-trip; Layer 1 (Postgres trigger)
    /// is the survives-buggy-build backstop. Lock-column-only writes
    /// (releaseExpiredSubjectLocks) are exempt — they don't go through
    /// the wrapped methods.
    case writeBlockedDuringActiveCaptureSession(galleryId: String)
}

/// Main manager for PowerSync - handles offline-first data sync
@MainActor
class PowerSyncManager: ObservableObject {

    // MARK: - Singleton

    static let shared = PowerSyncManager()

    // MARK: - Published Properties

    @Published var isConnected = false {
        didSet {
            // Post notification for views that can't use @ObservedObject on PowerSyncManager
            NotificationCenter.default.post(
                name: NSNotification.Name("PowerSyncConnectionChanged"),
                object: nil,
                userInfo: ["isConnected": isConnected]
            )
        }
    }
    @Published var isSyncing = false
    @Published var hasSynced = false
    @Published var lastSyncTime: Date?
    @Published var isUploading = false {
        didSet {
            NotificationCenter.default.post(
                name: NSNotification.Name("PowerSyncUploadingChanged"),
                object: nil,
                userInfo: ["isUploading": isUploading]
            )
        }
    }
    @Published var isDownloading = false

    /// Last time the SDK successfully applied a checkpoint (downloaded data).
    /// Sourced from PowerSync's own `SyncStatus.lastSyncedAt`, not local connect time.
    @Published var lastSyncedAt: Date?

    /// Most recent sync error surfaced by the SDK (download or upload). Cleared
    /// when the next status update reports nil. Used by the diagnostics UI.
    @Published var lastSyncError: String?

    /// Whether the PowerSync database is initialized and ready for operations
    var isReady: Bool { database != nil }

    // MARK: - Private Properties

    private var database: PowerSyncDatabaseProtocol?
    private let connector = SupabasePowerSyncConnector()

    // MARK: - Phase G G.5 Layer 2 — Active capture session tracker
    //
    // Set of gallery IDs (lowercased UUID strings) currently in an active
    // FP capture session on this iPad. FP-aware on-shoot views
    // (PoserStationView, FPSportsRosterView_iPad) register on appear and
    // deregister on disappear via beginActiveCaptureSession /
    // endActiveCaptureSession. The signal survives WebSocket flaps because
    // view lifecycle is independent of WS state.
    //
    // saveSubject, deleteSubject, deleteBatchSubjects all check this set
    // before writing — if the subject's gallery_id is registered, throw
    // PowerSyncManagerError.writeBlockedDuringActiveCaptureSession. The
    // wrapper is the typed-error contract; Layer 1 (Postgres trigger) is
    // the survives-buggy-build backstop.
    //
    // releaseExpiredSubjectLocks is NOT guarded — lock-column-only writes
    // are exempt per Amendment 3 (lock columns are control-plane state
    // for multi-device coordination; restricting them during a shoot
    // would break the coordination Phase G is enabling).
    private var _activeCaptureSessions: Set<String> = []

    /// Whether any active capture session is registered (used by
    /// deleteSubject/deleteBatchSubjects which only have ids, not the
    /// gallery context — conservative refusal when any session is
    /// active so callers can't bypass via id-only paths).
    var hasAnyActiveCaptureSession: Bool { !_activeCaptureSessions.isEmpty }

    /// First registered gallery id, used for diagnostic messages on
    /// id-only delete paths.
    private var firstActiveCaptureSessionGalleryId: String? { _activeCaptureSessions.first }

    /// Mark a gallery as in an active FP capture session on this iPad.
    /// Called from FP-aware on-shoot view lifecycle (.onAppear).
    /// Idempotent — repeated calls for the same gallery are no-ops.
    func beginActiveCaptureSession(galleryId: String) {
        let lowered = galleryId.lowercased()
        if _activeCaptureSessions.insert(lowered).inserted {
            print("PowerSyncManager: beginActiveCaptureSession(\(lowered))")
        }
    }

    /// Mark a gallery as no longer in an active FP capture session on
    /// this iPad. Called from FP-aware on-shoot view lifecycle
    /// (.onDisappear). Idempotent — repeated calls are no-ops.
    func endActiveCaptureSession(galleryId: String) {
        let lowered = galleryId.lowercased()
        if _activeCaptureSessions.remove(lowered) != nil {
            print("PowerSyncManager: endActiveCaptureSession(\(lowered))")
        }
    }

    /// Returns whether the given gallery is in an active capture session
    /// on this iPad. Public for tests; also used internally by the
    /// wrapper guards.
    func isGalleryInActiveCaptureSession(_ galleryId: String) -> Bool {
        return _activeCaptureSessions.contains(galleryId.lowercased())
    }

    // Network monitoring for airplane mode detection
    private var networkMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "PowerSyncNetworkMonitor")
    private var isConnecting = false
    private var syncStatusWatchTask: Task<Void, Never>?
    private var authStateWatchTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectPending = false

    // MARK: - Initialization

    private init() {}

    deinit {
        networkMonitor?.cancel()
    }

    // MARK: - Setup

    /// Initialize PowerSync database and connect
    func initialize() async throws {
        guard database == nil else {
            print("PowerSyncManager: Already initialized")
            return
        }

        print("PowerSyncManager: Initializing...")

        // Create the database with our schema
        database = PowerSyncDatabase(
            schema: powerSyncSchema,
            dbFilename: "powersync-sports.db"
        )

        // Start network monitoring for airplane mode detection
        startNetworkMonitoring()

        // Watch Supabase auth state so a token refresh re-binds the sync stream
        // to the new JWT. Without this, the sync socket can keep using a stale
        // token until the next reconnect.
        startAuthStateWatch()

        // Connect to PowerSync service
        try await connect()

        print("PowerSyncManager: Initialization complete")
    }

    // MARK: - Network Monitoring

    /// Start monitoring network connectivity for airplane mode detection
    private func startNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let wasConnected = self.isConnected
                let nowConnected = path.status == .satisfied

                print("PowerSyncManager: Network status changed - was: \(wasConnected), now: \(nowConnected)")

                // Update connection status
                self.isConnected = nowConnected

                // If we came back online, try to reconnect PowerSync
                if !wasConnected && nowConnected {
                    print("PowerSyncManager: Network restored, reconnecting...")
                    try? await self.connect()
                }
            }
        }
        networkMonitor?.start(queue: monitorQueue)
        print("PowerSyncManager: Network monitoring started")
    }

    /// Connect to PowerSync service
    func connect() async throws {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        // Prevent concurrent connect() calls (network monitor + initialize() race)
        guard !isConnecting else {
            print("PowerSyncManager: Already connecting, skipping duplicate call")
            return
        }
        isConnecting = true

        print("PowerSyncManager: Connecting...")

        do {
            try await db.connect(connector: connector)
            isConnected = true
            isConnecting = false
            print("PowerSyncManager: Connected successfully")

            // Check if we already have cached data from a previous sync
            if let syncStatus = db.currentStatus.hasSynced, syncStatus {
                hasSynced = true
                lastSyncTime = Date()
                print("PowerSyncManager: Has cached data from previous sync")
            }

            // Notify views that depend on PowerSync data
            NotificationCenter.default.post(name: NSNotification.Name("PowerSyncDidConnect"), object: nil)

            // Start watching sync status for upload/download indicators
            startSyncStatusWatch(db: db)
        } catch {
            isConnecting = false
            print("PowerSyncManager: Connection failed: \(error)")
            throw error
        }
    }

    /// Watch PowerSync's sync status stream for upload/download/error state changes.
    /// Surfaces `lastSyncedAt` and `anyError` so the diagnostics UI can show the
    /// real reason a sync is stalled instead of silently appearing "Synced".
    private func startSyncStatusWatch(db: PowerSyncDatabaseProtocol) {
        syncStatusWatchTask?.cancel()
        syncStatusWatchTask = Task { [weak self] in
            for await status in db.currentStatus.asFlow() {
                guard !Task.isCancelled else { break }
                guard let self = self else { break }
                let newUploading = status.uploading
                let newDownloading = status.downloading
                if self.isUploading != newUploading {
                    self.isUploading = newUploading
                }
                if self.isDownloading != newDownloading {
                    self.isDownloading = newDownloading
                }
                if self.lastSyncedAt != status.lastSyncedAt {
                    self.lastSyncedAt = status.lastSyncedAt
                }
                let newError = status.anyError.map { Self.sanitizeErrorMessage(String(describing: $0)) }
                if self.lastSyncError != newError {
                    self.lastSyncError = newError
                }
            }
        }
    }

    /// Subscribe to Supabase auth events.
    /// - `.tokenRefreshed` → schedule a reconnect (coalesced) so the new JWT is
    ///   bound to the sync stream instead of waiting for the SDK's next retry.
    /// - `.signedOut` → tear down the sync stream so we stop using the old session.
    /// Reconnects are dispatched via `scheduleReconnect()` (fire-and-forget) so a
    /// burst of auth events doesn't block this consumer loop and lose later events.
    private func startAuthStateWatch() {
        authStateWatchTask?.cancel()
        authStateWatchTask = Task { [weak self] in
            let supabase = SupabaseManager.shared.client
            for await state in await supabase.auth.authStateChanges {
                guard !Task.isCancelled else { break }
                guard let self = self else { break }
                switch state.event {
                case .tokenRefreshed:
                    print("PowerSyncManager: Token refreshed, scheduling reconnect")
                    self.scheduleReconnect()
                case .signedOut:
                    print("PowerSyncManager: User signed out, disconnecting sync stream")
                    Task { @MainActor [weak self] in
                        await self?.disconnect()
                    }
                default:
                    break
                }
            }
        }
    }

    /// Coalescing reconnect. Multiple calls while a reconnect is in flight collapse
    /// to one follow-up reconnect — guarantees the latest credentials are applied
    /// without dropping events the way an inline `await connect()` would.
    private func scheduleReconnect() {
        reconnectPending = true
        guard reconnectTask == nil else { return }
        reconnectTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            while self.reconnectPending {
                self.reconnectPending = false
                await self.performReconnect()
            }
            self.reconnectTask = nil
        }
    }

    /// Force a fresh sync stream by disconnecting then reconnecting. Waits for any
    /// in-flight `connect()` to finish (to avoid two concurrent `db.connect` calls)
    /// then claims the `isConnecting` slot for itself.
    private func performReconnect() async {
        guard let db = database else { return }
        while isConnecting {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await db.disconnect()
            try await db.connect(connector: connector)
            isConnected = true
            print("PowerSyncManager: Reconnected with fresh credentials")
        } catch {
            print("PowerSyncManager: Reconnect failed: \(error)")
        }
    }

    /// Strip JWT tokens and Bearer headers from error strings before they reach
    /// the UI. PowerSync errors can embed credential fragments in their debug
    /// descriptions; the iPad is sometimes handed to non-employees on-site.
    private static func sanitizeErrorMessage(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(
            of: "eyJ[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+",
            with: "[token]",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: "Bearer\\s+\\S+",
            with: "Bearer [token]",
            options: .regularExpression
        )
        return s
    }

    /// Clear local database and re-sync from server.
    /// Use when the CRUD queue is stuck and preventing downloads.
    /// Throws if the wipe or reconnect fails so the caller can surface the error;
    /// on a reconnect failure the local DB is already empty and the user must retry.
    func clearAndReSync() async throws {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }
        try await db.disconnectAndClear()
        hasSynced = false
        isConnected = false
        try await connect()
        print("PowerSyncManager: Cleared local data and reconnected")
    }

    /// Wipe the local PowerSync database without reconnecting.
    /// Called on sign-out: the roster data (student names, contact info)
    /// must not survive across accounts on shared iPads, and the next
    /// sign-in re-syncs from scratch with that user's credentials.
    func wipeForSignOut() async {
        guard let db = database else { return }
        syncStatusWatchTask?.cancel()
        syncStatusWatchTask = nil
        do {
            try await db.disconnectAndClear()
        } catch {
            print("PowerSyncManager: wipeForSignOut failed: \(error)")
        }
        hasSynced = false
        isConnected = false
        isUploading = false
        isDownloading = false
        print("PowerSyncManager: Local data wiped for sign-out")
    }

    /// Wait for first sync to complete using the SDK's built-in method.
    /// Local SQLite reads work immediately (cached data from previous sessions),
    /// but on a fresh install this waits for the first full sync from the server.
    func waitForFirstSync() async {
        guard let db = database else { return }

        // Already synced (cached data from previous app run) — return immediately
        if let syncStatus = db.currentStatus.hasSynced, syncStatus {
            hasSynced = true
            return
        }

        // Use the SDK's own waitForFirstSync with a timeout
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await db.waitForFirstSync()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000) // 15s timeout
                    throw CancellationError()
                }
                // Whichever finishes first wins
                try await group.next()
                group.cancelAll()
            }
            hasSynced = true
            lastSyncTime = Date()
            print("PowerSyncManager: First sync complete")
        } catch {
            print("PowerSyncManager: waitForFirstSync timed out or failed: \(error)")
        }
    }

    /// Disconnect from PowerSync
    func disconnect() async {
        guard let db = database else { return }

        syncStatusWatchTask?.cancel()
        syncStatusWatchTask = nil
        try? await db.disconnect()
        isConnected = false
        isUploading = false
        isDownloading = false

        print("PowerSyncManager: Disconnected")
    }

    // MARK: - Roster Entries

    /// Fetch all roster entries for a sports job
    func getRosterEntries(forJob jobId: UUID) async throws -> [RosterEntry] {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let jobIdString = jobId.uuidString.lowercased()

        let results: [RosterEntry] = try await db.getAll(
            sql: "SELECT * FROM roster_entries WHERE sports_job_id = ? ORDER BY sort_order ASC, last_name ASC",
            parameters: [jobIdString],
            mapper: { cursor in
                try Self.parseRosterEntry(from: cursor)
            }
        )

        return results
    }

    /// Save a roster entry (insert or update)
    func saveRosterEntry(_ entry: RosterEntry) async throws {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        // DIAGNOSTIC: capture the image_numbers value at the moment of the
        // local write. If a number "vanishes", this line reveals whether the
        // correct value ever reached the save (empty here == lost upstream in
        // the editing UI; correct here == lost later in sync).
        RosterEditDiagnostics.shared.log(
            "saveRosterEntry",
            entryId: entry.id.uuidString.lowercased(),
            numbers: entry.imageNumbers,
            extra: "v=\(entry.version)"
        )

        let idString = entry.id.uuidString.lowercased()
        let jobIdString = entry.sportsJobId.uuidString.lowercased()
        let updatedByString: String? = entry.updatedBy?.uuidString.lowercased()
        let lockedByString: String? = entry.lockedBy?.uuidString.lowercased()
        let updatedAtISO = ISO8601DateFormatter().string(from: entry.updatedAt)
        let createdAtISO = ISO8601DateFormatter().string(from: entry.createdAt)
        let lockedAtISO: String? = entry.lockedAt.map { ISO8601DateFormatter().string(from: $0) }
        let isFilledBlankInt: Int? = entry.isFilledBlank.map { $0 ? 1 : 0 }

        _ = try await db.execute(
            sql: """
                INSERT OR REPLACE INTO roster_entries
                (id, sports_job_id, organization_id, last_name, first_name, teacher, group_name, email, phone,
                 image_numbers, notes, sort_order, version, updated_at, updated_by,
                 locked_by, locked_by_name, locked_at, created_at, is_filled_blank, subject_id, roster_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                idString,
                jobIdString,
                entry.organizationId,
                entry.lastName,
                entry.firstName,
                entry.teacher,
                entry.groupName,
                entry.email,
                entry.phone,
                entry.imageNumbers,
                entry.notes,
                entry.sortOrder,
                entry.version,
                updatedAtISO,
                updatedByString,
                lockedByString,
                entry.lockedByName,
                lockedAtISO,
                createdAtISO,
                isFilledBlankInt,
                entry.subjectId,
                entry.rosterId
            ]
        )

        print("PowerSyncManager: Saved roster entry \(idString)")
    }

    /// Delete a roster entry
    func deleteRosterEntry(id: UUID) async throws {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let idString = id.uuidString.lowercased()

        _ = try await db.execute(
            sql: "DELETE FROM roster_entries WHERE id = ?",
            parameters: [idString]
        )

        print("PowerSyncManager: Deleted roster entry \(idString)")
    }

    /// Link a roster entry to a Production subject (update subject_id only)
    func linkRosterEntryToSubject(rosterEntryId: String, subjectId: String) async throws {
        guard let db = database else { throw PowerSyncManagerError.notInitialized }
        let updatedAt = ISO8601DateFormatter().string(from: Date())
        _ = try await db.execute(
            sql: "UPDATE roster_entries SET subject_id = ?, updated_at = ? WHERE id = ?",
            parameters: [subjectId, updatedAt, rosterEntryId]
        )
        print("PowerSyncManager: Linked roster entry \(rosterEntryId) -> subject \(subjectId)")
    }

    /// Batch delete multiple roster entries using a single SQL statement
    func deleteBatchRosterEntries(ids: [UUID]) async throws {
        guard let db = database else { throw PowerSyncManagerError.notInitialized }
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let sql = "DELETE FROM roster_entries WHERE id IN (\(placeholders))"
        let params: [String] = ids.map { $0.uuidString.lowercased() }
        _ = try await db.execute(sql: sql, parameters: params)
        print("PowerSyncManager: Batch deleted \(ids.count) roster entries")
    }

    /// Watch roster entries for real-time updates
    func watchRosterEntries(forJob jobId: UUID) -> AsyncThrowingStream<[RosterEntry], Error> {
        guard let db = database else {
            return AsyncThrowingStream { $0.finish() }
        }

        let jobIdString = jobId.uuidString.lowercased()

        do {
            return try db.watch(
                sql: "SELECT * FROM roster_entries WHERE sports_job_id = ? ORDER BY sort_order ASC, last_name ASC",
                parameters: [jobIdString],
                mapper: { cursor in
                    try Self.parseRosterEntry(from: cursor)
                }
            )
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    // MARK: - Group Images

    /// Fetch all group images for a sports job
    func getGroupImages(forJob jobId: UUID) async throws -> [GroupImage] {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let jobIdString = jobId.uuidString.lowercased()

        let results: [GroupImage] = try await db.getAll(
            sql: "SELECT * FROM group_images WHERE gallery_id = ? ORDER BY sort_order ASC",
            parameters: [jobIdString],
            mapper: { cursor in
                try Self.parseGroupImage(from: cursor)
            }
        )

        return results
    }

    /// Save a group image (insert or update)
    func saveGroupImage(_ group: GroupImage) async throws {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let idString = group.id.uuidString.lowercased()
        let jobIdString = group.sportsJobId.uuidString.lowercased()
        let updatedByString: String? = group.updatedBy?.uuidString.lowercased()
        let lockedByString: String? = group.lockedBy?.uuidString.lowercased()
        let updatedAtISO = ISO8601DateFormatter().string(from: group.updatedAt)
        let createdAtISO = ISO8601DateFormatter().string(from: group.createdAt)
        let lockedAtISO: String? = group.lockedAt.map { ISO8601DateFormatter().string(from: $0) }

        // Write sports_job_id alongside gallery_id during the column-rename
        // rollout. PowerSync's local SQLite only auto-migrates ADDED columns,
        // so any client whose local table was created before the rename still
        // has the old NOT NULL sports_job_id column AND no gallery_id column.
        // The Supabase trigger keeps both columns in sync server-side; we
        // write both client-side so the local INSERT succeeds regardless of
        // which schema generation the local SQLite happens to be on. Drop
        // sports_job_id from this statement when the next migration removes
        // the column server-side.
        _ = try await db.execute(
            sql: """
                INSERT OR REPLACE INTO group_images
                (id, gallery_id, sports_job_id, organization_id, description, image_numbers, notes, sport, gender,
                 team_level, sort_order, version, updated_at, updated_by,
                 locked_by, locked_by_name, locked_at, created_at, photographer_id,
                 member_field, member_value)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                idString,
                jobIdString,
                jobIdString,
                group.organizationId,
                group.description,
                group.imageNumbers,
                group.notes,
                group.sport,
                group.gender,
                group.teamLevel,
                group.sortOrder,
                group.version,
                updatedAtISO,
                updatedByString,
                lockedByString,
                group.lockedByName,
                lockedAtISO,
                createdAtISO,
                group.photographerId,
                group.memberField,
                group.memberValue
            ]
        )

        print("PowerSyncManager: Saved group image \(idString)")
    }

    /// Backfill organization_id on local group_images that are missing it.
    /// Looks up the org from the linked sports_jobs or galleries table.
    private func backfillGroupImageOrgIds() async {
        guard let db = database else { return }

        do {
            // Find group_images missing organization_id
            let missing: [[String: String]] = try await db.getAll(
                sql: "SELECT id, gallery_id FROM group_images WHERE organization_id IS NULL OR organization_id = ''",
                parameters: [],
                mapper: { cursor in
                    let id = try cursor.getString(name: "id")
                    let jobId = try cursor.getString(name: "gallery_id")
                    return ["id": id, "gallery_id": jobId]
                }
            )

            guard !missing.isEmpty else { return }
            print("PowerSyncManager: Backfilling organization_id on \(missing.count) group_images")

            for row in missing {
                guard let id = row["id"], let jobId = row["gallery_id"] else { continue }

                // Try sports_jobs first, then galleries
                var orgId: String? = nil
                if let sj: [String] = try? await db.getAll(
                    sql: "SELECT organization_id FROM sports_jobs WHERE id = ? LIMIT 1",
                    parameters: [jobId],
                    mapper: { try $0.getString(name: "organization_id") }
                ), let first = sj.first {
                    orgId = first
                } else if let gal: [String] = try? await db.getAll(
                    sql: "SELECT organization_id FROM galleries WHERE id = ? LIMIT 1",
                    parameters: [jobId],
                    mapper: { try $0.getString(name: "organization_id") }
                ), let first = gal.first {
                    orgId = first
                }

                if let orgId = orgId, !orgId.isEmpty {
                    _ = try? await db.execute(
                        sql: "UPDATE group_images SET organization_id = ? WHERE id = ?",
                        parameters: [orgId, id]
                    )
                    print("PowerSyncManager: Backfilled org_id on group_image \(id)")
                }
            }
        } catch {
            print("PowerSyncManager: Backfill failed (non-fatal): \(error)")
        }
    }

    /// Delete a group image
    func deleteGroupImage(id: UUID) async throws {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let idString = id.uuidString.lowercased()

        _ = try await db.execute(
            sql: "DELETE FROM group_images WHERE id = ?",
            parameters: [idString]
        )

        print("PowerSyncManager: Deleted group image \(idString)")
    }

    /// Watch group images for real-time updates
    func watchGroupImages(forJob jobId: UUID) -> AsyncThrowingStream<[GroupImage], Error> {
        guard let db = database else {
            return AsyncThrowingStream { $0.finish() }
        }

        let jobIdString = jobId.uuidString.lowercased()

        do {
            return try db.watch(
                sql: "SELECT * FROM group_images WHERE gallery_id = ? ORDER BY sort_order ASC",
                parameters: [jobIdString],
                mapper: { cursor in
                    try Self.parseGroupImage(from: cursor)
                }
            )
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    // MARK: - Sports Jobs

    /// Fetch all sports jobs for an organization
    func getSportsJobs(forOrg orgId: String) async throws -> [SportsShoot] {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let results: [SportsShoot] = try await db.getAll(
            sql: "SELECT * FROM sports_jobs WHERE organization_id = ? ORDER BY shoot_date DESC",
            parameters: [orgId],
            mapper: { cursor in
                try Self.parseSportsJob(from: cursor)
            }
        )

        return results
    }

    // MARK: - Galleries (offline-first for FP Sports)

    /// Fetch sports galleries from local SQLite — galleries are synced org-wide via by_org bucket
    func getSportGalleries(forOrg orgId: String) async throws -> [SportsShoot] {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let results: [SportsShoot] = try await db.getAll(
            sql: "SELECT * FROM galleries WHERE organization_id = ? AND shoot_type = 'sports' AND (is_deleted IS NULL OR is_deleted != 'true') ORDER BY created_at DESC",
            parameters: [orgId],
            mapper: { cursor in
                try Self.parseGalleryAsSportsShoot(from: cursor)
            }
        )

        return results
    }

    /// Watch sports galleries for real-time updates
    func watchSportGalleries(forOrg orgId: String) -> AsyncThrowingStream<[SportsShoot], Error> {
        guard let db = database else {
            return AsyncThrowingStream { $0.finish() }
        }

        do {
            return try db.watch(
                sql: "SELECT * FROM galleries WHERE organization_id = ? AND shoot_type = 'sports' AND (is_deleted IS NULL OR is_deleted != 'true') ORDER BY created_at DESC",
                parameters: [orgId],
                mapper: { cursor in
                    try Self.parseGalleryAsSportsShoot(from: cursor)
                }
            )
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    /// Fetch all galleries for the Capture section (all shoot types)
    func getCaptureGalleries(forOrg orgId: String) async throws -> [SportsShoot] {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let results: [SportsShoot] = try await db.getAll(
            sql: "SELECT * FROM galleries WHERE organization_id = ? AND (is_deleted IS NULL OR is_deleted != 'true') ORDER BY created_at DESC",
            parameters: [orgId],
            mapper: { cursor in
                try Self.parseGalleryAsSportsShoot(from: cursor)
            }
        )

        return results
    }

    /// Watch all galleries for the Capture section (real-time updates)
    func watchCaptureGalleries(forOrg orgId: String) -> AsyncThrowingStream<[SportsShoot], Error> {
        guard let db = database else {
            return AsyncThrowingStream { $0.finish() }
        }

        do {
            return try db.watch(
                sql: "SELECT * FROM galleries WHERE organization_id = ? AND (is_deleted IS NULL OR is_deleted != 'true') ORDER BY created_at DESC",
                parameters: [orgId],
                mapper: { cursor in
                    try Self.parseGalleryAsSportsShoot(from: cursor)
                }
            )
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    /// Fetch a single sports job by ID from local SQLite — used as offline fallback
    func getSportsJob(id: UUID) async throws -> SportsShoot? {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let idString = id.uuidString.lowercased()

        let results: [SportsShoot] = try await db.getAll(
            sql: "SELECT * FROM sports_jobs WHERE id = ? LIMIT 1",
            parameters: [idString],
            mapper: { cursor in
                try Self.parseSportsJob(from: cursor)
            }
        )

        return results.first
    }

    /// Watch sports jobs for real-time updates
    func watchSportsJobs(forOrg orgId: String) -> AsyncThrowingStream<[SportsShoot], Error> {
        guard let db = database else {
            return AsyncThrowingStream { $0.finish() }
        }

        do {
            return try db.watch(
                sql: "SELECT * FROM sports_jobs WHERE organization_id = ? ORDER BY shoot_date DESC",
                parameters: [orgId],
                mapper: { cursor in
                    try Self.parseSportsJob(from: cursor)
                }
            )
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    // MARK: - Parsing Helpers (nonisolated static methods for use in closures)

    private nonisolated static func parseRosterEntry(from cursor: SqlCursor) throws -> RosterEntry {
        let idString = try cursor.getString(name: "id")
        let jobIdString = try cursor.getString(name: "sports_job_id")

        guard let id = UUID(uuidString: idString),
              let jobId = UUID(uuidString: jobIdString) else {
            throw PowerSyncManagerError.invalidData
        }

        return RosterEntry(
            id: id,
            sportsJobId: jobId,
            organizationId: (try? cursor.getString(name: "organization_id")) ?? "",
            lastName: (try? cursor.getString(name: "last_name")) ?? "",
            firstName: (try? cursor.getString(name: "first_name")) ?? "",
            teacher: (try? cursor.getString(name: "teacher")) ?? "",
            groupName: (try? cursor.getString(name: "group_name")) ?? "",
            email: (try? cursor.getString(name: "email")) ?? "",
            phone: (try? cursor.getString(name: "phone")) ?? "",
            imageNumbers: (try? cursor.getString(name: "image_numbers")) ?? "",
            notes: (try? cursor.getString(name: "notes")) ?? "",
            sortOrder: (try? cursor.getIntOptional(name: "sort_order")) ?? 0,
            version: (try? cursor.getIntOptional(name: "version")) ?? 1,
            updatedAt: parseDate((try? cursor.getString(name: "updated_at"))) ?? Date(),
            updatedBy: (try? cursor.getString(name: "updated_by")).flatMap { UUID(uuidString: $0) },
            lockedBy: (try? cursor.getString(name: "locked_by")).flatMap { UUID(uuidString: $0) },
            lockedByName: try? cursor.getString(name: "locked_by_name"),
            lockedAt: parseDate((try? cursor.getString(name: "locked_at"))),
            createdAt: parseDate((try? cursor.getString(name: "created_at"))) ?? Date(),
            isFilledBlank: (try? cursor.getIntOptional(name: "is_filled_blank")).flatMap { $0 }.map { $0 == 1 },
            subjectId: try? cursor.getString(name: "subject_id"),
            rosterId: (try? cursor.getString(name: "roster_id")) ?? ""
        )
    }

    private nonisolated static func parseGroupImage(from cursor: SqlCursor) throws -> GroupImage {
        let idString = try cursor.getString(name: "id")
        let jobIdString = try cursor.getString(name: "gallery_id")

        guard let id = UUID(uuidString: idString),
              let jobId = UUID(uuidString: jobIdString) else {
            throw PowerSyncManagerError.invalidData
        }

        return GroupImage(
            id: id,
            sportsJobId: jobId,
            organizationId: (try? cursor.getString(name: "organization_id")) ?? "",
            description: (try? cursor.getString(name: "description")) ?? "",
            imageNumbers: (try? cursor.getString(name: "image_numbers")) ?? "",
            notes: (try? cursor.getString(name: "notes")) ?? "",
            sport: (try? cursor.getString(name: "sport")) ?? "",
            gender: (try? cursor.getString(name: "gender")) ?? "",
            teamLevel: (try? cursor.getString(name: "team_level")) ?? "",
            sortOrder: (try? cursor.getIntOptional(name: "sort_order")) ?? 0,
            version: (try? cursor.getIntOptional(name: "version")) ?? 1,
            updatedAt: parseDate((try? cursor.getString(name: "updated_at"))) ?? Date(),
            updatedBy: (try? cursor.getString(name: "updated_by")).flatMap { UUID(uuidString: $0) },
            lockedBy: (try? cursor.getString(name: "locked_by")).flatMap { UUID(uuidString: $0) },
            lockedByName: try? cursor.getString(name: "locked_by_name"),
            lockedAt: parseDate((try? cursor.getString(name: "locked_at"))),
            createdAt: parseDate((try? cursor.getString(name: "created_at"))) ?? Date(),
            photographerId: try? cursor.getString(name: "photographer_id"),
            memberField: try? cursor.getString(name: "member_field"),
            memberValue: try? cursor.getString(name: "member_value")
        )
    }

    /// Maps a galleries row to SportsShoot — mirrors the inline mapping in FPSportsRosterView_iPad.loadSportsShoots()
    private nonisolated static func parseGalleryAsSportsShoot(from cursor: SqlCursor) throws -> SportsShoot {
        let idString = try cursor.getString(name: "id")

        guard let id = UUID(uuidString: idString) else {
            throw PowerSyncManagerError.invalidData
        }

        // Parse photo_day date (stored as "yyyy-MM-dd" text in SQLite)
        var shootDate = Date()
        if let pd = try? cursor.getString(name: "photo_day"), !pd.isEmpty {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            shootDate = fmt.date(from: pd) ?? Date()
        }

        var shoot = SportsShoot(
            id: id,
            organizationId: (try? cursor.getString(name: "organization_id")) ?? "",
            schoolName: (try? cursor.getString(name: "name")) ?? "",
            schoolId: try? cursor.getString(name: "school_id"),
            sportName: "",
            seasonType: (try? cursor.getString(name: "school_year")) ?? "",
            shootDate: shootDate,
            location: "",
            photographer: "",
            additionalNotes: (try? cursor.getString(name: "notes")) ?? "",
            sessionId: nil,
            isArchived: (try? cursor.getString(name: "status")) == "archived",
            createdAt: parseDate((try? cursor.getString(name: "created_at"))) ?? Date(),
            updatedAt: parseDate((try? cursor.getString(name: "updated_at"))) ?? Date(),
            galleryId: idString   // The gallery IS the shoot — its own id is the galleryId
        )
        shoot.shootType = try? cursor.getString(name: "shoot_type")
        shoot.displayConfig = try? cursor.getString(name: "display_config")
        return shoot
    }

    private nonisolated static func parseSportsJob(from cursor: SqlCursor) throws -> SportsShoot {
        let idString = try cursor.getString(name: "id")

        guard let id = UUID(uuidString: idString) else {
            throw PowerSyncManagerError.invalidData
        }

        return SportsShoot(
            id: id,
            organizationId: (try? cursor.getString(name: "organization_id")) ?? "",
            schoolName: (try? cursor.getString(name: "school_name")) ?? "",
            schoolId: try? cursor.getString(name: "school_id"),
            sportName: (try? cursor.getString(name: "sport_name")) ?? "",
            seasonType: (try? cursor.getString(name: "season_type")) ?? "",
            shootDate: parseDate((try? cursor.getString(name: "shoot_date"))) ?? Date(),
            location: (try? cursor.getString(name: "location")) ?? "",
            photographer: (try? cursor.getString(name: "photographer")) ?? "",
            additionalNotes: (try? cursor.getString(name: "additional_notes")) ?? "",
            sessionId: try? cursor.getString(name: "session_id"),
            isArchived: (try? cursor.getIntOptional(name: "is_archived")).flatMap { $0 }.map { $0 == 1 } ?? false,
            createdAt: parseDate((try? cursor.getString(name: "created_at"))) ?? Date(),
            updatedAt: parseDate((try? cursor.getString(name: "updated_at"))) ?? Date(),
            galleryId: try? cursor.getString(name: "gallery_id")
        )
    }

    private nonisolated static func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - FP Sports Subjects (Production subjects table via PowerSync)

    /// Save a subject — UPDATE for existing, INSERT only for new.
    /// This prevents NULLing out Production-managed fields (school_id, qr_code, custom1-20, etc.)
    ///
    /// Phase G G.5 (Layer 2 wrapper): refuses with
    /// PowerSyncManagerError.writeBlockedDuringActiveCaptureSession when
    /// the subject's gallery_id is in an active FP capture session on
    /// this iPad. UI sites must route through SubjectSyncService instead;
    /// this method's only legitimate post-Phase-C/D callers are
    /// SubjectSyncService's internal paths (none of which are inside
    /// the Phase D fallback anymore — that fallback was deleted in
    /// commit 6d8776e).
    func saveSubject(_ subject: FPSubject) async throws {
        if isGalleryInActiveCaptureSession(subject.galleryId) {
            throw PowerSyncManagerError.writeBlockedDuringActiveCaptureSession(galleryId: subject.galleryId)
        }
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let idString = subject.id.uuidString.lowercased()
        let updatedAtISO = ISO8601DateFormatter().string(from: subject.updatedAt)
        let createdAtISO = ISO8601DateFormatter().string(from: subject.createdAt)
        let lockedByString: String? = subject.lockedBy?.uuidString.lowercased()
        let lockedAtISO: String? = subject.lockedAt.map { ISO8601DateFormatter().string(from: $0) }

        // Check if subject already exists
        let existing: [String] = try await db.getAll(
            sql: "SELECT id FROM subjects WHERE id = ?",
            parameters: [idString],
            mapper: { cursor in try cursor.getString(name: "id") }
        )

        if !existing.isEmpty {
            // UPDATE — every editable column on the iPad subject editor
            _ = try await db.execute(
                sql: """
                    UPDATE subjects SET
                        first_name = ?, last_name = ?, grade = ?, teacher = ?, homeroom = ?,
                        student_id = ?, roster_id = ?, jersey_number = ?, sport = ?, position = ?,
                        organization_name = ?, year = ?, subject_type = ?, title = ?, reference_number = ?,
                        photographer = ?, photo_session_date = ?, expiration_date = ?,
                        email = ?, phone = ?, phone2 = ?, address1 = ?, address2 = ?,
                        city = ?, state = ?, zip = ?, country = ?,
                        mother = ?, father = ?, online_code = ?, personalization = ?, discount_code = ?,
                        custom1 = ?, custom2 = ?, custom3 = ?, custom4 = ?, custom5 = ?,
                        custom6 = ?, custom7 = ?, custom8 = ?, custom9 = ?, custom10 = ?,
                        custom11 = ?, custom12 = ?, custom13 = ?, custom14 = ?, custom15 = ?,
                        custom16 = ?, custom17 = ?, custom18 = ?, custom19 = ?, custom20 = ?,
                        image_numbers = ?, notes = ?,
                        image_count = ?, is_absent = ?, is_photographed = ?, needs_retake = ?,
                        checked_in_at = ?, locked_by = ?, locked_by_name = ?, locked_at = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                parameters: [
                    subject.firstName, subject.lastName, subject.grade, subject.teacher, subject.homeroom,
                    subject.studentId, subject.rosterId, subject.jerseyNumber, subject.sport, subject.position,
                    subject.organizationName, subject.year, subject.subjectType, subject.title, subject.referenceNumber,
                    subject.photographer, subject.photoSessionDate, subject.expirationDate,
                    subject.email, subject.phone, subject.phone2, subject.address1, subject.address2,
                    subject.city, subject.state, subject.zip, subject.country,
                    subject.mother, subject.father, subject.onlineCode, subject.personalization, subject.discountCode,
                    subject.custom1, subject.custom2, subject.custom3, subject.custom4, subject.custom5,
                    subject.custom6, subject.custom7, subject.custom8, subject.custom9, subject.custom10,
                    subject.custom11, subject.custom12, subject.custom13, subject.custom14, subject.custom15,
                    subject.custom16, subject.custom17, subject.custom18, subject.custom19, subject.custom20,
                    subject.imageNumbers, subject.notes,
                    subject.imageCount, subject.isAbsent ? 1 : 0, subject.isPhotographed ? 1 : 0, subject.needsRetake ? 1 : 0,
                    subject.checkedInAt, lockedByString, subject.lockedByName, lockedAtISO,
                    updatedAtISO,
                    idString
                ]
            )
        } else {
            // INSERT — new subject, set every column the iPad supports
            _ = try await db.execute(
                sql: """
                    INSERT INTO subjects
                    (id, gallery_id, organization_id, first_name, last_name, grade, teacher, homeroom,
                     student_id, roster_id, jersey_number, sport, position,
                     organization_name, year, subject_type, title, reference_number,
                     photographer, photo_session_date, expiration_date,
                     email, phone, phone2, address1, address2, city, state, zip, country,
                     mother, father, online_code, personalization, discount_code,
                     custom1, custom2, custom3, custom4, custom5, custom6, custom7, custom8, custom9, custom10,
                     custom11, custom12, custom13, custom14, custom15, custom16, custom17, custom18, custom19, custom20,
                     image_numbers, notes, image_count, is_absent, is_photographed, needs_retake,
                     checked_in_at, locked_by, locked_by_name, locked_at, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?, ?)
                    """,
                parameters: [
                    idString, subject.galleryId, subject.organizationId,
                    subject.firstName, subject.lastName, subject.grade, subject.teacher, subject.homeroom,
                    subject.studentId, subject.rosterId, subject.jerseyNumber, subject.sport, subject.position,
                    subject.organizationName, subject.year, subject.subjectType, subject.title, subject.referenceNumber,
                    subject.photographer, subject.photoSessionDate, subject.expirationDate,
                    subject.email, subject.phone, subject.phone2, subject.address1, subject.address2,
                    subject.city, subject.state, subject.zip, subject.country,
                    subject.mother, subject.father, subject.onlineCode, subject.personalization, subject.discountCode,
                    subject.custom1, subject.custom2, subject.custom3, subject.custom4, subject.custom5,
                    subject.custom6, subject.custom7, subject.custom8, subject.custom9, subject.custom10,
                    subject.custom11, subject.custom12, subject.custom13, subject.custom14, subject.custom15,
                    subject.custom16, subject.custom17, subject.custom18, subject.custom19, subject.custom20,
                    subject.imageNumbers, subject.notes,
                    subject.imageCount, subject.isAbsent ? 1 : 0, subject.isPhotographed ? 1 : 0, subject.needsRetake ? 1 : 0,
                    subject.checkedInAt, lockedByString, subject.lockedByName, lockedAtISO,
                    createdAtISO, updatedAtISO
                ]
            )
        }

        print("PowerSyncManager: Saved subject \(idString)")

        // Sync rewrite — emit a structured event for every local subject
        // save. Pure observability; the SQLite write above is unchanged.
        // Mirrors update_subject_bg's hook on the Mac side.
        await MainActor.run {
            SubjectSyncEvents.shared.emit(SubjectSyncEvent(
                deviceId: UserDefaults.standard.string(forKey: "fp_sync_device_id") ?? "unknown",
                deviceRole: "iPad",
                operation: .update,
                outcome: .sent,
                sourcePath: "PowerSyncManager.saveSubject",
                subjectId: idString,
                galleryId: subject.galleryId
            ))
        }
    }

    /// Soft-delete a subject (matches Production's soft-delete pattern)
    ///
    /// Phase G G.5 (Layer 2 wrapper): refuses with
    /// PowerSyncManagerError.writeBlockedDuringActiveCaptureSession when
    /// any active FP capture session is registered on this iPad. The
    /// signature only carries the subject id, not the gallery — so the
    /// guard refuses conservatively when ANY session is active rather
    /// than doing a SQL round-trip to discover the row's gallery_id.
    /// All legitimate post-Phase-C/D callers route through
    /// SubjectSyncService (which has the gallery_id).
    func deleteSubject(id: UUID) async throws {
        if hasAnyActiveCaptureSession {
            let gid = firstActiveCaptureSessionGalleryId ?? "unknown"
            throw PowerSyncManagerError.writeBlockedDuringActiveCaptureSession(galleryId: gid)
        }
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let idString = id.uuidString.lowercased()
        let now = ISO8601DateFormatter().string(from: Date())

        _ = try await db.execute(
            sql: "UPDATE subjects SET is_deleted = 'true', deleted_at = ?, updated_at = ? WHERE id = ?",
            parameters: [now, now, idString]
        )

        print("PowerSyncManager: Soft-deleted subject \(idString)")
    }

    /// Batch soft-delete multiple subjects using a single SQL statement
    ///
    /// Phase G G.5 (Layer 2 wrapper): same conservative refusal as
    /// deleteSubject — the signature lacks gallery context, so any
    /// registered active session blocks the call. Phase G G.6 migrated
    /// the sole caller (FPSportsRosterView_iPad batchDeleteRosterEntries)
    /// to route through SubjectSyncService.batchDeleteSubjects, so this
    /// method should never be called from UI code post-Phase-G.
    func deleteBatchSubjects(ids: [UUID]) async throws {
        if hasAnyActiveCaptureSession {
            let gid = firstActiveCaptureSessionGalleryId ?? "unknown"
            throw PowerSyncManagerError.writeBlockedDuringActiveCaptureSession(galleryId: gid)
        }
        guard let db = database else { throw PowerSyncManagerError.notInitialized }
        guard !ids.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let sql = "UPDATE subjects SET is_deleted = 'true', deleted_at = ?, updated_at = ? WHERE id IN (\(placeholders))"
        let params: [Any] = [now, now] + ids.map { $0.uuidString.lowercased() }
        _ = try await db.execute(sql: sql, parameters: params)
        print("PowerSyncManager: Batch soft-deleted \(ids.count) subjects")
    }

    /// Clear expired subject locks (>2 minutes old) — same pattern as RosterEntryService.releaseExpiredLocks
    func releaseExpiredSubjectLocks(forGalleryId galleryId: String) async throws {
        guard let db = database else { return }
        let twoMinutesAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120))
        _ = try await db.execute(
            sql: "UPDATE subjects SET locked_by = NULL, locked_by_name = NULL, locked_at = NULL WHERE gallery_id = ? AND locked_at IS NOT NULL AND locked_at < ?",
            parameters: [galleryId, twoMinutesAgo]
        )
    }

    // MARK: - Gallery Pinning (selective sync)

    /// Pin a gallery for selective sync — tells PowerSync to sync this gallery's subjects
    func pinGallery(userId: String, galleryId: String, organizationId: String) async throws {
        guard let db = database else { throw PowerSyncManagerError.notInitialized }

        // Check if already pinned
        let existing: [String] = try await db.getAll(
            sql: "SELECT id FROM synced_galleries WHERE user_id = ? AND gallery_id = ?",
            parameters: [userId, galleryId],
            mapper: { cursor in try cursor.getString(name: "id") }
        )
        if !existing.isEmpty {
            print("PowerSyncManager: Gallery \(galleryId) already pinned")
            return
        }

        let id = UUID().uuidString.lowercased() // Must be valid UUID — Supabase column is uuid type
        let now = ISO8601DateFormatter().string(from: Date())

        _ = try await db.execute(
            sql: """
                INSERT OR REPLACE INTO synced_galleries (id, gallery_id, user_id, organization_id, synced_at)
                VALUES (?, ?, ?, ?, ?)
                """,
            parameters: [id, galleryId, userId, organizationId, now]
        )

        print("PowerSyncManager: Pinned gallery \(galleryId)")
    }

    /// Unpin a gallery — stop syncing its subjects.
    ///
    /// Phase AC H1.15 — after the synced_galleries DELETE, purge the
    /// SubscriptionCache's persisted state for the gallery. The user
    /// explicitly chose to unpin, so the cache must not survive past the
    /// unpin event. In-memory + disk both cleared via
    /// SubscriptionCache.purgeGallery.
    func unpinGallery(userId: String, galleryId: String) async throws {
        guard let db = database else { throw PowerSyncManagerError.notInitialized }

        // Match by (user_id, gallery_id) — the row's `id` is a random UUID
        // assigned at pin time, so deleting by a "userId_galleryId" composite
        // never matched and galleries could never be unpinned.
        _ = try await db.execute(
            sql: "DELETE FROM synced_galleries WHERE user_id = ? AND gallery_id = ?",
            parameters: [userId, galleryId]
        )

        SubscriptionCache.shared.purgeGallery(galleryId)

        print("PowerSyncManager: Unpinned gallery \(galleryId)")
    }

    // MARK: - FP Subject Parsing

    private nonisolated static func parseSubject(from cursor: SqlCursor) throws -> FPSubject {
        let idString = try cursor.getString(name: "id")

        guard let id = UUID(uuidString: idString) else {
            throw PowerSyncManagerError.invalidData
        }

        return FPSubject(
            id: id,
            galleryId: (try? cursor.getString(name: "gallery_id")) ?? "",
            organizationId: (try? cursor.getString(name: "organization_id")) ?? "",
            firstName: (try? cursor.getString(name: "first_name")) ?? "",
            lastName: (try? cursor.getString(name: "last_name")) ?? "",
            grade: (try? cursor.getString(name: "grade")) ?? "",
            teacher: (try? cursor.getString(name: "teacher")) ?? "",
            homeroom: (try? cursor.getString(name: "homeroom")) ?? "",
            studentId: (try? cursor.getString(name: "student_id")) ?? "",
            rosterId: (try? cursor.getString(name: "roster_id")) ?? "",
            jerseyNumber: (try? cursor.getString(name: "jersey_number")) ?? "",
            sport: (try? cursor.getString(name: "sport")) ?? "",
            position: (try? cursor.getString(name: "position")) ?? "",
            organizationName: (try? cursor.getString(name: "organization_name")) ?? "",
            year: (try? cursor.getString(name: "year")) ?? "",
            subjectType: (try? cursor.getString(name: "subject_type")) ?? "",
            title: (try? cursor.getString(name: "title")) ?? "",
            referenceNumber: (try? cursor.getString(name: "reference_number")) ?? "",
            photographer: (try? cursor.getString(name: "photographer")) ?? "",
            photoSessionDate: (try? cursor.getString(name: "photo_session_date")) ?? "",
            expirationDate: (try? cursor.getString(name: "expiration_date")) ?? "",
            email: (try? cursor.getString(name: "email")) ?? "",
            phone: (try? cursor.getString(name: "phone")) ?? "",
            phone2: (try? cursor.getString(name: "phone2")) ?? "",
            address1: (try? cursor.getString(name: "address1")) ?? "",
            address2: (try? cursor.getString(name: "address2")) ?? "",
            city: (try? cursor.getString(name: "city")) ?? "",
            state: (try? cursor.getString(name: "state")) ?? "",
            zip: (try? cursor.getString(name: "zip")) ?? "",
            country: (try? cursor.getString(name: "country")) ?? "",
            mother: (try? cursor.getString(name: "mother")) ?? "",
            father: (try? cursor.getString(name: "father")) ?? "",
            onlineCode: (try? cursor.getString(name: "online_code")) ?? "",
            personalization: (try? cursor.getString(name: "personalization")) ?? "",
            discountCode: (try? cursor.getString(name: "discount_code")) ?? "",
            custom1: (try? cursor.getString(name: "custom1")) ?? "",
            custom2: (try? cursor.getString(name: "custom2")) ?? "",
            custom3: (try? cursor.getString(name: "custom3")) ?? "",
            custom4: (try? cursor.getString(name: "custom4")) ?? "",
            custom5: (try? cursor.getString(name: "custom5")) ?? "",
            custom6: (try? cursor.getString(name: "custom6")) ?? "",
            custom7: (try? cursor.getString(name: "custom7")) ?? "",
            custom8: (try? cursor.getString(name: "custom8")) ?? "",
            custom9: (try? cursor.getString(name: "custom9")) ?? "",
            custom10: (try? cursor.getString(name: "custom10")) ?? "",
            custom11: (try? cursor.getString(name: "custom11")) ?? "",
            custom12: (try? cursor.getString(name: "custom12")) ?? "",
            custom13: (try? cursor.getString(name: "custom13")) ?? "",
            custom14: (try? cursor.getString(name: "custom14")) ?? "",
            custom15: (try? cursor.getString(name: "custom15")) ?? "",
            custom16: (try? cursor.getString(name: "custom16")) ?? "",
            custom17: (try? cursor.getString(name: "custom17")) ?? "",
            custom18: (try? cursor.getString(name: "custom18")) ?? "",
            custom19: (try? cursor.getString(name: "custom19")) ?? "",
            custom20: (try? cursor.getString(name: "custom20")) ?? "",
            imageCount: (try? cursor.getIntOptional(name: "image_count")) ?? 0,
            isAbsent: (try? cursor.getIntOptional(name: "is_absent")).flatMap { $0 }.map { $0 == 1 } ?? false,
            isPhotographed: (try? cursor.getIntOptional(name: "is_photographed")).flatMap { $0 }.map { $0 == 1 } ?? false,
            needsRetake: (try? cursor.getIntOptional(name: "needs_retake")).flatMap { $0 }.map { $0 == 1 } ?? false,
            checkedInAt: try? cursor.getString(name: "checked_in_at"),
            imageNumbers: (try? cursor.getString(name: "image_numbers")) ?? "",
            notes: (try? cursor.getString(name: "notes")) ?? "",
            createdAt: parseDate((try? cursor.getString(name: "created_at"))) ?? Date(),
            updatedAt: parseDate((try? cursor.getString(name: "updated_at"))) ?? Date(),
            lockedBy: (try? cursor.getString(name: "locked_by")).flatMap { UUID(uuidString: $0) },
            lockedByName: try? cursor.getString(name: "locked_by_name"),
            lockedAt: parseDate((try? cursor.getString(name: "locked_at")))
        )
    }
}
