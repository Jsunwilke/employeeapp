//
//  MileageData.swift
//  Iconik Employee
//
//  Created by administrator on 4/27/25.
//


import Foundation
import Firebase
import FirebaseFirestore
import SwiftUI

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
    let visits: Int
    let mileage: Double
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
        ["John", "Sarah", "Mike"]
    }
    
    // MARK: - Data Loading
    
    func loadData(timeRange: TimeRange) {
        isLoading = true
        errorMessage = ""
        
        // In a real app, this would fetch from Firestore
        // Here we'll simulate a network delay and load mock data
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.loadMockData(timeRange: timeRange)
            self.isLoading = false
        }
    }
    
    private func loadMockData(timeRange: TimeRange) {
        do {
            // 1. Mock Mileage Data - Per employee per month
            let mockMileageData = [
                MileageData(month: "Jan", john: 450, sarah: 380, mike: 320, total: 1150),
                MileageData(month: "Feb", john: 420, sarah: 400, mike: 310, total: 1130),
                MileageData(month: "Mar", john: 380, sarah: 410, mike: 290, total: 1080),
                MileageData(month: "Apr", john: 490, sarah: 370, mike: 340, total: 1200),
                MileageData(month: "May", john: 510, sarah: 390, mike: 360, total: 1260),
                MileageData(month: "Jun", john: 460, sarah: 420, mike: 330, total: 1210),
                MileageData(month: "Jul", john: 400, sarah: 360, mike: 300, total: 1060),
                MileageData(month: "Aug", john: 480, sarah: 430, mike: 350, total: 1260),
                MileageData(month: "Sep", john: 520, sarah: 450, mike: 370, total: 1340),
                MileageData(month: "Oct", john: 490, sarah: 420, mike: 330, total: 1240),
                MileageData(month: "Nov", john: 460, sarah: 390, mike: 320, total: 1170),
                MileageData(month: "Dec", john: 430, sarah: 370, mike: 300, total: 1100)
            ]
            
            // 2. Mock Location Data - Schools/locations with count of visits
            let mockLocationData = [
                LocationData(name: "Lincoln High School", visits: 28, mileage: 980),
                LocationData(name: "Washington Elementary", visits: 23, mileage: 620),
                LocationData(name: "Jefferson Middle School", visits: 21, mileage: 840),
                LocationData(name: "Roosevelt Academy", visits: 18, mileage: 720),
                LocationData(name: "Kennedy High School", visits: 15, mileage: 560),
                LocationData(name: "Adams Elementary", visits: 13, mileage: 340),
                LocationData(name: "Madison Middle School", visits: 12, mileage: 480),
                LocationData(name: "Other Locations", visits: 42, mileage: 1260)
            ]
            
            // 3. Mock Job Type Data - Distribution of job types
            let mockJobTypeData = [
                JobTypeData(name: "Fall Original Day", value: 180),
                JobTypeData(name: "Spring Photos", value: 150),
                JobTypeData(name: "Yearbook Groups", value: 120),
                JobTypeData(name: "Sports Photos", value: 100),
                JobTypeData(name: "Graduation", value: 80),
                JobTypeData(name: "Banner Photos", value: 70),
                JobTypeData(name: "School Board Photos", value: 50),
                JobTypeData(name: "Other", value: 100)
            ]
            
            // 4. Mock Photographer Data - Jobs and miles by photographer
            let mockPhotographerData = [
                PhotographerData(name: "John", jobs: 175, miles: 5240, avgJobTime: 3.2),
                PhotographerData(name: "Sarah", jobs: 160, miles: 4800, avgJobTime: 3.5),
                PhotographerData(name: "Mike", jobs: 140, miles: 4200, avgJobTime: 3.0),
                PhotographerData(name: "Lisa", jobs: 130, miles: 3900, avgJobTime: 3.3),
                PhotographerData(name: "David", jobs: 120, miles: 3600, avgJobTime: 3.1)
            ]
            
            // 5. Mock Weather Impact Data - How weather affects jobs
            let mockWeatherImpactData = [
                WeatherImpactData(weather: "Clear", jobs: 320, onTimeArrival: 95),
                WeatherImpactData(weather: "Cloudy", jobs: 280, onTimeArrival: 92),
                WeatherImpactData(weather: "Rain", jobs: 180, onTimeArrival: 85),
                WeatherImpactData(weather: "Snow", jobs: 90, onTimeArrival: 70),
                WeatherImpactData(weather: "Fog", jobs: 60, onTimeArrival: 80)
            ]
            
            // 6. Monthly Revenue Data (from jobs and mileage reimbursement)
            let mockMonthlyRevenue = [
                MonthlyRevenueData(month: "Jan", revenue: 32000, mileageReimbursement: 1150 * 0.3),
                MonthlyRevenueData(month: "Feb", revenue: 34000, mileageReimbursement: 1130 * 0.3),
                MonthlyRevenueData(month: "Mar", revenue: 28000, mileageReimbursement: 1080 * 0.3),
                MonthlyRevenueData(month: "Apr", revenue: 30000, mileageReimbursement: 1200 * 0.3),
                MonthlyRevenueData(month: "May", revenue: 35000, mileageReimbursement: 1260 * 0.3),
                MonthlyRevenueData(month: "Jun", revenue: 32000, mileageReimbursement: 1210 * 0.3),
                MonthlyRevenueData(month: "Jul", revenue: 24000, mileageReimbursement: 1060 * 0.3),
                MonthlyRevenueData(month: "Aug", revenue: 26000, mileageReimbursement: 1260 * 0.3),
                MonthlyRevenueData(month: "Sep", revenue: 38000, mileageReimbursement: 1340 * 0.3),
                MonthlyRevenueData(month: "Oct", revenue: 36000, mileageReimbursement: 1240 * 0.3),
                MonthlyRevenueData(month: "Nov", revenue: 32000, mileageReimbursement: 1170 * 0.3),
                MonthlyRevenueData(month: "Dec", revenue: 30000, mileageReimbursement: 1100 * 0.3)
            ]
            
            // Apply time range filtering
            var filteredMileageData = mockMileageData
            var filteredMonthlyRevenue = mockMonthlyRevenue
            
            switch timeRange {
            case .month:
                filteredMileageData = Array(mockMileageData.prefix(1))
                filteredMonthlyRevenue = Array(mockMonthlyRevenue.prefix(1))
            case .quarter:
                filteredMileageData = Array(mockMileageData.prefix(3))
                filteredMonthlyRevenue = Array(mockMonthlyRevenue.prefix(3))
            case .year:
                // Use all data
                break
            }
            
            // Update published properties
            DispatchQueue.main.async {
                self.mileageData = filteredMileageData
                self.locationData = mockLocationData
                self.jobTypeData = mockJobTypeData
                self.photographerData = mockPhotographerData
                self.weatherImpactData = mockWeatherImpactData
                self.monthlyRevenue = filteredMonthlyRevenue
            }
            
        } catch {
            self.errorMessage = "Failed to load statistics: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Real Data Implementation
    
    // In a real implementation, this would fetch from Firestore
    func loadRealData(timeRange: TimeRange) {
        let db = Firestore.firestore()
        
        // Example: Fetch mileage data from daily job reports
        fetchMileageData(db: db, timeRange: timeRange)
        
        // Example: Fetch location data
        fetchLocationData(db: db)
        
        // And so on for other data points...
    }
    
    private func fetchMileageData(db: Firestore, timeRange: TimeRange) {
        // Get date range based on time range
        let (startDate, endDate) = getDateRange(for: timeRange)
        
        db.collection("dailyJobReports")
            .whereField("date", isGreaterThanOrEqualTo: startDate)
            .whereField("date", isLessThanOrEqualTo: endDate)
            .getDocuments { snapshot, error in
                if let error = error {
                    self.errorMessage = "Error fetching mileage data: \(error.localizedDescription)"
                    return
                }
                
                guard let docs = snapshot?.documents else { return }
                
                // Process the documents to extract mileage data
                // This would need to be adapted to match your actual data structure
                // ...
            }
    }
    
    private func fetchLocationData(db: Firestore) {
        db.collection("dailyJobReports")
            .getDocuments { snapshot, error in
                if let error = error {
                    self.errorMessage = "Error fetching location data: \(error.localizedDescription)"
                    return
                }
                
                guard let docs = snapshot?.documents else { return }
                
                // Process the documents to extract location data
                // ...
            }
    }
    
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