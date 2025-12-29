//
//  MyJobReportsView.swift
//

import SwiftUI

// Display model for job reports list
struct JobReport: Identifiable {
    let id: String
    let date: Date
    let school: String
    let totalMileage: Double
    let photoCount: Int
    let photoURLs: [String]

    /// Create a JobReport display model from a DailyJobReport
    init(from report: DailyJobReport) {
        self.id = report.id
        self.date = report.date
        self.school = report.school_or_destination ?? ""
        self.totalMileage = report.total_mileage
        self.photoURLs = report.photo_urls ?? []
        self.photoCount = self.photoURLs.count
    }

    /// Direct initializer for testing or other uses
    init(id: String, date: Date, school: String, totalMileage: Double, photoCount: Int, photoURLs: [String]) {
        self.id = id
        self.date = date
        self.school = school
        self.totalMileage = totalMileage
        self.photoCount = photoCount
        self.photoURLs = photoURLs
    }
}

struct MyJobReportsView: View {
    @State private var reports: [JobReport] = []
    @AppStorage("userFirstName") var storedUserFirstName: String = ""
    @State private var userId: String? = nil
    @State private var showDeleteAlert = false
    @State private var reportToDelete: JobReport?
    @State private var isDeleting = false
    @State private var isLoading = false
    @State private var errorMessage: String = ""

    var body: some View {
        ZStack {
            if isLoading {
                VStack {
                    ProgressView("Loading reports...")
                    Text("Please wait")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !errorMessage.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        errorMessage = ""
                        if let userId = userId {
                            loadReports(userId: userId)
                        } else if let currentUserId = UserManager.shared.getCurrentUserIDUnified() {
                            userId = currentUserId
                            loadReports(userId: currentUserId)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                List {
                    ForEach(reports) { report in
                        NavigationLink(destination: EditDailyJobReportView(report: report)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(report.date, style: .date)
                                        .font(.headline)
                                    Text(report.school)
                                        .font(.subheadline)
                                    HStack {
                                        Text("Mileage: \(report.totalMileage, specifier: "%.1f")")
                                            .font(.footnote)
                                        if report.photoCount > 0 {
                                            Spacer()
                                            HStack(spacing: 4) {
                                                Image(systemName: "photo.fill")
                                                    .font(.caption)
                                                Text("\(report.photoCount)")
                                                    .font(.caption)
                                            }
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(10)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: deleteReports)
                }
            }
        }
        .navigationTitle("My Daily Job Reports")
        .onAppear {
            // Get current user ID and load reports
            if let currentUserId = UserManager.shared.getCurrentUserIDUnified() {
                userId = currentUserId
                loadReports(userId: currentUserId)  // Pass directly to avoid state timing issue
            } else {
                errorMessage = "Unable to load reports: not signed in"
                print("No user ID available - user may not be signed in")
            }
        }
        .alert("Delete Report", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {
                reportToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let report = reportToDelete {
                    deleteReport(report)
                }
            }
        } message: {
            if let report = reportToDelete {
                Text("Are you sure you want to delete the report from \(report.date, style: .date)?")
            }
        }
        .disabled(isDeleting)
    }
    
    func loadReports(userId: String) {
        let organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""

        guard !organizationID.isEmpty else {
            errorMessage = "Unable to load reports: no organization ID"
            print("No organization ID available")
            return
        }

        isLoading = true
        errorMessage = ""

        Task {
            do {
                print("Querying reports by userId: \(userId), orgID: \(organizationID)")
                let dailyReports = try await DailyJobReportService.shared.getReports(
                    userId: userId,
                    organizationID: organizationID
                )

                await MainActor.run {
                    isLoading = false
                    // Convert DailyJobReport to JobReport display model
                    reports = dailyReports.map { JobReport(from: $0) }
                    print("Loaded \(reports.count) reports")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to load reports: \(error.localizedDescription)"
                    print("Error fetching reports: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // Handle swipe-to-delete
    func deleteReports(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        reportToDelete = reports[index]
        showDeleteAlert = true
    }
    
    // Delete a report from Supabase
    func deleteReport(_ report: JobReport) {
        isDeleting = true

        Task {
            do {
                try await DailyJobReportService.shared.deleteReport(reportId: report.id)

                await MainActor.run {
                    isDeleting = false
                    // Remove from local array
                    reports.removeAll { $0.id == report.id }
                    reportToDelete = nil
                    print("Report deleted successfully")
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    print("Error deleting report: \(error.localizedDescription)")
                }
            }
        }
    }
}

