import Foundation
import FirebaseFirestore
import FirebaseAuth

class YearbookShootListService: ObservableObject {
    static let shared = YearbookShootListService()
    private let db = Firestore.firestore()
    private let collectionName = "yearbookShootLists"
    
    // Cache for offline support
    private var cachedLists: [String: YearbookShootList] = [:]
    private let cacheQueue = DispatchQueue(label: "com.iconik.yearbook.cache")
    
    private init() {
        // Firestore settings are configured app-wide in AppDelegate
        // No need to set them here
    }
    
    // MARK: - Fetch Operations
    
    /// Get yearbook shoot list for a specific school and year
    func getYearbookShootList(schoolId: String, schoolYear: String) async throws -> YearbookShootList? {
        // Check cache first
        let cacheKey = "\(schoolId)_\(schoolYear)"
        if let cached = getCachedList(key: cacheKey) {
            print("🗂️ Returning cached yearbook list for \(cacheKey)")
            return cached
        }
        
        let snapshot = try await db.collection(collectionName)
            .whereField("schoolId", isEqualTo: schoolId)
            .whereField("schoolYear", isEqualTo: schoolYear)
            .limit(to: 1)
            .getDocuments()
        
        guard let document = snapshot.documents.first else {
            print("📋 No yearbook list found for school: \(schoolId), year: \(schoolYear)")
            return nil
        }
        
        let shootList = try document.data(as: YearbookShootList.self)
        
        // Cache the result
        cacheList(shootList, key: cacheKey)
        
        return shootList
    }
    
    /// Get all yearbook lists for an organization
    func getOrganizationYearbookLists(organizationId: String) async throws -> [YearbookShootList] {
        let snapshot = try await db.collection(collectionName)
            .whereField("organizationId", isEqualTo: organizationId)
            .order(by: "schoolYear", descending: true)
            .getDocuments()
        
        return try snapshot.documents.compactMap { document in
            try document.data(as: YearbookShootList.self)
        }
    }
    
    /// DEBUG: Get all yearbook lists for an organization
    func debugGetAllYearbookLists(organizationId: String) async throws {
        print("🔍 DEBUG: Getting all yearbook lists for organization")
        let snapshot = try await db.collection(collectionName)
            .whereField("organizationId", isEqualTo: organizationId)
            .getDocuments()
        
        print("🔍 DEBUG: Found \(snapshot.documents.count) total yearbook lists")
        for doc in snapshot.documents {
            let data = doc.data()
            print("🔍 DEBUG: Document ID: \(doc.documentID)")
            print("🔍   - schoolId: '\(data["schoolId"] as? String ?? "nil")'")
            print("🔍   - schoolName: '\(data["schoolName"] as? String ?? "nil")'")
            print("🔍   - schoolYear: '\(data["schoolYear"] as? String ?? "nil")'")
            print("🔍   - organizationId: '\(data["organizationId"] as? String ?? "nil")'")
            print("🔍   ---")
        }
    }
    
    /// Get available years for a school
    func getAvailableYears(schoolId: String, organizationId: String) async throws -> [String] {
        print("🔍 YearbookShootListService.getAvailableYears")
        print("🔍 Querying collection: '\(collectionName)'")
        print("🔍 Looking for schoolId: '\(schoolId)'")
        print("🔍 With organizationId: '\(organizationId)'")
        
        // Query with both schoolId and organizationId to satisfy security rules
        let snapshot = try await db.collection(collectionName)
            .whereField("organizationId", isEqualTo: organizationId)
            .whereField("schoolId", isEqualTo: schoolId)
            .getDocuments()
        
        print("🔍 Found \(snapshot.documents.count) documents with exact match")
        
        // If no exact match, try getting all documents and comparing manually
        if snapshot.documents.isEmpty {
            print("🔍 No exact match found. Checking all documents for debugging...")
            let allDocs = try await db.collection(collectionName).getDocuments()
            print("🔍 Total documents in collection: \(allDocs.documents.count)")
            
            for doc in allDocs.documents {
                if let docSchoolId = doc.data()["schoolId"] as? String {
                    print("🔍 Comparing: '\(docSchoolId)' vs '\(schoolId)'")
                    print("🔍   - Equal: \(docSchoolId == schoolId)")
                    print("🔍   - Trimmed equal: \(docSchoolId.trimmingCharacters(in: .whitespacesAndNewlines) == schoolId.trimmingCharacters(in: .whitespacesAndNewlines))")
                    print("🔍   - Case insensitive: \(docSchoolId.lowercased() == schoolId.lowercased())")
                }
            }
        }
        
        // Debug: Print all document data
        for doc in snapshot.documents {
            print("🔍 Document ID: \(doc.documentID)")
            if let docSchoolId = doc.data()["schoolId"] as? String {
                print("🔍   - Document schoolId: '\(docSchoolId)'")
            }
            if let docSchoolName = doc.data()["schoolName"] as? String {
                print("🔍   - Document schoolName: '\(docSchoolName)'")
            }
            if let docYear = doc.data()["schoolYear"] as? String {
                print("🔍   - Document schoolYear: '\(docYear)'")
            }
        }
        
        let years = snapshot.documents.compactMap { doc in
            doc.data()["schoolYear"] as? String
        }
        
        let uniqueYears = Array(Set(years)).sorted(by: >)
        print("🔍 Unique years found: \(uniqueYears)")
        
        return uniqueYears
    }
    
    /// Get active yearbook lists for current school year
    func getActiveYearbookLists(organizationId: String) async throws -> [YearbookShootList] {
        let currentYear = YearbookShootList.getCurrentSchoolYear()
        
        let snapshot = try await db.collection(collectionName)
            .whereField("organizationId", isEqualTo: organizationId)
            .whereField("schoolYear", isEqualTo: currentYear)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        return try snapshot.documents.compactMap { document in
            try document.data(as: YearbookShootList.self)
        }
    }
    
    // MARK: - Create Operations
    
    /// Create a new yearbook shoot list
    func createYearbookShootList(_ list: YearbookShootList) async throws -> String {
        let documentRef = db.collection(collectionName).document()
        
        var newList = list
        newList.id = documentRef.documentID
        
        try await documentRef.setData(newList.toFirestoreData())
        
        // Cache the new list
        let cacheKey = "\(list.schoolId)_\(list.schoolYear)"
        cacheList(newList, key: cacheKey)
        
        print("✅ Created yearbook list for \(list.schoolName) - \(list.schoolYear)")
        return documentRef.documentID
    }
    
    /// Copy a yearbook list from another year or template
    func copyYearbookShootList(fromListId: String, toSchoolId: String, toSchoolYear: String, toSchoolName: String) async throws -> String {
        // Get the source list
        let sourceDoc = try await db.collection(collectionName).document(fromListId).getDocument()
        guard let sourceList = try? sourceDoc.data(as: YearbookShootList.self) else {
            throw YearbookError.listNotFound
        }
        
        // Create new list with copied items (reset completion status)
        let dates = YearbookShootList.getSchoolYearDates(schoolYear: toSchoolYear) ?? (Date(), Date())
        let newItems = sourceList.items.map { item in
            YearbookItem(
                name: item.name,
                description: item.description,
                category: item.category,
                required: item.required,
                completed: false,
                order: item.order
            )
        }
        
        let newList = YearbookShootList(
            organizationId: sourceList.organizationId,
            schoolId: toSchoolId,
            schoolName: toSchoolName,
            schoolYear: toSchoolYear,
            startDate: dates.start,
            endDate: dates.end,
            isActive: toSchoolYear == YearbookShootList.getCurrentSchoolYear(),
            copiedFromId: fromListId,
            completedCount: 0,
            totalCount: newItems.count,
            items: newItems,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        return try await createYearbookShootList(newList)
    }
    
    // MARK: - Update Operations
    
    /// Update a specific item in the yearbook list
    func updateShootListItem(listId: String, itemId: String, updates: [String: Any]) async throws {
        let listRef = db.collection(collectionName).document(listId)
        
        // Get current document
        let document = try await listRef.getDocument()
        guard var listData = document.data(),
              var items = listData["items"] as? [[String: Any]] else {
            throw YearbookError.listNotFound
        }
        
        // Find and update item
        guard let index = items.firstIndex(where: { ($0["id"] as? String) == itemId }) else {
            throw YearbookError.itemNotFound
        }
        
        // Track completion status change
        let wasCompleted = items[index]["completed"] as? Bool ?? false
        
        // Merge updates
        items[index].merge(updates) { _, new in new }
        
        // Update completed count if status changed
        let isNowCompleted = items[index]["completed"] as? Bool ?? false
        if wasCompleted != isNowCompleted {
            let currentCount = listData["completedCount"] as? Int ?? 0
            listData["completedCount"] = isNowCompleted ? currentCount + 1 : max(0, currentCount - 1)
        }
        
        // Update document
        try await listRef.updateData([
            "items": items,
            "completedCount": listData["completedCount"] ?? 0,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        // Invalidate cache
        if let schoolId = listData["schoolId"] as? String,
           let schoolYear = listData["schoolYear"] as? String {
            let cacheKey = "\(schoolId)_\(schoolYear)"
            invalidateCache(key: cacheKey)
        }
        
        print("✅ Updated item \(itemId) in list \(listId)")
    }
    
    /// Toggle item completion status
    func toggleItemCompletion(listId: String, itemId: String, sessionContext: YearbookSessionContext?) async throws {
        let listRef = db.collection(collectionName).document(listId)
        
        // Get current document
        let document = try await listRef.getDocument()
        guard let shootList = try? document.data(as: YearbookShootList.self),
              let item = shootList.items.first(where: { $0.id == itemId }) else {
            throw YearbookError.itemNotFound
        }
        
        // Prepare updates
        var updates: [String: Any] = [
            "completed": !item.completed
        ]
        
        if !item.completed {
            // Marking as complete
            updates["completedDate"] = Timestamp()
            
            if let context = sessionContext {
                updates["completedBySession"] = context.sessionId
                updates["photographerId"] = context.photographerId
                updates["photographerName"] = context.photographerName
            } else if let currentUser = Auth.auth().currentUser {
                updates["photographerId"] = currentUser.uid
                updates["photographerName"] = currentUser.displayName ?? "Unknown"
            }
        } else {
            // Marking as incomplete
            updates["completedDate"] = NSNull()
            updates["completedBySession"] = NSNull()
            updates["photographerId"] = NSNull()
            updates["photographerName"] = NSNull()
        }
        
        try await updateShootListItem(listId: listId, itemId: itemId, updates: updates)
    }
    
    /// Update item notes
    func updateItemNotes(listId: String, itemId: String, notes: String?) async throws {
        let updates: [String: Any] = notes != nil ? ["notes": notes!] : ["notes": NSNull()]
        try await updateShootListItem(listId: listId, itemId: itemId, updates: updates)
    }
    
    /// Update item image numbers
    func updateItemImageNumbers(listId: String, itemId: String, imageNumbers: [String]) async throws {
        let updates: [String: Any] = !imageNumbers.isEmpty ? ["imageNumbers": imageNumbers] : ["imageNumbers": NSNull()]
        try await updateShootListItem(listId: listId, itemId: itemId, updates: updates)
    }
    
    // MARK: - Real-time Listeners
    
    /// Subscribe to updates for a specific yearbook list
    func subscribeToShootListUpdates(schoolId: String, schoolYear: String, organizationId: String,
                                    completion: @escaping (YearbookShootList?) -> Void) -> ListenerRegistration {
        return db.collection(collectionName)
            .whereField("organizationId", isEqualTo: organizationId)
            .whereField("schoolId", isEqualTo: schoolId)
            .whereField("schoolYear", isEqualTo: schoolYear)
            .limit(to: 1)
            .addSnapshotListener { snapshot, error in
                guard let document = snapshot?.documents.first else {
                    completion(nil)
                    return
                }
                
                do {
                    let shootList = try document.data(as: YearbookShootList.self)
                    
                    // Update cache
                    let cacheKey = "\(schoolId)_\(schoolYear)"
                    self.cacheList(shootList, key: cacheKey)
                    
                    completion(shootList)
                } catch {
                    print("❌ Error decoding yearbook list: \(error)")
                    completion(nil)
                }
            }
    }
    
    /// Subscribe to all lists for an organization
    func subscribeToOrganizationLists(organizationId: String,
                                     completion: @escaping ([YearbookShootList]) -> Void) -> ListenerRegistration {
        return db.collection(collectionName)
            .whereField("organizationId", isEqualTo: organizationId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let lists = documents.compactMap { document in
                    try? document.data(as: YearbookShootList.self)
                }
                
                completion(lists)
            }
    }
    
    // MARK: - Delete Operations
    
    /// Delete a yearbook shoot list
    func deleteYearbookShootList(listId: String) async throws {
        try await db.collection(collectionName).document(listId).delete()
        print("🗑️ Deleted yearbook list: \(listId)")
    }
    
    // MARK: - Cache Management
    
    private func cacheList(_ list: YearbookShootList, key: String) {
        cacheQueue.async {
            self.cachedLists[key] = list
            
            // Save to UserDefaults for persistence
            if let encoded = try? JSONEncoder().encode(list) {
                UserDefaults.standard.set(encoded, forKey: "yearbook_cache_\(key)")
            }
        }
    }
    
    private func getCachedList(key: String) -> YearbookShootList? {
        // Check memory cache first
        if let cached = cacheQueue.sync(execute: { cachedLists[key] }) {
            return cached
        }
        
        // Check UserDefaults
        if let data = UserDefaults.standard.data(forKey: "yearbook_cache_\(key)"),
           let list = try? JSONDecoder().decode(YearbookShootList.self, from: data) {
            // Restore to memory cache
            cacheQueue.async {
                self.cachedLists[key] = list
            }
            return list
        }
        
        return nil
    }
    
    private func invalidateCache(key: String) {
        cacheQueue.async {
            self.cachedLists.removeValue(forKey: key)
            UserDefaults.standard.removeObject(forKey: "yearbook_cache_\(key)")
        }
    }
    
    func clearAllCache() {
        cacheQueue.async {
            self.cachedLists.removeAll()
            
            // Clear UserDefaults cache
            let defaults = UserDefaults.standard
            let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("yearbook_cache_") }
            keys.forEach { defaults.removeObject(forKey: $0) }
        }
    }
}