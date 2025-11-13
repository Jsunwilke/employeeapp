//
//  ConflictResolver.swift
//  Iconik Employee
//
//  Handles sync conflicts when multiple users edit the same data
//  Implements strategies: last-write-wins, recreate deleted, user decision
//

import Foundation

/// Types of conflicts that can occur during sync
enum ConflictType {
    case bothModified(local: RosterEntry, remote: RosterEntry, localTimestamp: Date?, remoteTimestamp: Date?)
    case deletedRemotely(local: RosterEntry)
    case deletedLocally(remote: RosterEntry)
    case shootArchived(shootId: String)
}

/// Resolution strategy for conflicts
enum ResolutionStrategy {
    case keepLocal       // Use local version
    case keepRemote      // Use remote version
    case merge           // Merge both versions (field-by-field)
    case askUser         // Require user decision
    case recreateDeleted // Recreate entry that was deleted remotely
}

/// Result of conflict resolution
enum ConflictResolution {
    case resolved(entry: RosterEntry, strategy: ResolutionStrategy)
    case requiresUserDecision(conflict: ConflictType)
    case failed(error: String)
}

class ConflictResolver {
    static let shared = ConflictResolver()

    private init() {}

    // MARK: - Detect Conflict

    /// Check if local and remote versions conflict
    func detectConflict(
        local: RosterEntry?,
        remote: RosterEntry?,
        localTimestamp: Date?,
        remoteTimestamp: Date?
    ) -> ConflictType? {
        // Case 1: Both exist and have been modified
        if let local = local, let remote = remote {
            if hasChanges(local: local, remote: remote) {
                return .bothModified(
                    local: local,
                    remote: remote,
                    localTimestamp: localTimestamp,
                    remoteTimestamp: remoteTimestamp
                )
            }
            return nil // No conflict - entries are identical
        }

        // Case 2: Local exists but remote was deleted
        if let local = local, remote == nil {
            return .deletedRemotely(local: local)
        }

        // Case 3: Remote exists but local was deleted
        if local == nil, let remote = remote {
            return .deletedLocally(remote: remote)
        }

        // Case 4: Both deleted - no conflict
        return nil
    }

    /// Check if there are actual changes between local and remote
    private func hasChanges(local: RosterEntry, remote: RosterEntry) -> Bool {
        return local.firstName != remote.firstName ||
               local.lastName != remote.lastName ||
               local.teacher != remote.teacher ||
               local.group != remote.group ||
               local.email != remote.email ||
               local.phone != remote.phone ||
               local.imageNumbers != remote.imageNumbers ||
               local.notes != remote.notes
    }

    // MARK: - Resolve Conflict

    /// Resolve a conflict using the specified strategy
    func resolveConflict(
        _ conflict: ConflictType,
        strategy: ResolutionStrategy
    ) -> ConflictResolution {
        switch conflict {
        case .bothModified(let local, let remote, let localTimestamp, let remoteTimestamp):
            return resolveBothModified(
                local: local,
                remote: remote,
                localTimestamp: localTimestamp,
                remoteTimestamp: remoteTimestamp,
                strategy: strategy
            )

        case .deletedRemotely(let local):
            return resolveDeletedRemotely(local: local, strategy: strategy)

        case .deletedLocally(let remote):
            return resolveDeletedLocally(remote: remote, strategy: strategy)

        case .shootArchived(let shootId):
            return .requiresUserDecision(conflict: conflict)
        }
    }

    // MARK: - Resolution Strategies

    /// Resolve conflict when both local and remote were modified
    private func resolveBothModified(
        local: RosterEntry,
        remote: RosterEntry,
        localTimestamp: Date?,
        remoteTimestamp: Date?,
        strategy: ResolutionStrategy
    ) -> ConflictResolution {
        switch strategy {
        case .keepLocal:
            print("🔄 Conflict resolved: Keeping local version for \(local.firstName) \(local.lastName)")
            return .resolved(entry: local, strategy: .keepLocal)

        case .keepRemote:
            print("🔄 Conflict resolved: Keeping remote version for \(remote.firstName) \(remote.lastName)")
            return .resolved(entry: remote, strategy: .keepRemote)

        case .merge:
            // Field-by-field merge: prefer most recent non-empty value
            let merged = mergeEntries(local: local, remote: remote, localTimestamp: localTimestamp, remoteTimestamp: remoteTimestamp)
            print("🔄 Conflict resolved: Merged versions for \(merged.firstName) \(merged.lastName)")
            return .resolved(entry: merged, strategy: .merge)

        case .askUser:
            return .requiresUserDecision(conflict: .bothModified(
                local: local,
                remote: remote,
                localTimestamp: localTimestamp,
                remoteTimestamp: remoteTimestamp
            ))

        case .recreateDeleted:
            // Not applicable for bothModified
            return .failed(error: "recreateDeleted strategy not applicable for bothModified conflict")
        }
    }

    /// Resolve conflict when entry was deleted remotely
    private func resolveDeletedRemotely(
        local: RosterEntry,
        strategy: ResolutionStrategy
    ) -> ConflictResolution {
        switch strategy {
        case .keepLocal, .recreateDeleted:
            // Recreate the entry with local changes
            print("🔄 Conflict resolved: Recreating deleted entry \(local.firstName) \(local.lastName)")
            return .resolved(entry: local, strategy: .recreateDeleted)

        case .keepRemote:
            // Accept the deletion
            print("🔄 Conflict resolved: Accepting remote deletion of \(local.firstName) \(local.lastName)")
            return .failed(error: "Entry deleted remotely - accepting deletion")

        case .merge, .askUser:
            return .requiresUserDecision(conflict: .deletedRemotely(local: local))
        }
    }

    /// Resolve conflict when entry was deleted locally
    private func resolveDeletedLocally(
        remote: RosterEntry,
        strategy: ResolutionStrategy
    ) -> ConflictResolution {
        switch strategy {
        case .keepLocal:
            // Keep the local deletion
            print("🔄 Conflict resolved: Keeping local deletion of \(remote.firstName) \(remote.lastName)")
            return .failed(error: "Entry deleted locally - keeping deletion")

        case .keepRemote:
            // Restore the remote entry
            print("🔄 Conflict resolved: Restoring remotely modified entry \(remote.firstName) \(remote.lastName)")
            return .resolved(entry: remote, strategy: .keepRemote)

        case .merge, .recreateDeleted, .askUser:
            return .requiresUserDecision(conflict: .deletedLocally(remote: remote))
        }
    }

    // MARK: - Merge Strategy

    /// Merge two entries by preferring most recent non-empty values
    private func mergeEntries(
        local: RosterEntry,
        remote: RosterEntry,
        localTimestamp: Date?,
        remoteTimestamp: Date?
    ) -> RosterEntry {
        // Use timestamp to decide which version to prefer
        let preferLocal = shouldPreferLocal(localTimestamp: localTimestamp, remoteTimestamp: remoteTimestamp)

        var merged = local

        // Merge firstName - prefer non-empty, or use timestamp
        if !local.firstName.isEmpty && !remote.firstName.isEmpty {
            merged.firstName = preferLocal ? local.firstName : remote.firstName
        } else {
            merged.firstName = !local.firstName.isEmpty ? local.firstName : remote.firstName
        }

        // Merge lastName - prefer non-empty, or use timestamp
        if !local.lastName.isEmpty && !remote.lastName.isEmpty {
            merged.lastName = preferLocal ? local.lastName : remote.lastName
        } else {
            merged.lastName = !local.lastName.isEmpty ? local.lastName : remote.lastName
        }

        // Merge teacher - prefer non-empty, or use timestamp
        if !local.teacher.isEmpty && !remote.teacher.isEmpty {
            merged.teacher = preferLocal ? local.teacher : remote.teacher
        } else {
            merged.teacher = !local.teacher.isEmpty ? local.teacher : remote.teacher
        }

        // Merge group - prefer non-empty, or use timestamp
        if !local.group.isEmpty && !remote.group.isEmpty {
            merged.group = preferLocal ? local.group : remote.group
        } else {
            merged.group = !local.group.isEmpty ? local.group : remote.group
        }

        // Merge email - prefer non-empty, or use timestamp
        if !local.email.isEmpty && !remote.email.isEmpty {
            merged.email = preferLocal ? local.email : remote.email
        } else {
            merged.email = !local.email.isEmpty ? local.email : remote.email
        }

        // Merge phone - prefer non-empty, or use timestamp
        if !local.phone.isEmpty && !remote.phone.isEmpty {
            merged.phone = preferLocal ? local.phone : remote.phone
        } else {
            merged.phone = !local.phone.isEmpty ? local.phone : remote.phone
        }

        // Merge imageNumbers - INTELLIGENT MERGE: combine both sources
        merged.imageNumbers = ImageNumbersMerger.mergeImageNumbers(
            local: local.imageNumbers,
            remote: remote.imageNumbers
        )

        // Merge notes - INTELLIGENT MERGE: combine both sources
        merged.notes = ImageNumbersMerger.mergeNotes(
            local: local.notes,
            remote: remote.notes
        )

        return merged
    }

    /// Determine if local version should be preferred based on timestamps
    private func shouldPreferLocal(localTimestamp: Date?, remoteTimestamp: Date?) -> Bool {
        guard let localTime = localTimestamp, let remoteTime = remoteTimestamp else {
            // If timestamps are missing, prefer local (conservative approach)
            return true
        }

        // Last-write-wins: prefer the most recent modification
        return localTime > remoteTime
    }

    // MARK: - Auto-Resolution Strategy

    /// Automatically determine the best resolution strategy for a conflict
    func autoResolveStrategy(for conflict: ConflictType) -> ResolutionStrategy {
        switch conflict {
        case .bothModified(_, _, let localTimestamp, let remoteTimestamp):
            // Default to last-write-wins merge strategy
            return .merge

        case .deletedRemotely:
            // If entry was deleted remotely but modified locally, recreate it
            return .recreateDeleted

        case .deletedLocally:
            // If entry was deleted locally, keep the deletion
            return .keepLocal

        case .shootArchived:
            // Archived shoots require user decision
            return .askUser
        }
    }

    // MARK: - Conflict Description (for UI)

    /// Get a user-friendly description of the conflict
    func describeConflict(_ conflict: ConflictType) -> String {
        switch conflict {
        case .bothModified(let local, _, _, _):
            return "'\(local.firstName) \(local.lastName)' was modified by multiple users."

        case .deletedRemotely(let local):
            return "'\(local.firstName) \(local.lastName)' was deleted remotely but modified locally."

        case .deletedLocally(let remote):
            return "'\(remote.firstName) \(remote.lastName)' was deleted locally but modified remotely."

        case .shootArchived(let shootId):
            return "Shoot '\(shootId)' was archived remotely but has local changes."
        }
    }

    /// Get resolution options for user decision
    func resolutionOptions(for conflict: ConflictType) -> [ResolutionStrategy] {
        switch conflict {
        case .bothModified:
            return [.keepLocal, .keepRemote, .merge]

        case .deletedRemotely:
            return [.recreateDeleted, .keepRemote]

        case .deletedLocally:
            return [.keepLocal, .keepRemote]

        case .shootArchived:
            return [.keepLocal] // Only option: block sync
        }
    }
}
