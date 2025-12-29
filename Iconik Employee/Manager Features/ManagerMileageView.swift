//
//  ManagerMileageView.swift
//  Iconik_EmployeeApp
//
//  Production-level manager screen that loads all employees, calculates period/month/year miles,
//  and displays them in a List. Tapping an employee navigates to ManagerEmployeeDetailView.
//
//  This file does NOT contain a NavigationView. It relies on MainEmployeeView's single nav stack.
//

import SwiftUI
import Supabase

/// Simple data model for an employee in the manager's organization.
struct EmployeeRecord: Identifiable {
    let id: String
    let firstName: String
    let amountPerMile: Double
}

/// Holds summary mileage stats for an employee.
struct ManagerMileageStats {
    let periodMiles: Double
    let monthMiles: Double
    let yearMiles: Double
}

/// ViewModel for ManagerMileageView, loading employees and computing mileage stats.
class ManagerMileageViewModel: ObservableObject {
    // Published properties for UI
    @Published var employees: [EmployeeRecord] = []
    @Published var statsByUser: [String: ManagerMileageStats] = [:]
    
    // Optional: hold an error message for display in an alert
    @Published var errorMessage: String? = nil
    
    // Store organization ID
    private var organizationID: String = ""
    
    // 14-day pay period logic
    private let calendar = Calendar.current
    let currentPeriodStart: Date
    let currentPeriodEnd: Date
    private let periodLength = 14
    
    init() {
        // Example reference date for your 14-day cycle
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let referenceDate = dateFormatter.date(from: "2/25/2024") else {
            fatalError("Invalid reference date for pay periods.")
        }
        
        // Make sure reference date is start of day
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        
        let today = Date()
        let daysSinceRef = calendar.dateComponents([.day], from: referenceStartOfDay, to: today).day ?? 0
        let periodsElapsed = daysSinceRef / periodLength
        
        guard let start = calendar.date(byAdding: .day, value: periodsElapsed * periodLength, to: referenceStartOfDay) else {
            fatalError("Could not compute 14-day start boundary.")
        }
        
        // Calculate end date and set it to end of day (23:59:59)
        guard let tempEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: start),
              let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
            fatalError("Could not compute 14-day end boundary.")
        }
        
        self.currentPeriodStart = start
        self.currentPeriodEnd = end
        
        // Log the calculated period for debugging
        let debugFormatter = DateFormatter()
        debugFormatter.dateStyle = .medium
        debugFormatter.timeStyle = .medium
        print("Manager current period calculated as: \(debugFormatter.string(from: start)) to \(debugFormatter.string(from: end))")
    }
    
    /// Loads employees from Supabase, then automatically loads stats for the current pay period.
    func loadEmployees(orgID: String) {
        self.organizationID = orgID

        Task {
            do {
                let supabase = SupabaseManager.shared.client

                struct UserRecord: Decodable {
                    let id: String
                    let first_name: String?
                    let amount_per_mile: Double?
                }

                let users: [UserRecord] = try await supabase
                    .from("users")
                    .select("id, first_name, amount_per_mile")
                    .eq("organization_id", value: orgID.lowercased())
                    .execute()
                    .value

                var list: [EmployeeRecord] = []
                for user in users {
                    list.append(EmployeeRecord(
                        id: user.id,
                        firstName: user.first_name ?? "Unknown",
                        amountPerMile: user.amount_per_mile ?? 0.0
                    ))
                }

                list.sort { $0.firstName.lowercased() < $1.firstName.lowercased() }

                await MainActor.run {
                    self.employees = list
                    self.loadStatsForPeriod(selectedPeriodStart: self.currentPeriodStart)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error loading employees: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Loads period/month/year miles for each employee.
    func loadStatsForPeriod(selectedPeriodStart: Date) {
        let now = Date()
        let currentYear  = calendar.component(.year,  from: now)
        let currentMonth = calendar.component(.month, from: now)

        // We'll fetch from start to end of this year, then filter in memory.
        var startOfYearComps = DateComponents()
        startOfYearComps.year  = currentYear
        startOfYearComps.month = 1
        startOfYearComps.day   = 1

        var endOfYearComps = DateComponents()
        endOfYearComps.year  = currentYear
        endOfYearComps.month = 12
        endOfYearComps.day   = 31
        endOfYearComps.hour  = 23
        endOfYearComps.minute = 59
        endOfYearComps.second = 59

        let yearStart = calendar.date(from: startOfYearComps) ?? now
        let yearEnd   = calendar.date(from: endOfYearComps)   ?? now

        // Calculate period end with proper end-of-day timing
        guard let tempPeriodEnd = calendar.date(byAdding: .day, value: 13, to: selectedPeriodStart),
              let periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempPeriodEnd) else {
            print("Error calculating period end date")
            return
        }

        // Log the date range we're querying for debugging
        let debugFormatter = DateFormatter()
        debugFormatter.dateStyle = .medium
        debugFormatter.timeStyle = .medium
        print("Manager loading stats from \(debugFormatter.string(from: selectedPeriodStart)) to \(debugFormatter.string(from: periodEnd))")

        // Reset stats
        statsByUser = [:]

        // Fetch stats for all employees using Supabase
        Task {
            let supabase = SupabaseManager.shared.client

            struct ReportRecord: Decodable {
                let your_name: String?
                let total_mileage: Double?
                let date: Date?
            }

            do {
                // Fetch all reports for the organization within the year range
                let reports: [ReportRecord] = try await supabase
                    .from("daily_job_reports")
                    .select("your_name, total_mileage, date")
                    .eq("organization_id", value: organizationID.lowercased())
                    .gte("date", value: yearStart.ISO8601Format())
                    .lte("date", value: yearEnd.ISO8601Format())
                    .execute()
                    .value

                // Group reports by employee name
                var reportsByEmployee: [String: [ReportRecord]] = [:]
                for report in reports {
                    guard let name = report.your_name else { continue }
                    if reportsByEmployee[name] == nil {
                        reportsByEmployee[name] = []
                    }
                    reportsByEmployee[name]?.append(report)
                }

                // Calculate stats for each employee
                var newStats: [String: ManagerMileageStats] = [:]

                for emp in employees {
                    let empReports = reportsByEmployee[emp.firstName] ?? []

                    var periodMiles = 0.0
                    var monthMiles  = 0.0
                    var yearMiles   = 0.0

                    for report in empReports {
                        let miles = report.total_mileage ?? 0.0
                        if let dateVal = report.date {
                            yearMiles += miles

                            let docMonth = calendar.component(.month, from: dateVal)
                            let docYear  = calendar.component(.year,  from: dateVal)
                            if docMonth == currentMonth && docYear == currentYear {
                                monthMiles += miles
                            }

                            // Check if date falls within the selected period
                            if dateVal >= selectedPeriodStart && dateVal <= periodEnd {
                                periodMiles += miles
                            }
                        }
                    }

                    newStats[emp.id] = ManagerMileageStats(
                        periodMiles: periodMiles,
                        monthMiles:  monthMiles,
                        yearMiles:   yearMiles
                    )

                    // Log the calculation for this employee
                    print("Manager calculated mileage for \(emp.firstName): period=\(periodMiles), month=\(monthMiles), year=\(yearMiles)")
                }

                await MainActor.run {
                    self.statsByUser = newStats
                    print("Manager finished loading all employee stats")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error fetching reports: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Returns up to 6 pay period starts (current + 5 previous).
    func availablePeriods() -> [Date] {
        var results: [Date] = []
        var current = currentPeriodStart
        for _ in 0..<6 {
            results.append(current)
            if let prev = calendar.date(byAdding: .day, value: -periodLength, to: current) {
                current = prev
            }
        }
        return results
    }
}

struct ManagerMileageView: View {
    @StateObject private var viewModel = ManagerMileageViewModel()
    
    // Typically from AppStorage, if your org ID is stored there
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    
    // The selected pay period from the horizontal scroller
    @State private var selectedPeriodStart: Date = Date()
    
    // For date formatting
    private var cardFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }
    private var fullRangeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }
    
    var body: some View {
        VStack(spacing: 16) {
            
            // 1) Horizontal scroller for picking a pay period
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.availablePeriods(), id: \.self) { period in
                        Button {
                            selectedPeriodStart = period
                            viewModel.loadStatsForPeriod(selectedPeriodStart: period)
                        } label: {
                            VStack {
                                Text(cardFormatter.string(from: period))
                                    .font(.headline)
                                    .foregroundColor(
                                        selectedPeriodStart == period ? .white : .primary
                                    )
                                Text("to")
                                    .font(.caption)
                                    .foregroundColor(
                                        selectedPeriodStart == period ? .white : .secondary
                                    )
                                if let end = Calendar.current.date(byAdding: .day, value: 13, to: period) {
                                    Text(cardFormatter.string(from: end))
                                        .font(.headline)
                                        .foregroundColor(
                                            selectedPeriodStart == period ? .white : .primary
                                        )
                                }
                            }
                            .padding(8)
                            .background(
                                selectedPeriodStart == period
                                ? Color.blue
                                : Color.gray.opacity(0.2)
                            )
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // 2) Show the selected date range below
            if let periodEnd = Calendar.current.date(byAdding: .day, value: 13, to: selectedPeriodStart) {
                Text("\(fullRangeFormatter.string(from: selectedPeriodStart)) - \(fullRangeFormatter.string(from: periodEnd))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 3) Filter employees with >0 miles in the chosen period
            let filtered = viewModel.employees.filter {
                (viewModel.statsByUser[$0.id]?.periodMiles ?? 0) > 0
            }
            
            // 4) Display them in a List
            List(filtered) { emp in
                let stats = viewModel.statsByUser[emp.id]
                let pMiles = stats?.periodMiles ?? 0
                let mMiles = stats?.monthMiles  ?? 0
                let yMiles = stats?.yearMiles   ?? 0
                let rate   = emp.amountPerMile
                
                let pPay = pMiles * rate
                let mPay = mMiles * rate
                let yPay = yMiles * rate
                
                NavigationLink(destination: {
                    // Navigate to the detail view
                    ManagerEmployeeDetailView(
                        employeeName: emp.firstName,
                        periodStart: selectedPeriodStart
                    )
                    .navigationBarTitleDisplayMode(.large)
                }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(emp.firstName)
                                .font(.headline)
                            Spacer()
                            Text(String(format: "Rate: $%.2f", rate))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text(String(format: "This Period: %.1f mi", pMiles))
                            Spacer()
                            Text(String(format: "$%.2f", pPay))
                                .foregroundColor(.secondary)
                        }
                        .font(.footnote)
                        
                        let mName = DateFormatter().monthSymbols[
                            Calendar.current.component(.month, from: Date()) - 1
                        ]
                        HStack {
                            Text(String(format: "Miles in %@: %.1f", mName, mMiles))
                            Spacer()
                            Text(String(format: "$%.2f", mPay))
                                .foregroundColor(.secondary)
                        }
                        .font(.footnote)
                        
                        HStack {
                            Text(String(format: "Miles this Year: %.1f", yMiles))
                            Spacer()
                            Text(String(format: "$%.2f", yPay))
                                .foregroundColor(.secondary)
                        }
                        .font(.footnote)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Manager Mileage") // Rely on parent's NavView
        .alert(item: Binding(
            get: { viewModel.errorMessage.map { ManagerMileageError(message: $0) } },
            set: { _ in viewModel.errorMessage = nil }
        )) { err in
            Alert(title: Text("Error"), message: Text(err.message), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            selectedPeriodStart = viewModel.currentPeriodStart
            viewModel.loadEmployees(orgID: storedUserOrganizationID)
        }
    }
}

// A small wrapper for presenting the error as an Identifiable object
fileprivate struct ManagerMileageError: Identifiable {
    let id = UUID()
    let message: String
}
