//
//  SportsShootRepositoryProtocol.swift
//  Iconik Employee
//
//  Created by administrator on 5/19/25.
//


import Foundation
import Firebase
import FirebaseFirestore
import Combine

/// Repository Protocol defining the interface for sports shoot data access
protocol SportsShootRepositoryProtocol {
    // MARK: - Sports Shoot Access
    func fetchSportsShoot(id: String) -> AnyPublisher<SportsShoot, Error>
    func fetchAllSportsShoots(forOrganization orgID: String) -> AnyPublisher<[SportsShoot], Error>
    
    // MARK: - Roster Entry Operations
    func addRosterEntry(shootID: String, entry: RosterEntry) -> AnyPublisher<Void, Error>
    func updateRosterEntry(shootID: String, entry: RosterEntry) -> AnyPublisher<Void, Error>
    func deleteRosterEntry(shootID: String, entryID: String) -> AnyPublisher<Void, Error>
    
    // MARK: - Group Image Operations
    func addGroupImage(shootID: String, groupImage: GroupImage) -> AnyPublisher<Void, Error>
    func updateGroupImage(shootID: String, groupImage: GroupImage) -> AnyPublisher<Void, Error>
    func deleteGroupImage(shootID: String, groupID: String) -> AnyPublisher<Void, Error>
    
    // MARK: - CSV Import/Export
    func importRosterFromCSV(csvString: String) -> [RosterEntry]
    func exportRosterToCSV(roster: [RosterEntry]) -> String
    
    // MARK: - Offline Support
    func cacheShootForOffline(id: String) -> AnyPublisher<Bool, Error>
    func syncStatus(for shootID: String) -> AnyPublisher<CacheStatus, Never>
    func syncModifiedShoots() -> AnyPublisher<Void, Never>
    func isDeviceOnline() -> Bool
    
    // MARK: - Lock Management
    func acquireLock(shootID: String, entryID: String, editorID: String, editorName: String) -> AnyPublisher<Bool, Error>
    func releaseLock(shootID: String, entryID: String, editorID: String) -> AnyPublisher<Bool, Error>
    func observeLocks(shootID: String) -> AnyPublisher<[String: String], Never>
}

/// Enum representing cache status of a sports shoot
enum CacheStatus {
    case notCached
    case cached
    case modified
    case syncing
    case error
}

/// Repository implementation that manages sports shoot data access from both online and offline sources
class SportsShootRepository: SportsShootRepositoryProtocol {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore()
    private let sportsShootsCollection = "sportsJobs"
    private var cancellables = Set<AnyCancellable>()
    
    // Network connectivity
    private let networkMonitor = ConnectivityMonitor.shared
    private var isOnline = true
    
    // Offline manager
    private let offlineManager: OfflineManagerProtocol
    
    // Lock manager
    private let lockManager: LockManagerProtocol
    
    // Central event bus
    private let eventBus: EventBus
    
    // MARK: - Initialization
    
    init(offlineManager: OfflineManagerProtocol = OfflineManager.shared, 
         lockManager: LockManagerProtocol = LockManager.shared,
         eventBus: EventBus = EventBus.shared) {
        self.offlineManager = offlineManager
        self.lockManager = lockManager
        self.eventBus = eventBus
        
        // Monitor network status
        setupNetworkMonitoring()
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor.connectivityPublisher
            .sink { [weak self] isConnected in
                guard let self = self else { return }
                self.isOnline = isConnected
                
                // Trigger sync when we come back online
                if isConnected {
                    self.syncModifiedShoots()
                        .sink(receiveValue: { _ in })
                        .store(in: &self.cancellables)
                }
                
                // Publish network status event
                self.eventBus.publish(.networkStatusChanged(isOnline: isConnected))
            }
            .store(in: &cancellables)
        
        // Initialize with current status
        isOnline = networkMonitor.isConnected
    }
    
    // MARK: - Sports Shoot Access
    
    func fetchSportsShoot(id: String) -> AnyPublisher<SportsShoot, Error> {
        // If we're offline, try to fetch from cache
        if !isOnline {
            return offlineManager.loadCachedShoot(id: id)
                .map { cachedShoot -> AnyPublisher<SportsShoot, Error> in
                    if let cachedShoot = cachedShoot {
                        return Just(cachedShoot)
                            .setFailureType(to: Error.self)
                            .eraseToAnyPublisher()
                    } else {
                        return Fail(error: RepositoryError.notCachedOffline)
                            .eraseToAnyPublisher()
                    }
                }
                .switchToLatest()
                .eraseToAnyPublisher()
        }
        
        // We're online, fetch from Firestore
        return Future<SportsShoot, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(RepositoryError.repositoryDeallocated))
                return
            }
            
            self.db.collection(self.sportsShootsCollection).document(id).getDocument { snapshot, error in
                if let error = error {
                    // Try to load from cache as fallback
                    if let cachedShoot = try? self.offlineManager.loadCachedShoot(id: id).value {
                        promise(.success(cachedShoot))
                    } else {
                        promise(.failure(error))
                    }
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists else {
                    promise(.failure(RepositoryError.documentNotFound))
                    return
                }
                
                if let sportsShoot = SportsShoot(from: snapshot) {
                    // Cache the shoot for offline use
                    self.offlineManager.cacheShoot(sportsShoot)
                        .sink(receiveCompletion: { _ in }, 
                              receiveValue: { _ in })
                        .store(in: &self.cancellables)
                    
                    promise(.success(sportsShoot))
                } else {
                    promise(.failure(RepositoryError.parsingError))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func fetchAllSportsShoots(forOrganization orgID: String) -> AnyPublisher<[SportsShoot], Error> {
        guard !orgID.isEmpty else {
            return Fail(error: RepositoryError.invalidParameter("Organization ID is required"))
                .eraseToAnyPublisher()
        }
        
        // If we're offline, try to load cached shoots
        if !isOnline {
            return offlineManager.loadAllCachedShoots(forOrganization: orgID)
                .eraseToAnyPublisher()
        }
        
        // We're online, fetch from Firestore
        return Future<[SportsShoot], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(RepositoryError.repositoryDeallocated))
                return
            }
            
            self.db.collection(self.sportsShootsCollection)
                .whereField("organizationID", isEqualTo: orgID)
                .order(by: "shootDate", descending: true)
                .getDocuments { snapshot, error in
                    if let error = error {
                        // Try to load from cache as fallback
                        self.offlineManager.loadAllCachedShoots(forOrganization: orgID)
                            .sink(
                                receiveCompletion: { completion in
                                    if case .failure = completion {
                                        promise(.failure(error))
                                    }
                                },
                                receiveValue: { shoots in
                                    promise(.success(shoots))
                                }
                            )
                            .store(in: &self.cancellables)
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        promise(.success([]))
                        return
                    }
                    
                    var sportsShoots: [SportsShoot] = []
                    
                    for document in documents {
                        if let sportsShoot = SportsShoot(from: document) {
                            sportsShoots.append(sportsShoot)
                            
                            // Cache each shoot in the background
                            self.offlineManager.cacheShoot(sportsShoot)
                                .sink(receiveCompletion: { _ in }, 
                                      receiveValue: { _ in })
                                .store(in: &self.cancellables)
                        }
                    }
                    
                    promise(.success(sportsShoots))
                }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Roster Entry Operations
    
    func addRosterEntry(shootID: String, entry: RosterEntry) -> AnyPublisher<Void, Error> {
        // If we're offline, update locally
        if !isOnline {
            return offlineManager.addRosterEntryOffline(shootID: shootID, entry: entry)
                .handleEvents(receiveOutput: { [weak self] _ in
                    // Notify about the change
                    self?.eventBus.publish(.rosterEntryUpdated(shootID: shootID, entryID: entry.id))
                })
                .eraseToAnyPublisher()
        }
        
        // We're online, update in Firestore
        return Future<Void, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(RepositoryError.repositoryDeallocated))
                return
            }
            
            let docRef = self.db.collection(self.sportsShootsCollection).document(shootID)
            let entryDict = entry.toDictionary()
            
            // Optimistic update - update local cache first
            self.fetchSportsShoot(id: shootID)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self] shoot in
                        guard let self = self else { return }
                        
                        var updatedShoot = shoot
                        updatedShoot.roster.append(entry)
                        
                        // Update cache optimistically
                        self.offlineManager.cacheShoot(updatedShoot)
                            .sink(receiveCompletion: { _ in }, 
                                  receiveValue: { _ in })
                            .store(in: &self.cancellables)
                        
                        // Notify UI that data is updated (optimistically)
                        self.eventBus.publish(.rosterEntryUpdated(shootID: shootID, entryID: entry.id))
                    }
                )
                .store(in: &self.cancellables)
            
            // Update Firestore
            docRef.updateData([
                "roster": FieldValue.arrayUnion([entryDict]),
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    // Update failed, revert optimistic update
                    self.fetchSportsShoot(id: shootID)
                        .sink(
                            receiveCompletion: { _ in },
                            receiveValue: { originalShoot in
                                // Re-cache the original state
                                self.offlineManager.cacheShoot(originalShoot)
                                    .sink(receiveCompletion: { _ in }, 
                                          receiveValue: { _ in })
                                    .store(in: &self.cancellables)
                                
                                // Notify UI of the revert
                                self.eventBus.publish(.rosterEntryUpdateFailed(shootID: shootID, entryID: entry.id))
                            }
                        )
                        .store(in: &self.cancellables)
                    
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func updateRosterEntry(shootID: String, entry: RosterEntry) -> AnyPublisher<Void, Error> {
        // If we're offline, update locally
        if !isOnline {
            return offlineManager.updateRosterEntryOffline(shootID: shootID, entry: entry)
                .handleEvents(receiveOutput: { [weak self] _ in
                    // Notify about the change
                    self?.eventBus.publish(.rosterEntryUpdated(shootID: shootID, entryID: entry.id))
                })
                .eraseToAnyPublisher()
        }
        
        // We're online, update in Firestore
        return Future<Void, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(RepositoryError.repositoryDeallocated))
                return
            }
            
            // Optimistic update - update local cache first
            self.fetchSportsShoot(id: shootID)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self] shoot in
                        guard let self = self else { return }
                        
                        var updatedShoot = shoot
                        if let index = updatedShoot.roster.firstIndex(where: { $0.id == entry.id }) {
                            updatedShoot.roster[index] = entry
                        } else {
                            updatedShoot.roster.append(entry)
                        }
                        
                        // Update cache optimistically
                        self.offlineManager.cacheShoot(updatedShoot)
                            .sink(receiveCompletion: { _ in }, 
                                  receiveValue: { _ in })
                            .store(in: &self.cancellables)
                        
                        // Notify UI that data is updated (optimistically)
                        self.eventBus.publish(.rosterEntryUpdated(shootID: shootID, entryID: entry.id))
                    }
                )
                .store(in: &self.cancellables)
            
            let docRef = self.db.collection(self.sportsShootsCollection).document(shootID)
            
            // Get the current document to remove old entry
            docRef.getDocument { snapshot, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists else {
                    promise(.failure(RepositoryError.documentNotFound))
                    return
                }
                
                // Find the index of the existing entry to replace
                if let rosterData = snapshot.data()?["roster"] as? [[String: Any]],
                   let index = rosterData.firstIndex(where: { ($0["id"] as? String) == entry.id }) {
                    
                    // Store the existing entry to remove
                    let existingEntry = rosterData[index]
                    
                    // Remove the existing entry
                    docRef.updateData([
                        "roster": FieldValue.arrayRemove([existingEntry]),
                    ]) { error in
                        if let error = error {
                            promise(.failure(error))
                            return
                        }
                        
                        // Add the updated entry
                        let entryDict = entry.toDictionary()
                        
                        docRef.updateData([
                            "roster": FieldValue.arrayUnion([entryDict]),
                            "updatedAt": FieldValue.serverTimestamp()
                        ]) { error in
                            if let error = error {
                                // Update failed, revert optimistic update
                                self.fetchSportsShoot(id: shootID)
                                    .sink(
                                        receiveCompletion: { _ in },
                                        receiveValue: { originalShoot in
                                            // Re-cache the original state
                                            self.offlineManager.cacheShoot(originalShoot)
                                                .sink(receiveCompletion: { _ in }, 
                                                      receiveValue: { _ in })
                                                .store(in: &self.cancellables)
                                            
                                            // Notify UI of the revert
                                            self.eventBus.publish(.rosterEntryUpdateFailed(shootID: shootID, entryID: entry.id))
                                        }
                                    )
                                    .store(in: &self.cancellables)
                                
                                promise(.failure(error))
                            } else {
                                promise(.success(()))
                            }
                        }
                    }
                } else {
                    // If entry doesn't exist yet, just add it
                    self.addRosterEntry(shootID: shootID, entry: entry)
                        .sink(
                            receiveCompletion: { completion in
                                if case let .failure(error) = completion {
                                    promise(.failure(error))
                                }
                            },
                            receiveValue: { _ in
                                promise(.success(()))
                            }
                        )
                        .store(in: &self.cancellables)
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func deleteRosterEntry(shootID: String, entryID: String) -> AnyPublisher<Void, Error> {
        // If we're offline, update locally
        if !isOnline {
            return offlineManager.deleteRosterEntryOffline(shootID: shootID, entryID: entryID)
                .handleEvents(receiveOutput: { [weak self] _ in
                    // Notify about the change
                    self?.eventBus.publish(.rosterEntryDeleted(shootID: shootID, entryID: entryID))
                })
                .eraseToAnyPublisher()
        }
        
        // We're online, delete from Firestore
        return Future<Void, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(RepositoryError.repositoryDeallocated))
                return
            }
            
            // Optimistic update - update local cache first
            self.fetchSportsShoot(id: shootID)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self] shoot in
                        guard let self = self else { return }
                        
                        // Store original shoot for potential revert
                        let originalShoot = shoot
                        
                        // Create optimistically updated version
                        var updatedShoot = shoot
                        guard let entryToRemove = updatedShoot.roster.first(where: { $0.id == entryID }) else {
                            promise(.failure(RepositoryError.entryNotFound))
                            return
                        }
                        
                        // Remove entry from local roster
                        updatedShoot.roster.removeAll(where: { $0.id == entryID })
                        
                        // Update cache optimistically
                        self.offlineManager.cacheShoot(updatedShoot)
                            .sink(receiveCompletion: { _ in }, 
                                  receiveValue: { _ in })
                            .store(in: &self.cancellables)
                        
                        // Notify UI that data is updated (optimistically)
                        self.eventBus.publish(.rosterEntryDeleted(shootID: shootID, entryID: entryID))
                        
                        // Convert to dictionary for Firestore
                        let entryDict = entryToRemove.toDictionary()
                        let docRef = self.db.collection(self.sportsShootsCollection).document(shootID)
                        
                        docRef.updateData([
                            "roster": FieldValue.arrayRemove([entryDict]),
                            "updatedAt": FieldValue.serverTimestamp()
                        ]) { error in
                            if let error = error {
                                // Update failed, revert optimistic update
                                self.offlineManager.cacheShoot(originalShoot)
                                    .sink(receiveCompletion: { _ in }, 
                                          receiveValue: { _ in })
                                    .store(in: &self.cancellables)
                                
                                // Notify UI of the revert
                                self.eventBus.publish(.rosterEntryUpdateFailed(shootID: shootID, entryID: entryID))
                                
                                promise(.failure(error))
                            } else {
                                promise(.success(()))
                            }
                        }
                    }
                )
                .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Group Image Operations
    
    func addGroupImage(shootID: String, groupImage: GroupImage) -> AnyPublisher<Void, Error> {
        // If we're offline, update locally
        if !isOnline {
            return offlineManager.addGroupImageOffline(shootID: shootID, group: groupImage)
                .handleEvents(receiveOutput: { [weak self] _ in
                    // Notify about the change
                    self?.eventBus.publish(.groupImageUpdated(shootID: shootID, groupID: groupImage.id))
                })
                .eraseToAnyPublisher()
        }
        
        // We're online, update in Firestore
        return Future<Void, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(RepositoryError.repositoryDeallocated))
                return
            }
            
            let docRef = self.db.collection(self.sportsShootsCollection).document(shootID)
            let groupDict = groupImage.toDictionary()
            
            // Optimistic update - update local cache first
            self.fetchSportsShoot(id: shootID)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self] shoot in
                        guard let self = self else { return }
                        
                        var updatedShoot = shoot
                        updatedShoot.groupImages.append(groupImage)
                        
                        // Update cache optimistically
                        self.offlineManager.cacheShoot(updatedShoot)
                            .sink(receiveCompletion: { _ in }, 
                                  receiveValue: { _ in })
                            .store(in: &self.cancellables)
                        
                        // Notify UI that data is updated (optimistically)
                        self.eventBus.publish(.groupImageUpdated(shootID: shootID, groupID: groupImage.id))
                    }
                )
                .store(in: &self.cancellables)
            
            // Update Firestore
            docRef.updateData([
                "groupImages": FieldValue.arrayUnion([groupDict]),
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    // Update failed, revert optimistic update
                    self.fetchSportsShoot(id: shootID)
                        .sink(
                            receiveCompletion: { _ in },
                            receiveValue: { originalShoot in
                                // Re-cache the original state
                                self.offlineManager.cacheShoot(originalShoot)
                                    .sink(receiveCompletion: { _ in }, 
                                          receiveValue: { _ in })
                                    .store(in: &self.cancellables)
                                
                                // Notify UI of the revert
                                self.eventBus.publish(.groupImageUpdateFailed(shootID: shootID, groupID: groupImage.id))
                            }
                        )
                        .store(in: &self.cancellables)
                    
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func updateGroupImage(shootID: String, groupImage: GroupImage) -> AnyPublisher<Void, Error> {
        // If we're offline, update locally
        if !isOnline {
            return offlineManager.updateGroupImageOffline(shootID: shootID, group: groupImage)
                .handleEvents(receiveOutput: { [weak self] _ in
                    // Notify about the change
                    self?.eventBus.publish(.groupImageUpdated(shootID: shootID, groupID: groupImage.id))
                })
                .eraseToAnyPublisher()
        }
        
        // We're online, update in Firestore
        return Future<Void, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(RepositoryError.repositoryDeallocated))
                return
            }
            
            // Optimistic update - update local cache first
            self.fetchSportsShoot(id: shootID)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self] shoot in
                        guard let self = self else { return }
                        
                        var updatedShoot = shoot
                        if let index = updatedShoot.groupImages.firstIndex(where: { $0.id == groupImage.id }) {
                            updatedShoot.groupImages[index] = groupImage
                        } else {
                            updatedShoot.groupImages.append(groupImage)
                        }
                        
                        // Update cache optimistically
                        self.offlineManager.cacheShoot(updatedShoot)
                            .sink(receiveCompletion: { _ in }, 
                                  receiveValue: { _ in })
                            .store(in: &self.cancellables)
                        
                        // Notify UI that data is updated (optimistically)
                        self.eventBus.publish(.groupImageUpdated(shootID: shootID, groupID: groupImage.id))
                    }
                )
                .store(in: &self.cancellables)
            
            let docRef = self.db.collection(self.sportsShootsCollection).document(shootID)
            
            // Get the current document to remove old group
            docRef.getDocument { snapshot, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists else {
                    promise(.failure(RepositoryError.documentNotFound))
                    return
                }
                
                // Find the index of the existing group to replace
                if let groupData = snapshot.data()?["groupImages"] as? [[String: Any]],
                   let index = groupData.firstIndex(where: { ($0["id"] as? String) == groupImage.id }) {
                    
                    // Store the existing group to remove
                    let existingGroup = groupData[index]
                    
                    // Remove the existing group
                    docRef.updateData([
                        "groupImages": FieldValue.arrayRemove([existingGroup]),
                    ]) { error in
                        if let error = error {
                            promise(.failure(error))
                            return
                        }
                        
                        // Add the updated group
                        let groupDict = groupImage.toDictionary()
                        
                        docRef.updateData([
                            "groupImages": FieldValue.arrayUnion([groupDict]),
                            "updatedAt": FieldValue.serverTimestamp()
                        ]) { error in
                            if let error = error {
                                // Update failed, revert optimistic update
                                self.fetchSportsShoot(id: shootID)
                                    .sink(
                                        receiveCompletion: { _ in },
                                        receiveValue: { originalShoot in
                                            // Re-cache the original state
                                            self.offlineManager.cacheShoot(originalShoot)
                                                .sink(receiveCompletion: { _ in }, 
                                                      receiveValue: { _ in })
                                                .store(in: &self.cancellables)
                                            
                                            // Notify UI of the revert
                                            self.eventBus.publish(.groupImageUpdateFailed(shootID: shootID, groupID: groupImage.id))
                                        }
                                    )
                                    .store(in: &self.cancellables)
                                
                                promise(.failure(error))
                            } else {
                                promise(.success(()))
                            }
                        }
                    }
                } else {
                    // If group doesn't exist yet, just add it
                    self.addGroupImage(shootID: shootID, groupImage: groupImage)
                        .sink(
                            receiveCompletion: { completion in
                                if case let .failure(error) = completion {
                                    promise(.failure(error))
                                }
                            },
                            receiveValue: { _ in
                                promise(.success(()))
                            }
                        )
                        .store(in: &self.cancellables)
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func deleteGroupImage(shootID: String, groupID: String) -> AnyPublisher<Void, Error> {
        // If we're offline, update locally
        if !isOnline {
            return offlineManager.deleteGroupImageOffline(shootID: shootID, groupID: groupID)
                .handleEvents(receiveOutput: { [weak self] _ in
                    // Notify about the change
                    self?.eventBus.publish(.groupImageDeleted(shootID: shootID, groupID: groupID))
                })
                .eraseToAnyPublisher()
        }
        
        // We're online, delete from Firestore
        return Future<Void, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(RepositoryError.repositoryDeallocated))
                return
            }
            
            // Optimistic update - update local cache first
            self.fetchSportsShoot(id: shootID)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self] shoot in
                        guard let self = self else { return }
                        
                        // Store original shoot for potential revert
                        let originalShoot = shoot
                        
                        // Create optimistically updated version
                        var updatedShoot = shoot
                        guard let groupToRemove = updatedShoot.groupImages.first(where: { $0.id == groupID }) else {
                            promise(.failure(RepositoryError.groupNotFound))
                            return
                        }
                        
                        // Remove group from local groupImages
                        updatedShoot.groupImages.removeAll(where: { $0.id == groupID })
                        
                        // Update cache optimistically
                        self.offlineManager.cacheShoot(updatedShoot)
                            .sink(receiveCompletion: { _ in }, 
                                  receiveValue: { _ in })
                            .store(in: &self.cancellables)
                        
                        // Notify UI that data is updated (optimistically)
                        self.eventBus.publish(.groupImageDeleted(shootID: shootID, groupID: groupID))
                        
                        // Convert to dictionary for Firestore
                        let groupDict = groupToRemove.toDictionary()
                        let docRef = self.db.collection(self.sportsShootsCollection).document(shootID)
                        
                        docRef.updateData([
                            "groupImages": FieldValue.arrayRemove([groupDict]),
                            "updatedAt": FieldValue.serverTimestamp()
                        ]) { error in
                            if let error = error {
                                // Update failed, revert optimistic update
                                self.offlineManager.cacheShoot(originalShoot)
                                    .sink(receiveCompletion: { _ in }, 
                                          receiveValue: { _ in })
                                    .store(in: &self.cancellables)
                                
                                // Notify UI of the revert
                                self.eventBus.publish(.groupImageUpdateFailed(shootID: shootID, groupID: groupID))
                                
                                promise(.failure(error))
                            } else {
                                promise(.success(()))
                            }
                        }
                    }
                )
                .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Offline Support
    
    func cacheShootForOffline(id: String) -> AnyPublisher<Bool, Error> {
        return fetchSportsShoot(id: id)
            .flatMap { [weak self] shoot -> AnyPublisher<Bool, Error> in
                guard let self = self else {
                    return Fail(error: RepositoryError.repositoryDeallocated)
                        .eraseToAnyPublisher()
                }
                
                return self.offlineManager.cacheShoot(shoot)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    func syncStatus(for shootID: String) -> AnyPublisher<CacheStatus, Never> {
        return offlineManager.cacheStatusForShoot(id: shootID)
            .eraseToAnyPublisher()
    }
    
    func syncModifiedShoots() -> AnyPublisher<Void, Never> {
        return offlineManager.syncModifiedShoots()
            .eraseToAnyPublisher()
    }
    
    func isDeviceOnline() -> Bool {
        return isOnline
    }
    
    // MARK: - Lock Management
    
    func acquireLock(shootID: String, entryID: String, editorID: String, editorName: String) -> AnyPublisher<Bool, Error> {
        return lockManager.acquireLock(shootID: shootID, entryID: entryID, editorID: editorID, editorName: editorName)
            .eraseToAnyPublisher()
    }
    
    func releaseLock(shootID: String, entryID: String, editorID: String) -> AnyPublisher<Bool, Error> {
        return lockManager.releaseLock(shootID: shootID, entryID: entryID, editorID: editorID)
            .eraseToAnyPublisher()
    }
    
    func observeLocks(shootID: String) -> AnyPublisher<[String: String], Never> {
        return lockManager.observeLocks(shootID: shootID)
            .eraseToAnyPublisher()
    }
}

/// Repository errors
enum RepositoryError: Error, LocalizedError {
    case repositoryDeallocated
    case documentNotFound
    case parsingError
    case notCachedOffline
    case invalidParameter(String)
    case entryNotFound
    case groupNotFound
    
    var errorDescription: String? {
        switch self {
        case .repositoryDeallocated:
            return "Internal error: repository was deallocated"
        case .documentNotFound:
            return "The requested document was not found"
        case .parsingError:
            return "Failed to parse document data"
        case .notCachedOffline:
            return "Document is not available offline"
        case .invalidParameter(let param):
            return "Invalid parameter: \(param)"
        case .entryNotFound:
            return "The requested roster entry was not found"
        case .groupNotFound:
            return "The requested group image was not found"
        }
    }
}