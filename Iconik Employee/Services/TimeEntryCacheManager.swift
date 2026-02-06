//
//  TimeEntryCacheManager.swift
//  Iconik Employee
//
//  Persistent offline cache for time tracking data
//

import Foundation

/// Manages persistent offline storage for time entries
/// Time entries are cached to disk so employees can view their hours without network
actor TimeEntryCacheManager {
    static let shared = TimeEntryCacheManager()

    // MARK: - Cache Configuration
    /// How long cached data is considered "fresh" (5 minutes)
    private let freshnessDuration: TimeInterval = 300

    /// Maximum age before cache is considered stale but still usable offline (7 days)
    private let maxOfflineAge: TimeInterval = 604800

    // MARK: - File Paths
    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeEntryCache", isDirectory: true)
    }

    private var entriesFileURL: URL {
        cacheDirectory.appendingPathComponent("time_entries.json")
    }

    private var metadataFileURL: URL {
        cacheDirectory.appendingPathComponent("metadata.json")
    }

    private var currentEntryFileURL: URL {
        cacheDirectory.appendingPathComponent("current_entry.json")
    }

    // MARK: - Cache Metadata
    private struct CacheMetadata: Codable {
        let lastSync: Date
        let userId: String
        let organizationId: String
        let entryCount: Int
        let periodStart: String  // YYYY-MM-DD
        let periodEnd: String    // YYYY-MM-DD
    }

    // MARK: - Initialization
    private init() {
        ensureCacheDirectoryExists()
    }

    private func ensureCacheDirectoryExists() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Save Time Entries

    /// Save time entries to persistent cache
    func saveTimeEntries(_ entries: [TimeEntry], userId: String, organizationId: String, periodStart: String, periodEnd: String) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            // Save entries
            let entriesData = try encoder.encode(entries)
            try entriesData.write(to: entriesFileURL)

            // Save metadata
            let metadata = CacheMetadata(
                lastSync: Date(),
                userId: userId,
                organizationId: organizationId,
                entryCount: entries.count,
                periodStart: periodStart,
                periodEnd: periodEnd
            )
            let metadataData = try encoder.encode(metadata)
            try metadataData.write(to: metadataFileURL)

            print("💾 TimeEntryCache: Saved \(entries.count) entries to disk for period \(periodStart) to \(periodEnd)")
        } catch {
            print("❌ TimeEntryCache: Failed to save entries - \(error.localizedDescription)")
        }
    }

    // MARK: - Load Time Entries

    /// Load time entries from persistent cache
    /// Returns nil if cache doesn't exist or is for different user/organization
    func loadTimeEntries(userId: String, organizationId: String) async -> (entries: [TimeEntry], lastSync: Date, isFresh: Bool)? {
        do {
            // Check metadata first
            guard let metadata = loadMetadata() else {
                print("📂 TimeEntryCache: No cached metadata found")
                return nil
            }

            // Verify user and organization match
            guard metadata.userId == userId, metadata.organizationId == organizationId else {
                print("📂 TimeEntryCache: Cache is for different user/organization")
                return nil
            }

            // Check if cache is too old
            let cacheAge = Date().timeIntervalSince(metadata.lastSync)
            if cacheAge > maxOfflineAge {
                print("📂 TimeEntryCache: Cache too old (\(Int(cacheAge / 86400)) days), clearing")
                await clearCache()
                return nil
            }

            // Load entries
            let entriesData = try Data(contentsOf: entriesFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entries = try decoder.decode([TimeEntry].self, from: entriesData)

            let isFresh = cacheAge < freshnessDuration
            print("📂 TimeEntryCache: Loaded \(entries.count) entries (age: \(Int(cacheAge))s, fresh: \(isFresh))")

            return (entries: entries, lastSync: metadata.lastSync, isFresh: isFresh)
        } catch {
            print("❌ TimeEntryCache: Failed to load entries - \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Current Active Entry Cache

    /// Save the current active time entry for instant display
    func saveCurrentEntry(_ entry: TimeEntry?) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            if let entry = entry {
                let data = try encoder.encode(entry)
                try data.write(to: currentEntryFileURL)
                print("💾 TimeEntryCache: Saved current active entry")
            } else {
                // Remove the file if no active entry
                try? FileManager.default.removeItem(at: currentEntryFileURL)
                print("💾 TimeEntryCache: Cleared current active entry")
            }
        } catch {
            print("❌ TimeEntryCache: Failed to save current entry - \(error.localizedDescription)")
        }
    }

    /// Load the cached current active entry
    func loadCurrentEntry() async -> TimeEntry? {
        do {
            let data = try Data(contentsOf: currentEntryFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entry = try decoder.decode(TimeEntry.self, from: data)
            print("📂 TimeEntryCache: Loaded cached current entry")
            return entry
        } catch {
            return nil
        }
    }

    // MARK: - Metadata

    private func loadMetadata() -> CacheMetadata? {
        do {
            let data = try Data(contentsOf: metadataFileURL)
            return try JSONDecoder().decode(CacheMetadata.self, from: data)
        } catch {
            return nil
        }
    }

    /// Get cache info without loading all entries
    func getCacheInfo(userId: String, organizationId: String) async -> (lastSync: Date, entryCount: Int, isFresh: Bool)? {
        guard let metadata = loadMetadata(),
              metadata.userId == userId,
              metadata.organizationId == organizationId else {
            return nil
        }

        let isFresh = Date().timeIntervalSince(metadata.lastSync) < freshnessDuration
        return (lastSync: metadata.lastSync, entryCount: metadata.entryCount, isFresh: isFresh)
    }

    // MARK: - Cache Management

    /// Clear all cached data
    func clearCache() async {
        try? FileManager.default.removeItem(at: entriesFileURL)
        try? FileManager.default.removeItem(at: metadataFileURL)
        try? FileManager.default.removeItem(at: currentEntryFileURL)
        print("🗑️ TimeEntryCache: Cache cleared")
    }

    /// Check if valid cache exists for user
    func hasCachedData(userId: String, organizationId: String) async -> Bool {
        guard let metadata = loadMetadata() else { return false }
        return metadata.userId == userId && metadata.organizationId == organizationId
    }

    /// Get time since last sync
    func timeSinceLastSync(userId: String, organizationId: String) async -> TimeInterval? {
        guard let metadata = loadMetadata(),
              metadata.userId == userId,
              metadata.organizationId == organizationId else {
            return nil
        }
        return Date().timeIntervalSince(metadata.lastSync)
    }

    /// Get human-readable last sync time
    func getLastSyncDisplay(userId: String, organizationId: String) async -> String {
        guard let timeSince = await timeSinceLastSync(userId: userId, organizationId: organizationId) else {
            return "Never synced"
        }

        if timeSince < 60 {
            return "Just now"
        } else if timeSince < 3600 {
            let minutes = Int(timeSince / 60)
            return "\(minutes)m ago"
        } else if timeSince < 86400 {
            let hours = Int(timeSince / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(timeSince / 86400)
            return "\(days)d ago"
        }
    }
}
