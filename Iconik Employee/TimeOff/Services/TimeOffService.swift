import Foundation
import FirebaseFirestore
import FirebaseAuth

class TimeOffService: ObservableObject {
    static let shared = TimeOffService()
    private let db = Firestore.firestore()
    
    @Published var timeOffRequests: [TimeOffRequest] = []
    @Published var myRequests: [TimeOffRequest] = []
    @Published var pendingRequests: [TimeOffRequest] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    private var requestsListener: ListenerRegistration?
    private var currentUserId: String?
    private var currentOrgId: String?
    
    private init() {
        setupUser()
    }
    
    deinit {
        requestsListener?.remove()
    }
    
    private func setupUser() {
        guard let user = Auth.auth().currentUser else { return }
        self.currentUserId = user.uid
        self.currentOrgId = UserDefaults.standard.string(forKey: "userOrganizationID")
    }
    
    // MARK: - Real-time Listeners
    
    func startListeningToRequests() {
        guard let orgId = currentOrgId else {
            errorMessage = "Organization ID not found"
            return
        }
        
        requestsListener?.remove()
        
        requestsListener = db.collection("timeOffRequests")
            .whereField("organizationID", isEqualTo: orgId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.errorMessage = "Error loading requests: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let documents = snapshot?.documents else { return }
                    
                    self?.timeOffRequests = documents.compactMap { doc in
                        TimeOffRequest(id: doc.documentID, data: doc.data())
                    }
                    
                    self?.updateFilteredLists()
                }
            }
    }
    
    private func updateFilteredLists() {
        guard let userId = currentUserId else { return }
        
        // Filter my requests
        myRequests = timeOffRequests.filter { $0.photographerId == userId }
        
        // Filter pending requests for managers
        pendingRequests = timeOffRequests.filter { $0.status == .pending }
    }
    
    func stopListening() {
        requestsListener?.remove()
        requestsListener = nil
    }
    
    // MARK: - Create Request
    
    func createTimeOffRequest(
        startDate: Date,
        endDate: Date,
        reason: TimeOffReason,
        notes: String,
        isPartialDay: Bool,
        startTime: String? = nil,
        endTime: String? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion(false, "User not authenticated")
            return
        }
        
        // Get user info
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let email = UserDefaults.standard.string(forKey: "userEmail") ?? ""
        
        let photographerName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        // Create request
        let request = TimeOffRequest(
            organizationID: orgId,
            photographerId: userId,
            photographerName: photographerName,
            photographerEmail: email,
            startDate: startDate,
            endDate: endDate,
            reason: reason,
            notes: notes,
            isPartialDay: isPartialDay,
            startTime: startTime,
            endTime: endTime
        )
        
        // Validate request
        let (isValid, validationError) = request.validate()
        if !isValid {
            completion(false, validationError)
            return
        }
        
        isLoading = true
        
        // Save to Firestore
        db.collection("timeOffRequests").addDocument(data: request.toFirestoreData()) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    completion(false, "Error creating request: \(error.localizedDescription)")
                } else {
                    completion(true, nil)
                }
            }
        }
    }
    
    // MARK: - Update Request
    
    func updateTimeOffRequest(
        requestId: String,
        startDate: Date,
        endDate: Date,
        reason: TimeOffReason,
        notes: String,
        isPartialDay: Bool,
        startTime: String? = nil,
        endTime: String? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion(false, "User not authenticated")
            return
        }
        
        // Find the existing request
        guard let existingRequest = timeOffRequests.first(where: { $0.id == requestId }) else {
            completion(false, "Request not found")
            return
        }
        
        // Check permissions
        if existingRequest.photographerId != userId {
            completion(false, "You can only edit your own requests")
            return
        }
        
        if existingRequest.status != .pending {
            completion(false, "You can only edit pending requests")
            return
        }
        
        isLoading = true
        
        var updateData: [String: Any] = [
            "startDate": Timestamp(date: startDate),
            "endDate": Timestamp(date: endDate),
            "reason": reason.rawValue,
            "notes": notes,
            "isPartialDay": isPartialDay,
            "updatedAt": Timestamp(date: Date())
        ]
        
        // Handle partial day fields
        if isPartialDay {
            if let startTime = startTime {
                updateData["startTime"] = startTime
            }
            if let endTime = endTime {
                updateData["endTime"] = endTime
            }
        } else {
            // Remove partial day fields if switching to full day
            updateData["startTime"] = FieldValue.delete()
            updateData["endTime"] = FieldValue.delete()
        }
        
        db.collection("timeOffRequests").document(requestId).updateData(updateData) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    completion(false, "Error updating request: \(error.localizedDescription)")
                } else {
                    completion(true, nil)
                }
            }
        }
    }
    
    // MARK: - Cancel Request
    
    func cancelTimeOffRequest(requestId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId else {
            completion(false, "User not authenticated")
            return
        }
        
        // Find the existing request
        guard let existingRequest = timeOffRequests.first(where: { $0.id == requestId }) else {
            completion(false, "Request not found")
            return
        }
        
        // Check permissions
        if existingRequest.photographerId != userId {
            completion(false, "You can only cancel your own requests")
            return
        }
        
        if existingRequest.status != .pending {
            completion(false, "You can only cancel pending requests")
            return
        }
        
        isLoading = true
        
        let updateData: [String: Any] = [
            "status": TimeOffStatus.cancelled.rawValue,
            "updatedAt": Timestamp(date: Date())
        ]
        
        db.collection("timeOffRequests").document(requestId).updateData(updateData) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    completion(false, "Error cancelling request: \(error.localizedDescription)")
                } else {
                    completion(true, nil)
                }
            }
        }
    }
    
    // MARK: - Manager Actions
    
    func approveTimeOffRequest(requestId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId else {
            completion(false, "User not authenticated")
            return
        }
        
        // Get manager info
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let approverName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        isLoading = true
        
        let updateData: [String: Any] = [
            "status": TimeOffStatus.approved.rawValue,
            "approvedBy": userId,
            "approverName": approverName,
            "approvedAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]
        
        db.collection("timeOffRequests").document(requestId).updateData(updateData) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    completion(false, "Error approving request: \(error.localizedDescription)")
                } else {
                    completion(true, nil)
                }
            }
        }
    }
    
    func denyTimeOffRequest(requestId: String, denialReason: String, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId else {
            completion(false, "User not authenticated")
            return
        }
        
        if denialReason.trimmingCharacters(in: .whitespaces).isEmpty {
            completion(false, "Denial reason is required")
            return
        }
        
        // Get manager info
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let denierName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        isLoading = true
        
        let updateData: [String: Any] = [
            "status": TimeOffStatus.denied.rawValue,
            "deniedBy": userId,
            "denierName": denierName,
            "deniedAt": Timestamp(date: Date()),
            "denialReason": denialReason,
            "updatedAt": Timestamp(date: Date())
        ]
        
        db.collection("timeOffRequests").document(requestId).updateData(updateData) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    completion(false, "Error denying request: \(error.localizedDescription)")
                } else {
                    completion(true, nil)
                }
            }
        }
    }
    
    // MARK: - Conflict Detection
    
    func checkForConflicts(
        startDate: Date,
        endDate: Date,
        isPartialDay: Bool,
        startTime: String? = nil,
        endTime: String? = nil,
        excludeRequestId: String? = nil,
        completion: @escaping ([String]) -> Void
    ) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion([])
            return
        }
        
        // Check against sessions first
        let sessionService = SessionService.shared
        
        // For full day requests, check entire days
        if !isPartialDay {
            // Check each day in the range
            var conflicts: [String] = []
            let calendar = Calendar.current
            var currentDate = startDate
            
            while currentDate <= endDate {
                // Check if user has sessions on this date
                // This would need integration with your session checking logic
                // For now, we'll just note it as a placeholder
                
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
                if currentDate > endDate { break }
            }
            
            completion(conflicts)
        } else {
            // For partial day requests, check time overlaps
            // This would need more complex logic to check session times
            // For now, we'll return empty array
            completion([])
        }
    }
    
    // MARK: - Helper Methods
    
    func getMyRequests(status: TimeOffStatus? = nil) -> [TimeOffRequest] {
        if let status = status {
            return myRequests.filter { $0.status == status }
        }
        return myRequests
    }
    
    func getPendingRequestsCount() -> Int {
        return pendingRequests.count
    }
    
    func refreshRequests() {
        startListeningToRequests()
    }
    
    // MARK: - Permission Checks
    
    func canManageRequests() -> Bool {
        let userRole = UserDefaults.standard.string(forKey: "userRole") ?? ""
        return userRole == "admin" || userRole == "manager" || userRole == "owner"
    }
    
    func canEditRequest(_ request: TimeOffRequest) -> Bool {
        guard let userId = currentUserId else { return false }
        return request.photographerId == userId && request.status == .pending
    }
    
    func canCancelRequest(_ request: TimeOffRequest) -> Bool {
        guard let userId = currentUserId else { return false }
        return request.photographerId == userId && request.status == .pending
    }
    
    // MARK: - Calendar Integration
    
    func getTimeOffForCalendar(dateRange: (start: Date, end: Date), completion: @escaping ([TimeOffCalendarEntry]) -> Void) {
        guard let orgId = currentOrgId else {
            completion([])
            return
        }
        
        // Query for time off requests that overlap with the visible date range
        // Include both pending and approved requests for calendar display
        db.collection("timeOffRequests")
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("status", in: ["pending", "approved"])
            .whereField("startDate", isLessThanOrEqualTo: Timestamp(date: dateRange.end))
            .whereField("endDate", isGreaterThanOrEqualTo: Timestamp(date: dateRange.start))
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching time off for calendar: \(error)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let requests = documents.compactMap { doc in
                    TimeOffRequest(id: doc.documentID, data: doc.data())
                }
                
                // Convert to calendar entries
                let calendarEntries = self.convertToCalendarEntries(requests: requests)
                
                DispatchQueue.main.async {
                    completion(calendarEntries)
                }
            }
    }
    
    func startListeningToCalendarTimeOff(dateRange: (start: Date, end: Date), completion: @escaping ([TimeOffCalendarEntry]) -> Void) -> ListenerRegistration? {
        guard let orgId = currentOrgId else {
            completion([])
            return nil
        }
        
        // Set up real-time listener for calendar time off updates
        return db.collection("timeOffRequests")
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("status", in: ["pending", "approved"])
            .whereField("startDate", isLessThanOrEqualTo: Timestamp(date: dateRange.end))
            .whereField("endDate", isGreaterThanOrEqualTo: Timestamp(date: dateRange.start))
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to calendar time off: \(error)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let requests = documents.compactMap { doc in
                    TimeOffRequest(id: doc.documentID, data: doc.data())
                }
                
                // Convert to calendar entries
                let calendarEntries = self.convertToCalendarEntries(requests: requests)
                
                DispatchQueue.main.async {
                    completion(calendarEntries)
                }
            }
    }
    
    private func convertToCalendarEntries(requests: [TimeOffRequest]) -> [TimeOffCalendarEntry] {
        var entries: [TimeOffCalendarEntry] = []
        let calendar = Calendar.current
        
        for request in requests {
            var currentDate = request.startDate
            let endDate = request.endDate
            
            // Create entries for each day in the range
            while currentDate <= endDate {
                let title = request.isPartialDay 
                    ? "Time Off: \(request.reason.displayName) (\(formatTime(request.startTime)) - \(formatTime(request.endTime)))"
                    : "Time Off: \(request.reason.displayName)"
                
                let entry = TimeOffCalendarEntry(
                    id: "\(request.id)-\(currentDate.timeIntervalSince1970)",
                    requestId: request.id,
                    title: title,
                    date: currentDate,
                    startTime: request.isPartialDay ? (request.startTime ?? "09:00") : "09:00",
                    endTime: request.isPartialDay ? (request.endTime ?? "17:00") : "17:00",
                    photographerId: request.photographerId,
                    photographerName: request.photographerName,
                    status: request.status,
                    isPartialDay: request.isPartialDay,
                    reason: request.reason,
                    notes: request.notes
                )
                
                entries.append(entry)
                
                // Move to next day
                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
                currentDate = nextDate
                
                if currentDate > endDate { break }
            }
        }
        
        return entries.sorted { $0.date < $1.date }
    }
    
    private func formatTime(_ timeString: String?) -> String {
        guard let timeString = timeString else { return "" }
        
        // Convert "HH:mm" to display format
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        if let date = formatter.date(from: timeString) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        
        return timeString
    }
}