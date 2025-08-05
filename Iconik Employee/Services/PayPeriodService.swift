import Foundation
import FirebaseFirestore
import FirebaseAuth

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
                        self.payPeriodSettings = organization.payPeriodSettings
                        self.cachedOrganizationID = orgID
                        self.isLoading = false
                        
                        if organization.payPeriodSettings != nil {
                            print("✅ PayPeriodService: Loaded pay period settings - Type: \(organization.payPeriodSettings!.type), Start: \(organization.payPeriodSettings!.startDate)")
                        } else {
                            print("⚠️ PayPeriodService: No pay period settings found for organization")
                        }
                        
                        completion(organization.payPeriodSettings != nil)
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
        
        // Parse the start date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        
        guard let referenceDate = dateFormatter.date(from: activeSettings.startDate) else {
            print("❌ PayPeriodService: Invalid start date format: \(activeSettings.startDate)")
            return getDefaultPayPeriod(for: date)
        }
        
        let calendar = Calendar.current
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        let targetStartOfDay = calendar.startOfDay(for: date)
        
        // Calculate period length based on type
        let periodLength: Int
        switch activeSettings.type.lowercased() {
        case "weekly":
            periodLength = 7
        case "bi-weekly", "biweekly":
            periodLength = 14
        case "monthly":
            // For monthly, we need different logic
            return getMonthlyPayPeriod(for: date, startDay: calendar.component(.day, from: referenceDate))
        default:
            print("⚠️ PayPeriodService: Unknown period type: \(activeSettings.type), defaulting to bi-weekly")
            periodLength = 14
        }
        
        // Calculate how many days between reference and target
        let daysSinceReference = calendar.dateComponents([.day], from: referenceStartOfDay, to: targetStartOfDay).day ?? 0
        
        // Calculate periods - if reference is in future, we need to go backwards
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
        print("   - Reference date: \(activeSettings.startDate)")
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
        let calendar = Calendar.current
        
        // Reference date: 2/25/2024 (existing hardcoded date)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let referenceDate = dateFormatter.date(from: "2/25/2024") else {
            return nil
        }
        
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        let targetStartOfDay = calendar.startOfDay(for: date)
        let daysSinceReference = calendar.dateComponents([.day], from: referenceStartOfDay, to: targetStartOfDay).day ?? 0
        let periodLength = 14
        let periodsElapsed = daysSinceReference / periodLength
        
        guard let periodStart = calendar.date(byAdding: .day, value: periodsElapsed * periodLength, to: referenceStartOfDay),
              let tempEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: periodStart),
              let periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
            return nil
        }
        
        return (periodStart, periodEnd)
    }
    
    // Get period length in days
    func getPeriodLength() -> Int {
        guard let settings = payPeriodSettings else {
            return 14 // Default bi-weekly
        }
        
        switch settings.type.lowercased() {
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