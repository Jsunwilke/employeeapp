//
//  GroupImageService.swift
//  Iconik Employee
//
//  Service for managing group images in the group_images table
//  Supports CRUD operations, row-level locking, and realtime subscriptions
//

import Foundation
import Supabase
import Realtime

class GroupImageService {
    static let shared = GroupImageService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private let tableName = "group_images"

    // Realtime channels for subscriptions - keyed by subscription ID for per-caller tracking
    private var realtimeChannels: [UUID: RealtimeChannelV2] = [:]

    private init() {}

    // MARK: - CRUD Operations (Cache-First Pattern)

    /// Fetch all group images for a sports job
    func fetchGroups(forJob jobId: UUID) async throws -> [GroupImage] {
        // Try to get from cache first
        let cached = LocalSportsRepository.shared.loadGroupImages(forJob: jobId)

        do {
            // Fetch from network
            let groups: [GroupImage] = try await supabase
                .from(tableName)
                .select()
                .eq("sports_job_id", value: jobId)
                .order("sort_order", ascending: true)
                .order("description", ascending: true)
                .execute()
                .value

            // Save to cache for offline use
            LocalSportsRepository.shared.saveGroupImages(groups, forJob: jobId)
            return groups
        } catch {
            // If network fails but we have cache, return cached data
            if let cached = cached {
                print("GroupImageService: Network failed, returning \(cached.count) cached groups")
                return cached
            }
            // No cache and network failed - rethrow error
            throw error
        }
    }

    /// Fetch a single group image by ID
    func fetchGroup(id: UUID) async throws -> GroupImage {
        let group: GroupImage = try await supabase
            .from(tableName)
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return group
    }

    /// Create a new group image
    func createGroup(_ group: GroupImage) async throws -> GroupImage {
        let created: GroupImage = try await supabase
            .from(tableName)
            .insert(group)
            .select()
            .single()
            .execute()
            .value
        return created
    }

    /// Create multiple group images at once
    func createGroups(_ groups: [GroupImage]) async throws -> [GroupImage] {
        let created: [GroupImage] = try await supabase
            .from(tableName)
            .insert(groups)
            .select()
            .execute()
            .value
        return created
    }

    /// Update an existing group image
    func updateGroup(_ group: GroupImage) async throws -> GroupImage {
        // Increment version for conflict detection
        var updatedGroup = group
        updatedGroup.version += 1
        updatedGroup.updatedAt = Date()

        let result: GroupImage = try await supabase
            .from(tableName)
            .update(updatedGroup)
            .eq("id", value: group.id)
            .select()
            .single()
            .execute()
            .value
        return result
    }

    /// Delete a group image
    func deleteGroup(id: UUID) async throws {
        try await supabase
            .from(tableName)
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// Delete all groups for a sports job
    func deleteAllGroups(forJob jobId: UUID) async throws {
        try await supabase
            .from(tableName)
            .delete()
            .eq("sports_job_id", value: jobId)
            .execute()
    }

    // MARK: - Locking Operations

    /// Attempt to acquire a lock on a group image using atomic UPDATE
    /// Returns true if lock was acquired, false if already locked by someone else
    /// When offline, returns true to allow local editing (SyncEngine handles conflicts)
    func acquireLock(groupId: UUID, userId: UUID, userName: String) async throws -> Bool {
        // If offline, allow local editing - SyncEngine will handle conflicts when back online
        let isOnline = await MainActor.run { SyncEngine.shared.isOnline }
        guard isOnline else {
            print("GroupImageService: Offline - allowing local edit without remote lock")
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
                .eq("id", value: groupId)
                .or("locked_by_name.is.null,locked_by_name.eq.\(userName),locked_at.lt.\(twoMinutesAgoISO)")
                .execute()

            // Verify we actually got the lock by fetching current state (check name for per-device locking)
            let group = try await fetchGroup(id: groupId)
            return group.lockedByName == userName
        } catch {
            // Network error - allow local editing, SyncEngine handles conflicts
            print("GroupImageService: Network error acquiring lock - allowing local edit: \(error)")
            return true
        }
    }

    /// Release a lock on a group image
    /// When offline, skips gracefully - lock will expire naturally in ≤2 minutes
    func releaseLock(groupId: UUID, userName: String) async throws {
        // If offline, skip - lock will expire naturally
        let isOnline = await MainActor.run { SyncEngine.shared.isOnline }
        guard isOnline else {
            print("GroupImageService: Offline - skipping lock release, will expire in ≤2 min")
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
            .eq("id", value: groupId)
            .eq("locked_by_name", value: userName)
            .execute()
    }

    /// Refresh/extend a lock (heartbeat)
    /// When offline, skips gracefully - lock will expire if we stay offline
    func refreshLock(groupId: UUID, userName: String) async throws {
        // If offline, skip - lock will expire if we stay offline too long
        let isOnline = await MainActor.run { SyncEngine.shared.isOnline }
        guard isOnline else {
            print("GroupImageService: Offline - skipping lock refresh")
            return
        }

        // Only refresh if this device owns the lock (check by name which includes device session)
        try await supabase
            .from(tableName)
            .update(["locked_at": Date().ISO8601Format()])
            .eq("id", value: groupId)
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
    func subscribeToChanges(subscriptionId: UUID, jobId: UUID, onChange: @escaping ([GroupImage]) -> Void) async {
        // Unsubscribe from any existing channel with this subscription ID first
        await unsubscribe(subscriptionId: subscriptionId)

        // Create unique channel name per subscription to avoid conflicts
        let channelName = "group_images_\(jobId.uuidString)_\(subscriptionId.uuidString)"
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
                // Fetch updated groups when any change occurs
                do {
                    let groups = try await self.fetchGroups(forJob: jobId)
                    await MainActor.run {
                        onChange(groups)
                    }
                } catch {
                    print("Error fetching groups after realtime change: \(error)")
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

    /// Check if a group has been modified since a given version
    func hasConflict(groupId: UUID, expectedVersion: Int) async throws -> Bool {
        let group = try await fetchGroup(id: groupId)
        return group.version != expectedVersion
    }

    /// Fetch the current server version of a group
    func getCurrentVersion(groupId: UUID) async throws -> Int {
        let group = try await fetchGroup(id: groupId)
        return group.version
    }
}
