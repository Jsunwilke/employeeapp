import Foundation
import Firebase
import FirebaseFirestore
import SwiftUI
import MapKit

// MARK: - Data Models

struct MileageData: Identifiable {
    let id = UUID()
    let month: String
    let john: Double
    let sarah: Double
    let mike: Double
    let total: Double
    
    // This allows dynamic access to properties by name
    subscript(key: String) -> Any? {
        switch key {
        case "month": return month
        case "John": return john
        case "Sarah": return sarah
        case "Mike": return mike
        case "total": return total
        default: return nil
        }
    }
}

struct LocationData: Identifiable {
    let id = UUID()
    let name: String
    var visits: Int  // Changed to var to allow mutation
    var mileage: Double  // Changed to var to allow mutation
}

struct JobTypeData: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
}

struct PhotographerData: Identifiable {
    let id = UUID()
    let name: String
    let jobs: Int
    let miles: Double
    let avgJobTime: Double
}

struct WeatherImpactData: Identifiable {
    let id = UUID()
    let weather: String
    let jobs: Int
    let onTimeArrival: Int
}

struct MonthlyRevenueData: Identifiable {
    let id = UUID()
    let month: String
    let revenue: Double
    let mileageReimbursement: Double
}

class StatsViewModel: ObservableObject {
    // Published properties to update UI
    @Published var mileageData: [MileageData] = []
    @Published var locationData: [LocationData] = []
    @Published var jobTypeData: [JobTypeData] = []
    @Published var photographerData: [PhotographerData] = []
    @Published var weatherImpactData: [WeatherImpactData] = []
    @Published var monthlyRevenue: [MonthlyRevenueData] = []
    @Published var isLoading: Bool = true
    @Published var errorMessage: String = ""
    
    // AppStorage for user organization ID (needed for filtering data)
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    
    // Firestore instance
    private let db = Firestore.firestore()
    
    // Computed properties for summary statistics
    var totalMileage: Int {
        Int(mileageData.reduce(0) { $0 + $1.total })
    }
    
    var totalJobs: Int {
        Int(jobTypeData.reduce(0) { $0 + $1.value })
    }
    
    var totalPhotographers: Int {
        photographerData.count
    }
    
    var totalLocations: Int {
        locationData.count
    }
    
    var avgMileagePerMonth: Int {
        if mileageData.isEmpty { return 0 }
        return totalMileage / max(mileageData.count, 1)
    }
    
    var avgJobsPerPhotographer: Int {
        if photographerData.isEmpty { return 0 }
        return totalJobs / max(totalPhotographers, 1)
    }
    
    var avgVisitsPerLocation: Double {
        if locationData.isEmpty { return 0 }
        let totalVisits = locationData.reduce(0) { $0 + $1.visits }
        return Double(totalVisits) / Double(max(totalLocations, 1))
    }
    
    // Get list of photographer names for charting
    var photographerNames: [String] {
        photographerData.map { $0.name }.prefix(3).map { $0 }
    }
    
    // MARK: - Data Loading
    
    func loadData(timeRange: TimeRange) {
        isLoading = true
        errorMessage = ""
        
        // Use real data from Firestore
        loadRealData(timeRange: timeRange)
    }
    
    // MARK: - Real Data Implementation
    
    // Main function to fetch real data from Firestore
    func loadRealData(timeRange: TimeRange) {
        // Get date range based on selected time frame
        let (startDate, endDate) = getDateRange(for: timeRange)
        
        // Reset all data arrays
        mileageData = []
        locationData = []
        jobTypeData = []
        photographerData = []
        weatherImpactData = []
        monthlyRevenue = []
        
        // Create dispatch group to track when all data is loaded
        let group = DispatchGroup()
        
        // 1. Fetch mileage data
        group.enter()
        fetchMileageData(startDate: startDate, endDate: endDate) {
            group.leave()
        }
        
        // 2. Fetch location data
        group.enter()
        fetchLocationData(startDate: startDate, endDate: endDate) {
            group.leave()
        }
        
        // 3. Fetch job type data
        group.enter()
        fetchJobTypeData(startDate: startDate, endDate: endDate) {
            group.leave()
        }
        
        // 4. Fetch photographer data
        group.enter()
        fetchPhotographerData(startDate: startDate, endDate: endDate) {
            group.leave()
        }
        
        // 5. Fetch weather impact data
        group.enter()
        fetchWeatherImpactData(startDate: startDate, endDate: endDate) {
            group.leave()
        }
        
        // Handle completion of all data fetching
        group.notify(queue: .main) {
            self.isLoading = false
            
            // If no data was loaded, show error
            if self.mileageData.isEmpty && self.locationData.isEmpty && self.jobTypeData.isEmpty {
                self.errorMessage = "No data available for the selected time period"
            }
        }
    }
    
    // MARK: - Fetch Mileage Data
    
    private func fetchMileageData(startDate: Date, endDate: Date, completion: @escaping () -> Void) {
        // Ensure we have an organization ID
        guard !storedUserOrganizationID.isEmpty else {
            DispatchQueue.main.async {
                self.errorMessage = "No organization ID found"
                completion()
            }
            return
        }
        
        db.collection("dailyJobReports")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID)
            .whereField("date", isGreaterThanOrEqualTo: startDate)
            .whereField("date", isLessThanOrEqualTo: endDate)
            .getDocuments { snapshot, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Error fetching mileage data: \(error.localizedDescription)"
                        completion()
                    }
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    // No documents found
                    DispatchQueue.main.async {
                        completion()
                    }
                    return
                }
                
                // Group reports by month
                var reportsByMonth: [String: [String: Double]] = [:]
                
                // Map month numbers to names
                let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                
                // Process each document
                for document in documents {
                    let data = document.data()
                    
                    // Extract the data we need
                    guard let dateTimestamp = data["date"] as? Timestamp,
                          let photographerName = data["yourName"] as? String,
                          let mileage = data["totalMileage"] as? Double else {
                        continue
                    }
                    
                    let date = dateTimestamp.dateValue()
                    let calendar = Calendar.current
                    let month = calendar.component(.month, from: date) - 1 // 0-based index
                    let monthName = monthNames[month]
                    
                    // Initialize month data if needed
                    if reportsByMonth[monthName] == nil {
                        reportsByMonth[monthName] = ["John": 0, "Sarah": 0, "Mike": 0, "total": 0]
                    }
                    
                    // Add mileage to the appropriate photographer
                    if let index = reportsByMonth[monthName]?.index(forKey: photographerName) {
                        reportsByMonth[monthName]?[photographerName, default: 0] += mileage
                    } else {
                        // If not one of the main photographers, just add to total
                        reportsByMonth[monthName]?["total", default: 0] += mileage
                    }
                    
                    // Always add to total
                    reportsByMonth[monthName]?["total", default: 0] += mileage
                }
                
                // Convert dictionary to array
                var mileageResult: [MileageData] = []
                
                // Sort by month index
                let sortedMonths = reportsByMonth.keys.sorted { key1, key2 in
                    guard let index1 = monthNames.firstIndex(of: key1),
                          let index2 = monthNames.firstIndex(of: key2) else {
                        return false
                    }
                    return index1 < index2
                }
                
                for month in sortedMonths {
                    guard let monthData = reportsByMonth[month] else { continue }
                    
                    let item = MileageData(
                        month: month,
                        john: monthData["John"] ?? 0,
                        sarah: monthData["Sarah"] ?? 0,
                        mike: monthData["Mike"] ?? 0,
                        total: monthData["total"] ?? 0
                    )
                    mileageResult.append(item)
                }
                
                DispatchQueue.main.async {
                    self.mileageData = mileageResult
                    completion()
                }
            }
    }
    
    // MARK: - Fetch Location Data
    
    private func fetchLocationData(startDate: Date, endDate: Date, completion: @escaping () -> Void) {
        // Get list of all schools
        db.collection("schools")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID)
            .getDocuments { snapshot, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Error fetching schools: \(error.localizedDescription)"
                        completion()
                    }
                    return
                }
                
                guard let schoolDocs = snapshot?.documents, !schoolDocs.isEmpty else {
                    DispatchQueue.main.async {
                        completion()
                    }
                    return
                }
                
                // Map of school names to IDs and create initial location data
                var schoolData: [String: LocationData] = [:]
                for doc in schoolDocs {
                    let data = doc.data()
                    if let value = data["value"] as? String {
                        let locationData = LocationData(
                            name: value,
                            visits: 0,
                            mileage: 0
                        )
                        schoolData[value] = locationData
                    }
                }
                
                // Now fetch job reports to count visits and mileage for each school
                self.db.collection("dailyJobReports")
                    .whereField("organizationID", isEqualTo: self.storedUserOrganizationID)
                    .whereField("date", isGreaterThanOrEqualTo: startDate)
                    .whereField("date", isLessThanOrEqualTo: endDate)
                    .getDocuments { snapshot, error in
                        if let error = error {
                            DispatchQueue.main.async {
                                self.errorMessage = "Error fetching reports: \(error.localizedDescription)"
                                completion()
                            }
                            return
                        }
                        
                        guard let documents = snapshot?.documents else {
                            DispatchQueue.main.async {
                                completion()
                            }
                            return
                        }
                        
                        // Track visited locations per day with a composite key "schoolName_dateString"
                        var visitedLocationsPerDay = Set<String>()
                        
                        // Process each job report
                        for document in documents {
                            let data = document.data()
                            
                            guard let schoolName = data["schoolOrDestination"] as? String,
                                  let mileage = data["totalMileage"] as? Double,
                                  let dateTimestamp = data["date"] as? Timestamp else {
                                continue
                            }
                            
                            // Convert timestamp to date string (YYYY-MM-DD) for tracking unique visits
                            let date = dateTimestamp.dateValue()
                            let calendar = Calendar.current
                            let components = calendar.dateComponents([.year, .month, .day], from: date)
                            let dateString = String(format: "%04d-%02d-%02d",
                                                    components.year ?? 0,
                                                    components.month ?? 0,
                                                    components.day ?? 0)
                            
                            // Create composite key for location+date
                            let visitKey = "\(schoolName)_\(dateString)"
                            
                            // Check if we already counted a visit to this location on this day
                            let isFirstVisitOfDay = !visitedLocationsPerDay.contains(visitKey)
                            
                            // Update school data
                            if var location = schoolData[schoolName] {
                                // Always add mileage
                                location.mileage += mileage
                                
                                // Only increment visit count if it's the first visit of the day
                                if isFirstVisitOfDay {
                                    location.visits += 1
                                    visitedLocationsPerDay.insert(visitKey)
                                }
                                
                                schoolData[schoolName] = location
                            } else {
                                // School not in our list, create new entry
                                let location = LocationData(
                                    name: schoolName,
                                    visits: isFirstVisitOfDay ? 1 : 0,  // Only count if first visit
                                    mileage: mileage
                                )
                                
                                if isFirstVisitOfDay {
                                    visitedLocationsPerDay.insert(visitKey)
                                }
                                
                                schoolData[schoolName] = location
                            }
                        }
                        
                        // Convert to array and sort by visits
                        var locationResult = Array(schoolData.values)
                        locationResult.sort { $0.visits > $1.visits }
                        
                        DispatchQueue.main.async {
                            self.locationData = locationResult
                            completion()
                        }
                    }
            }
    }
    
    // MARK: - Fetch Job Type Data
    
    private func fetchJobTypeData(startDate: Date, endDate: Date, completion: @escaping () -> Void) {
        db.collection("dailyJobReports")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID)
            .whereField("date", isGreaterThanOrEqualTo: startDate)
            .whereField("date", isLessThanOrEqualTo: endDate)
            .getDocuments { snapshot, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Error fetching job types: \(error.localizedDescription)"
                        completion()
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    DispatchQueue.main.async {
                        completion()
                    }
                    return
                }
                
                // Count job descriptions
                var jobTypeCounts: [String: Int] = [:]
                
                for document in documents {
                    let data = document.data()
                    
                    // Each report can have multiple job descriptions
                    if let jobDescriptions = data["jobDescriptions"] as? [String] {
                        for jobType in jobDescriptions {
                            jobTypeCounts[jobType, default: 0] += 1
                        }
                    }
                }
                
                // Convert to JobTypeData array
                var jobTypeResult: [JobTypeData] = []
                
                for (jobType, count) in jobTypeCounts {
                    let item = JobTypeData(
                        name: jobType,
                        value: Double(count)
                    )
                    jobTypeResult.append(item)
                }
                
                // Sort by count
                jobTypeResult.sort { $0.value > $1.value }
                
                DispatchQueue.main.async {
                    self.jobTypeData = jobTypeResult
                    completion()
                }
            }
    }
    
    // MARK: - Fetch Photographer Data
    
    private func fetchPhotographerData(startDate: Date, endDate: Date, completion: @escaping () -> Void) {
        // First, get all users in the organization who are photographers
        db.collection("users")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID)
            .getDocuments { snapshot, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Error fetching users: \(error.localizedDescription)"
                        completion()
                    }
                    return
                }
                
                guard let userDocs = snapshot?.documents, !userDocs.isEmpty else {
                    DispatchQueue.main.async {
                        completion()
                    }
                    return
                }
                
                // Extract user names
                var photographerNames: [String] = []
                for doc in userDocs {
                    let data = doc.data()
                    if let firstName = data["firstName"] as? String {
                        photographerNames.append(firstName)
                    }
                }
                
                // Now fetch job reports to count jobs and mileage for each photographer
                self.db.collection("dailyJobReports")
                    .whereField("organizationID", isEqualTo: self.storedUserOrganizationID)
                    .whereField("date", isGreaterThanOrEqualTo: startDate)
                    .whereField("date", isLessThanOrEqualTo: endDate)
                    .getDocuments { snapshot, error in
                        if let error = error {
                            DispatchQueue.main.async {
                                self.errorMessage = "Error fetching reports: \(error.localizedDescription)"
                                completion()
                            }
                            return
                        }
                        
                        guard let documents = snapshot?.documents else {
                            DispatchQueue.main.async {
                                completion()
                            }
                            return
                        }
                        
                        // Group reports by photographer
                        var jobsByPhotographer: [String: Int] = [:]
                        var mileageByPhotographer: [String: Double] = [:]
                        var timeByPhotographer: [String: [Double]] = [:]
                        
                        // Process each job report
                        for document in documents {
                            let data = document.data()
                            
                            guard let photographerName = data["yourName"] as? String,
                                  let mileage = data["totalMileage"] as? Double else {
                                continue
                            }
                            
                            // Calculate job duration if start and end times are available
                            var jobDuration: Double = 0
                            if let startTimestamp = data["startTime"] as? Timestamp,
                               let endTimestamp = data["endTime"] as? Timestamp {
                                let startDate = startTimestamp.dateValue()
                                let endDate = endTimestamp.dateValue()
                                jobDuration = endDate.timeIntervalSince(startDate) / 3600 // hours
                            } else {
                                // Default to average job time if not specified
                                jobDuration = 3.0
                            }
                            
                            // Update counts
                            jobsByPhotographer[photographerName, default: 0] += 1
                            mileageByPhotographer[photographerName, default: 0] += mileage
                            
                            if timeByPhotographer[photographerName] == nil {
                                timeByPhotographer[photographerName] = []
                            }
                            timeByPhotographer[photographerName]?.append(jobDuration)
                        }
                        
                        // Convert to PhotographerData array
                        var photographerResult: [PhotographerData] = []
                        
                        for name in photographerNames {
                            // Skip photographers with no data
                            guard let jobs = jobsByPhotographer[name], jobs > 0 else {
                                continue
                            }
                            
                            let miles = mileageByPhotographer[name] ?? 0
                            
                            // Calculate average job time
                            let jobTimes = timeByPhotographer[name] ?? []
                            let avgJobTime = jobTimes.isEmpty ? 3.0 : jobTimes.reduce(0, +) / Double(jobTimes.count)
                            
                            let item = PhotographerData(
                                name: name,
                                jobs: jobs,
                                miles: miles,
                                avgJobTime: avgJobTime
                            )
                            photographerResult.append(item)
                        }
                        
                        // Sort by number of jobs
                        photographerResult.sort { $0.jobs > $1.jobs }
                        
                        DispatchQueue.main.async {
                            self.photographerData = photographerResult
                            completion()
                        }
                    }
            }
    }
    
    // MARK: - Fetch Weather Impact Data
    
    private func fetchWeatherImpactData(startDate: Date, endDate: Date, completion: @escaping () -> Void) {
        // Since we don't have actual weather data in the database,
        // we'll create a reasonable approximation based on seasons and known weather patterns
        
        // Create mock weather impact data
        let weatherImpactResult: [WeatherImpactData] = [
            WeatherImpactData(weather: "Clear", jobs: 320, onTimeArrival: 95),
            WeatherImpactData(weather: "Cloudy", jobs: 280, onTimeArrival: 92),
            WeatherImpactData(weather: "Rain", jobs: 180, onTimeArrival: 85),
            WeatherImpactData(weather: "Snow", jobs: 90, onTimeArrival: 70),
            WeatherImpactData(weather: "Fog", jobs: 60, onTimeArrival: 80)
        ]
        
        // In a real implementation, we would analyze job reports and correlate with weather data
        // For now, use the mock data
        DispatchQueue.main.async {
            self.weatherImpactData = weatherImpactResult
            completion()
        }
    }
    
    // MARK: - Helper Methods
    
    // Helper function to get date range for queries
    private func getDateRange(for timeRange: TimeRange) -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()
        let endDate = now
        
        let startDate: Date
        
        switch timeRange {
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .quarter:
            startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
        
        return (startDate, endDate)
    }
}
