import Foundation
import FirebaseFirestore

struct PTOBalance: Identifiable, Codable {
    let id: String
    let userId: String
    let organizationID: String
    var totalBalance: Double       // Current available PTO hours
    var pendingBalance: Double     // Hours reserved for pending requests
    var usedThisYear: Double      // Hours used in current year
    var bankingBalance: Double    // Excess hours over max accrual
    var processedPeriods: [String] // Array of processed pay periods (e.g., ["2024-01", "2024-02"])
    let createdAt: Date
    var lastUpdated: Date
    
    // Firestore initializer
    init(id: String, data: [String: Any]) {
        self.id = id
        self.userId = data["userId"] as? String ?? ""
        self.organizationID = data["organizationID"] as? String ?? ""
        self.totalBalance = data["totalBalance"] as? Double ?? 0.0
        self.pendingBalance = data["pendingBalance"] as? Double ?? 0.0
        self.usedThisYear = data["usedThisYear"] as? Double ?? 0.0
        self.bankingBalance = data["bankingBalance"] as? Double ?? 0.0
        self.processedPeriods = data["processedPeriods"] as? [String] ?? []
        
        if let createdTimestamp = data["createdAt"] as? Timestamp {
            self.createdAt = createdTimestamp.dateValue()
        } else {
            self.createdAt = Date()
        }
        
        if let updatedTimestamp = data["lastUpdated"] as? Timestamp {
            self.lastUpdated = updatedTimestamp.dateValue()
        } else {
            self.lastUpdated = Date()
        }
    }
    
    // Standard initializer
    init(
        userId: String,
        organizationID: String,
        totalBalance: Double = 0.0,
        pendingBalance: Double = 0.0,
        usedThisYear: Double = 0.0,
        bankingBalance: Double = 0.0,
        processedPeriods: [String] = []
    ) {
        self.id = "\(organizationID)_\(userId)"
        self.userId = userId
        self.organizationID = organizationID
        self.totalBalance = totalBalance
        self.pendingBalance = pendingBalance
        self.usedThisYear = usedThisYear
        self.bankingBalance = bankingBalance
        self.processedPeriods = processedPeriods
        self.createdAt = Date()
        self.lastUpdated = Date()
    }
}

// MARK: - Computed Properties
extension PTOBalance {
    
    // Available balance (total minus pending)
    var availableBalance: Double {
        return max(0, totalBalance - pendingBalance)
    }
    
    // Total accrued (including banking)
    var totalAccrued: Double {
        return totalBalance + bankingBalance + usedThisYear
    }
    
    // Check if balance needs year-end reset
    var needsYearEndReset: Bool {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let lastUpdateYear = calendar.component(.year, from: lastUpdated)
        return currentYear > lastUpdateYear
    }
}

// MARK: - Firestore Conversion
extension PTOBalance {
    
    // Convert to dictionary for Firestore
    func toFirestoreData() -> [String: Any] {
        return [
            "userId": userId,
            "organizationID": organizationID,
            "totalBalance": totalBalance,
            "pendingBalance": pendingBalance,
            "usedThisYear": usedThisYear,
            "bankingBalance": bankingBalance,
            "processedPeriods": processedPeriods,
            "createdAt": Timestamp(date: createdAt),
            "lastUpdated": Timestamp(date: lastUpdated)
        ]
    }
    
    // Create or update document data
    func toUpdateData() -> [String: Any] {
        return [
            "totalBalance": totalBalance,
            "pendingBalance": pendingBalance,
            "usedThisYear": usedThisYear,
            "bankingBalance": bankingBalance,
            "processedPeriods": processedPeriods,
            "lastUpdated": Timestamp(date: Date())
        ]
    }
}

// MARK: - Helper Methods
extension PTOBalance {
    
    // Reserve hours for a pending request
    mutating func reserveHours(_ hours: Double) -> Bool {
        if hours <= availableBalance {
            pendingBalance += hours
            lastUpdated = Date()
            return true
        }
        return false
    }
    
    // Use hours when request is approved
    mutating func useHours(_ hours: Double) {
        pendingBalance = max(0, pendingBalance - hours)
        totalBalance = max(0, totalBalance - hours)
        usedThisYear += hours
        lastUpdated = Date()
    }
    
    // Release hours when request is denied/cancelled
    mutating func releaseHours(_ hours: Double) {
        pendingBalance = max(0, pendingBalance - hours)
        lastUpdated = Date()
    }
    
    // Add accrued hours
    mutating func addAccruedHours(_ hours: Double, maxAccrual: Double, bankingEnabled: Bool, maxBanking: Double) {
        let potentialBalance = totalBalance + hours
        
        if potentialBalance <= maxAccrual {
            // Under the cap, add to balance
            totalBalance = potentialBalance
        } else {
            // Over the cap
            totalBalance = maxAccrual
            
            if bankingEnabled {
                // Add excess to banking
                let excess = potentialBalance - maxAccrual
                bankingBalance = min(bankingBalance + excess, maxBanking)
            }
        }
        
        lastUpdated = Date()
    }
    
    // Year-end reset
    mutating func performYearEndReset(rolloverLimit: Double?) {
        // Reset used hours for new year
        usedThisYear = 0
        
        // Apply rollover limit if specified
        if let limit = rolloverLimit {
            totalBalance = min(totalBalance, limit)
        }
        
        // Clear processed periods for new year
        processedPeriods = []
        
        lastUpdated = Date()
    }
}