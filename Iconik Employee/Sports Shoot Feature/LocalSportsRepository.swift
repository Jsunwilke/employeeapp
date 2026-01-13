//
//  LocalSportsRepository.swift
//  Iconik Employee
//
//  Local cache for sports data - enables offline-first experience
//  Stores sports shoots, roster entries, and group images as JSON files
//

import Foundation

class LocalSportsRepository {
    static let shared = LocalSportsRepository()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // Cache directory for sports data
    private var cacheDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let cacheDir = paths[0].appendingPathComponent("SportsCache", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        return cacheDir
    }

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Sports Shoots

    /// Save all sports shoots for an organization
    func saveSportsShoots(_ shoots: [SportsShoot], forOrg orgId: String) {
        let filename = "shoots_\(orgId).json"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        do {
            let data = try encoder.encode(shoots)
            try data.write(to: fileURL, options: .atomic)
            print("LocalSportsRepository: Saved \(shoots.count) shoots for org \(orgId)")
        } catch {
            print("LocalSportsRepository: Failed to save shoots - \(error)")
        }
    }

    /// Load all sports shoots for an organization
    func loadSportsShoots(forOrg orgId: String) -> [SportsShoot]? {
        let filename = "shoots_\(orgId).json"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let shoots = try decoder.decode([SportsShoot].self, from: data)
            print("LocalSportsRepository: Loaded \(shoots.count) cached shoots for org \(orgId)")
            return shoots
        } catch {
            print("LocalSportsRepository: Failed to load shoots - \(error)")
            return nil
        }
    }

    /// Save a single sports shoot (also updates the org's shoot list)
    func saveSportsShoot(_ shoot: SportsShoot) {
        // Save individual shoot
        let filename = "shoot_\(shoot.id.uuidString).json"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        do {
            let data = try encoder.encode(shoot)
            try data.write(to: fileURL, options: .atomic)
            print("LocalSportsRepository: Saved shoot \(shoot.id)")
        } catch {
            print("LocalSportsRepository: Failed to save shoot - \(error)")
        }

        // Also update in org's shoot list if it exists
        if var shoots = loadSportsShoots(forOrg: shoot.organizationId) {
            if let index = shoots.firstIndex(where: { $0.id == shoot.id }) {
                shoots[index] = shoot
            } else {
                shoots.append(shoot)
            }
            saveSportsShoots(shoots, forOrg: shoot.organizationId)
        }
    }

    /// Load a single sports shoot by ID
    func loadSportsShoot(id: UUID) -> SportsShoot? {
        let filename = "shoot_\(id.uuidString).json"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let shoot = try decoder.decode(SportsShoot.self, from: data)
            return shoot
        } catch {
            print("LocalSportsRepository: Failed to load shoot \(id) - \(error)")
            return nil
        }
    }

    // MARK: - Roster Entries

    /// Save all roster entries for a job
    func saveRosterEntries(_ entries: [RosterEntry], forJob jobId: UUID) {
        let filename = "roster_\(jobId.uuidString).json"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        do {
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
            print("LocalSportsRepository: Saved \(entries.count) roster entries for job \(jobId)")
        } catch {
            print("LocalSportsRepository: Failed to save roster entries - \(error)")
        }
    }

    /// Load all roster entries for a job
    func loadRosterEntries(forJob jobId: UUID) -> [RosterEntry]? {
        let filename = "roster_\(jobId.uuidString).json"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let entries = try decoder.decode([RosterEntry].self, from: data)
            print("LocalSportsRepository: Loaded \(entries.count) cached roster entries for job \(jobId)")
            return entries
        } catch {
            print("LocalSportsRepository: Failed to load roster entries - \(error)")
            return nil
        }
    }

    /// Update a single roster entry in the cache
    func updateRosterEntry(_ entry: RosterEntry, forJob jobId: UUID) {
        guard var entries = loadRosterEntries(forJob: jobId) else {
            // No cache exists, create new with just this entry
            saveRosterEntries([entry], forJob: jobId)
            return
        }

        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }

        saveRosterEntries(entries, forJob: jobId)
    }

    /// Delete a roster entry from the cache
    func deleteRosterEntry(id: UUID, forJob jobId: UUID) {
        guard var entries = loadRosterEntries(forJob: jobId) else { return }

        entries.removeAll { $0.id == id }
        saveRosterEntries(entries, forJob: jobId)
    }

    // MARK: - Group Images

    /// Save all group images for a job
    func saveGroupImages(_ groups: [GroupImage], forJob jobId: UUID) {
        let filename = "groups_\(jobId.uuidString).json"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        do {
            let data = try encoder.encode(groups)
            try data.write(to: fileURL, options: .atomic)
            print("LocalSportsRepository: Saved \(groups.count) group images for job \(jobId)")
        } catch {
            print("LocalSportsRepository: Failed to save group images - \(error)")
        }
    }

    /// Load all group images for a job
    func loadGroupImages(forJob jobId: UUID) -> [GroupImage]? {
        let filename = "groups_\(jobId.uuidString).json"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let groups = try decoder.decode([GroupImage].self, from: data)
            print("LocalSportsRepository: Loaded \(groups.count) cached group images for job \(jobId)")
            return groups
        } catch {
            print("LocalSportsRepository: Failed to load group images - \(error)")
            return nil
        }
    }

    /// Update a single group image in the cache
    func updateGroupImage(_ group: GroupImage, forJob jobId: UUID) {
        guard var groups = loadGroupImages(forJob: jobId) else {
            // No cache exists, create new with just this group
            saveGroupImages([group], forJob: jobId)
            return
        }

        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }

        saveGroupImages(groups, forJob: jobId)
    }

    /// Delete a group image from the cache
    func deleteGroupImage(id: UUID, forJob jobId: UUID) {
        guard var groups = loadGroupImages(forJob: jobId) else { return }

        groups.removeAll { $0.id == id }
        saveGroupImages(groups, forJob: jobId)
    }

    // MARK: - Cache Management

    /// Clear all cached data for a specific job
    func clearJobCache(jobId: UUID) {
        let rosterFile = cacheDirectory.appendingPathComponent("roster_\(jobId.uuidString).json")
        let groupsFile = cacheDirectory.appendingPathComponent("groups_\(jobId.uuidString).json")
        let shootFile = cacheDirectory.appendingPathComponent("shoot_\(jobId.uuidString).json")

        try? fileManager.removeItem(at: rosterFile)
        try? fileManager.removeItem(at: groupsFile)
        try? fileManager.removeItem(at: shootFile)

        print("LocalSportsRepository: Cleared cache for job \(jobId)")
    }

    /// Clear all cached data
    func clearAllCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        print("LocalSportsRepository: Cleared all cache")
    }

    /// Get total cache size in bytes
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
    }
}
