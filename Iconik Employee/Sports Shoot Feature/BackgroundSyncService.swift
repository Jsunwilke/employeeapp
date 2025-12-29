//
//  BackgroundSyncService.swift
//  Iconik Employee
//
//  Monitors network status and syncs pending changes to Supabase
//  Handles retry logic with exponential backoff
//

import Foundation
import Supabase
import Combine

class BackgroundSyncService: ObservableObject {
    static let shared = BackgroundSyncService()

    private init() {}

    // MARK: - State

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var failedSyncCount = 0
    @Published private(set) var pendingChangeCount = 0
    @Published private(set) var lastSyncSuccess = true

    private var syncTimer: Timer?
    private var isMonitoring = false

    // MARK: - Start/Stop Monitoring

    /// Start monitoring network and syncing pending changes
    func startMonitoring() {
        guard !isMonitoring else {
            print("⚠️ BackgroundSyncService already monitoring")
            return
        }

        isMonitoring = true
        print("✓ BackgroundSyncService started monitoring")

        // Listen to network changes
        NetworkMonitor.shared.startMonitoring { [weak self] isConnected in
            guard let self = self else { return }

            if isConnected {
                print("📡 Network connected - triggering sync")
                Task {
                    await self.syncNow()
                }
            } else {
                print("📡 Network disconnected - pausing sync")
            }
        }

        // Set up periodic sync timer (every 30 seconds if online)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if NetworkMonitor.shared.isConnected {
                Task {
                    await self.syncNow()
                }
            }
        }

        // Run initial sync
        Task {
            await syncNow()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        syncTimer?.invalidate()
        syncTimer = nil
        print("✓ BackgroundSyncService stopped monitoring")
    }

    // MARK: - Manual Sync

    /// Manually trigger sync now
    func syncNow() async {
        guard !isSyncing else {
            print("⚠️ Sync already in progress")
            return
        }

        guard NetworkMonitor.shared.isConnected else {
            print("⚠️ Cannot sync - no network connection")
            return
        }

        await MainActor.run {
            self.isSyncing = true
            self.pendingChangeCount = PendingSyncManager.shared.pendingChangeCount
        }
        print("🔄 Starting sync...")

        await processPendingQueue()

        await MainActor.run {
            self.isSyncing = false
            self.lastSyncAt = Date()
            self.pendingChangeCount = PendingSyncManager.shared.pendingChangeCount
        }
        print("✓ Sync completed at \(lastSyncAt!)")
    }

    // MARK: - Process Pending Queue

    private func processPendingQueue() async {
        // Get all retryable pending changes
        let changes = PendingSyncManager.shared.getRetryableChanges()

        guard !changes.isEmpty else {
            print("✓ No pending changes to sync")
            return
        }

        print("📤 Syncing \(changes.count) pending change(s)...")

        // Track success/failure counts
        var successCount = 0
        var failureCount = 0

        // Group changes by shoot ID for efficient batch processing
        let changesByShoot = Dictionary(grouping: changes, by: { $0.shootId ?? "" })

        for (shootId, shootChanges) in changesByShoot {
            guard !shootId.isEmpty else { continue }

            print("📤 Processing \(shootChanges.count) change(s) for shoot \(shootId)")

            // Process each change sequentially
            for (index, change) in shootChanges.enumerated() {
                let changeType = change.changeType ?? "unknown"
                print("   [\(index + 1)/\(shootChanges.count)] Syncing \(changeType)...")

                let success = await syncChange(change)
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
        }

        print("✅ Sync complete: \(successCount) succeeded, \(failureCount) failed")
        if failureCount > 0 {
            print("⚠️  Failed changes will retry automatically")
        }

        // Update sync status
        await MainActor.run {
            self.lastSyncSuccess = (failureCount == 0)
            self.failedSyncCount = failureCount
        }
    }

    // MARK: - Sync Individual Change

    private func syncChange(_ change: PendingChange) async -> Bool {
        guard let changeType = ChangeType(rawValue: change.changeType ?? ""),
              let shootId = change.shootId,
              let changeData = PendingSyncManager.shared.decodeChangeData(from: change) else {
            print("❌ Invalid change data - removing from queue")
            if let id = change.id {
                PendingSyncManager.shared.removePendingChange(id: id)
            }
            return false
        }

        var success = false

        switch changeType {
        case .updateEntry:
            success = await syncRosterEntryUpdate(shootId: shootId, entryId: change.entryId, data: changeData)

        case .createEntry:
            success = await syncRosterEntryCreate(shootId: shootId, data: changeData)

        case .deleteEntry:
            success = await syncRosterEntryDelete(shootId: shootId, entryId: change.entryId, data: changeData)

        case .updateShootMetadata:
            success = await syncShootMetadataUpdate(shootId: shootId, data: changeData)
        }

        // Record attempt result
        PendingSyncManager.shared.recordAttempt(for: change, success: success)

        if success {
            print("      ✓ Success")
        } else {
            print("      ❌ Failed - will retry")
        }

        return success
    }

    // MARK: - Sync Operations

    private func syncRosterEntryUpdate(shootId: String, entryId: String?, data: [String: Any]) async -> Bool {
        guard let entryId = entryId else { return false }

        // Reconstruct RosterEntry from local change data
        var localEntry = RosterEntry(
            id: entryId,
            lastName: data["lastName"] as? String ?? "",
            firstName: data["firstName"] as? String ?? "",
            teacher: data["teacher"] as? String ?? "",
            group: data["group"] as? String ?? "",
            email: data["email"] as? String ?? "",
            phone: data["phone"] as? String ?? "",
            imageNumbers: data["imageNumbers"] as? String ?? "",
            notes: data["notes"] as? String ?? ""
        )

        // Fetch current remote state and merge if needed
        let mergedEntry = await fetchAndMergeRemoteEntry(shootId: shootId, localEntry: localEntry)

        return await withCheckedContinuation { continuation in
            SportsShootService.shared.updateRosterEntry(shootID: shootId, entry: mergedEntry) { result in
                switch result {
                case .success:
                    // Update local repository with merged entry and mark as synced
                    _ = LocalSportsShootRepository.shared.updateRosterEntry(shootId: shootId, entry: mergedEntry)
                    LocalSportsShootRepository.shared.markAsSynced(shootId: shootId)
                    continuation.resume(returning: true)
                case .failure(let error):
                    print("❌ Supabase update failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Fetch the current remote entry and intelligently merge with local changes
    private func fetchAndMergeRemoteEntry(shootId: String, localEntry: RosterEntry) async -> RosterEntry {
        // Fetch the remote shoot to get current state using Supabase
        do {
            let supabase = SupabaseManager.shared.client

            let shoots: [SupabaseSportsShoot] = try await supabase
                .from("sports_jobs")
                .select()
                .eq("id", value: shootId)
                .limit(1)
                .execute()
                .value

            guard let remoteShoot = shoots.first?.toSportsShoot(),
                  let remote = remoteShoot.roster.first(where: { $0.id == localEntry.id }) else {
                // No remote version found, use local as-is
                return localEntry
            }

            // Check if we need to merge imageNumbers
            if !localEntry.imageNumbers.isEmpty && !remote.imageNumbers.isEmpty &&
               localEntry.imageNumbers != remote.imageNumbers {
                // Both have imageNumbers - merge them!
                var merged = localEntry
                merged.imageNumbers = ImageNumbersMerger.mergeImageNumbers(
                    local: localEntry.imageNumbers,
                    remote: remote.imageNumbers
                )
                merged.notes = ImageNumbersMerger.mergeNotes(
                    local: localEntry.notes,
                    remote: remote.notes
                )
                print("   🔀 Merged with remote: imageNumbers=\"\(merged.imageNumbers)\"")
                return merged
            }

            // No merge needed, use local
            return localEntry
        } catch {
            print("❌ Error fetching remote shoot: \(error.localizedDescription)")
            return localEntry
        }
    }

    private func syncRosterEntryCreate(shootId: String, data: [String: Any]) async -> Bool {
        // Reconstruct RosterEntry from change data
        let entry = RosterEntry(
            id: data["id"] as? String ?? UUID().uuidString,
            lastName: data["lastName"] as? String ?? "",
            firstName: data["firstName"] as? String ?? "",
            teacher: data["teacher"] as? String ?? "",
            group: data["group"] as? String ?? "",
            email: data["email"] as? String ?? "",
            phone: data["phone"] as? String ?? "",
            imageNumbers: data["imageNumbers"] as? String ?? "",
            notes: data["notes"] as? String ?? ""
        )

        return await withCheckedContinuation { continuation in
            SportsShootService.shared.addRosterEntry(shootID: shootId, entry: entry) { result in
                switch result {
                case .success:
                    LocalSportsShootRepository.shared.markAsSynced(shootId: shootId)
                    continuation.resume(returning: true)
                case .failure(let error):
                    print("❌ Supabase create failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func syncRosterEntryDelete(shootId: String, entryId: String?, data: [String: Any]) async -> Bool {
        guard let entryId = entryId else { return false }

        return await withCheckedContinuation { continuation in
            SportsShootService.shared.deleteRosterEntry(shootID: shootId, entryID: entryId) { result in
                switch result {
                case .success:
                    LocalSportsShootRepository.shared.markAsSynced(shootId: shootId)
                    continuation.resume(returning: true)
                case .failure(let error):
                    print("❌ Supabase delete failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func syncShootMetadataUpdate(shootId: String, data: [String: Any]) async -> Bool {
        // This would update shoot-level metadata (title, location, date, etc.)
        // Implementation depends on SportsShootService having a metadata update method

        // For now, we'll just mark as synced if the shoot exists
        guard let shoot = LocalSportsShootRepository.shared.getShoot(id: shootId) else {
            return false
        }

        // TODO: Implement shoot metadata update in SportsShootService
        print("⚠️ Shoot metadata sync not yet implemented - marking as synced")
        LocalSportsShootRepository.shared.markAsSynced(shootId: shootId)

        return true
    }

    // MARK: - Conflict Detection

    /// Check if a remote version conflicts with local changes
    /// This will be enhanced in Phase 4 with ConflictResolver
    private func detectConflict(local: RosterEntry, remote: RosterEntry) -> Bool {
        // Simple conflict detection: if any field differs, there's a potential conflict
        // ConflictResolver will handle sophisticated resolution in Phase 4

        return local.firstName != remote.firstName ||
               local.lastName != remote.lastName ||
               local.teacher != remote.teacher ||
               local.group != remote.group ||
               local.email != remote.email ||
               local.phone != remote.phone ||
               local.imageNumbers != remote.imageNumbers ||
               local.notes != remote.notes
    }

    // MARK: - Status Helpers

    /// Get total number of pending changes across all shoots
    var totalPendingChanges: Int {
        return PendingSyncManager.shared.pendingChangeCount
    }

    /// Check if there are any pending changes
    var hasPendingChanges: Bool {
        return PendingSyncManager.shared.hasPendingChanges
    }
}
