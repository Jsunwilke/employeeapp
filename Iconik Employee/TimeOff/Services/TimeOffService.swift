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
    
    // Cache management
    private var lastCacheUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    // Track if we have an active listener to prevent duplicates
    private var hasActiveListener = false
    
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
        
        // Check if we already have an active listener
        if hasActiveListener {
            print("📅 TimeOffService: Reusing existing listener")
            // If we have cached data and it's still valid, use it
            if let lastUpdate = lastCacheUpdate,
               Date().timeIntervalSince(lastUpdate) < cacheValidityDuration,
               !timeOffRequests.isEmpty {
                updateFilteredLists()
            }
            return
        }
        
        requestsListener?.remove()
        hasActiveListener = true
        
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
                    
                    self?.lastCacheUpdate = Date()
                    
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
        hasActiveListener = false
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
        isPaidTimeOff: Bool = false,
        ptoHoursRequested: Double? = nil,
        projectedPTOBalance: Double? = nil,
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
            endTime: endTime,
            isPaidTimeOff: isPaidTimeOff,
            ptoHoursRequested: ptoHoursRequested,
            projectedPTOBalance: projectedPTOBalance
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
                    // If using PTO, reserve the hours
                    if isPaidTimeOff, let ptoHours = ptoHoursRequested {
                        PTOService.shared.reservePTOHours(
                            userId: userId,
                            organizationID: orgId,
                            hours: ptoHours
                        ) { reserved, ptoError in
                            if !reserved {
                                print("Warning: Failed to reserve PTO hours: \(ptoError ?? "Unknown error")")
                            }
                        }
                    }
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
        isPaidTimeOff: Bool = false,
        ptoHoursRequested: Double? = nil,
        projectedPTOBalance: Double? = nil,
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
        
        if existingRequest.status != .pending && existingRequest.status != .underReview {
            completion(false, "You can only edit pending or under review requests")
            return
        }
        
        isLoading = true
        
        var updateData: [String: Any] = [
            "startDate": Timestamp(date: startDate),
            "endDate": Timestamp(date: endDate),
            "reason": reason.rawValue,
            "notes": notes,
            "isPartialDay": isPartialDay,
            "isPaidTimeOff": isPaidTimeOff,
            "updatedAt": Timestamp(date: Date())
        ]
        
        // Add PTO fields if using PTO
        if isPaidTimeOff {
            if let ptoHours = ptoHoursRequested {
                updateData["ptoHoursRequested"] = ptoHours
            }
            if let projBalance = projectedPTOBalance {
                updateData["projectedPTOBalance"] = projBalance
            }
        } else {
            // Remove PTO fields if not using PTO
            updateData["ptoHoursRequested"] = FieldValue.delete()
            updateData["projectedPTOBalance"] = FieldValue.delete()
        }
        
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
        
        if existingRequest.status != .pending && existingRequest.status != .underReview {
            completion(false, "You can only cancel pending or under review requests")
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
                    // If request was using PTO, release the reserved hours
                    if existingRequest.isPaidTimeOff, let ptoHours = existingRequest.ptoHoursRequested {
                        PTOService.shared.releasePTOHours(
                            userId: userId,
                            organizationID: self?.currentOrgId ?? "",
                            hours: ptoHours
                        ) { released, ptoError in
                            if !released {
                                print("Warning: Failed to release PTO hours: \(ptoError ?? "Unknown error")")
                            }
                        }
                    }
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
        
        // Find the request to check if it uses PTO
        guard let request = timeOffRequests.first(where: { $0.id == requestId }) else {
            completion(false, "Request not found")
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
                    // If request uses PTO, deduct the hours
                    if request.isPaidTimeOff, let ptoHours = request.ptoHoursRequested {
                        PTOService.shared.usePTOHours(
                            userId: request.photographerId,
                            organizationID: request.organizationID,
                            hours: ptoHours
                        ) { used, ptoError in
                            if !used {
                                print("Warning: Failed to deduct PTO hours: \(ptoError ?? "Unknown error")")
                            }
                        }
                    }
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
        
        // Find the request to check if it uses PTO
        guard let request = timeOffRequests.first(where: { $0.id == requestId }) else {
            completion(false, "Request not found")
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
                    // If request was using PTO, release the reserved hours
                    if request.isPaidTimeOff, let ptoHours = request.ptoHoursRequested {
                        PTOService.shared.releasePTOHours(
                            userId: request.photographerId,
                            organizationID: request.organizationID,
                            hours: ptoHours
                        ) { released, ptoError in
                            if !released {
                                print("Warning: Failed to release PTO hours: \(ptoError ?? "Unknown error")")
                            }
                        }
                    }
                    completion(true, nil)
                }
            }
        }
    }
    
    func putTimeOffRequestInReview(requestId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId else {
            completion(false, "User not authenticated")
            return
        }
        
        // Find the request
        guard let request = timeOffRequests.first(where: { $0.id == requestId }) else {
            completion(false, "Request not found")
            return
        }
        
        // Only pending requests can be put in review
        if request.status != .pending {
            completion(false, "Only pending requests can be put in review")
            return
        }
        
        // Get reviewer info
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let reviewerName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        isLoading = true
        
        let updateData: [String: Any] = [
            "status": TimeOffStatus.underReview.rawValue,
            "reviewedBy": userId,
            "reviewerName": reviewerName,
            "reviewedAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]
        
        db.collection("timeOffRequests").document(requestId).updateData(updateData) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    completion(false, "Error putting request in review: \(error.localizedDescription)")
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
        return request.photographerId == userId && (request.status == .pending || request.status == .underReview)
    }
    
    func canCancelRequest(_ request: TimeOffRequest) -> Bool {
        guard let userId = currentUserId else { return false }
        return request.photographerId == userId && (request.status == .pending || request.status == .underReview)
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
            .whereField("status", in: ["pending", "under_review", "approved"])
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
        
        // Instead of creating a separate listener, filter from the main timeOffRequests
        // if we already have an active listener
        if hasActiveListener && !timeOffRequests.isEmpty {
            let filteredRequests = timeOffRequests.filter { request in
                (request.status == .pending || request.status == .underReview || request.status == .approved) &&
                request.startDate <= dateRange.end &&
                request.endDate >= dateRange.start
            }
            let calendarEntries = convertToCalendarEntries(requests: filteredRequests)
            completion(calendarEntries)
            
            // Return a dummy listener that does nothing when removed
            return ListenerRegistrationWrapper {
                print("📅 TimeOff calendar: Using filtered data from main listener")
            }
        }
        
        // Set up real-time listener for calendar time off updates
        return db.collection("timeOffRequests")
            .whereField("organizationID", isEqualTo: orgId)
            .whereField("status", in: ["pending", "under_review", "approved"])
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