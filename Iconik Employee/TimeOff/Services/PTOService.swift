import Foundation
import FirebaseFirestore
import FirebaseAuth

class PTOService: ObservableObject {
    static let shared = PTOService()
    private let db = Firestore.firestore()
    
    @Published var currentBalance: PTOBalance?
    @Published var ptoSettings: PTOSettings?
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    // Cache management
    private var balanceListener: ListenerRegistration?
    private var lastBalanceUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    deinit {
        balanceListener?.remove()
    }
    
    // MARK: - PTO Balance Management
    
    // Get current PTO balance for a user
    func getPTOBalance(userId: String, organizationID: String, completion: @escaping (PTOBalance?) -> Void) {
        let balanceId = "\(organizationID)_\(userId)"
        
        // Check cache first
        if let balance = currentBalance,
           balance.id == balanceId,
           let lastUpdate = lastBalanceUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheValidityDuration {
            completion(balance)
            return
        }
        
        isLoading = true
        
        db.collection("ptoBalances").document(balanceId).getDocument { [weak self] snapshot, error in
            self?.isLoading = false
            
            if let error = error {
                self?.errorMessage = "Error fetching PTO balance: \(error.localizedDescription)"
                completion(nil)
                return
            }
            
            if let data = snapshot?.data() {
                let balance = PTOBalance(id: balanceId, data: data)
                self?.currentBalance = balance
                self?.lastBalanceUpdate = Date()
                completion(balance)
            } else {
                // Create new balance record if none exists
                let newBalance = PTOBalance(userId: userId, organizationID: organizationID)
                self?.createPTOBalance(newBalance) { created in
                    if created {
                        self?.currentBalance = newBalance
                        self?.lastBalanceUpdate = Date()
                        completion(newBalance)
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }
    
    // Listen to PTO balance changes
    func listenToPTOBalance(userId: String, organizationID: String, completion: @escaping (PTOBalance?) -> Void) -> ListenerRegistration {
        let balanceId = "\(organizationID)_\(userId)"
        
        // Remove existing listener
        balanceListener?.remove()
        
        balanceListener = db.collection("ptoBalances").document(balanceId)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    self?.errorMessage = "Error listening to PTO balance: \(error.localizedDescription)"
                    completion(nil)
                    return
                }
                
                if let data = snapshot?.data() {
                    let balance = PTOBalance(id: balanceId, data: data)
                    self?.currentBalance = balance
                    self?.lastBalanceUpdate = Date()
                    
                    completion(balance)
                } else {
                    completion(nil)
                }
            }
        
        return balanceListener!
    }
    
    // Create new PTO balance record
    private func createPTOBalance(_ balance: PTOBalance, completion: @escaping (Bool) -> Void) {
        db.collection("ptoBalances").document(balance.id).setData(balance.toFirestoreData()) { error in
            if let error = error {
                print("Error creating PTO balance: \(error.localizedDescription)")
                completion(false)
            } else {
                completion(true)
            }
        }
    }
    
    // MARK: - PTO Calculations
    
    // Calculate projected PTO balance for a future date
    func calculateProjectedBalance(
        currentBalance: PTOBalance,
        settings: PTOSettings,
        targetDate: Date,
        pendingRequests: [TimeOffRequest] = []
    ) -> Double {
        let today = Date()
        
        // If target date is in the past, return current balance
        if targetDate < today {
            return currentBalance.totalBalance
        }
        
        // Calculate projected accrual
        let projectedAccrual = settings.calculateProjectedAccrual(from: today, to: targetDate)
        
        // Start with current balance plus projected accrual
        var projectedBalance = min(currentBalance.totalBalance + projectedAccrual, settings.maxAccrual)
        
        // Subtract pending requests that would occur before target date
        for request in pendingRequests {
            if request.status == .pending && 
               request.isPaidTimeOff && 
               request.startDate < targetDate,
               let ptoHours = request.ptoHoursRequested {
                projectedBalance -= ptoHours
            }
        }
        
        return max(0, projectedBalance)
    }
    
    // Calculate PTO hours for a time off request
    func calculatePTOHours(
        startDate: Date,
        endDate: Date,
        isPartialDay: Bool,
        startTime: String? = nil,
        endTime: String? = nil
    ) -> Double {
        if isPartialDay {
            // Calculate hours for partial day
            guard let startTimeStr = startTime,
                  let endTimeStr = endTime else { return 0 }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            
            guard let start = formatter.date(from: startTimeStr),
                  let end = formatter.date(from: endTimeStr) else { return 0 }
            
            let hours = end.timeIntervalSince(start) / 3600
            return max(0, hours)
        } else {
            // Calculate hours for full days (8 hours per day)
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            return Double(days + 1) * 8.0
        }
    }
    
    // MARK: - PTO Operations
    
    // Reserve PTO hours for a pending request
    func reservePTOHours(
        userId: String,
        organizationID: String,
        hours: Double,
        completion: @escaping (Bool, String?) -> Void
    ) {
        getPTOBalance(userId: userId, organizationID: organizationID) { [weak self] balance in
            guard var balance = balance else {
                completion(false, "Could not fetch PTO balance")
                return
            }
            
            // Check if sufficient balance available
            if hours > balance.availableBalance {
                completion(false, "Insufficient PTO balance")
                return
            }
            
            // Reserve the hours
            balance.pendingBalance += hours
            balance.lastUpdated = Date()
            
            // Update in Firestore
            self?.db.collection("ptoBalances").document(balance.id).updateData(balance.toUpdateData()) { error in
                if let error = error {
                    completion(false, "Error reserving PTO: \(error.localizedDescription)")
                } else {
                    self?.currentBalance = balance
                    self?.lastBalanceUpdate = Date()
                    completion(true, nil)
                }
            }
        }
    }
    
    // Use PTO hours when request is approved
    func usePTOHours(
        userId: String,
        organizationID: String,
        hours: Double,
        completion: @escaping (Bool, String?) -> Void
    ) {
        getPTOBalance(userId: userId, organizationID: organizationID) { [weak self] balance in
            guard var balance = balance else {
                completion(false, "Could not fetch PTO balance")
                return
            }
            
            // Use the hours
            balance.useHours(hours)
            
            // Update in Firestore
            self?.db.collection("ptoBalances").document(balance.id).updateData(balance.toUpdateData()) { error in
                if let error = error {
                    completion(false, "Error using PTO: \(error.localizedDescription)")
                } else {
                    self?.currentBalance = balance
                    self?.lastBalanceUpdate = Date()
                    completion(true, nil)
                }
            }
        }
    }
    
    // Release PTO hours when request is denied/cancelled
    func releasePTOHours(
        userId: String,
        organizationID: String,
        hours: Double,
        completion: @escaping (Bool, String?) -> Void
    ) {
        getPTOBalance(userId: userId, organizationID: organizationID) { [weak self] balance in
            guard var balance = balance else {
                completion(false, "Could not fetch PTO balance")
                return
            }
            
            // Release the hours
            balance.releaseHours(hours)
            
            // Update in Firestore
            self?.db.collection("ptoBalances").document(balance.id).updateData(balance.toUpdateData()) { error in
                if let error = error {
                    completion(false, "Error releasing PTO: \(error.localizedDescription)")
                } else {
                    self?.currentBalance = balance
                    self?.lastBalanceUpdate = Date()
                    completion(true, nil)
                }
            }
        }
    }
    
    // MARK: - Settings Management
    
    // Get PTO settings from organization
    func getPTOSettings(organizationID: String, completion: @escaping (PTOSettings?) -> Void) {
        // Check cache first
        if let settings = ptoSettings {
            completion(settings)
            return
        }
        
        db.collection("organizations").document(organizationID).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("Error fetching organization settings: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            if let data = snapshot?.data(),
               let ptoSettingsData = data["ptoSettings"] as? [String: Any] {
                let settings = PTOSettings(from: ptoSettingsData)
                self?.ptoSettings = settings
                completion(settings)
            } else {
                // Return default settings if none found
                let defaultSettings = PTOSettings.defaultSettings
                self?.ptoSettings = defaultSettings
                completion(defaultSettings)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    // Format PTO hours for display
    func formatPTOHours(_ hours: Double) -> String {
        if hours.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(hours)) hour\(Int(hours) == 1 ? "" : "s")"
        } else {
            return String(format: "%.1f hours", hours)
        }
    }
    
    // Format PTO balance summary
    func formatBalanceSummary(_ balance: PTOBalance) -> String {
        let available = formatPTOHours(balance.availableBalance)
        let pending = balance.pendingBalance > 0 ? " (\(formatPTOHours(balance.pendingBalance)) pending)" : ""
        return "\(available) available\(pending)"
    }
    
    // Clear cache
    func clearCache() {
        currentBalance = nil
        ptoSettings = nil
        lastBalanceUpdate = nil
    }
}