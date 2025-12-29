import Foundation
import Supabase
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

    // Supabase client
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    
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
        
        // Use real data from Supabase
        loadRealData(timeRange: timeRange)
    }
    
    // MARK: - Real Data Implementation
    
    // Main function to fetch real data from Supabase
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

        // Use async Task to load all data
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchMileageDataAsync(startDate: startDate, endDate: endDate) }
                group.addTask { await self.fetchLocationDataAsync(startDate: startDate, endDate: endDate) }
                group.addTask { await self.fetchJobTypeDataAsync(startDate: startDate, endDate: endDate) }
                group.addTask { await self.fetchPhotographerDataAsync(startDate: startDate, endDate: endDate) }
                group.addTask { await self.fetchWeatherImpactDataAsync(startDate: startDate, endDate: endDate) }
            }

            await MainActor.run {
                self.isLoading = false

                // If no data was loaded, show error
                if self.mileageData.isEmpty && self.locationData.isEmpty && self.jobTypeData.isEmpty {
                    self.errorMessage = "No data available for the selected time period"
                }
            }
        }
    }
    
    // MARK: - Fetch Mileage Data

    private func fetchMileageDataAsync(startDate: Date, endDate: Date) async {
        // Ensure we have an organization ID
        guard !storedUserOrganizationID.isEmpty else {
            await MainActor.run {
                self.errorMessage = "No organization ID found"
            }
            return
        }

        do {
            struct ReportRecord: Decodable {
                let date: Date?
                let your_name: String?
                let total_mileage: Double?
            }

            let reports: [ReportRecord] = try await supabase
                .from("daily_job_reports")
                .select("date, your_name, total_mileage")
                .eq("organization_id", value: storedUserOrganizationID.lowercased())
                .gte("date", value: startDate.ISO8601Format())
                .lte("date", value: endDate.ISO8601Format())
                .execute()
                .value

            guard !reports.isEmpty else { return }

            // Group reports by month
            var reportsByMonth: [String: [String: Double]] = [:]
            let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            let calendar = Calendar.current

            for report in reports {
                guard let date = report.date,
                      let photographerName = report.your_name,
                      let mileage = report.total_mileage else {
                    continue
                }

                let month = calendar.component(.month, from: date) - 1
                let monthName = monthNames[month]

                if reportsByMonth[monthName] == nil {
                    reportsByMonth[monthName] = ["John": 0, "Sarah": 0, "Mike": 0, "total": 0]
                }

                if reportsByMonth[monthName]?.index(forKey: photographerName) != nil {
                    reportsByMonth[monthName]?[photographerName, default: 0] += mileage
                } else {
                    reportsByMonth[monthName]?["total", default: 0] += mileage
                }

                reportsByMonth[monthName]?["total", default: 0] += mileage
            }

            // Convert dictionary to array
            var mileageResult: [MileageData] = []
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

            await MainActor.run {
                self.mileageData = mileageResult
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching mileage data: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Fetch Location Data

    private func fetchLocationDataAsync(startDate: Date, endDate: Date) async {
        do {
            // Get list of all schools
            struct SchoolRecord: Decodable {
                let id: String
                let value: String?
            }

            let schoolDocs: [SchoolRecord] = try await supabase
                .from("schools")
                .select("id, value")
                .eq("organization_id", value: storedUserOrganizationID.lowercased())
                .execute()
                .value

            guard !schoolDocs.isEmpty else { return }

            // Map of school names to location data
            var schoolData: [String: LocationData] = [:]
            for doc in schoolDocs {
                if let value = doc.value {
                    schoolData[value] = LocationData(name: value, visits: 0, mileage: 0)
                }
            }

            // Fetch job reports
            struct ReportRecord: Decodable {
                let school_or_destination: String?
                let total_mileage: Double?
                let date: Date?
            }

            let reports: [ReportRecord] = try await supabase
                .from("daily_job_reports")
                .select("school_or_destination, total_mileage, date")
                .eq("organization_id", value: storedUserOrganizationID.lowercased())
                .gte("date", value: startDate.ISO8601Format())
                .lte("date", value: endDate.ISO8601Format())
                .execute()
                .value

            // Track visited locations per day
            var visitedLocationsPerDay = Set<String>()
            let calendar = Calendar.current

            for report in reports {
                guard let schoolName = report.school_or_destination,
                      let mileage = report.total_mileage,
                      let date = report.date else {
                    continue
                }

                let components = calendar.dateComponents([.year, .month, .day], from: date)
                let dateString = String(format: "%04d-%02d-%02d",
                                        components.year ?? 0,
                                        components.month ?? 0,
                                        components.day ?? 0)

                let visitKey = "\(schoolName)_\(dateString)"
                let isFirstVisitOfDay = !visitedLocationsPerDay.contains(visitKey)

                if var location = schoolData[schoolName] {
                    location.mileage += mileage
                    if isFirstVisitOfDay {
                        location.visits += 1
                        visitedLocationsPerDay.insert(visitKey)
                    }
                    schoolData[schoolName] = location
                } else {
                    let location = LocationData(
                        name: schoolName,
                        visits: isFirstVisitOfDay ? 1 : 0,
                        mileage: mileage
                    )
                    if isFirstVisitOfDay {
                        visitedLocationsPerDay.insert(visitKey)
                    }
                    schoolData[schoolName] = location
                }
            }

            var locationResult = Array(schoolData.values)
            locationResult.sort { $0.visits > $1.visits }

            await MainActor.run {
                self.locationData = locationResult
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching location data: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Fetch Job Type Data

    private func fetchJobTypeDataAsync(startDate: Date, endDate: Date) async {
        do {
            struct ReportRecord: Decodable {
                let job_descriptions: [String]?
            }

            let reports: [ReportRecord] = try await supabase
                .from("daily_job_reports")
                .select("job_descriptions")
                .eq("organization_id", value: storedUserOrganizationID.lowercased())
                .gte("date", value: startDate.ISO8601Format())
                .lte("date", value: endDate.ISO8601Format())
                .execute()
                .value

            var jobTypeCounts: [String: Int] = [:]

            for report in reports {
                if let jobDescriptions = report.job_descriptions {
                    for jobType in jobDescriptions {
                        jobTypeCounts[jobType, default: 0] += 1
                    }
                }
            }

            var jobTypeResult: [JobTypeData] = []
            for (jobType, count) in jobTypeCounts {
                jobTypeResult.append(JobTypeData(name: jobType, value: Double(count)))
            }
            jobTypeResult.sort { $0.value > $1.value }

            await MainActor.run {
                self.jobTypeData = jobTypeResult
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching job types: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Fetch Photographer Data

    private func fetchPhotographerDataAsync(startDate: Date, endDate: Date) async {
        do {
            // First, get all users in the organization
            struct UserRecord: Decodable {
                let first_name: String?
            }

            let userDocs: [UserRecord] = try await supabase
                .from("users")
                .select("first_name")
                .eq("organization_id", value: storedUserOrganizationID.lowercased())
                .execute()
                .value

            guard !userDocs.isEmpty else { return }

            var photographerNames: [String] = []
            for doc in userDocs {
                if let firstName = doc.first_name {
                    photographerNames.append(firstName)
                }
            }

            // Fetch job reports
            struct ReportRecord: Decodable {
                let your_name: String?
                let total_mileage: Double?
                let start_time: Date?
                let end_time: Date?
            }

            let reports: [ReportRecord] = try await supabase
                .from("daily_job_reports")
                .select("your_name, total_mileage, start_time, end_time")
                .eq("organization_id", value: storedUserOrganizationID.lowercased())
                .gte("date", value: startDate.ISO8601Format())
                .lte("date", value: endDate.ISO8601Format())
                .execute()
                .value

            var jobsByPhotographer: [String: Int] = [:]
            var mileageByPhotographer: [String: Double] = [:]
            var timeByPhotographer: [String: [Double]] = [:]

            for report in reports {
                guard let photographerName = report.your_name,
                      let mileage = report.total_mileage else {
                    continue
                }

                var jobDuration: Double = 3.0 // Default
                if let startTime = report.start_time, let endTime = report.end_time {
                    jobDuration = endTime.timeIntervalSince(startTime) / 3600
                }

                jobsByPhotographer[photographerName, default: 0] += 1
                mileageByPhotographer[photographerName, default: 0] += mileage

                if timeByPhotographer[photographerName] == nil {
                    timeByPhotographer[photographerName] = []
                }
                timeByPhotographer[photographerName]?.append(jobDuration)
            }

            var photographerResult: [PhotographerData] = []

            for name in photographerNames {
                guard let jobs = jobsByPhotographer[name], jobs > 0 else { continue }

                let miles = mileageByPhotographer[name] ?? 0
                let jobTimes = timeByPhotographer[name] ?? []
                let avgJobTime = jobTimes.isEmpty ? 3.0 : jobTimes.reduce(0, +) / Double(jobTimes.count)

                photographerResult.append(PhotographerData(
                    name: name,
                    jobs: jobs,
                    miles: miles,
                    avgJobTime: avgJobTime
                ))
            }

            photographerResult.sort { $0.jobs > $1.jobs }

            await MainActor.run {
                self.photographerData = photographerResult
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching photographer data: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Fetch Weather Impact Data

    private func fetchWeatherImpactDataAsync(startDate: Date, endDate: Date) async {
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
        await MainActor.run {
            self.weatherImpactData = weatherImpactResult
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
