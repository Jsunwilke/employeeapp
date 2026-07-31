//  SearchView.swift
//  Iconik Employee — the job box / SD card search, converted (AMB.11)
//
//  Drawn from the approved `JobBoxLabSearchSurface`. Rendered BARE inside
//  `NFCContainerView`, which owns the one nav bar (title "Search") and the one
//  backdrop — this file adds neither.
//
//  THE DATA SEMANTICS ARE UNCHANGED, and they are unusual enough to be worth
//  stating rather than rediscovering (§1.6):
//    - a number search is an EXACT string match: "0301" and "301" are different
//      cards, and there is no partial or prefix match;
//    - photographer and school are exact and CASE-SENSITIVE `.eq` filters;
//    - a status search is done CLIENT-SIDE over every row in the org — it
//      answers "currently at status X", not "was ever at X";
//    - the unsearched list is the most recent 50, sorted after pulling
//      everything.
//  None of that changed here. This is a design phase (D12).
//
//  WHAT CHANGED
//    - the second segmented picker became field CHIPS in an `AmbientFlowLayout`,
//      and the field list is now per-mode;
//    - the SD-card "Photographer" field is DROPPED (operator-approved, §0.26):
//      it issues `.eq("photographer", …)` against a column the `records` table
//      does not have, so it can never return a row. Job-box photographer search
//      is a real column and stays;
//    - a real EMPTY state, a real FAILED state with a retry, and a loading state
//      for the initial fetch and the search (findings N12, N10-shaped);
//    - errors no longer share the `"Info"` alert title with successes (N59). A
//      successful delete is now the row leaving, with no alert at all; only a
//      FAILED delete raises one, titled "Error";
//    - `initialStatus` is applied in `init` and searched explicitly, instead of
//      a 0.1s `asyncAfter` and a flag existing to suppress the `.onChange`
//      cascade it triggered (N41);
//    - the two delete paths and the two confirm paths are one each (N63);
//    - the status option lists come from `NFCRoutingRules` rather than being a
//      fourth hardcoded copy;
//    - listener teardown on disappear (N24), generation-guarded so it cannot
//      unsubscribe the channels the NEXT screen just subscribed.

import SwiftUI

struct SearchView: View {
    /// Set when Statistics (or the Scan screen's alert banner) routes in
    /// pre-filtered. Applied in `init`, searched in `onAppear`.
    let initialStatus: String?

    @State private var isJobBoxMode: Bool
    @State private var searchField: String
    @State private var searchValue: String

    @State private var searchResults: [NFCRecord] = []
    @State private var jobBoxSearchResults: [JobBox] = []

    @State private var isSearching = false
    @State private var isLoadingInitial = false
    /// The failed state. Holds the sentence shown on the failure card.
    @State private var failureMessage: String?
    /// Whether the list on screen is a search result rather than the recent-50.
    @State private var hasSearched = false
    @State private var statusSearchPerformed = false

    /// THE ORDERING TOKEN (audit round). Every fetch here is callback-based and
    /// nothing cancelled or sequenced them, so on a slow network the LAST
    /// request to come back won — not the last one asked for. A search landing
    /// after a chip tap repopulated a list the user had just changed the field
    /// of, and a stale FAILURE hid a perfectly good list behind a failure card.
    /// Each intent takes a new generation; a callback publishes nothing unless
    /// its generation is still the current one.
    @State private var searchGeneration = 0

    /// Set when a field chip is tapped: the results were cleared and no query
    /// has been run yet, so the empty state must not claim the organization has
    /// no scans.
    @State private var awaitingQuery = false

    @State private var showAlert = false
    @State private var alertTitle = "Info"
    @State private var alertMessage = ""

    // For schools and photographers
    @State private var schools: [SchoolItem] = []
    @State private var photographerNames: [String] = []
    /// The dropdown-listener subscription this view established. See
    /// `DatabaseManager.stopListening(ifGeneration:)`.
    @State private var listenerGeneration = 0

    // For custom confirmation dialog
    @State private var showConfirmationDialog = false
    @State private var confirmationConfig = AlertConfiguration(
        title: "",
        message: "",
        primaryButtonTitle: "",
        secondaryButtonTitle: nil,
        isDestructive: false,
        primaryAction: {},
        secondaryAction: nil
    )

    // For network status indicator
    @ObservedObject private var offlineManager = OfflineDataManager.shared
    @ObservedObject private var userManager = UserManager.shared

    init(initialStatus: String? = nil, initialIsJobBoxMode: Bool = false) {
        self.initialStatus = initialStatus
        _isJobBoxMode = State(initialValue: initialIsJobBoxMode)
        _searchField = State(initialValue: initialStatus == nil ? "cardNumber" : "status")
        _searchValue = State(initialValue: initialStatus ?? "")
    }

    // MARK: - Vocabulary

    /// The SD statuses offered by the picker: the lifecycle ring plus the two
    /// side states. "Personal" has zero live rows and is deliberately KEPT — it
    /// is offered today and dropping it is not an approved change.
    private var sdStatuses: [String] {
        NFCRoutingRules.sdStatusRing + NFCRoutingRules.sdSideStatuses
    }

    private var jobBoxStatuses: [String] { NFCRoutingRules.jobBoxStatusRing }

    /// The searchable fields, in the mockup's order. `key` is the wire field the
    /// data layer takes; `label` is what the chip says.
    private var fields: [(key: String, label: String)] {
        if isJobBoxMode {
            return [("cardNumber", "Box #"),
                    ("photographer", "Photographer"),
                    ("school", "School"),
                    ("status", "Status")]
        }
        return [("cardNumber", "Card #"),
                ("school", "School"),
                ("status", "Status")]
    }

    private var tint: Color { FeatureTheme.color(for: "scan") }

    private var resultCount: Int {
        isJobBoxMode ? jobBoxSearchResults.count : searchResults.count
    }

    private var isBusy: Bool { isSearching || isLoadingInitial }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                controls
                resultsList
            }

            // Custom confirmation dialog
            ConfirmationDialogView(isPresented: $showConfirmationDialog, config: confirmationConfig)
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle),
                  message: Text(alertMessage),
                  dismissButton: .default(Text("OK")))
        }
        .onAppear {
            loadDropdowns()
            if initialStatus != nil {
                performSearch()
            } else {
                fetchInitialRecords()
            }
        }
        .onDisappear {
            DatabaseManager.shared.stopListening(ifGeneration: listenerGeneration)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !offlineManager.isOnline {
                offlineBanner
            }

            Picker("Search Type", selection: $isJobBoxMode) {
                Text("Job Boxes").tag(true)
                Text("SD Cards").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: isJobBoxMode) { _ in modeChanged() }

            AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(fields, id: \.key) { field in
                    JobBoxChip(text: field.label,
                               on: searchField == field.key,
                               tint: tint) {
                        select(field: field.key)
                    }
                }
            }

            queryInput

            searchButton

            if searchField == "status" && statusSearchPerformed {
                Text(countLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private var offlineBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.white)
            Text("Offline Mode")
                .foregroundStyle(.white)
                .font(.subheadline)
            if offlineManager.syncPending {
                Text("• Sync Pending")
                    .foregroundStyle(.yellow)
                    .font(.subheadline)
            }
        }
        .ambientCard(density: .compact, fill: .tint(Color.red.opacity(0.8)), fillWidth: true)
    }

    @ViewBuilder
    private var queryInput: some View {
        switch searchField {
        case "cardNumber":
            JobBoxSearchField(placeholder: isJobBoxMode ? "Enter Box Number" : "Enter Card Number",
                              text: $searchValue,
                              keyboard: .numberPad)
        case "photographer":
            DropdownSearchField(
                placeholder: "Select Photographer",
                selectedText: searchValue,
                options: photographerNames,
                onSelect: { selected in searchValue = selected }
            )
        case "school":
            DropdownSearchField(
                placeholder: "Select School",
                selectedText: searchValue,
                options: schools.map { $0.name }.sorted(),
                onSelect: { selected in searchValue = selected }
            )
        default:
            DropdownSearchField(
                placeholder: "Select Status",
                selectedText: searchValue,
                options: isJobBoxMode ? jobBoxStatuses : sdStatuses,
                onSelect: { selected in searchValue = selected }
            )
        }
    }

    private var searchButton: some View {
        Button(action: performSearch) {
            HStack(spacing: 8) {
                if isSearching {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
                Text(isSearching ? "Searching..." : "Search")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            // ambient-allow: the submit control, not a container.
            .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
        .disabled(isSearching)
    }

    private var countLine: String {
        if isJobBoxMode {
            return "\(jobBoxSearchResults.count) \(jobBoxSearchResults.count == 1 ? "job box" : "job boxes") in \(searchValue) status"
        }
        return "\(searchResults.count) \(searchResults.count == 1 ? "card" : "cards") in \(searchValue) status"
    }

    // MARK: - Results
    //
    // THIS IS A `List`, AND THAT IS LOAD-BEARING. `.swipeActions` is a List-only
    // modifier — on a row inside a `LazyVStack` it silently does nothing. So the
    // List stays and its chrome is stripped instead, the same recipe the chat
    // conversion uses, and the cards supply all the spacing.

    private var resultsList: some View {
        List {
            if let failureMessage {
                JobBoxFailureCard(message: failureMessage, retry: retry)
                    .modifier(SearchListRow())
            } else if isBusy {
                JobBoxLoadingCard(message: isSearching ? "Searching…" : "Loading recent scans…")
                    .modifier(SearchListRow())
            } else if resultCount == 0 {
                emptyState.modifier(SearchListRow())
            } else {
                AmbientSectionTitle(isJobBoxMode ? "Job boxes" : "SD cards",
                                    trailing: "\(resultCount)")
                    .modifier(SearchListRow())

                if isJobBoxMode {
                    ForEach(jobBoxSearchResults) { record in
                        JobBoxBubbleView(record: record)
                            .modifier(SearchListRow())
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    confirmDelete(subject: "job box #\(record.boxNumber)",
                                                  recordID: record.id,
                                                  isJobBox: true)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } else {
                    ForEach(searchResults) { record in
                        RecordBubbleView(record: record)
                            .modifier(SearchListRow())
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    confirmDelete(subject: "card #\(record.cardNumber)",
                                                  recordID: record.id,
                                                  isJobBox: false)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        // A PROPERLY ASYNC BODY (audit round): this used to fire a callback-based
        // fetch and return immediately, so the spinner retracted before any data
        // arrived — the same defect the manager tracker's `.refreshable` was
        // fixed for. It now awaits the fetch it started.
        .refreshable { await refresh() }
    }

    /// The pull-to-refresh body. Bridges the callback fetches to `async` by
    /// resuming when the one it started settles.
    private func refresh() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if searchValue.isEmpty {
                fetchInitialRecords { continuation.resume() }
            } else {
                performSearch { continuation.resume() }
            }
        }
    }

    /// The state that did not exist: an empty result used to be a blank `List`
    /// plus a modal alert saying "No records found." that had to be dismissed
    /// before the query could be edited (finding N12).
    @ViewBuilder
    private var emptyState: some View {
        if awaitingQuery {
            // Switching fields no longer pulls the whole table, so this state is
            // "nothing has been asked yet" — which must not be dressed up as
            // "this organization has no scans".
            AmbientEmptyState(
                title: "Ready to search",
                message: "Pick a value above and tap Search.",
                systemImage: "magnifyingglass")
        } else {
            AmbientEmptyState(
                title: isJobBoxMode ? "No boxes match" : "No cards match",
                message: emptyMessage,
                systemImage: "magnifyingglass")
        }
    }

    private var emptyMessage: String {
        guard hasSearched, !searchValue.isEmpty else {
            return isJobBoxMode
                ? "No job box scans in this organization yet."
                : "No card scans in this organization yet."
        }
        if searchField == "status" {
            return "Nothing in this organization is currently at “\(searchValue)”. A status search reads where each \(isJobBoxMode ? "box" : "card") is NOW, not where it has been."
        }
        return isJobBoxMode
            ? "Nothing in this organization matches “\(searchValue)”. Box numbers match exactly — a leading zero counts."
            : "Nothing in this organization matches “\(searchValue)”. Card numbers match exactly — a leading zero counts."
    }

    // MARK: - Control actions

    private func select(field key: String) {
        guard searchField != key else { return }
        withAnimation(AmbientMotion.snappy) { searchField = key }
        searchValue = ""
        statusSearchPerformed = false
        hasSearched = false
        failureMessage = nil
        searchResults = []
        jobBoxSearchResults = []
        // NO REFETCH (audit round). Changing which FIELD you are about to search
        // does not change the recent-50, and this pulled every row in the
        // organization — client-side — on each of the three or four chips. The
        // list is cleared and the next Search fills it; `modeChanged` keeps its
        // refetch, because the other mode reads a different table.
        awaitingQuery = true
        invalidateInFlight()
    }

    private func modeChanged() {
        searchValue = ""
        searchField = "cardNumber"
        statusSearchPerformed = false
        hasSearched = false
        failureMessage = nil
        searchResults = []
        jobBoxSearchResults = []
        awaitingQuery = false
        fetchInitialRecords()
    }

    private func retry() {
        failureMessage = nil
        if searchValue.isEmpty {
            fetchInitialRecords()
        } else {
            performSearch()
        }
    }

    /// Take the next generation, so anything already in flight publishes
    /// nothing when it lands.
    @discardableResult
    private func beginRequest() -> Int {
        searchGeneration += 1
        return searchGeneration
    }

    /// Abandon whatever is in flight WITHOUT starting a new fetch — the busy
    /// flags have to be dropped here, because the callback that would have
    /// cleared them is now a no-op.
    private func invalidateInFlight() {
        beginRequest()
        isSearching = false
        isLoadingInitial = false
    }

    // MARK: - Loading

    /// The one sentence for "there is no organization id", shared by the three
    /// paths that used to return silently — the same shape (and the same words)
    /// as the manager tracker's.
    private static let missingOrgMessage =
        "We couldn't tell which organization you belong to, so scans can't be loaded."

    private func loadDropdowns() {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            // WAS A SILENT RETURN (audit round): the school and photographer
            // dropdowns simply had no options and nothing said why.
            failureMessage = Self.missingOrgMessage
            return
        }

        // Load cached photographer names
        if let data = UserDefaults.standard.data(forKey: "photographerNames"),
           let cachedNames = try? JSONDecoder().decode([String].self, from: data) {
            self.photographerNames = cachedNames
        }
        DatabaseManager.shared.listenForPhotographers(inOrgID: orgID) { names in
            self.photographerNames = names
        }

        // Load cached dropdown data for schools
        if let data = UserDefaults.standard.data(forKey: "nfcSchools"),
           let cachedSchools = try? JSONDecoder().decode([SchoolItem].self, from: data) {
            self.schools = cachedSchools
        }
        DatabaseManager.shared.listenForSchoolsData(forOrgID: orgID) { schoolItems in
            self.schools = schoolItems
        }

        listenerGeneration = DatabaseManager.shared.currentNFCListenerGeneration
    }

    /// The unsearched list: the most recent 50, sorted client-side after pulling
    /// everything — the data layer applies neither `.limit()` nor `.order()`.
    private func fetchInitialRecords(then finished: (() -> Void)? = nil) {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            // WAS A SILENT RETURN (audit round): an empty list that read as "this
            // organization has no scans".
            failureMessage = Self.missingOrgMessage
            finished?()
            return
        }

        let generation = beginRequest()
        awaitingQuery = false
        isLoadingInitial = true
        failureMessage = nil

        if isJobBoxMode {
            DatabaseManager.shared.fetchJobBoxRecords(field: "all", value: "", organizationID: orgID) { result in
                guard generation == searchGeneration else { finished?(); return }
                isLoadingInitial = false
                switch result {
                case .success(let records):
                    let sortedRecords = records.sorted { $0.timestampDate > $1.timestampDate }
                    jobBoxSearchResults = Array(sortedRecords.prefix(50))
                case .failure(let error):
                    failureMessage = "Error fetching job box records: \(error.localizedDescription)"
                }
                finished?()
            }
        } else {
            DatabaseManager.shared.fetchRecords(field: "all", value: "", organizationID: orgID) { result in
                guard generation == searchGeneration else { finished?(); return }
                isLoadingInitial = false
                switch result {
                case .success(let records):
                    let sortedRecords = records.sorted { $0.timestamp > $1.timestamp }
                    searchResults = Array(sortedRecords.prefix(50))
                case .failure(let error):
                    failureMessage = "Error fetching records: \(error.localizedDescription)"
                }
                finished?()
            }
        }
    }

    // MARK: - Searching

    func performSearch() { performSearch(then: nil) }

    func performSearch(then finished: (() -> Void)?) {
        UIApplication.shared.endEditing()

        guard !searchValue.isEmpty else {
            alertTitle = "Info"
            alertMessage = "Please enter/select a value to search."
            showAlert = true
            finished?()
            return
        }

        // Split out of the guard above (audit round): a missing organization id
        // is not the user forgetting to type something, and telling them to
        // enter a value could never fix it.
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            failureMessage = Self.missingOrgMessage
            finished?()
            return
        }

        let generation = beginRequest()
        awaitingQuery = false
        isSearching = true
        failureMessage = nil
        hasSearched = true

        if isJobBoxMode {
            performJobBoxSearch(orgID: orgID, generation: generation, finished: finished)
        } else {
            performSDCardSearch(orgID: orgID, generation: generation, finished: finished)
        }
    }

    private func performSDCardSearch(orgID: String, generation: Int, finished: (() -> Void)?) {
        if searchField.lowercased() == "status" {
            statusSearchPerformed = true
            DatabaseManager.shared.fetchRecords(field: "all", value: "", organizationID: orgID) { result in
                guard generation == searchGeneration else { finished?(); return }
                isSearching = false
                switch result {
                case .success(let records):
                    let latestRecordsDict = Dictionary(grouping: records, by: { $0.cardNumber })
                        .compactMapValues { recs in
                            recs.sorted { $0.timestamp > $1.timestamp }.first
                        }
                    let filteredRecords = latestRecordsDict.values.filter {
                        $0.status.lowercased() == searchValue.lowercased()
                    }
                    searchResults = filteredRecords.sorted { $0.timestamp > $1.timestamp }
                case .failure(let error):
                    failureMessage = "Error fetching records: \(error.localizedDescription)"
                }
                finished?()
            }
        } else {
            DatabaseManager.shared.fetchRecords(field: searchField, value: searchValue, organizationID: orgID) { result in
                guard generation == searchGeneration else { finished?(); return }
                isSearching = false
                switch result {
                case .success(let records):
                    searchResults = records.sorted { $0.timestamp > $1.timestamp }
                case .failure(let error):
                    failureMessage = "Error fetching records: \(error.localizedDescription)"
                }
                finished?()
            }
        }
    }

    private func performJobBoxSearch(orgID: String, generation: Int, finished: (() -> Void)?) {
        let fieldToSearch = searchField == "cardNumber" ? "boxNumber" : searchField

        if fieldToSearch.lowercased() == "status" {
            statusSearchPerformed = true
            DatabaseManager.shared.fetchJobBoxRecords(field: "all", value: "", organizationID: orgID) { result in
                guard generation == searchGeneration else { finished?(); return }
                isSearching = false
                switch result {
                case .success(let records):
                    let latestRecordsDict = Dictionary(grouping: records, by: { $0.boxNumber })
                        .compactMapValues { recs in
                            recs.sorted { $0.timestampDate > $1.timestampDate }.first
                        }
                    let filteredRecords = latestRecordsDict.values.filter { record in
                        record.status.lowercased() == searchValue.lowercased()
                    }
                    jobBoxSearchResults = filteredRecords.sorted { $0.timestampDate > $1.timestampDate }
                case .failure(let error):
                    failureMessage = "Error fetching job box records: \(error.localizedDescription)"
                }
                finished?()
            }
        } else {
            DatabaseManager.shared.fetchJobBoxRecords(field: fieldToSearch, value: searchValue, organizationID: orgID) { result in
                guard generation == searchGeneration else { finished?(); return }
                isSearching = false
                switch result {
                case .success(let records):
                    jobBoxSearchResults = records.sorted { $0.timestampDate > $1.timestampDate }
                case .failure(let error):
                    failureMessage = "Error fetching job box records: \(error.localizedDescription)"
                }
                finished?()
            }
        }
    }

    // MARK: - Deleting
    //
    // ONE confirm path and ONE delete path (finding N63); the two flavours
    // differ only in which table and which noun. The success ALERT is gone: the
    // row leaving is the confirmation, and the count line above the list is
    // computed from the array, so it can no longer go stale (N47). A FAILED
    // delete keeps the row and says so, under an "Error" title rather than the
    // "Info" one successes used to share (N59).

    private func confirmDelete(subject: String, recordID: String, isJobBox: Bool) {
        confirmationConfig = AlertConfiguration(
            title: "Confirm Deletion",
            message: "Are you sure you want to delete the record for \(subject)? This action cannot be undone.",
            primaryButtonTitle: "Delete",
            secondaryButtonTitle: "Cancel",
            isDestructive: true,
            primaryAction: {
                delete(recordID: recordID, isJobBox: isJobBox)
            },
            secondaryAction: {
                // Cancel action
            }
        )

        showConfirmationDialog = true
    }

    private func delete(recordID: String, isJobBox: Bool) {
        if isJobBox {
            DatabaseManager.shared.deleteJobBoxRecord(recordID: recordID) { result in
                switch result {
                case .success:
                    jobBoxSearchResults.removeAll { $0.id == recordID }
                case .failure(let error):
                    presentError("Failed to delete job box record: \(error.localizedDescription)")
                }
            }
        } else {
            DatabaseManager.shared.deleteRecord(recordID: recordID) { result in
                switch result {
                case .success:
                    searchResults.removeAll { $0.id == recordID }
                case .failure(let error):
                    presentError("Failed to delete record: \(error.localizedDescription)")
                }
            }
        }
    }

    private func presentError(_ message: String) {
        alertTitle = "Error"
        alertMessage = message
        showAlert = true
    }
}

/// Strips a List row back to nothing so the shell's wash shows through and the
/// cards supply all the spacing — while keeping the row a real List row, which
/// is what keeps `.swipeActions` alive.
private struct SearchListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: AmbientDensity.compact.stackSpacing / 2,
                                      leading: 16,
                                      bottom: AmbientDensity.compact.stackSpacing / 2,
                                      trailing: 16))
    }
}

// Helper extension
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
