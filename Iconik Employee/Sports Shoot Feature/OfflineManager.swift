//
//  OfflineManager.swift
//  Iconik Employee
//
//  Created by administrator on 5/18/25.
//


import Foundation
import Firebase
import FirebaseFirestore
import CoreData

// MARK: - Offline Manager for Sports Shoots
class OfflineManager {
    static let shared = OfflineManager()
    
    // File manager to handle caching
    private let fileManager = FileManager.default
    private let db = Firestore.firestore()
    
    // Network status
    private var isOnline = true
    private let networkMonitor = NetworkMonitor()
    
    // Directory for cached sports shoots
    private var cachesDirectory: URL {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("sportsShootCache")
    }
    
    // Path for tracking cached shoots
    private var cachedShootsPath: URL {
        return cachesDirectory.appendingPathComponent("cachedShoots.json")
    }
    
    // Dictionary to track modified shoots that need syncing
    private var modifiedShoots: [String: Date] = [:]
    private var cachedShoots: [String] = []
    
    // Dictionary to cache locks locally when offline
    private var localLocks: [String: [String: String]] = [:] // [shootID: [entryID: editorName]]
    
    // Cache status
    enum CacheStatus {
        case notCached
        case cached
        case modified
        case syncing
        case error
    }
    
    private init() {
        // Create cache directory if it doesn't exist
        do {
            if !fileManager.fileExists(atPath: cachesDirectory.path) {
                try fileManager.createDirectory(at: cachesDirectory, withIntermediateDirectories: true)
            }
            
            // Load list of cached shoots
            loadCachedShootsList()
            
            // Set up network monitoring
            setupNetworkMonitoring()
            
        } catch {
            print("Error initializing cache: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor.startMonitoring { [weak self] isConnected in
            self?.isOnline = isConnected
            
            // If we just came online, start syncing
            if isConnected {
                self?.syncModifiedShoots()
                // Clear local locks when going online
                self?.clearLocalLocks()
            } else {
                // When going offline, clear any locks from the server
                // as they won't be valid anyway
                self?.localLocks.removeAll()
            }
            
            // Notify others about network status change
            NotificationCenter.default.post(
                name: NSNotification.Name("OfflineManagerNetworkStatusChanged"),
                object: nil,
                userInfo: ["isOnline": isConnected]
            )
        }
    }
    
    // Public method to check if device is online
    func isDeviceOnline() -> Bool {
        return isOnline
    }
    
    // MARK: - Caching
    
    // Cache a shoot for offline use
    func cacheShoot(_ shoot: SportsShoot, completion: @escaping (Bool) -> Void) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            let shootData = try encoder.encode(shoot)
            let shootPath = cachesDirectory.appendingPathComponent("\(shoot.id).json")
            
            try shootData.write(to: shootPath)
            
            // Add to cached shoots list if not already present
            if !cachedShoots.contains(shoot.id) {
                cachedShoots.append(shoot.id)
                saveCachedShootsList()
            }
            
            completion(true)
        } catch {
            print("Error caching shoot: \(error.localizedDescription)")
            completion(false)
        }
    }
    
    // Get cache status for a shoot
    func cacheStatusForShoot(id: String) -> CacheStatus {
        if modifiedShoots[id] != nil {
            return .modified
        }
        
        if cachedShoots.contains(id) {
            return .cached
        }
        
        return .notCached
    }
    
    // Check if a shoot is cached
    func isShootCached(id: String) -> Bool {
        return cachedShoots.contains(id)
    }
    
    // Load a cached shoot
    func loadCachedShoot(id: String) -> SportsShoot? {
        let shootPath = cachesDirectory.appendingPathComponent("\(id).json")
        
        guard fileManager.fileExists(atPath: shootPath.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: shootPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let shoot = try decoder.decode(SportsShoot.self, from: data)
            return shoot
        } catch {
            print("Error loading cached shoot: \(error.localizedDescription)")
            return nil
        }
    }
    
    // Mark a shoot as modified (needs syncing)
    func markShootAsModified(id: String) {
        modifiedShoots[id] = Date()
        saveModifiedShootsList()
    }
    
    // Save cached shoots list
    private func saveCachedShootsList() {
        do {
            let data = try JSONEncoder().encode(cachedShoots)
            try data.write(to: cachedShootsPath)
        } catch {
            print("Error saving cached shoots list: \(error.localizedDescription)")
        }
    }
    
    // Load cached shoots list
    private func loadCachedShootsList() {
        guard fileManager.fileExists(atPath: cachedShootsPath.path) else {
            cachedShoots = []
            return
        }
        
        do {
            let data = try Data(contentsOf: cachedShootsPath)
            cachedShoots = try JSONDecoder().decode([String].self, from: data)
        } catch {
            print("Error loading cached shoots list: \(error.localizedDescription)")
            cachedShoots = []
        }
    }
    
    // Save modified shoots list
    private func saveModifiedShootsList() {
        let modifiedShootsPath = cachesDirectory.appendingPathComponent("modifiedShoots.json")
        
        do {
            let data = try JSONEncoder().encode(modifiedShoots)
            try data.write(to: modifiedShootsPath)
        } catch {
            print("Error saving modified shoots list: \(error.localizedDescription)")
        }
    }
    
    // Load modified shoots list
    private func loadModifiedShootsList() {
        let modifiedShootsPath = cachesDirectory.appendingPathComponent("modifiedShoots.json")
        
        guard fileManager.fileExists(atPath: modifiedShootsPath.path) else {
            modifiedShoots = [:]
            return
        }
        
        do {
            let data = try Data(contentsOf: modifiedShootsPath)
            modifiedShoots = try JSONDecoder().decode([String: Date].self, from: data)
        } catch {
            print("Error loading modified shoots list: \(error.localizedDescription)")
            modifiedShoots = [:]
        }
    }
    
    // MARK: - Lock Management for Offline Mode
    
    // Add a local lock when offline
    func addLocalLock(shootID: String, entryID: String, editorName: String) {
        if localLocks[shootID] == nil {
            localLocks[shootID] = [:]
        }
        
        localLocks[shootID]?[entryID] = editorName
        
        // Notify that locks have changed
        NotificationCenter.default.post(
            name: NSNotification.Name("OfflineLocksChanged"),
            object: nil,
            userInfo: ["shootID": shootID]
        )
    }
    
    // Remove a local lock
    func removeLocalLock(shootID: String, entryID: String) {
        localLocks[shootID]?[entryID] = nil
        
        // Notify that locks have changed
        NotificationCenter.default.post(
            name: NSNotification.Name("OfflineLocksChanged"),
            object: nil,
            userInfo: ["shootID": shootID]
        )
    }
    
    // Get all local locks for a shoot
    func getLocalLocks(shootID: String) -> [String: String] {
        return localLocks[shootID] ?? [:]
    }
    
    // Clear all local locks
    func clearLocalLocks() {
        localLocks.removeAll()
    }
    
    // MARK: - Entry Management
    
    // This helps manage entry conflicts when going from offline to online
    struct EntryConflict {
        let localEntry: RosterEntry
        let remoteEntry: RosterEntry
    }
    
    struct GroupConflict {
        let localGroup: GroupImage
        let remoteGroup: GroupImage
    }
    
    // Update a roster entry when offline
    func updateRosterEntryOffline(shootID: String, entry: RosterEntry, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get the cached shoot
        guard var shoot = loadCachedShoot(id: shootID) else {
            let error = NSError(domain: "OfflineManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Shoot not found in cache"])
            completion(.failure(error))
            return
        }
        
        // Find the index of the entry to update
        if let index = shoot.roster.firstIndex(where: { $0.id == entry.id }) {
            // Update the entry
            shoot.roster[index] = entry
        } else {
            // Add the entry if it doesn't exist
            shoot.roster.append(entry)
        }
        
        // Update the shoot
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            let shootData = try encoder.encode(shoot)
            let shootPath = cachesDirectory.appendingPathComponent("\(shootID).json")
            
            try shootData.write(to: shootPath)
            
            // Mark shoot as modified
            markShootAsModified(id: shootID)
            
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    // Add a roster entry when offline
    func addRosterEntryOffline(shootID: String, entry: RosterEntry, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get the cached shoot
        guard var shoot = loadCachedShoot(id: shootID) else {
            let error = NSError(domain: "OfflineManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Shoot not found in cache"])
            completion(.failure(error))
            return
        }
        
        // Add the entry
        shoot.roster.append(entry)
        
        // Update the shoot
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            let shootData = try encoder.encode(shoot)
            let shootPath = cachesDirectory.appendingPathComponent("\(shootID).json")
            
            try shootData.write(to: shootPath)
            
            // Mark shoot as modified
            markShootAsModified(id: shootID)
            
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    // Delete a roster entry when offline
    func deleteRosterEntryOffline(shootID: String, entryID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get the cached shoot
        guard var shoot = loadCachedShoot(id: shootID) else {
            let error = NSError(domain: "OfflineManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Shoot not found in cache"])
            completion(.failure(error))
            return
        }
        
        // Remove the entry
        shoot.roster.removeAll(where: { $0.id == entryID })
        
        // Update the shoot
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            let shootData = try encoder.encode(shoot)
            let shootPath = cachesDirectory.appendingPathComponent("\(shootID).json")
            
            try shootData.write(to: shootPath)
            
            // Mark shoot as modified
            markShootAsModified(id: shootID)
            
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    // Similar functions for group images
    func updateGroupImageOffline(shootID: String, group: GroupImage, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get the cached shoot
        guard var shoot = loadCachedShoot(id: shootID) else {
            let error = NSError(domain: "OfflineManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Shoot not found in cache"])
            completion(.failure(error))
            return
        }
        
        // Find the index of the group to update
        if let index = shoot.groupImages.firstIndex(where: { $0.id == group.id }) {
            // Update the group
            shoot.groupImages[index] = group
        } else {
            // Add the group if it doesn't exist
            shoot.groupImages.append(group)
        }
        
        // Update the shoot
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            let shootData = try encoder.encode(shoot)
            let shootPath = cachesDirectory.appendingPathComponent("\(shootID).json")
            
            try shootData.write(to: shootPath)
            
            // Mark shoot as modified
            markShootAsModified(id: shootID)
            
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    func addGroupImageOffline(shootID: String, group: GroupImage, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get the cached shoot
        guard var shoot = loadCachedShoot(id: shootID) else {
            let error = NSError(domain: "OfflineManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Shoot not found in cache"])
            completion(.failure(error))
            return
        }
        
        // Add the group
        shoot.groupImages.append(group)
        
        // Update the shoot
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            let shootData = try encoder.encode(shoot)
            let shootPath = cachesDirectory.appendingPathComponent("\(shootID).json")
            
            try shootData.write(to: shootPath)
            
            // Mark shoot as modified
            markShootAsModified(id: shootID)
            
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    func deleteGroupImageOffline(shootID: String, groupID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get the cached shoot
        guard var shoot = loadCachedShoot(id: shootID) else {
            let error = NSError(domain: "OfflineManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Shoot not found in cache"])
            completion(.failure(error))
            return
        }
        
        // Remove the group
        shoot.groupImages.removeAll(where: { $0.id == groupID })
        
        // Update the shoot
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            let shootData = try encoder.encode(shoot)
            let shootPath = cachesDirectory.appendingPathComponent("\(shootID).json")
            
            try shootData.write(to: shootPath)
            
            // Mark shoot as modified
            markShootAsModified(id: shootID)
            
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Synchronization
    
    // Sync all modified shoots when back online
    func syncModifiedShoots() {
        guard isOnline else { return }
        
        for (shootID, _) in modifiedShoots {
            syncShoot(shootID: shootID)
        }
    }
    
    // Sync a specific shoot
    func syncShoot(shootID: String) {
        // Load the cached shoot
        guard let localShoot = loadCachedShoot(id: shootID) else {
            // If shoot doesn't exist in cache, remove from modified list
            modifiedShoots.removeValue(forKey: shootID)
            saveModifiedShootsList()
            return
        }
        
        // Fetch the remote shoot
        db.collection("sportsJobs").document(shootID).getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error fetching remote shoot: \(error.localizedDescription)")
                // Will retry on next sync attempt
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists else {
                // Remote shoot doesn't exist, push local version
                self.pushShootToServer(localShoot)
                return
            }
            
            // Remote shoot exists, check for conflicts
            guard let remoteShoot = SportsShoot(from: snapshot) else {
                print("Error parsing remote shoot")
                return
            }
            
            self.handleShootConflicts(localShoot: localShoot, remoteShoot: remoteShoot)
        }
    }
    
    // Push a shoot to the server
    private func pushShootToServer(_ shoot: SportsShoot) {
        let docRef = db.collection("sportsJobs").document(shoot.id)
        
        // Convert roster entries to dictionaries
        let rosterDicts = shoot.roster.map { $0.toDictionary() }
        
        // Convert group images to dictionaries
        let groupDicts = shoot.groupImages.map { $0.toDictionary() }
        
        // Create document data
        var docData: [String: Any] = [
            "schoolName": shoot.schoolName,
            "sportName": shoot.sportName,
            "shootDate": Timestamp(date: shoot.shootDate),
            "location": shoot.location,
            "photographer": shoot.photographer,
            "roster": rosterDicts,
            "groupImages": groupDicts,
            "additionalNotes": shoot.additionalNotes,
            "organizationID": shoot.organizationID,
            "updatedAt": Timestamp(date: Date())
        ]
        
        // Set created date if it's a new document
        if shoot.createdAt != Date(timeIntervalSince1970: 0) {
            docData["createdAt"] = Timestamp(date: shoot.createdAt)
        } else {
            docData["createdAt"] = Timestamp(date: Date())
        }
        
        // Set or update the document
        docRef.setData(docData) { [weak self] error in
            if let error = error {
                print("Error pushing shoot to server: \(error.localizedDescription)")
                return
            }
            
            // Sync successful, remove from modified list
            self?.modifiedShoots.removeValue(forKey: shoot.id)
            self?.saveModifiedShootsList()
        }
    }
    
    // Handle conflicts between local and remote shoots
    private func handleShootConflicts(localShoot: SportsShoot, remoteShoot: SportsShoot) {
        // Create lists of conflicts
        var entryConflicts: [EntryConflict] = []
        var groupConflicts: [GroupConflict] = []
        
        // Check for entry conflicts
        for localEntry in localShoot.roster {
            if let remoteEntry = remoteShoot.roster.first(where: { $0.id == localEntry.id }),
               entryHasConflict(localEntry: localEntry, remoteEntry: remoteEntry) {
                entryConflicts.append(EntryConflict(localEntry: localEntry, remoteEntry: remoteEntry))
            }
        }
        
        // Check for group conflicts
        for localGroup in localShoot.groupImages {
            if let remoteGroup = remoteShoot.groupImages.first(where: { $0.id == localGroup.id }),
               groupHasConflict(localGroup: localGroup, remoteGroup: remoteGroup) {
                groupConflicts.append(GroupConflict(localGroup: localGroup, remoteGroup: remoteGroup))
            }
        }
        
        // If there are conflicts, notify the user
        if !entryConflicts.isEmpty || !groupConflicts.isEmpty {
            NotificationCenter.default.post(
                name: NSNotification.Name("SyncConflictsDetected"),
                object: nil,
                userInfo: [
                    "shootID": localShoot.id,
                    "entryConflicts": entryConflicts,
                    "groupConflicts": groupConflicts,
                    "localShoot": localShoot,
                    "remoteShoot": remoteShoot
                ]
            )
        } else {
            // No conflicts, merge and push
            let mergedShoot = mergeShootsWithoutConflicts(localShoot: localShoot, remoteShoot: remoteShoot)
            pushShootToServer(mergedShoot)
        }
    }
    
    // Check if an entry has a conflict
    private func entryHasConflict(localEntry: RosterEntry, remoteEntry: RosterEntry) -> Bool {
        // Check for specific fields that might conflict - focus on image numbers
        return localEntry.imageNumbers != remoteEntry.imageNumbers &&
               !localEntry.imageNumbers.isEmpty &&
               !remoteEntry.imageNumbers.isEmpty
    }
    
    // Check if a group has a conflict
    private func groupHasConflict(localGroup: GroupImage, remoteGroup: GroupImage) -> Bool {
        // Check for specific fields that might conflict - focus on image numbers
        return localGroup.imageNumbers != remoteGroup.imageNumbers &&
               !localGroup.imageNumbers.isEmpty &&
               !remoteGroup.imageNumbers.isEmpty
    }
    
    // Merge shoots without conflicts
    private func mergeShootsWithoutConflicts(localShoot: SportsShoot, remoteShoot: SportsShoot) -> SportsShoot {
        var mergedShoot = remoteShoot
        
        // For roster entries
        for localEntry in localShoot.roster {
            // If entry exists in remote, update if local is newer or has additional info
            if let remoteIndex = remoteShoot.roster.firstIndex(where: { $0.id == localEntry.id }) {
                let remoteEntry = remoteShoot.roster[remoteIndex]
                
                // If local entry has image numbers and remote doesn't, use local
                if !localEntry.imageNumbers.isEmpty && remoteEntry.imageNumbers.isEmpty {
                    mergedShoot.roster[remoteIndex] = localEntry
                }
                // If fields have been updated in both, prefer local for now (since local changes are newest)
                else if !entryHasConflict(localEntry: localEntry, remoteEntry: remoteEntry) {
                    mergedShoot.roster[remoteIndex] = localEntry
                }
            } else {
                // Entry doesn't exist in remote, add it
                mergedShoot.roster.append(localEntry)
            }
        }
        
        // For group images
        for localGroup in localShoot.groupImages {
            // If group exists in remote, update if local is newer or has additional info
            if let remoteIndex = remoteShoot.groupImages.firstIndex(where: { $0.id == localGroup.id }) {
                let remoteGroup = remoteShoot.groupImages[remoteIndex]
                
                // If local group has image numbers and remote doesn't, use local
                if !localGroup.imageNumbers.isEmpty && remoteGroup.imageNumbers.isEmpty {
                    mergedShoot.groupImages[remoteIndex] = localGroup
                }
                // If fields have been updated in both, prefer local for now (since local changes are newest)
                else if !groupHasConflict(localGroup: localGroup, remoteGroup: remoteGroup) {
                    mergedShoot.groupImages[remoteIndex] = localGroup
                }
            } else {
                // Group doesn't exist in remote, add it
                mergedShoot.groupImages.append(localGroup)
            }
        }
        
        return mergedShoot
    }
    
    // Resolve conflicts by choosing either local or remote version
    func resolveConflicts(shootID: String, useLocalEntries: [String], useRemoteEntries: [String], useLocalGroups: [String], useRemoteGroups: [String], completion: @escaping (Bool) -> Void) {
        // Load both local and remote shoots
        guard let localShoot = loadCachedShoot(id: shootID) else {
            completion(false)
            return
        }
        
        // Fetch the remote shoot
        db.collection("sportsJobs").document(shootID).getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error fetching remote shoot: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists,
                  let remoteShoot = SportsShoot(from: snapshot) else {
                print("Error parsing remote shoot")
                completion(false)
                return
            }
            
            // Create a new merged shoot
            var mergedShoot = remoteShoot
            
            // Merge roster entries based on conflict resolution choices
            for entry in localShoot.roster {
                if let index = mergedShoot.roster.firstIndex(where: { $0.id == entry.id }) {
                    // Entry exists in both - check if it has a conflict and which version to use
                    if useLocalEntries.contains(entry.id) {
                        // Use local version
                        mergedShoot.roster[index] = entry
                    }
                    // Otherwise keep remote version which is already in mergedShoot
                } else {
                    // Entry only exists locally, always add it
                    mergedShoot.roster.append(entry)
                }
            }
            
            // Merge group images based on conflict resolution choices
            for group in localShoot.groupImages {
                if let index = mergedShoot.groupImages.firstIndex(where: { $0.id == group.id }) {
                    // Group exists in both - check if it has a conflict and which version to use
                    if useLocalGroups.contains(group.id) {
                        // Use local version
                        mergedShoot.groupImages[index] = group
                    }
                    // Otherwise keep remote version which is already in mergedShoot
                } else {
                    // Group only exists locally, always add it
                    mergedShoot.groupImages.append(group)
                }
            }
            
            // Push the merged shoot to the server
            self.pushShootToServer(mergedShoot)
            
            // Also update the cached version
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                
                let shootData = try encoder.encode(mergedShoot)
                let shootPath = self.cachesDirectory.appendingPathComponent("\(shootID).json")
                
                try shootData.write(to: shootPath)
                
                // Remove from modified list since we've synced
                self.modifiedShoots.removeValue(forKey: shootID)
                self.saveModifiedShootsList()
                
                completion(true)
            } catch {
                print("Error updating cached shoot: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
}
