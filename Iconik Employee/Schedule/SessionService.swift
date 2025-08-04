import Foundation
import FirebaseFirestore
import FirebaseAuth
import Network
import SwiftUI
import Combine

class SessionService: ObservableObject {
    // Singleton instance
    static let shared = SessionService()
    
    private let db = Firestore.firestore()
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected: Bool = true
    @Published var lastError: String?
    @Published var isRetrying: Bool = false
    
    // Cache for sessions
    private var sessionsCache: [Session] = []
    private var lastCacheUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    // Track active listeners to prevent duplicates
    private var activeListeners: [String: ListenerRegistration] = [:]
    private let listenerQueue = DispatchQueue(label: "SessionServiceListeners")
    
    // Pagination support
    private let pageSize = 50
    private var lastDocument: DocumentSnapshot?
    private var hasMorePages = true
    
    private init() {
        setupNetworkMonitoring()
    }
    
    // MARK: - Session Retrieval
    
    // Listen for sessions in real-time for current user's organization
    func listenForSessions(completion: @escaping ([Session]) -> Void) -> ListenerRegistration {
        return listenForSessions(includeUnpublished: false, completion: completion)
    }
    
    // Listen for sessions with option to include unpublished (for admin/manager)
    func listenForSessions(includeUnpublished: Bool, completion: @escaping ([Session]) -> Void) -> ListenerRegistration {
        #if DEBUG
        print("🔄 SessionService: listenForSessions called (includeUnpublished: \(includeUnpublished))")
        #endif
        
        // Use cached organization ID if available, otherwise get it
        let cachedOrgID = UserManager.shared.getCachedOrganizationID()
        #if DEBUG
        print("🔄 SessionService: cached org ID = '\(cachedOrgID)'")
        #endif
        
        if !cachedOrgID.isEmpty {
            #if DEBUG
            print("🔄 SessionService: Using cached org ID")
            #endif
            return listenForSessionsWithOrganizationID(cachedOrgID, includeUnpublished: includeUnpublished, completion: completion)
        } else {
            #if DEBUG
            print("🔄 SessionService: No cached org ID, fetching async")
            #endif
            
            // Create a dummy listener that we'll replace once we have the org ID
            var realListener: ListenerRegistration?
            
            // Get organization ID and then set up listener
            UserManager.shared.getCurrentUserOrganizationID { organizationID in
                #if DEBUG
                print("🔄 SessionService: Async org ID fetch completed: '\(organizationID ?? "nil")'")
                #endif
                guard let orgID = organizationID else {
                    #if DEBUG
                    print("🔐 Cannot load sessions: no organization ID found")
                    #endif
                    completion([])
                    return
                }
                
                // Now set up the real listener with the organization ID
                realListener = self.listenForSessionsWithOrganizationID(orgID, includeUnpublished: includeUnpublished, completion: completion)
            }
            
            // Return a wrapper that will remove the real listener when called
            return ListenerRegistrationWrapper {
                realListener?.remove()
            }
        }
    }
    
    // Helper method to listen for sessions with a specific organization ID
    private func listenForSessionsWithOrganizationID(_ organizationID: String, includeUnpublished: Bool = false, completion: @escaping ([Session]) -> Void) -> ListenerRegistration {
        let listenerKey = "sessions-org-\(organizationID)-unpub-\(includeUnpublished)"
        
        // Check if we already have an active listener for this query
        var existingListener: ListenerRegistration?
        listenerQueue.sync {
            existingListener = activeListeners[listenerKey]
        }
        
        if existingListener != nil {
            #if DEBUG
            print("📅 Reusing existing listener for org: \(organizationID)")
            #endif
            // Return cached data immediately if available
            if !sessionsCache.isEmpty {
                completion(sessionsCache)
            }
            // Return wrapper that removes reference but doesn't actually remove the shared listener
            return ListenerRegistrationWrapper { [weak self] in
                self?.listenerQueue.sync {
                    // Don't remove the actual listener as others might be using it
                    #if DEBUG
                    print("📅 Listener reference removed but keeping shared listener active")
                    #endif
                }
            }
        }
        
        // Check cache first
        if let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheValidityDuration,
           !sessionsCache.isEmpty {
            #if DEBUG
            print("📅 Using cached sessions: \(sessionsCache.count) sessions")
            #endif
            completion(sessionsCache)
            
            // Return a dummy listener that does nothing when removed
            // This prevents creating a new listener when we have valid cache
            return ListenerRegistrationWrapper {
                #if DEBUG
                print("📅 Dummy listener removed (was using cache)")
                #endif
            }
        }
        
        // Create new listener
        print("📅 SessionService: Creating listener for org '\(organizationID)' (includeUnpublished: \(includeUnpublished))")
        
        // Create base query
        var query = db.collection("sessions")
            .whereField("organizationID", isEqualTo: organizationID)
        
        // Only add isPublished filter for non-admin/manager users
        if !includeUnpublished {
            query = query.whereField("isPublished", isEqualTo: true)
            print("📅 SessionService: Filtering for published sessions only")
        } else {
            print("📅 SessionService: Including ALL sessions (no isPublished filter)")
        }
        
        let listener = query.addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("🔥 SessionService Error: \(error)")
                    print("🔥 Error code: \((error as NSError).code)")
                    print("🔥 Error domain: \((error as NSError).domain)")
                    
                    // Check if it's a missing index error
                    if error.localizedDescription.contains("index") {
                        print("🔥 MISSING INDEX ERROR - Create composite index for: organizationID + isPublished")
                    }
                    
                    self?.handleError(error, operation: "Listening for sessions")
                    // Return cached data on error if available
                    if let self = self, !self.sessionsCache.isEmpty {
                        completion(self.sessionsCache)
                    } else {
                        completion([])
                    }
                    return
                }
                
                // Clear any previous errors on successful data load
                DispatchQueue.main.async {
                    self?.lastError = nil
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                print("📅 Query returned \(documents.count) documents")
                
                let sessions = documents.map { document in
                    let data = document.data()
                    print("🔄 Listener update - Session ID: \(document.documentID), isPublished: \(data["isPublished"] ?? "nil")")
                    return Session(id: document.documentID, data: data)
                }
                
                // Debug: Log session details
                print("📅 SessionService listener: Processing \(sessions.count) sessions")
                for session in sessions {
                    print("📅 Session: \(session.schoolName) - ID: \(session.id) - isPublished: \(session.isPublished)")
                }
                
                // Update cache
                self?.sessionsCache = sessions
                self?.lastCacheUpdate = Date()
                
                print("📅 Loaded \(sessions.count) sessions for organization \(organizationID)")
                completion(sessions)
            }
        
        // Store the listener
        listenerQueue.sync {
            activeListeners[listenerKey] = listener
        }
        
        // Return wrapper that properly manages the listener
        return ListenerRegistrationWrapper { [weak self] in
            self?.listenerQueue.sync {
                // Only remove if this is the actual listener owner
                if self?.activeListeners[listenerKey] != nil {
                    self?.activeListeners[listenerKey]?.remove()
                    self?.activeListeners.removeValue(forKey: listenerKey)
                    #if DEBUG
                    print("📅 Removed listener for key: \(listenerKey)")
                    #endif
                }
            }
        }
    }
    
    // Listen for a specific session by ID
    func listenForSession(sessionId: String, completion: @escaping (Session?) -> Void) -> ListenerRegistration {
        return db.collection("sessions").document(sessionId)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    self?.handleError(error, operation: "Listening for session \(sessionId)")
                    completion(nil)
                    return
                }
                
                // Clear any previous errors on successful data load
                DispatchQueue.main.async {
                    self?.lastError = nil
                }
                
                guard let document = snapshot, document.exists,
                      let data = document.data() else {
                    completion(nil)
                    return
                }
                
                let session = Session(id: document.documentID, data: data)
                
                print("📅 Updated session \(session.schoolName) - ID: \(session.id)")
                print("📅 Session isPublished: \(session.isPublished)")
                print("📅 Raw data isPublished: \(data["isPublished"] ?? "nil")")
                completion(session)
            }
    }
    
    // Listen for sessions within a date range for current user's organization
    func listenForSessions(from startDate: Date, to endDate: Date, completion: @escaping ([Session]) -> Void) -> ListenerRegistration {
        return listenForSessions(from: startDate, to: endDate, includeUnpublished: false, completion: completion)
    }
    
    // Listen for sessions within a date range with option to include unpublished
    func listenForSessions(from startDate: Date, to endDate: Date, includeUnpublished: Bool, completion: @escaping ([Session]) -> Void) -> ListenerRegistration {
        // Convert dates to string format for Firestore filtering
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)
        
        let cachedOrgID = UserManager.shared.getCachedOrganizationID()
        
        if !cachedOrgID.isEmpty {
            var query = db.collection("sessions")
                .whereField("organizationID", isEqualTo: cachedOrgID)
                .whereField("date", isGreaterThanOrEqualTo: startDateString)
                .whereField("date", isLessThan: endDateString)
            
            // Only filter by isPublished if we don't want unpublished sessions
            if !includeUnpublished {
                query = query.whereField("isPublished", isEqualTo: true)
            }
            
            return query.addSnapshotListener { [weak self] snapshot, error in
                    if let error = error {
                        self?.handleError(error, operation: "Listening for sessions in date range")
                        completion([])
                        return
                    }
                    
                    // Clear any previous errors on successful data load
                    DispatchQueue.main.async {
                        self?.lastError = nil
                    }
                    
                    guard let documents = snapshot?.documents else {
                        completion([])
                        return
                    }
                    
                    let sessions = documents.map { document in
                        Session(id: document.documentID, data: document.data())
                    }
                    
                    completion(sessions)
                }
        } else {
            // Create a dummy listener that we'll replace once we have the org ID
            var realListener: ListenerRegistration?
            
            // Get organization ID first
            UserManager.shared.getCurrentUserOrganizationID { organizationID in
                guard let orgID = organizationID else {
                    #if DEBUG
                    print("🔐 Cannot load sessions: no organization ID found")
                    #endif
                    completion([])
                    return
                }
                
                var query = self.db.collection("sessions")
                    .whereField("organizationID", isEqualTo: orgID)
                    .whereField("date", isGreaterThanOrEqualTo: startDateString)
                    .whereField("date", isLessThan: endDateString)
                
                // Only filter by isPublished if we don't want unpublished sessions
                if !includeUnpublished {
                    query = query.whereField("isPublished", isEqualTo: true)
                }
                
                realListener = query.addSnapshotListener { snapshot, error in
                        if let error = error {
                            print("Error listening for sessions in date range: \(error.localizedDescription)")
                            completion([])
                            return
                        }
                        
                        guard let documents = snapshot?.documents else {
                            completion([])
                            return
                        }
                        
                        let sessions = documents.map { document in
                            Session(id: document.documentID, data: document.data())
                        }
                        
                        
                        completion(sessions)
                    }
            }
            
            // Return a wrapper that will remove the real listener when called
            return ListenerRegistrationWrapper {
                realListener?.remove()
            }
        }
    }
    
    // Listen for sessions for a specific employee in current user's organization
    func listenForSessions(forEmployee employeeName: String, completion: @escaping ([Session]) -> Void) -> ListenerRegistration {
        let cachedOrgID = UserManager.shared.getCachedOrganizationID()
        
        if !cachedOrgID.isEmpty {
            return db.collection("sessions")
                .whereField("organizationID", isEqualTo: cachedOrgID)
                .whereField("isPublished", isEqualTo: true)
                .whereField("employeeName", isEqualTo: employeeName)
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        print("Error listening for sessions for employee: \(error.localizedDescription)")
                        completion([])
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        completion([])
                        return
                    }
                    
                    let sessions = documents.map { document in
                        Session(id: document.documentID, data: document.data())
                    }
                    
                    completion(sessions)
                }
        } else {
            // Create a dummy listener that we'll replace once we have the org ID
            var realListener: ListenerRegistration?
            
            UserManager.shared.getCurrentUserOrganizationID { organizationID in
                guard let orgID = organizationID else {
                    completion([])
                    return
                }
                
                realListener = self.db.collection("sessions")
                    .whereField("organizationID", isEqualTo: orgID)
                    .whereField("employeeName", isEqualTo: employeeName)
                    .addSnapshotListener { snapshot, error in
                        if let error = error {
                            print("Error listening for sessions for employee: \(error.localizedDescription)")
                            completion([])
                            return
                        }
                        
                        guard let documents = snapshot?.documents else {
                            completion([])
                            return
                        }
                        
                        let sessions = documents.map { document in
                            Session(id: document.documentID, data: document.data())
                        }
                        
                        
                        completion(sessions)
                    }
            }
            
            // Return a wrapper that will remove the real listener when called
            return ListenerRegistrationWrapper {
                realListener?.remove()
            }
        }
    }
    
    // Get sessions for a specific week in current user's organization
    func getSessionsForWeek(startOfWeek: Date, completion: @escaping ([Session]) -> Void) {
        let calendar = Calendar.current
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) ?? startOfWeek
        
        // Convert dates to string format for Firestore filtering
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateString = dateFormatter.string(from: startOfWeek)
        let endDateString = dateFormatter.string(from: endOfWeek)
        
        UserManager.shared.getCurrentUserOrganizationID { organizationID in
            guard let orgID = organizationID else {
                print("🔐 Cannot get sessions: no organization ID found")
                completion([])
                return
            }
            
            self.db.collection("sessions")
                .whereField("organizationID", isEqualTo: orgID)
                .whereField("isPublished", isEqualTo: true)
                .whereField("date", isGreaterThanOrEqualTo: startDateString)
                .whereField("date", isLessThan: endDateString)
                .getDocuments { snapshot, error in
                    if let error = error {
                        print("Error getting sessions for week: \(error.localizedDescription)")
                        completion([])
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        completion([])
                        return
                    }
                    
                    let sessions = documents.map { document in
                        Session(id: document.documentID, data: document.data())
                    }
                    
                    completion(sessions)
                }
        }
    }
    
    // MARK: - Session Management
    
    // Validate session input
    func validateSessionInput(formData: SessionFormData) -> [String: String] {
        var errors: [String: String] = [:]
        
        if formData.schoolId.isEmpty {
            errors["schoolId"] = "School is required"
        }
        
        if formData.date.isEmpty {
            errors["date"] = "Date is required"
        }
        
        if formData.startTime.isEmpty {
            errors["startTime"] = "Start time is required"
        }
        
        if formData.endTime.isEmpty {
            errors["endTime"] = "End time is required"
        }
        
        if formData.sessionTypes.isEmpty {
            errors["sessionTypes"] = "At least one session type is required"
        }
        
        if formData.sessionTypes.contains("other") && formData.customSessionType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["customSessionType"] = "Please specify a custom session type"
        }
        
        // Validate time range
        if !formData.startTime.isEmpty && !formData.endTime.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            
            if let start = formatter.date(from: formData.startTime),
               let end = formatter.date(from: formData.endTime),
               end <= start {
                errors["endTime"] = "End time must be after start time"
            }
        }
        
        return errors
    }
    
    // Calculate session color based on order within the day
    func calculateSessionColor(organizationID: String, date: String, startTime: String, isTimeOff: Bool = false) async throws -> String {
        // Time off sessions always get gray
        if isTimeOff {
            return "#666"
        }
        
        // Get existing sessions for the same date
        let query = db.collection("sessions")
            .whereField("organizationID", isEqualTo: organizationID)
            .whereField("date", isEqualTo: date)
        
        let snapshot = try await query.getDocuments()
        
        // Filter out time-off sessions and convert to array
        var existingSessions = snapshot.documents
            .compactMap { doc -> (id: String, startTime: String, schoolId: String)? in
                let data = doc.data()
                guard let isTimeOff = data["isTimeOff"] as? Bool, !isTimeOff,
                      let startTime = data["startTime"] as? String,
                      let schoolId = data["schoolId"] as? String else { return nil }
                return (id: doc.documentID, startTime: startTime, schoolId: schoolId)
            }
        
        // Add the new session temporarily for color calculation
        existingSessions.append((id: "temp", startTime: startTime, schoolId: ""))
        
        // Sort by start time, then by school ID for consistency
        existingSessions.sort { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            return lhs.schoolId < rhs.schoolId
        }
        
        // Find the index of our new session
        let orderIndex = existingSessions.firstIndex { $0.id == "temp" } ?? 0
        
        // Get organization colors or use defaults
        let organization = try await OrganizationService.shared.getOrganization(organizationID: organizationID)
        let customColors = organization?.sessionOrderColors
        let defaultColors = [
            "#3b82f6", "#10b981", "#8b5cf6", "#f59e0b",
            "#ef4444", "#06b6d4", "#8b5a3c", "#6b7280"
        ]
        let colors = (customColors?.count ?? 0) >= 8 ? customColors! : defaultColors
        
        return colors[min(orderIndex, colors.count - 1)]
    }
    
    // Create a new session
    func createSession(organizationID: String, formData: SessionFormData, currentUser: FirebaseAuth.User, teamMembers: [TeamMember], schools: [School]) async throws -> String {
        // Get organization settings
        let organization = try await OrganizationService.shared.getOrganization(organizationID: organizationID)
        let enablePublishing = organization?.enableSessionPublishing ?? false
        
        // Calculate session color
        let sessionColor = try await calculateSessionColor(
            organizationID: organizationID,
            date: formData.date,
            startTime: formData.startTime,
            isTimeOff: formData.isTimeOff
        )
        
        // Get photographer details
        let selectedPhotographers: [SessionPhotographer] = formData.photographerIds.compactMap { photographerId in
            guard let member = teamMembers.first(where: { $0.id == photographerId }) else { return nil }
            return SessionPhotographer(
                id: member.id,
                name: member.fullName,
                email: member.email,
                notes: formData.photographerNotes[member.id] ?? ""
            )
        }
        
        // Get school name
        let schoolName = schools.first { $0.id == formData.schoolId }?.value ?? ""
        
        // Prepare session data
        var sessionData: [String: Any] = [
            "organizationID": organizationID,
            "schoolId": formData.schoolId,
            "schoolName": schoolName,
            "date": formData.date,
            "startTime": formData.startTime,
            "endTime": formData.endTime,
            "sessionTypes": formData.sessionTypes,
            "notes": formData.notes,
            "status": formData.status,
            "sessionColor": sessionColor,
            "createdAt": FieldValue.serverTimestamp(),
            "createdBy": [
                "id": currentUser.uid,
                "name": currentUser.displayName ?? "\(currentUser.firstName ?? "") \(currentUser.lastName ?? "")",
                "email": currentUser.email ?? ""
            ]
        ]
        
        // Add photographers array
        sessionData["photographers"] = selectedPhotographers.map { photographer in
            [
                "id": photographer.id,
                "name": photographer.name,
                "email": photographer.email,
                "notes": photographer.notes
            ]
        }
        
        // Add optional fields
        if formData.sessionTypes.contains("other") {
            sessionData["customSessionType"] = formData.customSessionType.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if formData.isTimeOff {
            sessionData["isTimeOff"] = true
        }
        
        if enablePublishing {
            sessionData["isPublished"] = false
        } else {
            sessionData["isPublished"] = true
        }
        
        // Create the session
        let docRef = try await db.collection("sessions").addDocument(data: sessionData)
        
        // Recalculate colors for all sessions on this date
        try await recalculateSessionColorsForDate(
            organizationID: organizationID,
            date: formData.date,
            organization: organization
        )
        
        return docRef.documentID
    }
    
    // Update an existing session
    func updateSession(sessionId: String, formData: SessionFormData, teamMembers: [TeamMember], schools: [School]) async throws {
        // Get current session data
        let doc = try await db.collection("sessions").document(sessionId).getDocument()
        guard let currentData = doc.data() else {
            throw SessionError.notFound
        }
        
        let currentDate = currentData["date"] as? String ?? ""
        let currentStartTime = currentData["startTime"] as? String ?? ""
        let organizationID = currentData["organizationID"] as? String ?? ""
        
        // Check if date or time changed (affects color ordering)
        let affectsOrdering = formData.date != currentDate || formData.startTime != currentStartTime
        
        // Get photographer details
        let selectedPhotographers: [[String: Any]] = formData.photographerIds.compactMap { photographerId in
            guard let member = teamMembers.first(where: { $0.id == photographerId }) else { return nil }
            return [
                "id": member.id,
                "name": member.fullName,
                "email": member.email,
                "notes": formData.photographerNotes[member.id] ?? ""
            ]
        }
        
        // Get school name
        let schoolName = schools.first { $0.id == formData.schoolId }?.value ?? ""
        
        // Prepare update data
        var updateData: [String: Any] = [
            "schoolId": formData.schoolId,
            "schoolName": schoolName,
            "date": formData.date,
            "startTime": formData.startTime,
            "endTime": formData.endTime,
            "sessionTypes": formData.sessionTypes,
            "photographers": selectedPhotographers,
            "notes": formData.notes,
            "status": formData.status,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        // Handle custom session type
        if formData.sessionTypes.contains("other") {
            updateData["customSessionType"] = formData.customSessionType.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            updateData["customSessionType"] = FieldValue.delete()
        }
        
        // Update the session
        try await db.collection("sessions").document(sessionId).updateData(updateData)
        
        // Recalculate colors if ordering changed
        if affectsOrdering {
            // Recalculate for old date if date changed
            if currentDate != formData.date {
                try await recalculateSessionColorsForDate(
                    organizationID: organizationID,
                    date: currentDate
                )
            }
            
            // Recalculate for new date
            try await recalculateSessionColorsForDate(
                organizationID: organizationID,
                date: formData.date
            )
        }
    }
    
    // Recalculate colors for all sessions on a specific date
    private func recalculateSessionColorsForDate(organizationID: String, date: String, organization: Organization? = nil) async throws {
        // Get organization if not provided
        let org: Organization?
        if let organization = organization {
            org = organization
        } else {
            org = try await OrganizationService.shared.getOrganization(organizationID: organizationID)
        }
        
        // Get all sessions for this date
        let query = db.collection("sessions")
            .whereField("organizationID", isEqualTo: organizationID)
            .whereField("date", isEqualTo: date)
        
        let snapshot = try await query.getDocuments()
        
        let allSessions = snapshot.documents.map { doc -> (id: String, data: [String: Any]) in
            (id: doc.documentID, data: doc.data())
        }
        
        // Separate time off from regular sessions
        let regularSessions = allSessions.filter { session in
            !(session.data["isTimeOff"] as? Bool ?? false)
        }
        let timeOffSessions = allSessions.filter { session in
            session.data["isTimeOff"] as? Bool ?? false
        }
        
        // Sort regular sessions by start time, then school ID
        let sortedRegularSessions = regularSessions.sorted { lhs, rhs in
            let lhsStart = lhs.data["startTime"] as? String ?? ""
            let rhsStart = rhs.data["startTime"] as? String ?? ""
            if lhsStart != rhsStart {
                return lhsStart < rhsStart
            }
            let lhsSchool = lhs.data["schoolId"] as? String ?? ""
            let rhsSchool = rhs.data["schoolId"] as? String ?? ""
            return lhsSchool < rhsSchool
        }
        
        // Get color array
        let customColors = org?.sessionOrderColors
        let defaultColors = [
            "#3b82f6", "#10b981", "#8b5cf6", "#f59e0b",
            "#ef4444", "#06b6d4", "#8b5a3c", "#6b7280"
        ]
        let colors = (customColors?.count ?? 0) >= 8 ? customColors! : defaultColors
        
        // Batch update colors
        let batch = db.batch()
        var hasUpdates = false
        
        // Update regular sessions
        for (index, session) in sortedRegularSessions.enumerated() {
            let expectedColor = colors[min(index, colors.count - 1)]
            let currentColor = session.data["sessionColor"] as? String
            
            if currentColor != expectedColor {
                let docRef = db.collection("sessions").document(session.id)
                batch.updateData(["sessionColor": expectedColor], forDocument: docRef)
                hasUpdates = true
            }
        }
        
        // Update time off sessions
        for session in timeOffSessions {
            let expectedColor = "#666"
            let currentColor = session.data["sessionColor"] as? String
            
            if currentColor != expectedColor {
                let docRef = db.collection("sessions").document(session.id)
                batch.updateData(["sessionColor": expectedColor], forDocument: docRef)
                hasUpdates = true
            }
        }
        
        // Commit batch if there are updates
        if hasUpdates {
            try await batch.commit()
        }
    }
    
    // Delete a session
    func deleteSession(id: String, completion: @escaping (Bool, String?) -> Void) {
        db.collection("sessions").document(id).delete { error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                completion(true, nil)
            }
        }
    }
    
    // Fetch a single session by ID
    func fetchSession(by sessionId: String, completion: @escaping (Session?) -> Void) {
        guard !sessionId.isEmpty else {
            print("⚠️ fetchSession called with empty sessionId")
            completion(nil)
            return
        }
        
        print("🔍 Fetching session with ID: \(sessionId)")
        
        db.collection("sessions").document(sessionId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching session \(sessionId): \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let snapshot = snapshot else {
                print("❌ No snapshot returned for session \(sessionId)")
                completion(nil)
                return
            }
            
            guard snapshot.exists else {
                print("❌ Session document \(sessionId) does not exist in Firestore")
                completion(nil)
                return
            }
            
            guard let data = snapshot.data() else {
                print("❌ Session \(sessionId) exists but has no data")
                completion(nil)
                return
            }
            
            print("✅ Found session \(sessionId) with data keys: \(data.keys.sorted())")
            
            // Log the organization ID to check for mismatches
            if let sessionOrgId = data["organizationID"] as? String {
                print("📍 Session organizationID: '\(sessionOrgId)'")
            }
            
            let session = Session(id: sessionId, data: data)
            print("✅ Created session object: \(session.schoolName) - \(session.sessionType?.joined(separator: ", ") ?? "no types")")
            completion(session)
        }
    }
    
    // Get session display name for a session ID
    func getSessionDisplayName(for sessionId: String, completion: @escaping (String) -> Void) {
        fetchSession(by: sessionId) { session in
            if let session = session {
                // Create a meaningful display name from session data
                var displayName = session.schoolName
                
                // Add all session types
                if let sessionTypes = session.sessionType, !sessionTypes.isEmpty {
                    let typesString = sessionTypes.joined(separator: ", ")
                    displayName += " - \(typesString)"
                }
                
                // Add formatted date if available
                if let dateString = session.date {
                    // Convert yyyy-MM-dd to more readable format
                    let inputFormatter = DateFormatter()
                    inputFormatter.dateFormat = "yyyy-MM-dd"
                    
                    if let date = inputFormatter.date(from: dateString) {
                        let outputFormatter = DateFormatter()
                        outputFormatter.dateFormat = "MMM d"  // e.g., "Aug 4"
                        let formattedDate = outputFormatter.string(from: date)
                        displayName += " (\(formattedDate))"
                    } else {
                        displayName += " (\(dateString))"
                    }
                }
                
                completion(displayName)
            } else {
                // Fallback to session ID if session not found
                completion(sessionId)
            }
        }
    }
    
    // MARK: - Publishing Methods
    
    // Publish a single session
    func publishSession(sessionId: String) async throws {
        print("🚀 Publishing session: \(sessionId)")
        
        // First, get the current session data to log
        let document = try await db.collection("sessions").document(sessionId).getDocument()
        if let data = document.data() {
            let currentIsPublished = data["isPublished"] as? Bool ?? true
            print("🚀 Current isPublished value: \(currentIsPublished)")
        }
        
        // Update the session
        try await db.collection("sessions").document(sessionId).updateData([
            "isPublished": true,
            "publishedAt": FieldValue.serverTimestamp()
        ])
        
        print("✅ Session published successfully: \(sessionId)")
        
        // Verify the update
        let updatedDoc = try await db.collection("sessions").document(sessionId).getDocument()
        if let data = updatedDoc.data() {
            let newIsPublished = data["isPublished"] as? Bool ?? true
            print("✅ Verified isPublished value after update: \(newIsPublished)")
        }
    }
    
    // Temporarily create an unpublished test session for debugging
    func createTestUnpublishedSession(organizationID: String) async throws -> String {
        let testSessionData: [String: Any] = [
            "organizationID": organizationID,
            "schoolId": "test-school",
            "schoolName": "Test School - Unpublished Session",
            "date": "2025-08-04",
            "startTime": "09:00",
            "endTime": "12:00",
            "sessionTypes": ["Photography"],
            "notes": "This is a test unpublished session for admin visibility testing",
            "status": "scheduled",
            "sessionColor": "#FF6B6B",
            "isPublished": false, // Explicitly set to false
            "createdAt": FieldValue.serverTimestamp(),
            "createdBy": [
                "id": "test-admin",
                "name": "Test Admin",
                "email": "admin@test.com"
            ],
            "photographers": [
                [
                    "id": "test-photographer",
                    "name": "Test Photographer",
                    "email": "photographer@test.com",
                    "notes": "Test photographer for unpublished session"
                ]
            ]
        ]
        
        let docRef = try await db.collection("sessions").addDocument(data: testSessionData)
        print("🧪 Created test unpublished session with ID: \(docRef.documentID)")
        return docRef.documentID
    }
    
    // Publish all unpublished sessions for a specific date
    func publishSessionsForDate(organizationID: String, date: String) async throws {
        // Get all unpublished sessions for the date
        let query = db.collection("sessions")
            .whereField("organizationID", isEqualTo: organizationID)
            .whereField("date", isEqualTo: date)
            .whereField("isPublished", isEqualTo: false)
        
        let snapshot = try await query.getDocuments()
        
        // Batch update all sessions
        let batch = db.batch()
        var hasUpdates = false
        
        for document in snapshot.documents {
            let docRef = db.collection("sessions").document(document.documentID)
            batch.updateData([
                "isPublished": true,
                "publishedAt": FieldValue.serverTimestamp()
            ], forDocument: docRef)
            hasUpdates = true
        }
        
        // Commit batch if there are updates
        if hasUpdates {
            try await batch.commit()
        }
    }
    
    // Check if there are unpublished sessions for a date
    func hasUnpublishedSessionsForDate(organizationID: String, date: String) async throws -> Bool {
        let query = db.collection("sessions")
            .whereField("organizationID", isEqualTo: organizationID)
            .whereField("date", isEqualTo: date)
            .whereField("isPublished", isEqualTo: false)
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        return !snapshot.documents.isEmpty
    }
    
    // MARK: - Helper Methods
    
    // Clear the sessions cache
    func clearCache() {
        sessionsCache = []
        lastCacheUpdate = nil
    }
    
    // Check if user has permission to manage sessions (for future admin features)
    func userCanManageSessions() -> Bool {
        // For now, allow all authenticated users to read sessions
        return Auth.auth().currentUser != nil
    }
    
    // Get current connection status for UI indicators
    func getConnectionStatus() -> (isConnected: Bool, lastError: String?, isRetrying: Bool) {
        return (isConnected: isConnected, lastError: lastError, isRetrying: isRetrying)
    }
    
    // Filter sessions by employee name (case-insensitive)
    func filterSessions(_ sessions: [Session], forEmployee employeeName: String) -> [Session] {
        let trimmedName = employeeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return sessions }
        
        return sessions.filter { session in
            session.employeeName.lowercased() == trimmedName.lowercased()
        }
    }
    
    // Sort sessions by start date
    func sortSessionsByDate(_ sessions: [Session]) -> [Session] {
        return sessions.sorted { (session1, session2) -> Bool in
            guard let date1 = session1.startDate, let date2 = session2.startDate else {
                return false
            }
            return date1 < date2
        }
    }
    
    // Get sessions for a specific day
    func getSessionsForDay(_ sessions: [Session], date: Date) -> [Session] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return sessions.filter { session in
            guard let sessionDate = session.startDate else { return false }
            return sessionDate >= startOfDay && sessionDate < endOfDay
        }
    }
    
    // Check if there are sessions on a specific date
    func hasSessions(_ sessions: [Session], on date: Date) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return sessions.contains { session in
            guard let sessionDate = session.startDate else { return false }
            return sessionDate >= startOfDay && sessionDate < endOfDay
        }
    }
    
    // MARK: - Paginated Loading
    
    // Load sessions with pagination support
    func loadSessionsPage(organizationID: String, completion: @escaping ([Session], Bool) -> Void) {
        guard hasMorePages else {
            completion([], false)
            return
        }
        
        var query = db.collection("sessions")
            .whereField("organizationID", isEqualTo: organizationID)
            .whereField("isPublished", isEqualTo: true)
            .order(by: "date", descending: true)
            .limit(to: pageSize)
        
        // If we have a last document, start after it
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        query.getDocuments { [weak self] snapshot, error in
            if let error = error {
                print("Error loading sessions page: \(error.localizedDescription)")
                completion([], false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion([], false)
                return
            }
            
            let sessions = documents.map { document in
                Session(id: document.documentID, data: document.data())
            }
            
            // Update pagination state
            self?.lastDocument = documents.last
            self?.hasMorePages = documents.count == self?.pageSize
            
            completion(sessions, self?.hasMorePages ?? false)
        }
    }
    
    // Reset pagination state
    func resetPagination() {
        lastDocument = nil
        hasMorePages = true
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasConnected = self?.isConnected ?? true
                self?.isConnected = path.status == .satisfied
                
                // Clear errors when connection is restored
                if !wasConnected && path.status == .satisfied {
                    self?.lastError = nil
                    self?.isRetrying = false
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error, operation: String) {
        DispatchQueue.main.async {
            self.lastError = "\(operation): \(error.localizedDescription)"
            print("🔥 SessionService Error - \(operation): \(error.localizedDescription)")
            
            // Start retry logic for network errors
            if !self.isConnected && !self.isRetrying {
                self.startRetryLogic()
            }
        }
    }
    
    private func startRetryLogic() {
        isRetrying = true
        
        // Retry after 5 seconds if still connected
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.isConnected && self.isRetrying {
                self.isRetrying = false
                self.lastError = nil
                // Listeners will automatically reconnect when Firestore detects connectivity
            }
        }
    }
    
    deinit {
        monitor.cancel()
    }
}

