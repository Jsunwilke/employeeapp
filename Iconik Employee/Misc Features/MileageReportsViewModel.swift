import Foundation
import SwiftUI

class MileageReportsViewModel: ObservableObject {
    static let shared = MileageReportsViewModel()

    @Published var currentPeriodMileage: Double = 0
    @Published var monthMileage: Double = 0
    @Published var yearMileage: Double = 0
    @Published var records: [MileageRecordWrapper] = []

    var userName: String = ""
    var userId: String?

    let calendar = Calendar.current
    var currentPeriodStart: Date = Date()
    var currentPeriodEnd: Date = Date()

    private let payPeriodService = PayPeriodService.shared
    private var updateCallback: (() -> Void)?

    // Local wrapper model to hold report data
    struct MileageRecordWrapper: Identifiable {
        let id: String
        let date: Date
        let totalMileage: Double
        let schoolName: String

        /// Create from DailyJobReport
        init(from report: DailyJobReport) {
            self.id = report.id
            self.date = report.date
            self.totalMileage = report.total_mileage
            self.schoolName = report.school_or_destination ?? ""
        }

        /// Direct initializer
        init(id: String, date: Date, totalMileage: Double, schoolName: String) {
            self.id = id
            self.date = date
            self.totalMileage = totalMileage
            self.schoolName = schoolName
        }
    }
    
    init(userName: String = "") {
        self.userName = userName.isEmpty ? (UserDefaults.standard.string(forKey: "userFirstName") ?? "") : userName
        
        // Get the current user's ID for more reliable filtering
        if let userId = UserManager.shared.getCurrentUserIDUnified() {
            self.userId = userId
            print("🚗 MileageReportsViewModel: Initialized with userId: \(userId), userName: \(self.userName)")
        } else {
            print("⚠️ MileageReportsViewModel: No authenticated user, using userName: \(self.userName)")
        }
        
        // Load pay period settings and calculate current period
        payPeriodService.loadPayPeriodSettings { [weak self] success in
            guard let self = self else { return }
            
            if let (start, end) = self.payPeriodService.getCurrentPayPeriod() {
                self.currentPeriodStart = start
                self.currentPeriodEnd = end
                
                // Log the calculated period for debugging
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                print("📅 MileageReportsViewModel: Current period from PayPeriodService: \(dateFormatter.string(from: start)) to \(dateFormatter.string(from: end))")
            } else {
                // Fallback to default calculation if service fails
                print("⚠️ MileageReportsViewModel: Failed to get pay period from service, using fallback")
                self.setDefaultPayPeriod()
            }
        }
    }
    
    // Add callback support for updates
    func listenForMileageUpdates(completion: @escaping () -> Void) {
        self.updateCallback = completion
    }
    
    private func setDefaultPayPeriod() {
        // Fallback calculation using the old reference date
        let payPeriodFormatter = DateFormatter()
        payPeriodFormatter.dateFormat = "M/d/yyyy"
        payPeriodFormatter.locale = Locale(identifier: "en_US_POSIX")
        guard let referenceDate = payPeriodFormatter.date(from: "2/25/2024") else {
            return
        }
        
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        let today = Date()
        let daysSinceReference = calendar.dateComponents([.day], from: referenceStartOfDay, to: today).day ?? 0
        let periodLength = 14
        let periodsElapsed = daysSinceReference / periodLength
        
        if let currentStart = calendar.date(byAdding: .day, value: periodsElapsed * periodLength, to: referenceStartOfDay),
           let tempEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: currentStart),
           let currentEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) {
            self.currentPeriodStart = currentStart
            self.currentPeriodEnd = currentEnd
        }
    }
    
    /// Loads mileage records for the given pay period. If none provided, uses the current period.
    func loadRecords(forPayPeriodStart payPeriodStart: Date? = nil) {
        // If we're using the current period and it hasn't been set yet, wait for it
        if payPeriodStart == nil && currentPeriodStart == currentPeriodEnd {
            // Load pay period settings first
            payPeriodService.loadPayPeriodSettings { [weak self] success in
                guard let self = self else { return }
                
                if let (start, end) = self.payPeriodService.getCurrentPayPeriod() {
                    self.currentPeriodStart = start
                    self.currentPeriodEnd = end
                } else {
                    self.setDefaultPayPeriod()
                }
                
                // Now load records with the updated period
                self.loadRecordsInternal(forPayPeriodStart: nil)
            }
            return
        }
        
        loadRecordsInternal(forPayPeriodStart: payPeriodStart)
    }
    
    private func loadRecordsInternal(forPayPeriodStart payPeriodStart: Date? = nil) {
        let periodStart = payPeriodStart ?? currentPeriodStart
        let periodEnd: Date

        if let customStart = payPeriodStart {
            // Calculate end date for custom period using PayPeriodService
            if let settings = payPeriodService.payPeriodSettings,
               let (_, end) = payPeriodService.getPayPeriod(for: customStart, settings: settings) {
                periodEnd = end
            } else {
                // Fallback to 14-day period
                if let tempEnd = calendar.date(byAdding: .day, value: 13, to: customStart),
                   let customEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) {
                    periodEnd = customEnd
                } else {
                    periodEnd = currentPeriodEnd
                }
            }
        } else {
            periodEnd = currentPeriodEnd
        }

        // Log the date range we're querying
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        print("🚗 Loading mileage records from \(dateFormatter.string(from: periodStart)) to \(dateFormatter.string(from: periodEnd))")

        guard let userId = userId else {
            print("🚗 No userId available for mileage query")
            return
        }

        Task {
            do {
                print("🚗 Querying mileage reports by userId: \(userId)")
                let reports = try await DailyJobReportService.shared.getReports(
                    userId: userId,
                    startDate: periodStart,
                    endDate: periodEnd
                )

                await MainActor.run {
                    // Log how many documents were found
                    print("Found \(reports.count) reports for the period")

                    // Convert DailyJobReport to local wrapper models
                    self.records = reports.map { MileageRecordWrapper(from: $0) }

                    // Since we already filtered by date in the query, just sum all records
                    self.currentPeriodMileage = self.records.reduce(0) { $0 + $1.totalMileage }
                    print("🚗 Pay period mileage: \(self.currentPeriodMileage) miles from \(self.records.count) records")

                    // Also load month and year totals
                    self.loadYearAndMonthMileage()

                    // Notify listener of update
                    self.updateCallback?()
                }
            } catch {
                print("Error fetching mileage reports: \(error.localizedDescription)")
            }
        }
    }
    
    /// Calculate the mileage total for the selected period.
    func calculateMileage(forPeriodStart periodStart: Date, periodEnd: Date) {
        print("🚗 Calculating mileage for period...")
        print("   - Period start: \(periodStart)")
        print("   - Period end: \(periodEnd)")
        print("   - Total records available: \(records.count)")
        
        let currentRecords = records.filter { record in
            let inRange = record.date >= periodStart && record.date <= periodEnd
            if !inRange {
                print("   - Record date \(record.date) is outside range")
            }
            return inRange
        }
        
        currentPeriodMileage = currentRecords.reduce(0) { $0 + $1.totalMileage }
        
        // Log the calculation for debugging
        print("🚗 Calculated mileage for period: \(currentPeriodMileage) miles from \(currentRecords.count) records")
    }
    
    /// Loads records for the current calendar year and calculates:
    ///   - total mileage for the current month
    ///   - total mileage for the year
    func loadYearAndMonthMileage() {
        print("🚗 Loading year and month mileage totals...")

        let currentYear = calendar.component(.year, from: Date())

        // Start of year
        var startComps = DateComponents()
        startComps.year = currentYear
        startComps.month = 1
        startComps.day = 1
        let yearStart = calendar.date(from: startComps)!

        // End of year - set to last second of the year
        var endComps = DateComponents()
        endComps.year = currentYear
        endComps.month = 12
        endComps.day = 31
        endComps.hour = 23
        endComps.minute = 59
        endComps.second = 59
        let yearEnd = calendar.date(from: endComps)!

        // Log the year range for debugging
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        print("Loading year mileage from \(dateFormatter.string(from: yearStart)) to \(dateFormatter.string(from: yearEnd))")

        guard let userId = userId else {
            print("🚗 No userId available for year/month mileage query")
            return
        }

        Task {
            do {
                let reports = try await DailyJobReportService.shared.getReports(
                    userId: userId,
                    startDate: yearStart,
                    endDate: yearEnd
                )

                await MainActor.run {
                    // Log how many documents were found for the year
                    print("Found \(reports.count) reports for the year")

                    // Convert to tuples for processing
                    let allRecords = reports.map { (date: $0.date, mileage: $0.total_mileage) }

                    // Sum mileage for the entire year
                    self.yearMileage = allRecords.reduce(0) { $0 + $1.mileage }

                    // Sum mileage for the current month
                    let currentMonth = self.calendar.component(.month, from: Date())
                    let monthRecords = allRecords.filter {
                        self.calendar.component(.month, from: $0.date) == currentMonth &&
                        self.calendar.component(.year, from: $0.date) == currentYear
                    }
                    self.monthMileage = monthRecords.reduce(0) { $0 + $1.mileage }

                    print("🚗 Calculated year mileage: \(self.yearMileage) miles from \(allRecords.count) total records")
                    print("🚗 Calculated month mileage: \(self.monthMileage) miles from \(monthRecords.count) month records")
                    print("🚗 Current year: \(currentYear), Current month: \(currentMonth)")

                    // Notify listener of update
                    self.updateCallback?()
                }
            } catch {
                print("Error fetching yearly reports: \(error.localizedDescription)")
            }
        }
    }
}
