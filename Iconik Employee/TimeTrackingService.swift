import Foundation
import FirebaseFirestore
import FirebaseAuth

class TimeTrackingService: ObservableObject {
    private let db = Firestore.firestore()
    
    @Published var currentTimeEntry: TimeEntry?
    @Published var isClockIn = false
    @Published var elapsedTime: TimeInterval = 0
    
    private var timer: Timer?
    private var currentUserId: String?
    private var currentOrgId: String?
    
    // Listeners for real-time updates
    private var currentEntryListener: ListenerRegistration?
    private var entriesListener: ListenerRegistration?
    
    // Cache for time entries
    private var timeEntriesCache: [TimeEntry] = []
    private var lastCacheUpdate: Date?
    
    init() {
        setupUser()
        checkCurrentStatus()
    }
    
    deinit {
        currentEntryListener?.remove()
        entriesListener?.remove()
    }
    
    func setupUser() {
        guard let user = Auth.auth().currentUser else { return }
        self.currentUserId = user.uid
        
        // Get organization ID from UserManager
        UserManager.shared.initializeOrganizationID()
        self.currentOrgId = UserDefaults.standard.string(forKey: "userOrganizationID")
    }
    
    func refreshUserAndStatus() {
        setupUser()
        checkCurrentStatus()
    }
    
    // MARK: - Main Clock In/Out Functions
    
    func clockIn(sessionId: String? = nil, notes: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion(false, "User not authenticated")
            return
        }
        
        // Validate notes
        let (isValid, error) = TimeEntryValidator.validateNotes(notes)
        if !isValid {
            completion(false, error)
            return
        }
        
        getCurrentTimeEntry(userId: userId, organizationID: orgId) { [weak self] activeEntry in
            if activeEntry != nil {
                completion(false, "You already have an active time entry. Please clock out first.")
                return
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current
            let currentDate = dateFormatter.string(from: Date())
            
            var timeEntryData: [String: Any] = [
                "userId": userId,
                "organizationID": orgId,
                "clockInTime": FieldValue.serverTimestamp(),
                "date": currentDate,
                "status": "clocked-in",
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            if let sessionId = sessionId {
                timeEntryData["sessionId"] = sessionId
            }
            if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                timeEntryData["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            self?.db.collection("timeEntries").addDocument(data: timeEntryData) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(false, "Failed to clock in: \(error.localizedDescription)")
                    } else {
                        self?.checkCurrentStatus()
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    func clockOut(notes: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion(false, "User not authenticated")
            return
        }
        
        // Validate notes
        let (isValid, error) = TimeEntryValidator.validateNotes(notes)
        if !isValid {
            completion(false, error)
            return
        }
        
        getCurrentTimeEntry(userId: userId, organizationID: orgId) { [weak self] activeEntry in
            guard let activeEntry = activeEntry else {
                completion(false, "No active time entry found. Please clock in first.")
                return
            }
            
            var updateData: [String: Any] = [
                "clockOutTime": FieldValue.serverTimestamp(),
                "status": "clocked-out",
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateData["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            self?.db.collection("timeEntries").document(activeEntry.id).updateData(updateData) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(false, "Failed to clock out: \(error.localizedDescription)")
                    } else {
                        self?.checkCurrentStatus()
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    // MARK: - Status Management
    
    func checkCurrentStatus() {
        guard let userId = currentUserId,
              let orgId = currentOrgId else { return }
        
        getCurrentTimeEntry(userId: userId, organizationID: orgId) { [weak self] activeEntry in
            DispatchQueue.main.async {
                self?.currentTimeEntry = activeEntry
                self?.isClockIn = (activeEntry != nil)
                
                if activeEntry != nil {
                    self?.startTimer()
                } else {
                    self?.stopTimer()
                }
            }
        }
    }
    
    private func startTimer() {
        stopTimer() // Stop any existing timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateElapsedTime()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsedTime = 0
    }
    
    private func updateElapsedTime() {
        guard let currentEntry = currentTimeEntry,
              let clockInTime = currentEntry.clockInTime else {
            elapsedTime = 0
            return
        }
        
        elapsedTime = Date().timeIntervalSince(clockInTime)
    }
    
    func formatElapsedTime() -> String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    // MARK: - Helper Functions
    
    private func getCurrentTimeEntry(userId: String, organizationID: String, completion: @escaping (TimeEntry?) -> Void) {
        // Remove existing listener if any
        currentEntryListener?.remove()
        
        // Use real-time listener for current entry
        currentEntryListener = db.collection("timeEntries")
            .whereField("userId", isEqualTo: userId)
            .whereField("organizationID", isEqualTo: organizationID)
            .whereField("status", isEqualTo: "clocked-in")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error getting current time entry: \(error)")
                    completion(nil)
                    return
                }
                
                if let document = snapshot?.documents.first {
                    let timeEntry = TimeEntry(document: document)
                    
                    completion(timeEntry)
                } else {
                    completion(nil)
                }
            }
    }
    
    func getTimeEntries(startDate: String, endDate: String, completion: @escaping ([TimeEntry]) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion([])
            return
        }
        
        // Check cache first if dates match
        if !timeEntriesCache.isEmpty,
           let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < 300 { // 5 minute cache
            // Filter cached entries by date range
            let filteredEntries = timeEntriesCache.filter { entry in
                let entryDate = entry.date
                return entryDate >= startDate && entryDate <= endDate
            }
            completion(filteredEntries)
            return
        }
        
        // Remove existing listener if any
        entriesListener?.remove()
        
        // Set up real-time listener
        entriesListener = db.collection("timeEntries")
            .whereField("userId", isEqualTo: userId)
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("date", isGreaterThanOrEqualTo: startDate)
            .whereField("date", isLessThanOrEqualTo: endDate)
            .order(by: "date", descending: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 100) // Limit to prevent excessive reads
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error getting time entries: \(error)")
                    completion([])
                    return
                }
                
                let timeEntries = snapshot?.documents.compactMap { document in
                    TimeEntry(document: document)
                } ?? []
                
                // Update cache
                self?.timeEntriesCache = timeEntries
                self?.lastCacheUpdate = Date()
                
                completion(timeEntries)
            }
    }
    
    func getTodayAssignedSessions(completion: @escaping ([Session]) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion([])
            return
        }
        
        // Get today's date in YYYY-MM-DD format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())
        
        db.collection("sessions")
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("date", isEqualTo: today)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error getting sessions: \(error)")
                    completion([])
                    return
                }
                
                let allSessions = snapshot?.documents.compactMap { document in
                    Session(id: document.documentID, data: document.data())
                } ?? []
                
                // Filter sessions assigned to the user
                let assignedSessions = allSessions.filter { session in
                    session.isUserAssigned(userID: userId)
                }
                
                completion(assignedSessions)
            }
    }
    
    // MARK: - Manual Time Entry Operations
    
    func createManualTimeEntry(date: Date, startTime: Date, endTime: Date, sessionId: String? = nil, notes: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion(false, "User not authenticated")
            return
        }
        
        // Validate the manual entry
        let dateString = date.toYYYYMMDD()
        let (isValid, validationError) = TimeEntryValidator.validateManualEntry(date: dateString, startTime: startTime, endTime: endTime)
        if !isValid {
            completion(false, validationError)
            return
        }
        
        // Validate notes
        let (notesValid, notesError) = TimeEntryValidator.validateNotes(notes)
        if !notesValid {
            completion(false, notesError)
            return
        }
        
        // Check for overlaps
        checkTimeOverlap(startTime: startTime, endTime: endTime) { hasOverlap, overlapCount in
            if hasOverlap {
                completion(false, "This time entry overlaps with \(overlapCount) existing entries. Please choose different times.")
                return
            }
            
            // Create the manual time entry data
            var timeEntryData: [String: Any] = [
                "userId": userId,
                "organizationID": orgId,
                "clockInTime": Timestamp(date: startTime),
                "clockOutTime": Timestamp(date: endTime),
                "date": dateString,
                "status": "clocked-out", // Manual entries are always completed
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            if let sessionId = sessionId {
                timeEntryData["sessionId"] = sessionId
            }
            if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                timeEntryData["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Save to Firestore
            self.db.collection("timeEntries").addDocument(data: timeEntryData) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(false, "Failed to create time entry: \(error.localizedDescription)")
                    } else {
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    func updateTimeEntry(entryId: String, startTime: Date, endTime: Date, sessionId: String? = nil, notes: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion(false, "User not authenticated")
            return
        }
        
        // First get the existing entry to validate edit permissions
        db.collection("timeEntries").document(entryId).getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(false, "Error accessing time entry: \(error.localizedDescription)")
                return
            }
            
            guard let document = snapshot, document.exists else {
                completion(false, "Time entry not found")
                return
            }
            
            let timeEntry = TimeEntry(document: document)
            
            // Check if user can edit this entry
            if !TimeEntryValidator.canEditEntry(timeEntry) {
                completion(false, "This time entry cannot be edited (either it's active or outside the 30-day edit window)")
                return
            }
            
            // Check if the entry belongs to the current user
            if timeEntry.userId != userId || timeEntry.organizationID != orgId {
                completion(false, "You don't have permission to edit this time entry")
                return
            }
            
            // Validate the updated times
            let dateString = timeEntry.date
            let (isValid, validationError) = TimeEntryValidator.validateManualEntry(date: dateString, startTime: startTime, endTime: endTime)
            if !isValid {
                completion(false, validationError)
                return
            }
            
            // Validate notes
            let (notesValid, notesError) = TimeEntryValidator.validateNotes(notes)
            if !notesValid {
                completion(false, notesError)
                return
            }
            
            // Check for overlaps (excluding the current entry)
            self?.checkTimeOverlap(startTime: startTime, endTime: endTime, excludeEntryId: entryId) { hasOverlap, overlapCount in
                if hasOverlap {
                    completion(false, "This time entry would overlap with \(overlapCount) existing entries. Please choose different times.")
                    return
                }
                
                // Update the time entry
                var updateData: [String: Any] = [
                    "clockInTime": Timestamp(date: startTime),
                    "clockOutTime": Timestamp(date: endTime),
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                
                if let sessionId = sessionId {
                    updateData["sessionId"] = sessionId
                } else {
                    updateData["sessionId"] = FieldValue.delete()
                }
                
                if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updateData["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    updateData["notes"] = FieldValue.delete()
                }
                
                self?.db.collection("timeEntries").document(entryId).updateData(updateData) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion(false, "Failed to update time entry: \(error.localizedDescription)")
                        } else {
                            completion(true, nil)
                        }
                    }
                }
            }
        }
    }
    
    func deleteTimeEntry(entryId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion(false, "User not authenticated")
            return
        }
        
        // First get the existing entry to validate delete permissions
        db.collection("timeEntries").document(entryId).getDocument { [weak self] snapshot, error in
            if let error = error {
                completion(false, "Error accessing time entry: \(error.localizedDescription)")
                return
            }
            
            guard let document = snapshot, document.exists else {
                completion(false, "Time entry not found")
                return
            }
            
            let timeEntry = TimeEntry(document: document)
            
            // Check if user can delete this entry
            if !TimeEntryValidator.canEditEntry(timeEntry) {
                completion(false, "This time entry cannot be deleted (either it's active or outside the 30-day edit window)")
                return
            }
            
            // Check if the entry belongs to the current user
            if timeEntry.userId != userId || timeEntry.organizationID != orgId {
                completion(false, "You don't have permission to delete this time entry")
                return
            }
            
            // Delete the entry
            self?.db.collection("timeEntries").document(entryId).delete { error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(false, "Failed to delete time entry: \(error.localizedDescription)")
                    } else {
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    func getSessionsForDate(_ date: Date, completion: @escaping ([Session]) -> Void) {
        guard let orgId = currentOrgId else {
            completion([])
            return
        }
        
        let dateString = date.toYYYYMMDD()
        
        db.collection("sessions")
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("date", isEqualTo: dateString)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error getting sessions for date: \(error)")
                    completion([])
                    return
                }
                
                let sessions = snapshot?.documents.compactMap { document in
                    Session(id: document.documentID, data: document.data())
                } ?? []
                
                completion(sessions)
            }
    }
    
    // MARK: - Overlap Detection
    
    func checkTimeOverlap(startTime: Date, endTime: Date, excludeEntryId: String? = nil, completion: @escaping (Bool, Int) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion(false, 0)
            return
        }
        
        // Get date string for the entry
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: startTime)
        
        db.collection("timeEntries")
            .whereField("userId", isEqualTo: userId)
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("date", isEqualTo: dateString)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error checking overlap: \(error)")
                    completion(false, 0)
                    return
                }
                
                var overlapCount = 0
                let entries = snapshot?.documents.compactMap { document in
                    TimeEntry(document: document)
                } ?? []
                
                for entry in entries {
                    // Skip the entry being edited
                    if let excludeId = excludeEntryId, entry.id == excludeId {
                        continue
                    }
                    
                    // Skip entries without proper times
                    guard let entryStart = entry.clockInTime,
                          let entryEnd = entry.clockOutTime else {
                        continue
                    }
                    
                    // Check for overlap
                    if startTime < entryEnd && endTime > entryStart {
                        overlapCount += 1
                    }
                }
                
                completion(overlapCount > 0, overlapCount)
            }
    }
}