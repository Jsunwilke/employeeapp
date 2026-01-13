//
//  TaskCacheService.swift
//  Iconik Employee
//
//  Cache service for task data with 24-hour expiration
//  Implements cache-first loading strategy to minimize database reads
//

import Foundation

// MARK: - Cached Task Data Structure

struct CachedTaskData: Codable {
    let tasks: [TaskItem]
    let cachedAt: Date
    let version: String
}

// MARK: - Task Cache Service

class TaskCacheService {
    static let shared = TaskCacheService()

    private let cacheVersion = "1.2"  // Bumped for schema changes: removed fields, order → sortOrder
    private let cacheAge: TimeInterval = 24 * 60 * 60  // 24 hours
    private let userDefaults = UserDefaults.standard

    private init() {}

    // MARK: - Cache Keys

    private func tasksKey(userId: String, orgId: String) -> String {
        return "focal_tasks_\(cacheVersion)_\(orgId)_\(userId)"
    }

    private func teamTasksKey(orgId: String) -> String {
        return "focal_team_tasks_\(cacheVersion)_\(orgId)"
    }

    private func timestampKey(userId: String, orgId: String) -> String {
        return "focal_tasks_timestamp_\(orgId)_\(userId)"
    }

    private func teamTimestampKey(orgId: String) -> String {
        return "focal_tasks_team_timestamp_\(orgId)"
    }

    // MARK: - Cache Operations (User Tasks)

    /// Get cached tasks for a specific user
    func getCachedTasks(userId: String, orgId: String) -> [TaskItem]? {
        guard let data = userDefaults.data(forKey: tasksKey(userId: userId, orgId: orgId)) else {
            return nil
        }

        do {
            let cachedData = try JSONDecoder().decode(CachedTaskData.self, from: data)

            // Check expiration
            if Date().timeIntervalSince(cachedData.cachedAt) > cacheAge {
                clearCache(userId: userId, orgId: orgId)
                return nil
            }

            return cachedData.tasks
        } catch {
            return nil
        }
    }

    /// Save tasks to cache for a specific user
    func setCachedTasks(_ tasks: [TaskItem], userId: String, orgId: String) {
        let cachedData = CachedTaskData(
            tasks: tasks,
            cachedAt: Date(),
            version: cacheVersion
        )

        do {
            let data = try JSONEncoder().encode(cachedData)
            userDefaults.set(data, forKey: tasksKey(userId: userId, orgId: orgId))

            // Update timestamp to latest task
            if let latestTask = tasks.max(by: { $0.updatedAt < $1.updatedAt }) {
                setLatestTimestamp(latestTask.updatedAt, userId: userId, orgId: orgId)
            }
        } catch {
            // Silent failure
        }
    }

    /// Clear cache for a specific user
    func clearCache(userId: String, orgId: String) {
        userDefaults.removeObject(forKey: tasksKey(userId: userId, orgId: orgId))
        userDefaults.removeObject(forKey: timestampKey(userId: userId, orgId: orgId))
    }

    // MARK: - Cache Operations (Team/Organization Tasks)

    /// Get cached team tasks for an organization
    func getCachedTeamTasks(orgId: String) -> [TaskItem]? {
        guard let data = userDefaults.data(forKey: teamTasksKey(orgId: orgId)) else {
            return nil
        }

        do {
            let cachedData = try JSONDecoder().decode(CachedTaskData.self, from: data)

            // Check expiration
            if Date().timeIntervalSince(cachedData.cachedAt) > cacheAge {
                clearTeamCache(orgId: orgId)
                return nil
            }

            return cachedData.tasks
        } catch {
            return nil
        }
    }

    /// Save team tasks to cache
    func setCachedTeamTasks(_ tasks: [TaskItem], orgId: String) {
        let cachedData = CachedTaskData(
            tasks: tasks,
            cachedAt: Date(),
            version: cacheVersion
        )

        do {
            let data = try JSONEncoder().encode(cachedData)
            userDefaults.set(data, forKey: teamTasksKey(orgId: orgId))

            // Update team timestamp to latest task
            if let latestTask = tasks.max(by: { $0.updatedAt < $1.updatedAt }) {
                setTeamLatestTimestamp(latestTask.updatedAt, orgId: orgId)
            }
        } catch {
            // Silent failure
        }
    }

    /// Clear team cache for an organization
    func clearTeamCache(orgId: String) {
        userDefaults.removeObject(forKey: teamTasksKey(orgId: orgId))
        userDefaults.removeObject(forKey: teamTimestampKey(orgId: orgId))
    }

    // MARK: - Organization-Wide Cache Clear

    /// Clear ALL cache entries for an organization (both user and team)
    /// CRITICAL: Call this after creating, updating, or deleting any task to prevent ghost tasks
    func clearOrganizationCache(orgId: String) {
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let orgKeys = allKeys.filter { $0.contains(orgId) }

        for key in orgKeys {
            userDefaults.removeObject(forKey: key)
        }
    }

    // MARK: - Timestamp Management (User)

    /// Get latest cached timestamp for incremental updates
    func getLatestTimestamp(userId: String, orgId: String) -> Date? {
        guard let interval = userDefaults.object(forKey: timestampKey(userId: userId, orgId: orgId)) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    /// Set latest timestamp from tasks
    private func setLatestTimestamp(_ date: Date, userId: String, orgId: String) {
        userDefaults.set(date.timeIntervalSince1970, forKey: timestampKey(userId: userId, orgId: orgId))
    }

    // MARK: - Timestamp Management (Team)

    /// Get latest cached timestamp for team tasks
    func getTeamLatestTimestamp(orgId: String) -> Date? {
        guard let interval = userDefaults.object(forKey: teamTimestampKey(orgId: orgId)) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    /// Set latest timestamp for team tasks
    private func setTeamLatestTimestamp(_ date: Date, orgId: String) {
        userDefaults.set(date.timeIntervalSince1970, forKey: teamTimestampKey(orgId: orgId))
    }

    // MARK: - Merge Operations

    /// Merge new tasks from database with cached tasks
    /// Used for incremental updates from real-time listeners
    func mergeTasks(cached: [TaskItem], new: [TaskItem]) -> [TaskItem] {
        var merged = cached

        for newTask in new {
            if let index = merged.firstIndex(where: { $0.id == newTask.id }) {
                // Replace existing task with updated version
                merged[index] = newTask
            } else {
                // Add new task
                merged.append(newTask)
            }
        }

        // Sort by updatedAt descending
        merged.sort { $0.updatedAt > $1.updatedAt }

        return merged
    }

    /// Remove deleted tasks from cache
    func removeDeletedTasks(cached: [TaskItem], deletedIds: [String]) -> [TaskItem] {
        return cached.filter { !deletedIds.contains($0.id) }
    }

    // MARK: - Cache Statistics

    /// Get cache age for a user
    func getCacheAge(userId: String, orgId: String) -> TimeInterval? {
        guard let data = userDefaults.data(forKey: tasksKey(userId: userId, orgId: orgId)) else {
            return nil
        }

        do {
            let cachedData = try JSONDecoder().decode(CachedTaskData.self, from: data)
            return Date().timeIntervalSince(cachedData.cachedAt)
        } catch {
            return nil
        }
    }

    /// Check if cache is valid (exists and not expired)
    func isCacheValid(userId: String, orgId: String) -> Bool {
        guard let age = getCacheAge(userId: userId, orgId: orgId) else {
            return false
        }
        return age < cacheAge
    }

    /// Get human-readable cache status
    func getCacheStatus(userId: String, orgId: String) -> String {
        guard let age = getCacheAge(userId: userId, orgId: orgId) else {
            return "No cache"
        }

        let hours = Int(age / 3600)
        let minutes = Int((age.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "Cached \(hours)h \(minutes)m ago"
        } else {
            return "Cached \(minutes)m ago"
        }
    }

    // MARK: - Clear All Cache

    /// Clear ALL task caches (useful for logout or data reset)
    func clearAllCaches() {
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let taskKeys = allKeys.filter { $0.hasPrefix("focal_tasks_") || $0.hasPrefix("focal_team_tasks_") }

        for key in taskKeys {
            userDefaults.removeObject(forKey: key)
        }
    }
}
