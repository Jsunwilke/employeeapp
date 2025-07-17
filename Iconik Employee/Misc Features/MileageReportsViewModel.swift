import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import SwiftUI
import Firebase
import FirebaseAuth

class MileageReportsViewModel: ObservableObject {
    @Published var currentPeriodMileage: Double = 0
    @Published var monthMileage: Double = 0
    @Published var yearMileage: Double = 0
    @Published var records: [MileageRecordWrapper] = []
    
    var userName: String
    var userId: String?
    
    let calendar = Calendar.current
    let currentPeriodStart: Date
    let currentPeriodEnd: Date
    
    // Local wrapper model to hold Firestore data
    struct MileageRecordWrapper: Identifiable {
        let id: String // Firestore document ID
        let date: Date
        let totalMileage: Double
        let schoolName: String
    }
    
    init(userName: String) {
        self.userName = userName
        
        // Get the current user's ID for more reliable filtering
        if let currentUser = Auth.auth().currentUser {
            self.userId = currentUser.uid
        }
        
        // Calculate the current pay period based on a reference date (2/25/2024).
        let payPeriodFormatter = DateFormatter()
        payPeriodFormatter.dateFormat = "M/d/yyyy"
        payPeriodFormatter.locale = Locale(identifier: "en_US_POSIX")
        guard let referenceDate = payPeriodFormatter.date(from: "2/25/2024") else {
            fatalError("Invalid reference date format.")
        }
        
        // Make sure reference date is start of day
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        
        let today = Date()
        let daysSinceReference = calendar.dateComponents([.day], from: referenceStartOfDay, to: today).day ?? 0
        let periodLength = 14
        let periodsElapsed = daysSinceReference / periodLength
        
        guard let currentStart = calendar.date(byAdding: .day, value: periodsElapsed * periodLength, to: referenceStartOfDay) else {
            fatalError("Error calculating current pay period start date.")
        }
        
        // Calculate end date and set it to end of day (23:59:59)
        guard let tempEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: currentStart),
              let currentEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
            fatalError("Error calculating current pay period end date.")
        }
        
        self.currentPeriodStart = currentStart
        self.currentPeriodEnd = currentEnd
        
        // Log the calculated period for debugging
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        print("Current period calculated as: \(dateFormatter.string(from: currentStart)) to \(dateFormatter.string(from: currentEnd))")
    }
    
    /// Loads mileage records for the given pay period. If none provided, uses the current period.
    func loadRecords(forPayPeriodStart payPeriodStart: Date? = nil) {
        let periodStart = payPeriodStart ?? currentPeriodStart
        
        // Calculate end date and set it to end of day (23:59:59)
        guard let tempEnd = calendar.date(byAdding: .day, value: 13, to: periodStart),
              let periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
            print("Error calculating period end date")
            return
        }
        
        // Log the date range we're querying
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        print("Loading mileage records from \(dateFormatter.string(from: periodStart)) to \(dateFormatter.string(from: periodEnd))")
        
        let db = Firestore.firestore()
        
        // Build query - prefer userId if available, fallback to yourName
        let baseCollection = db.collection("dailyJobReports")
        let query: Query
        
        if let userId = userId {
            print("Querying mileage reports by userId: \(userId)")
            query = baseCollection.whereField("userId", isEqualTo: userId)
                .whereField("date", isGreaterThanOrEqualTo: periodStart)
                .whereField("date", isLessThanOrEqualTo: periodEnd)
        } else {
            print("Querying mileage reports by yourName: \(userName)")
            query = baseCollection.whereField("yourName", isEqualTo: userName)
                .whereField("date", isGreaterThanOrEqualTo: periodStart)
                .whereField("date", isLessThanOrEqualTo: periodEnd)
        }
        
        query.getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error fetching mileage reports: \(error.localizedDescription)")
                        
                        // More detailed error logging
                        if (error as NSError).code == 7 { // Permission denied
                            print("Permission denied. User ID: \(self?.userId ?? "nil"), UserName: \(self?.userName ?? "nil")")
                        }
                        return
                    }
                    guard let documents = snapshot?.documents else { return }
                    
                    // Log how many documents were found
                    print("Found \(documents.count) reports for the period")
                    
                    // Convert Firestore documents to local models
                    self?.records = documents.compactMap { doc in
                        let data = doc.data()
                        
                        guard let timestamp = data["date"] as? Timestamp else {
                            print("Missing date in document: \(doc.documentID)")
                            return nil
                        }
                        let date = timestamp.dateValue()
                        
                        // Log each report date for debugging
                        print("Report date: \(dateFormatter.string(from: date))")
                        
                        let mileage = data["totalMileage"] as? Double ?? 0.0
                        
                        // Pull the school/destination name from Firestore
                        let schoolName = data["schoolOrDestination"] as? String ?? ""
                        
                        return MileageRecordWrapper(
                            id: doc.documentID,
                            date: date,
                            totalMileage: mileage,
                            schoolName: schoolName
                        )
                    }
                    
                    self?.calculateMileage(forPeriodStart: periodStart, periodEnd: periodEnd)
                }
            }
    }
    
    /// Calculate the mileage total for the selected period.
    func calculateMileage(forPeriodStart periodStart: Date, periodEnd: Date) {
        let currentRecords = records.filter { $0.date >= periodStart && $0.date <= periodEnd }
        currentPeriodMileage = currentRecords.reduce(0) { $0 + $1.totalMileage }
        
        // Log the calculation for debugging
        print("Calculated mileage for period: \(currentPeriodMileage) miles from \(currentRecords.count) records")
    }
    
    /// Loads records for the current calendar year and calculates:
    ///   - total mileage for the current month
    ///   - total mileage for the year
    func loadYearAndMonthMileage() {
        let db = Firestore.firestore()
        
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
        
        // Build query - prefer userId if available, fallback to yourName
        let baseCollection = db.collection("dailyJobReports")
        let query: Query
        
        if let userId = userId {
            print("Querying mileage reports by userId: \(userId)")
            query = baseCollection.whereField("userId", isEqualTo: userId)
                .whereField("date", isGreaterThanOrEqualTo: yearStart)
                .whereField("date", isLessThanOrEqualTo: yearEnd)
        } else {
            print("Querying mileage reports by yourName: \(userName)")
            query = baseCollection.whereField("yourName", isEqualTo: userName)
                .whereField("date", isGreaterThanOrEqualTo: yearStart)
                .whereField("date", isLessThanOrEqualTo: yearEnd)
        }
        
        query.getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error fetching yearly reports: \(error.localizedDescription)")
                        
                        // More detailed error logging
                        if (error as NSError).code == 7 { // Permission denied
                            print("Permission denied for yearly reports. User ID: \(self?.userId ?? "nil"), UserName: \(self?.userName ?? "nil")")
                        }
                        return
                    }
                    guard let documents = snapshot?.documents else { return }
                    
                    // Log how many documents were found for the year
                    print("Found \(documents.count) reports for the year")
                    
                    let allRecords = documents.compactMap { doc -> (date: Date, mileage: Double)? in
                        let data = doc.data()
                        guard let timestamp = data["date"] as? Timestamp else { return nil }
                        let date = timestamp.dateValue()
                        let mileage = data["totalMileage"] as? Double ?? 0.0
                        return (date, mileage)
                    }
                    
                    // Sum mileage for the entire year
                    self?.yearMileage = allRecords.reduce(0) { $0 + $1.mileage }
                    
                    // Sum mileage for the current month
                    let currentMonth = self?.calendar.component(.month, from: Date()) ?? 1
                    let monthRecords = allRecords.filter {
                        self?.calendar.component(.month, from: $0.date) == currentMonth &&
                        self?.calendar.component(.year, from: $0.date) == currentYear
                    }
                    self?.monthMileage = monthRecords.reduce(0) { $0 + $1.mileage }
                    
                    print("Calculated year mileage: \(self?.yearMileage ?? 0) miles")
                    print("Calculated month mileage: \(self?.monthMileage ?? 0) miles")
                }
            }
    }
}
