//
//  in.swift
//  Iconik Employee
//
//  Created by administrator on 5/19/25.
//


//
//  CacheStatus.swift
//  Iconik Employee
//
//  Created to resolve ambiguity issues
//

import Foundation

// Define the CacheStatus enum in a standalone file
// This ensures a single source of truth for this type
public enum CacheStatus {
    case notCached
    case cached
    case modified
    case syncing
    case error
    
    // Utility method to convert status to string
    public func description() -> String {
        switch self {
        case .notCached:
            return "Not Available Offline"
        case .cached:
            return "Available Offline"
        case .modified:
            return "Modified - Needs Sync"
        case .syncing:
            return "Syncing..."
        case .error:
            return "Sync Error"
        }
    }
}