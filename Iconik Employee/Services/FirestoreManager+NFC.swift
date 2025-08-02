import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - NFC SD Tracker Extensions to FirestoreManager

// Singleton FirestoreManager for NFC functionality
class FirestoreManager: ObservableObject {
    static let shared = FirestoreManager()
    
    private init() {}
    
    // Published properties for UI updates
    @Published var isLoading = false
    @Published var loadingMessage = ""
    
    // MARK: - Save Record (SD Card)
    func saveRecord(timestamp: Date,
                   photographer: String,
                   cardNumber: String,
                   school: String,
                   status: String,
                   uploadedFromJasonsHouse: String?,
                   uploadedFromAndysHouse: String?,
                   organizationID: String,
                   userId: String,
                   completion: @escaping (Result<String, Error>) -> Void) {
        
        // Check if we're online
        if OfflineDataManager.shared.isOnline {
            let db = Firestore.firestore()
            
            // Create document data
            var documentData: [String: Any] = [
                "cardNumber": cardNumber,
                "school": school,
                "status": status,
                "photographer": photographer,
                "userId": userId,
                "organizationID": organizationID,
                "timestamp": Timestamp(date: timestamp)
            ]
            
            // Add upload location fields if status is "Uploaded"
            if status.lowercased() == "uploaded" {
                if let jasonHouse = uploadedFromJasonsHouse, !jasonHouse.isEmpty {
                    documentData["uploadedFromJasonsHouse"] = jasonHouse
                }
                if let andyHouse = uploadedFromAndysHouse, !andyHouse.isEmpty {
                    documentData["uploadedFromAndysHouse"] = andyHouse
                }
            }
            
            db.collection("records").addDocument(data: documentData) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success("SD card scan saved successfully"))
                }
            }
        } else {
            // Handle offline saving
            let record = FirestoreRecord(
                timestamp: timestamp,
                photographer: photographer,
                cardNumber: cardNumber,
                school: school,
                status: status,
                uploadedFromJasonsHouse: uploadedFromJasonsHouse,
                uploadedFromAndysHouse: uploadedFromAndysHouse,
                organizationID: organizationID,
                userId: userId
            )
            OfflineDataManager.shared.addOfflineRecord(record: record)
            completion(.success("SD card scan saved offline. Will sync when connection is restored."))
        }
    }
    
    // MARK: - Fetch Records (SD Card)
    func fetchRecords(field: String,
                     value: String,
                     organizationID: String,
                     completion: @escaping (Result<[FirestoreRecord], Error>) -> Void) {
        
        // Check if we're online
        if OfflineDataManager.shared.isOnline {
            let db = Firestore.firestore()
            var query: Query = db.collection("records").whereField("organizationID", isEqualTo: organizationID)
            
            if field.lowercased() != "all" {
                query = query.whereField(field, isEqualTo: value)
            }
            
            query.getDocuments { snapshot, error in
                if let error = error {
                    // Try to get cached data if there's an error
                    if let cachedRecords = OfflineDataManager.shared.getCachedRecords() {
                        let filteredRecords = self.filterCachedRecords(
                            records: cachedRecords,
                            field: field,
                            value: value,
                            organizationID: organizationID
                        )
                        completion(.success(filteredRecords))
                    } else {
                        completion(.failure(error))
                    }
                } else if let snapshot = snapshot {
                    let records = snapshot.documents.map { document -> FirestoreRecord in
                        return FirestoreRecord(id: document.documentID, data: document.data())
                    }
                    
                    // Cache records for offline use
                    OfflineDataManager.shared.cacheRecords(records: records)
                    
                    completion(.success(records))
                }
            }
        } else {
            // Offline mode - use cached data
            if let cachedRecords = OfflineDataManager.shared.getCachedRecords() {
                let filteredRecords = filterCachedRecords(
                    records: cachedRecords,
                    field: field,
                    value: value,
                    organizationID: organizationID
                )
                completion(.success(filteredRecords))
            } else {
                let error = NSError(domain: "com.iconikstudio.sdtracker", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "No cached SD card data available while offline"
                ])
                completion(.failure(error))
            }
        }
    }
    
    // Helper method to filter cached records
    private func filterCachedRecords(records: [FirestoreRecord],
                                   field: String,
                                   value: String,
                                   organizationID: String) -> [FirestoreRecord] {
        let orgRecords = records.filter { $0.organizationID == organizationID }
        
        if field.lowercased() == "all" {
            return orgRecords
        } else {
            return orgRecords.filter { record in
                switch field.lowercased() {
                case "cardnumber":
                    return record.cardNumber == value
                case "photographer":
                    return record.photographer == value
                case "school":
                    return record.school == value
                case "status":
                    return record.status.lowercased() == value.lowercased()
                default:
                    return false
                }
            }
        }
    }
    
    // MARK: - Save Job Box Record
    func saveJobBoxRecord(timestamp: Date,
                        photographer: String,
                        boxNumber: String,
                        school: String,
                        schoolId: String? = nil,
                        status: String,
                        organizationID: String,
                        userId: String,
                        shiftUid: String? = nil,
                        completion: @escaping (Result<String, Error>) -> Void) {
        
        // Check if we're online
        if OfflineDataManager.shared.isOnline {
            let firestore = Firestore.firestore()
            var jobBoxRef: DocumentReference?
            
            // Create a dictionary with all fields for Firestore
            var documentData: [String: Any] = [
                "boxNumber": boxNumber,
                "school": school,
                "status": status,
                "photographer": photographer,
                "userId": userId,
                "organizationID": organizationID,
                "timestamp": Timestamp(date: timestamp)
            ]
            
            // Add optional fields if present
            if let schoolId = schoolId {
                documentData["schoolId"] = schoolId
            }
            if let shiftUid = shiftUid {
                documentData["shiftUid"] = shiftUid
            }
            
            jobBoxRef = firestore.collection("jobBoxes").addDocument(data: documentData) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    // Update the session to mark it as assigned
                    if let shiftUid = shiftUid,
                       let jobBoxId = jobBoxRef?.documentID {
                        firestore.collection("sessions").document(shiftUid).updateData([
                            "hasJobBoxAssigned": true,
                            "jobBoxRecordId": jobBoxId
                        ]) { updateError in
                            if let updateError = updateError {
                                print("⚠️ Warning: Failed to update session assignment status: \(updateError)")
                                // Still consider the job box save successful
                            } else {
                                print("✅ Successfully updated session \(shiftUid) with job box assignment")
                            }
                        }
                    }
                    
                    completion(.success("Job box record saved successfully"))
                }
            }
        } else {
            // Handle offline saving
            let recordData: [String: Any] = [
                "boxNumber": boxNumber,
                "school": school,
                "status": status,
                "photographer": photographer,
                "userId": userId,
                "organizationID": organizationID,
                "timestamp": timestamp,
                "schoolId": schoolId as Any,
                "shiftUid": shiftUid as Any
            ]
            OfflineDataManager.shared.addPendingOperation(
                type: .add,
                collectionPath: "jobBoxes",
                data: recordData
            )
            completion(.success("Job box record saved offline. Will sync when connection is restored."))
        }
    }
    
    // MARK: - Fetch Job Box Records
    func fetchJobBoxRecords(field: String,
                          value: String,
                          organizationID: String,
                          completion: @escaping (Result<[JobBox], Error>) -> Void) {
        
        // Check if we're online
        if OfflineDataManager.shared.isOnline {
            let firestore = Firestore.firestore()
            var query: Query = firestore.collection("jobBoxes").whereField("organizationID", isEqualTo: organizationID)
            if field.lowercased() != "all" {
                query = query.whereField(field, isEqualTo: value)
            }
            
            query.getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                } else if let snapshot = snapshot {
                    let records = snapshot.documents.map { document -> JobBox in
                        return JobBox(id: document.documentID, data: document.data())
                    }
                    
                    completion(.success(records))
                }
            }
        } else {
            // Offline mode - return empty array for now
            let error = NSError(domain: "com.iconikstudio.sdtracker", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Job box data not available offline"
            ])
            completion(.failure(error))
        }
    }
    
    // MARK: - Listen for Photographers
    func listenForPhotographers(inOrgID orgID: String, completion: @escaping ([String]) -> Void) {
        let db = Firestore.firestore()
        
        db.collection("users")
            .whereField("organizationID", isEqualTo: orgID)
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening for photographers: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let photographers = documents.compactMap { doc -> String? in
                    return doc.data()["firstName"] as? String
                }.sorted()
                
                // Cache the photographer names
                if let encoded = try? JSONEncoder().encode(photographers) {
                    UserDefaults.standard.set(encoded, forKey: "photographerNames")
                }
                
                completion(photographers)
            }
    }
    
    // MARK: - Listen for Schools Data
    func listenForSchoolsData(forOrgID orgID: String, completion: @escaping ([SchoolItem]) -> Void) {
        let db = Firestore.firestore()
        
        db.collection("schools")
            .whereField("organizationID", isEqualTo: orgID)
            .order(by: "value")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening for schools: \(error)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let schools = documents.compactMap { doc -> SchoolItem? in
                    let data = doc.data()
                    guard let name = data["value"] as? String else { return nil }
                    
                    // Build address from available fields (matching TemplateService pattern)
                    var addressComponents: [String] = []
                    if let street = data["street"] as? String, !street.isEmpty {
                        addressComponents.append(street)
                    }
                    if let city = data["city"] as? String, !city.isEmpty {
                        addressComponents.append(city)
                    }
                    if let state = data["state"] as? String, !state.isEmpty {
                        addressComponents.append(state)
                    }
                    if let zipCode = data["zipCode"] as? String, !zipCode.isEmpty {
                        addressComponents.append(zipCode)
                    }
                    
                    let address = addressComponents.isEmpty ? name : addressComponents.joined(separator: ", ")
                    let coordinates = data["coordinates"] as? String
                    
                    return SchoolItem(
                        id: doc.documentID,
                        name: name,
                        address: address,
                        coordinates: coordinates
                    )
                }
                
                // Cache the school records
                if let encoded = try? JSONEncoder().encode(schools) {
                    UserDefaults.standard.set(encoded, forKey: "nfcSchools")
                }
                
                completion(schools)
            }
    }
    
    // MARK: - Delete Operations
    
    func deleteRecord(recordID: String, completion: @escaping (Result<String, Error>) -> Void) {
        let db = Firestore.firestore()
        
        db.collection("records").document(recordID).delete() { error in
            if let error = error {
                completion(.failure(error))
            } else {
                // Also mark for offline deletion if needed
                if !OfflineDataManager.shared.isOnline {
                    OfflineDataManager.shared.addPendingOperation(
                        type: .delete,
                        collectionPath: "records",
                        data: [:],
                        id: recordID
                    )
                }
                completion(.success("Record deleted successfully"))
            }
        }
    }
    
    func deleteJobBoxRecord(recordID: String, completion: @escaping (Result<String, Error>) -> Void) {
        let db = Firestore.firestore()
        
        db.collection("jobBoxes").document(recordID).delete() { error in
            if let error = error {
                completion(.failure(error))
            } else {
                // Also mark for offline deletion if needed
                if !OfflineDataManager.shared.isOnline {
                    OfflineDataManager.shared.addPendingOperation(
                        type: .delete,
                        collectionPath: "jobBoxes",
                        data: [:],
                        id: recordID
                    )
                }
                completion(.success("Job box record deleted successfully"))
            }
        }
    }
    
    // Debug helper to print job box document structure
    func debugPrintJobBoxDocuments(organizationID: String) {
        let db = Firestore.firestore()
        
        db.collection("jobBoxes")
            .whereField("organizationID", isEqualTo: organizationID)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ DEBUG: Error fetching job box documents: \(error)")
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    print("❌ DEBUG: No job box documents found")
                    return
                }
                
                print("📦 DEBUG: Job Box Document Structure:")
                print("Document ID: \(document.documentID)")
                let data = document.data()
                for (key, value) in data {
                    print("  \(key): \(type(of: value)) = \(value)")
                }
            }
    }
    
    // MARK: - Get Highest Box Number
    func getHighestBoxNumber(organizationID: String, completion: @escaping (Result<Int, Error>) -> Void) {
        let db = Firestore.firestore()
        
        db.collection("jobBoxes")
            .whereField("organizationID", isEqualTo: organizationID)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success(3000)) // Default starting number
                    return
                }
                
                let boxNumbers = documents.compactMap { doc -> Int? in
                    let data = doc.data()
                    if let boxNumberStr = data["boxNumber"] as? String {
                        return Int(boxNumberStr)
                    }
                    return nil
                }
                
                if let maxNumber = boxNumbers.max() {
                    completion(.success(maxNumber))
                } else {
                    completion(.success(3000)) // Default if no boxes found
                }
            }
    }
}