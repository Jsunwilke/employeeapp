//
//  EntryLockManager.swift
//  Iconik Employee
//
//  Created by administrator on 5/13/25.
//


import Foundation
import Firebase
import FirebaseFirestore

// Class to manage entry locking functionality
class EntryLockManager {
    static let shared = EntryLockManager()
    private let db = Firestore.firestore()
    
    // Create a lock document for an entry
    func acquireLock(shootID: String, entryID: String, editorID: String, editorName: String, completion: @escaping (Bool) -> Void) {
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
                
                // If lock exists and is not owned by this editor, fail
                if let snapshot = snapshot, snapshot.exists,
                   let data = snapshot.data(),
                   let existingEditorID = data["editorID"] as? String,
                   existingEditorID != editorID {
                    
                    print("Entry is already locked by another editor")
                    completion(false)
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
                            completion(false)
                        } else {
                            print("Lock acquired successfully for \(entryID) by \(editorName)")
                            completion(true)
                        }
                    }
            }
    }
    
    // Release a lock
    func releaseLock(shootID: String, entryID: String, editorID: String, completion: ((Bool) -> Void)? = nil) {
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
                    // Entry is locked
                    let editorName = data["editorName"] as? String
                    completion(true, editorName)
                } else {
                    // Entry is not locked
                    completion(false, nil)
                }
            }
    }
    
    // Set up a listener for locks on a specific shoot
    func listenForLocks(shootID: String, completion: @escaping ([String: String]) -> Void) {
        print("Setting up lock listener for shoot: \(shootID)")
        
        db.collection("sportsJobs").document(shootID)
            .collection("locks")
            .addSnapshotListener { snapshot, error in
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
                
                completion(locks)
            }
    }
    
    // Clean up old locks (can be called periodically)
    func cleanupStaleLocks(shootID: String, timeThreshold: TimeInterval = 300) {
        print("Cleaning up stale locks for shoot: \(shootID)")
        let cutoffDate = Date().addingTimeInterval(-timeThreshold)
        
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
