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
        #if DEBUG
        print("🔄 SessionService: listenForSessions called")
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
            return listenForSessionsWithOrganizationID(cachedOrgID, completion: completion)
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
                realListener = self.listenForSessionsWithOrganizationID(orgID, completion: completion)
            }
            
            // Return a wrapper that will remove the real listener when called
            return ListenerRegistrationWrapper {
                realListener?.remove()
            }
        }
    }
    
    // Helper method to listen for sessions with a specific organization ID
    private func listenForSessionsWithOrganizationID(_ organizationID: String, completion: @escaping ([Session]) -> Void) -> ListenerRegistration {
        let listenerKey = "sessions-org-\(organizationID)"
        
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
        let listener = db.collection("sessions")
            .whereField("organizationID", isEqualTo: organizationID)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
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
                
                let sessions = documents.map { document in
                    Session(id: document.documentID, data: document.data())
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
                
                print("📅 Updated session \(session.schoolName)")
                completion(session)
            }
    }
    
    // Listen for sessions within a date range for current user's organization
    func listenForSessions(from startDate: Date, to endDate: Date, completion: @escaping ([Session]) -> Void) -> ListenerRegistration {
        // Convert dates to string format for Firestore filtering
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)
        
        let cachedOrgID = UserManager.shared.getCachedOrganizationID()
        
        if !cachedOrgID.isEmpty {
            return db.collection("sessions")
                .whereField("organizationID", isEqualTo: cachedOrgID)
                .whereField("date", isGreaterThanOrEqualTo: startDateString)
                .whereField("date", isLessThan: endDateString)
                .addSnapshotListener { [weak self] snapshot, error in
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
                
                realListener = self.db.collection("sessions")
                    .whereField("organizationID", isEqualTo: orgID)
                    .whereField("date", isGreaterThanOrEqualTo: startDateString)
                    .whereField("date", isLessThan: endDateString)
                    .addSnapshotListener { snapshot, error in
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
    
    // Create a new session
    func createSession(_ session: Session, completion: @escaping (Bool, String?) -> Void) {
        var sessionData = session.toDictionary
        sessionData["createdAt"] = Timestamp(date: Date())
        sessionData["updatedAt"] = Timestamp(date: Date())
        
        db.collection("sessions").document(session.id).setData(sessionData) { error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                completion(true, nil)
            }
        }
    }
    
    // Update an existing session
    func updateSession(_ session: Session, completion: @escaping (Bool, String?) -> Void) {
        var sessionData = session.toDictionary
        sessionData["updatedAt"] = Timestamp(date: Date())
        
        db.collection("sessions").document(session.id).updateData(sessionData) { error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                completion(true, nil)
            }
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

