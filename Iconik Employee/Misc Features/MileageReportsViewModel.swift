//  MileageReportsViewModel.swift
//  Iconik Employee — the Mileage Reports data layer, rebuilt in AMB.9
//
//  THE OLD VERSION IS GONE FROM THIS FILE, not left beside the new one. What it did
//  and why each piece changed:
//
//    · SELECTION IS AN INDEX, RESOLVED AFTER THE SERVICE ANSWERS. It used to be a
//      `Date` seeded in the VIEW's `init` from `currentPeriodStart`, which was
//      `Date()` until an async completion replaced it — so on first render the
//      selected date matched none of the six cards.
//    · THE CAROUSEL'S BOUNDARIES ARE THE ORG'S REAL ONES. The view stepped its
//      labels back by a hardcoded 14 days while the data came from
//      `PayPeriodService`. Now both come from the same resolver, walked backwards a
//      day at a time (`PayPeriodSequence`), so a weekly or monthly org gets its
//      own cycle and the caption says which.
//    · FAILURES ARE PUBLISHED. Both fetch paths swallowed their error to a `print`,
//      so a failed load rendered "0.0 miles / $0.00" — indistinguishable from a
//      genuinely empty period. `state` now carries the failure, and when figures
//      from a previous successful load exist they are shown behind a banner rather
//      than replaced with zeroes.
//    · ONE FETCH PER APPEARANCE. `.onAppear` called both loaders while
//      `loadRecordsInternal` already chained the second, and every carousel tap
//      re-fetched the rates. Rates load once; a tap loads only the period.
//    · `calculateMileage(forPeriodStart:periodEnd:)` IS DELETED — 19 lines, zero
//      callers.
//    · THE IDENTITY LOGGING IS DELETED. Twelve-plus emoji `print`s, several of them
//      printing a user id.
//
//  WHAT IS DELIBERATELY LEFT AS IT WAS, because changing it changes another screen:
//    · `updateCallback` IS STILL A SINGLE SLOT. A second subscriber silently
//      unsubscribes the first. The home dashboard's `MileageWidget` depends on this
//      exact mechanism (`DashboardWidgets.swift:851`), and turning it into a list of
//      observers is a change to a screen this phase does not own.
//    · THERE ARE STILL TWO INSTANCES. The widget uses `.shared`; the screen builds
//      its own. An edit refreshes the screen and the dashboard goes stale until it
//      reloads. Same reason: the fix belongs where the widget lives.
//    · COMPENSATION IS Σ(miles × TODAY's rate). No per-report rate is stored, so a
//      historical rate cannot be recovered — see MileageRules.swift's header.
//
//  All arithmetic is in MileageRules.swift, which is compiled and RUN by
//  scripts/test_mileage_rules.sh.

import Foundation
import SwiftUI

/// What the screen is showing right now.
///
/// FOUR STATES, and the distinction between the last two is the point: a failure
/// with nothing behind it is an error card, and a failure with figures behind it is
/// those figures plus a banner saying how old they are. Collapsing them is how a
/// stale number gets read as a current one.
enum MileageScreenState: Equatable {
    case loading
    case loaded
    /// Nothing to show. The error card and its Retry.
    case failed(String)
    /// Figures from a previous successful load, plus the banner.
    case stale(String)
}

class MileageReportsViewModel: ObservableObject {
    static let shared = MileageReportsViewModel()

    // MARK: - Published figures
    //
    // These names and meanings are UNCHANGED: `DashboardWidgets.MileageWidget`
    // reads every one of them off `.shared`.

    /// THE THREE HEADLINE TOTALS ARE DERIVED, NOT MIRRORED. They used to be stored
    /// `@Published`s written beside the split miles on every apply — two
    /// representations of one figure, which is how a bucket's miles and its money
    /// come to be read off different sources. They are computed over the splits now
    /// and keep their names, because `DashboardWidgets.MileageWidget` reads every one
    /// of them off `.shared`.
    var currentPeriodMileage: Double { currentPeriodSplit.totalMiles }
    var monthMileage: Double { monthSplit.totalMiles }
    var yearMileage: Double { yearSplit.totalMiles }

    /// Trips for the selected period, NEWEST FIRST — sorted once here, where they
    /// land, rather than by a computed `sortedRecords` the list re-sorted on every
    /// body evaluation.
    @Published var records: [MileageRecordWrapper] = []

    // Personal/company split miles per bucket (rate-independent; compensation is
    // folded in reactively via the resolved rates below).
    @Published var currentPeriodPersonalMiles: Double = 0
    @Published var currentPeriodCompanyMiles: Double = 0
    @Published var monthPersonalMiles: Double = 0
    @Published var monthCompanyMiles: Double = 0
    @Published var yearPersonalMiles: Double = 0
    @Published var yearCompanyMiles: Double = 0

    // Resolved rates: personal = this photographer's users.amount_per_mile (|| 0.67),
    // company = org organizations.company_car_rate (|| 0.10).
    @Published var personalRate: Double = VehicleRates.defaultMileageRate
    @Published var companyRate: Double = VehicleRates.defaultCompanyCarRate

    // MARK: - Published screen state

    /// The six chips, newest first. Empty until the pay-period service answers.
    @Published var periods: [PayPeriod] = []
    /// Which chip is selected, by index. 0 is the current period.
    @Published var selectedPeriodIndex: Int = 0
    /// Which cycle the org is on, for the caption under the carousel.
    @Published var cycle: PayPeriodCycle = .biweekly
    @Published var state: MileageScreenState = .loading
    /// True while a CHIP fetch is in flight. The header is derived from the
    /// selection, so between the tap and the answer the figures under it belong to
    /// the period you just left — the hero redacts them rather than letting them
    /// stand under the new header.
    @Published var isFetchingPeriod = false
    /// A chip fetch that failed. The figures on screen are current for the period
    /// the selection reverted to, so this is a transient line under them, NOT the
    /// stale banner — nothing here is older than it says.
    @Published var periodNotice: String?

    var userName: String = ""
    var userId: String?

    /// MINTED FRESH ON EVERY READ, never captured at init. `PayPeriodService`
    /// re-reads `TimeZone.current` on every call, so a calendar frozen at init
    /// starts disagreeing with it the moment the device changes zone — and the two
    /// then mint boundaries an hour apart, which the carousel's contiguity guard
    /// (`PayPeriodSequence.build`) reads as a gap and collapses the six chips to
    /// one. `.shared` outlives many appearances, so "at init" can be days ago.
    var calendar: Calendar { Calendar.current }

    private let payPeriodService = PayPeriodService.shared
    private var updateCallback: (() -> Void)?
    /// Rates are org/user configuration, not per-period data: fetched once per
    /// screen rather than on every carousel tap.
    private var ratesLoaded = false
    /// True once any load has succeeded, or once the cold-start cache produced a
    /// non-zero figure — which is what makes a later failure `.stale` rather than
    /// `.failed`.
    private var hasSyncedFigures = false
    /// True once `applyYearAndMonth` has actually run this session. Until then the
    /// month and year figures are the cache's or zero — NOT fetched — and neither
    /// the widget's cache nor a `.loaded` state may claim otherwise.
    ///
    /// PUBLISHED, because the two tiles are the ones making the claim: while this is
    /// false they draw an explicit unloaded presentation instead of a number. Relying
    /// on `periodNotice` to carry that caveat did not hold — it is a shared slot that
    /// the next chip tap clears, and the tiles were left reading $0.00 as a total.
    @Published private(set) var monthYearLoaded = false
    /// The one in-flight load. Cancelled by every new load or selection, so two
    /// fetches cannot land out of order and write one another's figures.
    private var loadTask: Task<Void, Never>?
    /// A full load already running. A double `.onAppear` must not fetch everything
    /// twice concurrently; `force` (Retry) still preempts.
    ///
    /// RAISED SYNCHRONOUSLY WHERE THE TASK IS CREATED, not in the task body: two
    /// `.onAppear`s in the same turn both read the flag before any body had run, so
    /// both passed the guard and both loads went out.
    private var isLoadingEverything = false
    /// Bumped where a full load starts. The clear is guarded by it — exactly like
    /// `endPeriodFetch` — so a superseded load finishing later cannot lower the flag
    /// while its replacement is still running.
    private var loadEverythingGeneration = 0
    /// Bumped by every period fetch. The apply is guarded by it, so a superseded
    /// fetch cannot write its figures or clear the in-flight flag under a newer one.
    private var periodFetchGeneration = 0

    /// The three headline totals, persisted on every successful load of the CURRENT
    /// period so a failure has something honest to fall back to. Same pattern and
    /// the same keys the home dashboard's mileage widget already uses
    /// (`DashboardWidgets.swift:717-719`) — one cache for one set of figures rather
    /// than a second store that can disagree with it.
    private enum Cache {
        static let periodMiles = "cached_currentPeriodMileage"
        static let monthMiles = "cached_monthMileage"
        static let yearMiles = "cached_yearMileage"
    }

    // MARK: - Derived

    /// Split (miles + compensation) for a bucket, through the ONE accumulator.
    /// Computed rather than stored so a rate that lands after the miles still
    /// revalues the money.
    private func split(personalMiles: Double, companyMiles: Double) -> VehicleRates.Split {
        MileageMath.split(personalMiles: personalMiles,
                          companyMiles: companyMiles,
                          personalRate: personalRate,
                          companyCarRate: companyRate)
    }

    var currentPeriodSplit: VehicleRates.Split { split(personalMiles: currentPeriodPersonalMiles, companyMiles: currentPeriodCompanyMiles) }
    var monthSplit: VehicleRates.Split { split(personalMiles: monthPersonalMiles, companyMiles: monthCompanyMiles) }
    var yearSplit: VehicleRates.Split { split(personalMiles: yearPersonalMiles, companyMiles: yearCompanyMiles) }

    var currentPeriodFigures: MileageFigures { MileageFigures(split: currentPeriodSplit) }
    var monthFigures: MileageFigures { MileageFigures(split: monthSplit) }
    var yearFigures: MileageFigures { MileageFigures(split: yearSplit) }

    /// The selected period, or nil while the pay-period service has not answered.
    var selectedPeriod: PayPeriod? {
        guard periods.indices.contains(selectedPeriodIndex) else { return periods.first }
        return periods[selectedPeriodIndex]
    }

    /// One trip's money, at the rate its own vehicle type pays.
    func amount(for record: MileageRecordWrapper) -> Double {
        MileageMath.amount(miles: record.totalMileage,
                           vehicleType: record.vehicleType,
                           personalRate: personalRate,
                           companyCarRate: companyRate)
    }

    // MARK: - Model

    /// Local wrapper model to hold report data.
    struct MileageRecordWrapper: Identifiable {
        let id: String
        let date: Date
        let totalMileage: Double
        let schoolName: String
        let vehicleType: String  // "personal" or "company"

        /// Create from DailyJobReport
        init(from report: DailyJobReport) {
            self.id = report.id
            self.date = report.date
            self.totalMileage = report.total_mileage
            self.schoolName = report.school_or_destination ?? ""
            self.vehicleType = report.vehicle_type ?? "personal"
        }

        /// Direct initializer
        init(id: String, date: Date, totalMileage: Double, schoolName: String, vehicleType: String = "personal") {
            self.id = id
            self.date = date
            self.totalMileage = totalMileage
            self.schoolName = schoolName
            self.vehicleType = vehicleType
        }

        var vehicle: MileageVehicle { MileageVehicle.from(storage: vehicleType) }
    }

    // MARK: - Init

    init(userName: String = "") {
        self.userName = userName.isEmpty ? (UserDefaults.standard.string(forKey: "userFirstName") ?? "") : userName
        self.userId = UserManager.shared.getCurrentUserIDUnified()

        // Seed the headline figures from the last successful load, so a cold start
        // that cannot reach the server shows the last real numbers behind a banner
        // instead of a screen full of zeroes.
        let cachedPeriod = UserDefaults.standard.double(forKey: Cache.periodMiles)
        let cachedMonth = UserDefaults.standard.double(forKey: Cache.monthMiles)
        let cachedYear = UserDefaults.standard.double(forKey: Cache.yearMiles)
        // The cache holds totals, not the split, so the personal bucket carries them
        // — the same estimate the dashboard widget makes at cold start. The three
        // headline totals are computed over these, so seeding the buckets seeds them.
        currentPeriodPersonalMiles = cachedPeriod
        monthPersonalMiles = cachedMonth
        yearPersonalMiles = cachedYear
        hasSyncedFigures = cachedPeriod != 0 || cachedMonth != 0 || cachedYear != 0

        // NO pay-period fetch here. The old init started one and the view read
        // `currentPeriodStart` synchronously in its own init to seed the selection,
        // which is exactly how the selection came to match none of the chips.
    }

    // MARK: - Subscription (unchanged mechanism — see the file header)

    func listenForMileageUpdates(completion: @escaping () -> Void) {
        self.updateCallback = completion
    }

    // MARK: - Loading

    /// The dashboard widget's entry point, unchanged in name and meaning: load the
    /// current period plus the month and year totals.
    func loadRecords() {
        load()
    }

    /// Load everything the screen needs. One call per appearance — and one at a
    /// time: `.onAppear` fires twice on some navigation paths and the old version
    /// would have run two full loads side by side.
    func load(force: Bool = false) {
        if isLoadingEverything && !force { return }
        let generation = beginLoadEverything()
        startLoadTask { await $0.loadEverything(force: force, generation: generation) }
    }

    /// The error card's Retry — and the stale banner's: re-read the settings, the
    /// rates and the figures.
    func retry() {
        let generation = beginLoadEverything()
        startLoadTask { model in
            // FROM `.stale`, THE FIGURES STAY. `.loading` is the skeleton state: it
            // drops the banner and replaces real last-synced figures with a
            // placeholder, so tapping the banner's own Retry destroyed the only
            // numbers on screen and left nothing if the retry also failed. The
            // in-flight signal is `isFetchingPeriod`, raised by the fetch itself and
            // lowered by it, so it cannot be left stuck on an early return.
            if case .stale = model.state {} else { model.state = .loading }
            model.periodNotice = nil
            await model.loadEverything(force: true, generation: generation)
        }
    }

    /// A carousel tap. Loads the selected period, and the rates or the year ONLY when
    /// those have never resolved (see `loadSelectedPeriod`) — every tap used to be a
    /// three-query round trip.
    func selectPeriod(index: Int) {
        guard periods.indices.contains(index), index != selectedPeriodIndex else { return }
        let previous = selectedPeriodIndex
        selectedPeriodIndex = index
        periodNotice = nil
        startLoadTask { await $0.loadSelectedPeriod(revertingTo: previous) }
    }

    /// ONE task, cancelled when it is superseded — the shape `StatsViewModel.load`
    /// already ships (`StatsViewModel.swift:79`). Without it two chip taps race and
    /// the slower answer wins, leaving one period's money under another's header
    /// permanently, because nothing re-fetches until the screen is reopened.
    private func startLoadTask(_ work: @escaping @MainActor (MileageReportsViewModel) async -> Void) {
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await work(self)
        }
    }

    @MainActor
    private func loadEverything(force: Bool, generation loadGeneration: Int) async {
        defer { endLoadEverything(loadGeneration) }

        // A CANCELLED TASK MUTATES NOTHING. Every await below is a point at which a
        // newer load may have superseded this one, and this body sets flags, rebuilds
        // the carousel and bumps the fetch generation — under the survivor, if it is
        // allowed to keep running.
        guard !Task.isCancelled else { return }

        if !hasSyncedFigures { state = .loading }

        guard let userId = resolvedUserId() else {
            fail("We couldn't tell who is signed in, so there is nothing to load. Sign out and back in to try again.")
            return
        }

        // A pay-period read that failed with nothing already built has already failed
        // the screen with the reason. Running on would replace that with "your
        // organization's pay periods aren't set up yet", which is a different claim
        // and the wrong one.
        guard await ensurePeriods(force: force) else { return }
        guard !Task.isCancelled else { return }

        if force || !ratesLoaded { await loadRates() }
        guard !Task.isCancelled else { return }

        guard let period = selectedPeriod else {
            fail("Your organization's pay periods aren't set up yet, so there is no period to total.")
            return
        }

        let generation = beginPeriodFetch()
        defer { endPeriodFetch(generation) }

        // TWO FETCHES, TWO FATES. They used to share one do/catch, so a failed year
        // query threw away a period result that had already arrived and failed the
        // whole screen — the hero went to an error card because two TILES could not
        // be totalled.
        let periodReports: [DailyJobReport]
        do {
            periodReports = try await DailyJobReportService.shared.getReports(
                userId: userId, startDate: period.start, endDate: period.end)
        } catch {
            guard isCurrent(generation) else { return }
            fail(MileageFailureCard.genericMessage, underlying: error)
            return
        }
        guard isCurrent(generation) else { return }

        applyPeriod(periodReports)
        periodNotice = nil
        succeed()

        do {
            let yearReports = try await DailyJobReportService.shared.getReports(
                userId: userId, startDate: yearStart, endDate: yearEnd)
            guard isCurrent(generation) else { return }
            // Sets `monthYearLoaded`; `succeed()` runs again so the month and year
            // cache keys — which are gated on that flag — are actually written.
            applyYearAndMonth(yearReports)
            succeed()
        } catch {
            guard isCurrent(generation) else { return }
            // `monthYearLoaded` stays false: the two tiles were never fetched, so
            // nothing downstream (the widget's cache included) may claim they were.
            // An inline line says so, the same slot a failed chip fetch uses.
            print("⚠️ Mileage: month/year totals unavailable — \(error.localizedDescription)")
            periodNotice = yearTotalsFailureNotice
            notifyLoadEnded()
        }
    }

    @MainActor
    private func loadSelectedPeriod(revertingTo previousIndex: Int? = nil) async {
        // Superseded before the body even started: bumping the fetch generation here
        // would make the survivor's own apply look stale and discard a good result.
        guard !Task.isCancelled else { return }
        guard let userId = resolvedUserId(), let period = selectedPeriod else { return }

        let generation = beginPeriodFetch()
        let requestedIndex = selectedPeriodIndex
        defer { endPeriodFetch(generation) }

        // A CHIP TAP CAN BE THE FIRST THING THAT EVER FETCHES. `selectPeriod` cancels
        // the in-flight full load, so a tap during the first appearance can cancel the
        // rates fetch — and nothing re-ran it until the NEXT appearance, so the whole
        // session drew its money at the 0.67/0.10 defaults. Guarded on `ratesLoaded`
        // exactly as `loadEverything` guards it, so a tap costs nothing once both
        // lookups have resolved.
        //
        // Inside the in-flight window on purpose: `beginPeriodFetch` has already
        // raised `isFetchingPeriod`, so the hero redacts for the rates round-trip too
        // rather than standing unredacted under a header that has already moved.
        if !ratesLoaded { await loadRates() }
        guard isCurrent(generation), requestedIndex == selectedPeriodIndex else { return }

        // TWO FETCHES, TWO FATES — the same split `loadEverything` carries. One
        // do/catch over both meant a failing YEAR query threw away a period result
        // that had already arrived: the selection reverted and the screen said
        // "Couldn't load that period" about a period that had loaded fine.
        let reports: [DailyJobReport]
        do {
            reports = try await DailyJobReportService.shared.getReports(
                userId: userId, startDate: period.start, endDate: period.end)
        } catch {
            guard isCurrent(generation), requestedIndex == selectedPeriodIndex else { return }
            // THE SELECTION GOES BACK. The figures on screen belong to the period
            // that DID load, and the header is derived from the selection — so
            // leaving the new chip selected after a failed fetch would put a header
            // over totals from a different fortnight. That is the exact defect this
            // conversion removed ("Current Period" over a past period's numbers) in
            // a new costume, so the honest move is to keep the header and the
            // figures describing the same period and say the fetch failed.
            if let previousIndex, periods.indices.contains(previousIndex) {
                selectedPeriodIndex = previousIndex
            }
            if case .loaded = state {
                // NOT `.stale`. That banner says "everything here is older than
                // now", and after reverting the selection it is not: these are the
                // current figures for the period now selected, fetched this session.
                // One fetch failed, so one line says so and nothing else changes.
                //
                // Gated on the state being `.loaded` rather than on
                // `hasSyncedFigures`: from `.stale` (cold start on cache) or
                // `.failed` the figures really are not current, and `fail(...)`
                // keeps whichever of those two is true.
                print("⚠️ Mileage: period fetch failed — \(error.localizedDescription)")
                periodNotice = periodFetchFailureNotice
            } else {
                fail(MileageFailureCard.genericMessage, underlying: error)
            }
            return
        }
        // Only the fetch that is still the current selection may write figures. Two
        // taps in flight otherwise land in whatever order the network returns them,
        // and the header — derived from the selection — sits over the loser's money
        // until the screen is reopened.
        guard isCurrent(generation), requestedIndex == selectedPeriodIndex else { return }

        // APPLIED AS SOON AS IT LANDS, before the year fetch is even attempted, so
        // nothing downstream can discard it.
        applyPeriod(reports)
        periodNotice = nil
        succeed()

        // THE CHIP PATH IS ALSO THE RECOVERY PATH. After a failed first load the month
        // and year figures have never been fetched, so this tap loads them too — the
        // tiles otherwise stay in their unloaded presentation for the whole session.
        guard !monthYearLoaded else { return }
        do {
            let yearReports = try await DailyJobReportService.shared.getReports(
                userId: userId, startDate: yearStart, endDate: yearEnd)
            guard isCurrent(generation), requestedIndex == selectedPeriodIndex else { return }
            applyYearAndMonth(yearReports)
            succeed()
        } catch {
            guard isCurrent(generation), requestedIndex == selectedPeriodIndex else { return }
            // `monthYearLoaded` stays false, so the two tiles keep drawing "—" rather
            // than a total nobody fetched. The period figures above stand: they landed.
            print("⚠️ Mileage: month/year totals unavailable — \(error.localizedDescription)")
            periodNotice = yearTotalsFailureNotice
            notifyLoadEnded()
        }
    }

    /// "Couldn't load that period — still showing Jul 20 – Aug 2".
    private var periodFetchFailureNotice: String {
        guard let period = selectedPeriod else {
            return "Couldn't load that period."
        }
        let range = period.rangeLabel(monthDay: { Formatters.monthDay.string(from: $0) })
        return "Couldn't load that period — still showing \(range)."
    }

    /// The month and year query failed while the period query succeeded. The hero is
    /// current; the two tiles are not, and must not be read as real totals.
    private var yearTotalsFailureNotice: String {
        "Couldn't load your month and year totals — the pay-period figures above are current."
    }

    // MARK: - In-flight bookkeeping

    /// Raised where a full load is CREATED, before any await. See
    /// `isLoadingEverything`.
    private func beginLoadEverything() -> Int {
        loadEverythingGeneration += 1
        isLoadingEverything = true
        return loadEverythingGeneration
    }

    /// Only the newest full load may lower the flag — otherwise a superseded load
    /// finishing later reopens the gate while its replacement is still fetching, and
    /// a third `.onAppear` runs a second full load beside it.
    private func endLoadEverything(_ generation: Int) {
        guard generation == loadEverythingGeneration else { return }
        isLoadingEverything = false
    }

    @MainActor
    private func beginPeriodFetch() -> Int {
        periodFetchGeneration += 1
        isFetchingPeriod = true
        return periodFetchGeneration
    }

    /// Only the newest fetch may lower the flag: a superseded one finishing later
    /// would otherwise clear the indicator while a fetch is still running.
    @MainActor
    private func endPeriodFetch(_ generation: Int) {
        guard generation == periodFetchGeneration else { return }
        isFetchingPeriod = false
    }

    @MainActor
    private func isCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == periodFetchGeneration
    }

    /// NO `.lowercased()`: the id already is. `UserManager.getCurrentSupabaseUserID`
    /// lowercases the auth uuid at source (`UserManager.swift:71-79`), which is the
    /// only producer of `userId` here, so a second fold was a no-op citing a rule that
    /// does not apply — `daily_job_reports.user_id` is not a column this app writes
    /// from Swift's uppercase `UUID()`.
    private func resolvedUserId() -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return userId
    }

    /// True when the newest chip no longer contains today — the pay period rolled
    /// over while this instance was alive. `.shared` outlives many appearances (the
    /// dashboard widget holds it), so without this the carousel would keep offering
    /// a "current" period that ended days ago and the hero would title a past
    /// fortnight "This pay period".
    private var periodsAreStaleForToday: Bool {
        guard let newest = periods.first else { return true }
        return newest.end < Date()
    }

    /// Returns false when the carousel could not be built and the screen has already
    /// been failed — the caller must stop rather than run on to a second, wronger
    /// message about pay periods that "aren't set up yet".
    @MainActor
    private func ensurePeriods(force: Bool) async -> Bool {
        guard periods.isEmpty || force || periodsAreStaleForToday else { return true }

        let settingsRead = await loadPayPeriodSettings()
        // Rebuilding the carousel under a newer load would move the selection out
        // from under the fetch that is still running.
        guard !Task.isCancelled else { return false }

        // A FAILED LOAD IS NOT "NO SETTINGS", and this screen used to treat them as
        // the same thing because it threw the completion `Bool` away.
        // `PayPeriodService` answers a settings-less org with a hardcoded
        // 2/25/2024-anchored 14-day grid, which is the right answer for an org that
        // genuinely has no settings row. For an org whose row could not be READ it is
        // a fabricated payroll calendar: six chips, a hero header and every total
        // under them describing fortnights the org may not be on, beneath a caption
        // stating the real cycle with complete confidence.
        //
        // So a failed read with nothing already built says so and leaves `periods`
        // EMPTY, which is what makes the next `load()` retry it. A failed read with
        // periods already built keeps them — they came from a read that succeeded.
        guard settingsRead else {
            if periods.isEmpty {
                fail("Couldn't load your organization's pay periods — retry when you're back online.")
                return false
            }
            return true
        }

        let service = payPeriodService
        let built = PayPeriodSequence.build(now: Date(), calendar: calendar) { date in
            service.getPayPeriod(for: date)
        }
        periods = built
        cycle = PayPeriodCycle.from(type: service.payPeriodSettings?.type,
                                       isActive: service.payPeriodSettings?.isActive ?? false)
        if !periods.indices.contains(selectedPeriodIndex) { selectedPeriodIndex = 0 }
        return true
    }

    /// True when the organisation's row was READ — settings or no settings.
    ///
    /// NOT the completion `Bool`, which cannot answer this: the service reports
    /// `false` both for "this org carries no pay-period settings" (a real answer, and
    /// the default grid is the documented behaviour for it) and for "the org could not
    /// be fetched" (not an answer at all). `cachedOrganizationID` is assigned only on
    /// the path that actually read the row, so it is the discriminator — and the
    /// completion still gates it, because the id is only trustworthy once the call has
    /// come back.
    ///
    /// `PayPeriodService` is completion-based and caches per organisation, so this is
    /// cheap on every call after the first.
    private func loadPayPeriodSettings() async -> Bool {
        let hadSettings: Bool = await withCheckedContinuation { continuation in
            payPeriodService.loadPayPeriodSettings { continuation.resume(returning: $0) }
        }
        if hadSettings { return true }
        let orgId = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        return !orgId.isEmpty && payPeriodService.cachedOrganizationID == orgId
    }

    /// Fetch this photographer's personal rate (users.amount_per_mile) and the org's
    /// company-car rate (organizations.company_car_rate). Both fall back via
    /// VehicleRates. A rate failure is NOT a screen failure — the fallbacks are the
    /// documented behaviour — so it does not set `state`.
    ///
    /// A FAILURE IS NOT AN ANSWER. `ratesLoaded` used to be set unconditionally at
    /// the end, so one failed or cancelled fetch pinned the defaults (0.67 / 0.10)
    /// on this instance for as long as it lived — and `.shared` lives as long as the
    /// app, because the dashboard widget holds it. Most photographers have their own
    /// `amount_per_mile`, so that is the hero's money wrong until the app restarts.
    /// It is now set only when BOTH lookups resolved, and a lookup resolves when the
    /// query SUCCEEDED — a successful query returning no row, or a null column, is a
    /// real answer ("no rate set", take the fallback); a thrown query is not an
    /// answer at all and is retried by the next `load()`.
    @MainActor
    private func loadRates() async {
        let supabase = SupabaseManager.shared.client

        // RESOLVED BY ABSENCE ONLY WHERE RE-ASKING IS IMPOSSIBLE. With no signed-in
        // id there is nothing to ask and never will be on this instance — `userId` is
        // read once in `init` and `loadEverything` has already failed the screen in
        // that case — so calling that an answer costs nothing.
        //
        // THE ORG ID IS NOT SUCH A CASE, and treating it as one was wrong money. It
        // comes from UserDefaults, which `UserManager`'s resolver fills in
        // asynchronously and GIVES UP ON after three tries while `RootView` renders
        // anyway — so an empty org id at this moment means "not known yet", not "no
        // answer". Marking it resolved pinned `ratesLoaded`, and with it the 0.10
        // company-car default, for the life of `.shared` — which is the life of the
        // app, because the dashboard widget holds it. It now leaves `companyResolved`
        // false so the next load re-asks: the cost is one single-row select per
        // appearance until the id shows up, which is the right trade against a
        // company-car rate that is silently the wrong one all day.
        var personalResolved = true
        var companyResolved = true

        if let userId = resolvedUserId() {
            struct PersonalRateResponse: Codable { let amount_per_mile: Double? }
            personalResolved = false
            do {
                let rows: [PersonalRateResponse] = try await supabase
                    .from("users")
                    .select("amount_per_mile")
                    .eq("id", value: userId)
                    .limit(1)
                    .execute()
                    .value
                guard !Task.isCancelled else { return }
                personalRate = VehicleRates.resolvePersonalRate(rows.first?.amount_per_mile)
                personalResolved = true
            } catch {
                guard !Task.isCancelled else { return }
                print("⚠️ Mileage: personal rate unavailable, using the default — \(error.localizedDescription)")
            }
        }

        // NOT `.lowercased()`. `organizations.id` carries mixed-case Firebase ids
        // (production's is `T6XeeaUNoOp8VJqq36wi`), and `.eq` is a string comparison
        // — case-folding it matches ZERO rows and silently yields the fallback rate.
        // The repo's lowercase-UUID rule is about columns SUPABASE MINTS as `uuid`,
        // not about carried-over Firebase text ids. Used exactly as stored, which is
        // what `OrganizationService.getOrganization` does.
        let orgId = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        if orgId.isEmpty {
            // NOT AN ANSWER — see above. The next load re-asks.
            companyResolved = false
        } else {
            struct CompanyRateResponse: Codable { let company_car_rate: Double? }
            companyResolved = false
            do {
                let rows: [CompanyRateResponse] = try await supabase
                    .from("organizations")
                    .select("company_car_rate")
                    .eq("id", value: orgId)
                    .limit(1)
                    .execute()
                    .value
                guard !Task.isCancelled else { return }
                companyRate = VehicleRates.resolveCompanyCarRate(rows.first?.company_car_rate)
                companyResolved = true
            } catch {
                guard !Task.isCancelled else { return }
                print("⚠️ Mileage: company-car rate unavailable, using the default — \(error.localizedDescription)")
            }
        }

        if personalResolved && companyResolved { ratesLoaded = true }
    }

    // MARK: - Applying results

    @MainActor
    private func applyPeriod(_ reports: [DailyJobReport]) {
        // SORTED ONCE, HERE. The list used to read a computed `sortedRecords`, which
        // re-sorted the whole period on every body evaluation.
        records = reports.map { MileageRecordWrapper(from: $0) }.sorted { $0.date > $1.date }
        let split = MileageMath.accumulate(records,
                                          miles: { $0.totalMileage },
                                          vehicleType: { $0.vehicleType },
                                          personalRate: personalRate,
                                          companyCarRate: companyRate)
        currentPeriodPersonalMiles = split.personalMiles
        currentPeriodCompanyMiles = split.companyMiles
    }

    @MainActor
    private func applyYearAndMonth(_ reports: [DailyJobReport]) {
        let rows = reports.map { MileageRecordWrapper(from: $0) }

        let yearSplitValue = MileageMath.accumulate(rows,
                                                   miles: { $0.totalMileage },
                                                   vehicleType: { $0.vehicleType },
                                                   personalRate: personalRate,
                                                   companyCarRate: companyRate)
        yearPersonalMiles = yearSplitValue.personalMiles
        yearCompanyMiles = yearSplitValue.companyMiles

        // ONE READ, hoisted out of the closure. `calendar` mints a fresh
        // `Calendar.current` on every access, so reading it per row let a device that
        // changed zone mid-filter classify two rows of the same month differently.
        let now = Date()
        let calendar = self.calendar
        // THE STORED DAY IS READ IN UTC, "this month" in the device's calendar — see
        // `MileageMath.storedDayCalendar`. Bucketing the report locally dropped every
        // 1st-of-month trip into the previous month and made this tile disagree with
        // Statistics about the same row.
        let monthRows = rows.filter {
            MileageMath.isInSameMonth($0.date, as: now, referenceCalendar: calendar)
        }
        let monthSplitValue = MileageMath.accumulate(monthRows,
                                                    miles: { $0.totalMileage },
                                                    vehicleType: { $0.vehicleType },
                                                    personalRate: personalRate,
                                                    companyCarRate: companyRate)
        monthPersonalMiles = monthSplitValue.personalMiles
        monthCompanyMiles = monthSplitValue.companyMiles

        // THE ONLY PLACE THIS BECOMES TRUE. Everything downstream that claims the
        // month and year figures are real — the widget's cache, the two tiles'
        // `.loaded` state — is gated on it.
        monthYearLoaded = true
    }

    @MainActor
    private func succeed() {
        hasSyncedFigures = true
        state = .loaded
        cacheHeadlineTotals()

        // THE SUBSCRIBER IS GATED ON THE SAME FLAG THE CACHE IS. `succeed()` runs
        // twice per load — once when the period lands and again after the year does —
        // and the dashboard widget's callback body writes cached_monthMileage and
        // cached_yearMileage UNGATED (`DashboardWidgets.swift:846-856`). Firing it on
        // the first call therefore persisted month and year figures nobody had fetched:
        // zeroes on a cold start, read back on the next launch as real totals. The
        // second call carries the real ones, so the widget is told then.
        //
        // Gated HERE rather than in the widget because the flag lives here and the
        // widget is another phase's screen: this object knows whether the two figures
        // it is publishing were ever loaded, and the subscriber cannot.
        guard monthYearLoaded else { return }
        updateCallback?()
    }

    /// THE LOAD IS OVER, however it ended — tell the subscriber.
    ///
    /// The gate in `succeed()` closes a real hole and opens a smaller one: on a load
    /// whose period query SUCCEEDED and whose year query FAILED, neither `succeed()`
    /// (gated) nor `fail()` (not called — the period figures are good) would notify,
    /// and `MileageWidget` lowers its `isLoading` only inside this callback. A cold
    /// start with no cache would spin there forever. This is that path's exit.
    ///
    /// IT CANNOT PERSIST A FIGURE NOBODY FETCHED. While `monthYearLoaded` is false the
    /// month and year buckets still hold exactly what `init` seeded them with — the
    /// cached totals — because `applyYearAndMonth` is the only writer and it is what
    /// raises the flag. So the widget's ungated cache write copies back the values that
    /// were already in those keys.
    @MainActor
    private func notifyLoadEnded() {
        updateCallback?()
    }

    @MainActor
    private func fail(_ message: String, underlying: Error? = nil) {
        if let underlying {
            print("⚠️ Mileage load failed: \(underlying.localizedDescription)")
        }
        // Figures that DID sync are still true, just older than now. Zeroing them
        // is the failure mode this state machine exists to remove.
        state = hasSyncedFigures ? .stale(message) : .failed(message)

        // THE SUBSCRIBER IS TOLD ABOUT A FAILURE TOO, and that is a fix rather than
        // noise. `MileageWidget` raises its own `isLoading` when it has no cache and
        // lowers it ONLY inside this callback (`DashboardWidgets.swift:840-844`,
        // `:857-859`) — so a cold start that could not reach the server left the home
        // widget spinning for as long as the dashboard stayed on screen. It now
        // renders the values it seeded itself, which on that path are zeroes: a
        // widget showing 0 mi with no cache behind it is honest about having nothing,
        // and an eternal spinner is not.
        //
        // NO CACHE KEY IS WRITTEN ON THIS PATH: `cacheHeadlineTotals()` is not called
        // here, and the widget's own writes copy the figures it just read, which on a
        // failure are the ones it already had.
        updateCallback?()
    }

    /// EACH KEY IS WRITTEN ONLY WHEN THE FIGURE BEHIND IT WAS LOADED.
    ///
    /// The period key needs the CURRENT period selected: the cache is what the
    /// dashboard widget shows before its own fetch lands, so filling it from a
    /// period the user happened to browse back to would make the home screen state
    /// last fortnight's miles as this fortnight's.
    ///
    /// The month and year keys need `monthYearLoaded`, for the same reason one step
    /// further: the chip path does not fetch them, so writing them from a chip
    /// success persisted whatever they happened to hold — zero on a session whose
    /// only successful load was a chip tap — and the widget then read that zero back
    /// on the next cold start as a real total.
    private func cacheHeadlineTotals() {
        if selectedPeriod?.isCurrent == true {
            UserDefaults.standard.set(currentPeriodMileage, forKey: Cache.periodMiles)
        }
        if monthYearLoaded {
            UserDefaults.standard.set(monthMileage, forKey: Cache.monthMiles)
            UserDefaults.standard.set(yearMileage, forKey: Cache.yearMiles)
        }
    }

    // MARK: - The calendar year the tiles count

    /// EACH BOUNDARY READS `calendar` ONCE. It mints a fresh `Calendar.current` per
    /// access, so the two-access version could take the year from one zone and mint
    /// the date in another — an off-by-an-hour Jan 1 at the edge of a zone change,
    /// which is a whole day of trips in or out of the year total.
    private var yearStart: Date {
        let calendar = self.calendar
        var comps = DateComponents()
        comps.year = calendar.component(.year, from: Date())
        comps.month = 1
        comps.day = 1
        return calendar.date(from: comps) ?? Date()
    }

    private var yearEnd: Date {
        let calendar = self.calendar
        var comps = DateComponents()
        comps.year = calendar.component(.year, from: Date())
        comps.month = 12
        comps.day = 31
        comps.hour = 23
        comps.minute = 59
        comps.second = 59
        return calendar.date(from: comps) ?? Date()
    }
}
