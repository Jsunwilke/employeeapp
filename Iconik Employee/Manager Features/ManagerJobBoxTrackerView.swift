//  ManagerJobBoxTrackerView.swift
//  Iconik Employee — the manager's job box tracker, converted in AMB.11
//
//  THE DESIGN IS `JobBoxLabTrackerSurface` / `JobBoxLabTrackerRow` /
//  `JobBoxLabEditSheet` in `DesignLab/Mockups/JobBoxMockup.swift`, approved at the
//  batch-4 sitting (2026-07-30). The vocabulary comes from `NFC/JobBoxKit.swift`
//  and the Ambient primitives; the meter is the SHIPPED `JobBoxProgressMeter`,
//  embedded rather than redrawn.
//
//  WHAT THE CONVERSION CHANGED, and why each is in scope:
//    · ONE TITLE. The shell supplies a nav bar, the view sets `.navigationTitle`,
//      and the body ALSO drew a `largeTitle` Text of the same words — the title
//      rendered twice. The body's copy is gone.
//    · "FLAG FOR ATTENTION" IS REAL (operator ruling, batch-4 sitting). It always
//      wrote `flagged` / `flag_note` / `flagged_at` and none of those columns
//      existed, so PostgREST rejected the statement as a unit and no box has ever
//      been flagged. The columns are added by
//      `supabase/drafts/20260730_amb11_jobbox_flag_columns.sql`; the write now
//      PROVES a row matched (a zero-row PostgREST UPDATE returns 200 — the AMB.9
//      lesson), a flagged box READS as flagged on its row, and there is an unflag.
//    · THE DATE FILTER IS GONE. `selectedDate` was written by a DatePicker and
//      read by nothing — no query, no filter, no sort.
//    · ONE SELECTION COLOUR. The primary pills selected blue and the status pills
//      directly beneath them selected green.
//    · NO FIFTH COLOUR MAP. The row background painted its own packed-blue /
//      pickedUp-purple / leftJob-orange / turnedIn-green; the stage colour now
//      comes from the meter and the box badge, which every other job-box surface
//      also uses.
//    · THE 30-DAY WINDOW SAYS SO. Both queries are bounded at 30 days and nothing
//      said it, so a box last scanned five weeks ago read as "No job boxes found".
//    · THE CARD-NUMBER BRANCHES ARE GONE. `cardNumber` was hardcoded to "" on
//      every row this screen built, so the row pill, two sheet rows, both grouping
//      keys and one search leg were structurally unreachable.
//    · REAL STATES. Loading / empty / failure-with-retry / offline / missing-org-id
//      are distinct, and an error and an empty list never assert at once.
//
//  CLEARANCE: this is a SHELL-WRAPPED feature — `MainEmployeeView.featureContainer`
//  supplies the NavigationView and the tab-bar clearance, so this root adds only
//  its own `AmbientBackdrop` (D14: no tint).
//
//  THIS IS STILL A `List`, and that is load-bearing rather than a style choice:
//  `.swipeActions` are List-only — on a row inside a LazyVStack they compile,
//  render and silently do nothing. Edit and Flag are real swipe capabilities here,
//  so List's own chrome is stripped (hidden scroll background, clear row
//  backgrounds, no separators, insets by hand) and the wash shows through. Same
//  pattern as Class Groups (AMB.10) and Chat (AMB.6).

import SwiftUI
import Supabase

struct JobBoxWithEvent: Identifiable {
    let id: String
    let jobBox: JobBox
    let schoolName: String
    let date: Date
    let photographerName: String
    let jobboxNumber: String

    /// EVERY row this view fetched for this box, not just the latest one.
    ///
    /// The rows were always here — `processJobBoxRecords` groups them by box
    /// number and then throws the siblings away, keeping one summary row. That is
    /// why the old progress pills had to infer history from a single status and
    /// drew stages that were never scanned. Carrying the group costs nothing (no
    /// extra query) and lets the meter read what actually happened.
    var log: [JobBox] = []

    /// The rows of this box's CURRENT TRIP.
    ///
    /// The trip matters because this screen groups by box number across ALL TIME —
    /// correctly, since it answers "where is box 3028 now" and a box is a reused
    /// physical object. Without cutting at the last Packed scan, June's trip and
    /// October's would merge and report stages complete that belong to another job.
    ///
    /// THE CUT ITSELF IS `JobBoxProgressRules`', not a second copy of the rule: the
    /// reading performs it and this maps the boundary back onto the DATABASE ROWS,
    /// which is what the flag columns live on (`JobBoxScanPoint` deliberately does
    /// not carry them). A reading with no readable scan at all leaves every row in
    /// — there is no seam to cut on.
    var currentTripRows: [JobBox] {
        let rows = log.isEmpty ? [jobBox] : log
        guard let start = reading.scans.first?.at else { return rows }
        return rows.filter { $0.timestampDate >= start }
    }

    /// The progress reading for this box's CURRENT trip.
    var reading: JobBoxProgressReading {
        JobBoxProgressReading(rows: log.isEmpty ? [jobBox] : log)
    }

    /// True when this row is ONE RAW SCAN ROW rather than a grouped box.
    ///
    /// `processJobBoxRecords` short-circuits for a number search and returns the
    /// filtered rows verbatim, each carrying `log == []`. Every GROUPED row gets
    /// its log from `fullLogByKey[key]`, and that dictionary is built by grouping
    /// the same rows by the same key — so a key that exists always maps to at
    /// least one row and the fallback `boxes.map(\.jobBox)` is non-empty too.
    /// `log.isEmpty` is therefore exactly "came from the number-search
    /// short-circuit", which is what the flag controls are hidden on: flagging a
    /// raw row writes the flag onto a row outside the box's current trip, where
    /// grouped mode can neither read it nor clear it.
    var isRawScanRow: Bool { log.isEmpty }

    /// Whether a manager has flagged this box, and what they said.
    ///
    /// ANY flagged row of the current trip flags the box — the rule and the reason
    /// live in `JobBox/JobBoxFlagRules.swift`. Reading the latest row alone would
    /// clear the flag the moment a photographer scans the box, which is exactly
    /// the situation a flag exists to survive.
    var flagState: (flagged: Bool, note: String?, flaggedAt: Date?) {
        JobBoxFlagRules.flagReading(currentTripRows: currentTripRows)
    }

    // Computed property to determine if the job box is stalled
    var isStalled: Bool {
        let threshold = JobBoxSettingsManager.shared.getStalledThreshold(for: jobBox.jobBoxStatus)
        let thresholdDate = Date().addingTimeInterval(-threshold)
        return jobBox.timestampDate < thresholdDate && jobBox.jobBoxStatus != .turnedIn
    }

    /// One hoisted formatter, in `JobBoxFormat`. This used to allocate a
    /// `RelativeDateTimeFormatter` on every access and was read twice per row.
    var timeSinceUpdate: String {
        JobBoxFormat.elapsed(since: jobBox.timestamp)
    }
}

enum JobBoxFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case stalled = "Stalled"
    case today = "Today"
    case completed = "Completed"
}

enum JobBoxSort: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case schoolName = "School Name"
    case photographer = "Photographer"
    case jobboxNumber = "Job Box Number"
    case status = "Status"
}

enum JobBoxStatusFilter: String, CaseIterable {
    case all = "All Statuses"
    case packed = "Packed"
    case pickedUp = "Picked Up"
    case leftJob = "Left Job"
    case turnedIn = "Turned In"

    var correspondingStatus: JobBoxStatus? {
        switch self {
        case .all:
            return nil
        case .packed:
            return .packed
        case .pickedUp:
            return .pickedUp
        case .leftJob:
            return .leftJob
        case .turnedIn:
            return .turnedIn
        }
    }
}

/// `@MainActor` on the TYPE, not hops inside it (AMB.11 / N43). Three published
/// fields were mutated with no actor hop at all — latent only because every caller
/// happened to be on main. Annotating the class makes that a compiler guarantee and
/// deletes the `MainActor.run` blocks that were doing it by hand.
@MainActor
class ManagerJobBoxViewModel: ObservableObject {
    // NOTE (2026-07-29): the intermediate SupabaseJobBox struct was deleted here. It
    // duplicated JobBox and carried FIVE Firebase-era ghost fields (jobbox_number,
    // card_number, card_id, event_date, scanned_by) plus updated_at — none of which
    // exist on the live job_boxes table, so every one decoded nil on every row and the
    // fallback chains reading them were dead. Fetches decode [JobBox] directly; the scan
    // time is the `timestamp` column (see the note on JobBox.timestamp).

    @Published var allJobBoxes: [JobBoxWithEvent] = []
    @Published var selectedFilter: JobBoxFilter = .active
    @Published var selectedSort: JobBoxSort = .newestFirst
    @Published var selectedStatusFilter: JobBoxStatusFilter = .all
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""

    /// True while the field holds a number: typing `3028` lists every scan row for
    /// that box, typing `Lincoln` lists one row per box. Two list semantics behind
    /// one field — kept deliberately, it is how managers look a box up.
    private var isNumberSearch: Bool = false

    // Store organization ID
    private var organizationID: String = ""

    /// The in-flight fetch, so a retype CANCELS it rather than racing it. Without
    /// this the last request to complete won, which on a slow network is not the
    /// last one typed.
    private var loadTask: Task<Void, Never>?
    /// The keystroke debounce. The old screen fired a full network refetch on every
    /// single keystroke.
    private var debounceTask: Task<Void, Never>?

    private static let searchDebounce: UInt64 = 300_000_000 // 300ms

    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    init() {
        // Don't load job boxes until organization ID is set
    }

    func setOrganizationID(_ orgID: String) {
        self.organizationID = orgID
        guard !orgID.isEmpty else {
            // WAS A SILENT RETURN. The guard inside `loadJobBoxes` could never be
            // reached from `onAppear`, so a missing organization id rendered as
            // "No job boxes found" — the empty-state-hides-a-failure shape.
            isLoading = false
            errorMessage = "We couldn't tell which organization you belong to, so job boxes can't be loaded."
            return
        }
        loadJobBoxes()
    }

    /// Fire-and-forget reload for buttons and write completions.
    ///
    /// `isLoading` is raised HERE, synchronously, not inside the Task: the Task's
    /// body does not run until the next hop, and in that gap the view rendered the
    /// empty state — "No job boxes in the last 30 days" flashing before every
    /// first load.
    func loadJobBoxes() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = ""
        loadTask = Task { await self.reload() }
    }

    /// A DEBOUNCED reload for the search field, cancelling the pending one.
    func searchTextChanged() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.searchDebounce)
            guard !Task.isCancelled, let self else { return }
            self.loadJobBoxes()
        }
    }

    /// The load itself, awaitable — which is what `.refreshable` needs. It used to
    /// be handed a synchronous body that fired a detached Task, so the pull-to-
    /// refresh spinner retracted before any data arrived.
    ///
    /// - Parameter showingSpinner: pull-to-refresh passes `false`. It draws its own
    ///   spinner, and raising `isLoading` there would replace the list — the thing
    ///   being pulled — with the loading card mid-gesture.
    func reload(showingSpinner: Bool = true) async {
        guard !organizationID.isEmpty else {
            isLoading = false
            errorMessage = "We couldn't tell which organization you belong to, so job boxes can't be loaded."
            return
        }

        // There is NO job-box offline cache, so this is the honest thing to say.
        // Offline used to surface as a raw URLError string in red.
        guard OfflineDataManager.shared.isOnline else {
            isLoading = false
            errorMessage = Self.offlineMessage
            return
        }

        isLoading = showingSpinner
        errorMessage = ""

        // Check if we're searching by box number (numeric search)
        isNumberSearch = !searchText.isEmpty && searchText.rangeOfCharacter(from: .decimalDigits) != nil &&
            searchText.rangeOfCharacter(from: .letters) == nil

        // Query all job boxes
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        do {
            var jobBoxes: [JobBox]

            // Build query based on filters. The time filters run on `timestamp` —
            // the column that exists and that every scan writes. They used to run on
            // updated_at, which does not exist on job_boxes, so PostgREST rejected
            // the whole query and this screen errored on EVERY load (2026-07-29).
            if selectedFilter == .today && !isNumberSearch {
                let startOfDay = calendar.startOfDay(for: Date())
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

                jobBoxes = try await supabase
                    .from("job_boxes")
                    .select()
                    .eq("organization_id", value: organizationID)
                    .gte("timestamp", value: startOfDay.ISO8601Format())
                    .lt("timestamp", value: endOfDay.ISO8601Format())
                    .execute()
                    .value
            } else {
                jobBoxes = try await supabase
                    .from("job_boxes")
                    .select()
                    .eq("organization_id", value: organizationID)
                    .gte("timestamp", value: thirtyDaysAgo.ISO8601Format())
                    .execute()
                    .value
            }

            guard !Task.isCancelled else { return }
            processJobBoxRecords(jobBoxes)
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            errorMessage = OfflineDataManager.shared.isOnline
                ? "Error loading job boxes: \(error.localizedDescription)"
                : Self.offlineMessage
        }
    }

    static let offlineMessage = "You're offline — job boxes can't load without a connection."

    private func processJobBoxRecords(_ records: [JobBox]) {
        // This will hold all job boxes
        var allBoxes: [JobBoxWithEvent] = []

        // Process each record
        for jobBox in records {
            let schoolName = jobBox.school ?? "Unknown School"
            let jobboxNumber = jobBox.boxNumber
            let date = jobBox.timestamp ?? Date()
            let photographerName = jobBox.photographer.isEmpty ? "Unknown" : jobBox.photographer

            // Create JobBoxWithEvent object
            let jobBoxWithEvent = JobBoxWithEvent(
                id: jobBox.id,
                jobBox: jobBox,
                schoolName: schoolName,
                date: date,
                photographerName: photographerName,
                jobboxNumber: jobboxNumber
            )

            // Add to the array
            allBoxes.append(jobBoxWithEvent)
        }

        // A box's HISTORY is built from the unfiltered set, deliberately.
        //
        // The search filter runs over school / photographer / box number, and a
        // Packed row usually has NO photographer (NULL on 199 live rows, rendered
        // "Unknown"). Searching a photographer's name therefore drops that box's
        // Packed scan — and a meter fed the filtered rows would draw Packed as
        // "never scanned" purely because of what was typed in the search field.
        // The search decides which boxes are LISTED; it must not decide what
        // happened to them.
        //
        // The key is `box_number` plainly. It used to be
        // `cardNumber.isEmpty ? jobboxNumber : cardNumber` in two places, with
        // `cardNumber` hardcoded to "" — a branch that could never be taken.
        let fullLogByKey = Dictionary(grouping: allBoxes, by: \.jobboxNumber)
            .mapValues { $0.map(\.jobBox) }

        // First apply search filter to all boxes
        let filteredBoxes = filterJobBoxesBySearch(allBoxes)

        // If we're searching for a specific box number, show every scan row for it
        if isNumberSearch {
            allJobBoxes = sortJobBoxes(filteredBoxes)
            isLoading = false
            return
        }

        // Group by box number and get only the latest status for each
        let groupedBoxes = Dictionary(grouping: filteredBoxes, by: \.jobboxNumber)

        // For each group, get only the latest status
        var latestStatusBoxes: [JobBoxWithEvent] = []

        for (key, boxes) in groupedBoxes {
            // Sort by timestamp (newest first) and take only the first one —
            // but CARRY THE GROUP on it, so the row can draw the box's real
            // progress instead of inferring it from this one status.
            if let latestBox = boxes.sorted(by: { $0.jobBox.timestampDate > $1.jobBox.timestampDate }).first {
                var withLog = latestBox
                withLog.log = fullLogByKey[key] ?? boxes.map(\.jobBox)
                latestStatusBoxes.append(withLog)
            }
        }

        // IMPORTANT: Apply status filter AFTER determining the latest status
        // This ensures we only see boxes currently at a specific status
        if selectedStatusFilter != .all {
            if let status = selectedStatusFilter.correspondingStatus {
                latestStatusBoxes = latestStatusBoxes.filter { $0.jobBox.jobBoxStatus == status }
            }
        }

        // Process the 'stalled' filter separately
        if selectedFilter == .stalled {
            latestStatusBoxes = latestStatusBoxes.filter { $0.isStalled }
        }

        // Apply active/completed filter after getting the latest status
        if selectedFilter == .active {
            // For Active tab, filter out boxes whose most recent status is "turned in"
            latestStatusBoxes = latestStatusBoxes.filter { $0.jobBox.jobBoxStatus != .turnedIn }
        } else if selectedFilter == .completed {
            // For Completed tab, only show boxes whose most recent status is "turned in"
            latestStatusBoxes = latestStatusBoxes.filter { $0.jobBox.jobBoxStatus == .turnedIn }
        }

        // Apply sort
        allJobBoxes = sortJobBoxes(latestStatusBoxes)
        isLoading = false
    }

    // Filter job boxes based on search text
    func filterJobBoxesBySearch(_ jobBoxes: [JobBoxWithEvent]) -> [JobBoxWithEvent] {
        if searchText.isEmpty {
            return jobBoxes
        }

        let searchTextLower = searchText.lowercased()
        return jobBoxes.filter { jobBox in
            // If searching by box number (only digits), match only that
            if isNumberSearch {
                return jobBox.jobboxNumber.lowercased().contains(searchTextLower)
            } else {
                // Otherwise, search across all fields
                return jobBox.schoolName.lowercased().contains(searchTextLower) ||
                       jobBox.photographerName.lowercased().contains(searchTextLower) ||
                       jobBox.jobboxNumber.lowercased().contains(searchTextLower)
            }
        }
    }

    // Sort job boxes based on the selected sort option
    func sortJobBoxes(_ jobBoxes: [JobBoxWithEvent]) -> [JobBoxWithEvent] {
        switch selectedSort {
        case .newestFirst:
            return jobBoxes.sorted { $0.jobBox.timestampDate > $1.jobBox.timestampDate }

        case .oldestFirst:
            return jobBoxes.sorted { $0.jobBox.timestampDate < $1.jobBox.timestampDate }

        case .schoolName:
            return jobBoxes.sorted { $0.schoolName < $1.schoolName }

        case .photographer:
            return jobBoxes.sorted { $0.photographerName < $1.photographerName }

        case .jobboxNumber:
            return jobBoxes.sorted { $0.jobboxNumber < $1.jobboxNumber }

        case .status:
            return jobBoxes.sorted { statusPriority($0.jobBox.jobBoxStatus) < statusPriority($1.jobBox.jobBoxStatus) }
        }
    }

    // Helper function to determine status priority for sorting (optimized version)
    private func statusPriority(_ status: JobBoxStatus) -> Int {
        if status == .packed { return 0 }
        if status == .pickedUp { return 1 }
        if status == .leftJob { return 2 }
        return 3 // Must be .turnedIn
    }

    // Apply filters and sorting
    func applyFiltersAndSort() {
        loadJobBoxes()
    }

    // MARK: - Writes

    /// A zero-row PostgREST UPDATE returns 200 (AMB.9 shipped a critical this way),
    /// so every update here proves a row matched — the same `WrittenRowID` /
    /// `requireRowsWritten` shape as `DailyJobReportService` and `TimeTrackingService`.
    private struct WrittenRowID: Decodable { let id: String }

    enum WriteError: LocalizedError, CustomDebugStringConvertible {
        case noRowsMatched(id: String)
        case partialBatch(expected: Int, written: Int)

        var errorDescription: String? {
            switch self {
            case .noRowsMatched:
                return "Nothing was saved — this scan may have been changed elsewhere. Pull to refresh and try again."
            case .partialBatch(let expected, let written):
                return "Only \(written) of \(expected) rows were updated, so this box is still partly flagged. Pull to refresh and try again."
            }
        }

        var debugDescription: String {
            switch self {
            case .noRowsMatched(let id):
                return "WriteError.noRowsMatched: nothing in job_boxes matches id \(id)"
            case .partialBatch(let expected, let written):
                return "WriteError.partialBatch: expected \(expected) rows, server reported \(written)"
            }
        }
    }

    private func requireRowsWritten(_ rows: [WrittenRowID], id: String) throws {
        guard rows.isEmpty else { return }
        let error = WriteError.noRowsMatched(id: id)
        print("⚠️ \(error.debugDescription)")
        throw error
    }

    /// The BATCH proof — the first batch update in this repo, so it gets its own
    /// rule rather than reusing the single-row one. `requireRowsWritten(_:id:)`
    /// only asks whether ANY row matched, and for an `.in(...)` update that is
    /// not enough: a partial match (one id changed elsewhere, one row deleted)
    /// would report success while leaving the box flagged. Every id must come
    /// back.
    private func requireRowsWritten(_ rows: [WrittenRowID], ids: [String]) throws {
        guard rows.count != ids.count else { return }
        let error = WriteError.partialBatch(expected: ids.count, written: rows.count)
        print("⚠️ \(error.debugDescription) — ids \(ids.joined(separator: ","))")
        throw error
    }

    /// Record a scan. Returns the row THE SERVER STORED, or THROWS.
    ///
    /// It returns the row rather than a Bool because of the AMB.10 law: a screen
    /// mirrors what a write REPORTS and never reconstructs it locally. The edit
    /// sheet appends this observed row to its own log, so its checkmarks and
    /// progress card move because the database says so — not because a row was
    /// fabricated from the values that were sent.
    ///
    /// IT THROWS rather than setting `errorMessage` (audit round): the caller is
    /// a SHEET, `errorMessage` is the LIST's failure channel, and the sheet's own
    /// dismissal fires `loadJobBoxes()` — whose first act clears `errorMessage`.
    /// A write failure said nothing, anywhere. The sheet surfaces it in itself.
    func recordScan(jobBox: JobBoxWithEvent, newStatus: JobBoxStatus) async throws -> JobBox {
        // A correction is a new scan EVENT, not an edit (review round). Every
        // other writer on this shared table — the iOS NFC scan path and the web
        // app — INSERTs one row per status change and reads latest-by-timestamp,
        // and the crew push trigger fires on INSERT. The previous version
        // UPDATEd the latest row in place, which (a) falsified the original
        // scan's recorded moment and (b) made a manager's correction the one
        // status change the crew was never told about. (Before that it wrote
        // the nonexistent updated_at column and never worked at all.) Inserting
        // makes the correction the latest state everywhere — progression bar,
        // web modal, crew pushes — while the history stays true.
        let correctedBy = UserDefaults.standard.string(forKey: "userFirstName") ?? "Manager"
        let userId = UserManager.shared.getCurrentUserIDUnified()?.lowercased() ?? ""

        // A NEW id is MINTED here, so lowercase is right (the repo rule is
        // "mint lowercase, but filter with the case the column actually
        // stores" — the flag writes below use stored ids verbatim).
        var insertData: [String: AnyJSON] = [
            "id": .string(UUID().uuidString.lowercased()),
            "status": .string(newStatus.rawValue),
            "photographer": .string(correctedBy),
            "timestamp": .string(Date().ISO8601Format()),
            "organization_id": .string(jobBox.jobBox.organizationID)
        ]
        if !jobBox.jobBox.boxNumber.isEmpty {
            insertData["box_number"] = .string(jobBox.jobBox.boxNumber)
        }
        if !jobBox.jobBox.shiftUid.isEmpty {
            insertData["shift_uid"] = .string(jobBox.jobBox.shiftUid)
        }
        if let school = jobBox.jobBox.school, !school.isEmpty {
            insertData["school"] = .string(school)
        }
        if !jobBox.jobBox.schoolId.isEmpty {
            insertData["school_id"] = .string(jobBox.jobBox.schoolId)
        }
        if !userId.isEmpty {
            insertData["user_id"] = .string(userId)
        }

        // `.select().single()` reads the inserted row BACK. Same reason the
        // updates below prove a row matched: what the caller renders has to
        // come from the server's answer.
        let stored: JobBox = try await supabase
            .from("job_boxes")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        loadJobBoxes()
        return stored
    }

    /// Flag a job box for attention — the box's LATEST row carries the flag.
    ///
    /// Until `supabase/drafts/20260730_amb11_jobbox_flag_columns.sql` is applied
    /// this fails with an unknown-column error, which the FLAG SHEET surfaces in
    /// itself (audit round — see `recordScan` for why it is not `errorMessage`).
    /// That is the correct behaviour: the alternative is a control that reports
    /// success and does nothing, which is what this screen shipped for a year.
    func flagJobBox(jobBox: JobBoxWithEvent, note: String) async throws {
        let updateData: [String: AnyJSON] = [
            "flagged": .bool(true),
            "flag_note": .string(note),
            "flagged_at": .string(Date().ISO8601Format())
        ]

        // The id EXACTLY as stored — `job_boxes.id` is TEXT and PostgREST `.eq`
        // on a TEXT column is case-SENSITIVE, so lowercasing an id that was
        // minted uppercase matches nothing and returns 200.
        let rowId = jobBox.jobBox.id
        let written: [WrittenRowID] = try await supabase
            .from("job_boxes")
            .update(updateData)
            .eq("id", value: rowId)
            .select("id")
            .execute()
            .value
        try requireRowsWritten(written, id: rowId)

        loadJobBoxes()
    }

    /// Clear the flag from EVERY flagged row of this box's current trip.
    ///
    /// Every row, because the box reads as flagged when ANY of them is — clearing
    /// only the latest would leave the flag standing.
    func unflagJobBox(jobBox: JobBoxWithEvent) async throws {
        let ids = jobBox.currentTripRows.filter(\.flagged).map(\.id)
        guard !ids.isEmpty else { return }

        let updateData: [String: AnyJSON] = [
            "flagged": .bool(false),
            "flag_note": .null,
            "flagged_at": .null
        ]

        let written: [WrittenRowID] = try await supabase
            .from("job_boxes")
            .update(updateData)
            .in("id", values: ids)
            .select("id")
            .execute()
            .value
        // The BATCH proof: EVERY id must come back, not merely one of them.
        try requireRowsWritten(written, ids: ids)

        loadJobBoxes()
    }
}

// MARK: - The screen

struct ManagerJobBoxTrackerView: View {
    @StateObject private var viewModel = ManagerJobBoxViewModel()
    /// OBSERVED, not read (N-parity §1.13): the thresholds drive `isStalled` on
    /// every row, and this screen used to hold no observation at all, so a change
    /// only showed up because "Done" happened to reload.
    @ObservedObject private var stalledSettings = JobBoxSettingsManager.shared
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    /// ONE sheet state instead of three booleans plus an optional the sheet
    /// builders read through `if let` — that shape renders an empty sheet whenever
    /// the optional clears first.
    private enum TrackerSheet: Identifiable {
        case edit(JobBoxWithEvent)
        case flag(JobBoxWithEvent)
        case settings

        var id: String {
            switch self {
            case .edit(let box): return "edit-\(box.id)"
            case .flag(let box): return "flag-\(box.id)"
            case .settings: return "settings"
            }
        }
    }

    @State private var sheet: TrackerSheet?
    @State private var showStatusRow = false

    private var tint: Color { FeatureTheme.color(for: "jobBoxTracker") }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    JobBoxSearchField(placeholder: "Search schools, photographers or box #",
                                      text: $viewModel.searchText)
                        .onChange(of: viewModel.searchText) { _ in
                            viewModel.searchTextChanged()
                        }
                    filterRow
                    if showStatusRow { statusRow }
                    sortRow
                    windowNote
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                content
            }
        }
        .navigationTitle("Job Box Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet, onDismiss: {
            // Covers the settings sheet's thresholds (the stalled FILTER is applied
            // during the load, so observing the manager is not enough on its own)
            // and any write whose reload has already landed — the same reload the
            // old "Done" button fired.
            viewModel.loadJobBoxes()
        }) { sheet in
            switch sheet {
            case .edit(let box):
                JobBoxEditSheet(box: box, viewModel: viewModel)
            case .flag(let box):
                JobBoxFlagSheet(box: box, viewModel: viewModel)
            case .settings:
                JobBoxSettingsView()
            }
        }
        .onAppear {
            viewModel.setOrganizationID(storedUserOrganizationID)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // The count counts WHAT THE LIST SHOWS: groups after filtering, or —
            // in number-search mode — raw scan rows for that box. One field, two
            // list semantics; the count line follows whichever is on screen.
            AmbientSectionTitle("Job boxes", trailing: "\(viewModel.allJobBoxes.count) shown")
            Spacer(minLength: 8)

            Button { sheet = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
                    // ambient-allow: an icon control, not a container.
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stalled time settings")

            Button { viewModel.loadJobBoxes() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
                    // ambient-allow: an icon control, not a container.
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh")
        }
    }

    // MARK: - Filters

    private var filterRow: some View {
        AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(JobBoxFilter.allCases, id: \.self) { filter in
                JobBoxChip(text: filter.rawValue,
                           on: viewModel.selectedFilter == filter,
                           tint: tint) {
                    withAnimation(AmbientMotion.snappy) { viewModel.selectedFilter = filter }
                    viewModel.applyFiltersAndSort()
                }
            }
            JobBoxChip(text: showStatusRow ? "Status ▾" : "Status ▸",
                       on: showStatusRow,
                       tint: tint) {
                withAnimation(AmbientMotion.snappy) { showStatusRow.toggle() }
            }
        }
    }

    private var statusRow: some View {
        AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(JobBoxStatusFilter.allCases, id: \.self) { statusFilter in
                JobBoxChip(text: statusFilter.rawValue,
                           on: viewModel.selectedStatusFilter == statusFilter,
                           tint: tint) {
                    withAnimation(AmbientMotion.snappy) { viewModel.selectedStatusFilter = statusFilter }
                    viewModel.applyFiltersAndSort()
                }
            }
        }
    }

    /// The sort control sits with the chips. Its own `Picker` label never renders
    /// under `MenuPickerStyle`, so the visible word is a real `Text` and the
    /// picker's string is the accessibility label rather than dead furniture.
    private var sortRow: some View {
        HStack(spacing: 8) {
            Text("Sort")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Sort job boxes", selection: $viewModel.selectedSort) {
                ForEach(JobBoxSort.allCases, id: \.self) { sort in
                    Text(sort.rawValue).tag(sort)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            .font(.caption.weight(.semibold))
            .tint(tint)
            .onChange(of: viewModel.selectedSort) { _ in
                viewModel.applyFiltersAndSort()
            }

            Spacer(minLength: 0)
        }
    }

    private var windowNote: some View {
        AmbientNoteCard(
            title: "Showing the last 30 days",
            text: "Boxes last scanned more than 30 days ago are not fetched. A box you cannot find here may still exist — search its number to see every scan on it.",
            accent: tint,
            density: .compact)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            VStack {
                JobBoxLoadingCard(message: "Loading job boxes…")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        } else if !viewModel.errorMessage.isEmpty {
            // AN ERROR AND AN EMPTY LIST ARE DIFFERENT CLAIMS, and they used to
            // render at once — a red string above the words "No job boxes found".
            VStack {
                JobBoxFailureCard(message: viewModel.errorMessage) {
                    viewModel.loadJobBoxes()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        } else if viewModel.allJobBoxes.isEmpty {
            ScrollView {
                AmbientEmptyState(
                    title: "No job boxes in the last 30 days",
                    message: "Nothing matches this filter inside the window. Search a box number to look further back.",
                    systemImage: "shippingbox",
                    actionTitle: "Show all statuses",
                    actionIcon: "line.3.horizontal.decrease.circle",
                    action: {
                        viewModel.selectedFilter = .all
                        viewModel.selectedStatusFilter = .all
                        viewModel.applyFiltersAndSort()
                    },
                    actionTint: tint)
                .padding(.horizontal, 16)
            }
            .refreshable { await viewModel.reload(showingSpinner: false) }
        } else {
            jobBoxList
        }
    }

    private var jobBoxList: some View {
        List {
            ForEach(viewModel.allJobBoxes) { jobBox in
                Button {
                    sheet = .edit(jobBox)
                } label: {
                    JobBoxTrackerRow(box: jobBox)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(JobBoxTrackerListRow())
                .swipeActions {
                    Button {
                        sheet = .edit(jobBox)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)

                    // NO FLAG ON A RAW SCAN ROW (audit round). In number-search
                    // mode this list is one row per SCAN, not one per box, and
                    // those rows carry no log — flagging one writes the flag onto
                    // a row that may sit outside the box's current trip, where
                    // grouped mode can neither read it nor clear it. See
                    // `JobBoxWithEvent.isRawScanRow`.
                    if !jobBox.isRawScanRow {
                        Button {
                            sheet = .flag(jobBox)
                        } label: {
                            Label("Flag", systemImage: "flag")
                        }
                        .tint(.orange)
                    }
                }
                .contextMenu {
                    Button {
                        sheet = .edit(jobBox)
                    } label: {
                        Label("Edit Status", systemImage: "pencil")
                    }

                    if !jobBox.isRawScanRow {
                        Button {
                            sheet = .flag(jobBox)
                        } label: {
                            Label("Flag for Attention", systemImage: "flag")
                        }
                    }

                    Divider()

                    Text("Last Updated: \(jobBox.timeSinceUpdate)")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        // A properly async body: the spinner now retracts when the data lands, not
        // when a detached Task was created.
        .refreshable { await viewModel.reload(showingSpinner: false) }
    }

    // statusToStep / getStepColor / getStatusColor were DELETED here when this
    // screen adopted JobBoxProgressMeter. They were this file's private copy of
    // the shift detail's stepper logic, with a different colour map, and they were
    // the reason two screens described the same box differently. The stage
    // vocabulary and its colours now live in one place:
    // JobBox/JobBoxProgressRules.swift and JobBox/JobBoxProgressMeter.swift.
    //
    // `rowBackground` went the same way in AMB.11: a FIFTH colour map (packed blue
    // 5%, pickedUp purple 5%, leftJob orange 5%, turnedIn green 5%) painted behind
    // rows whose meter and badge already carry the stage colour.
}

private struct JobBoxTrackerListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: AmbientDensity.roomy.stackSpacing / 2,
                                      leading: 16,
                                      bottom: AmbientDensity.roomy.stackSpacing / 2,
                                      trailing: 16))
    }
}

// MARK: - The row

private struct JobBoxTrackerRow: View {
    let box: JobBoxWithEvent

    var body: some View {
        let reading = box.reading
        let flag = box.flagState

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(box.schoolName).font(AmbientDensity.compact.titleFont)
                Spacer(minLength: 8)
                // A STALLED BOX SAYS SO. Without this the "Stalled" filter's
                // results are indistinguishable from any other row and the whole
                // settings sheet configures something invisible (D12 — a feature
                // must not be lost to a conversion). `isStalled` is unchanged; only
                // its presentation moved into the badge vocabulary.
                if box.isStalled {
                    AmbientBadge(text: "Stalled", systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
                AmbientBadge(text: "Box \(box.jobboxNumber)", tint: reading.meterTint)
            }

            if flag.flagged {
                JobBoxFlagBadge(note: flag.note, flaggedAt: flag.flaggedAt)
            }

            HStack(spacing: 8) {
                Text(reading.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reading.meterTint)
                Text(reading.detailLine())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            JobBoxProgressMeter(reading: reading, compact: true)

            if let note = reading.skipNote {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
            if box.jobBox.shiftUid.isEmpty {
                Text("Not linked to a session — this box will not appear on a job's tracker.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

// MARK: - Edit sheet

private struct JobBoxEditSheet: View {
    let box: JobBoxWithEvent
    @ObservedObject var viewModel: ManagerJobBoxViewModel
    @Environment(\.dismiss) private var dismiss

    /// The success confirmation the screen never had: recording a scan just
    /// dismissed the sheet, with no toast, no haptic and nothing that said the one
    /// thing this sheet exists to do had happened.
    @State private var justRecorded = false

    /// The rows this sheet WATCHED the database store, appended to the box's log.
    ///
    /// AMB.10's law: mirror what the write REPORTS, never reconstruct it. These are
    /// the rows `recordScan` read back with `.select().single()` — not rows built
    /// from the values that were sent. Without them the sheet kept the snapshot it
    /// opened with, so recording a scan left its own checkmarks and progress card
    /// showing the state from before the tap.
    @State private var observedRows: [JobBox] = []

    /// One insert per stage at a time. A double-tap used to fire two inserts, and
    /// this table is append-only — both would be stored.
    @State private var inFlight: Set<Int> = []

    /// THE SHEET'S OWN FAILURE SURFACE (audit round). A failed insert used to be
    /// written to the view model's `errorMessage` — the LIST's channel, under
    /// this sheet — and the sheet's dismissal fires `loadJobBoxes()`, whose first
    /// act clears it. The tap reported nothing at all. Cleared on the next
    /// attempt.
    @State private var errorText: String?

    private var tint: Color { FeatureTheme.color(for: "jobBoxTracker") }

    /// The box's rows plus everything observed since the sheet opened.
    private var rows: [JobBox] {
        (box.log.isEmpty ? [box.jobBox] : box.log) + observedRows
    }

    private var reading: JobBoxProgressReading { JobBoxProgressReading(rows: rows) }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        JobBoxProgressCard(reading: reading, boxNumber: box.jobboxNumber)

                        AmbientFormSection(title: "Details", status: box.schoolName, statusTint: nil) {
                            VStack(alignment: .leading, spacing: 6) {
                                JobBoxStatLine(label: "Photographer",
                                               value: reading.latest?.who ?? "Not recorded")
                                JobBoxStatLine(label: "Last scan",
                                               value: JobBoxFormat.stamp(reading.latest?.at))
                                JobBoxStatLine(label: "Session",
                                               value: box.jobBox.shiftUid.isEmpty ? "Not linked" : "Linked")
                            }
                        }

                        AmbientFormSection(title: "Record a scan",
                                           status: justRecorded ? "Scan recorded" : "inserts a row",
                                           statusTint: justRecorded ? .green : .orange) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let errorText {
                                    AmbientNoteCard(title: "That scan wasn't saved",
                                                    text: errorText,
                                                    accent: .red,
                                                    density: .compact)
                                }

                                ForEach(JobBoxTripStage.allCases, id: \.rawValue) { stage in
                                    Button {
                                        record(stage)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: stage.meterIcon)
                                                .foregroundStyle(stage.meterTint)
                                                .frame(width: 22)
                                            Text(stage.label)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            Spacer(minLength: 0)
                                            if inFlight.contains(stage.rawValue) {
                                                ProgressView()
                                            } else if reading.state(stage) == .scanned {
                                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!inFlight.isEmpty)
                                }
                                // These INSERT a new scan row rather than updating one —
                                // deliberately: an update falsified the scan moment and
                                // skipped the crew push trigger. There is still NO
                                // transition validation, which is named in the parity
                                // contract and not changed here.
                                if justRecorded {
                                    Label("Scan recorded", systemImage: "checkmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Box \(box.jobboxNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func record(_ stage: JobBoxTripStage) {
        guard let status = JobBoxStatus(rawValue: stage.stored) else { return }
        // Append-only table: a second tap while the first insert is in flight
        // stores a second row. Every stage is disabled while any one is writing.
        guard inFlight.isEmpty else { return }
        // The retry clears the last failure — the card above must not outlive the
        // attempt it describes.
        errorText = nil
        inFlight.insert(stage.rawValue)

        Task {
            do {
                // The row the SERVER stored, not one built from what was sent.
                let stored = try await viewModel.recordScan(jobBox: box, newStatus: status)
                inFlight.remove(stage.rawValue)
                withAnimation(AmbientMotion.snappy) { observedRows.append(stored) }
                AmbientHaptics.impact(.medium)
                withAnimation(AmbientMotion.snappy) { justRecorded = true }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(AmbientMotion.gentle) { justRecorded = false }
            } catch {
                inFlight.remove(stage.rawValue)
                withAnimation(AmbientMotion.snappy) {
                    errorText = "Error updating job box: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Flag sheet

private struct JobBoxFlagSheet: View {
    let box: JobBoxWithEvent
    @ObservedObject var viewModel: ManagerJobBoxViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var note = ""

    /// THE SHEET'S OWN FAILURE SURFACE (audit round), for the same reason as the
    /// edit sheet's: a failed flag/unflag wrote to the LIST's `errorMessage`,
    /// which sits under this sheet and is cleared by the reload the sheet's own
    /// dismissal fires. The button simply did nothing, forever — and the flag
    /// columns may not exist on the database this build talks to, which is
    /// exactly the failure this has to be able to say out loud.
    @State private var errorText: String?

    /// The write in flight, so a slow save is not a dead button.
    @State private var isWriting = false

    private var flag: (flagged: Bool, note: String?, flaggedAt: Date?) { box.flagState }

    @ViewBuilder
    private var errorCard: some View {
        if let errorText {
            AmbientNoteCard(title: "That didn't save",
                            text: errorText,
                            accent: .red,
                            density: .compact)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AmbientFormSection(title: "Job box", status: box.schoolName, statusTint: nil) {
                            VStack(alignment: .leading, spacing: 6) {
                                JobBoxStatLine(label: "Box", value: box.jobboxNumber)
                                JobBoxStatLine(label: "Photographer",
                                               value: box.jobBox.photographer.isEmpty ? "Not recorded" : box.jobBox.photographer)
                                JobBoxStatLine(label: "Last scan",
                                               value: JobBoxFormat.stamp(box.jobBox.timestamp))
                                JobBoxStatLine(label: "Status", value: box.jobBox.jobBoxStatus.rawValue)
                            }
                        }

                        if flag.flagged {
                            flagged
                        } else {
                            unflagged
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(flag.flagged ? "Flagged Job Box" : "Flag Job Box")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    /// Already flagged: show what was said, and offer the way out. Without this the
    /// flag would be a one-way door.
    private var flagged: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientFormSection(title: "Flagged", status: JobBoxFormat.elapsed(since: flag.flaggedAt), statusTint: .red) {
                VStack(alignment: .leading, spacing: 6) {
                    JobBoxFlagBadge(note: flag.note, flaggedAt: flag.flaggedAt)
                }
            }

            errorCard

            Button {
                write("Error removing the flag") { try await viewModel.unflagJobBox(jobBox: box) }
            } label: {
                HStack(spacing: 8) {
                    if isWriting { ProgressView().tint(.white) }
                    Text(isWriting ? "Removing…" : "Remove Flag")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                // ambient-allow: a destructive control, not a container.
                .background(Capsule().fill(Color.red))
            }
            .buttonStyle(.plain)
            .disabled(isWriting)
        }
    }

    private var unflagged: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientFormSection(title: "Flag note", status: note.isEmpty ? "required" : "\(note.count)", statusTint: note.isEmpty ? .orange : nil) {
                TextEditor(text: $note)
                    .font(.subheadline)
                    .frame(height: 100)
            }

            errorCard

            Button {
                write("Error flagging job box") { try await viewModel.flagJobBox(jobBox: box, note: note) }
            } label: {
                HStack(spacing: 8) {
                    if isWriting { ProgressView().tint(.white) }
                    Text(isWriting ? "Flagging…" : "Flag for Attention")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                // ambient-allow: a destructive control, not a container.
                .background(Capsule().fill(note.isEmpty ? Color.red.opacity(0.35) : Color.red))
            }
            .buttonStyle(.plain)
            .disabled(isWriting || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// One write path for both buttons: clear the last failure, hold the
    /// in-flight state, dismiss on success, and SAY SO on failure instead of
    /// leaving a button that looks like it was never tapped.
    private func write(_ context: String, _ perform: @escaping () async throws -> Void) {
        guard !isWriting else { return }
        errorText = nil
        isWriting = true
        Task {
            do {
                try await perform()
                isWriting = false
                dismiss()
            } catch {
                isWriting = false
                withAnimation(AmbientMotion.snappy) {
                    errorText = "\(context): \(error.localizedDescription)"
                }
            }
        }
    }
}
