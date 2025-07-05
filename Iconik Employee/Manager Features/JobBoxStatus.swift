//
//  JobBoxStatus.swift
//  Iconik Employee
//
//  Created by administrator on 5/10/25.
//


import Foundation
import Firebase
import FirebaseFirestore

// Enum for possible job box status values
enum JobBoxStatus: String {
    case packed = "Packed"
    case pickedUp = "Picked Up"
    case leftJob = "Left Job"
    case turnedIn = "Turned In"
    case unknown = "Unknown"
}

// Model for job box data
struct JobBox: Identifiable {
    let id: String
    let shiftUid: String
    let status: JobBoxStatus
    let scannedBy: String
    let timestamp: Date
    
    init(id: String, data: [String: Any]) {
        self.id = id
        self.shiftUid = data["shiftUid"] as? String ?? ""
        
        if let statusString = data["status"] as? String {
            self.status = JobBoxStatus(rawValue: statusString) ?? .unknown
        } else {
            self.status = .unknown
        }
        
        // FIXED: Map the 'photographer' field to scannedBy
        self.scannedBy = data["photographer"] as? String ?? ""
        
        if let timestamp = data["timestamp"] as? Timestamp {
            self.timestamp = timestamp.dateValue()
        } else {
            self.timestamp = Date()
        }
        
        // DEBUG: Print all fields when initializing a JobBox
        print("DEBUG-JOBBOX-INIT - Created JobBox: id=\(id), shiftUid=\(self.shiftUid), status=\(self.status.rawValue), scannedBy=\(self.scannedBy)")
    }
}

// Service to interact with job box data in Firestore
class JobBoxService {
    // Singleton instance
    static let shared = JobBoxService()
    
    private let db = Firestore.firestore()
    
    private init() {}
    
    // Generate a custom shift ID using the same formula as the other app
    static func generateCustomShiftID(schoolName: String, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd" // Date only, no time component
        let dateString = dateFormatter.string(from: date)
        
        // DEBUG: Print input parameters
        print("DEBUG-SHIFTUID - Generating shift UID with inputs:")
        print("DEBUG-SHIFTUID - School Name: '\(schoolName)'")
        print("DEBUG-SHIFTUID - Date: \(date)")
        print("DEBUG-SHIFTUID - Formatted Date String: \(dateString)")
        
        // FIXED: Modified normalization to match the other app's format
        // 1. Convert to lowercase
        // 2. Replace spaces with underscores
        // 3. Keep hyphens (do not remove them)
        let normalizedSchool = schoolName.lowercased().replacingOccurrences(of: " ", with: "_")
        print("DEBUG-SHIFTUID - Normalized School Name: '\(normalizedSchool)'")
        
        // FIXED: Create the custom UID with the correct format to match the other app
        // 1. Added underscore after "shift"
        // 2. Added underscore before the date
        let shiftUid = "shift_\(normalizedSchool)_\(dateString)"
        print("DEBUG-SHIFTUID - Generated shift UID: '\(shiftUid)'")
        
        return shiftUid
    }
    
    // Listen for job box updates for a specific shift
    func listenForJobBoxes(forShift event: ICSEvent, completion: @escaping ([JobBox]) -> Void) -> ListenerRegistration? {
        guard let shiftDate = event.startDate else {
            print("ERROR-JOBBOX - No shift date available")
            completion([])
            return nil
        }
        
        print("DEBUG-JOBBOX-LISTEN - ===== LISTENER SETUP START =====")
        print("DEBUG-JOBBOX-LISTEN - School Name: '\(event.schoolName)'")
        print("DEBUG-JOBBOX-LISTEN - Date: \(shiftDate)")
        
        // Generate the shift UID using the same formula as the other app
        let shiftUid = JobBoxService.generateCustomShiftID(schoolName: event.schoolName, date: shiftDate)
        print("DEBUG-JOBBOX-LISTEN - Generated shiftUid: '\(shiftUid)'")
        
        // Set up a listener for job boxes with the matching shift UID
        print("DEBUG-JOBBOX-LISTEN - Setting up Firestore listener for collection 'jobBoxes' where shiftUid = '\(shiftUid)'")
        
        return db.collection("jobBoxes")
            .whereField("shiftUid", isEqualTo: shiftUid)
            .addSnapshotListener { snapshot, error in
                print("DEBUG-JOBBOX-LISTEN - Snapshot listener triggered")
                
                if let error = error {
                    print("ERROR-JOBBOX-LISTEN - Error listening for job boxes: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("DEBUG-JOBBOX-LISTEN - No job box documents found for shiftUid: '\(shiftUid)'")
                    completion([])
                    return
                }
                
                print("DEBUG-JOBBOX-LISTEN - Found \(documents.count) job box documents")
                
                // Convert documents to JobBox objects
                let jobBoxes = documents.map { document -> JobBox in
                    print("DEBUG-JOBBOX-LISTEN - Processing document ID: \(document.documentID)")
                    print("DEBUG-JOBBOX-LISTEN - Document data: \(document.data())")
                    
                    let jobBox = JobBox(id: document.documentID, data: document.data())
                    return jobBox
                }
                
                print("DEBUG-JOBBOX-LISTEN - Returning \(jobBoxes.count) job boxes to completion handler")
                print("DEBUG-JOBBOX-LISTEN - ===== LISTENER SETUP END =====")
                
                completion(jobBoxes)
            }
    }
    
    // Process a job box notification payload
    func processJobBoxNotification(userInfo: [AnyHashable: Any]) -> (status: JobBoxStatus, scannedBy: String)? {
        print("DEBUG-JOBBOX-NOTIFY - Processing notification payload: \(userInfo)")
        
        guard let statusString = userInfo["status"] as? String,
              let scannedBy = userInfo["photographer"] as? String else {  // FIXED: Use photographer field instead of scannedBy
            print("ERROR-JOBBOX-NOTIFY - Missing required fields in notification payload")
            return nil
        }
        
        print("DEBUG-JOBBOX-NOTIFY - Extracted status: '\(statusString)', scannedBy: '\(scannedBy)'")
        
        // Check if shiftUid is present in the notification
        if let notificationShiftUid = userInfo["shiftUid"] as? String {
            print("DEBUG-JOBBOX-NOTIFY - Notification contains shiftUid: '\(notificationShiftUid)'")
        } else {
            print("DEBUG-JOBBOX-NOTIFY - Warning: Notification does not contain shiftUid")
        }
        
        let status = JobBoxStatus(rawValue: statusString) ?? .unknown
        print("DEBUG-JOBBOX-NOTIFY - Final processed status: \(status.rawValue)")
        
        return (status: status, scannedBy: scannedBy)
    }
    
    // Register device token for push notifications
    func registerDeviceToken(_ deviceToken: Data) {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("ERROR-JOBBOX-TOKEN - Cannot register device token: No user is signed in")
            return
        }
        
        // Convert token to string format
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("DEBUG-JOBBOX-TOKEN - Registering device token for user \(userId): \(tokenString)")
        
        // Store the token in Firestore
        db.collection("users").document(userId).updateData([
            "fcmToken": tokenString
        ]) { error in
            if let error = error {
                print("ERROR-JOBBOX-TOKEN - Error registering device token: \(error.localizedDescription)")
            } else {
                print("DEBUG-JOBBOX-TOKEN - Successfully registered device token for job box notifications")
            }
        }
    }
    
    // DEBUG: Query all job boxes to check for any matching records
    func debugQueryAllJobBoxes(completion: @escaping ([JobBox]) -> Void) {
        print("DEBUG-JOBBOX-QUERY - Querying all job boxes in the collection")
        
        db.collection("jobBoxes")
            .limit(to: 20)  // Limit to avoid retrieving too many records
            .getDocuments { snapshot, error in
                if let error = error {
                    print("ERROR-JOBBOX-QUERY - Error querying job boxes: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("DEBUG-JOBBOX-QUERY - No job box documents found at all")
                    completion([])
                    return
                }
                
                print("DEBUG-JOBBOX-QUERY - Found \(documents.count) job box documents in the collection")
                
                // Print the shiftUid of each document for debugging
                documents.forEach { document in
                    if let shiftUid = document.data()["shiftUid"] as? String {
                        print("DEBUG-JOBBOX-QUERY - Document ID: \(document.documentID), shiftUid: '\(shiftUid)'")
                    } else {
                        print("DEBUG-JOBBOX-QUERY - Document ID: \(document.documentID), missing shiftUid field")
                    }
                }
                
                let jobBoxes = documents.map { JobBox(id: $0.documentID, data: $0.data()) }
                completion(jobBoxes)
            }
    }
    
    // DEBUG: Query job boxes using partial matching
    func debugQueryJobBoxesByPartialShiftID(partialID: String, completion: @escaping ([JobBox]) -> Void) {
        print("DEBUG-JOBBOX-PARTIAL - Querying job boxes with partial shiftUid: '\(partialID)'")
        
        db.collection("jobBoxes")
            .whereField("shiftUid", isGreaterThanOrEqualTo: partialID)
            .whereField("shiftUid", isLessThanOrEqualTo: partialID + "\u{f8ff}")  // Unicode high value for prefix search
            .limit(to: 20)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("ERROR-JOBBOX-PARTIAL - Error querying job boxes: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("DEBUG-JOBBOX-PARTIAL - No job box documents found with partial ID: '\(partialID)'")
                    completion([])
                    return
                }
                
                print("DEBUG-JOBBOX-PARTIAL - Found \(documents.count) job box documents with partial ID: '\(partialID)'")
                
                documents.forEach { document in
                    if let shiftUid = document.data()["shiftUid"] as? String {
                        print("DEBUG-JOBBOX-PARTIAL - Document ID: \(document.documentID), shiftUid: '\(shiftUid)'")
                    }
                }
                
                let jobBoxes = documents.map { JobBox(id: $0.documentID, data: $0.data()) }
                completion(jobBoxes)
            }
    }
}
