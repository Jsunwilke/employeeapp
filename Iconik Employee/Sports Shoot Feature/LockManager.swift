//
//  LockManager.swift
//  Iconik Employee
//
//  Centralized lock management for roster entries and group images
//  Handles lock acquisition, release, and heartbeat to keep locks alive
//

import Foundation
import Combine
import Supabase
import Realtime

enum LockType {
    case rosterEntry
    case groupImage
    case subject      // FP Sports — locks on Production subjects table
}

enum LockLostReason {
    case heartbeatFailed
    case expiredWhileOffline
    case takenByOtherUser
}

struct LockLostEvent: Identifiable {
    let id = UUID()
    let entryId: UUID
    let type: LockType
    let reason: LockLostReason
}

struct ActiveLock {
    let id: UUID
    let type: LockType
    let acquiredAt: Date
    var lastRefreshedAt: Date
}

@MainActor
class LockManager: ObservableObject {
    static let shared = LockManager()

    // Device session ID - unique per app launch, used to distinguish same user on different devices
    static let deviceSessionID = UUID().uuidString

    // Current user info (should be set on login)
    @Published var currentUserId: UUID?
    @Published var currentUserName: String = ""

    // Full editor identifier including device session (used for lock comparison)
    var currentEditorIdentifier: String {
        guard !currentUserName.isEmpty else { return "" }
        return "\(currentUserName) (\(String(Self.deviceSessionID.prefix(8))))"
    }

    // Active locks held by this user
    @Published private(set) var activeLocks: [ActiveLock] = []

    // Event published when a lock is lost (heartbeat fail, offline expiry, taken by other)
    @Published var lockLostEvent: LockLostEvent?

    // Heartbeat timer
    private var heartbeatTimer: Timer?
    private let heartbeatInterval: TimeInterval = 30 // Refresh every 30 seconds

    private init() {}

    // MARK: - Configuration

    /// Set the current user info (call on login)
    func setCurrentUser(userId: UUID, userName: String) {
        self.currentUserId = userId
        self.currentUserName = userName
    }

    /// Clear the current user info (call on logout)
    func clearCurrentUser() {
        // Capture credentials before clearing so releaseAllLocks can use them
        let capturedIdentifier = currentEditorIdentifier
        let locks = activeLocks

        // Clear state immediately
        self.currentUserId = nil
        self.currentUserName = ""
        self.activeLocks.removeAll()
        stopHeartbeat()

        // Release locks on server using captured credentials
        Task {
            for lock in locks {
                do {
                    switch lock.type {
                    case .rosterEntry:
                        try await RosterEntryService.shared.releaseLock(entryId: lock.id, userName: capturedIdentifier)
                    case .groupImage:
                        try await GroupImageService.shared.releaseLock(groupId: lock.id, userName: capturedIdentifier)
                    case .subject:
                        let supabase = SupabaseManager.shared.client
                        let updateData: [String: AnyJSON] = [
                            "locked_by": AnyJSON.null,
                            "locked_by_name": AnyJSON.null,
                            "locked_at": AnyJSON.null
                        ]
                        try await supabase
                            .from("subjects")
                            .update(updateData)
                            .eq("id", value: lock.id)
                            .eq("locked_by_name", value: capturedIdentifier)
                            .execute()
                    }
                } catch {
                    print("LockManager: Failed to release lock \(lock.id) on logout: \(error)")
                }
            }
        }
    }

    // MARK: - Lock Acquisition

    /// Acquire a lock on a roster entry
    func acquireRosterEntryLock(entryId: UUID) async -> Bool {
        guard let userId = currentUserId else {
            print("LockManager: No current user set")
            return false
        }

        do {
            // Use full editor identifier (includes device session ID) for lock name
            let acquired = try await RosterEntryService.shared.acquireLock(
                entryId: entryId,
                userId: userId,
                userName: currentEditorIdentifier
            )

            if acquired {
                let lock = ActiveLock(id: entryId, type: .rosterEntry, acquiredAt: Date(), lastRefreshedAt: Date())
                activeLocks.append(lock)
                startHeartbeatIfNeeded()
            }

            return acquired
        } catch {
            print("LockManager: Failed to acquire roster entry lock: \(error)")
            return false
        }
    }

    /// Acquire a lock on a group image
    func acquireGroupImageLock(groupId: UUID) async -> Bool {
        guard let userId = currentUserId else {
            print("LockManager: No current user set")
            return false
        }

        do {
            // Use full editor identifier (includes device session ID) for lock name
            let acquired = try await GroupImageService.shared.acquireLock(
                groupId: groupId,
                userId: userId,
                userName: currentEditorIdentifier
            )

            if acquired {
                let lock = ActiveLock(id: groupId, type: .groupImage, acquiredAt: Date(), lastRefreshedAt: Date())
                activeLocks.append(lock)
                startHeartbeatIfNeeded()
            }

            return acquired
        } catch {
            print("LockManager: Failed to acquire group image lock: \(error)")
            return false
        }
    }

    // MARK: - Lock Release

    /// Release a lock on a roster entry
    func releaseRosterEntryLock(entryId: UUID) async {
        guard currentUserId != nil else { return }

        do {
            try await RosterEntryService.shared.releaseLock(entryId: entryId, userName: currentEditorIdentifier)
            activeLocks.removeAll { $0.id == entryId && $0.type == .rosterEntry }
            stopHeartbeatIfNoLocks()
        } catch {
            print("LockManager: Failed to release roster entry lock: \(error)")
        }
    }

    // MARK: - FP Sports Subject Locks

    /// Acquire a lock on a Production subject (FP Sports)
    /// Same pattern as RosterEntryService.acquireLock — Supabase RPC, offline fallback
    func acquireSubjectLock(subjectId: UUID) async -> Bool {
        guard let userId = currentUserId else {
            print("LockManager: No current user set — allowing local subject edit")
            return true
        }

        let isOnline = PowerSyncManager.shared.isConnected
        guard isOnline else {
            print("LockManager: Offline — allowing local subject edit without remote lock")
            return true
        }

        do {
            let supabase = SupabaseManager.shared.client
            let result: AnyJSON = try await supabase
                .rpc("acquire_lock", params: [
                    "p_table_name": AnyJSON.string("subjects"),
                    "p_record_id": AnyJSON.string(subjectId.uuidString.lowercased()),
                    "p_user_id": AnyJSON.string(userId.uuidString.lowercased()),
                    "p_user_name": AnyJSON.string(currentEditorIdentifier)
                ])
                .execute()
                .value

            if case .object(let dict) = result,
               case .bool(let success) = dict["success"] {
                if success {
                    let lock = ActiveLock(id: subjectId, type: .subject, acquiredAt: Date(), lastRefreshedAt: Date())
                    activeLocks.append(lock)
                    startHeartbeatIfNeeded()
                } else if case .string(let lockedBy) = dict["locked_by"] {
                    print("LockManager: Subject lock held by \(lockedBy)")
                }
                return success
            }

            print("LockManager: Unexpected RPC response format — allowing local edit")
            return true
        } catch {
            print("LockManager: Network error acquiring subject lock — allowing local edit: \(error)")
            return true
        }
    }

    /// Release a lock on a Production subject
    /// Same pattern as RosterEntryService.releaseLock
    func releaseSubjectLock(subjectId: UUID) async {
        let isOnline = PowerSyncManager.shared.isConnected
        guard isOnline else {
            print("LockManager: Offline — skipping subject lock release, will expire in ≤2 min")
            return
        }

        do {
            let supabase = SupabaseManager.shared.client
            let updateData: [String: AnyJSON] = [
                "locked_by": AnyJSON.null,
                "locked_by_name": AnyJSON.null,
                "locked_at": AnyJSON.null
            ]
            try await supabase
                .from("subjects")
                .update(updateData)
                .eq("id", value: subjectId)
                .eq("locked_by_name", value: currentEditorIdentifier)
                .execute()

            activeLocks.removeAll { $0.id == subjectId && $0.type == .subject }
            stopHeartbeatIfNoLocks()
        } catch {
            print("LockManager: Failed to release subject lock: \(error)")
        }
    }

    /// Check if a subject is locked by this user
    func hasSubjectLock(subjectId: UUID) -> Bool {
        return activeLocks.contains { $0.id == subjectId && $0.type == .subject }
    }

    /// Release a lock on a group image
    func releaseGroupImageLock(groupId: UUID) async {
        guard currentUserId != nil else { return }

        do {
            try await GroupImageService.shared.releaseLock(groupId: groupId, userName: currentEditorIdentifier)
            activeLocks.removeAll { $0.id == groupId && $0.type == .groupImage }
            stopHeartbeatIfNoLocks()
        } catch {
            print("LockManager: Failed to release group image lock: \(error)")
        }
    }

    /// Release all active locks
    func releaseAllLocks() async {
        guard currentUserId != nil else { return }

        for lock in activeLocks {
            do {
                switch lock.type {
                case .rosterEntry:
                    try await RosterEntryService.shared.releaseLock(entryId: lock.id, userName: currentEditorIdentifier)
                case .groupImage:
                    try await GroupImageService.shared.releaseLock(groupId: lock.id, userName: currentEditorIdentifier)
                case .subject:
                    await releaseSubjectLock(subjectId: lock.id)
                }
            } catch {
                print("LockManager: Failed to release lock \(lock.id): \(error)")
            }
        }

        activeLocks.removeAll()
        stopHeartbeat()
    }

    // MARK: - Lock Status

    /// Check if a roster entry is locked by this user
    func hasRosterEntryLock(entryId: UUID) -> Bool {
        return activeLocks.contains { $0.id == entryId && $0.type == .rosterEntry }
    }

    /// Check if a group image is locked by this user
    func hasGroupImageLock(groupId: UUID) -> Bool {
        return activeLocks.contains { $0.id == groupId && $0.type == .groupImage }
    }

    /// Get the count of active locks
    var activeLockCount: Int {
        return activeLocks.count
    }

    // MARK: - Heartbeat

    private func startHeartbeatIfNeeded() {
        guard heartbeatTimer == nil, !activeLocks.isEmpty else { return }

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAllLocks()
            }
        }
    }

    private func stopHeartbeatIfNoLocks() {
        if activeLocks.isEmpty {
            stopHeartbeat()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    /// Refresh all active locks to prevent expiration
    private func refreshAllLocks() async {
        guard currentUserId != nil else { return }

        // Collect results first, then apply mutations (avoid mutating during iteration)
        var locksToRemove: [(UUID, LockType, LockLostReason)] = []
        var locksToUpdate: [UUID] = []

        for lock in activeLocks {
            // Check if lock has been offline too long (>120s since last successful refresh)
            if Date().timeIntervalSince(lock.lastRefreshedAt) > 120 {
                print("LockManager: Lock \(lock.id) expired while offline (no refresh for >120s)")
                locksToRemove.append((lock.id, lock.type, .expiredWhileOffline))
                continue
            }

            do {
                switch lock.type {
                case .rosterEntry:
                    try await RosterEntryService.shared.refreshLock(entryId: lock.id, userName: currentEditorIdentifier)
                case .groupImage:
                    try await GroupImageService.shared.refreshLock(groupId: lock.id, userName: currentEditorIdentifier)
                case .subject:
                    // Refresh subject lock by updating locked_at timestamp
                    let supabase = SupabaseManager.shared.client
                    try await supabase
                        .from("subjects")
                        .update(["locked_at": ISO8601DateFormatter().string(from: Date())])
                        .eq("id", value: lock.id)
                        .eq("locked_by_name", value: currentEditorIdentifier)
                        .execute()
                }
                locksToUpdate.append(lock.id)
            } catch {
                print("LockManager: Failed to refresh lock \(lock.id): \(error)")
                locksToRemove.append((lock.id, lock.type, .heartbeatFailed))
            }
        }

        // Apply mutations after iteration
        for id in locksToUpdate {
            if let index = activeLocks.firstIndex(where: { $0.id == id }) {
                activeLocks[index].lastRefreshedAt = Date()
            }
        }
        for (id, type, reason) in locksToRemove {
            activeLocks.removeAll { $0.id == id }
            lockLostEvent = LockLostEvent(entryId: id, type: type, reason: reason)
        }

        stopHeartbeatIfNoLocks()
    }

    // MARK: - App Lifecycle

    /// Call when app goes to background
    func handleAppBackground() {
        Task {
            await releaseAllLocks()
        }
    }

    /// Call when app returns to foreground - re-acquire locks for active editing
    func handleAppForeground() {
        // Locks are re-acquired by the view when it detects active editing
    }

    // MARK: - Network Reconnection

    /// Validate/re-acquire all active locks after coming back online
    /// Called when PowerSync transitions from disconnected to connected
    func handleNetworkReconnection() async {
        guard let userId = currentUserId else { return }

        // Collect results first, then apply mutations
        var locksToRemove: [(UUID, LockType)] = []
        var locksToUpdate: [UUID] = []

        for lock in activeLocks {
            do {
                var acquired = false
                switch lock.type {
                case .rosterEntry:
                    acquired = try await RosterEntryService.shared.acquireLock(
                        entryId: lock.id,
                        userId: userId,
                        userName: currentEditorIdentifier
                    )
                case .groupImage:
                    acquired = try await GroupImageService.shared.acquireLock(
                        groupId: lock.id,
                        userId: userId,
                        userName: currentEditorIdentifier
                    )
                case .subject:
                    acquired = await acquireSubjectLock(subjectId: lock.id)
                }

                if acquired {
                    locksToUpdate.append(lock.id)
                    print("LockManager: Lock \(lock.id) validated on reconnection")
                } else {
                    locksToRemove.append((lock.id, lock.type))
                    print("LockManager: Lock \(lock.id) taken by another user during offline period")
                }
            } catch {
                print("LockManager: Failed to validate lock \(lock.id) on reconnection: \(error)")
                // Network still flaky, keep local lock state but don't emit event yet
            }
        }

        // Apply mutations after iteration
        for id in locksToUpdate {
            if let index = activeLocks.firstIndex(where: { $0.id == id }) {
                activeLocks[index].lastRefreshedAt = Date()
            }
        }
        for (id, type) in locksToRemove {
            activeLocks.removeAll { $0.id == id }
            lockLostEvent = LockLostEvent(entryId: id, type: type, reason: .takenByOtherUser)
        }

        stopHeartbeatIfNoLocks()
    }

    /// Re-acquire a specific lock (used when returning from background)
    func reacquireLock(entryId: UUID, type: LockType) async -> Bool {
        guard let userId = currentUserId else { return false }

        do {
            var acquired = false
            switch type {
            case .rosterEntry:
                acquired = try await RosterEntryService.shared.acquireLock(
                    entryId: entryId,
                    userId: userId,
                    userName: currentEditorIdentifier
                )
            case .groupImage:
                acquired = try await GroupImageService.shared.acquireLock(
                    groupId: entryId,
                    userId: userId,
                    userName: currentEditorIdentifier
                )
            case .subject:
                acquired = await acquireSubjectLock(subjectId: entryId)
            }

            if acquired {
                // Add back to active locks if not already there
                if !activeLocks.contains(where: { $0.id == entryId }) {
                    activeLocks.append(ActiveLock(id: entryId, type: type, acquiredAt: Date(), lastRefreshedAt: Date()))
                } else if let index = activeLocks.firstIndex(where: { $0.id == entryId }) {
                    activeLocks[index].lastRefreshedAt = Date()
                }
                startHeartbeatIfNeeded()
            }

            return acquired
        } catch {
            print("LockManager: Failed to re-acquire lock \(entryId): \(error)")
            return false
        }
    }
}
