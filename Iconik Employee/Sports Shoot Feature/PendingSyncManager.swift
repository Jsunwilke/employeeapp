//
//  PendingSyncManager.swift
//  Iconik Employee
//
//  Manages pending changes queue for offline edits
//  Tracks all edits made while offline for background sync
//

import Foundation
import CoreData

enum ChangeType: String, Codable {
    case updateEntry
    case createEntry
    case deleteEntry
    case updateShootMetadata
}

class PendingSyncManager {
    static let shared = PendingSyncManager()

    private init() {}

    private var context: NSManagedObjectContext {
        return LocalSportsShootRepository.shared.persistentContainer.viewContext
    }

    // MARK: - Queue Change

    /// Add a change to the pending sync queue
    func queueChange(
        shootId: String,
        entryId: String? = nil,
        changeType: ChangeType,
        data: [String: Any]
    ) {
        let pendingChange = PendingChange(context: context)
        pendingChange.id = UUID()
        pendingChange.shootId = shootId
        pendingChange.entryId = entryId
        pendingChange.changeType = changeType.rawValue
        pendingChange.createdAt = Date()
        pendingChange.attemptCount = 0
        pendingChange.priority = 0

        // Convert data dictionary to JSON string
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            pendingChange.changeData = String(data: jsonData, encoding: .utf8)

            try context.save()
            print("✓ Queued \(changeType.rawValue) for shoot \(shootId)")
        } catch {
            print("Error queuing change: \(error.localizedDescription)")
        }
    }

    // MARK: - Get Pending Changes

    /// Get all pending changes for a specific shoot
    func getPendingChanges(for shootId: String) -> [PendingChange] {
        let fetchRequest: NSFetchRequest<PendingChange> = PendingChange.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "shootId == %@", shootId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("Error fetching pending changes: \(error.localizedDescription)")
            return []
        }
    }

    /// Get all pending changes across all shoots
    func getAllPendingChanges() -> [PendingChange] {
        let fetchRequest: NSFetchRequest<PendingChange> = PendingChange.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "priority", ascending: false), // Higher priority first
            NSSortDescriptor(key: "createdAt", ascending: true)  // Older first
        ]

        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("Error fetching all pending changes: \(error.localizedDescription)")
            return []
        }
    }

    /// Get pending changes that are ready to retry
    func getRetryableChanges() -> [PendingChange] {
        let fetchRequest: NSFetchRequest<PendingChange> = PendingChange.fetchRequest()

        // Get changes that either:
        // 1. Haven't been attempted yet (attemptCount == 0)
        // 2. Last attempt was more than retry delay ago
        let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)

        fetchRequest.predicate = NSPredicate(format: "attemptCount == 0 OR lastAttemptAt < %@", fiveMinutesAgo as NSDate)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "priority", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]

        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("Error fetching retryable changes: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Remove Pending Change

    /// Remove a pending change after successful sync
    func removePendingChange(id: UUID) {
        let fetchRequest: NSFetchRequest<PendingChange> = PendingChange.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        do {
            let results = try context.fetch(fetchRequest)
            for change in results {
                context.delete(change)
            }
            try context.save()
            print("✓ Removed pending change \(id)")
        } catch {
            print("Error removing pending change: \(error.localizedDescription)")
        }
    }

    /// Remove all pending changes for a shoot (use after successful full sync)
    func removeAllPendingChanges(for shootId: String) {
        let fetchRequest: NSFetchRequest<PendingChange> = PendingChange.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "shootId == %@", shootId)

        do {
            let results = try context.fetch(fetchRequest)
            for change in results {
                context.delete(change)
            }
            try context.save()
            print("✓ Removed all pending changes for shoot \(shootId)")
        } catch {
            print("Error removing pending changes: \(error.localizedDescription)")
        }
    }

    // MARK: - Update Attempt Count

    /// Increment attempt count and update last attempt time
    func recordAttempt(for change: PendingChange, success: Bool) {
        if success {
            // Remove from queue
            removePendingChange(id: change.id!)
        } else {
            // Increment attempt count
            change.attemptCount += 1
            change.lastAttemptAt = Date()

            do {
                try context.save()
                print("⚠️ Attempt \(change.attemptCount) failed for change \(change.id!)")
            } catch {
                print("Error recording attempt: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Retry Logic

    /// Retry all failed changes
    func retryFailedChanges() {
        let changes = getRetryableChanges()
        print("Retrying \(changes.count) pending changes...")

        // This method just returns the changes - actual retry logic
        // will be in BackgroundSyncService
    }

    // MARK: - Status

    /// Check if there are any pending changes
    var hasPendingChanges: Bool {
        let fetchRequest: NSFetchRequest<PendingChange> = PendingChange.fetchRequest()

        do {
            let count = try context.count(for: fetchRequest)
            return count > 0
        } catch {
            return false
        }
    }

    /// Get count of pending changes
    var pendingChangeCount: Int {
        let fetchRequest: NSFetchRequest<PendingChange> = PendingChange.fetchRequest()

        do {
            return try context.count(for: fetchRequest)
        } catch {
            return 0
        }
    }

    /// Get count of pending changes for a specific shoot
    func pendingChangeCount(for shootId: String) -> Int {
        let fetchRequest: NSFetchRequest<PendingChange> = PendingChange.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "shootId == %@", shootId)

        do {
            return try context.count(for: fetchRequest)
        } catch {
            return 0
        }
    }

    // MARK: - Decode Change Data

    /// Helper to decode change data from JSON string
    func decodeChangeData(from change: PendingChange) -> [String: Any]? {
        guard let jsonString = change.changeData,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            let data = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            return data
        } catch {
            print("Error decoding change data: \(error.localizedDescription)")
            return nil
        }
    }
}
