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

    // Realtime channel for subscriptions
    private var realtimeChannel: RealtimeChannelV2?

    private init() {}

    // MARK: - CRUD Operations

    /// Fetch all group images for a sports job
    func fetchGroups(forJob jobId: UUID) async throws -> [GroupImage] {
        let groups: [GroupImage] = try await supabase
            .from(tableName)
            .select()
            .eq("sports_job_id", value: jobId)
            .order("sort_order", ascending: true)
            .order("description", ascending: true)
            .execute()
            .value
        return groups
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

    /// Attempt to acquire a lock on a group image
    /// Returns true if lock was acquired, false if already locked by someone else
    func acquireLock(groupId: UUID, userId: UUID, userName: String) async throws -> Bool {
        let twoMinutesAgo = Date().addingTimeInterval(-120)

        // First, check if we can acquire the lock
        let groups: [GroupImage] = try await supabase
            .from(tableName)
            .select()
            .eq("id", value: groupId)
            .execute()
            .value

        guard let group = groups.first else {
            throw NSError(domain: "GroupImageService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Group not found"])
        }

        // Check if locked by someone else and lock hasn't expired
        if let lockedBy = group.lockedBy, let lockedAt = group.lockedAt {
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
            .eq("id", value: groupId)
            .execute()

        return true
    }

    /// Release a lock on a group image
    func releaseLock(groupId: UUID, userId: UUID) async throws {
        // Only release if we own the lock
        let updateData: [String: AnyJSON] = [
            "locked_by": AnyJSON.null,
            "locked_by_name": AnyJSON.null,
            "locked_at": AnyJSON.null
        ]
        try await supabase
            .from(tableName)
            .update(updateData)
            .eq("id", value: groupId)
            .eq("locked_by", value: userId)
            .execute()
    }

    /// Refresh/extend a lock (heartbeat)
    func refreshLock(groupId: UUID, userId: UUID) async throws {
        try await supabase
            .from(tableName)
            .update(["locked_at": Date().ISO8601Format()])
            .eq("id", value: groupId)
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
    func subscribeToChanges(jobId: UUID, onChange: @escaping ([GroupImage]) -> Void) async {
        // Unsubscribe from any existing channel first
        await unsubscribe()

        let channel = supabase.realtimeV2.channel("group_images_\(jobId.uuidString)")

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
