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

    /// Whether the PowerSync database is initialized and ready for operations
    var isReady: Bool { database != nil }

    // MARK: - Private Properties

    private var database: PowerSyncDatabaseProtocol?
    private let connector = SupabasePowerSyncConnector()

    // Network monitoring for airplane mode detection
    private var networkMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "PowerSyncNetworkMonitor")
    private var isConnecting = false

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
        } catch {
            isConnecting = false
            print("PowerSyncManager: Connection failed: \(error)")
            throw error
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

        try? await db.disconnect()
        isConnected = false

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
                (id, sports_job_id, description, image_numbers, notes, sport, gender,
                 team_level, sort_order, version, updated_at, updated_by,
                 locked_by, locked_by_name, locked_at, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                idString,
                jobIdString,
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
                createdAtISO
            ]
        )

        print("PowerSyncManager: Saved group image \(idString)")
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
            createdAt: parseDate((try? cursor.getString(name: "created_at"))) ?? Date()
        )
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
}
