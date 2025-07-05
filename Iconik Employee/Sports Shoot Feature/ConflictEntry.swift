import Foundation

/// Models for representing conflicts
public struct ConflictEntry {
    let localEntry: RosterEntry
    let remoteEntry: RosterEntry
}

public struct ConflictGroup {
    let localGroup: GroupImage
    let remoteGroup: GroupImage
}

// Extension to make OfflineManager's internal conflict types match our public conflict types
extension OfflineManager {
    typealias EntryConflict = ConflictEntry
    typealias GroupConflict = ConflictGroup
}