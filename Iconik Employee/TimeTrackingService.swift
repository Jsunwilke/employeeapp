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
    private var dashboardEntriesListener: ListenerRegistration?
    
    init() {
        setupUser()
        checkCurrentStatus()
    }
    
    deinit {
        currentEntryListener?.remove()
        entriesListener?.remove()
        dashboardEntriesListener?.remove()
    }
    
    func setupUser() {
        print("🔧 TimeTrackingService.setupUser called")
        guard let user = Auth.auth().currentUser else { 
            print("❌ TimeTrackingService.setupUser: No authenticated user")
            return 
        }
        self.currentUserId = user.uid
        print("✅ TimeTrackingService.setupUser: userId set to \(user.uid)")
        
        // Get organization ID from UserManager
        UserManager.shared.initializeOrganizationID()
        self.currentOrgId = UserDefaults.standard.string(forKey: "userOrganizationID")
        print("✅ TimeTrackingService.setupUser: orgId set to \(self.currentOrgId ?? "nil")")
    }
    
    func refreshUserAndStatus() {
        setupUser()
        
        // If orgId is still nil, try to get it from UserDefaults again
        // This helps when UserManager has fetched it asynchronously
        if currentOrgId == nil {
            currentOrgId = UserDefaults.standard.string(forKey: "userOrganizationID")
            if currentOrgId != nil {
                print("✅ TimeTrackingService.refreshUserAndStatus: orgId updated to \(currentOrgId!)")
            }
        }
        
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
                
                // Fetch session name and then create the time entry
                SessionService.shared.getSessionDisplayName(for: sessionId) { sessionName in
                    timeEntryData["sessionName"] = sessionName
                    
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
            } else {
                // No session ID, proceed without it
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
    
    // Manual clock out with specific date/time for cross-midnight support
    func clockOutManual(clockOutDateTime: Date, notes: String? = nil, completion: @escaping (Bool, String?) -> Void) {
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
        
        // Validate clock out time is not in the future
        if clockOutDateTime > Date() {
            completion(false, "Clock out time cannot be in the future")
            return
        }
        
        getCurrentTimeEntry(userId: userId, organizationID: orgId) { [weak self] activeEntry in
            guard let activeEntry = activeEntry else {
                completion(false, "No active time entry found. Please clock in first.")
                return
            }
            
            // Validate clock out is after clock in
            guard let clockInTime = activeEntry.clockInTime else {
                completion(false, "Invalid clock in time")
                return
            }
            
            if clockOutDateTime <= clockInTime {
                completion(false, "Clock out time must be after clock in time")
                return
            }
            
            // Validate shift is not longer than 24 hours
            let duration = clockOutDateTime.timeIntervalSince(clockInTime)
            if duration > 24 * 60 * 60 { // 24 hours in seconds
                completion(false, "Shift duration cannot exceed 24 hours")
                return
            }
            
            // Format the clock out date for the date field
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current
            let clockOutDateString = dateFormatter.string(from: clockOutDateTime)
            
            var updateData: [String: Any] = [
                "clockOutTime": Timestamp(date: clockOutDateTime),
                "status": "clocked-out",
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            // Update the date field if clock out is on a different day
            let clockInDateString = dateFormatter.string(from: clockInTime)
            if clockOutDateString != clockInDateString {
                // Keep the original clock in date, but note this is a cross-midnight entry
                updateData["crossMidnight"] = true
            }
            
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
    
    // MARK: - Migration Functions
    
    // Update existing time entries with session names
    func updateExistingEntriesWithSessionNames() {
        guard let userId = currentUserId,
              let orgId = currentOrgId else { 
            print("⚠️ Cannot update session names: missing userId or orgId")
            return 
        }
        
        print("🔄 Starting migration to add session names to time entries for user: \(userId), org: \(orgId)")
        
        // Fetch time entries that have sessionId but no sessionName
        db.collection("timeEntries")
            .whereField("userId", isEqualTo: userId)
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("sessionId", isNotEqualTo: NSNull())
            .getDocuments { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("❌ Error fetching time entries for migration: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                print("📊 Found \(documents.count) time entries to check")
                var entriesNeedingUpdate = 0
                
                // Process each document
                for document in documents {
                    let data = document.data()
                    
                    // Check if it already has a sessionName
                    if data["sessionName"] != nil {
                        print("✓ Entry \(document.documentID) already has sessionName")
                        continue
                    }
                    
                    // Get sessionId and fetch the session name
                    if let sessionId = data["sessionId"] as? String {
                        entriesNeedingUpdate += 1
                        print("🔍 Entry \(document.documentID) needs update - sessionId: '\(sessionId)' (length: \(sessionId.count))")
                        
                        // Run diagnostic on first entry only
                        if entriesNeedingUpdate == 1 {
                            self?.checkSessionAvailability(for: sessionId)
                        }
                        
                        SessionService.shared.getSessionDisplayName(for: sessionId) { sessionName in
                            print("📝 Got session name '\(sessionName)' for sessionId: \(sessionId)")
                            
                            // Update the document with session name
                            self?.db.collection("timeEntries").document(document.documentID)
                                .updateData(["sessionName": sessionName]) { error in
                                    if let error = error {
                                        print("❌ Error updating session name for entry \(document.documentID): \(error.localizedDescription)")
                                    } else {
                                        print("✅ Successfully updated session name for entry \(document.documentID) to: \(sessionName)")
                                    }
                                }
                        }
                    }
                }
                
                print("📊 Migration summary: \(entriesNeedingUpdate) entries need session name updates")
            }
    }
    
    // Diagnostic function to check session availability
    func checkSessionAvailability(for sessionId: String) {
        print("\n🔍 DIAGNOSTIC: Checking session availability for ID: '\(sessionId)'")
        
        // First, try to fetch from sessions collection
        db.collection("sessions").document(sessionId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error accessing sessions collection: \(error.localizedDescription)")
            } else if let snapshot = snapshot {
                if snapshot.exists {
                    print("✅ Session EXISTS in 'sessions' collection")
                    if let data = snapshot.data() {
                        print("   - Organization ID: \(data["organizationID"] ?? "none")")
                        print("   - School Name: \(data["schoolName"] ?? "none")")
                        print("   - Date: \(data["date"] ?? "none")")
                    }
                } else {
                    print("❌ Session NOT FOUND in 'sessions' collection")
                    
                    // Try to find sessions with similar IDs
                    print("🔍 Searching for similar session IDs...")
                    self.db.collection("sessions")
                        .limit(to: 10)
                        .getDocuments { snapshot, error in
                            if let documents = snapshot?.documents {
                                print("   Sample session IDs in database:")
                                for doc in documents.prefix(5) {
                                    print("   - \(doc.documentID)")
                                }
                            }
                        }
                }
            }
        }
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
        print("🔍 TimeTrackingService.getTimeEntries called - startDate: \(startDate), endDate: \(endDate)")
        print("   - currentUserId: \(currentUserId ?? "nil")")
        print("   - currentOrgId: \(currentOrgId ?? "nil")")
        
        // If orgId is nil, try to refresh it from UserDefaults
        if currentOrgId == nil {
            currentOrgId = UserDefaults.standard.string(forKey: "userOrganizationID")
            if currentOrgId != nil {
                print("✅ TimeTrackingService.getTimeEntries: orgId refreshed to \(currentOrgId!)")
            }
        }
        
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            print("❌ TimeTrackingService.getTimeEntries: Missing userId or orgId, returning empty array")
            completion([])
            return
        }
        
        // Use a one-time query instead of listener for dashboard queries
        db.collection("timeEntries")
            .whereField("userId", isEqualTo: userId)
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("date", isGreaterThanOrEqualTo: startDate)
            .whereField("date", isLessThanOrEqualTo: endDate)
            .order(by: "date", descending: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 100) // Limit to prevent excessive reads
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ TimeTrackingService.getTimeEntries: Error - \(error)")
                    completion([])
                    return
                }
                
                let timeEntries = snapshot?.documents.compactMap { document in
                    TimeEntry(document: document)
                } ?? []
                
                print("✅ TimeTrackingService.getTimeEntries: Query complete")
                print("   - Date range: \(startDate) to \(endDate)")
                print("   - Found \(timeEntries.count) entries")
                for entry in timeEntries.prefix(3) {
                    print("   - Entry: date=\(entry.date), duration=\(entry.durationInHours)hrs")
                }
                
                completion(timeEntries)
            }
    }
    
    // Real-time listener for time entries with cache support
    func listenForTimeEntries(startDate: String, endDate: String, completion: @escaping ([TimeEntry]) -> Void) {
        print("🔍 TimeTrackingService.listenForTimeEntries called - startDate: \(startDate), endDate: \(endDate)")
        print("   - currentUserId: \(currentUserId ?? "nil")")
        print("   - currentOrgId: \(currentOrgId ?? "nil")")
        
        // If orgId is nil, try to refresh it from UserDefaults
        if currentOrgId == nil {
            currentOrgId = UserDefaults.standard.string(forKey: "userOrganizationID")
            if currentOrgId != nil {
                print("✅ TimeTrackingService.listenForTimeEntries: orgId refreshed to \(currentOrgId!)")
            }
        }
        
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            print("❌ TimeTrackingService.listenForTimeEntries: Missing userId or orgId, returning empty array")
            completion([])
            return
        }
        
        // Remove existing listener if any
        dashboardEntriesListener?.remove()
        
        // Set up real-time listener with cache
        dashboardEntriesListener = db.collection("timeEntries")
            .whereField("userId", isEqualTo: userId)
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("date", isGreaterThanOrEqualTo: startDate)
            .whereField("date", isLessThanOrEqualTo: endDate)
            .order(by: "date", descending: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener(includeMetadataChanges: false) { snapshot, error in
                if let error = error {
                    print("❌ TimeTrackingService.listenForTimeEntries: Error - \(error)")
                    completion([])
                    return
                }
                
                guard let snapshot = snapshot else {
                    print("❌ TimeTrackingService.listenForTimeEntries: No snapshot")
                    completion([])
                    return
                }
                
                // Check if data is from cache or server
                let source = snapshot.metadata.isFromCache ? "cache" : "server"
                print("📊 TimeTrackingService.listenForTimeEntries: Data from \(source)")
                
                let timeEntries = snapshot.documents.compactMap { document in
                    TimeEntry(document: document)
                }
                
                print("✅ TimeTrackingService.listenForTimeEntries: Update received")
                print("   - Source: \(source)")
                print("   - Date range: \(startDate) to \(endDate)")
                print("   - Found \(timeEntries.count) entries")
                
                completion(timeEntries)
            }
    }
    
    // Clean up dashboard listener when not needed
    func stopListeningForDashboardEntries() {
        dashboardEntriesListener?.remove()
        dashboardEntriesListener = nil
        print("🛑 TimeTrackingService: Stopped listening for dashboard entries")
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
                
                // Fetch session name and then create the time entry
                SessionService.shared.getSessionDisplayName(for: sessionId) { sessionName in
                    timeEntryData["sessionName"] = sessionName
                    
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
            } else {
                // No session ID, proceed without it
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
    
    // Real-time listener version for views that need live updates
    func listenToTimeEntries(startDate: String, endDate: String, completion: @escaping ([TimeEntry]) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion([])
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
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to time entries: \(error)")
                    completion([])
                    return
                }
                
                let timeEntries = snapshot?.documents.compactMap { document in
                    TimeEntry(document: document)
                } ?? []
                
                completion(timeEntries)
            }
    }
    
    func getAvailableSessionsForJobBox(completion: @escaping ([Session]) -> Void) {
        guard let orgId = currentOrgId else {
            completion([])
            return
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoWeeksFromNow = calendar.date(byAdding: .day, value: 14, to: today)!
        
        // Format dates for comparison
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)
        let twoWeeksString = dateFormatter.string(from: twoWeeksFromNow)
        
        db.collection("sessions")
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("status", isEqualTo: "scheduled")
            .whereField("date", isGreaterThanOrEqualTo: todayString)
            .whereField("date", isLessThanOrEqualTo: twoWeeksString)
            .getDocuments(completion: { snapshot, error in
                if let error = error {
                    print("Error getting available sessions for job box: \(error)")
                    completion([])
                    return
                }
                
                let sessions: [Session] = snapshot?.documents.compactMap { document in
                    let data = document.data()
                    // Filter out sessions that are already assigned to a job box
                    if let hasJobBoxAssigned = data["hasJobBoxAssigned"] as? Bool, hasJobBoxAssigned {
                        return nil
                    }
                    return Session(id: document.documentID, data: data)
                } ?? []
                
                // Sort by date and time
                let sortedSessions = sessions.sorted { (session1, session2) in
                    if let date1 = session1.date, let date2 = session2.date, date1 != date2 {
                        return date1 < date2
                    }
                    if let time1 = session1.startTime, let time2 = session2.startTime {
                        return time1 < time2
                    }
                    return false
                }
                
                completion(sortedSessions)
            })
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