//
//  LockManagerProtocol.swift
//  Iconik Employee
//
//  Created by administrator on 5/19/25.
//


import Foundation
import Firebase
import FirebaseFirestore
import Combine

/// Protocol defining the interface for lock management
protocol LockManagerProtocol {
    func acquireLock(shootID: String, entryID: String, editorID: String, editorName: String) -> AnyPublisher<Bool, Error>
    func releaseLock(shootID: String, entryID: String, editorID: String) -> AnyPublisher<Bool, Error>
    func observeLocks(shootID: String) -> AnyPublisher<[String: String], Never>
    func cleanupStaleLocks(shootID: String, timeThreshold: TimeInterval) -> AnyPublisher<Void, Error>
}

/// Manager class for handling entry locks
class LockManager: LockManagerProtocol {
    static let shared = LockManager()
    
    private let db = Firestore.firestore()
    private var isOnline = true
    private var cancellables = Set<AnyCancellable>()
    
    // Dictionary to cache locks locally when offline
    private var localLocks: [String: [String: String]] = [:] // [shootID: [entryID: editorName]]
    
    // Subject for broadcasting lock changes
    private var lockSubjects: [String: CurrentValueSubject<[String: String], Never>] = [:]
    
    // Central event bus
    private let eventBus: EventBus
    
    // Connectivity monitor
    private let connectivityMonitor: ConnectivityMonitor
    
    private init(eventBus: EventBus = EventBus.shared, connectivityMonitor: ConnectivityMonitor = ConnectivityMonitor.shared) {
        self.eventBus = eventBus
        self.connectivityMonitor = connectivityMonitor
        
        // Monitor network status
        setupConnectivityMonitoring()
    }
    
    // MARK: - Network Monitoring
    
    private func setupConnectivityMonitoring() {
        connectivityMonitor.connectivityPublisher
            .sink { [weak self] isConnected in
                guard let self = self else { return }
                
                self.isOnline = isConnected
                
                // If we just came online, clear local locks
                if isConnected {
                    self.clearLocalLocks()
                }
            }
            .store(in: &cancellables)
        
        // Initialize with current status
        isOnline = connectivityMonitor.isConnected
    }
    
    // MARK: - Lock Management
    
    func acquireLock(shootID: String, entryID: String, editorID: String, editorName: String) -> AnyPublisher<Bool, Error> {
        // If we're offline, use local locks
        if !isOnline {
            return Future<Bool, Error> { [weak self] promise in
                guard let self = self else {
                    promise(.failure(NSError(domain: "LockManager", code: 1000, userInfo: [NSLocalizedDescriptionKey: "LockManager has been deallocated"])))
                    return
                }
                
                print("Offline mode: Adding local lock for \(entryID) by \(editorName)")
                self.addLocalLock(shootID: shootID, entryID: entryID, editorName: editorName)
                promise(.success(true))
            }
            .eraseToAnyPublisher()
        }
        
        // We're online, use Firestore locks
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NSError(domain: "LockManager", code: 1000, userInfo: [NSLocalizedDescriptionKey: "LockManager has been deallocated"])))
                return
            }
            
            let lockID = entryID
            
            // First check if a lock already exists for this entry
            self.db.collection("sportsJobs").document(shootID)
                .collection("locks").document(lockID)
                .getDocument { snapshot, error in
                    
                    if let error = error {
                        print("Error checking for existing lock: \(error.localizedDescription)")
                        promise(.failure(error))
                        return
                    }
                    
                    // If lock exists and is not owned by this editor, fail
                    if let snapshot = snapshot, snapshot.exists,
                       let data = snapshot.data(),
                       let existingEditorID = data["editorID"] as? String,
                       existingEditorID != editorID {
                        
                        print("Entry is already locked by another editor")
                        promise(.success(false))
                        return
                    }
                    
                    // No existing conflicting lock, so create or update it
                    let lockData: [String: Any] = [
                        "entryID": entryID,
                        "editorID": editorID,
                        "editorName": editorName,
                        "timestamp": FieldValue.serverTimestamp()
                    ]
                    
                    self.db.collection("sportsJobs").document(shootID)
                        .collection("locks").document(lockID)
                        .setData(lockData) { error in
                            if let error = error {
                                print("Error acquiring lock: \(error.localizedDescription)")
                                promise(.failure(error))
                            } else {
                                print("Lock acquired successfully for \(entryID) by \(editorName)")
                                
                                // Notify event bus about lock acquisition
                                self.eventBus.publish(.lockAcquired(shootID: shootID, entryID: entryID, editorName: editorName))
                                
                                promise(.success(true))
                            }
                        }
                }
        }
        .eraseToAnyPublisher()
    }
    
    func releaseLock(shootID: String, entryID: String, editorID: String) -> AnyPublisher<Bool, Error> {
        // If we're offline, use local locks
        if !isOnline {
            return Future<Bool, Error> { [weak self] promise in
                guard let self = self else {
                    promise(.failure(NSError(domain: "LockManager", code: 1000, userInfo: [NSLocalizedDescriptionKey: "LockManager has been deallocated"])))
                    return
                }
                
                print("Offline mode: Removing local lock for \(entryID)")
                self.removeLocalLock(shootID: shootID, entryID: entryID)
                promise(.success(true))
            }
            .eraseToAnyPublisher()
        }
        
        // We're online, use Firestore locks
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NSError(domain: "LockManager", code: 1000, userInfo: [NSLocalizedDescriptionKey: "LockManager has been deallocated"])))
                return
            }
            
            let lockID = entryID
            
            // First verify that the lock is owned by this editor
            self.db.collection("sportsJobs").document(shootID)
                .collection("locks").document(lockID)
                .getDocument { snapshot, error in
                    
                    if let error = error {
                        print("Error checking lock ownership: \(error.localizedDescription)")
                        promise(.failure(error))
                        return
                    }
                    
                    // Only delete if lock exists and is owned by this editor
                    if let snapshot = snapshot, snapshot.exists,
                       let data = snapshot.data(),
                       let existingEditorID = data["editorID"] as? String,
                       let editorName = data["editorName"] as? String {
                        
                        // If owned by someone else, don't release
                        if existingEditorID != editorID {
                            print("Lock is owned by another editor, cannot release")
                            promise(.success(false))
                            return
                        }
                        
                        // Delete the lock
                        self.db.collection("sportsJobs").document(shootID)
                            .collection("locks").document(lockID)
                            .delete { error in
                                if let error = error {
                                    print("Error releasing lock: \(error.localizedDescription)")
                                    promise(.failure(error))
                                } else {
                                    print("Lock released successfully for \(entryID)")
                                    
                                    // Notify event bus about lock release
                                    self.eventBus.publish(.lockReleased(shootID: shootID, entryID: entryID, editorName: editorName))
                                    
                                    promise(.success(true))
                                }
                            }
                    } else {
                        // Lock doesn't exist, consider it released
                        print("No lock exists to release for \(entryID)")
                        promise(.success(true))
                    }
                }
        }
        .eraseToAnyPublisher()
    }
    
    func observeLocks(shootID: String) -> AnyPublisher<[String: String], Never> {
        // Create a subject for this shoot if it doesn't exist
        if lockSubjects[shootID] == nil {
            lockSubjects[shootID] = CurrentValueSubject<[String: String], Never>([:])
            
            // Setup the actual listener
            if isOnline {
                setupFirestoreLockListener(shootID: shootID)
            } else {
                // If offline, use local locks
                let localLocksForShoot = getLocalLocks(shootID: shootID)
                lockSubjects[shootID]?.send(localLocksForShoot)
            }
        }
        
        return lockSubjects[shootID]!.eraseToAnyPublisher()
    }
    
    func cleanupStaleLocks(shootID: String, timeThreshold: TimeInterval = 300) -> AnyPublisher<Void, Error> {
        // If we're offline, nothing to do
        if !isOnline {
            return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        
        return Future<Void, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(NSError(domain: "LockManager", code: 1000, userInfo: [NSLocalizedDescriptionKey: "LockManager has been deallocated"])))
                return
            }
            
            print("Cleaning up stale locks for shoot: \(shootID)")
            let cutoffDate = Date().addingTimeInterval(-timeThreshold)
            
            self.db.collection("sportsJobs").document(shootID)
                .collection("locks")
                .whereField("timestamp", isLessThan: cutoffDate)
                .getDocuments { snapshot, error in
                    if let error = error {
                        print("Error getting stale locks: \(error.localizedDescription)")
                        promise(.failure(error))
                        return
                    }
                    
                    guard let documents = snapshot?.documents, !documents.isEmpty else {
                        print("No stale locks found")
                        promise(.success(()))
                        return
                    }
                    
                    print("Found \(documents.count) stale locks to clean up")
                    let batch = self.db.batch()
                    
                    for doc in documents {
                        let entryID = doc.data()["entryID"] as? String ?? "unknown"
                        let editorName = doc.data()["editorName"] as? String ?? "unknown"
                        
                        print("Removing stale lock for: \(entryID)")
                        batch.deleteDocument(doc.reference)
                        
                        // Notify event bus about stale lock cleanup
                        self.eventBus.publish(.lockStaleRemoved(shootID: shootID, entryID: entryID, editorName: editorName))
                    }
                    
                    batch.commit { error in
                        if let error = error {
                            print("Error cleaning up stale locks: \(error.localizedDescription)")
                            promise(.failure(error))
                        } else {
                            print("Deleted \(documents.count) stale locks")
                            promise(.success(()))
                        }
                    }
                }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Firestore Lock Listener
    
    private func setupFirestoreLockListener(shootID: String) {
        print("Setting up lock listener for shoot: \(shootID)")
        
        db.collection("sportsJobs").document(shootID)
            .collection("locks")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error listening for locks: \(error.localizedDescription)")
                    return
                }
                
                var locks: [String: String] = [:]
                
                if let documents = snapshot?.documents {
                    print("Received \(documents.count) lock documents")
                    for doc in documents {
                        let data = doc.data()
                        if let entryID = data["entryID"] as? String,
                           let editorName = data["editorName"] as? String {
                            locks[entryID] = editorName
                            print("Lock for entry \(entryID) by \(editorName)")
                        }
                    }
                }
                
                // Update the subject for this shoot
                self.lockSubjects[shootID]?.send(locks)
                
                // Also notify event bus
                self.eventBus.publish(.locksUpdated(shootID: shootID, locks: locks))
            }
    }
    
    // MARK: - Local Lock Management (for offline mode)
    
    // Add a local lock when offline
    private func addLocalLock(shootID: String, entryID: String, editorName: String) {
        if localLocks[shootID] == nil {
            localLocks[shootID] = [:]
        }
        
        localLocks[shootID]?[entryID] = editorName
        
        // Update the subject for this shoot
        lockSubjects[shootID]?.send(localLocks[shootID] ?? [:])
        
        // Notify event bus
        eventBus.publish(.lockAcquired(shootID: shootID, entryID: entryID, editorName: editorName))
    }
    
    // Remove a local lock
    private func removeLocalLock(shootID: String, entryID: String) {
        guard let editorName = localLocks[shootID]?[entryID] else { return }
        
        localLocks[shootID]?[entryID] = nil
        
        // Update the subject for this shoot
        lockSubjects[shootID]?.send(localLocks[shootID] ?? [:])
        
        // Notify event bus
        eventBus.publish(.lockReleased(shootID: shootID, entryID: entryID, editorName: editorName))
    }
    
    // Get all local locks for a shoot
    private func getLocalLocks(shootID: String) -> [String: String] {
        return localLocks[shootID] ?? [:]
    }
    
    // Clear all local locks
    private func clearLocalLocks() {
        localLocks.removeAll()
        
        // Update all subjects
        for (shootID, subject) in lockSubjects {
            subject.send([:])
            
            // Notify event bus
            eventBus.publish(.locksUpdated(shootID: shootID, locks: [:]))
        }
    }
}