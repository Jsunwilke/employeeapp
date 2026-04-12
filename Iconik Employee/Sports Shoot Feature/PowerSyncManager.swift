//
//  PowerSyncManager.swift
//  Iconik Employee
//
//  Main manager for PowerSync offline-first sync
//  Replaces SyncEngine for roster entries and group images
//

import Foundation
import PowerSync
import Combine
import Network

/// Errors specific to PowerSync operations
enum PowerSyncManagerError: Error {
    case notInitialized
    case notConnected
    case invalidData
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

    /// Whether the PowerSync database is initialized and ready for operations
    var isReady: Bool { database != nil }

    // MARK: - Private Properties

    private var database: PowerSyncDatabaseProtocol?
    private let connector = SupabasePowerSyncConnector()

    // Network monitoring for airplane mode detection
    private var networkMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "PowerSyncNetworkMonitor")
    private var isConnecting = false
    private var syncStatusWatchTask: Task<Void, Never>?

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

    /// Watch PowerSync's sync status stream for upload/download state changes
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
            }
        }
    }

    /// Clear local database and re-sync from server.
    /// Use when the CRUD queue is stuck and preventing downloads.
    func clearAndReSync() async {
        guard let db = database else { return }
        do {
            try await db.disconnectAndClear()
            hasSynced = false
            isConnected = false
            try await connect()
            print("PowerSyncManager: Cleared local data and reconnected")
        } catch {
            print("PowerSyncManager: clearAndReSync failed: \(error)")
        }
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
            sql: "SELECT * FROM group_images WHERE sports_job_id = ? ORDER BY sort_order ASC",
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

        _ = try await db.execute(
            sql: """
                INSERT OR REPLACE INTO group_images
                (id, sports_job_id, organization_id, description, image_numbers, notes, sport, gender,
                 team_level, sort_order, version, updated_at, updated_by,
                 locked_by, locked_by_name, locked_at, created_at, photographer_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                idString,
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
                group.photographerId
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
                sql: "SELECT id, sports_job_id FROM group_images WHERE organization_id IS NULL OR organization_id = ''",
                parameters: [],
                mapper: { cursor in
                    let id = try cursor.getString(name: "id")
                    let jobId = try cursor.getString(name: "sports_job_id")
                    return ["id": id, "sports_job_id": jobId]
                }
            )

            guard !missing.isEmpty else { return }
            print("PowerSyncManager: Backfilling organization_id on \(missing.count) group_images")

            for row in missing {
                guard let id = row["id"], let jobId = row["sports_job_id"] else { continue }

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
                sql: "SELECT * FROM group_images WHERE sports_job_id = ? ORDER BY sort_order ASC",
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
        let jobIdString = try cursor.getString(name: "sports_job_id")

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
            photographerId: try? cursor.getString(name: "photographer_id")
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

    /// Fetch all subjects for a gallery
    func getSubjects(forGalleryId galleryId: String) async throws -> [FPSubject] {
        guard let db = database else {
            throw PowerSyncManagerError.notInitialized
        }

        let results: [FPSubject] = try await db.getAll(
            sql: "SELECT * FROM subjects WHERE gallery_id = ? AND (is_deleted IS NULL OR is_deleted != 'true') ORDER BY last_name ASC, first_name ASC",
            parameters: [galleryId],
            mapper: { cursor in
                try Self.parseSubject(from: cursor)
            }
        )

        return results
    }

    /// Save a subject — UPDATE for existing, INSERT only for new.
    /// This prevents NULLing out Production-managed fields (school_id, qr_code, custom1-20, etc.)
    func saveSubject(_ subject: FPSubject) async throws {
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
            // UPDATE — only iPad-managed fields (never overwrite Production-managed fields)
            _ = try await db.execute(
                sql: """
                    UPDATE subjects SET
                        first_name = ?, last_name = ?, grade = ?, teacher = ?, homeroom = ?,
                        student_id = ?, roster_id = ?, jersey_number = ?, sport = ?, position = ?,
                        email = ?, phone = ?, image_numbers = ?, notes = ?,
                        image_count = ?, is_absent = ?, is_photographed = ?, needs_retake = ?,
                        checked_in_at = ?, locked_by = ?, locked_by_name = ?, locked_at = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                parameters: [
                    subject.firstName, subject.lastName, subject.grade, subject.teacher, subject.homeroom,
                    subject.studentId, subject.rosterId, subject.jerseyNumber, subject.sport, subject.position,
                    subject.email, subject.phone, subject.imageNumbers, subject.notes,
                    subject.imageCount, subject.isAbsent ? 1 : 0, subject.isPhotographed ? 1 : 0, subject.needsRetake ? 1 : 0,
                    subject.checkedInAt, lockedByString, subject.lockedByName, lockedAtISO,
                    updatedAtISO,
                    idString
                ]
            )
        } else {
            // INSERT — new subject, set all fields
            _ = try await db.execute(
                sql: """
                    INSERT INTO subjects
                    (id, gallery_id, organization_id, first_name, last_name, grade, teacher, homeroom,
                     student_id, roster_id, jersey_number, sport, position, email, phone,
                     image_numbers, notes, image_count, is_absent, is_photographed, needs_retake,
                     checked_in_at, locked_by, locked_by_name, locked_at, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                parameters: [
                    idString, subject.galleryId, subject.organizationId,
                    subject.firstName, subject.lastName, subject.grade, subject.teacher, subject.homeroom,
                    subject.studentId, subject.rosterId, subject.jerseyNumber, subject.sport, subject.position,
                    subject.email, subject.phone,
                    subject.imageNumbers, subject.notes,
                    subject.imageCount, subject.isAbsent ? 1 : 0, subject.isPhotographed ? 1 : 0, subject.needsRetake ? 1 : 0,
                    subject.checkedInAt, lockedByString, subject.lockedByName, lockedAtISO,
                    createdAtISO, updatedAtISO
                ]
            )
        }

        print("PowerSyncManager: Saved subject \(idString)")
    }

    /// Soft-delete a subject (matches Production's soft-delete pattern)
    func deleteSubject(id: UUID) async throws {
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
    func deleteBatchSubjects(ids: [UUID]) async throws {
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

    /// Watch subjects for real-time updates (PowerSync reactive query)
    func watchSubjects(forGalleryId galleryId: String) -> AsyncThrowingStream<[FPSubject], Error> {
        guard let db = database else {
            return AsyncThrowingStream { $0.finish() }
        }

        do {
            return try db.watch(
                sql: "SELECT * FROM subjects WHERE gallery_id = ? AND (is_deleted IS NULL OR is_deleted != 'true') ORDER BY last_name ASC, first_name ASC",
                parameters: [galleryId],
                mapper: { cursor in
                    try Self.parseSubject(from: cursor)
                }
            )
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
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

    /// Unpin a gallery — stop syncing its subjects
    func unpinGallery(userId: String, galleryId: String) async throws {
        guard let db = database else { throw PowerSyncManagerError.notInitialized }

        let id = "\(userId)_\(galleryId)"

        _ = try await db.execute(
            sql: "DELETE FROM synced_galleries WHERE id = ?",
            parameters: [id]
        )

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
            email: (try? cursor.getString(name: "email")) ?? "",
            phone: (try? cursor.getString(name: "phone")) ?? "",
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
