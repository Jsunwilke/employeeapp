//
//  LockManager.swift
//  Iconik Employee
//
//  Centralized lock management for roster entries and group images
//  Handles lock acquisition, release, and heartbeat to keep locks alive
//

import Foundation
import Combine

enum LockType {
    case rosterEntry
    case groupImage
}

struct ActiveLock {
    let id: UUID
    let type: LockType
    let acquiredAt: Date
}

@MainActor
class LockManager: ObservableObject {
    static let shared = LockManager()

    // Current user info (should be set on login)
    @Published var currentUserId: UUID?
    @Published var currentUserName: String = ""

    // Active locks held by this user
    @Published private(set) var activeLocks: [ActiveLock] = []

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
        Task {
            await releaseAllLocks()
        }
        self.currentUserId = nil
        self.currentUserName = ""
    }

    // MARK: - Lock Acquisition

    /// Acquire a lock on a roster entry
    func acquireRosterEntryLock(entryId: UUID) async -> Bool {
        guard let userId = currentUserId else {
            print("LockManager: No current user set")
            return false
        }

        do {
            let acquired = try await RosterEntryService.shared.acquireLock(
                entryId: entryId,
                userId: userId,
                userName: currentUserName
            )

            if acquired {
                let lock = ActiveLock(id: entryId, type: .rosterEntry, acquiredAt: Date())
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
            let acquired = try await GroupImageService.shared.acquireLock(
                groupId: groupId,
                userId: userId,
                userName: currentUserName
            )

            if acquired {
                let lock = ActiveLock(id: groupId, type: .groupImage, acquiredAt: Date())
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
        guard let userId = currentUserId else { return }

        do {
            try await RosterEntryService.shared.releaseLock(entryId: entryId, userId: userId)
            activeLocks.removeAll { $0.id == entryId && $0.type == .rosterEntry }
            stopHeartbeatIfNoLocks()
        } catch {
            print("LockManager: Failed to release roster entry lock: \(error)")
        }
    }

    /// Release a lock on a group image
    func releaseGroupImageLock(groupId: UUID) async {
        guard let userId = currentUserId else { return }

        do {
            try await GroupImageService.shared.releaseLock(groupId: groupId, userId: userId)
            activeLocks.removeAll { $0.id == groupId && $0.type == .groupImage }
            stopHeartbeatIfNoLocks()
        } catch {
            print("LockManager: Failed to release group image lock: \(error)")
        }
    }

    /// Release all active locks
    func releaseAllLocks() async {
        guard let userId = currentUserId else { return }

        for lock in activeLocks {
            do {
                switch lock.type {
                case .rosterEntry:
                    try await RosterEntryService.shared.releaseLock(entryId: lock.id, userId: userId)
                case .groupImage:
                    try await GroupImageService.shared.releaseLock(groupId: lock.id, userId: userId)
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
        guard let userId = currentUserId else { return }

        for lock in activeLocks {
            do {
                switch lock.type {
                case .rosterEntry:
                    try await RosterEntryService.shared.refreshLock(entryId: lock.id, userId: userId)
                case .groupImage:
                    try await GroupImageService.shared.refreshLock(groupId: lock.id, userId: userId)
                }
            } catch {
                print("LockManager: Failed to refresh lock \(lock.id): \(error)")
                // Lock may have been taken by someone else, remove from active locks
                activeLocks.removeAll { $0.id == lock.id }
            }
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

    /// Call when app returns to foreground
    func handleAppForeground() {
        // Locks should be re-acquired when user starts editing again
    }
}
