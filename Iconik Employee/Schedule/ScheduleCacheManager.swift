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
        /// Whether the stored set carries draft rows worth preserving — i.e. it
        /// was written by, or merged from, a fetch that asked for unpublished
        /// sessions. This is what tells a later narrower save not to drop them.
        ///
        /// Optional so a cache written before PUB.1 still decodes; absent means
        /// published-only, which is what every writer before PUB.1 was. Without
        /// this the file was a single unlabelled blob that two callers with
        /// different scopes took turns overwriting, and every reader then
        /// ASSUMED it held everything.
        let containsUnpublished: Bool?

        /// Whether the drafts in the file are a COMPLETE, current snapshot —
        /// true only when the last write was itself a broad fetch.
        ///
        /// Deliberately separate from `containsUnpublished`, because they are
        /// different facts and conflating them is how the in-memory cache came to
        /// lie in the first place. A narrow save that PRESERVED drafts still holds
        /// drafts, but it learned nothing about ones created or deleted since —
        /// so it must not be served to a draft-wanting caller as if authoritative.
        let unpublishedComplete: Bool?
    }

    // MARK: - Initialization
    private init() {
        ensureCacheDirectoryExists()
    }

    private func ensureCacheDirectoryExists() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Save Sessions

    /// Save sessions to persistent cache.
    ///
    /// `includesUnpublished` is the scope the caller FETCHED with, not a property
    /// of the rows. It matters because there is one file behind several callers:
    /// the home dashboard asks for published sessions only, the schedule asks for
    /// everything, and before PUB.1 whichever refreshed last decided what the
    /// whole app could see offline. Since the schedule now fetches unpublished
    /// for every user, a published-only save landing last would have deleted
    /// every draft from the offline cache — and the schedule would then have
    /// shown a draft-free week, offline, with no error and no way to tell.
    func saveSessions(_ sessions: [Session], organizationId: String, includesUnpublished: Bool) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            var toStore = sessions
            var carriesDrafts = includesUnpublished

            // A narrower save keeps the drafts a broader one put here — it was
            // never told about them, so it cannot be treated as evidence they are
            // gone. Anything it DID fetch replaces what was on disk, matched by
            // id, so a draft that has since been published is not kept twice.
            //
            // What it must NOT do is claim the result is a current picture of the
            // drafts: one created or deleted since the last broad fetch is missing
            // or stale here, and `unpublishedComplete` stays false to say so.
            if !includesUnpublished,
               let existing = loadMetadata(),
               existing.organizationId == organizationId,
               existing.containsUnpublished == true,
               let previous = loadSessionsFile() {
                let incomingIDs = Set(sessions.map { $0.id })
                let keptDrafts = previous.filter { !$0.is_published && !incomingIDs.contains($0.id) }
                if !keptDrafts.isEmpty {
                    toStore = sessions + keptDrafts
                    carriesDrafts = true
                }
            }

            // Save sessions
            let sessionsData = try encoder.encode(toStore)
            try sessionsData.write(to: sessionsFileURL)

            // Save metadata
            let metadata = CacheMetadata(
                lastSync: Date(),
                organizationId: organizationId,
                sessionCount: toStore.count,
                containsUnpublished: carriesDrafts,
                unpublishedComplete: includesUnpublished
            )
            let metadataData = try encoder.encode(metadata)
            try metadataData.write(to: metadataFileURL)

            print("💾 ScheduleCache: Saved \(toStore.count) sessions to disk for org \(organizationId) (drafts: \(carriesDrafts), complete: \(includesUnpublished))")
        } catch {
            print("❌ ScheduleCache: Failed to save sessions - \(error.localizedDescription)")
        }
    }

    /// The stored session array on its own, with no metadata checks. Only for the
    /// merge above, which has already validated the metadata it cares about.
    private func loadSessionsFile() -> [Session]? {
        guard let data = try? Data(contentsOf: sessionsFileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Session].self, from: data)
    }

    // MARK: - Load Sessions

    /// Load sessions from persistent cache
    /// Returns nil if cache doesn't exist or is for a different organization.
    /// `unpublishedComplete` reports whether the stored drafts can be trusted as a
    /// current, complete set, so the caller can tag its own in-memory cache
    /// truthfully instead of assuming. Drafts may be present even when it is
    /// false — they are just not known to be up to date.
    func loadSessions(organizationId: String) async -> (sessions: [Session], lastSync: Date, isFresh: Bool, unpublishedComplete: Bool)? {
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
            let unpublishedComplete = metadata.unpublishedComplete ?? false
            print("📂 ScheduleCache: Loaded \(sessions.count) sessions (age: \(Int(cacheAge))s, fresh: \(isFresh), drafts complete: \(unpublishedComplete))")

            return (sessions: sessions, lastSync: metadata.lastSync, isFresh: isFresh,
                    unpublishedComplete: unpublishedComplete)
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
