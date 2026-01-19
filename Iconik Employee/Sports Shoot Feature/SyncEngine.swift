//
//  SyncEngine.swift
//  Iconik Employee
//
//  Coordinates offline-first sync operations for roster entries and group images
//  Queues changes when offline, syncs when online, handles conflicts
//

import Foundation
import Combine
import Network

// MARK: - Sync Operation Types

enum SyncOperationType: String, Codable {
    case insert
    case update
    case delete
}

enum SyncItemType: String, Codable {
    case rosterEntry
    case groupImage
    case sportsShoot
}

enum SyncStatus: String, Codable {
    case pending
    case syncing
    case synced
    case conflict
    case failed
}

struct SyncQueueItem: Identifiable, Codable {
    let id: UUID
    let itemType: SyncItemType
    let operation: SyncOperationType
    let recordId: UUID
    let jobId: UUID
    let payload: Data  // JSON encoded RosterEntry or GroupImage
    let baseVersion: Int  // Version when edit started
    let createdAt: Date
    var status: SyncStatus
    var errorMessage: String?
    var retryCount: Int

    init(
        id: UUID = UUID(),
        itemType: SyncItemType,
        operation: SyncOperationType,
        recordId: UUID,
        jobId: UUID,
        payload: Data,
        baseVersion: Int,
        createdAt: Date = Date(),
        status: SyncStatus = .pending,
        errorMessage: String? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.itemType = itemType
        self.operation = operation
        self.recordId = recordId
        self.jobId = jobId
        self.payload = payload
        self.baseVersion = baseVersion
        self.createdAt = createdAt
        self.status = status
        self.errorMessage = errorMessage
        self.retryCount = retryCount
    }
}

// MARK: - Conflict Info

struct ConflictInfo: Identifiable {
    let id: UUID
    let itemType: SyncItemType
    let recordId: UUID
    let localVersion: Int
    let serverVersion: Int
    let localData: Any  // RosterEntry or GroupImage
    let serverData: Any
    let queueItemId: UUID
}

// MARK: - Sync Engine

@MainActor
class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    // Published state
    @Published private(set) var isOnline = true
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var activeConflicts: [ConflictInfo] = []

    // Sync queue (persisted to UserDefaults for simplicity - could use Core Data)
    private var syncQueue: [SyncQueueItem] = []
    private let syncQueueKey = "SportsShootSyncQueue"

    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")

    // Services
    private let rosterService = RosterEntryService.shared
    private let groupService = GroupImageService.shared

    // Sync timer
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 10  // Check every 10 seconds when online

    // Max retries before marking as failed
    private let maxRetries = 3

    private init() {
        loadSyncQueue()
        startNetworkMonitoring()
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                let wasOnline = self?.isOnline ?? false
                let nowOnline = path.status == .satisfied
                self?.isOnline = nowOnline

                // Force NetworkMonitor to recheck its status too (keeps both monitors in sync)
                _ = NetworkMonitor.shared.getCurrentConnectionStatus()

                // Post notification when status changes so UI updates
                if wasOnline != nowOnline {
                    print("SyncEngine: Network status changed to \(nowOnline ? "online" : "offline")")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NetworkStatusChanged"),
                        object: nil,
                        userInfo: ["isConnected": nowOnline]
                    )
                }

                // If we just came online, trigger sync
                if !wasOnline && nowOnline {
                    print("SyncEngine: Network restored, triggering sync")
                    await self?.syncNow()
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Sync Control

    /// Start the automatic sync timer
    func startSyncing() {
        guard syncTimer == nil else { return }

        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isOnline, !self.isSyncing else { return }
                await self.processPendingOperations()
            }
        }

        // Also sync immediately if online
        if isOnline {
            Task {
                await syncNow()
            }
        }
    }

    /// Stop automatic syncing
    func stopSyncing() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    /// Trigger an immediate sync
    func syncNow() async {
        guard isOnline, !isSyncing else { return }
        await processPendingOperations()
    }

    // MARK: - Queue Management

    /// Add a roster entry operation to the sync queue
    func queueRosterEntryOperation(
        operation: SyncOperationType,
        entry: RosterEntry,
        jobId: UUID
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let payload = try? encoder.encode(entry) else {
            print("SyncEngine: Failed to encode roster entry")
            return
        }

        let item = SyncQueueItem(
            itemType: .rosterEntry,
            operation: operation,
            recordId: entry.id,
            jobId: jobId,
            payload: payload,
            baseVersion: entry.version
        )

        // Update local cache for immediate UI consistency (offline-first)
        switch operation {
        case .insert, .update:
            LocalSportsRepository.shared.updateRosterEntry(entry, forJob: jobId)
        case .delete:
            LocalSportsRepository.shared.deleteRosterEntry(id: entry.id, forJob: jobId)
        }

        addToQueue(item)
    }

    /// Add a group image operation to the sync queue
    func queueGroupImageOperation(
        operation: SyncOperationType,
        group: GroupImage,
        jobId: UUID
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let payload = try? encoder.encode(group) else {
            print("SyncEngine: Failed to encode group image")
            return
        }

        let item = SyncQueueItem(
            itemType: .groupImage,
            operation: operation,
            recordId: group.id,
            jobId: jobId,
            payload: payload,
            baseVersion: group.version
        )

        // Update local cache for immediate UI consistency (offline-first)
        switch operation {
        case .insert, .update:
            LocalSportsRepository.shared.updateGroupImage(group, forJob: jobId)
        case .delete:
            LocalSportsRepository.shared.deleteGroupImage(id: group.id, forJob: jobId)
        }

        addToQueue(item)
    }

    /// Add a sports shoot operation to the sync queue
    func queueSportsShootOperation(
        operation: SyncOperationType,
        shoot: SportsShoot
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let payload = try? encoder.encode(shoot) else {
            print("SyncEngine: Failed to encode sports shoot")
            return
        }

        let item = SyncQueueItem(
            itemType: .sportsShoot,
            operation: operation,
            recordId: shoot.id,
            jobId: shoot.id,  // Use shoot ID as job ID for shoots
            payload: payload,
            baseVersion: 1  // Sports shoots don't have versioning yet
        )

        // Update local cache for immediate UI consistency (offline-first)
        LocalSportsRepository.shared.saveSportsShoot(shoot)

        addToQueue(item)
    }

    private func addToQueue(_ item: SyncQueueItem) {
        // Remove any existing pending operation for the same record
        syncQueue.removeAll { $0.recordId == item.recordId && $0.status == .pending }

        syncQueue.append(item)
        pendingCount = syncQueue.filter { $0.status == .pending }.count
        saveSyncQueue()

        print("SyncEngine: Queued \(item.operation) for \(item.itemType) \(item.recordId)")

        // If online, try to sync immediately
        if isOnline && !isSyncing {
            Task {
                await processPendingOperations()
            }
        }
    }

    // MARK: - Pending Items Helpers

    /// Get all pending roster entry operations for a job (for merging with server data)
    func getPendingRosterOperations(forJob jobId: UUID) -> [(operation: SyncOperationType, entry: RosterEntry)] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return syncQueue
            .filter { $0.itemType == .rosterEntry && $0.jobId == jobId && $0.status == .pending }
            .compactMap { item -> (SyncOperationType, RosterEntry)? in
                guard let entry = try? decoder.decode(RosterEntry.self, from: item.payload) else { return nil }
                return (item.operation, entry)
            }
    }

    /// Get all pending group image operations for a job (for merging with server data)
    func getPendingGroupOperations(forJob jobId: UUID) -> [(operation: SyncOperationType, group: GroupImage)] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return syncQueue
            .filter { $0.itemType == .groupImage && $0.jobId == jobId && $0.status == .pending }
            .compactMap { item -> (SyncOperationType, GroupImage)? in
                guard let group = try? decoder.decode(GroupImage.self, from: item.payload) else { return nil }
                return (item.operation, group)
            }
    }

    /// Get IDs of entries with pending operations for a job (for protecting from realtime overwrites)
    func getPendingEntryIds(forJob jobId: UUID) -> Set<UUID> {
        return Set(
            syncQueue
                .filter { $0.itemType == .rosterEntry && $0.jobId == jobId && $0.status == .pending }
                .map { $0.recordId }
        )
    }

    /// Get IDs of groups with pending operations for a job (for protecting from realtime overwrites)
    func getPendingGroupIds(forJob jobId: UUID) -> Set<UUID> {
        return Set(
            syncQueue
                .filter { $0.itemType == .groupImage && $0.jobId == jobId && $0.status == .pending }
                .map { $0.recordId }
        )
    }

    /// Clear all active conflicts (call after successful sync or manual resolution)
    func clearAllConflicts() {
        activeConflicts.removeAll()
        saveSyncQueue()
    }

    // MARK: - Sync Processing

    private func processPendingOperations() async {
        guard !isSyncing else { return }

        let pendingItems = syncQueue.filter { $0.status == .pending }
        guard !pendingItems.isEmpty else { return }

        isSyncing = true
        defer {
            isSyncing = false
            pendingCount = syncQueue.filter { $0.status == .pending }.count
        }

        print("SyncEngine: Processing \(pendingItems.count) pending operations")

        for item in pendingItems {
            guard isOnline else {
                print("SyncEngine: Lost connection, stopping sync")
                break
            }

            do {
                try await processItem(item)
                markItemSynced(item.id)
            } catch let error as SyncConflictError {
                await handleConflict(item: item, serverData: error.serverData)
            } catch {
                handleError(item: item, error: error)
            }
        }

        lastSyncTime = Date()
        saveSyncQueue()

        // Clean up old synced items (keep for 24 hours for debugging)
        cleanupSyncedItems()
    }

    private func processItem(_ item: SyncQueueItem) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        switch item.itemType {
        case .rosterEntry:
            try await processRosterEntry(item, decoder: decoder)
        case .groupImage:
            try await processGroupImage(item, decoder: decoder)
        case .sportsShoot:
            try await processSportsShoot(item, decoder: decoder)
        }
    }

    private func processRosterEntry(_ item: SyncQueueItem, decoder: JSONDecoder) async throws {
        guard let entry = try? decoder.decode(RosterEntry.self, from: item.payload) else {
            throw SyncError.invalidPayload
        }

        switch item.operation {
        case .insert:
            _ = try await rosterService.createEntry(entry)

        case .update:
            // Check for conflict
            let serverVersion = try await rosterService.getCurrentVersion(entryId: entry.id)
            if serverVersion != item.baseVersion {
                let serverEntry = try await rosterService.fetchEntry(id: entry.id)
                throw SyncConflictError(serverData: serverEntry, serverVersion: serverVersion)
            }
            _ = try await rosterService.updateEntry(entry)

        case .delete:
            try await rosterService.deleteEntry(id: entry.id)
        }
    }

    private func processGroupImage(_ item: SyncQueueItem, decoder: JSONDecoder) async throws {
        guard let group = try? decoder.decode(GroupImage.self, from: item.payload) else {
            throw SyncError.invalidPayload
        }

        switch item.operation {
        case .insert:
            _ = try await groupService.createGroup(group)

        case .update:
            // Check for conflict
            let serverVersion = try await groupService.getCurrentVersion(groupId: group.id)
            if serverVersion != item.baseVersion {
                let serverGroup = try await groupService.fetchGroup(id: group.id)
                throw SyncConflictError(serverData: serverGroup, serverVersion: serverVersion)
            }
            _ = try await groupService.updateGroup(group)

        case .delete:
            try await groupService.deleteGroup(id: group.id)
        }
    }

    private func processSportsShoot(_ item: SyncQueueItem, decoder: JSONDecoder) async throws {
        guard let shoot = try? decoder.decode(SportsShoot.self, from: item.payload) else {
            throw SyncError.invalidPayload
        }

        switch item.operation {
        case .insert:
            _ = try await SportsShootService.shared.createSportsShoot(shoot)
        case .update:
            try await SportsShootService.shared.updateSportsShoot(shoot)
        case .delete:
            try await SportsShootService.shared.deleteSportsShoot(id: shoot.id)
        }
    }

    // MARK: - Conflict Handling

    private func handleConflict(item: SyncQueueItem, serverData: Any) async {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var localData: Any?
        var serverVersion = 0

        switch item.itemType {
        case .rosterEntry:
            if let entry = try? decoder.decode(RosterEntry.self, from: item.payload) {
                localData = entry
            }
            if let serverEntry = serverData as? RosterEntry {
                serverVersion = serverEntry.version
            }
        case .groupImage:
            if let group = try? decoder.decode(GroupImage.self, from: item.payload) {
                localData = group
            }
            if let serverGroup = serverData as? GroupImage {
                serverVersion = serverGroup.version
            }
        case .sportsShoot:
            // Sports shoots don't have conflict resolution yet - just use local version
            if let shoot = try? decoder.decode(SportsShoot.self, from: item.payload) {
                localData = shoot
                serverVersion = 1
            }
        }

        guard let local = localData else {
            markItemFailed(item.id, error: "Failed to decode local data")
            return
        }

        // Mark item as conflict
        if let index = syncQueue.firstIndex(where: { $0.id == item.id }) {
            syncQueue[index].status = .conflict
        }

        let conflict = ConflictInfo(
            id: UUID(),
            itemType: item.itemType,
            recordId: item.recordId,
            localVersion: item.baseVersion,
            serverVersion: serverVersion,
            localData: local,
            serverData: serverData,
            queueItemId: item.id
        )

        activeConflicts.append(conflict)
        saveSyncQueue()

        print("SyncEngine: Conflict detected for \(item.itemType) \(item.recordId)")
    }

    /// Resolve a conflict by choosing local or server data
    func resolveConflict(
        conflictId: UUID,
        resolution: ConflictResolution
    ) async {
        guard let conflictIndex = activeConflicts.firstIndex(where: { $0.id == conflictId }) else {
            return
        }

        let conflict = activeConflicts[conflictIndex]

        switch resolution {
        case .keepLocal:
            // Re-queue with updated base version
            if let queueIndex = syncQueue.firstIndex(where: { $0.id == conflict.queueItemId }) {
                var updatedItem = syncQueue[queueIndex]
                updatedItem.status = .pending

                // Update the payload with new version
                if conflict.itemType == .rosterEntry, var entry = conflict.localData as? RosterEntry {
                    entry.version = conflict.serverVersion
                    if let newPayload = try? JSONEncoder().encode(entry) {
                        syncQueue[queueIndex] = SyncQueueItem(
                            id: updatedItem.id,
                            itemType: updatedItem.itemType,
                            operation: updatedItem.operation,
                            recordId: updatedItem.recordId,
                            jobId: updatedItem.jobId,
                            payload: newPayload,
                            baseVersion: conflict.serverVersion,
                            createdAt: updatedItem.createdAt,
                            status: .pending
                        )
                    }
                } else if conflict.itemType == .groupImage, var group = conflict.localData as? GroupImage {
                    group.version = conflict.serverVersion
                    if let newPayload = try? JSONEncoder().encode(group) {
                        syncQueue[queueIndex] = SyncQueueItem(
                            id: updatedItem.id,
                            itemType: updatedItem.itemType,
                            operation: updatedItem.operation,
                            recordId: updatedItem.recordId,
                            jobId: updatedItem.jobId,
                            payload: newPayload,
                            baseVersion: conflict.serverVersion,
                            createdAt: updatedItem.createdAt,
                            status: .pending
                        )
                    }
                } else if conflict.itemType == .sportsShoot, let shoot = conflict.localData as? SportsShoot {
                    // Sports shoots don't have versioning - just re-queue
                    if let newPayload = try? JSONEncoder().encode(shoot) {
                        syncQueue[queueIndex] = SyncQueueItem(
                            id: updatedItem.id,
                            itemType: updatedItem.itemType,
                            operation: updatedItem.operation,
                            recordId: updatedItem.recordId,
                            jobId: updatedItem.jobId,
                            payload: newPayload,
                            baseVersion: 1,
                            createdAt: updatedItem.createdAt,
                            status: .pending
                        )
                    }
                }
            }

        case .keepServer:
            // Just remove from queue, server data is already correct
            syncQueue.removeAll { $0.id == conflict.queueItemId }
        }

        activeConflicts.remove(at: conflictIndex)
        saveSyncQueue()

        // Try to sync again
        if resolution == .keepLocal {
            await syncNow()
        }
    }

    // MARK: - Error Handling

    private func handleError(item: SyncQueueItem, error: Error) {
        guard let index = syncQueue.firstIndex(where: { $0.id == item.id }) else { return }

        syncQueue[index].retryCount += 1
        syncQueue[index].errorMessage = error.localizedDescription

        if syncQueue[index].retryCount >= maxRetries {
            syncQueue[index].status = .failed
            print("SyncEngine: Item \(item.id) failed after \(maxRetries) retries: \(error)")
        } else {
            print("SyncEngine: Item \(item.id) failed (retry \(syncQueue[index].retryCount)): \(error)")
        }

        saveSyncQueue()
    }

    private func markItemSynced(_ itemId: UUID) {
        if let index = syncQueue.firstIndex(where: { $0.id == itemId }) {
            syncQueue[index].status = .synced
        }
    }

    private func markItemFailed(_ itemId: UUID, error: String) {
        if let index = syncQueue.firstIndex(where: { $0.id == itemId }) {
            syncQueue[index].status = .failed
            syncQueue[index].errorMessage = error
        }
    }

    // MARK: - Cleanup

    private func cleanupSyncedItems() {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)  // 24 hours ago
        syncQueue.removeAll { item in
            item.status == .synced && item.createdAt < cutoff
        }
    }

    /// Clear all failed items from the queue
    func clearFailedItems() {
        syncQueue.removeAll { $0.status == .failed }
        saveSyncQueue()
    }

    /// Retry all failed items
    func retryFailedItems() {
        for index in syncQueue.indices {
            if syncQueue[index].status == .failed {
                syncQueue[index].status = .pending
                syncQueue[index].retryCount = 0
                syncQueue[index].errorMessage = nil
            }
        }
        pendingCount = syncQueue.filter { $0.status == .pending }.count
        saveSyncQueue()

        Task {
            await syncNow()
        }
    }

    // MARK: - Persistence

    private func saveSyncQueue() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(syncQueue) {
            UserDefaults.standard.set(data, forKey: syncQueueKey)
        }
    }

    private func loadSyncQueue() {
        guard let data = UserDefaults.standard.data(forKey: syncQueueKey) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let queue = try? decoder.decode([SyncQueueItem].self, from: data) {
            syncQueue = queue
            pendingCount = queue.filter { $0.status == .pending }.count
        }
    }

    // MARK: - Debug

    var debugQueueStatus: String {
        let pending = syncQueue.filter { $0.status == .pending }.count
        let syncing = syncQueue.filter { $0.status == .syncing }.count
        let synced = syncQueue.filter { $0.status == .synced }.count
        let conflict = syncQueue.filter { $0.status == .conflict }.count
        let failed = syncQueue.filter { $0.status == .failed }.count

        return "Queue: \(pending) pending, \(syncing) syncing, \(synced) synced, \(conflict) conflict, \(failed) failed"
    }
}

// MARK: - Errors

enum SyncError: Error, LocalizedError {
    case invalidPayload
    case networkError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Invalid sync payload"
        case .networkError:
            return "Network error"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

struct SyncConflictError: Error {
    let serverData: Any
    let serverVersion: Int
}

enum ConflictResolution {
    case keepLocal
    case keepServer
}
