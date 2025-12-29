import Foundation

class PayPeriodService: ObservableObject {
    static let shared = PayPeriodService()
    
    @Published var payPeriodSettings: PayPeriodSettings?
    @Published var isLoading = false
    
    private let organizationService = OrganizationService.shared
    private var cachedOrganizationID: String?
    
    private init() {}
    
    // Fetch pay period settings for the current user's organization
    func loadPayPeriodSettings(completion: @escaping (Bool) -> Void) {
        // Get current user's organization ID
        guard let orgID = UserDefaults.standard.string(forKey: "userOrganizationID"),
              !orgID.isEmpty else {
            print("❌ PayPeriodService: No organization ID found")
            isLoading = false
            completion(false)
            return
        }
        
        // Check if we already have cached settings for this org
        if cachedOrganizationID == orgID, payPeriodSettings != nil, !isLoading {
            // Already have settings, no need to reload
            completion(true)
            return
        }
        
        // Prevent multiple simultaneous loads
        if isLoading {
            // Already loading, wait for it to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion(self.payPeriodSettings != nil)
            }
            return
        }
        
        isLoading = true
        
        Task {
            do {
                if let organization = try await organizationService.getOrganization(organizationID: orgID) {
                    
                    await MainActor.run {
                        self.payPeriodSettings = organization.pay_period_settings
                        self.cachedOrganizationID = orgID
                        self.isLoading = false

                        if let settings = organization.pay_period_settings {
                            print("✅ PayPeriodService: Loaded pay period settings - Type: \(settings.type ?? "unknown"), Start: \(settings.startDate ?? "not set")")
                        } else {
                            print("⚠️ PayPeriodService: No pay period settings found for organization")
                        }

                        completion(organization.pay_period_settings != nil)
                    }
                } else {
                    await MainActor.run {
                        self.isLoading = false
                        print("❌ PayPeriodService: Organization not found")
                        completion(false)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("❌ PayPeriodService: Error loading organization: \(error)")
                    completion(false)
                }
            }
        }
    }
    
    // Calculate the current pay period based on settings
    func getCurrentPayPeriod() -> (start: Date, end: Date)? {
        guard let settings = payPeriodSettings,
              settings.isActive else {
            print("⚠️ PayPeriodService: No active pay period settings, using default")
            return getDefaultPayPeriod()
        }
        
        return getPayPeriod(for: Date(), settings: settings)
    }
    
    // Calculate pay period for a specific date
    func getPayPeriod(for date: Date, settings: PayPeriodSettings? = nil) -> (start: Date, end: Date)? {
        let activeSettings = settings ?? payPeriodSettings
        
        guard let activeSettings = activeSettings,
              activeSettings.isActive else {
            return getDefaultPayPeriod(for: date)
        }
        
        // Ensure consistent timezone usage
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        // Parse the start date with explicit timezone
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let startDateStr = activeSettings.startDate,
              let referenceDate = dateFormatter.date(from: startDateStr) else {
            print("❌ PayPeriodService: Invalid start date format: \(activeSettings.startDate ?? "nil")")
            return getDefaultPayPeriod(for: date)
        }
        
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        let targetStartOfDay = calendar.startOfDay(for: date)
        
        // Calculate period length based on type
        let periodLength: Int
        let typeStr = activeSettings.type?.lowercased() ?? "bi-weekly"
        switch typeStr {
        case "weekly":
            periodLength = 7
        case "bi-weekly", "biweekly":
            periodLength = 14
        case "monthly":
            // For monthly, we need different logic
            return getMonthlyPayPeriod(for: date, startDay: calendar.component(.day, from: referenceDate))
        default:
            print("⚠️ PayPeriodService: Unknown period type: \(typeStr), defaulting to bi-weekly")
            periodLength = 14
        }
        
        // Calculate how many days between reference and target
        let components = calendar.dateComponents([.day], from: referenceStartOfDay, to: targetStartOfDay)
        let daysSinceReference = components.day ?? 0
        
        // Calculate periods using proper floor division
        let periodsElapsed: Int
        if daysSinceReference >= 0 {
            // Normal case: reference date is in the past
            periodsElapsed = daysSinceReference / periodLength
        } else {
            // Reference date is in the future, calculate backwards
            periodsElapsed = (daysSinceReference - periodLength + 1) / periodLength
        }
        
        // Calculate start and end dates
        guard let periodStart = calendar.date(byAdding: .day, value: periodsElapsed * periodLength, to: referenceStartOfDay) else {
            return getDefaultPayPeriod(for: date)
        }
        
        guard let tempEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: periodStart),
              let periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
            return getDefaultPayPeriod(for: date)
        }
        
        print("📅 PayPeriodService: Calculated pay period from \(dateFormatter.string(from: periodStart)) to \(dateFormatter.string(from: periodEnd))")
        print("   - Reference date: \(startDateStr)")
        print("   - Target date: \(dateFormatter.string(from: date))")
        print("   - Days since reference: \(daysSinceReference)")
        print("   - Periods elapsed: \(periodsElapsed)")
        
        return (periodStart, periodEnd)
    }
    
    // Handle monthly pay periods
    private func getMonthlyPayPeriod(for date: Date, startDay: Int) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: date)
        
        // Set to start day of the month
        components.day = startDay
        
        // If the date is before the start day this month, use previous month
        if calendar.component(.day, from: date) < startDay {
            components.month! -= 1
        }
        
        guard let periodStart = calendar.date(from: components) else {
            return getDefaultPayPeriod(for: date)
        }
        
        // End date is one day before next month's start day
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: periodStart),
              let tempEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth),
              let periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
            return getDefaultPayPeriod(for: date)
        }
        
        return (calendar.startOfDay(for: periodStart), periodEnd)
    }
    
    // Default fallback using the old hardcoded date
    private func getDefaultPayPeriod(for date: Date = Date()) -> (start: Date, end: Date)? {
        // Ensure consistent timezone usage
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        // Reference date: 2/25/2024 (Sunday - start of a pay period)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yyyy"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let referenceDate = dateFormatter.date(from: "2/25/2024") else {
            print("❌ PayPeriodService: Failed to parse reference date")
            return nil
        }
        
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        let targetStartOfDay = calendar.startOfDay(for: date)
        
        // Calculate days between dates using dateComponents
        let components = calendar.dateComponents([.day], from: referenceStartOfDay, to: targetStartOfDay)
        let daysSinceReference = components.day ?? 0
        
        let periodLength = 14
        
        // Use integer division to get complete periods elapsed
        let periodsElapsed = daysSinceReference >= 0 ? 
            daysSinceReference / periodLength : 
            ((daysSinceReference - periodLength + 1) / periodLength)
        
        // Calculate the start of the current period
        guard let periodStart = calendar.date(byAdding: .day, value: periodsElapsed * periodLength, to: referenceStartOfDay) else {
            print("❌ PayPeriodService: Failed to calculate period start")
            return nil
        }
        
        // Calculate the end of the period (13 days later, end of day)
        guard let tempEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: periodStart),
              let periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
            print("❌ PayPeriodService: Failed to calculate period end")
            return nil
        }
        
        // Debug logging
        print("📅 Default Pay Period Calculation:")
        print("   Reference: 2/25/2024 (Sunday)")
        print("   Target: \(dateFormatter.string(from: date))")
        print("   Days since reference: \(daysSinceReference)")
        print("   Periods elapsed: \(periodsElapsed)")
        print("   Period: \(dateFormatter.string(from: periodStart)) to \(dateFormatter.string(from: periodEnd))")
        
        return (periodStart, periodEnd)
    }
    
    // Get period length in days
    func getPeriodLength() -> Int {
        guard let settings = payPeriodSettings,
              let typeStr = settings.type?.lowercased() else {
            return 14 // Default bi-weekly
        }

        switch typeStr {
        case "weekly":
            return 7
        case "bi-weekly", "biweekly":
            return 14
        case "monthly":
            return 30 // Approximate
        default:
            return 14
        }
    }
}