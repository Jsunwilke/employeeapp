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

    // Realtime channel for subscriptions
    private var realtimeChannel: RealtimeChannelV2?

    private init() {}

    // MARK: - CRUD Operations

    /// Fetch all roster entries for a sports job
    func fetchEntries(forJob jobId: UUID) async throws -> [RosterEntry] {
        let entries: [RosterEntry] = try await supabase
            .from(tableName)
            .select()
            .eq("sports_job_id", value: jobId)
            .order("sort_order", ascending: true)
            .order("last_name", ascending: true)
            .execute()
            .value
        return entries
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

    /// Attempt to acquire a lock on a roster entry
    /// Returns true if lock was acquired, false if already locked by someone else
    func acquireLock(entryId: UUID, userId: UUID, userName: String) async throws -> Bool {
        // Try to acquire lock only if:
        // 1. Entry is not locked (locked_by is NULL), OR
        // 2. Lock has expired (locked_at is more than 2 minutes ago)
        let twoMinutesAgo = Date().addingTimeInterval(-120)

        // First, check if we can acquire the lock
        let entries: [RosterEntry] = try await supabase
            .from(tableName)
            .select()
            .eq("id", value: entryId)
            .execute()
            .value

        guard let entry = entries.first else {
            throw NSError(domain: "RosterEntryService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Entry not found"])
        }

        // Check if locked by someone else and lock hasn't expired
        if let lockedBy = entry.lockedBy, let lockedAt = entry.lockedAt {
            if lockedBy != userId && lockedAt > twoMinutesAgo {
                // Locked by someone else and lock is still valid
                return false
            }
        }

        // Acquire the lock
        try await supabase
            .from(tableName)
            .update([
                "locked_by": userId.uuidString,
                "locked_by_name": userName,
                "locked_at": Date().ISO8601Format()
            ])
            .eq("id", value: entryId)
            .execute()

        return true
    }

    /// Release a lock on a roster entry
    func releaseLock(entryId: UUID, userId: UUID) async throws {
        // Only release if we own the lock
        let updateData: [String: AnyJSON] = [
            "locked_by": AnyJSON.null,
            "locked_by_name": AnyJSON.null,
            "locked_at": AnyJSON.null
        ]
        try await supabase
            .from(tableName)
            .update(updateData)
            .eq("id", value: entryId)
            .eq("locked_by", value: userId)
            .execute()
    }

    /// Refresh/extend a lock (heartbeat)
    func refreshLock(entryId: UUID, userId: UUID) async throws {
        try await supabase
            .from(tableName)
            .update(["locked_at": Date().ISO8601Format()])
            .eq("id", value: entryId)
            .eq("locked_by", value: userId)
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
    func subscribeToChanges(jobId: UUID, onChange: @escaping ([RosterEntry]) -> Void) async {
        // Unsubscribe from any existing channel first
        await unsubscribe()

        let channel = supabase.realtimeV2.channel("roster_entries_\(jobId.uuidString)")

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: tableName,
            filter: "sports_job_id=eq.\(jobId.uuidString)"
        )

        await channel.subscribe()

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

        self.realtimeChannel = channel
    }

    /// Unsubscribe from realtime changes
    func unsubscribe() async {
        if let channel = realtimeChannel {
            await channel.unsubscribe()
            realtimeChannel = nil
        }
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
