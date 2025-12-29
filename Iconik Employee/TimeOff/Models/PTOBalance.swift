import Foundation

/// PTO Balance model for Supabase
struct PTOBalance: Identifiable, Codable {
    let id: String

    // Supabase snake_case properties (matching database)
    let user_id: String
    let organization_id: String
    var balance: Double              // Current available PTO hours (DB column name)
    var pending_balance: Double      // Hours reserved for pending requests
    var banking_balance: Double      // Excess hours over max accrual
    var processed_periods: [String]  // Array of processed pay periods (e.g., ["2024-01", "2024-02"])
    var year: Int                    // Year for this balance record
    let created_at: Date
    var updated_at: Date

    // Backward compatibility computed properties (camelCase for iOS code)
    var userId: String { user_id }
    var organizationID: String { organization_id }
    var totalBalance: Double {
        get { balance }
        set { balance = newValue }
    }
    var pendingBalance: Double {
        get { pending_balance }
        set { pending_balance = newValue }
    }
    var bankingBalance: Double {
        get { banking_balance }
        set { banking_balance = newValue }
    }
    var processedPeriods: [String] {
        get { processed_periods }
        set { processed_periods = newValue }
    }
    var createdAt: Date { created_at }
    var lastUpdated: Date {
        get { updated_at }
        set { updated_at = newValue }
    }

    // Not stored in DB, calculated on client
    var usedThisYear: Double = 0.0

    // Standard initializer
    init(
        userId: String,
        organizationID: String,
        balance: Double = 0.0,
        pendingBalance: Double = 0.0,
        bankingBalance: Double = 0.0,
        processedPeriods: [String] = [],
        year: Int? = nil
    ) {
        self.id = "\(organizationID)_\(userId)"
        self.user_id = userId
        self.organization_id = organizationID
        self.balance = balance
        self.pending_balance = pendingBalance
        self.banking_balance = bankingBalance
        self.processed_periods = processedPeriods

        // Default to current year if not specified
        let calendar = Calendar.current
        self.year = year ?? calendar.component(.year, from: Date())

        self.created_at = Date()
        self.updated_at = Date()
    }

    // Coding keys for Supabase (must match database column names exactly)
    enum CodingKeys: String, CodingKey {
        case id
        case user_id
        case organization_id
        case balance
        case pending_balance
        case banking_balance
        case processed_periods
        case year
        case created_at
        case updated_at
    }
}

// MARK: - Computed Properties
extension PTOBalance {

    // Available balance (total minus pending)
    var availableBalance: Double {
        return max(0, balance - pending_balance)
    }

    // Total accrued (including banking) - Note: usedThisYear not stored in DB
    var totalAccrued: Double {
        return balance + banking_balance + usedThisYear
    }

    // Check if balance needs year-end reset
    var needsYearEndReset: Bool {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        return currentYear > year
    }
}

// MARK: - Helper Methods
extension PTOBalance {

    // Reserve hours for a pending request
    mutating func reserveHours(_ hours: Double) -> Bool {
        if hours <= availableBalance {
            pending_balance += hours
            updated_at = Date()
            return true
        }
        return false
    }

    // Use hours when request is approved
    mutating func useHours(_ hours: Double) {
        pending_balance = max(0, pending_balance - hours)
        balance = max(0, balance - hours)
        usedThisYear += hours
        updated_at = Date()
    }

    // Release hours when request is denied/cancelled
    mutating func releaseHours(_ hours: Double) {
        pending_balance = max(0, pending_balance - hours)
        updated_at = Date()
    }

    // Add accrued hours
    mutating func addAccruedHours(_ hours: Double, maxAccrual: Double, bankingEnabled: Bool, maxBanking: Double) {
        let potentialBalance = balance + hours

        if potentialBalance <= maxAccrual {
            // Under the cap, add to balance
            balance = potentialBalance
        } else {
            // Over the cap
            balance = maxAccrual

            if bankingEnabled {
                // Add excess to banking
                let excess = potentialBalance - maxAccrual
                banking_balance = min(banking_balance + excess, maxBanking)
            }
        }

        updated_at = Date()
    }

    // Year-end reset
    mutating func performYearEndReset(rolloverLimit: Double?) {
        // Reset used hours for new year
        usedThisYear = 0

        // Apply rollover limit if specified
        if let limit = rolloverLimit {
            balance = min(balance, limit)
        }

        // Clear processed periods for new year
        processed_periods = []

        // Update to new year
        let calendar = Calendar.current
        year = calendar.component(.year, from: Date())

        updated_at = Date()
    }
}
