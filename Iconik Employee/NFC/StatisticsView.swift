//  StatisticsView.swift
//  Iconik Employee — job box / SD card statistics, converted (AMB.11)
//
//  Drawn from the approved `JobBoxLabStatsSurface`. Rendered BARE inside
//  `NFCContainerView`, which owns the one nav bar (title "Statistics") and the
//  one backdrop — this file adds neither.
//
//  THE ARITHMETIC IS UNCHANGED, WITH ONE DELIBERATE DEVIATION, recorded in the
//  audit round (2026-07-30):
//
//    · PHOTOGRAPHER ACTIVITY NOW OBEYS THE TIME FRAME. The old code fed it the
//      UNFILTERED record set while every other block on the screen used the
//      time-frame window, so switching to "This week" left one section reporting
//      all time — a screen contradicting its own filter. It is now fed
//      `filtered`, like everything else, and the numbers there will be SMALLER
//      than they used to be for any window narrower than the whole history.
//      Kept deliberately; see the call site in `calculateStats`.
//
//  Everything else is computed exactly as it was, including the parts that are
//  surprising (§1.5), because this is a design phase and D12 says the business
//  rules do not change in one:
//    - status distribution counts DISTINCT cards/boxes at their latest scan, not
//      scans;
//    - "average time in status" divides by the number of INTERVAL SAMPLES, not
//      by the number of cards, and folds in the open dwell (now − last scan)
//      only when it is under 30 days — so an idle card contributes nothing and
//      an open one inflates the mean;
//    - only ADJACENT status pairs count for the job-box timeline, so a Left Job
//      scan between pickup and turn-in destroys the completion pair; intervals
//      are accepted only between 0 and 168 hours, card cycles only between 0 and
//      90 days;
//    - photographer activity counts DISTINCT box numbers, top five;
//    - the "Left Job" average mixes closed spans (counted only at an hour or
//      more) with spans that are still open. That one is now SAID OUT LOUD under
//      the block instead of being hidden behind the word "Average".
//
//  DELETED IN THE SAME CHANGE (delete-first migration):
//    - the hand-drawn pie: `PieSlice`, `PieChartSlice`, `createPieChartSlices`,
//      the `startAngle`/`endAngle`/`labelPosition` chain (N20) and the white
//      trig-positioned slice labels that were near-invisible over envelope
//      #FFCC00 (N57). Its `Int(%)` truncation sat beside a legend printing
//      `%.1f%%` — two roundings of one number, side by side (N56). The
//      distribution is now labelled bars;
//    - `findTappedStatus(at:in:)` — 88 lines of DONUT hit-testing with zero call
//      sites, on a view that never drew a donut (N11);
//    - `extension CGRect { var midPoint }` — zero call sites app-wide (N21);
//    - every `#available(iOS 16.0, *)` else-branch, including the string
//      "Chart requires iOS 16+" that no user could ever see: the deployment
//      target is 16.6 (N19). `import Charts` goes with them — the mockup's stats
//      surface is stat-line cards, not charts;
//    - roughly twenty `print("DEBUG:")` calls inside the per-photographer,
//      per-box, per-transition loops, which ran on every mode and time-frame
//      switch (N22);
//    - `colorScheme`, `lastTapLocation` and `debugMode` — unused state, the last
//      of which gated an unreachable disjunct (N48);
//    - four copies of two algorithms, collapsed to one generic each (N64).
//
//  ADDED (approved): a loading state — `isLoading` was written in three places
//  and never read, so the first paint was a full set of ZEROES that read as an
//  answer (N10); a failure state with a real retry, keeping the partial-failure
//  semantics (an SD failure aborts everything, a job-box failure still computes
//  the SD half) and saying so when the job-box failure is simply that there is
//  no offline cache for boxes; an empty state; and an HONEST empty state for
//  photographer activity in SD mode, which was drawn as a titled, permanently
//  empty chart because the `records` table has no photographer column (§0.26).

import SwiftUI

struct StatisticsView: View {
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var offlineManager = OfflineDataManager.shared

    // Callback for navigation to search
    var onNavigateToSearch: ((String, Bool) -> Void)?

    @State private var records: [NFCRecord] = []
    @State private var jobBoxRecords: [JobBox] = []

    @State private var isLoading = false
    /// So a re-appearance refreshes behind the numbers already on screen rather
    /// than blanking them back to the loading card.
    @State private var hasLoaded = false
    /// An SD failure aborts everything; a job-box failure only blocks job-box
    /// mode. Kept exactly as the shipped load path behaved.
    @State private var sdFailure: String?
    @State private var jobBoxFailure: String?

    @State private var selectedTimeFrame: TimeFrame = .all
    @State private var isJobBoxMode = false

    // For status distribution
    @State private var statusCounts: [StatusCount] = []
    @State private var totalCards: Int = 0

    // For time tracking
    @State private var averageTimes: [StatusTime] = []

    // For card lifecycle tracking
    @State private var cardLifecycles: [CardLifecycle] = []
    @State private var averageCycleDuration: Double = 0
    @State private var shortestCycle: Double = 0
    @State private var longestCycle: Double = 0
    @State private var totalCompletedCycles: Int = 0

    // For job box specific stats
    @State private var jobBoxStatusCounts: [StatusCount] = []
    @State private var totalJobBoxes: Int = 0
    @State private var jobBoxAverageTimes: [StatusTime] = []
    @State private var averageJobAssignmentTime: Double = 0 // Time from Packed to Picked Up
    @State private var averageJobCompletionTime: Double = 0 // Time from Picked Up to Turned In

    // For photographer job box "Left Job" duration metrics
    @State private var photographerLeftJobTimes: [PhotographerLeftJobTime] = []
    @State private var photographerActivity: [PhotographerData] = []

    enum TimeFrame: String, CaseIterable, Identifiable {
        case day = "Today"
        case week = "This Week"
        case month = "This Month"
        case all = "All Time"

        var id: String { self.rawValue }
    }

    /// The share is NOT stored any more. It used to be, formatted `%.1f%%` for
    /// the legend while the pie beside it printed a truncated `Int(%)` of the
    /// same number (N56); `JobBoxDistributionRow` derives the one percentage it
    /// shows from `count` and `total`, so there is nothing left to disagree.
    struct StatusCount: Identifiable {
        let id = UUID()
        let status: String
        let count: Int
    }

    struct StatusTime: Identifiable {
        let id = UUID()
        let status: String
        let averageHours: Double

        var formattedTime: String {
            if averageHours < 24 {
                return String(format: "%.1f hours", averageHours)
            } else {
                let days = averageHours / 24
                return String(format: "%.1f days", days)
            }
        }
    }

    struct CardLifecycle: Identifiable {
        let id = UUID()
        let cardNumber: String
        let startDate: Date
        let endDate: Date
        let durationDays: Double
    }

    // Data structure for photographer activity
    struct PhotographerData: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
    }

    // Status colours. Job boxes read the one iOS↔web contract
    // (JobBoxTripStage.meterTint); SD cards read the SD map. The single
    // `StatusColors` job-box map they both used to share was deleted 2026-07-30 —
    // it disagreed with the shipped meter on three of four statuses.
    func statusColor(_ status: String) -> Color {
        if isJobBoxMode {
            // The fallback is the never-scanned/unreadable-status colour, not a
            // status colour of its own.
            return JobBoxTripStage(stored: status)?.meterTint ?? Color(hex: "#7A8794")
        }
        return StatusColors.color(forSDStatus: status)
    }

    private var tint: Color { FeatureTheme.color(for: "scan") }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("View Mode", selection: $isJobBoxMode) {
                    Text("Job Boxes").tag(true)
                    Text("SD Cards").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: isJobBoxMode) { _ in
                    // Recalculate stats when changing modes — no refetch.
                    calculateStats()
                }

                VStack(alignment: .leading, spacing: 8) {
                    AmbientSectionTitle("Time frame")
                    AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(TimeFrame.allCases) { frame in
                            JobBoxChip(text: frame.rawValue,
                                       on: selectedTimeFrame == frame,
                                       tint: tint) {
                                withAnimation(AmbientMotion.snappy) { selectedTimeFrame = frame }
                                calculateStats()
                            }
                        }
                    }
                }

                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear {
            loadData()
        }
    }

    /// An SD failure aborts everything; a job-box failure blocks only job-box
    /// mode, because the SD half was still computed.
    private var blockingFailure: String? {
        if let sdFailure { return sdFailure }
        if isJobBoxMode, let jobBoxFailure { return jobBoxFailure }
        return nil
    }

    private var currentStatusCounts: [StatusCount] {
        isJobBoxMode ? jobBoxStatusCounts : statusCounts
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && !hasLoaded {
            JobBoxLoadingCard(message: "Loading statistics…")
        } else if let message = blockingFailure {
            JobBoxFailureCard(message: message, retry: loadData)
        } else if currentStatusCounts.isEmpty {
            AmbientEmptyState(title: "No data available",
                              message: "No scans in this time frame.",
                              systemImage: "chart.bar")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                distribution
                averages
                lifecycle
                photographerActivitySection
                if isJobBoxMode {
                    leftJobDurations
                }
            }
        }
    }

    // MARK: - Distribution

    /// EACH ROW IS STILL A TAP THROUGH to Search filtered to that status — the
    /// only cross-screen navigation this view has, and it is kept.
    private var distribution: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle(isJobBoxMode ? "Job box status distribution" : "Card status distribution",
                                trailing: isJobBoxMode
                                    ? "Total Job Boxes: \(totalJobBoxes)"
                                    : "Total Cards: \(totalCards)")

            VStack(spacing: 10) {
                ForEach(currentStatusCounts) { item in
                    Button {
                        navigateToSearchView(with: item.status)
                    } label: {
                        JobBoxDistributionRow(label: item.status,
                                              count: item.count,
                                              total: isJobBoxMode ? totalJobBoxes : totalCards,
                                              tint: statusColor(item.status))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows every \(isJobBoxMode ? "box" : "card") currently at \(item.status)")
                }
            }
            .ambientCard(density: .compact, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
        }
    }

    // MARK: - Average time in status

    private var averages: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Average time in status")
            VStack(spacing: 8) {
                let times = isJobBoxMode ? jobBoxAverageTimes : averageTimes
                if times.isEmpty {
                    Text("No data available")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(times) { item in
                        JobBoxStatLine(label: item.status, value: item.formattedTime)
                    }
                }
            }
            .ambientCard(density: .compact, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
        }
    }

    // MARK: - Lifecycle

    @ViewBuilder
    private var lifecycle: some View {
        if isJobBoxMode {
            VStack(alignment: .leading, spacing: 8) {
                AmbientSectionTitle("Job box processing timeline")
                VStack(spacing: 8) {
                    JobBoxStatLine(label: "Assignment · Packed → Picked Up",
                                   value: String(format: "%.1f hours", averageJobAssignmentTime))
                    JobBoxStatLine(label: "Completion · Picked Up → Turned In",
                                   value: String(format: "%.1f hours", averageJobCompletionTime))
                }
                .ambientCard(density: .compact, fill: .surface,
                             border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                AmbientSectionTitle("Card lifecycle", trailing: "Job Box → Cleared")
                VStack(spacing: 8) {
                    if totalCompletedCycles > 0 {
                        JobBoxStatLine(label: "Average",
                                       value: String(format: "%.1f days", averageCycleDuration))
                        JobBoxStatLine(label: "Shortest",
                                       value: String(format: "%.1f days", shortestCycle))
                        JobBoxStatLine(label: "Longest",
                                       value: String(format: "%.1f days", longestCycle))
                        JobBoxStatLine(label: "Total completed cycles",
                                       value: "\(totalCompletedCycles)")

                        Divider()

                        // The ten most recent completed cycles — what the bar
                        // chart plotted, as lines.
                        ForEach(Array(cardLifecycles.prefix(10))) { cycle in
                            JobBoxStatLine(label: "Card #\(cycle.cardNumber)",
                                           value: String(format: "%.1f days", cycle.durationDays))
                        }
                    } else {
                        Text("No complete card cycles found")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Complete cycles go from Job Box to Cleared status")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .ambientCard(density: .compact, fill: .surface,
                             border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
            }
        }
    }

    // MARK: - Photographer activity

    @ViewBuilder
    private var photographerActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Photographer activity")
            if isJobBoxMode {
                VStack(spacing: 8) {
                    if photographerActivity.isEmpty {
                        Text("No data available")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(photographerActivity) { item in
                            JobBoxStatLine(label: item.name, value: "\(item.count) boxes")
                        }
                    }
                }
                .ambientCard(density: .compact, fill: .surface,
                             border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
            } else {
                // The honest version of a chart that was drawn titled and
                // permanently empty: the `records` table has no photographer
                // column, so every SD row's photographer is the empty string and
                // the grouping drops all of them.
                AmbientEmptyState(
                    title: "Not available for SD cards",
                    message: "SD card scans do not record who scanned them, so there is nothing to group by.",
                    systemImage: "person.crop.circle.badge.questionmark")
            }
        }
    }

    // MARK: - Left Job durations

    private var leftJobDurations: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Job Box 'Left Job' Duration by Photographer")

            VStack(spacing: 12) {
                if photographerLeftJobTimes.isEmpty {
                    Text("No 'Left Job' data available")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(photographerLeftJobTimes) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(metric.photographerName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                if metric.currentBoxes > 0 {
                                    Label("\(metric.currentBoxes)", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            JobBoxStatLine(label: "Average Time", value: metric.formattedAverageTime)
                            JobBoxStatLine(label: "Total Transitions", value: "\(metric.transitionCount)")
                            if metric.currentBoxes > 0 {
                                JobBoxStatLine(label: "Currently Left", value: "\(metric.currentBoxes)")
                            }
                        }
                    }
                }
            }
            .ambientCard(density: .compact, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)

            Text("\"Average Time\" mixes completed spans — counted only at an hour or more — with spans that are still open, so it is not a like-for-like average.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Navigation

    func navigateToSearchView(with status: String) {
        if let navigate = onNavigateToSearch {
            navigate(status, isJobBoxMode)
        }
    }

    // MARK: - Loading

    func loadData() {
        // Fires on every appearance and re-pulls both tables whole, as before —
        // with a guard so two appearances cannot run two loads at once.
        guard !isLoading else { return }

        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            sdFailure = "User organization not found."
            return
        }

        isLoading = true
        sdFailure = nil
        jobBoxFailure = nil

        // Load SD card records
        DatabaseManager.shared.fetchRecords(field: "all", value: "", organizationID: orgID) { result in
            switch result {
            case .success(let fetchedRecords):
                self.records = fetchedRecords

                // Now load job box records
                DatabaseManager.shared.fetchJobBoxRecords(field: "all", value: "", organizationID: orgID) { jobBoxResult in
                    self.isLoading = false
                    self.hasLoaded = true

                    switch jobBoxResult {
                    case .success(let fetchedJobBoxRecords):
                        self.jobBoxRecords = fetchedJobBoxRecords

                        // Calculate stats once both data sets are loaded
                        self.calculateStats()

                    case .failure(let error):
                        // Kept: a job-box failure still computes the SD half.
                        // There is NO offline cache for job boxes, unlike SD
                        // cards, so say that rather than blaming the server.
                        self.jobBoxFailure = self.offlineManager.isOnline
                            ? "Couldn't load job box statistics. \(error.localizedDescription)"
                            : "Couldn't load job box statistics. Job box data is not available offline — there is no offline cache for boxes, unlike SD cards."
                        self.calculateStats()
                    }
                }

            case .failure(let error):
                // Kept: an SD failure aborts everything.
                self.isLoading = false
                self.sdFailure = "Couldn't load statistics. \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Computation

    func calculateStats() {
        if isJobBoxMode {
            let filtered = filterByTimeFrame(jobBoxRecords) { $0.timestampDate }
            let distribution = statusDistribution(filtered, key: { $0.boxNumber },
                                                  date: { $0.timestampDate },
                                                  status: { $0.status })
            jobBoxStatusCounts = distribution.counts
            totalJobBoxes = distribution.total
            jobBoxAverageTimes = averageTimeInStatus(filtered, key: { $0.boxNumber },
                                                     date: { $0.timestampDate },
                                                     status: { $0.status })
            calculateJobBoxTimelines(filtered)
            // THE ONE DELIBERATE ARITHMETIC DEVIATION (see the file header):
            // this was handed the UNFILTERED `jobBoxRecords`, so Photographer
            // activity ignored the Time Frame chips the rest of the screen
            // obeys. `filtered` is the fix and it is kept.
            calculatePhotographerActivity(filtered)
            calculatePhotographerLeftJobTimes(filtered)
        } else {
            let filtered = filterByTimeFrame(records) { $0.timestamp }
            let distribution = statusDistribution(filtered, key: { $0.cardNumber },
                                                  date: { $0.timestamp },
                                                  status: { $0.status })
            statusCounts = distribution.counts
            totalCards = distribution.total
            averageTimes = averageTimeInStatus(filtered, key: { $0.cardNumber },
                                               date: { $0.timestamp },
                                               status: { $0.status })
            calculateCardLifecycles(filtered)
        }
    }

    /// The time-frame window, one copy instead of two line-for-line duplicates
    /// (N64). `.week` uses `yearForWeekOfYear` + `weekOfYear`, so the week starts
    /// on the LOCALE's first weekday — unchanged, and worth knowing.
    ///
    /// The four force unwraps this replaces (N58) are now safe fallbacks: a
    /// calendar that cannot build the start of the week or the month falls back
    /// to the start of today, which is the narrowest honest window rather than a
    /// crash.
    private func filterByTimeFrame<T>(_ items: [T], date: (T) -> Date) -> [T] {
        let calendar = Calendar.current
        let now = Date()

        switch selectedTimeFrame {
        case .day:
            let startOfDay = calendar.startOfDay(for: now)
            return items.filter { calendar.isDate(date($0), inSameDayAs: startOfDay) }

        case .week:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let startOfWeek = calendar.date(from: components) ?? calendar.startOfDay(for: now)
            return items.filter { date($0) >= startOfWeek }

        case .month:
            let components = calendar.dateComponents([.year, .month], from: now)
            let startOfMonth = calendar.date(from: components) ?? calendar.startOfDay(for: now)
            return items.filter { date($0) >= startOfMonth }

        case .all:
            return items
        }
    }

    /// Group by card/box, take the max-timestamp row for each, count those by
    /// lowercased status, label with `.capitalized`. The total is a count of
    /// DISTINCT cards/boxes, not of scans.
    private func statusDistribution<T>(_ items: [T],
                                       key: (T) -> String,
                                       date: (T) -> Date,
                                       status: (T) -> String) -> (counts: [StatusCount], total: Int) {
        let groups = Dictionary(grouping: items, by: key)

        var latestRecords: [T] = []
        for (_, group) in groups {
            if let latest = group.sorted(by: { date($0) > date($1) }).first {
                latestRecords.append(latest)
            }
        }

        let statusGroups = Dictionary(grouping: latestRecords, by: { status($0).lowercased() })
        let counts = statusGroups.mapValues { $0.count }
        let total = latestRecords.count

        let result = counts.map { statusKey, count in
            StatusCount(status: statusKey.capitalized, count: count)
        }.sorted { $0.count > $1.count }

        return (result, total)
    }

    /// Per card/box, every adjacent-pair interval `> 0` goes into a bucket keyed
    /// by the EARLIER record's status; then the open dwell (now − last scan) goes
    /// into the last status's bucket only when `0 < duration < 30 days`. The mean
    /// divides by the number of INTERVAL SAMPLES, not by the number of cards.
    ///
    /// One copy instead of two line-for-line duplicates (N64).
    private func averageTimeInStatus<T>(_ items: [T],
                                        key: (T) -> String,
                                        date: (T) -> Date,
                                        status: (T) -> String) -> [StatusTime] {
        let groups = Dictionary(grouping: items, by: key)

        var statusDurations: [String: [TimeInterval]] = [:]

        for (_, group) in groups {
            let sortedRecords = group.sorted(by: { date($0) < date($1) })

            // Process transitions
            for i in 0..<max(0, sortedRecords.count - 1) {
                let currentRecord = sortedRecords[i]
                let nextRecord = sortedRecords[i + 1]

                let duration = date(nextRecord).timeIntervalSince(date(currentRecord))
                let key = status(currentRecord).lowercased()

                if duration > 0 {
                    statusDurations[key, default: []].append(duration)
                }
            }

            // For the last record, calculate time from then to now (if it's recent enough)
            if let lastRecord = sortedRecords.last {
                let duration = Date().timeIntervalSince(date(lastRecord))
                let key = status(lastRecord).lowercased()

                // Only include if it's less than 30 days to avoid skewing data
                if duration > 0 && duration < (30 * 24 * 60 * 60) {
                    statusDurations[key, default: []].append(duration)
                }
            }
        }

        return statusDurations.compactMap { statusKey, durations in
            guard !durations.isEmpty else { return nil }
            let totalSeconds = durations.reduce(0, +)
            let averageSeconds = totalSeconds / Double(durations.count)
            let averageHours = averageSeconds / 3600.0 // Convert to hours

            return StatusTime(status: statusKey.capitalized, averageHours: averageHours)
        }.sorted { $0.averageHours > $1.averageHours }
    }

    /// The metric is DISTINCT box numbers, not scan count; empty names are
    /// skipped; top five.
    ///
    /// JOB BOXES ONLY. The SD branch this used to carry could never produce a
    /// row — every SD record's photographer is the empty string (§0.26) — and
    /// SD mode now shows an empty state that says so.
    private func calculatePhotographerActivity(_ records: [JobBox]) {
        let groups = Dictionary(grouping: records, by: { $0.scannedBy })

        photographerActivity = groups.compactMap { name, boxes -> PhotographerData? in
            guard !name.isEmpty else { return nil }
            return PhotographerData(name: name, count: Set(boxes.map { $0.boxNumber }).count)
        }
        .sorted { $0.count > $1.count }
        .prefix(5) // Just show top 5 photographers
        .map { $0 } // Convert to array
    }

    func calculateCardLifecycles(_ records: [NFCRecord]) {
        // Group all records by card number
        let cardGroups = Dictionary(grouping: records, by: { $0.cardNumber })

        var lifecycles: [CardLifecycle] = []

        for (cardNumber, cardRecords) in cardGroups {
            // Sort records by timestamp (oldest first)
            let sortedRecords = cardRecords.sorted(by: { $0.timestamp < $1.timestamp })

            // Find all job box entries (cycle starts)
            let jobBoxEntries = sortedRecords.filter { $0.status.lowercased() == "job box" }

            // For each job box entry, find the next "cleared" status.
            //
            // NAMED, NOT FIXED (finding N46): `subsequentRecords` is recomputed
            // from the full sorted list every iteration, so ONE "cleared" row can
            // close SEVERAL "job box" starts for the same card and overlapping
            // cycles are double counted. Changing it would change the numbers,
            // which a design phase does not do (D12).
            for jobBoxEntry in jobBoxEntries {
                // Find records that occurred after this job box entry
                let subsequentRecords = sortedRecords.filter { $0.timestamp > jobBoxEntry.timestamp }

                // Find the next "cleared" status
                if let clearedEntry = subsequentRecords.first(where: { $0.status.lowercased() == "cleared" }) {
                    // Calculate duration in days
                    let durationSeconds = clearedEntry.timestamp.timeIntervalSince(jobBoxEntry.timestamp)
                    let durationDays = durationSeconds / (24 * 3600) // Convert seconds to days

                    // Only include realistic cycles (more than 0 days, less than 90 days)
                    if durationDays > 0 && durationDays < 90 {
                        let lifecycle = CardLifecycle(
                            cardNumber: cardNumber,
                            startDate: jobBoxEntry.timestamp,
                            endDate: clearedEntry.timestamp,
                            durationDays: durationDays
                        )
                        lifecycles.append(lifecycle)
                    }
                }
            }
        }

        // Calculate statistics
        if !lifecycles.isEmpty {
            let totalDays = lifecycles.reduce(0) { $0 + $1.durationDays }
            averageCycleDuration = totalDays / Double(lifecycles.count)
            shortestCycle = lifecycles.min(by: { $0.durationDays < $1.durationDays })?.durationDays ?? 0
            longestCycle = lifecycles.max(by: { $0.durationDays < $1.durationDays })?.durationDays ?? 0
            totalCompletedCycles = lifecycles.count
        } else {
            averageCycleDuration = 0
            shortestCycle = 0
            longestCycle = 0
            totalCompletedCycles = 0
        }

        cardLifecycles = lifecycles.sorted(by: { $0.endDate > $1.endDate })
    }

    func calculateJobBoxTimelines(_ records: [JobBox]) {
        // Group by box number
        let boxGroups = Dictionary(grouping: records, by: { $0.boxNumber })

        var assignmentTimes: [Double] = []
        var completionTimes: [Double] = []

        for (_, boxRecords) in boxGroups {
            // Sort records by timestamp (oldest first)
            let sortedRecords = boxRecords.sorted(by: { $0.timestampDate < $1.timestampDate })

            // Find transition times between ADJACENT statuses only — a Left Job
            // scan between pickup and turn-in destroys the completion pair.
            for i in 0..<max(0, sortedRecords.count - 1) {
                let currentRecord = sortedRecords[i]
                let nextRecord = sortedRecords[i + 1]

                // Packed → Picked Up (Assignment time)
                if currentRecord.jobBoxStatus == .packed && nextRecord.jobBoxStatus == .pickedUp {
                    let durationHours = nextRecord.timestampDate.timeIntervalSince(currentRecord.timestampDate) / 3600.0
                    if durationHours > 0 && durationHours < 168 { // Less than a week to avoid outliers
                        assignmentTimes.append(durationHours)
                    }
                }

                // Picked Up → Turned In (Completion time)
                if currentRecord.jobBoxStatus == .pickedUp && nextRecord.jobBoxStatus == .turnedIn {
                    let durationHours = nextRecord.timestampDate.timeIntervalSince(currentRecord.timestampDate) / 3600.0
                    if durationHours > 0 && durationHours < 168 { // Less than a week to avoid outliers
                        completionTimes.append(durationHours)
                    }
                }
            }
        }

        // Calculate averages
        if !assignmentTimes.isEmpty {
            averageJobAssignmentTime = assignmentTimes.reduce(0, +) / Double(assignmentTimes.count)
        } else {
            averageJobAssignmentTime = 0
        }

        if !completionTimes.isEmpty {
            averageJobCompletionTime = completionTimes.reduce(0, +) / Double(completionTimes.count)
        } else {
            averageJobCompletionTime = 0
        }
    }

    /// A run of `.leftJob` opens a span. A CLOSED span counts only at an hour or
    /// more; an OPEN span (leftJob is the box's last record) counts with no
    /// minimum at all and also increments `currentBoxes`. The mean is total ÷
    /// transitions — so it mixes the two, which the caption under the block now
    /// says out loud.
    ///
    /// The ~20 `print("DEBUG:")` calls that ran once per photographer, per box
    /// and per transition are gone (N22), as is the `debugMode` disjunct that
    /// could never be true (N48). The old `else averageHours = totalLeftJobHours`
    /// branch was unreachable — `currentBoxes` and `transitions` are incremented
    /// together, so zero transitions means zero current boxes and the metric was
    /// not appended at all.
    func calculatePhotographerLeftJobTimes(_ records: [JobBox]) {
        // Group by photographer (scannedBy field)
        let photographerGroups = Dictionary(grouping: records, by: { $0.scannedBy })

        var leftJobMetrics: [PhotographerLeftJobTime] = []
        let currentTime = Date()

        for (photographerName, boxRecords) in photographerGroups {
            // Skip if no photographer name
            if photographerName.isEmpty { continue }

            // Sort records by box number and timestamp to group by individual box
            let sortedByBox = Dictionary(grouping: boxRecords, by: { $0.boxNumber })

            var totalLeftJobHours: Double = 0
            var leftJobTransitionsCount: Int = 0
            var currentLeftJobBoxes: Int = 0

            for (_, boxRecords) in sortedByBox {
                let sortedRecords = boxRecords.sorted(by: { $0.timestampDate < $1.timestampDate })

                // Track periods in "Left Job" status
                var inLeftJob = false
                var leftJobStartTime: Date?

                for (index, record) in sortedRecords.enumerated() {
                    if record.jobBoxStatus == .leftJob {
                        if !inLeftJob {
                            // Entering "Left Job" status
                            inLeftJob = true
                            leftJobStartTime = record.timestampDate
                        }

                        // If this is the last record for this box and it's still in "Left Job"
                        if index == sortedRecords.count - 1 && inLeftJob {
                            currentLeftJobBoxes += 1

                            // Add the time from the start to now for current boxes still in "Left Job"
                            if let startTime = leftJobStartTime {
                                let hoursInLeftJob = currentTime.timeIntervalSince(startTime) / 3600.0

                                // Always count current boxes, regardless of duration
                                totalLeftJobHours += hoursInLeftJob
                                leftJobTransitionsCount += 1
                            }
                        }
                    } else if inLeftJob {
                        // Transitioning out of "Left Job" status
                        inLeftJob = false

                        if let startTime = leftJobStartTime {
                            let hoursInLeftJob = record.timestampDate.timeIntervalSince(startTime) / 3600.0

                            // Only count if it was in "Left Job" for at least 1 hour
                            if hoursInLeftJob >= 1 {
                                totalLeftJobHours += hoursInLeftJob
                                leftJobTransitionsCount += 1
                            }
                        }

                        // Reset the start time
                        leftJobStartTime = nil
                    }
                }
            }

            // Calculate the average hours in "Left Job" status
            let averageHours = leftJobTransitionsCount > 0
                ? totalLeftJobHours / Double(leftJobTransitionsCount)
                : 0

            let metric = PhotographerLeftJobTime(
                photographerName: photographerName,
                averageHours: averageHours,
                totalHours: totalLeftJobHours,
                transitionCount: leftJobTransitionsCount,
                currentBoxes: currentLeftJobBoxes
            )

            // Include photographers with any data about job boxes in "Left Job" status
            if leftJobTransitionsCount > 0 || currentLeftJobBoxes > 0 {
                leftJobMetrics.append(metric)
            }
        }

        // Sort by average time, longest first
        self.photographerLeftJobTimes = leftJobMetrics.sorted(by: { $0.averageHours > $1.averageHours })
    }
}

// MARK: - Supporting Structs

struct PhotographerLeftJobTime: Identifiable {
    let id = UUID()
    let photographerName: String
    let averageHours: Double
    let totalHours: Double
    let transitionCount: Int
    let currentBoxes: Int

    var formattedAverageTime: String {
        if averageHours < 24 {
            return String(format: "%.1f hours", averageHours)
        } else {
            let days = averageHours / 24
            return String(format: "%.1f days", days)
        }
    }
}
