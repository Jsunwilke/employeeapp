//
//  in.swift
//  Iconik Employee
//
//  Created by administrator on 5/19/25.
//


import Foundation

// This file ensures we have proper access to the CacheStatus enum in OfflineManager
// If the main OfflineManager defines its CacheStatus differently, this will be superseded

// Extend OfflineManager with helper methods for specific CacheStatus usages
extension OfflineManager {
    // Access CacheStatus values in a type-safe way
    var notCachedStatus: CacheStatus { return .notCached }
    var cachedStatus: CacheStatus { return .cached }
    var modifiedStatus: CacheStatus { return .modified }
    var syncingStatus: CacheStatus { return .syncing }
    var errorStatus: CacheStatus { return .error }
}