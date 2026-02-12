//
//  ScheduleCacheManager.swift
//  Iconik Employee
//
//  Persistent offline cache for schedule data with realtime sync
//

import Foundation

/// Manages persistent offline storage for schedule sessions
/// Sessions are cached to disk so employees can view their schedule without network
actor ScheduleCacheManager {
    static let shared = ScheduleCacheManager()

    // MARK: - Cache Keys
    private let sessionsKey = "cached_sessions"
    private let lastSyncKey = "sessions_last_sync"
    private let organizationKey = "sessions_organization_id"

    // MARK: - Cache Configuration
    /// How long cached data is considered "fresh" (15 minutes)
    private let freshnessDuration: TimeInterval = 900

    /// Maximum age before cache is considered stale but still usable offline (7 days)
    private let maxOfflineAge: TimeInterval = 604800

    // MARK: - File Paths
    private var cacheDirectory: URL {
        guard let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            // Fallback to temporary directory if caches directory unavailable
            print("⚠️ ScheduleCache: Caches directory not available, using temp directory")
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("ScheduleCache", isDirectory: true)
        }
        return baseURL.appendingPathComponent("ScheduleCache", isDirectory: true)
    }

    private var sessionsFileURL: URL {
        cacheDirectory.appendingPathComponent("sessions.json")
    }

    private var metadataFileURL: URL {
        cacheDirectory.appendingPathComponent("metadata.json")
    }

    // MARK: - Cache Metadata
    private struct CacheMetadata: Codable {
        let lastSync: Date
        let organizationId: String
        let sessionCount: Int
    }

    // MARK: - Initialization
    private init() {
        ensureCacheDirectoryExists()
    }

    private func ensureCacheDirectoryExists() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Save Sessions

    /// Save sessions to persistent cache
    func saveSessions(_ sessions: [Session], organizationId: String) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            // Save sessions
            let sessionsData = try encoder.encode(sessions)
            try sessionsData.write(to: sessionsFileURL)

            // Save metadata
            let metadata = CacheMetadata(
                lastSync: Date(),
                organizationId: organizationId,
                sessionCount: sessions.count
            )
            let metadataData = try encoder.encode(metadata)
            try metadataData.write(to: metadataFileURL)

            print("💾 ScheduleCache: Saved \(sessions.count) sessions to disk for org \(organizationId)")
        } catch {
            print("❌ ScheduleCache: Failed to save sessions - \(error.localizedDescription)")
        }
    }

    // MARK: - Load Sessions

    /// Load sessions from persistent cache
    /// Returns nil if cache doesn't exist or is for a different organization
    func loadSessions(organizationId: String) async -> (sessions: [Session], lastSync: Date, isFresh: Bool)? {
        do {
            // Check metadata first
            guard let metadata = loadMetadata() else {
                print("📂 ScheduleCache: No cached metadata found")
                return nil
            }

            // Verify organization matches
            guard metadata.organizationId == organizationId else {
                print("📂 ScheduleCache: Cache is for different organization")
                return nil
            }

            // Check if cache is too old (beyond max offline age)
            let cacheAge = Date().timeIntervalSince(metadata.lastSync)
            if cacheAge > maxOfflineAge {
                print("📂 ScheduleCache: Cache too old (\(Int(cacheAge / 86400)) days), clearing")
                await clearCache()
                return nil
            }

            // Load sessions
            let sessionsData = try Data(contentsOf: sessionsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let sessions = try decoder.decode([Session].self, from: sessionsData)

            let isFresh = cacheAge < freshnessDuration
            print("📂 ScheduleCache: Loaded \(sessions.count) sessions (age: \(Int(cacheAge))s, fresh: \(isFresh))")

            return (sessions: sessions, lastSync: metadata.lastSync, isFresh: isFresh)
        } catch {
            print("❌ ScheduleCache: Failed to load sessions - \(error.localizedDescription)")
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

    /// Get cache info without loading all sessions
    func getCacheInfo(organizationId: String) async -> (lastSync: Date, sessionCount: Int, isFresh: Bool)? {
        guard let metadata = loadMetadata(),
              metadata.organizationId == organizationId else {
            return nil
        }

        let isFresh = Date().timeIntervalSince(metadata.lastSync) < freshnessDuration
        return (lastSync: metadata.lastSync, sessionCount: metadata.sessionCount, isFresh: isFresh)
    }

    // MARK: - Cache Management

    /// Clear all cached data
    func clearCache() async {
        try? FileManager.default.removeItem(at: sessionsFileURL)
        try? FileManager.default.removeItem(at: metadataFileURL)
        print("🗑️ ScheduleCache: Cache cleared")
    }

    /// Check if valid cache exists for organization
    func hasCachedData(organizationId: String) async -> Bool {
        guard let metadata = loadMetadata() else { return false }
        return metadata.organizationId == organizationId
    }

    /// Get time since last sync
    func timeSinceLastSync(organizationId: String) async -> TimeInterval? {
        guard let metadata = loadMetadata(),
              metadata.organizationId == organizationId else {
            return nil
        }
        return Date().timeIntervalSince(metadata.lastSync)
    }

    // MARK: - Formatted Display

    /// Get human-readable last sync time
    func getLastSyncDisplay(organizationId: String) async -> String {
        guard let timeSince = await timeSinceLastSync(organizationId: organizationId) else {
            return "Never synced"
        }

        if timeSince < 60 {
            return "Just now"
        } else if timeSince < 3600 {
            let minutes = Int(timeSince / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if timeSince < 86400 {
            let hours = Int(timeSince / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(timeSince / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}
