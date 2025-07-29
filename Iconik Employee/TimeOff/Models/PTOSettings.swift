import Foundation

struct PTOSettings: Codable {
    let enabled: Bool
    let accrualRate: Double        // Hours earned per accrual period
    let accrualPeriod: Double      // Hours worked to earn PTO
    let maxAccrual: Double         // Maximum PTO hours allowed
    let rolloverPolicy: RolloverPolicy
    let rolloverLimit: Double?     // Max hours to rollover (if limited)
    let yearlyAllotment: Double    // Yearly grant (alternative to accrual)
    let bankingEnabled: Bool       // Allow banking excess hours
    let maxBanking: Double         // Maximum banking hours
    
    enum RolloverPolicy: String, Codable {
        case none = "none"
        case limited = "limited"
        case unlimited = "unlimited"
    }
    
    // Default settings
    static let defaultSettings = PTOSettings(
        enabled: false,
        accrualRate: 1.0,
        accrualPeriod: 40.0,
        maxAccrual: 240.0,
        rolloverPolicy: .limited,
        rolloverLimit: 80.0,
        yearlyAllotment: 0.0,
        bankingEnabled: true,
        maxBanking: 40.0
    )
    
    // Initialize from Firestore data
    init(from data: [String: Any]?) {
        guard let data = data else {
            self = PTOSettings.defaultSettings
            return
        }
        
        self.enabled = data["enabled"] as? Bool ?? false
        self.accrualRate = data["accrualRate"] as? Double ?? 1.0
        self.accrualPeriod = data["accrualPeriod"] as? Double ?? 40.0
        self.maxAccrual = data["maxAccrual"] as? Double ?? 240.0
        
        if let policyString = data["rolloverPolicy"] as? String,
           let policy = RolloverPolicy(rawValue: policyString) {
            self.rolloverPolicy = policy
        } else {
            self.rolloverPolicy = .limited
        }
        
        self.rolloverLimit = data["rolloverLimit"] as? Double
        self.yearlyAllotment = data["yearlyAllotment"] as? Double ?? 0.0
        self.bankingEnabled = data["bankingEnabled"] as? Bool ?? true
        self.maxBanking = data["maxBanking"] as? Double ?? 40.0
    }
    
    // Standard initializer
    init(
        enabled: Bool,
        accrualRate: Double,
        accrualPeriod: Double,
        maxAccrual: Double,
        rolloverPolicy: RolloverPolicy,
        rolloverLimit: Double? = nil,
        yearlyAllotment: Double = 0,
        bankingEnabled: Bool = true,
        maxBanking: Double = 40
    ) {
        self.enabled = enabled
        self.accrualRate = accrualRate
        self.accrualPeriod = accrualPeriod
        self.maxAccrual = maxAccrual
        self.rolloverPolicy = rolloverPolicy
        self.rolloverLimit = rolloverLimit
        self.yearlyAllotment = yearlyAllotment
        self.bankingEnabled = bankingEnabled
        self.maxBanking = maxBanking
    }
}

// MARK: - Computed Properties
extension PTOSettings {
    
    // Check if using accrual system vs yearly allotment
    var usesAccrualSystem: Bool {
        return yearlyAllotment == 0 && accrualRate > 0
    }
    
    // Get effective rollover limit
    var effectiveRolloverLimit: Double? {
        switch rolloverPolicy {
        case .none:
            return 0
        case .limited:
            return rolloverLimit ?? 0
        case .unlimited:
            return nil
        }
    }
    
    // Calculate hours earned for a given period
    func calculateAccrual(hoursWorked: Double) -> Double {
        guard usesAccrualSystem && accrualPeriod > 0 else { return 0 }
        return (hoursWorked / accrualPeriod) * accrualRate
    }
    
    // Calculate projected accrual between dates
    func calculateProjectedAccrual(from startDate: Date, to endDate: Date) -> Double {
        guard usesAccrualSystem else { return 0 }
        
        // Calculate working days between dates (excluding weekends)
        let workingDays = calculateWorkingDays(from: startDate, to: endDate)
        
        // Assume 8 hours per working day
        let projectedHours = Double(workingDays) * 8.0
        
        return calculateAccrual(hoursWorked: projectedHours)
    }
    
    // Helper to calculate working days
    private func calculateWorkingDays(from startDate: Date, to endDate: Date) -> Int {
        let calendar = Calendar.current
        var workingDays = 0
        var currentDate = startDate
        
        while currentDate <= endDate {
            let weekday = calendar.component(.weekday, from: currentDate)
            // Monday = 2, Friday = 6
            if weekday >= 2 && weekday <= 6 {
                workingDays += 1
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return workingDays
    }
}

// MARK: - Display Helpers
extension PTOSettings {
    
    // Format accrual rate for display
    var formattedAccrualRate: String {
        if usesAccrualSystem {
            return "\(Int(accrualRate)) hour\(accrualRate == 1 ? "" : "s") per \(Int(accrualPeriod)) hours worked"
        } else {
            return "\(Int(yearlyAllotment)) hours per year"
        }
    }
    
    // Format max accrual for display
    var formattedMaxAccrual: String {
        let days = maxAccrual / 8.0
        return "\(Int(maxAccrual)) hours (\(Int(days)) days)"
    }
    
    // Format rollover policy for display
    var formattedRolloverPolicy: String {
        switch rolloverPolicy {
        case .none:
            return "No rollover"
        case .limited:
            if let limit = rolloverLimit {
                return "Up to \(Int(limit)) hours"
            }
            return "Limited rollover"
        case .unlimited:
            return "Unlimited rollover"
        }
    }
}

