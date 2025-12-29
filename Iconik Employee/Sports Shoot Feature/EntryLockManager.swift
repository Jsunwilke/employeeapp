//
//  EntryLockManager.swift
//  Iconik Employee
//
//  Created by administrator on 5/13/25.
//  Updated to include automatic lock expiration and permission error handling
//  Migrated to Supabase - uses sports_job_locks table
//


import Foundation
import Supabase

// Class to manage entry locking functionality
class EntryLockManager {
    static let shared = EntryLockManager()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private var isOnline = true
    
    // Lock expiration time in seconds (30 seconds to prevent blocking)
    private let lockExpirationTime: TimeInterval = 30
    
    // Initialize and listen for network status changes
    private init() {
        // Listen for network status changes from OfflineManager
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkStatusChanged(_:)),
            name: NSNotification.Name("OfflineManagerNetworkStatusChanged"),
            object: nil
        )
        
        // Also listen for offline locks changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(offlineLocksChanged(_:)),
            name: NSNotification.Name("OfflineLocksChanged"),
            object: nil
        )
        
        // Initialize online status
        isOnline = OfflineManager.shared.isDeviceOnline()
    }
    
    @objc private func networkStatusChanged(_ notification: Notification) {
        if let isOnline = notification.userInfo?["isOnline"] as? Bool {
            self.isOnline = isOnline
        }
    }
    
    @objc private func offlineLocksChanged(_ notification: Notification) {
        // When offline locks change, notify any active listeners
        if let shootID = notification.userInfo?["shootID"] as? String {
            // Get the local locks for this shoot
            let localLocks = OfflineManager.shared.getLocalLocks(shootID: shootID)
            
            // Notify registered listeners for this shoot about the lock changes
            NotifyLockListeners(shootID: shootID, locks: localLocks)
        }
    }
    
    // Create a lock document for an entry
    func acquireLock(shootID: String, entryID: String, editorID: String, editorName: String, completion: @escaping (Bool) -> Void) {
        // If we're offline, use local locks
        if !isOnline {
            print("Offline mode: Adding local lock for \(entryID) by \(editorName)")
            OfflineManager.shared.addLocalLock(shootID: shootID, entryID: entryID, editorName: editorName)
            completion(true)
            return
        }
        
        // We're online, use Supabase locks with retry mechanism
        acquireLockWithRetry(shootID: shootID, entryID: entryID, editorID: editorID, editorName: editorName, retryCount: 0, completion: completion)
    }
    
    // Helper method to handle lock acquisition with retry logic
    private func acquireLockWithRetry(shootID: String, entryID: String, editorID: String, editorName: String, retryCount: Int, completion: @escaping (Bool) -> Void) {
        let maxRetries = 3
        let lockID = entryID

        Task {
            do {
                // Check for existing lock
                struct LockRecord: Decodable {
                    let id: String
                    let shoot_id: String
                    let entry_id: String
                    let editor_id: String?
                    let editor_name: String?
                    let timestamp: Date?
                }

                let locks: [LockRecord] = try await supabase
                    .from("sports_job_locks")
                    .select()
                    .eq("shoot_id", value: shootID)
                    .eq("entry_id", value: lockID)
                    .limit(1)
                    .execute()
                    .value

                if let existingLock = locks.first {
                    // Check if expired or owned by this editor
                    let timeSinceCreation = Date().timeIntervalSince(existingLock.timestamp ?? Date(timeIntervalSince1970: 0))

                    if timeSinceCreation > self.lockExpirationTime || existingLock.editor_id == editorID {
                        await self.createOrUpdateLockWithRetry(shootID: shootID, lockID: lockID, editorID: editorID, editorName: editorName, retryCount: retryCount, completion: completion)
                    } else {
                        print("Entry is already locked by another editor and not expired")
                        await MainActor.run { completion(false) }
                    }
                } else {
                    // No existing lock, create a new one
                    await self.createOrUpdateLockWithRetry(shootID: shootID, lockID: lockID, editorID: editorID, editorName: editorName, retryCount: retryCount, completion: completion)
                }
            } catch {
                print("Error checking for existing lock: \(error.localizedDescription)")

                if self.isPermissionError(error) {
                    print("Permission error detected - allowing lock acquisition for \(entryID)")
                    await MainActor.run { completion(true) }
                    return
                }

                if retryCount < maxRetries && self.isNetworkError(error) {
                    let retryDelay = Double(retryCount + 1) * 1.0
                    print("Retrying lock acquisition for \(entryID) (attempt \(retryCount + 1)/\(maxRetries)) in \(retryDelay) seconds...")
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                    self.acquireLockWithRetry(shootID: shootID, entryID: entryID, editorID: editorID, editorName: editorName, retryCount: retryCount + 1, completion: completion)
                    return
                }

                print("Failed to acquire lock for \(entryID) after \(retryCount) retries")
                await MainActor.run { completion(false) }
            }
        }
    }
    
    // Helper method to create or update a lock with retry logic
    private func createOrUpdateLockWithRetry(shootID: String, lockID: String, editorID: String, editorName: String, retryCount: Int, completion: @escaping (Bool) -> Void) async {
        let maxRetries = 3

        do {
            // Create lock data with current timestamp using upsert
            let lockData: [String: AnyJSON] = [
                "id": .string("\(shootID)_\(lockID)"),
                "shoot_id": .string(shootID),
                "entry_id": .string(lockID),
                "editor_id": .string(editorID),
                "editor_name": .string(editorName),
                "timestamp": .string(Date().ISO8601Format())
            ]

            try await supabase
                .from("sports_job_locks")
                .upsert(lockData)
                .execute()

            print("Lock acquired successfully for \(lockID) by \(editorName)")
            await MainActor.run { completion(true) }
        } catch {
            print("Error acquiring lock: \(error.localizedDescription)")

            if self.isPermissionError(error) {
                print("Permission error detected - pretending lock acquired for \(lockID)")
                await MainActor.run { completion(true) }
                return
            }

            if retryCount < maxRetries && self.isNetworkError(error) {
                let retryDelay = Double(retryCount + 1) * 1.0
                print("Retrying lock creation for \(lockID) (attempt \(retryCount + 1)/\(maxRetries)) in \(retryDelay) seconds...")
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                await self.createOrUpdateLockWithRetry(shootID: shootID, lockID: lockID, editorID: editorID, editorName: editorName, retryCount: retryCount + 1, completion: completion)
                return
            }

            print("Failed to create lock for \(lockID) after \(retryCount) retries")
            await MainActor.run { completion(false) }
        }
    }
    
    // Helper method to create or update a lock (legacy method for backward compatibility)
    private func createOrUpdateLock(shootID: String, lockID: String, editorID: String, editorName: String, completion: @escaping (Bool) -> Void) {
        Task {
            await createOrUpdateLockWithRetry(shootID: shootID, lockID: lockID, editorID: editorID, editorName: editorName, retryCount: 0, completion: completion)
        }
    }

    // Release a lock
    func releaseLock(shootID: String, entryID: String, editorID: String, completion: ((Bool) -> Void)? = nil) {
        // If we're offline, use local locks
        if !isOnline {
            print("Offline mode: Removing local lock for \(entryID)")
            OfflineManager.shared.removeLocalLock(shootID: shootID, entryID: entryID)
            completion?(true)
            return
        }

        // We're online, use Supabase locks
        let lockID = "\(shootID)_\(entryID)"

        Task {
            do {
                // Check if lock exists and is owned by this editor
                struct LockRecord: Decodable {
                    let editor_id: String?
                }

                let locks: [LockRecord] = try await supabase
                    .from("sports_job_locks")
                    .select("editor_id")
                    .eq("id", value: lockID)
                    .limit(1)
                    .execute()
                    .value

                if let existingLock = locks.first {
                    // Check ownership
                    if existingLock.editor_id != editorID {
                        print("Lock is owned by another editor, cannot release")
                        await MainActor.run { completion?(false) }
                        return
                    }

                    // Delete the lock
                    try await supabase
                        .from("sports_job_locks")
                        .delete()
                        .eq("id", value: lockID)
                        .execute()

                    print("Lock released successfully for \(entryID)")
                    await MainActor.run { completion?(true) }
                } else {
                    // Lock doesn't exist, consider it released
                    print("No lock exists to release for \(entryID)")
                    await MainActor.run { completion?(true) }
                }
            } catch {
                print("Error releasing lock: \(error.localizedDescription)")

                if self.isPermissionError(error) {
                    print("Permission error detected - pretending lock released for \(entryID)")
                    await MainActor.run { completion?(true) }
                    return
                }

                await MainActor.run { completion?(false) }
            }
        }
    }
    
    // Helper to check if error is network-related
    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let errorMessage = error.localizedDescription.lowercased()
        
        // Check NSURLError codes
        if nsError.domain == NSURLErrorDomain {
            return true
        }
        
        // Check common network error codes
        let networkErrorCodes = [
            14, // Network unavailable
            -1009, // No internet connection
            -1001, // Request timed out
            -1004, // Could not connect to server
            -1005, // Network connection lost
            -1006, // DNS lookup failed
            -1011, // Bad server response
            8 // Deadline exceeded
        ]
        
        if networkErrorCodes.contains(nsError.code) {
            return true
        }
        
        // Check error message for network-related keywords
        let networkKeywords = [
            "network", "connection", "timeout", "unreachable", 
            "deadline exceeded", "cancelled", "unavailable",
            "dns", "server", "internet", "offline"
        ]
        
        return networkKeywords.contains { errorMessage.contains($0) }
    }
    
    // Helper to check if error is permission-related
    private func isPermissionError(_ error: Error) -> Bool {
        let errorMessage = error.localizedDescription.lowercased()
        return errorMessage.contains("permission") || 
               errorMessage.contains("insufficient") ||
               errorMessage.contains("unauthorized")
    }
    
    // Check if an entry is locked
    func checkLock(shootID: String, entryID: String, completion: @escaping (Bool, String?) -> Void) {
        // If we're offline, use local locks
        if !isOnline {
            let localLocks = OfflineManager.shared.getLocalLocks(shootID: shootID)
            if let editorName = localLocks[entryID] {
                completion(true, editorName)
            } else {
                completion(false, nil)
            }
            return
        }

        // We're online, use Supabase locks
        let lockID = "\(shootID)_\(entryID)"

        Task {
            do {
                struct LockRecord: Decodable {
                    let editor_name: String?
                    let timestamp: Date?
                }

                let locks: [LockRecord] = try await supabase
                    .from("sports_job_locks")
                    .select("editor_name, timestamp")
                    .eq("id", value: lockID)
                    .limit(1)
                    .execute()
                    .value

                if let lock = locks.first {
                    // Check if the lock has expired
                    if let timestamp = lock.timestamp {
                        let timeSinceCreation = Date().timeIntervalSince(timestamp)

                        if timeSinceCreation > self.lockExpirationTime {
                            // Lock has expired
                            print("Lock has expired for \(entryID)")
                            await MainActor.run { completion(false, nil) }

                            // Only remove if significantly expired
                            if timeSinceCreation > (self.lockExpirationTime * 2) {
                                try? await supabase
                                    .from("sports_job_locks")
                                    .delete()
                                    .eq("id", value: lockID)
                                    .execute()
                            }
                        } else {
                            // Entry is locked and not expired
                            await MainActor.run { completion(true, lock.editor_name) }
                        }
                    } else {
                        // No timestamp - treat as locked (new lock)
                        await MainActor.run { completion(true, lock.editor_name) }
                    }
                } else {
                    // Entry is not locked
                    await MainActor.run { completion(false, nil) }
                }
            } catch {
                print("Error checking lock: \(error.localizedDescription)")
                await MainActor.run { completion(false, nil) }
            }
        }
    }
    
    // Dictionary to keep track of active lock listeners per shoot
    private var lockListeners: [String: [([String: String]) -> Void]] = [:]

    // Store realtime channels for each shoot
    private var realtimeChannels: [String: RealtimeChannelV2] = [:]
    
    // Set up a listener for locks on a specific shoot
    func listenForLocks(shootID: String, completion: @escaping ([String: String]) -> Void) {
        print("Setting up lock listener for shoot: \(shootID)")

        // Store the completion handler
        if lockListeners[shootID] == nil {
            lockListeners[shootID] = []
        }
        lockListeners[shootID]?.append(completion)

        // If we're offline, use local locks
        if !isOnline {
            let localLocks = OfflineManager.shared.getLocalLocks(shootID: shootID)
            completion(localLocks)
            return
        }

        // We're online, set up Supabase realtime listener
        Task {
            // First, fetch initial lock data
            await fetchAndNotifyLocks(shootID: shootID)

            // Then set up realtime subscription
            let channelKey = "locks_\(shootID)"

            // Unsubscribe from existing channel if any
            if let existingChannel = realtimeChannels[channelKey] {
                await existingChannel.unsubscribe()
            }

            let channel = supabase.channel(channelKey)

            // Listen for changes to locks for this shoot
            let changeStream = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "sports_job_locks",
                filter: "shoot_id=eq.\(shootID)"
            )

            // Start listening for changes
            Task {
                for await _ in changeStream {
                    // Refetch all locks when any change occurs
                    await self.fetchAndNotifyLocks(shootID: shootID)
                }
            }

            await channel.subscribe()
            realtimeChannels[channelKey] = channel
        }
    }

    // Helper method to fetch locks and notify listeners
    private func fetchAndNotifyLocks(shootID: String) async {
        do {
            struct LockRecord: Decodable {
                let entry_id: String
                let editor_name: String?
                let timestamp: Date?
            }

            let locks: [LockRecord] = try await supabase
                .from("sports_job_locks")
                .select("entry_id, editor_name, timestamp")
                .eq("shoot_id", value: shootID)
                .execute()
                .value

            print("Received \(locks.count) lock documents")

            var validLocks: [String: String] = [:]
            var expiredLockIDs: [String] = []

            for lock in locks {
                guard let editorName = lock.editor_name else { continue }

                // Check if the lock has expired
                if let timestamp = lock.timestamp {
                    let timeSinceCreation = Date().timeIntervalSince(timestamp)

                    // Add grace period: only expire locks that are 2x the expiration time
                    if timeSinceCreation > (self.lockExpirationTime * 2) {
                        print("Lock for entry \(lock.entry_id) by \(editorName) is expired (\(Int(timeSinceCreation))s old) - removing")
                        expiredLockIDs.append("\(shootID)_\(lock.entry_id)")
                    } else {
                        // Lock is valid
                        validLocks[lock.entry_id] = editorName
                        print("Lock for entry \(lock.entry_id) by \(editorName) (age: \(Int(timeSinceCreation))s)")
                    }
                } else {
                    // No timestamp yet - treat as valid lock
                    validLocks[lock.entry_id] = editorName
                    print("Lock for entry \(lock.entry_id) by \(editorName) (new lock)")
                }
            }

            // Delete expired locks
            for lockID in expiredLockIDs {
                try? await supabase
                    .from("sports_job_locks")
                    .delete()
                    .eq("id", value: lockID)
                    .execute()
                print("Successfully deleted expired lock: \(lockID)")
            }

            // Notify all listeners on main thread
            await MainActor.run {
                self.NotifyLockListeners(shootID: shootID, locks: validLocks)
            }
        } catch {
            print("Error fetching locks: \(error.localizedDescription)")
        }
    }
    
    // Helper method to notify all listeners for a shoot
    private func NotifyLockListeners(shootID: String, locks: [String: String]) {
        if let listeners = lockListeners[shootID] {
            for listener in listeners {
                listener(locks)
            }
        }
    }
    
    // Clean up old locks (can be called periodically)
    func cleanupStaleLocks(shootID: String, timeThreshold: TimeInterval? = nil) {
        // If we're offline, nothing to do
        if !isOnline {
            return
        }

        // Use the provided threshold or default to our lockExpirationTime
        let cutoffTime = timeThreshold ?? lockExpirationTime
        print("Cleaning up stale locks for shoot: \(shootID) with threshold: \(cutoffTime) seconds")

        let cutoffDate = Date().addingTimeInterval(-cutoffTime)

        Task {
            do {
                struct LockRecord: Decodable {
                    let id: String
                    let entry_id: String?
                    let timestamp: Date?
                }

                let staleLocks: [LockRecord] = try await supabase
                    .from("sports_job_locks")
                    .select("id, entry_id, timestamp")
                    .eq("shoot_id", value: shootID)
                    .lt("timestamp", value: cutoffDate.ISO8601Format())
                    .execute()
                    .value

                guard !staleLocks.isEmpty else {
                    print("No stale locks found")
                    return
                }

                print("Found \(staleLocks.count) stale locks to clean up")

                // Delete each stale lock
                for lock in staleLocks {
                    let entryID = lock.entry_id ?? "unknown"
                    print("Removing stale lock for: \(entryID)")
                    try await supabase
                        .from("sports_job_locks")
                        .delete()
                        .eq("id", value: lock.id)
                        .execute()
                }

                print("Deleted \(staleLocks.count) stale locks")
            } catch {
                print("Error cleaning up stale locks: \(error.localizedDescription)")
            }
        }
    }
    
    // Force release a lock (admin/recovery function)
    func forceReleaseLock(shootID: String, entryID: String, completion: @escaping (Bool) -> Void) {
        // If we're offline, use local locks
        if !isOnline {
            print("Offline mode: Force removing local lock for \(entryID)")
            OfflineManager.shared.removeLocalLock(shootID: shootID, entryID: entryID)
            completion(true)
            return
        }

        // We're online, force delete from Supabase
        let lockID = "\(shootID)_\(entryID)"

        Task {
            do {
                try await supabase
                    .from("sports_job_locks")
                    .delete()
                    .eq("id", value: lockID)
                    .execute()

                print("Lock force released successfully for \(entryID)")
                await MainActor.run { completion(true) }
            } catch {
                print("Error force releasing lock: \(error.localizedDescription)")
                await MainActor.run { completion(false) }
            }
        }
    }

    // Clean up realtime channel when no longer needed
    func stopListeningForLocks(shootID: String) {
        let channelKey = "locks_\(shootID)"
        if let channel = realtimeChannels[channelKey] {
            Task {
                await channel.unsubscribe()
            }
            realtimeChannels.removeValue(forKey: channelKey)
        }
        lockListeners.removeValue(forKey: shootID)
    }
}
