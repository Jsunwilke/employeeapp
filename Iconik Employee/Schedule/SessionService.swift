import Foundation
import FirebaseFirestore
import FirebaseAuth
import Network

class SessionService: ObservableObject {
    // Singleton instance
    static let shared = SessionService()
    
    private let db = Firestore.firestore()
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected: Bool = true
    @Published var lastError: String?
    @Published var isRetrying: Bool = false
    
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
                
                // Now set up the listener with the organization ID and call completion
                let _ = self.listenForSessionsWithOrganizationID(orgID, completion: completion)
            }
            
            // Return a placeholder listener that doesn't interfere
            return db.collection("sessions").whereField("organizationID", isEqualTo: "loading").addSnapshotListener { _, _ in
                // This is a placeholder listener that won't match any real documents
                #if DEBUG
                print("🔄 SessionService: Placeholder listener fired (should not happen)")
                #endif
            }
        }
    }
    
    // Helper method to listen for sessions with a specific organization ID
    private func listenForSessionsWithOrganizationID(_ organizationID: String, completion: @escaping ([Session]) -> Void) -> ListenerRegistration {
        return db.collection("sessions")
            .whereField("organizationID", isEqualTo: organizationID)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    self?.handleError(error, operation: "Listening for sessions")
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
                
                #if DEBUG
                print("📅 Loaded \(sessions.count) sessions for organization \(organizationID)")
                #endif
                completion(sessions)
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
            // Get organization ID first
            UserManager.shared.getCurrentUserOrganizationID { organizationID in
                guard let orgID = organizationID else {
                    #if DEBUG
                    print("🔐 Cannot load sessions: no organization ID found")
                    #endif
                    completion([])
                    return
                }
                
                let _ = self.db.collection("sessions")
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
            
            return db.collection("sessions").whereField("organizationID", isEqualTo: "loading").addSnapshotListener { _, _ in 
                // This is a placeholder listener that won't match any real documents
                #if DEBUG
                print("🔄 SessionService: Placeholder listener fired (should not happen)")
                #endif
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
            UserManager.shared.getCurrentUserOrganizationID { organizationID in
                guard let orgID = organizationID else {
                    completion([])
                    return
                }
                
                let _ = self.db.collection("sessions")
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
            
            return db.collection("sessions").whereField("organizationID", isEqualTo: "loading").addSnapshotListener { _, _ in 
                // This is a placeholder listener that won't match any real documents
                #if DEBUG
                print("🔄 SessionService: Placeholder listener fired (should not happen)")
                #endif
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