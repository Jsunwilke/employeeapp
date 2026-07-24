//
//  ManagerEmployeeDetailView.swift
//  Iconik_EmployeeApp
//
//  Shows the employee's name in a large font within the content area,
//  leaving the navigation bar title empty. The system back button remains
//  in the nav bar, but no text is shown in the nav bar itself.
//

import SwiftUI

struct ManagerDailyRecord: Identifiable {
    let id: String
    let date: Date
    let schoolName: String
    let totalMileage: Double
    let vehicleType: String
    let photoURLs: [String]

    /// Create from DailyJobReport
    init(from report: DailyJobReport) {
        self.id = report.id
        self.date = report.date
        self.schoolName = report.school_or_destination ?? "Unknown"
        self.totalMileage = report.total_mileage
        self.vehicleType = report.vehicle_type ?? "personal"
        self.photoURLs = report.photo_urls ?? []
    }

    /// Direct initializer
    init(id: String, date: Date, schoolName: String, totalMileage: Double, vehicleType: String = "personal", photoURLs: [String]) {
        self.id = id
        self.date = date
        self.schoolName = schoolName
        self.totalMileage = totalMileage
        self.vehicleType = vehicleType
        self.photoURLs = photoURLs
    }
}

class ManagerEmployeeDetailViewModel: ObservableObject {
    @Published var records: [ManagerDailyRecord] = []
    @Published var totalPeriodMileage: Double = 0.0
    @Published var personalPeriodMileage: Double = 0.0
    @Published var companyPeriodMileage: Double = 0.0
    @Published var errorMessage: String? = nil

    let employeeName: String
    let periodStart: Date
    let periodEnd: Date
    let organizationID: String

    private let calendar = Calendar.current

    init(employeeName: String, periodStart: Date, organizationID: String) {
        self.employeeName = employeeName
        self.periodStart  = periodStart
        self.organizationID = organizationID
        // A 14-day window
        self.periodEnd    = calendar.date(byAdding: .day, value: 13, to: periodStart) ?? periodStart
    }

    func loadRecords() {
        guard !organizationID.isEmpty else {
            self.errorMessage = "User organization not found"
            return
        }

        Task {
            do {
                let reports = try await DailyJobReportService.shared.getReports(
                    yourName: self.employeeName,
                    organizationID: self.organizationID,
                    startDate: self.periodStart,
                    endDate: self.periodEnd
                )

                await MainActor.run {
                    // Convert to ManagerDailyRecord and calculate totals
                    var tempRecords = reports.map { ManagerDailyRecord(from: $0) }
                    let totalMiles = tempRecords.reduce(0.0) { $0 + $1.totalMileage }
                    let companyMiles = tempRecords
                        .filter { VehicleRates.isCompany($0.vehicleType) }
                        .reduce(0.0) { $0 + $1.totalMileage }

                    // Sort descending by date
                    tempRecords.sort { $0.date > $1.date }

                    self.records = tempRecords
                    self.totalPeriodMileage = totalMiles
                    self.companyPeriodMileage = companyMiles
                    self.personalPeriodMileage = totalMiles - companyMiles
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error loading records: \(error.localizedDescription)"
                }
            }
        }
    }
    
    var periodRangeText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return "\(f.string(from: periodStart)) - \(f.string(from: periodEnd))"
    }
}

struct ManagerEmployeeDetailView: View {
    @StateObject private var viewModel: ManagerEmployeeDetailViewModel

    init(employeeName: String, periodStart: Date) {
        // Get organization ID from UserDefaults (same as @AppStorage)
        let organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        let vm = ManagerEmployeeDetailViewModel(
            employeeName: employeeName,
            periodStart: periodStart,
            organizationID: organizationID
        )
        _viewModel = StateObject(wrappedValue: vm)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 1) Big name text at the top
            Text(viewModel.employeeName)
                .font(.system(size: 40, weight: .bold))
                .padding(.top, 16)
                .padding(.horizontal)
            
            // 2) Period date range
            Text("Period: \(viewModel.periodRangeText)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 4)
                .padding(.horizontal)
            
            // 3) Total miles in this period
            HStack {
                Text("Total Miles This Period:")
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.1f", viewModel.totalPeriodMileage))
                    .font(.headline)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Personal/company split — only shown once company miles exist.
            if viewModel.companyPeriodMileage > 0 {
                HStack {
                    Text(String(format: "Personal %.1f · Company %.1f mi", viewModel.personalPeriodMileage, viewModel.companyPeriodMileage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            // 4) List of daily records
            List(viewModel.records) { record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dateFormatter.string(from: record.date))
                                .font(.headline)
                            Text(record.schoolName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                Text(String(format: "%.1f miles", record.totalMileage))
                                    .font(.footnote)
                                if VehicleRates.isCompany(record.vehicleType) {
                                    Text("Company")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if !record.photoURLs.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.fill")
                                    .font(.caption)
                                Text("\(record.photoURLs.count)")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    
                    // Show photo thumbnails if available
                    if !record.photoURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(record.photoURLs.prefix(5), id: \.self) { photoURL in
                                    StorageImageThumbnail(imageURL: photoURL, size: 60)
                                }
                                if record.photoURLs.count > 5 {
                                    ZStack {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 60, height: 60)
                                            .cornerRadius(8)
                                        Text("+\(record.photoURLs.count - 5)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        // 5) Remove any text from the nav bar title
        .navigationBarTitle("", displayMode: .inline)
        // Let the system show the single back button (arrow + default text)
        .navigationBarBackButtonHidden(false)
        // If you want only the arrow, you can do the custom approach:
        // .navigationBarBackButtonHidden(true)
        // .toolbar { ... custom arrow ... }
        .alert(item: Binding(
            get: { viewModel.errorMessage.map { ManagerDetailError(message: $0) } },
            set: { _ in viewModel.errorMessage = nil }
        )) { err in
            Alert(title: Text("Error"), message: Text(err.message), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            viewModel.loadRecords()
        }
    }
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }
}

fileprivate struct ManagerDetailError: Identifiable {
    let id = UUID()
    let message: String
}

