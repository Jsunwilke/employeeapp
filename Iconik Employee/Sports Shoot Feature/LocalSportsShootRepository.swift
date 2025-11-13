//
//  LocalSportsShootRepository.swift
//  Iconik Employee
//
//  Local-first data repository for sports shoots
//  All UI operations use this repository - no direct Firestore calls
//

import Foundation
import CoreData

class LocalSportsShootRepository {
    static let shared = LocalSportsShootRepository()

    private init() {}

    // MARK: - Core Data Stack

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "SportsShootDataModel")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
            print("✓ CoreData persistent store loaded: \(description)")
        }
        // Ensure viewContext merges changes from parent
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    private var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    // MARK: - Save Context

    private func saveContext() -> Bool {
        if context.hasChanges {
            do {
                try context.save()
                print("✓ CoreData context saved successfully")
                return true
            } catch let error as NSError {
                print("❌ Error saving CoreData context:")
                print("   Description: \(error.localizedDescription)")
                print("   User Info: \(error.userInfo)")
                if let detailedErrors = error.userInfo[NSDetailedErrorsKey] as? [NSError] {
                    for detailedError in detailedErrors {
                        print("   Detailed Error: \(detailedError.localizedDescription)")
                    }
                }
                return false
            }
        }
        return true
    }

    // MARK: - Shoot Operations

    /// Save a complete shoot to local cache
    func saveShoot(_ shoot: SportsShoot) -> Bool {
        // Check if shoot already exists
        let fetchRequest: NSFetchRequest<CachedShoot> = CachedShoot.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", shoot.id)

        do {
            let results = try context.fetch(fetchRequest)
            let cachedShoot: CachedShoot

            if let existing = results.first {
                cachedShoot = existing
            } else {
                cachedShoot = CachedShoot(context: context)
                cachedShoot.id = shoot.id
            }

            // Update shoot attributes
            cachedShoot.schoolName = shoot.schoolName
            cachedShoot.schoolId = shoot.schoolId
            cachedShoot.sportName = shoot.sportName
            cachedShoot.seasonType = shoot.seasonType
            cachedShoot.shootDate = shoot.shootDate
            cachedShoot.location = shoot.location
            cachedShoot.photographer = shoot.photographer
            cachedShoot.additionalNotes = shoot.additionalNotes
            cachedShoot.organizationID = shoot.organizationID
            cachedShoot.createdAt = shoot.createdAt
            cachedShoot.updatedAt = shoot.updatedAt
            cachedShoot.isArchived = shoot.isArchived
            cachedShoot.modifiedAt = Date()

            // Store raw JSON for complete data preservation (includes groupImages)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let jsonData = try? encoder.encode(shoot),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                cachedShoot.rawData = jsonString
            }

            // Save roster entries
            // First, remove old entries
            if let existingRoster = cachedShoot.roster as? Set<CachedRosterEntry> {
                for entry in existingRoster {
                    context.delete(entry)
                }
            }

            // Add new entries
            for rosterEntry in shoot.roster {
                let cachedEntry = CachedRosterEntry(context: context)
                cachedEntry.id = rosterEntry.id
                cachedEntry.shootId = shoot.id
                cachedEntry.lastName = rosterEntry.lastName
                cachedEntry.firstName = rosterEntry.firstName
                cachedEntry.teacher = rosterEntry.teacher
                cachedEntry.group = rosterEntry.group
                cachedEntry.email = rosterEntry.email
                cachedEntry.phone = rosterEntry.phone
                cachedEntry.imageNumbers = rosterEntry.imageNumbers
                cachedEntry.notes = rosterEntry.notes
                cachedEntry.wasBlank = rosterEntry.wasBlank
                cachedEntry.isFilledBlank = rosterEntry.isFilledBlank
                cachedEntry.modifiedAt = Date()
                cachedEntry.isSynced = true
                cachedEntry.shoot = cachedShoot
            }

            return saveContext()
        } catch {
            print("Error saving shoot: \(error.localizedDescription)")
            return false
        }
    }

    /// Get a shoot from local cache
    func getShoot(id: String) -> SportsShoot? {
        let fetchRequest: NSFetchRequest<CachedShoot> = CachedShoot.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)

        do {
            let results = try context.fetch(fetchRequest)
            guard let cachedShoot = results.first else { return nil }

            // Try to decode from raw JSON first (preserves all data including groupImages)
            if let rawData = cachedShoot.rawData,
               let jsonData = rawData.data(using: .utf8) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let shoot = try? decoder.decode(SportsShoot.self, from: jsonData) {
                    return shoot
                }
            }

            // Fallback: construct from CoreData attributes
            var roster: [RosterEntry] = []
            if let cachedRoster = cachedShoot.roster as? Set<CachedRosterEntry> {
                roster = cachedRoster.map { entry in
                    RosterEntry(
                        id: entry.id ?? UUID().uuidString,
                        lastName: entry.lastName ?? "",
                        firstName: entry.firstName ?? "",
                        teacher: entry.teacher ?? "",
                        group: entry.group ?? "",
                        email: entry.email ?? "",
                        phone: entry.phone ?? "",
                        imageNumbers: entry.imageNumbers ?? "",
                        notes: entry.notes ?? "",
                        wasBlank: entry.wasBlank,
                        isFilledBlank: entry.isFilledBlank
                    )
                }
            }

            // Reconstruct SportsShoot from CoreData
            return SportsShoot(
                id: cachedShoot.id ?? "",
                schoolName: cachedShoot.schoolName ?? "",
                schoolId: cachedShoot.schoolId,
                sportName: cachedShoot.sportName ?? "",
                seasonType: cachedShoot.seasonType,
                shootDate: cachedShoot.shootDate ?? Date(),
                location: cachedShoot.location ?? "",
                photographer: cachedShoot.photographer ?? "",
                roster: roster,
                groupImages: [], // Empty if no raw data (groupImages not in CoreData schema)
                additionalNotes: cachedShoot.additionalNotes ?? "",
                organizationID: cachedShoot.organizationID ?? "",
                createdAt: cachedShoot.createdAt ?? Date(),
                updatedAt: cachedShoot.updatedAt ?? Date(),
                isArchived: cachedShoot.isArchived
            )
        } catch {
            print("Error fetching shoot: \(error.localizedDescription)")
            return nil
        }
    }

    /// Update a single roster entry
    func updateRosterEntry(shootId: String, entry: RosterEntry) -> Bool {
        let fetchRequest: NSFetchRequest<CachedRosterEntry> = CachedRosterEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@ AND shootId == %@", entry.id, shootId)

        do {
            let results = try context.fetch(fetchRequest)

            let cachedEntry: CachedRosterEntry
            if let existing = results.first {
                cachedEntry = existing
                print("📝 Updating existing entry: \(entry.id)")
            } else {
                cachedEntry = CachedRosterEntry(context: context)
                cachedEntry.id = entry.id
                cachedEntry.shootId = shootId
                print("📝 Creating new entry: \(entry.id)")
            }

            // Update attributes
            cachedEntry.lastName = entry.lastName
            cachedEntry.firstName = entry.firstName
            cachedEntry.teacher = entry.teacher
            cachedEntry.group = entry.group
            cachedEntry.email = entry.email
            cachedEntry.phone = entry.phone
            cachedEntry.imageNumbers = entry.imageNumbers
            cachedEntry.notes = entry.notes
            cachedEntry.wasBlank = entry.wasBlank
            cachedEntry.isFilledBlank = entry.isFilledBlank
            cachedEntry.modifiedAt = Date()
            cachedEntry.isSynced = false // Mark as needing sync
            print("   Updated imageNumbers: \(entry.imageNumbers)")

            // Update shoot's modified date and raw data
            let shootFetch: NSFetchRequest<CachedShoot> = CachedShoot.fetchRequest()
            shootFetch.predicate = NSPredicate(format: "id == %@", shootId)
            if let shoot = try context.fetch(shootFetch).first {
                shoot.modifiedAt = Date()
                shoot.updatedAt = Date()

                // Update raw JSON data if it exists
                if let rawData = shoot.rawData,
                   let jsonData = rawData.data(using: .utf8) {

                    // Use proper date decoding strategy
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601

                    if var sportsShoot = try? decoder.decode(SportsShoot.self, from: jsonData) {
                        // Update the entry in the roster
                        if let index = sportsShoot.roster.firstIndex(where: { $0.id == entry.id }) {
                            sportsShoot.roster[index] = entry
                        } else {
                            sportsShoot.roster.append(entry)
                        }
                        sportsShoot.updatedAt = Date()

                        // Save updated JSON with proper date encoding
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601

                        if let updatedJsonData = try? encoder.encode(sportsShoot),
                           let updatedJsonString = String(data: updatedJsonData, encoding: .utf8) {
                            shoot.rawData = updatedJsonString
                            print("✓ Updated rawData for shoot \(shootId)")
                        } else {
                            print("⚠️ Failed to encode updated shoot to JSON")
                        }
                    } else {
                        print("⚠️ Failed to decode existing rawData for shoot \(shootId)")
                    }
                }
            }

            return saveContext()
        } catch {
            print("Error updating roster entry: \(error.localizedDescription)")
            return false
        }
    }

    /// Delete a shoot from local cache
    func deleteShoot(id: String) -> Bool {
        let fetchRequest: NSFetchRequest<CachedShoot> = CachedShoot.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)

        do {
            let results = try context.fetch(fetchRequest)
            for shoot in results {
                context.delete(shoot)
            }
            return saveContext()
        } catch {
            print("Error deleting shoot: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Sync Tracking

    /// Mark a shoot as synced with Firestore
    func markAsSynced(shootId: String) {
        let fetchRequest: NSFetchRequest<CachedShoot> = CachedShoot.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", shootId)

        do {
            let results = try context.fetch(fetchRequest)
            if let shoot = results.first {
                shoot.lastSyncedAt = Date()

                // Mark all roster entries as synced
                if let roster = shoot.roster as? Set<CachedRosterEntry> {
                    for entry in roster {
                        entry.isSynced = true
                    }
                }

                _ = saveContext()
            }
        } catch {
            print("Error marking shoot as synced: \(error.localizedDescription)")
        }
    }

    /// Get all shoots that need syncing
    func getShoots(needingSync: Bool) -> [SportsShoot] {
        let fetchRequest: NSFetchRequest<CachedShoot> = CachedShoot.fetchRequest()

        if needingSync {
            // Find shoots where modifiedAt > lastSyncedAt or lastSyncedAt is nil
            fetchRequest.predicate = NSPredicate(format: "modifiedAt > lastSyncedAt OR lastSyncedAt == nil")
        }

        do {
            let results = try context.fetch(fetchRequest)
            return results.compactMap { cachedShoot in
                guard let id = cachedShoot.id else { return nil }
                return getShoot(id: id)
            }
        } catch {
            print("Error fetching shoots needing sync: \(error.localizedDescription)")
            return []
        }
    }

    /// Get all unsynced roster entries for a shoot
    func getUnsyncedEntries(shootId: String) -> [RosterEntry] {
        let fetchRequest: NSFetchRequest<CachedRosterEntry> = CachedRosterEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "shootId == %@ AND isSynced == NO", shootId)

        do {
            let results = try context.fetch(fetchRequest)
            return results.map { entry in
                RosterEntry(
                    id: entry.id ?? UUID().uuidString,
                    lastName: entry.lastName ?? "",
                    firstName: entry.firstName ?? "",
                    teacher: entry.teacher ?? "",
                    group: entry.group ?? "",
                    email: entry.email ?? "",
                    phone: entry.phone ?? "",
                    imageNumbers: entry.imageNumbers ?? "",
                    notes: entry.notes ?? "",
                    wasBlank: entry.wasBlank,
                    isFilledBlank: entry.isFilledBlank
                )
            }
        } catch {
            print("Error fetching unsynced entries: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Download Status

    /// Check if a shoot is fully cached
    func isFullyCached(shootId: String) -> Bool {
        let fetchRequest: NSFetchRequest<CachedShoot> = CachedShoot.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@ AND isFullyCached == YES", shootId)

        do {
            let count = try context.count(for: fetchRequest)
            return count > 0
        } catch {
            print("Error checking if shoot is cached: \(error.localizedDescription)")
            return false
        }
    }

    /// Mark a shoot as fully cached (available offline)
    func markFullyCached(shootId: String) {
        let fetchRequest: NSFetchRequest<CachedShoot> = CachedShoot.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", shootId)

        do {
            let results = try context.fetch(fetchRequest)
            if let shoot = results.first {
                shoot.isFullyCached = true
                _ = saveContext()
            }
        } catch {
            print("Error marking shoot as fully cached: \(error.localizedDescription)")
        }
    }

    /// Get all fully cached shoot IDs
    func getAllCachedShootIds() -> [String] {
        let fetchRequest: NSFetchRequest<CachedShoot> = CachedShoot.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isFullyCached == YES")
        fetchRequest.propertiesToFetch = ["id"]

        do {
            let results = try context.fetch(fetchRequest)
            return results.compactMap { $0.id }
        } catch {
            print("Error fetching cached shoot IDs: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Migration from JSON Cache

    /// Migrate existing JSON cached shoots to CoreData
    /// Call this once on app launch to convert old cache format
    func migrateFromJSONCache() {
        let fileManager = FileManager.default
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sportsShootCache")

        // Check if migration already completed
        let migrationKey = "didMigrateJSONCacheToCoreData"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            print("JSON to CoreData migration already completed")
            return
        }

        print("Starting migration from JSON cache to CoreData...")

        guard fileManager.fileExists(atPath: cachesDirectory.path) else {
            print("No JSON cache directory found, skipping migration")
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: cachesDirectory, includingPropertiesForKeys: nil)
            let jsonFiles = fileURLs.filter { $0.pathExtension == "json" && $0.lastPathComponent != "cachedShoots.json" }

            var migratedCount = 0
            var failedCount = 0

            for fileURL in jsonFiles {
                do {
                    let jsonData = try Data(contentsOf: fileURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601

                    let shoot = try decoder.decode(SportsShoot.self, from: jsonData)

                    // Save to CoreData
                    if saveShoot(shoot) {
                        markFullyCached(shootId: shoot.id)
                        markAsSynced(shootId: shoot.id)
                        migratedCount += 1
                        print("✓ Migrated shoot: \(shoot.schoolName)")
                    } else {
                        failedCount += 1
                        print("✗ Failed to migrate shoot: \(shoot.schoolName)")
                    }
                } catch {
                    failedCount += 1
                    print("✗ Error migrating file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }

            print("Migration complete: \(migratedCount) shoots migrated, \(failedCount) failed")

            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: migrationKey)

        } catch {
            print("Error during migration: \(error.localizedDescription)")
        }
    }
}
