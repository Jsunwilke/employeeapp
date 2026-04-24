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
    /// NOTE: For offline-first access, use PowerSyncManager.getGroupImages() instead
    /// Uses pagination to handle more than 1000 entries (Supabase default limit)
    func fetchGroups(forJob jobId: UUID) async throws -> [GroupImage] {
        var allGroups: [GroupImage] = []
        let batchSize = 1000
        var offset = 0

        while true {
            let groups: [GroupImage] = try await supabase
                .from(tableName)
                .select()
                .eq("gallery_id", value: jobId)
                .order("sort_order", ascending: true)
                .order("description", ascending: true)
                .range(from: offset, to: offset + batchSize - 1)
                .execute()
                .value

            allGroups.append(contentsOf: groups)

            if groups.count < batchSize {
                break  // No more records
            }
            offset += batchSize
        }

        return allGroups
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
            .eq("gallery_id", value: jobId)
            .execute()
    }

    // MARK: - Locking Operations

    /// Attempt to acquire a lock on a group image using atomic RPC function
    /// Returns true if lock was acquired, false if already locked by someone else
    /// When offline, returns true to allow local editing (PowerSync handles sync)
    func acquireLock(groupId: UUID, userId: UUID, userName: String) async throws -> Bool {
        // If offline, allow local editing - PowerSync will sync when back online
        let isOnline = await MainActor.run { PowerSyncManager.shared.isConnected }
        guard isOnline else {
            print("GroupImageService: Offline - allowing local edit without remote lock")
            return true
        }

        do {
            // Use atomic RPC function with SELECT ... FOR UPDATE to prevent race conditions
            let result: AnyJSON = try await supabase
                .rpc("acquire_lock", params: [
                    "p_table_name": AnyJSON.string("group_images"),
                    "p_record_id": AnyJSON.string(groupId.uuidString.lowercased()),
                    "p_user_id": AnyJSON.string(userId.uuidString.lowercased()),
                    "p_user_name": AnyJSON.string(userName)
                ])
                .execute()
                .value

            // Parse the JSONB response
            if case .object(let dict) = result,
               case .bool(let success) = dict["success"] {
                if !success, case .string(let lockedBy) = dict["locked_by"] {
                    print("GroupImageService: Lock held by \(lockedBy)")
                }
                return success
            }

            print("GroupImageService: Unexpected RPC response format")
            return false
        } catch {
            // Network error - allow local editing, PowerSync handles sync
            print("GroupImageService: Network error acquiring lock - allowing local edit: \(error)")
            return true
        }
    }

    /// Release a lock on a group image
    /// When offline, skips gracefully - lock will expire naturally in ≤2 minutes
    func releaseLock(groupId: UUID, userName: String) async throws {
        // If offline, skip - lock will expire naturally
        let isOnline = await MainActor.run { PowerSyncManager.shared.isConnected }
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
        let isOnline = await MainActor.run { PowerSyncManager.shared.isConnected }
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
            .eq("gallery_id", value: jobId)
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
            filter: "gallery_id=eq.\(jobId.uuidString)"
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
