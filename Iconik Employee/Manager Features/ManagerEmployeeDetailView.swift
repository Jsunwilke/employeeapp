//  ManagerEmployeeDetailView.swift
//  Iconik Employee — one photographer's period, converted to Ambient in AMB.12
//
//  THE DESIGN was `ManagerLabEmployeeDetail` in
//  `DesignLab/Mockups/ManagerMockup.swift`, approved at the batch-4 sitting
//  (2026-07-30). The shared pieces live in `Manager Features/ManagerKit.swift`.
//
//  WHAT THE CONVERSION CHANGED, and why each is in scope:
//    · THE SCREEN HAS CONTROLS. It had ZERO: the thumbnails, the "+N" overflow tile
//      and the photo-count chip were all inert, so any photo past the FIFTH was
//      unreachable and the only interactive thing on screen was the system Back
//      button. The count is now a tap that opens the day's report, which is where
//      those photos already live — and the report screen shows all of them.
//    · LOADING, EMPTY AND FAILURE ARE THREE THINGS. A blank list under a 0.0 total
//      was all three at once, on a screen a manager uses to check what someone is
//      owed. A failure was an alert titled "Error" over that same zero, which
//      stayed on screen behind it.
//    · THE WINDOW IS LABELLED. It always was a fixed 14 days; now it says so, and
//      says which fourteen. See `ManagerPeriodText` for why that matters on a
//      manager screen.
//
//  UNCHANGED ON PURPOSE: the fixed 14-day window, the date-descending order, the
//  personal/company split shown only once company miles exist, the "Unknown" /
//  "personal" fallbacks, and the deliberately empty nav bar with the name as large
//  text in the CONTENT.
//
//  CLEARANCE: this screen is PUSHED, and it applied no clearance at all — a pushed
//  screen does not inherit the container's inset, so its last row sat under the
//  floating tab bar. It insets itself now, the way every other pushed screen does.

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
    /// Loading, loaded and failed as three separate things — see `ManagerLoadState`.
    /// The old screen had one: whatever the fetch did, the list rendered.
    @Published var state: ManagerLoadState = .loading

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
            self.state = .failed("User organization not found")
            return
        }

        state = .loading

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
                    self.state = .loaded
                }
            } catch {
                await MainActor.run {
                    self.state = .failed("Error loading records: \(error.localizedDescription)")
                }
            }
        }
    }

    /// "Last 14 days · Jul 20, 2026 – Aug 2, 2026" — the window said out loud
    /// rather than implied.
    var periodRangeText: String {
        ManagerPeriodText.fixedWindow(periodStart, periodEnd)
    }

    /// The exact totals, which the rounded stat tiles cannot carry. The split half
    /// is appended only once company miles exist, which is how this screen has
    /// always read.
    var totalsLine: String {
        let total = "\(MileageFigures.oneDecimal(totalPeriodMileage)) miles filed"
        guard companyPeriodMileage > 0 else { return total }
        return total
            + " · Personal \(MileageFigures.oneDecimal(personalPeriodMileage))"
            + " · Company \(MileageFigures.oneDecimal(companyPeriodMileage)) mi"
    }
}

struct ManagerEmployeeDetailView: View {
    @StateObject private var viewModel: ManagerEmployeeDetailViewModel

    /// One enum, one `.ambientPush` — the AMB.3 rule. There is one destination
    /// today and it still goes through the enum, because the second one is what
    /// turns two `NavigationLink`s into a broken back stack.
    @State private var destination: ManagerEmployeeDestination?

    private var tint: Color { ManagerStyle.mileageTint }

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
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        // Remove any text from the nav bar title — the name is large text in the
        // CONTENT, and the system back button stays.
        .navigationBarTitle("", displayMode: .inline)
        .navigationBarBackButtonHidden(false)
        // A pushed screen does not inherit the container's inset; without this the
        // last row sits under the floating tab bar.
        .tabBarClearance()
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .report(let reportID):
                // THE DAY'S REPORT, READ-ONLY, which is where these photos already
                // live — all of them, not the first five.
                //
                // IT MUST BE THIS SCREEN AND NOT `ReportEditorView`. The first cut
                // of this conversion routed here to the editor, because that is
                // the screen a photographer opens for their OWN report and it does
                // show the photos. But this screen belongs to a MANAGER looking at
                // SOMEBODY ELSE'S filed report, and it had zero controls before
                // this phase — the approved drawing turns a dead photo count into
                // a way to SEE the photos, not into edit and delete rights over
                // another person's payroll-adjacent record. A restyle that hands
                // out a destructive action nobody asked for is not a restyle.
                //
                // `DailyReportDetailView` is read-only by construction (no edit, no
                // delete, no share, no toolbar) and renders every attached photo.
                DailyReportDetailView(docID: reportID)
            }
        }
        .onAppear {
            viewModel.loadRecords()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AmbientAvatar(name: viewModel.employeeName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.employeeName)
                        .font(.system(size: 20, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(viewModel.periodRangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                AmbientStatTile(value: Int(viewModel.totalPeriodMileage.rounded()),
                                label: "miles this period",
                                systemImage: "car.fill",
                                tint: tint)
                AmbientStatTile(value: Int(viewModel.companyPeriodMileage.rounded()),
                                label: "company miles",
                                systemImage: "building.2.fill",
                                tint: .orange)
                AmbientStatTile(value: viewModel.records.count,
                                label: "days filed",
                                systemImage: "calendar",
                                tint: .secondary)
            }

            // The tiles round; payroll does not. The exact figures stay on screen.
            Text(viewModel.totalsLine)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy, fillWidth: true)
        // A HEADER OF ZEROES IS A CLAIM. While the fetch is running or after it
        // failed, nothing has been counted — the numbers are placeholders, not
        // totals, and they are drawn as such.
        .redacted(reason: viewModel.state == .loaded ? [] : .placeholder)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            AmbientLoadingRow(message: "Loading mileage…")

        case .failed(let message):
            AmbientFailureCard(message: message) { viewModel.loadRecords() }

        case .loaded:
            if viewModel.records.isEmpty {
                AmbientEmptyState(
                    title: "No mileage in this period",
                    message: "Nothing was filed in the last 14 days.",
                    systemImage: "car")
            } else {
                rows
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Days", trailing: "newest first")
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(viewModel.records) { record in
                    ManagerMileageDayRow(
                        date: record.date,
                        school: record.schoolName,
                        miles: record.totalMileage,
                        isCompany: VehicleRates.isCompany(record.vehicleType),
                        photoCount: record.photoURLs.count,
                        tint: tint,
                        openReport: record.photoURLs.isEmpty
                            ? nil
                            : { destination = .report(record.id) })
                }
            }
        }
    }
}

/// The one place this screen goes.
enum ManagerEmployeeDestination: Identifiable {
    case report(String)

    var id: String {
        switch self {
        case .report(let reportID): return reportID
        }
    }
}
