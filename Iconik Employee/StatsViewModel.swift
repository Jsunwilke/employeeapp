//  StatsViewModel.swift
//  Iconik Employee — the Statistics data layer, repaired in AMB.9
//
//  THE SCREEN HAD NEVER RENDERED. Opened on a signed-in simulator 2026-07-29 it
//  read "Error Loading Data — column daily_job_reports.start_time does not
//  exist", with no content on any tab. Two of its five queries named four columns
//  that do not exist in the shared database (`daily_job_reports.start_time` and
//  `.end_time`, `schools.value` and `.type` — all four proved absent by live
//  query), and one failing query replaced the entire screen. So this file is a
//  rewrite, not a restyle, under the operator's 2026-07-29 approval covering the
//  design AND the query repair.
//
//  WHAT CHANGED, AND WHY EACH CHANGE IS A CORRECTNESS FIX RATHER THAN A TASTE ONE
//
//    · ONE fetch of `daily_job_reports` per load, selecting all eight columns
//      the screen needs, instead of FOUR full reads of the same table for the
//      same window. Four reads is four chances to fail and four inconsistent
//      snapshots of a table another photographer is writing to.
//
//    · AN EXPLICIT `.limit(...)`. No query on the old screen carried one, so
//      PostgREST's default cap silently truncated the read — a statistics screen
//      quietly reporting a fraction of the org's miles. The table holds ~2,500
//      rows org-wide today.
//
//    · NO `schools` QUERY AT ALL. "Schools visited" now derives from the
//      destinations the reports actually carry, so it counts places that were
//      visited rather than every school on the org's list (the old figure
//      included never-visited schools, and its query named absent columns).
//
//    · THE DATE COLUMN IS DECODED AS A STRING and reduced to a day. The Supabase
//      decoder only parses whole ISO8601 timestamps, so a bare "2026-07-15"
//      throws and empties the whole fetch — the same trap `DailyJobReport` and
//      `JobBox` both already work around. `StatsDay` does it in one place.
//
//    · ALL ARITHMETIC LEFT. Every number is computed by `Stats/StatsRules.swift`,
//      which `scripts/test_stats_rules.sh` compiles and runs. This file fetches
//      and decodes; it does not add anything up.
//
//  DELETED WITH THE REWRITE, not left beside it: the fabricated weather table
//  (five literal rows, 930 invented jobs), `MonthlyRevenueData`/`monthlyRevenue`
//  (dead), `MileageData` and its `john`/`sarah`/`mike` fields and name subscript,
//  the average-job-time computation (no column exists to compute it from), and
//  the doubled mileage accumulator.

import Foundation
import Supabase
import SwiftUI

@MainActor
final class StatsViewModel: ObservableObject {

    /// Loading, loaded or failed — one state, so a failure cannot be rendered as
    /// an empty period and an empty period cannot be rendered as a failure. Both
    /// happened on the old screen, in opposite directions.
    enum LoadState {
        case loading
        case loaded(StatsAggregate)
        case failed(String)
    }

    @Published private(set) var state: LoadState = .loading

    /// The ceiling on one read of `daily_job_reports`. Above this the numbers
    /// would be quietly wrong, so it is far above the live row count rather than
    /// a page size: ~2,500 rows org-wide today.
    static let reportRowLimit = 5000

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private var loadTask: Task<Void, Never>?

    // MARK: - Load

    func load(period: StatsPeriod, reference: Date) {
        // The old screen refetched all five queries on every appearance with no
        // guard and let them race to write one error message. One task, cancelled
        // when it is superseded.
        loadTask?.cancel()
        state = .loading

        let organizationID = storedUserOrganizationID
        let window = period.window(reference: reference)

        guard !organizationID.isEmpty else {
            state = .failed("Your account isn't linked to an organization yet, so there's nothing to add up.")
            return
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let reports = try await self.fetchReports(organizationID: organizationID, window: window)
                let people = try await self.fetchPeople(organizationID: organizationID)
                let companyCarRate = try await self.fetchCompanyCarRate(organizationID: organizationID)
                if Task.isCancelled { return }
                let aggregate = StatsAggregator.aggregate(reports: reports,
                                                          people: people,
                                                          companyCarRate: companyCarRate,
                                                          period: period,
                                                          reference: reference)
                self.state = .loaded(aggregate)
            } catch {
                if Task.isCancelled { return }
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - The one report fetch

    /// The seven columns that EXIST on `daily_job_reports` and are needed here,
    /// read once for the whole screen. `date` comes back as text and is reduced
    /// to a day; see `StatsDay`.
    private struct ReportRow: Decodable {
        let user_id: String?
        let your_name: String?
        let date: String?
        let total_mileage: Double?
        let vehicle_type: String?
        let school_or_destination: String?
        let job_descriptions: [String]?

        /// Written out rather than synthesized: a type with a hand-written
        /// `init(from:)` does not get a generated `CodingKeys`.
        enum CodingKeys: String, CodingKey {
            case user_id, your_name, date, total_mileage, vehicle_type
            case school_or_destination, job_descriptions
        }

        /// EVERY FIELD IS TOLERANT. A strict field throws on the first row that
        /// disagrees with it and a thrown decode empties the ENTIRE fetch — which
        /// on this screen presents as "no reports in July", the empty-state class
        /// this project keeps paying for (JobBox: 316 of 1,055 live rows carry a
        /// NULL the strict version would have died on).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            user_id = (try? c.decodeIfPresent(String.self, forKey: .user_id)) ?? nil
            your_name = (try? c.decodeIfPresent(String.self, forKey: .your_name)) ?? nil
            date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? nil
            total_mileage = (try? c.decodeIfPresent(Double.self, forKey: .total_mileage)) ?? nil
            vehicle_type = (try? c.decodeIfPresent(String.self, forKey: .vehicle_type)) ?? nil
            school_or_destination = (try? c.decodeIfPresent(String.self, forKey: .school_or_destination)) ?? nil
            job_descriptions = (try? c.decodeIfPresent([String].self, forKey: .job_descriptions)) ?? nil
        }
    }

    private func fetchReports(organizationID: String, window: StatsWindow) async throws -> [StatsReport] {
        let rows: [ReportRow] = try await supabase
            .from("daily_job_reports")
            .select("user_id, your_name, date, total_mileage, vehicle_type, school_or_destination, job_descriptions")
            .eq("organization_id", value: organizationID)
            // Day strings, not instants: the column is a day and the filter says
            // so. `lt` on the first day of the following month includes the last
            // day of the period whatever time of day its timestamp carries.
            .gte("date", value: window.queryFirstDayString)
            .lt("date", value: window.queryEndExclusiveString)
            .limit(Self.reportRowLimit)
            .execute()
            .value

        return rows.map { row in
            StatsReport(userId: row.user_id,
                        yourName: row.your_name,
                        day: StatsDay(stored: row.date),
                        miles: row.total_mileage ?? 0,
                        vehicleType: row.vehicle_type,
                        destination: row.school_or_destination,
                        jobDescriptions: row.job_descriptions ?? [])
        }
    }

    // MARK: - Rates and names

    /// id, first_name, amount_per_mile — exactly what `ManagerMileageView`
    /// selects, because this screen's reimbursement figure now uses the same rule
    /// and must therefore use the same inputs.
    private struct UserRow: Decodable {
        let id: String
        let first_name: String?
        let amount_per_mile: Double?
    }

    private func fetchPeople(organizationID: String) async throws -> [StatsPersonRecord] {
        let rows: [UserRow] = try await supabase
            .from("users")
            .select("id, first_name, amount_per_mile")
            .eq("organization_id", value: organizationID)
            .execute()
            .value
        return rows.map { StatsPersonRecord(id: $0.id, firstName: $0.first_name, amountPerMile: $0.amount_per_mile) }
    }

    private struct OrgRateRow: Decodable { let company_car_rate: Double? }

    /// The raw org rate, NULL tolerated — `VehicleRates` resolves it. NOT
    /// `try?`-swallowed: a failed read here would silently value every company
    /// mile at the 10¢ fallback, which is the shape the manager screen ships and
    /// this one is not repeating.
    private func fetchCompanyCarRate(organizationID: String) async throws -> Double? {
        let rows: [OrgRateRow] = try await supabase
            .from("organizations")
            .select("company_car_rate")
            .eq("id", value: organizationID)
            .limit(1)
            .execute()
            .value
        return rows.first?.company_car_rate
    }
}
