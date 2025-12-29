import Foundation
import Supabase

@MainActor
class PTOService: ObservableObject {
    static let shared = PTOService()
    private let supabase = SupabaseManager.shared.client

    @Published var currentBalance: PTOBalance?
    @Published var ptoSettings: PTOSettings?
    @Published var isLoading = false
    @Published var errorMessage = ""

    // Cache management
    private var balanceChannel: RealtimeChannel?
    private var lastBalanceUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    private init() {}

    deinit {
        Task { [weak balanceChannel] in
            await balanceChannel?.unsubscribe()
        }
    }

    // MARK: - PTO Balance Management

    // Get current PTO balance for a user
    func getPTOBalance(userId: String, organizationID: String) async throws -> PTOBalance {
        let balanceId = "\(organizationID)_\(userId)"

        // Check cache first
        if let balance = currentBalance,
           balance.id == balanceId,
           let lastUpdate = lastBalanceUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheValidityDuration {
            return balance
        }

        isLoading = true

        do {
            // Try to fetch existing balance
            let response: [PTOBalance] = try await supabase.database
                .from("pto_balances")
                .select()
                .eq("id", value: balanceId)
                .limit(1)
                .execute()
                .value

            if let balance = response.first {
                self.currentBalance = balance
                self.lastBalanceUpdate = Date()
                isLoading = false
                return balance
            } else {
                // Create new balance record if none exists
                let newBalance = PTOBalance(
                    userId: userId,
                    organizationID: organizationID
                )
                try await createPTOBalance(newBalance)
                self.currentBalance = newBalance
                self.lastBalanceUpdate = Date()
                isLoading = false
                return newBalance
            }

        } catch {
            isLoading = false
            throw NSError(domain: "PTOService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error fetching PTO balance: \(error.localizedDescription)"])
        }
    }

    // Listen to PTO balance changes
    func listenToPTOBalance(userId: String, organizationID: String) async throws -> RealtimeChannel? {
        // Clean up existing channel
        await balanceChannel?.unsubscribe()

        // Initial fetch
        let balance = try await getPTOBalance(userId: userId, organizationID: organizationID)
        self.currentBalance = balance
        self.lastBalanceUpdate = Date()

        // TODO: Set up real-time listener when Supabase realtime API is confirmed
        // For now, return nil and rely on manual refresh
        return nil
    }

    // Create new PTO balance record
    private func createPTOBalance(_ balance: PTOBalance) async throws {
        struct InsertData: Encodable {
            let id: String
            let user_id: String
            let organization_id: String
            let balance: Double
            let pending_balance: Double
            let banking_balance: Double
            let processed_periods: [String]
            let year: Int
        }

        let insertData = InsertData(
            id: balance.id,
            user_id: balance.user_id,
            organization_id: balance.organization_id,
            balance: balance.balance,
            pending_balance: balance.pending_balance,
            banking_balance: balance.banking_balance,
            processed_periods: balance.processed_periods,
            year: balance.year
        )

        do {
            try await supabase.database
                .from("pto_balances")
                .insert(insertData)
                .execute()
        } catch {
            throw NSError(domain: "PTOService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error creating PTO balance: \(error.localizedDescription)"])
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
            if request.status == "pending" &&
               request.is_paid_time_off == true &&
               request.start_date < targetDate,
               let ptoHours = request.pto_hours_requested {
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
        hours: Double
    ) async throws {
        var balance = try await getPTOBalance(userId: userId, organizationID: organizationID)

        // Check if sufficient balance available
        if hours > balance.availableBalance {
            throw NSError(domain: "PTOService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Insufficient PTO balance"])
        }

        // Reserve the hours
        balance.pending_balance += hours
        balance.updated_at = Date()

        // Update in Supabase
        struct UpdateData: Encodable {
            let pending_balance: Double
            let updated_at: Date
        }

        let updateData = UpdateData(
            pending_balance: balance.pending_balance,
            updated_at: balance.updated_at
        )

        do {
            try await supabase.database
                .from("pto_balances")
                .update(updateData)
                .eq("id", value: balance.id)
                .execute()

            self.currentBalance = balance
            self.lastBalanceUpdate = Date()

        } catch {
            throw NSError(domain: "PTOService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error reserving PTO: \(error.localizedDescription)"])
        }
    }

    // Use PTO hours when request is approved
    func usePTOHours(
        userId: String,
        organizationID: String,
        hours: Double
    ) async throws {
        var balance = try await getPTOBalance(userId: userId, organizationID: organizationID)

        // Use the hours
        balance.useHours(hours)

        // Update in Supabase
        struct UpdateData: Encodable {
            let balance: Double
            let pending_balance: Double
            let updated_at: Date
        }

        let updateData = UpdateData(
            balance: balance.balance,
            pending_balance: balance.pending_balance,
            updated_at: balance.updated_at
        )

        do {
            try await supabase.database
                .from("pto_balances")
                .update(updateData)
                .eq("id", value: balance.id)
                .execute()

            self.currentBalance = balance
            self.lastBalanceUpdate = Date()

        } catch {
            throw NSError(domain: "PTOService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error using PTO: \(error.localizedDescription)"])
        }
    }

    // Release PTO hours when request is denied/cancelled
    func releasePTOHours(
        userId: String,
        organizationID: String,
        hours: Double
    ) async throws {
        var balance = try await getPTOBalance(userId: userId, organizationID: organizationID)

        // Release the hours
        balance.releaseHours(hours)

        // Update in Supabase
        struct UpdateData: Encodable {
            let pending_balance: Double
            let updated_at: Date
        }

        let updateData = UpdateData(
            pending_balance: balance.pending_balance,
            updated_at: balance.updated_at
        )

        do {
            try await supabase.database
                .from("pto_balances")
                .update(updateData)
                .eq("id", value: balance.id)
                .execute()

            self.currentBalance = balance
            self.lastBalanceUpdate = Date()

        } catch {
            throw NSError(domain: "PTOService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error releasing PTO: \(error.localizedDescription)"])
        }
    }

    // MARK: - Settings Management

    // Get PTO settings from organization
    func getPTOSettings(organizationID: String) async throws -> PTOSettings {
        // Check cache first
        if let settings = ptoSettings {
            return settings
        }

        do {
            // Fetch organization data
            struct OrganizationResponse: Decodable {
                let id: String
                let pto_settings: PTOSettingsData?
            }

            struct PTOSettingsData: Decodable {
                let enabled: Bool?
                let accrualRate: Double?
                let accrualPeriod: Double?
                let maxAccrual: Double?
                let rolloverPolicy: String?
                let rolloverLimit: Double?
                let yearlyAllotment: Double?
                let bankingEnabled: Bool?
                let maxBanking: Double?
            }

            let response: [OrganizationResponse] = try await supabase.database
                .from("organizations")
                .select("id, pto_settings")
                .eq("id", value: organizationID)
                .limit(1)
                .execute()
                .value

            if let orgData = response.first,
               let ptoSettingsData = orgData.pto_settings {
                // Convert to dictionary format for PTOSettings initializer
                var settingsDict: [String: Any] = [:]
                settingsDict["enabled"] = ptoSettingsData.enabled ?? false
                settingsDict["accrualRate"] = ptoSettingsData.accrualRate ?? 1.0
                settingsDict["accrualPeriod"] = ptoSettingsData.accrualPeriod ?? 40.0
                settingsDict["maxAccrual"] = ptoSettingsData.maxAccrual ?? 240.0
                settingsDict["rolloverPolicy"] = ptoSettingsData.rolloverPolicy ?? "limited"
                if let limit = ptoSettingsData.rolloverLimit {
                    settingsDict["rolloverLimit"] = limit
                }
                settingsDict["yearlyAllotment"] = ptoSettingsData.yearlyAllotment ?? 0.0
                settingsDict["bankingEnabled"] = ptoSettingsData.bankingEnabled ?? true
                settingsDict["maxBanking"] = ptoSettingsData.maxBanking ?? 40.0

                let settings = PTOSettings(from: settingsDict)
                self.ptoSettings = settings
                return settings
            } else {
                // Return default settings if none found
                let defaultSettings = PTOSettings.defaultSettings
                self.ptoSettings = defaultSettings
                return defaultSettings
            }

        } catch {
            print("⚠️ Error fetching PTO settings: \(error.localizedDescription)")
            // Return default settings on error
            let defaultSettings = PTOSettings.defaultSettings
            self.ptoSettings = defaultSettings
            return defaultSettings
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
        let pending = balance.pending_balance > 0 ? " (\(formatPTOHours(balance.pending_balance)) pending)" : ""
        return "\(available) available\(pending)"
    }

    // Clear cache
    func clearCache() {
        currentBalance = nil
        ptoSettings = nil
        lastBalanceUpdate = nil
    }

    // Stop listening to balance changes
    func stopListening() async {
        await balanceChannel?.unsubscribe()
        balanceChannel = nil
    }
}
