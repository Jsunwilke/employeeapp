import Foundation
import Firebase
import FirebaseFirestore

// Model for roster entry (individual subject)
struct RosterEntry: Identifiable, Codable, Hashable {
    var id: String
    var lastName: String     // Maps to "Name" in Captura
    var firstName: String    // Maps to "Subject ID" in Captura
    var teacher: String      // Maps to "Special" in Captura
    var group: String        // Maps to "Sport/Team" in Captura
    var email: String
    var phone: String
    var imageNumbers: String
    var notes: String
    var wasBlank: Bool       // Track if entry was created as blank
    var isFilledBlank: Bool // Track if blank entry was filled with a name
    
    init(id: String = UUID().uuidString,
         lastName: String = "",
         firstName: String = "",
         teacher: String = "",
         group: String = "",
         email: String = "",
         phone: String = "",
         imageNumbers: String = "",
         notes: String = "",
         wasBlank: Bool = true,
         isFilledBlank: Bool = false) {
        self.id = id
        self.lastName = lastName
        self.firstName = firstName
        self.teacher = teacher
        self.group = group
        self.email = email
        self.phone = phone
        self.imageNumbers = imageNumbers
        self.notes = notes
        self.wasBlank = wasBlank
        // If creating with a lastName, mark as filled
        self.isFilledBlank = isFilledBlank || !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Create from a dictionary - handle field mapping
    init?(from dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String else {
            return nil
        }
        
        self.id = id
        self.lastName = dictionary["lastName"] as? String ?? ""      // Maps to "Name" in Captura
        self.firstName = dictionary["firstName"] as? String ?? ""    // Maps to "Subject ID" in Captura
        self.teacher = dictionary["teacher"] as? String ?? ""        // Maps to "Special" in Captura
        self.group = dictionary["group"] as? String ?? ""            // Maps to "Sport/Team" in Captura
        self.email = dictionary["email"] as? String ?? ""
        self.phone = dictionary["phone"] as? String ?? ""
        self.imageNumbers = dictionary["imageNumbers"] as? String ?? ""
        self.notes = dictionary["notes"] as? String ?? ""
        self.wasBlank = dictionary["wasBlank"] as? Bool ?? true
        self.isFilledBlank = dictionary["isFilledBlank"] as? Bool ?? false
    }
    
    // Convert to dictionary for Firestore
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "lastName": lastName,          // Maps to "Name" in Captura
            "firstName": firstName,        // Maps to "Subject ID" in Captura
            "teacher": teacher,            // Maps to "Special" in Captura
            "group": group,                // Maps to "Sport/Team" in Captura
            "email": email,
            "phone": phone,
            "imageNumbers": imageNumbers,
            "notes": notes,
            "wasBlank": wasBlank,
            "isFilledBlank": isFilledBlank
        ]
    }
}

// Model for group image tracking
struct GroupImage: Identifiable, Codable, Hashable {
    var id: String
    var description: String
    var imageNumbers: String
    var notes: String
    
    init(id: String = UUID().uuidString,
         description: String = "",
         imageNumbers: String = "",
         notes: String = "") {
        self.id = id
        self.description = description
        self.imageNumbers = imageNumbers
        self.notes = notes
    }
    
    // Create from a dictionary
    init?(from dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String else {
            return nil
        }
        
        self.id = id
        self.description = dictionary["description"] as? String ?? ""
        self.imageNumbers = dictionary["imageNumbers"] as? String ?? ""
        self.notes = dictionary["notes"] as? String ?? ""
    }
    
    // Convert to dictionary for Firestore
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "description": description,
            "imageNumbers": imageNumbers,
            "notes": notes
        ]
    }
}

// Main sports shoot model
struct SportsShoot: Identifiable, Codable {
    var id: String
    var schoolName: String
    var schoolId: String?
    var sportName: String
    var seasonType: String?
    var shootDate: Date
    var location: String
    var photographer: String
    var roster: [RosterEntry]
    var groupImages: [GroupImage]
    var additionalNotes: String
    var organizationID: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    
    init(id: String = UUID().uuidString,
         schoolName: String = "",
         schoolId: String? = nil,
         sportName: String = "",
         seasonType: String? = nil,
         shootDate: Date = Date(),
         location: String = "",
         photographer: String = "",
         roster: [RosterEntry] = [],
         groupImages: [GroupImage] = [],
         additionalNotes: String = "",
         organizationID: String = "",
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         isArchived: Bool = false) {
        self.id = id
        self.schoolName = schoolName
        self.schoolId = schoolId
        self.sportName = sportName
        self.seasonType = seasonType
        self.shootDate = shootDate
        self.location = location
        self.photographer = photographer
        self.roster = roster
        self.groupImages = groupImages
        self.additionalNotes = additionalNotes
        self.organizationID = organizationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }
    
    // Adding a custom Codable implementation to handle optional fields and field mapping
    enum CodingKeys: String, CodingKey {
        case id, schoolName, schoolId, sportName, seasonType, shootDate, location, photographer
        case roster, groupImages, additionalNotes, organizationID
        case createdAt, updatedAt, isArchived
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        schoolName = try container.decodeIfPresent(String.self, forKey: .schoolName) ?? ""
        schoolId = try container.decodeIfPresent(String.self, forKey: .schoolId)
        sportName = try container.decodeIfPresent(String.self, forKey: .sportName) ?? ""
        seasonType = try container.decodeIfPresent(String.self, forKey: .seasonType)
        shootDate = try container.decodeIfPresent(Date.self, forKey: .shootDate) ?? Date()
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        photographer = try container.decodeIfPresent(String.self, forKey: .photographer) ?? ""
        roster = try container.decodeIfPresent([RosterEntry].self, forKey: .roster) ?? []
        groupImages = try container.decodeIfPresent([GroupImage].self, forKey: .groupImages) ?? []
        additionalNotes = try container.decodeIfPresent(String.self, forKey: .additionalNotes) ?? ""
        organizationID = try container.decodeIfPresent(String.self, forKey: .organizationID) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
    
    // Create from a Firestore document
    init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        self.id = document.documentID
        self.schoolName = data["schoolName"] as? String ?? "Unknown School"
        self.sportName = data["sportName"] as? String ?? "Unknown Sport"
        self.shootDate = (data["shootDate"] as? Timestamp)?.dateValue() ?? Date()
        self.location = data["location"] as? String ?? ""
        self.photographer = data["photographer"] as? String ?? ""
        self.additionalNotes = data["additionalNotes"] as? String ?? ""
        self.organizationID = data["organizationID"] as? String ?? ""
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        self.isArchived = data["isArchived"] as? Bool ?? false
        
        // Parse roster entries with field mapping
        self.roster = []
        if let rosterData = data["roster"] as? [[String: Any]] {
            for entryData in rosterData {
                if let entry = RosterEntry(from: entryData) {
                    self.roster.append(entry)
                }
            }
        }
        
        // Parse group images
        self.groupImages = []
        if let groupData = data["groupImages"] as? [[String: Any]] {
            for groupDict in groupData {
                if let group = GroupImage(from: groupDict) {
                    self.groupImages.append(group)
                }
            }
        }
    }
}

// Service class for managing Sports Shoots
class SportsShootService {
    static let shared = SportsShootService()
    private let db = Firestore.firestore()
    private let sportsShootsCollection = "sportsJobs"
    
    // Network monitor for connectivity tracking
    private let networkMonitor = NetworkMonitor()
    private var isOnline = true
    
    // Initialize the service
    private init() {
        // Start monitoring network status
        networkMonitor.startMonitoring { [weak self] isConnected in
            self?.isOnline = isConnected
            
            // If we just came online, sync modified shoots
            if isConnected {
                OfflineManager.shared.syncModifiedShoots()
            }
            
            // Notify listeners about network status change
            NotificationCenter.default.post(
                name: NSNotification.Name("SportsShootServiceNetworkStatusChanged"),
                object: nil,
                userInfo: ["isOnline": isConnected]
            )
        }
        
        // Initialize the isOnline property with the current status
        isOnline = networkMonitor.getCurrentConnectionStatus()
        
        // Also listen for network status changes from OfflineManager
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkStatusChanged(_:)),
            name: NSNotification.Name("OfflineManagerNetworkStatusChanged"),
            object: nil
        )
    }
    
    @objc private func networkStatusChanged(_ notification: Notification) {
        if let isOnline = notification.userInfo?["isOnline"] as? Bool {
            self.isOnline = isOnline
        }
    }
    
    // Public method to check if device is online
    func isDeviceOnline() -> Bool {
        return isOnline
    }
    
    // MARK: - Fetch
    
    func fetchSportsShoot(id: String, completion: @escaping (Result<SportsShoot, Error>) -> Void) {
        print("Fetching sports shoot with ID: \(id)")
        
        // Check if we are offline
        if !isOnline {
            print("Device is offline, using cached data...")
            
            // Try to load from cache
            if let cachedShoot = OfflineManager.shared.loadCachedShoot(id: id) {
                completion(.success(cachedShoot))
                return
            } else {
                // No cached data available
                let userInfo = [NSLocalizedDescriptionKey: "Shoot not found in cache and device is offline"]
                let error = NSError(domain: "SportsShootService", code: -1, userInfo: userInfo)
                completion(.failure(error))
                return
            }
        }
        
        // We're online, fetch from Firestore
        db.collection(sportsShootsCollection).document(id).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("Error fetching document: \(error.localizedDescription)")
                
                // Try to load from cache as fallback
                if let cachedShoot = OfflineManager.shared.loadCachedShoot(id: id) {
                    completion(.success(cachedShoot))
                } else {
                    completion(.failure(error))
                }
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists else {
                print("Document does not exist")
                let userInfo = [NSLocalizedDescriptionKey: "Sports shoot not found"]
                let error = NSError(domain: "SportsShootService", code: -1, userInfo: userInfo)
                completion(.failure(error))
                return
            }
            
            if let sportsShoot = SportsShoot(from: snapshot) {
                // Cache the shoot for offline use
                OfflineManager.shared.cacheShoot(sportsShoot) { _ in
                    // Just log the result, don't block the completion
                    print("Cached shoot \(id) for offline use")
                }
                
                completion(.success(sportsShoot))
            } else {
                let userInfo = [NSLocalizedDescriptionKey: "Failed to parse sports shoot data"]
                let error = NSError(domain: "SportsShootService", code: -2, userInfo: userInfo)
                completion(.failure(error))
            }
        }
    }
    
    func fetchAllSportsShoots(forOrganization orgID: String, completion: @escaping (Result<[SportsShoot], Error>) -> Void) {
        print("Fetching all sports shoots for organization: \(orgID)")
        
        // Make sure we're not querying with an empty orgID
        guard !orgID.isEmpty else {
            let userInfo = [NSLocalizedDescriptionKey: "Organization ID is required"]
            let error = NSError(domain: "SportsShootService", code: -2, userInfo: userInfo)
            completion(.failure(error))
            return
        }
        
        // Check if we are offline - if so, use cached data
        if !isOnline {
            print("Device is offline, using cached data...")
            var cachedShoots: [SportsShoot] = []
            
            // Fetch cached shoots from offline manager
            // This is a simplification - in a real app, you'd need to also store
            // all cached shoot IDs per organization for more complex offline flow
            // For now, we'll just look through all cached shoots (simple approach)
            let fileManager = FileManager.default
            let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("sportsShootCache")
            
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil)
                
                for fileURL in fileURLs {
                    if fileURL.pathExtension == "json" && fileURL.lastPathComponent != "cachedShoots.json" && fileURL.lastPathComponent != "modifiedShoots.json" {
                        // Extract ID from filename
                        let shootID = fileURL.deletingPathExtension().lastPathComponent
                        
                        if let shoot = OfflineManager.shared.loadCachedShoot(id: shootID),
                           shoot.organizationID == orgID {
                            cachedShoots.append(shoot)
                        }
                    }
                }
                
                // Sort by date descending
                cachedShoots.sort { $0.shootDate > $1.shootDate }
                
                completion(.success(cachedShoots))
            } catch {
                print("Error reading cached shoots: \(error.localizedDescription)")
                completion(.failure(error))
            }
            
            return
        }
        
        // We're online, fetch from Firestore
        db.collection(sportsShootsCollection)
            .whereField("organizationID", isEqualTo: orgID)
            .order(by: "shootDate", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching documents: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No documents found in collection")
                    completion(.success([]))
                    return
                }
                
                print("Found \(documents.count) documents")
                
                var sportsShoots: [SportsShoot] = []
                
                for document in documents {
                    if let sportsShoot = SportsShoot(from: document) {
                        sportsShoots.append(sportsShoot)
                    }
                }
                
                print("Successfully processed \(sportsShoots.count) sports shoots")
                completion(.success(sportsShoots))
            }
    }
    
    // MARK: - Update
    
    // Update roster entry with field mapping
    func updateRosterEntry(shootID: String, entry: RosterEntry, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check if we are offline
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            
            // Update the shoot in cache
            OfflineManager.shared.updateRosterEntryOffline(shootID: shootID, entry: entry, completion: completion)
            return
        }
        
        // We're online, update in Firestore
        let docRef = db.collection(sportsShootsCollection).document(shootID)
        
        // First remove the old entry
        docRef.getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let self = self, let snapshot = snapshot, snapshot.exists else {
                let userInfo = [NSLocalizedDescriptionKey: "Sports shoot not found"]
                let error = NSError(domain: "SportsShootService", code: -1, userInfo: userInfo)
                completion(.failure(error))
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
                    "updatedAt": FieldValue.serverTimestamp()
                ]) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    
                    // Add the updated entry
                    let entryDict = entry.toDictionary()
                    
                    docRef.updateData([
                        "roster": FieldValue.arrayUnion([entryDict]),
                        "updatedAt": FieldValue.serverTimestamp()
                    ]) { error in
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            // Update succeeded, update the cached version too
                            if let shoot = SportsShoot(from: snapshot) {
                                var updatedShoot = shoot
                                if let idx = updatedShoot.roster.firstIndex(where: { $0.id == entry.id }) {
                                    updatedShoot.roster[idx] = entry
                                } else {
                                    updatedShoot.roster.append(entry)
                                }
                                
                                // Cache the updated shoot
                                OfflineManager.shared.cacheShoot(updatedShoot) { _ in }
                            }
                            
                            completion(.success(()))
                        }
                    }
                }
            } else {
                // If entry doesn't exist yet, just add it
                self.addRosterEntry(shootID: shootID, entry: entry, completion: completion)
            }
        }
    }
    
    // Update group image
    func updateGroupImage(shootID: String, groupImage: GroupImage, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check if we are offline
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            
            // Update the shoot in cache
            OfflineManager.shared.updateGroupImageOffline(shootID: shootID, group: groupImage, completion: completion)
            return
        }
        
        // We're online, update in Firestore
        let docRef = db.collection(sportsShootsCollection).document(shootID)
        
        // First remove the old group
        docRef.getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let self = self, let snapshot = snapshot, snapshot.exists else {
                let userInfo = [NSLocalizedDescriptionKey: "Sports shoot not found"]
                let error = NSError(domain: "SportsShootService", code: -1, userInfo: userInfo)
                completion(.failure(error))
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
                    "updatedAt": FieldValue.serverTimestamp()
                ]) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    
                    // Add the updated group
                    let groupDict = groupImage.toDictionary()
                    
                    docRef.updateData([
                        "groupImages": FieldValue.arrayUnion([groupDict]),
                        "updatedAt": FieldValue.serverTimestamp()
                    ]) { error in
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            // Update succeeded, update the cached version too
                            if let shoot = SportsShoot(from: snapshot) {
                                var updatedShoot = shoot
                                if let idx = updatedShoot.groupImages.firstIndex(where: { $0.id == groupImage.id }) {
                                    updatedShoot.groupImages[idx] = groupImage
                                } else {
                                    updatedShoot.groupImages.append(groupImage)
                                }
                                
                                // Cache the updated shoot
                                OfflineManager.shared.cacheShoot(updatedShoot) { _ in }
                            }
                            
                            completion(.success(()))
                        }
                    }
                }
            } else {
                // If group doesn't exist yet, just add it
                self.addGroupImage(shootID: shootID, groupImage: groupImage, completion: completion)
            }
        }
    }
    
    // Add a new roster entry with field mapping
    func addRosterEntry(shootID: String, entry: RosterEntry, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check if we are offline
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            
            // Add the entry to the cached shoot
            OfflineManager.shared.addRosterEntryOffline(shootID: shootID, entry: entry, completion: completion)
            return
        }
        
        // We're online, update in Firestore
        let docRef = db.collection(sportsShootsCollection).document(shootID)
        
        // Convert to dictionary for Firestore
        let entryDict = entry.toDictionary()
        
        docRef.updateData([
            "roster": FieldValue.arrayUnion([entryDict]),
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            if let error = error {
                completion(.failure(error))
            } else {
                // Update succeeded, update the cached version too
                self?.fetchSportsShoot(id: shootID) { _ in
                    // Just refresh the cache, don't need to handle result
                }
                
                completion(.success(()))
            }
        }
    }
    
    // Batch add multiple roster entries
    func batchAddRosterEntries(shootID: String, entries: [RosterEntry], completion: @escaping (Bool, Error?) -> Void) {
        // Check if we are offline
        if !isOnline {
            print("Device is offline, cannot batch add entries")
            let error = NSError(domain: "SportsShootService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot batch add entries while offline"])
            completion(false, error)
            return
        }
        
        // We're online, update in Firestore
        let docRef = db.collection(sportsShootsCollection).document(shootID)
        
        // Convert all entries to dictionaries for Firestore
        let entryDicts = entries.map { $0.toDictionary() }
        
        // Use batch operation for better performance
        docRef.updateData([
            "roster": FieldValue.arrayUnion(entryDicts),
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            if let error = error {
                completion(false, error)
            } else {
                // Update succeeded, update the cached version too
                self?.fetchSportsShoot(id: shootID) { _ in
                    // Just refresh the cache, don't need to handle result
                }
                
                completion(true, nil)
            }
        }
    }
    
    // Add a new group image
    func addGroupImage(shootID: String, groupImage: GroupImage, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check if we are offline
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            
            // Add the group to the cached shoot
            OfflineManager.shared.addGroupImageOffline(shootID: shootID, group: groupImage, completion: completion)
            return
        }
        
        // We're online, update in Firestore
        let docRef = db.collection(sportsShootsCollection).document(shootID)
        
        // Convert to dictionary for Firestore
        let groupDict = groupImage.toDictionary()
        
        docRef.updateData([
            "groupImages": FieldValue.arrayUnion([groupDict]),
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            if let error = error {
                completion(.failure(error))
            } else {
                // Update succeeded, update the cached version too
                self?.fetchSportsShoot(id: shootID) { _ in
                    // Just refresh the cache, don't need to handle result
                }
                
                completion(.success(()))
            }
        }
    }
    
    // Delete roster entry
    func deleteRosterEntry(shootID: String, entryID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check if we are offline
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            
            // Delete the entry from the cached shoot
            OfflineManager.shared.deleteRosterEntryOffline(shootID: shootID, entryID: entryID, completion: completion)
            return
        }
        
        // We're online, fetch the shoot from Firestore
        fetchSportsShoot(id: shootID) { result in
            switch result {
            case .success(let shoot):
                guard let entryToRemove = shoot.roster.first(where: { $0.id == entryID }) else {
                    let userInfo = [NSLocalizedDescriptionKey: "Entry not found"]
                    let error = NSError(domain: "SportsShootService", code: -1, userInfo: userInfo)
                    completion(.failure(error))
                    return
                }
                
                // Convert to dictionary for Firestore
                let entryDict = entryToRemove.toDictionary()
                let docRef = self.db.collection(self.sportsShootsCollection).document(shootID)
                
                docRef.updateData([
                    "roster": FieldValue.arrayRemove([entryDict]),
                    "updatedAt": FieldValue.serverTimestamp()
                ]) { [weak self] error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        // Update succeeded, update the cached version too
                        self?.fetchSportsShoot(id: shootID) { _ in
                            // Just refresh the cache, don't need to handle result
                        }
                        
                        completion(.success(()))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // Delete group image
    func deleteGroupImage(shootID: String, groupID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check if we are offline
        if !isOnline {
            print("Device is offline, updating cached shoot...")
            
            // Delete the group from the cached shoot
            OfflineManager.shared.deleteGroupImageOffline(shootID: shootID, groupID: groupID, completion: completion)
            return
        }
        
        // We're online, fetch the shoot from Firestore
        fetchSportsShoot(id: shootID) { result in
            switch result {
            case .success(let shoot):
                guard let groupToRemove = shoot.groupImages.first(where: { $0.id == groupID }) else {
                    let userInfo = [NSLocalizedDescriptionKey: "Group not found"]
                    let error = NSError(domain: "SportsShootService", code: -1, userInfo: userInfo)
                    completion(.failure(error))
                    return
                }
                
                // Convert to dictionary for Firestore
                let groupDict = groupToRemove.toDictionary()
                let docRef = self.db.collection(self.sportsShootsCollection).document(shootID)
                
                docRef.updateData([
                    "groupImages": FieldValue.arrayRemove([groupDict]),
                    "updatedAt": FieldValue.serverTimestamp()
                ]) { [weak self] error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        // Update succeeded, update the cached version too
                        self?.fetchSportsShoot(id: shootID) { _ in
                            // Just refresh the cache, don't need to handle result
                        }
                        
                        completion(.success(()))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Offline Helpers
    
    // Check sync status for a shoot
    func syncStatusForShoot(id: String) -> OfflineManager.CacheStatus {
        return OfflineManager.shared.cacheStatusForShoot(id: id)
    }
    
    // Cache a shoot for offline use
    func cacheShootForOffline(id: String, completion: @escaping (Bool) -> Void) {
        // Fetch the shoot and cache it
        fetchSportsShoot(id: id) { result in
            switch result {
            case .success(let shoot):
                OfflineManager.shared.cacheShoot(shoot, completion: completion)
            case .failure:
                completion(false)
            }
        }
    }
    
    // Helper to handle conflict resolution
    func handleSyncConflicts() {
        // Listen for sync conflict notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SyncConflictsDetected"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let shootID = userInfo["shootID"] as? String,
                  let entryConflicts = userInfo["entryConflicts"] as? [OfflineManager.EntryConflict],
                  let groupConflicts = userInfo["groupConflicts"] as? [OfflineManager.GroupConflict],
                  let localShoot = userInfo["localShoot"] as? SportsShoot,
                  let remoteShoot = userInfo["remoteShoot"] as? SportsShoot else {
                return
            }
            
            // Post a notification to show the conflict resolution UI
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowConflictResolution"),
                object: nil,
                userInfo: [
                    "shootID": shootID,
                    "entryConflicts": entryConflicts,
                    "groupConflicts": groupConflicts,
                    "localShoot": localShoot,
                    "remoteShoot": remoteShoot
                ]
            )
        }
    }
    
    // MARK: - Archive Management
    
    // Archive a sports shoot
    func archiveSportsShoot(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let docRef = db.collection(sportsShootsCollection).document(id)
        
        docRef.updateData([
            "isArchived": true,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                // Update cached version if exists
                if let cachedShoot = OfflineManager.shared.loadCachedShoot(id: id) {
                    var updatedShoot = cachedShoot
                    updatedShoot.isArchived = true
                    updatedShoot.updatedAt = Date()
                    OfflineManager.shared.cacheShoot(updatedShoot) { _ in }
                }
                completion(.success(()))
            }
        }
    }
    
    // Unarchive a sports shoot
    func unarchiveSportsShoot(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let docRef = db.collection(sportsShootsCollection).document(id)
        
        docRef.updateData([
            "isArchived": false,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                // Update cached version if exists
                if let cachedShoot = OfflineManager.shared.loadCachedShoot(id: id) {
                    var updatedShoot = cachedShoot
                    updatedShoot.isArchived = false
                    updatedShoot.updatedAt = Date()
                    OfflineManager.shared.cacheShoot(updatedShoot) { _ in }
                }
                completion(.success(()))
            }
        }
    }
    
    // MARK: - CSV Import/Export
    
    // Import roster from CSV with updated display names
    func importRosterFromCSV(csvString: String) -> [RosterEntry] {
        var roster: [RosterEntry] = []
        
        // Split into lines
        let lines = csvString.components(separatedBy: .newlines)
        
        // Need at least a header row and one data row
        guard lines.count >= 2 else { return [] }
        
        // Get headers
        let headers = lines[0].components(separatedBy: ",")
        
        // Find column indices based on headers (case-insensitive)
        let normalizedHeaders = headers.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // Support both old column names and new display names
        let nameIndex = normalizedHeaders.firstIndex {
            $0.contains("last name") || $0.contains("name") && !$0.contains("first")
        } ?? -1
        
        let subjectIDIndex = normalizedHeaders.firstIndex {
            $0.contains("first name") || $0.contains("subject id")
        } ?? -1
        
        let specialIndex = normalizedHeaders.firstIndex {
            $0.contains("teacher") || $0.contains("special")
        } ?? -1
        
        let sportTeamIndex = normalizedHeaders.firstIndex {
            $0.contains("group") || $0.contains("sport") || $0.contains("team")
        } ?? -1
        
        let emailIndex = normalizedHeaders.firstIndex(where: { $0.contains("email") }) ?? -1
        let phoneIndex = normalizedHeaders.firstIndex(where: { $0.contains("phone") }) ?? -1
        let imagesIndex = normalizedHeaders.firstIndex(where: { $0.contains("image") }) ?? -1
        
        // Process data rows
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { continue }
            
            // Parse CSV line (handling quotes properly)
            var fields: [String] = []
            var currentField = ""
            var insideQuotes = false
            
            for char in line {
                if char == "\"" {
                    insideQuotes = !insideQuotes
                } else if char == "," && !insideQuotes {
                    fields.append(currentField)
                    currentField = ""
                } else {
                    currentField.append(char)
                }
            }
            fields.append(currentField) // Add the last field
            
            // Create entry with mapped fields
            let lastName = nameIndex >= 0 && nameIndex < fields.count ? fields[nameIndex] : ""
            let entry = RosterEntry(
                id: UUID().uuidString,
                lastName: lastName,
                firstName: subjectIDIndex >= 0 && subjectIDIndex < fields.count ? fields[subjectIDIndex] : "",
                teacher: specialIndex >= 0 && specialIndex < fields.count ? fields[specialIndex] : "",
                group: sportTeamIndex >= 0 && sportTeamIndex < fields.count ? fields[sportTeamIndex] : "",
                email: emailIndex >= 0 && emailIndex < fields.count ? fields[emailIndex] : "",
                phone: phoneIndex >= 0 && phoneIndex < fields.count ? fields[phoneIndex] : "",
                imageNumbers: imagesIndex >= 0 && imagesIndex < fields.count ? fields[imagesIndex] : "",
                notes: "",
                wasBlank: true,  // All imported entries are considered new/blank
                isFilledBlank: !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty  // Filled if has lastName
            )
            
            roster.append(entry)
        }
        
        return roster
    }
    
    // Export roster to CSV with updated display names
    func exportRosterToCSV(roster: [RosterEntry]) -> String {
        // Create header row with mapped fields (display names)
        var csv = "Name,Subject ID,Special,Sport/Team,Email,Phone,Images\n"
        
        // Add entries
        for entry in roster {
            let escapedLastName = escapeCSVField(entry.lastName)
            let escapedFirstName = escapeCSVField(entry.firstName)
            let escapedTeacher = escapeCSVField(entry.teacher)
            let escapedGroup = escapeCSVField(entry.group)
            let escapedEmail = escapeCSVField(entry.email)
            let escapedPhone = escapeCSVField(entry.phone)
            let escapedImageNumbers = escapeCSVField(entry.imageNumbers)
            
            csv += "\(escapedLastName),\(escapedFirstName),\(escapedTeacher),\(escapedGroup),\(escapedEmail),\(escapedPhone),\(escapedImageNumbers)\n"
        }
        
        return csv
    }
    
    // Helper to escape CSV fields
    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}
