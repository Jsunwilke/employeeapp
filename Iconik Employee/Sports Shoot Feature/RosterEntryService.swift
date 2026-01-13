//
//  RosterEntryService.swift
//  Iconik Employee
//
//  Service for managing roster entries in the roster_entries table
//  Supports CRUD operations, row-level locking, and realtime subscriptions
//

import Foundation
import Supabase
import Realtime

class RosterEntryService {
    static let shared = RosterEntryService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private let tableName = "roster_entries"

    // Realtime channels for subscriptions - keyed by subscription ID for per-caller tracking
    private var realtimeChannels: [UUID: RealtimeChannelV2] = [:]

    private init() {}

    // MARK: - CRUD Operations (Cache-First Pattern)

    /// Fetch all roster entries for a sports job
    func fetchEntries(forJob jobId: UUID) async throws -> [RosterEntry] {
        // Try to get from cache first
        let cached = LocalSportsRepository.shared.loadRosterEntries(forJob: jobId)

        do {
            // Fetch from network
            let entries: [RosterEntry] = try await supabase
                .from(tableName)
                .select()
                .eq("sports_job_id", value: jobId)
                .order("sort_order", ascending: true)
                .order("last_name", ascending: true)
                .execute()
                .value

            // Save to cache for offline use
            LocalSportsRepository.shared.saveRosterEntries(entries, forJob: jobId)
            return entries
        } catch {
            // If network fails but we have cache, return cached data
            if let cached = cached {
                print("RosterEntryService: Network failed, returning \(cached.count) cached entries")
                return cached
            }
            // No cache and network failed - rethrow error
            throw error
        }
    }

    /// Fetch a single roster entry by ID
    func fetchEntry(id: UUID) async throws -> RosterEntry {
        let entry: RosterEntry = try await supabase
            .from(tableName)
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return entry
    }

    /// Create a new roster entry
    func createEntry(_ entry: RosterEntry) async throws -> RosterEntry {
        let created: RosterEntry = try await supabase
            .from(tableName)
            .insert(entry)
            .select()
            .single()
            .execute()
            .value
        return created
    }

    /// Create multiple roster entries at once
    func createEntries(_ entries: [RosterEntry]) async throws -> [RosterEntry] {
        let created: [RosterEntry] = try await supabase
            .from(tableName)
            .insert(entries)
            .select()
            .execute()
            .value
        return created
    }

    /// Update an existing roster entry
    func updateEntry(_ entry: RosterEntry) async throws -> RosterEntry {
        // Increment version for conflict detection
        var updatedEntry = entry
        updatedEntry.version += 1
        updatedEntry.updatedAt = Date()

        let result: RosterEntry = try await supabase
            .from(tableName)
            .update(updatedEntry)
            .eq("id", value: entry.id)
            .select()
            .single()
            .execute()
            .value
        return result
    }

    /// Delete a roster entry
    func deleteEntry(id: UUID) async throws {
        try await supabase
            .from(tableName)
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// Delete all entries for a sports job
    func deleteAllEntries(forJob jobId: UUID) async throws {
        try await supabase
            .from(tableName)
            .delete()
            .eq("sports_job_id", value: jobId)
            .execute()
    }

    // MARK: - Locking Operations

    /// Attempt to acquire a lock on a roster entry using atomic UPDATE
    /// Returns true if lock was acquired, false if already locked by someone else
    /// When offline, returns true to allow local editing (SyncEngine handles conflicts)
    func acquireLock(entryId: UUID, userId: UUID, userName: String) async throws -> Bool {
        // If offline, allow local editing - SyncEngine will handle conflicts when back online
        let isOnline = await MainActor.run { SyncEngine.shared.isOnline }
        guard isOnline else {
            print("RosterEntryService: Offline - allowing local edit without remote lock")
            return true
        }

        // Use atomic UPDATE with conditions to prevent race conditions
        // Lock can be acquired if:
        // 1. Entry is not locked (locked_by_name is NULL), OR
        // 2. Already locked by this device (locked_by_name matches - includes device session ID), OR
        // 3. Lock has expired (locked_at is more than 2 minutes ago)
        let twoMinutesAgo = Date().addingTimeInterval(-120)
        let twoMinutesAgoISO = twoMinutesAgo.ISO8601Format()

        do {
            // Atomic UPDATE: only succeeds if conditions are met
            // Using OR filter with locked_by_name for per-device locking (same user on different devices = different locks)
            try await supabase
                .from(tableName)
                .update([
                    "locked_by": userId.uuidString,
                    "locked_by_name": userName,
                    "locked_at": Date().ISO8601Format()
                ])
                .eq("id", value: entryId)
                .or("locked_by_name.is.null,locked_by_name.eq.\(userName),locked_at.lt.\(twoMinutesAgoISO)")
                .execute()

            // Verify we actually got the lock by fetching current state (check name for per-device locking)
            let entry = try await fetchEntry(id: entryId)
            return entry.lockedByName == userName
        } catch {
            // Network error - allow local editing, SyncEngine handles conflicts
            print("RosterEntryService: Network error acquiring lock - allowing local edit: \(error)")
            return true
        }
    }

    /// Release a lock on a roster entry
    /// When offline, skips gracefully - lock will expire naturally in ≤2 minutes
    func releaseLock(entryId: UUID, userName: String) async throws {
        // If offline, skip - lock will expire naturally
        let isOnline = await MainActor.run { SyncEngine.shared.isOnline }
        guard isOnline else {
            print("RosterEntryService: Offline - skipping lock release, will expire in ≤2 min")
            return
        }

        // Only release if this device owns the lock (check by name which includes device session)
        let updateData: [String: AnyJSON] = [
            "locked_by": AnyJSON.null,
            "locked_by_name": AnyJSON.null,
            "locked_at": AnyJSON.null
        ]
        try await supabase
            .from(tableName)
            .update(updateData)
            .eq("id", value: entryId)
            .eq("locked_by_name", value: userName)
            .execute()
    }

    /// Refresh/extend a lock (heartbeat)
    /// When offline, skips gracefully - lock will expire if we stay offline
    func refreshLock(entryId: UUID, userName: String) async throws {
        // If offline, skip - lock will expire if we stay offline too long
        let isOnline = await MainActor.run { SyncEngine.shared.isOnline }
        guard isOnline else {
            print("RosterEntryService: Offline - skipping lock refresh")
            return
        }

        // Only refresh if this device owns the lock (check by name which includes device session)
        try await supabase
            .from(tableName)
            .update(["locked_at": Date().ISO8601Format()])
            .eq("id", value: entryId)
            .eq("locked_by_name", value: userName)
            .execute()
    }

    /// Force release all expired locks for a job
    func releaseExpiredLocks(forJob jobId: UUID) async throws {
        let twoMinutesAgo = Date().addingTimeInterval(-120)
        let updateData: [String: AnyJSON] = [
            "locked_by": AnyJSON.null,
            "locked_by_name": AnyJSON.null,
            "locked_at": AnyJSON.null
        ]
        try await supabase
            .from(tableName)
            .update(updateData)
            .eq("sports_job_id", value: jobId)
            .lt("locked_at", value: twoMinutesAgo.ISO8601Format())
            .execute()
    }

    // MARK: - Realtime Subscriptions

    /// Subscribe to changes for a specific sports job
    /// Each caller should provide a unique subscriptionId to maintain their own subscription
    func subscribeToChanges(subscriptionId: UUID, jobId: UUID, onChange: @escaping ([RosterEntry]) -> Void) async {
        // Unsubscribe from any existing channel with this subscription ID first
        await unsubscribe(subscriptionId: subscriptionId)

        // Create unique channel name per subscription to avoid conflicts
        let channelName = "roster_entries_\(jobId.uuidString)_\(subscriptionId.uuidString)"
        let channel = supabase.realtimeV2.channel(channelName)

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: tableName,
            filter: "sports_job_id=eq.\(jobId.uuidString)"
        )

        await channel.subscribe()

        // Store this subscription
        realtimeChannels[subscriptionId] = channel

        // Listen for changes in a separate task
        Task {
            for await change in changes {
                // Fetch updated entries when any change occurs
                do {
                    let entries = try await self.fetchEntries(forJob: jobId)
                    await MainActor.run {
                        onChange(entries)
                    }
                } catch {
                    print("Error fetching entries after realtime change: \(error)")
                }
            }
        }
    }

    /// Unsubscribe a specific subscription
    func unsubscribe(subscriptionId: UUID) async {
        if let channel = realtimeChannels[subscriptionId] {
            await channel.unsubscribe()
            realtimeChannels.removeValue(forKey: subscriptionId)
        }
    }

    /// Unsubscribe from all realtime changes (for cleanup)
    func unsubscribeAll() async {
        for (_, channel) in realtimeChannels {
            await channel.unsubscribe()
        }
        realtimeChannels.removeAll()
    }

    // MARK: - Conflict Detection

    /// Check if an entry has been modified since a given version
    func hasConflict(entryId: UUID, expectedVersion: Int) async throws -> Bool {
        let entry = try await fetchEntry(id: entryId)
        return entry.version != expectedVersion
    }

    /// Fetch the current server version of an entry
    func getCurrentVersion(entryId: UUID) async throws -> Int {
        let entry = try await fetchEntry(id: entryId)
        return entry.version
    }
}
