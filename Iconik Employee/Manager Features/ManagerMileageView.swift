//  ManagerMileageView.swift
//  Iconik Employee — the manager's mileage list, converted to Ambient in AMB.12
//
//  DEFERRED HERE FROM AMB.9 by operator ruling, and the batch-4 mockup says in its
//  own header that it deliberately does NOT redraw this screen. So this conversion
//  invents nothing: it is the SAME content AMB.9 already designed and the operator
//  already approved for the photographer-facing mileage screen, seen from the
//  manager's side. The period carousel is `MileageKit`'s `MileagePeriodChip`, the
//  chips step `MileagePeriod`s, and the per-employee row — the one thing the
//  employee screen has no equivalent for — is drawn with the shared primitives in
//  `Manager Features/ManagerKit.swift`.
//
//  WHAT THE CONVERSION CHANGED, and why each is in scope:
//    · MONEY IS SPELLED ONCE. This screen carried FOUR hand-rolled currency
//      spellings and two of them read wrong — a whole-dollar total came out as
//      "$12" and a four-figure total ran together as "$1234.50". Every dollar now
//      goes through `Formatters.currency`, which AMB.9 named as this phase's to
//      reconcile.
//    · THE WINDOW SAYS WHICH FORTNIGHT IT IS. The 14-day cycles here are counted
//      from a hardcoded 2/25/2024 anchor while the photographer's own mileage
//      screen reads the organization's configured pay periods, so the same
//      fortnight can be two different windows depending on who is looking. The
//      ARITHMETIC IS UNTOUCHED — making the two agree is a data-layer change and is
//      out of this phase (D12) — but the screen now states the window it is
//      actually showing instead of implying it agrees with anything.
//    · THE MONTH LINE IS LABELLED FROM THE SELECTED PERIOD. It took the month name
//      from `Date()` while the number came from the selection, so picking a June
//      period produced a row reading "Miles in July" over June's figures.
//    · REAL STATES. There was no loading state (`isLoadingOrgID` was written and
//      never read), no empty state, and a failure was an alert over a list that had
//      silently filtered itself to nothing. Loading, empty and failed are three
//      things now, and the empty state names the filter that hides people.
//    · THE PUSH GOES THROUGH `.ambientPush(item:)` (D3), not a `NavigationLink`
//      built inside a `List` row.
//
//  UNCHANGED ON PURPOSE: the six 14-day period cards and their arithmetic, the
//  per-employee `amount_per_mile` and the org company-car rate, the filter that
//  lists only photographers with mileage in the chosen period (now named on the
//  empty state rather than hidden), and the year-scoped query behind the month and
//  year figures.
//
//  This file does NOT contain a NavigationView. It is a SHELL-WRAPPED feature —
//  `MainEmployeeView.featureContainer` supplies the bar, the Home button and the
//  tab-bar clearance, so this root adds only its own `AmbientBackdrop` (D14).

import SwiftUI
import Supabase

/// Simple data model for an employee in the manager's organization.
struct EmployeeRecord: Identifiable {
    let id: String
    let firstName: String
    let amountPerMile: Double
}

/// Holds summary mileage stats for an employee (totals + company-vehicle portion).
struct ManagerMileageStats {
    let periodMiles: Double
    let monthMiles: Double
    let yearMiles: Double
    let periodCompanyMiles: Double
    let monthCompanyMiles: Double
    let yearCompanyMiles: Double
}

/// ViewModel for ManagerMileageView, loading employees and computing mileage stats.
class ManagerMileageViewModel: ObservableObject {
    // Published properties for UI
    @Published var employees: [EmployeeRecord] = []
    @Published var statsByUser: [String: ManagerMileageStats] = [:]
    @Published var companyCarRate: Double = VehicleRates.defaultCompanyCarRate

    /// Loading, loaded and failed as three separate things — see `ManagerLoadState`.
    /// This screen used to have one state and an alert.
    @Published var state: ManagerLoadState = .loading
    /// True while a chip tap's figures are on their way. The rows on screen still
    /// belong to the period you just left, so they are redacted rather than left
    /// standing under a range that already changed — the AMB.9 rule.
    @Published var isFetchingStats = false

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
            print("❌ Invalid reference date for pay periods - using fallback to 2 weeks ago")
            let fallbackEnd = Date()
            let fallbackStart = calendar.date(byAdding: .day, value: -14, to: fallbackEnd) ?? fallbackEnd
            self.currentPeriodStart = fallbackStart
            self.currentPeriodEnd = fallbackEnd
            return
        }

        // Make sure reference date is start of day
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)

        let today = Date()
        let daysSinceRef = calendar.dateComponents([.day], from: referenceStartOfDay, to: today).day ?? 0
        let periodsElapsed = daysSinceRef / periodLength

        guard let start = calendar.date(byAdding: .day, value: periodsElapsed * periodLength, to: referenceStartOfDay) else {
            print("❌ Could not compute 14-day start boundary - using fallback")
            let fallbackEnd = Date()
            let fallbackStart = calendar.date(byAdding: .day, value: -14, to: fallbackEnd) ?? fallbackEnd
            self.currentPeriodStart = fallbackStart
            self.currentPeriodEnd = fallbackEnd
            return
        }

        // Calculate end date and set it to end of day (23:59:59)
        guard let tempEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: start),
              let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
            print("❌ Could not compute 14-day end boundary - using fallback")
            self.currentPeriodStart = start
            self.currentPeriodEnd = calendar.date(byAdding: .day, value: 14, to: start) ?? Date()
            return
        }

        self.currentPeriodStart = start
        self.currentPeriodEnd = end
    }

    /// Loads employees from Supabase, then automatically loads stats for the current pay period.
    func loadEmployees(orgID: String) {
        self.organizationID = orgID
        self.state = .loading

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
                    .eq("organization_id", value: orgID)
                    .execute()
                    .value

                // Fetch the org company-car rate (NULL → 0.10).
                struct OrgRateRecord: Decodable { let company_car_rate: Double? }
                let orgRows: [OrgRateRecord] = (try? await supabase
                    .from("organizations")
                    .select("company_car_rate")
                    .eq("id", value: orgID)
                    .limit(1)
                    .execute()
                    .value) ?? []
                let resolvedCompanyRate = VehicleRates.resolveCompanyCarRate(orgRows.first?.company_car_rate)

                var list: [EmployeeRecord] = []
                for user in users {
                    list.append(EmployeeRecord(
                        id: user.id,
                        firstName: user.first_name ?? "Unknown",
                        amountPerMile: VehicleRates.resolvePersonalRate(user.amount_per_mile)
                    ))
                }

                list.sort { $0.firstName.lowercased() < $1.firstName.lowercased() }

                // Handed over as a `let`: capturing the mutable `list` in the
                // main-actor hop is a data race the compiler already warns about
                // and Swift 6 rejects outright.
                let sorted = list

                await MainActor.run {
                    self.employees = sorted
                    self.companyCarRate = resolvedCompanyRate
                    self.loadStatsForPeriod(selectedPeriodStart: self.currentPeriodStart)
                }
            } catch {
                await MainActor.run {
                    self.state = .failed("Error loading employees: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Loads period/month/year miles for each employee.
    func loadStatsForPeriod(selectedPeriodStart: Date) {
        let selectedYear  = calendar.component(.year,  from: selectedPeriodStart)
        let selectedMonth = calendar.component(.month, from: selectedPeriodStart)

        // Calculate period end (14 days from start, end of day)
        guard let tempPeriodEnd = calendar.date(byAdding: .day, value: 13, to: selectedPeriodStart),
              let periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempPeriodEnd) else {
            return
        }

        // Query the full year of the selected period for year/month totals
        var startOfYearComps = DateComponents()
        startOfYearComps.year  = selectedYear
        startOfYearComps.month = 1
        startOfYearComps.day   = 1

        var endOfYearComps = DateComponents()
        endOfYearComps.year  = selectedYear
        endOfYearComps.month = 12
        endOfYearComps.day   = 31
        endOfYearComps.hour  = 23
        endOfYearComps.minute = 59
        endOfYearComps.second = 59

        let queryStart = calendar.date(from: startOfYearComps) ?? selectedPeriodStart
        let queryEnd = calendar.date(from: endOfYearComps) ?? periodEnd

        // THE OLD FIGURES ARE KEPT UNTIL THE NEW ONES LAND, redacted while they are
        // on their way. Emptying the dictionary here left every row reading 0.0 mi
        // and $0.00 mid-fetch — real-looking figures for a period nobody had
        // counted yet.
        isFetchingStats = true

        // Fetch stats for all employees using Supabase
        Task {
            let supabase = SupabaseManager.shared.client

            struct ReportRecord: Decodable {
                let user_id: String?
                let total_mileage: Double?
                let date: Date?
                let vehicle_type: String?
            }

            do {
                // Fetch all reports for the organization within the available periods range
                let reports: [ReportRecord] = try await supabase
                    .from("daily_job_reports")
                    .select("user_id, total_mileage, date, vehicle_type")
                    .eq("organization_id", value: organizationID)
                    .gte("date", value: queryStart.ISO8601Format())
                    .lte("date", value: queryEnd.ISO8601Format())
                    .execute()
                    .value

                // Group reports by user_id
                var reportsByUserId: [String: [ReportRecord]] = [:]
                for report in reports {
                    guard let userId = report.user_id else { continue }
                    if reportsByUserId[userId] == nil {
                        reportsByUserId[userId] = []
                    }
                    reportsByUserId[userId]?.append(report)
                }

                // Calculate stats for each employee
                var newStats: [String: ManagerMileageStats] = [:]

                for emp in employees {
                    let empReports = reportsByUserId[emp.id] ?? []

                    var periodMiles = 0.0
                    var monthMiles  = 0.0
                    var yearMiles   = 0.0
                    var periodCompanyMiles = 0.0
                    var monthCompanyMiles  = 0.0
                    var yearCompanyMiles   = 0.0

                    for report in empReports {
                        let miles = report.total_mileage ?? 0.0
                        let isCompany = VehicleRates.isCompany(report.vehicle_type)
                        if let dateVal = report.date {
                            let docMonth = calendar.component(.month, from: dateVal)
                            let docYear  = calendar.component(.year,  from: dateVal)

                            // Year miles: same year as selected period
                            if docYear == selectedYear {
                                yearMiles += miles
                                if isCompany { yearCompanyMiles += miles }
                            }

                            // Month miles: same month AND year as selected period
                            if docMonth == selectedMonth && docYear == selectedYear {
                                monthMiles += miles
                                if isCompany { monthCompanyMiles += miles }
                            }

                            // Period miles: within the 14-day period
                            if dateVal >= selectedPeriodStart && dateVal <= periodEnd {
                                periodMiles += miles
                                if isCompany { periodCompanyMiles += miles }
                            }
                        }
                    }

                    newStats[emp.id] = ManagerMileageStats(
                        periodMiles: periodMiles,
                        monthMiles:  monthMiles,
                        yearMiles:   yearMiles,
                        periodCompanyMiles: periodCompanyMiles,
                        monthCompanyMiles:  monthCompanyMiles,
                        yearCompanyMiles:   yearCompanyMiles
                    )
                }

                // Same reason as `sorted` above: the hop takes an immutable copy.
                let stats = newStats

                await MainActor.run {
                    self.statsByUser = stats
                    self.isFetchingStats = false
                    self.state = .loaded
                }
            } catch {
                await MainActor.run {
                    self.isFetchingStats = false
                    // A FAILED STATS FETCH IS NOT AN EMPTY PERIOD. The list filters
                    // itself to employees with miles in the period, so swallowing
                    // this would draw "nobody drove" over a query that never
                    // answered.
                    self.state = .failed("Error fetching reports: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Returns up to 6 pay period starts (current + 5 previous), newest first.
    func availablePeriods() -> [MileagePeriod] {
        var results: [MileagePeriod] = []
        var current = currentPeriodStart
        for index in 0..<6 {
            let end = calendar.date(byAdding: .day, value: periodLength - 1, to: current) ?? current
            results.append(MileagePeriod(index: index, start: current, end: end))
            if let prev = calendar.date(byAdding: .day, value: -periodLength, to: current) {
                current = prev
            }
        }
        return results
    }
}

struct ManagerMileageView: View {
    @StateObject private var viewModel = ManagerMileageViewModel()

    // The organization ID - refreshed from the database on appear
    @State private var organizationID: String = ""

    // The selected pay period from the horizontal carousel
    @State private var selectedPeriodStart: Date = Date()

    /// One `@State` destination, one `.ambientPush` — the AMB.3 rule.
    @State private var pushedEmployee: ManagerMileageDestination?

    private var tint: Color { ManagerStyle.mileageTint }

    /// Only photographers with mileage in the chosen period. A hidden rule until
    /// now — the empty state names it.
    private var filtered: [EmployeeRecord] {
        viewModel.employees.filter {
            (viewModel.statsByUser[$0.id]?.periodMiles ?? 0) > 0
        }
    }

    private var selectedPeriodEnd: Date {
        Calendar.current.date(byAdding: .day, value: 13, to: selectedPeriodStart) ?? selectedPeriodStart
    }

    /// "July 2026" — from the SELECTED period, which is where the numbers come
    /// from. It used to come from `Date()`.
    private var monthLabel: String {
        Formatters.monthYear.string(from: selectedPeriodStart)
    }

    private var yearLabel: String {
        "\(Calendar.current.component(.year, from: selectedPeriodStart)) total"
    }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    periodCarousel
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .navigationTitle("Manager Mileage") // Rely on parent's NavView
        .navigationBarTitleDisplayMode(.inline)
        .ambientPush(item: $pushedEmployee) { employee in
            ManagerEmployeeDetailView(employeeName: employee.name,
                                      periodStart: employee.periodStart)
        }
        .onAppear {
            selectedPeriodStart = viewModel.currentPeriodStart
            // Force refresh organization ID from database to fix stale cache
            Task {
                if let refreshedOrgID = await UserManager.shared.forceRefreshOrganizationID() {
                    await MainActor.run {
                        organizationID = refreshedOrgID
                        viewModel.loadEmployees(orgID: refreshedOrgID)
                    }
                } else {
                    // Fallback to cached value if refresh fails
                    let cachedOrgID = UserManager.shared.getCachedOrganizationID()
                    await MainActor.run {
                        organizationID = cachedOrgID
                        viewModel.loadEmployees(orgID: cachedOrgID)
                    }
                }
            }
        }
    }

    // MARK: - The period

    private var periodCarousel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.availablePeriods()) { period in
                        MileagePeriodChip(
                            label: period.rangeLabel(monthDay: { Formatters.monthDay.string(from: $0) }),
                            isCurrent: period.isCurrent,
                            isSelected: Calendar.current.isDate(period.start,
                                                                inSameDayAs: selectedPeriodStart),
                            tint: tint) {
                                selectedPeriodStart = period.start
                                viewModel.loadStatsForPeriod(selectedPeriodStart: period.start)
                            }
                    }
                }
                .ambientScrollTargets()
            }
            .ambientCarousel(margin: 16)
            .padding(.horizontal, -16)

            // THE WINDOW, SAID OUT LOUD — the fortnight on screen, and the fact
            // that this screen counts its own fortnights.
            Text(ManagerPeriodText.range(selectedPeriodStart, selectedPeriodEnd))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(ManagerPeriodText.cycleCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            AmbientLoadingRow(message: "Loading photographers…")

        case .failed(let message):
            AmbientFailureCard(message: message) {
                viewModel.loadEmployees(orgID: organizationID)
            }

        case .loaded:
            if filtered.isEmpty {
                AmbientEmptyState(
                    title: "No mileage in this period",
                    message: "Only photographers who filed mileage inside the selected period are listed. Pick another period to look back.",
                    systemImage: "car")
            } else {
                employeeList
            }
        }
    }

    private var employeeList: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Photographers", trailing: "\(filtered.count)")
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(filtered) { emp in
                    row(for: emp)
                }
            }
            .redacted(reason: viewModel.isFetchingStats ? .placeholder : [])
        }
    }

    private func row(for emp: EmployeeRecord) -> some View {
        let stats = viewModel.statsByUser[emp.id]
        let pMiles = stats?.periodMiles ?? 0
        let mMiles = stats?.monthMiles  ?? 0
        let yMiles = stats?.yearMiles   ?? 0
        let pCompany = stats?.periodCompanyMiles ?? 0
        let mCompany = stats?.monthCompanyMiles  ?? 0
        let yCompany = stats?.yearCompanyMiles   ?? 0
        let rate = emp.amountPerMile
        let companyRate = viewModel.companyCarRate

        // Personal miles pay the employee's rate; company miles pay the org rate.
        let pPay = (pMiles - pCompany) * rate + pCompany * companyRate
        let mPay = (mMiles - mCompany) * rate + mCompany * companyRate
        let yPay = (yMiles - yCompany) * rate + yCompany * companyRate

        return ManagerEmployeeMileageRow(
            name: emp.firstName,
            rate: rate,
            periodMiles: pMiles,
            periodPay: pPay,
            periodCompanyMiles: pCompany,
            companyRate: companyRate,
            monthLabel: monthLabel,
            monthMiles: mMiles,
            monthPay: mPay,
            yearLabel: yearLabel,
            yearMiles: yMiles,
            yearPay: yPay,
            tint: tint) {
                pushedEmployee = ManagerMileageDestination(id: emp.id,
                                                           name: emp.firstName,
                                                           periodStart: selectedPeriodStart)
            }
    }
}

/// The one place this screen goes: one photographer's period.
struct ManagerMileageDestination: Identifiable {
    let id: String
    let name: String
    let periodStart: Date
}
