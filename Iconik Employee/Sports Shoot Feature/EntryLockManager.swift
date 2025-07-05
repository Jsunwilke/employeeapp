//
//  EntryLockManager.swift
//  Iconik Employee
//
//  Created by administrator on 5/13/25.
//  Updated to include automatic lock expiration


import Foundation
import Firebase
import FirebaseFirestore

// Class to manage entry locking functionality
class EntryLockManager {
    static let shared = EntryLockManager()
    private let db = Firestore.firestore()
    private var isOnline = true
    
    // Lock expiration time in seconds (200 seconds as requested)
    private let lockExpirationTime: TimeInterval = 200
    
    // Initialize and listen for network status changes
    private init() {
        // Listen for network status changes from OfflineManager
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkStatusChanged(_:)),
            name: NSNotification.Name("OfflineManagerNetworkStatusChanged"),
            object: nil
        )
        
        // Also listen for offline locks changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(offlineLocksChanged(_:)),
            name: NSNotification.Name("OfflineLocksChanged"),
            object: nil
        )
        
        // Initialize online status
        isOnline = OfflineManager.shared.isDeviceOnline()
    }
    
    @objc private func networkStatusChanged(_ notification: Notification) {
        if let isOnline = notification.userInfo?["isOnline"] as? Bool {
            self.isOnline = isOnline
        }
    }
    
    @objc private func offlineLocksChanged(_ notification: Notification) {
        // When offline locks change, notify any active listeners
        if let shootID = notification.userInfo?["shootID"] as? String {
            // Get the local locks for this shoot
            let localLocks = OfflineManager.shared.getLocalLocks(shootID: shootID)
            
            // Notify registered listeners for this shoot about the lock changes
            NotifyLockListeners(shootID: shootID, locks: localLocks)
        }
    }
    
    // Create a lock document for an entry
    func acquireLock(shootID: String, entryID: String, editorID: String, editorName: String, completion: @escaping (Bool) -> Void) {
        // If we're offline, use local locks
        if !isOnline {
            print("Offline mode: Adding local lock for \(entryID) by \(editorName)")
            OfflineManager.shared.addLocalLock(shootID: shootID, entryID: entryID, editorName: editorName)
            completion(true)
            return
        }
        
        // We're online, use Firestore locks
        let lockID = entryID
        
        // First check if a lock already exists for this entry
        db.collection("sportsJobs").document(shootID)
            .collection("locks").document(lockID)
            .getDocument { snapshot, error in
                
                if let error = error {
                    print("Error checking for existing lock: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                // If lock exists, check if it's expired or owned by this editor
                if let snapshot = snapshot, snapshot.exists,
                   let data = snapshot.data() {
                    
                    let existingEditorID = data["editorID"] as? String
                    let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(timeIntervalSince1970: 0)
                    let timeSinceCreation = Date().timeIntervalSince(timestamp)
                    
                    // If lock is expired, we can acquire it regardless of who owned it
                    // Or if the lock is owned by this editor, we can update it
                    if timeSinceCreation > self.lockExpirationTime || existingEditorID == editorID {
                        self.createOrUpdateLock(shootID: shootID, lockID: lockID, editorID: editorID, editorName: editorName, completion: completion)
                    } else {
                        print("Entry is already locked by another editor and not expired")
                        completion(false)
                    }
                    return
                }
                
                // No existing lock, so create a new one
                self.createOrUpdateLock(shootID: shootID, lockID: lockID, editorID: editorID, editorName: editorName, completion: completion)
            }
    }
    
    // Helper method to create or update a lock
    private func createOrUpdateLock(shootID: String, lockID: String, editorID: String, editorName: String, completion: @escaping (Bool) -> Void) {
        // Create lock data with current timestamp
        let lockData: [String: Any] = [
            "entryID": lockID,
            "editorID": editorID,
            "editorName": editorName,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        self.db.collection("sportsJobs").document(shootID)
            .collection("locks").document(lockID)
            .setData(lockData) { error in
                if let error = error {
                    print("Error acquiring lock: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("Lock acquired successfully for \(lockID) by \(editorName)")
                    completion(true)
                }
            }
    }
    
    // Release a lock
    func releaseLock(shootID: String, entryID: String, editorID: String, completion: ((Bool) -> Void)? = nil) {
        // If we're offline, use local locks
        if !isOnline {
            print("Offline mode: Removing local lock for \(entryID)")
            OfflineManager.shared.removeLocalLock(shootID: shootID, entryID: entryID)
            completion?(true)
            return
        }
        
        // We're online, use Firestore locks
        let lockID = entryID
        
        // First verify that the lock is owned by this editor
        db.collection("sportsJobs").document(shootID)
            .collection("locks").document(lockID)
            .getDocument { snapshot, error in
                
                if let error = error {
                    print("Error checking lock ownership: \(error.localizedDescription)")
                    completion?(false)
                    return
                }
                
                // Only delete if lock exists and is owned by this editor
                if let snapshot = snapshot, snapshot.exists,
                   let data = snapshot.data(),
                   let existingEditorID = data["editorID"] as? String {
                    
                    // If owned by someone else, don't release
                    if existingEditorID != editorID {
                        print("Lock is owned by another editor, cannot release")
                        completion?(false)
                        return
                    }
                    
                    // Delete the lock
                    self.db.collection("sportsJobs").document(shootID)
                        .collection("locks").document(lockID)
                        .delete { error in
                            if let error = error {
                                print("Error releasing lock: \(error.localizedDescription)")
                                completion?(false)
                            } else {
                                print("Lock released successfully for \(entryID)")
                                completion?(true)
                            }
                        }
                } else {
                    // Lock doesn't exist, consider it released
                    print("No lock exists to release for \(entryID)")
                    completion?(true)
                }
            }
    }
    
    // Check if an entry is locked
    func checkLock(shootID: String, entryID: String, completion: @escaping (Bool, String?) -> Void) {
        // If we're offline, use local locks
        if !isOnline {
            let localLocks = OfflineManager.shared.getLocalLocks(shootID: shootID)
            if let editorName = localLocks[entryID] {
                completion(true, editorName)
            } else {
                completion(false, nil)
            }
            return
        }
        
        // We're online, use Firestore locks
        let lockID = entryID
        
        db.collection("sportsJobs").document(shootID)
            .collection("locks").document(lockID)
            .getDocument { snapshot, error in
                
                if let error = error {
                    print("Error checking lock: \(error.localizedDescription)")
                    completion(false, nil)
                    return
                }
                
                if let snapshot = snapshot, snapshot.exists, let data = snapshot.data() {
                    // Check if the lock has expired
                    let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(timeIntervalSince1970: 0)
                    let timeSinceCreation = Date().timeIntervalSince(timestamp)
                    
                    if timeSinceCreation > self.lockExpirationTime {
                        // Lock has expired
                        print("Lock has expired for \(entryID)")
                        completion(false, nil)
                        
                        // Optionally, remove the expired lock
                        self.db.collection("sportsJobs").document(shootID)
                            .collection("locks").document(lockID)
                            .delete { error in
                                if let error = error {
                                    print("Error removing expired lock: \(error.localizedDescription)")
                                }
                            }
                    } else {
                        // Entry is locked and not expired
                        let editorName = data["editorName"] as? String
                        completion(true, editorName)
                    }
                } else {
                    // Entry is not locked
                    completion(false, nil)
                }
            }
    }
    
    // Dictionary to keep track of active lock listeners per shoot
    private var lockListeners: [String: [([String: String]) -> Void]] = [:]
    
    // Set up a listener for locks on a specific shoot
    func listenForLocks(shootID: String, completion: @escaping ([String: String]) -> Void) {
        print("Setting up lock listener for shoot: \(shootID)")
        
        // Store the completion handler
        if lockListeners[shootID] == nil {
            lockListeners[shootID] = []
        }
        lockListeners[shootID]?.append(completion)
        
        // If we're offline, use local locks
        if !isOnline {
            let localLocks = OfflineManager.shared.getLocalLocks(shootID: shootID)
            completion(localLocks)
            return
        }
        
        // We're online, add a Firestore listener
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
                        
                        // Check if the lock has expired
                        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(timeIntervalSince1970: 0)
                        let timeSinceCreation = Date().timeIntervalSince(timestamp)
                        
                        if timeSinceCreation <= self.lockExpirationTime {
                            // Only include non-expired locks
                            if let entryID = data["entryID"] as? String,
                               let editorName = data["editorName"] as? String {
                                locks[entryID] = editorName
                                print("Lock for entry \(entryID) by \(editorName)")
                            }
                        } else {
                            // Lock has expired, remove it
                            print("Removing expired lock document: \(doc.documentID)")
                            self.db.collection("sportsJobs").document(shootID)
                                .collection("locks").document(doc.documentID)
                                .delete { error in
                                    if let error = error {
                                        print("Error removing expired lock: \(error.localizedDescription)")
                                    }
                                }
                        }
                    }
                }
                
                // Notify all listeners
                self.NotifyLockListeners(shootID: shootID, locks: locks)
            }
    }
    
    // Helper method to notify all listeners for a shoot
    private func NotifyLockListeners(shootID: String, locks: [String: String]) {
        if let listeners = lockListeners[shootID] {
            for listener in listeners {
                listener(locks)
            }
        }
    }
    
    // Clean up old locks (can be called periodically)
    func cleanupStaleLocks(shootID: String, timeThreshold: TimeInterval? = nil) {
        // If we're offline, nothing to do
        if !isOnline {
            return
        }
        
        // Use the provided threshold or default to our lockExpirationTime
        let cutoffTime = timeThreshold ?? lockExpirationTime
        print("Cleaning up stale locks for shoot: \(shootID) with threshold: \(cutoffTime) seconds")
        
        let cutoffDate = Date().addingTimeInterval(-cutoffTime)
        
        db.collection("sportsJobs").document(shootID)
            .collection("locks")
            .whereField("timestamp", isLessThan: cutoffDate)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error getting stale locks: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    print("No stale locks found")
                    return
                }
                
                print("Found \(documents.count) stale locks to clean up")
                let batch = self.db.batch()
                for doc in documents {
                    let entryID = doc.data()["entryID"] as? String ?? "unknown"
                    print("Removing stale lock for: \(entryID)")
                    batch.deleteDocument(doc.reference)
                }
                
                batch.commit { error in
                    if let error = error {
                        print("Error cleaning up stale locks: \(error.localizedDescription)")
                    } else {
                        print("Deleted \(documents.count) stale locks")
                    }
                }
            }
    }
}
