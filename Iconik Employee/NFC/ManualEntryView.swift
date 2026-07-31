//  ManualEntryView.swift
//  Iconik Employee — recording a box or a card by number, with no tag
//
//  AMB.11 conversion. EVERY business rule is preserved (D12); where a rule was
//  written out longhand it now comes from `NFC/NFCRoutingRules.swift`, using the
//  `.form` variant — which, unlike the scan screen's, gives "Camera Bag" and
//  "Personal" explicit landings. That difference is deliberate and is modelled
//  rather than unified (see the rules file).
//
//  WHAT CHANGED ON SCREEN, from the operator-approved `JobBoxMockup` Manual
//  surface: `Form` becomes `AmbientFormSection`s over the feature wash, the
//  action row becomes two capsules, and the nested `NavigationView` is gone — the
//  container owns the one bar and titles it "Manual Entry".
//
//  APPROVED ADDITIONS (each was PROPOSED in the mockup and approved with it):
//    - a visible session LOADING state and a surfaced session-load FAILURE with a
//      retry. The session control is the one thing that links a box to a job, and
//      "still loading", "no sessions" and "the fetch failed" were all drawn as
//      the same nothing — the failure was a `print` (N30);
//    - a Submit IN-FLIGHT state. Submit only greyed;
//    - the form CLEARS after a successful save (N35). It did not, so a second
//      Submit re-inserted the same values.
//
//  Fixed in passing: N34 (`refreshSchoolsAsync` busy-waited on a `@State` Bool —
//  it now awaits the refresh itself), N61 (`selectedStatus = isJobBoxMode ? "" : ""`),
//  N62 (`onCancel` was optional with an unreachable `dismiss()` fallback; the sole
//  call site is `NFCContainerView`, so it is required).

import SwiftUI

struct ManualEntryView: View {
    @State private var cardNumber: String = ""
    @State private var selectedSchool: String = ""
    @State private var selectedStatus: String = ""
    @State private var isJobBoxMode: Bool = false

    /// N62. Required — `NFCContainerView` is the only call site and always
    /// supplies it, so the `dismiss()` fallback it used to carry was dead.
    var onCancel: () -> Void

    let localStatuses: [String] = ["Job Box", "Camera", "Envelope", "Uploaded", "Cleared", "Camera Bag", "Personal"]
    let jobBoxStatuses = NFCRoutingRules.jobBoxStatusRing

    @State private var schools: [SchoolItem] = []
    @State private var photographerNames: [String] = []
    @State private var isRefreshing = false
    /// The dropdown-listener subscription this view established. See
    /// `DatabaseManager.stopListening(ifGeneration:)`.
    @State private var listenerGeneration = 0

    @State private var localPhotographer: String = ""
    @State private var uploadedFromJasonsHouse: Bool = false
    @State private var uploadedFromAndysHouse: Bool = false

    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    /// Consumed by the card-number `onChange` so the post-save clear's final
    /// state survives it. See `clearFormAfterSave`.
    @State private var isClearingAfterSave = false
    @State private var lastRecord: NFCRecord? = nil
    @State private var lastJobBoxRecord: JobBox? = nil

    // Pickup mismatch check (JobBoxPickupRules): set when Submit finds the
    // entered box doesn't match what was packed for the chosen job.
    @State private var pickupWarning: JobBoxPickupWarning? = nil
    @State private var showPickupWarning = false
    @State private var pendingPickupSchoolId: String? = nil

    // For session selection
    @State private var selectedSession: Session? = nil
    @State private var showSessionSelection = false
    @State private var availableSessions: [Session] = []
    /// The two states the session control never had.
    @State private var sessionsLoading = false
    @State private var sessionsLoadFailed = false

    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var timeTrackingService = TimeTrackingService.shared
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""

    private var tint: Color { FeatureTheme.color(for: "scan") }

    private var numberIsValid: Bool { cardNumber.count == 4 && Int(cardNumber) != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                numberSection

                photographerSection

                if numberIsValid {
                    if isJobBoxMode { sessionSection }
                    additionalSection
                } else {
                    Text("Enter a valid 4-digit \(isJobBoxMode ? "box" : "card") number to load additional information.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actionRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: refreshSchools) {
                    if isRefreshing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh schools")
            }
        }
        .refreshable {
            await refreshSchoolsAsync()
        }
        // ONE ALERT API on this view (audit round — the AMB.10 mixed-presentation
        // class). This was the deprecated `Alert(...)` initializer stacked on the
        // modern `alert(_:isPresented:)` below it; every string is unchanged.
        .alert("Info", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert(
            pickupWarning?.title ?? "",
            isPresented: $showPickupWarning,
            presenting: pickupWarning
        ) { warning in
            Button(warning.confirmLabel, role: .destructive) {
                isSubmitting = true
                submitJobBoxData(boxNumber: cardNumber, schoolId: pendingPickupSchoolId)
            }
            Button("Go Back", role: .cancel) {}
        } message: { warning in
            Text(warning.message)
        }
        .sheet(isPresented: $showSessionSelection) {
            NFCSessionSelectionView(
                sessions: availableSessions,
                selectedSession: $selectedSession,
                isPresented: $showSessionSelection,
                isLoading: sessionsLoading,
                loadFailed: sessionsLoadFailed,
                onRetry: { loadAvailableSessionsForJobBox() }
            )
        }
        .onAppear {
            localPhotographer = storedUserFirstName
            loadInitialData()
        }
        // LISTENER TOKEN SYMMETRY (audit round). This view subscribes the shared
        // photographer/school channels on every appear and never handed them
        // back, so the generation token modelled a teardown that never happened.
        // Generation-guarded like `SearchView`: a teardown for a generation that
        // is no longer current is a no-op, so leaving this tab cannot kill the
        // channels the ARRIVING tab has just subscribed.
        .onDisappear {
            DatabaseManager.shared.stopListening(ifGeneration: listenerGeneration)
        }
    }

    // MARK: - Sections

    private var numberSection: some View {
        AmbientFormSection(title: isJobBoxMode ? "Job box information" : "Card information",
                           status: numberIsValid ? cardNumber : "4 digits",
                           statusTint: numberIsValid ? nil : .orange) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Entry Type", selection: $isJobBoxMode) {
                    Text("SD Card").tag(false)
                    Text("Job Box").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: isJobBoxMode) { newValue in
                    // Reset form when switching modes
                    cardNumber = ""
                    selectedStatus = newValue ? "Packed" : ""
                    lastRecord = nil
                    lastJobBoxRecord = nil
                    selectedSession = nil

                    // Load available sessions if switching to job box mode
                    if newValue {
                        loadAvailableSessionsForJobBox()
                        // Ensure schools are loaded
                        if schools.isEmpty {
                            loadInitialData()
                        }
                    }
                }

                TextField(isJobBoxMode ? "Enter 4-digit Box Number (3001+)" : "Enter 4-digit Card Number",
                          text: $cardNumber)
                    .font(.subheadline)
                    .keyboardType(.numberPad)
                    .onChange(of: cardNumber) { newValue in
                        // The post-save clear owns the form's final state; this
                        // must not overwrite it. Consumed once, whatever the new
                        // value is, so the flag can never survive to swallow a
                        // real edit.
                        if isClearingAfterSave {
                            isClearingAfterSave = false
                            return
                        }
                        if newValue.count == 4, Int(newValue) != nil {
                            if isJobBoxMode {
                                fetchLastJobBoxRecord(for: newValue)
                            } else {
                                fetchLastRecord(for: newValue)
                            }
                        } else {
                            selectedSchool = ""
                            // N61: this was `isJobBoxMode ? "" : ""`.
                            selectedStatus = ""
                        }
                    }

                Text("The last record for this number is fetched the moment the fourth digit lands.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var photographerSection: some View {
        AmbientFormSection(title: "Photographer",
                           status: localPhotographer.isEmpty ? "required" : localPhotographer,
                           statusTint: localPhotographer.isEmpty ? .orange : nil) {
            Picker("Photographer", selection: $localPhotographer) {
                ForEach(photographerNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        }
    }

    private var sessionSection: some View {
        AmbientFormSection(title: "Session assignment",
                           status: sessionStatus,
                           statusTint: sessionStatusTint) {
            VStack(alignment: .leading, spacing: 10) {
                if sessionsLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading sessions…").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if sessionsLoadFailed {
                    // Surfaced rather than printed (N30).
                    HStack(spacing: 8) {
                        Label("Couldn't load sessions.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Spacer(minLength: 8)
                        Button("Retry") { loadAvailableSessionsForJobBox() }
                            .font(.caption.weight(.semibold))
                    }
                }

                Button {
                    showSessionSelection = true
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "calendar").foregroundStyle(tint).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedSession?.schoolName ?? "Select Session")
                                .font(AmbientDensity.compact.titleFont)
                            Text(selectedSession.map { formatSessionSubtitle($0) }
                                 ?? "Choose from available sessions in the next 2 weeks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: selectedSession) { newSession in
            if let session = newSession {
                // Find the school by ID so the name matches the school record exactly
                let schoolId = session.schoolId
                if let school = schools.first(where: { $0.id == schoolId }) {
                    selectedSchool = school.name
                } else {
                    // Fallback to session's school name if not found
                    selectedSchool = session.schoolName
                }
                selectedStatus = "Packed"
            } else {
                // CLEARED via the sheet's "No session" row — the exact inverse of
                // the branch above: drop the session's school so the number's own
                // defaults refill it, then replay them.
                //
                // NOT `updateJobBoxDefaults()`: that also runs the session
                // PRE-SELECT, which would immediately re-link the box to the very
                // session just cleared. Only the number-derived half is replayed.
                selectedSchool = ""
                applyJobBoxNumberDefaults()
            }
        }
    }

    private var sessionStatus: String {
        if sessionsLoading { return "loading" }
        if sessionsLoadFailed { return "unavailable" }
        return selectedSession == nil ? "none selected" : "1 selected"
    }

    private var sessionStatusTint: Color? {
        if sessionsLoading { return .orange }
        if sessionsLoadFailed { return .orange }
        return selectedSession == nil ? .orange : nil
    }

    private var additionalSection: some View {
        AmbientFormSection(title: "Additional information",
                           status: selectedStatus.isEmpty ? "required" : selectedStatus,
                           statusTint: selectedStatus.isEmpty ? .orange : nil) {
            VStack(alignment: .leading, spacing: 10) {
                // School
                if schools.isEmpty {
                    Text("Loading schools...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    SearchableSchoolPickerString(
                        selection: $selectedSchool,
                        schools: $schools,
                        title: "School",
                        disabled: isJobBoxMode && selectedSession != nil,
                        organizationID: userManager.currentUserOrganizationID
                    )
                }

                Divider()

                // Status
                Picker("Status", selection: $selectedStatus) {
                    if isJobBoxMode {
                        ForEach(jobBoxStatuses, id: \.self) { status in
                            Text(status).tag(status)
                        }
                    } else {
                        ForEach(localStatuses, id: \.self) { status in
                            Text(status).tag(status)
                        }
                    }
                }
                .onChange(of: selectedStatus) { newVal in
                    if !isJobBoxMode && newVal.lowercased() == "cleared" {
                        selectedSchool = "Iconik"
                    } else if isJobBoxMode && newVal.lowercased() == "turned in" {
                        selectedSchool = "Iconik"
                    }
                }

                // Conditional toggles for SD Card. The hardcoded organization gate
                // is KEPT — two people's names in shipped UI is an operator call,
                // not a design one.
                if !isJobBoxMode && selectedStatus.lowercased() == "uploaded",
                   userManager.currentUserOrganizationID == "T6XeeaUNoOp8VJqq36wi" {
                    Toggle("Uploaded from Jason's house", isOn: $uploadedFromJasonsHouse)
                        .tint(tint)
                        .onChange(of: uploadedFromJasonsHouse) { newValue in
                            if newValue { uploadedFromAndysHouse = false }
                        }

                    Toggle("Uploaded from Andy's house", isOn: $uploadedFromAndysHouse)
                        .tint(tint)
                        .onChange(of: uploadedFromAndysHouse) { newValue in
                            if newValue { uploadedFromJasonsHouse = false }
                        }
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    // ambient-allow: a form button, not a container.
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            // Cancel stayed live during a save, so the screen could be torn down
            // mid-write with the result landing on a view that is gone.
            .disabled(isSubmitting)

            Button {
                submitData()
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().tint(.white) }
                    Text(isSubmitting ? "Saving…" : "Submit")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                // ambient-allow: the primary action — a control.
                .background(Capsule().fill(isSubmitting ? Color.gray : tint))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || !numberIsValid)
        }
    }

    private func formatSessionSubtitle(_ session: Session) -> String {
        let time = "\(session.startTime) - \(session.endTime)"
        return "\(session.date) · \(time)"
    }

    // MARK: - Schools

    func refreshSchools() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            isRefreshing = false
            return
        }

        // Force refresh from server
        DatabaseManager.shared.refreshSchoolsFromServer(forOrgID: orgID) { schoolItems in
            DispatchQueue.main.async {
                self.schools = schoolItems
                self.isRefreshing = false
            }
        }
    }

    /// N34. This used to call `refreshSchools()` and then busy-wait on the
    /// `isRefreshing` flag with a 0.1s sleep loop — which spins forever if the
    /// completion never fires, and whose `try?` swallowed cancellation. It now
    /// awaits the fetch itself.
    func refreshSchoolsAsync() async {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty, !isRefreshing else { return }
        isRefreshing = true

        let schoolItems: [SchoolItem] = await withCheckedContinuation { continuation in
            DatabaseManager.shared.refreshSchoolsFromServer(forOrgID: orgID) { items in
                continuation.resume(returning: items)
            }
        }

        self.schools = schoolItems
        self.isRefreshing = false
    }

    func loadInitialData() {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            // WAS A SILENT RETURN (audit round). With no organization id the
            // school and photographer pickers stay permanently on "Loading
            // schools..." with nothing said — the same empty-state-hides-a-failure
            // shape the tracker was fixed for. It surfaces through this view's
            // own alert.
            alertMessage = "We couldn't tell which organization you belong to, so schools and photographers can't be loaded."
            showAlert = true
            return
        }

        // Load photographers
        if let data = UserDefaults.standard.data(forKey: "photographerNames"),
           let cachedNames = try? JSONDecoder().decode([String].self, from: data) {
            self.photographerNames = cachedNames
        }
        DatabaseManager.shared.listenForPhotographers(inOrgID: orgID) { names in
            DispatchQueue.main.async {
                self.photographerNames = names
            }
        }

        // Load schools
        if let data = UserDefaults.standard.data(forKey: "nfcSchools"),
           let cachedSchools = try? JSONDecoder().decode([SchoolItem].self, from: data) {
            self.schools = cachedSchools
        }
        // First refresh from server to get latest schools
        DatabaseManager.shared.refreshSchoolsFromServer(forOrgID: orgID) { schoolItems in
            DispatchQueue.main.async {
                self.schools = schoolItems
            }
        }

        // Then listen for real-time updates
        DatabaseManager.shared.listenForSchoolsData(forOrgID: orgID) { schoolItems in
            DispatchQueue.main.async {
                self.schools = schoolItems
            }
        }

        // Recorded AFTER subscribing, which is what makes the token mean "the
        // channels I started".
        listenerGeneration = DatabaseManager.shared.currentNFCListenerGeneration
    }

    func loadAvailableSessionsForJobBox() {
        sessionsLoading = true
        sessionsLoadFailed = false
        Task {
            do {
                let sessions = try await timeTrackingService.getAvailableSessionsForJobBox()
                await MainActor.run {
                    self.availableSessions = sessions
                    self.sessionsLoading = false
                }
            } catch {
                await MainActor.run {
                    self.sessionsLoading = false
                    self.sessionsLoadFailed = true
                }
            }
        }
    }

    // MARK: - History

    func fetchLastRecord(for cardNumber: String) {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else { return }

        DatabaseManager.shared.fetchRecords(field: "cardNumber", value: cardNumber, organizationID: orgID) { result in
            switch result {
            case .success(let records):
                let sortedRecords = records.sorted { $0.timestamp > $1.timestamp }
                self.lastRecord = sortedRecords.first
                updateSDCardDefaults()
            case .failure(let error):
                print("Error fetching record for card \(cardNumber): \(error.localizedDescription)")
            }
        }
    }

    func fetchLastJobBoxRecord(for boxNumber: String) {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else { return }

        DatabaseManager.shared.fetchJobBoxRecords(field: "boxNumber", value: boxNumber, organizationID: orgID) { result in
            switch result {
            case .success(let records):
                let sortedRecords = records.sorted { $0.timestampDate > $1.timestampDate }
                self.lastJobBoxRecord = sortedRecords.first
                updateJobBoxDefaults()
            case .failure(let error):
                print("Error fetching job box record for box \(boxNumber): \(error.localizedDescription)")
            }
        }
    }

    private func updateSDCardDefaults() {
        if let last = lastRecord {
            // If last record was "cleared," default to "Iconik"
            if last.status.lowercased() == "cleared" {
                selectedSchool = "Iconik"
            } else {
                selectedSchool = last.school
            }

            // The FORM variant: "Camera Bag" -> "Camera", "Personal" -> "Cleared",
            // everything else one step round the ring.
            selectedStatus = NFCRoutingRules.nextSDStatus(after: last.status, variant: .form)
        } else {
            selectedSchool = ""
            selectedStatus = ""
        }
    }

    /// The school and status this NUMBER implies, with no session involved.
    ///
    /// Split out of `updateJobBoxDefaults` so clearing a session can replay
    /// exactly this and nothing else — the session pre-select below it would
    /// otherwise re-link the box the moment it was unlinked.
    private func applyJobBoxNumberDefaults() {
        if let last = lastJobBoxRecord {
            selectedSchool = last.school ?? ""

            // If last status was "Turned In", default school to "Iconik"
            if last.jobBoxStatus == .turnedIn {
                selectedSchool = "Iconik"
            }

            // Calculate next status in the cycle
            selectedStatus = NFCRoutingRules.nextJobBoxStatus(after: last.status)
        } else {
            // Default for new job box
            if selectedSchool.isEmpty {
                if let firstSchool = schools.sorted(by: { $0.name < $1.name }).first?.name {
                    selectedSchool = firstSchool
                }
            }
            selectedStatus = "Packed"
        }
    }

    private func updateJobBoxDefaults() {
        applyJobBoxNumberDefaults()

        if let last = lastJobBoxRecord {
            // If there's a shiftUid and we're not in Packed status, try to find the
            // session — but never from a Turned In record: that trip is over
            // (unreachable today since the status cycle wraps Turned In to Packed,
            // guarded anyway to match JobBoxFormView).
            if selectedStatus.lowercased() != "packed" && !last.shiftUid.isEmpty && last.jobBoxStatus != .turnedIn {
                // Find the session in available sessions
                if let matchingSession = availableSessions.first(where: { $0.id == last.shiftUid }) {
                    selectedSession = matchingSession
                }
            }
        }

        // Load available sessions when in Packed status
        if selectedStatus.lowercased() == "packed" {
            loadAvailableSessionsForJobBox()
        }
    }

    // MARK: - Submitting

    func submitData() {
        guard !isSubmitting else { return }

        guard cardNumber.count == 4, Int(cardNumber) != nil else {
            alertMessage = "Please enter a valid 4-digit \(isJobBoxMode ? "box" : "card") number."
            showAlert = true
            return
        }

        // Validate session selection for new job boxes
        if isJobBoxMode && selectedSession == nil && lastJobBoxRecord == nil {
            alertMessage = "Please select a session for this job box"
            showAlert = true
            return
        }

        isSubmitting = true

        if isJobBoxMode {
            // Submit job box
            let schoolId = selectedSession?.schoolId ?? schools.first { $0.name == selectedSchool }?.id
            if selectedStatus == "Picked Up" {
                // Check the entered box against what was packed for the job
                // this pickup will file under (JobBoxPickupRules).
                Task { await checkPickupThenSubmit(schoolId: schoolId) }
            } else {
                submitJobBoxData(boxNumber: cardNumber, schoolId: schoolId)
            }
        } else {
            // Submit SD card
            let jasonValue = uploadedFromJasonsHouse ? "Yes" : ""
            let andyValue = uploadedFromAndysHouse ? "Yes" : ""
            submitSDCardData(cardNumber: cardNumber, jasonValue: jasonValue, andyValue: andyValue)
        }
    }

    /// N35. A successful save used to leave every value in place, so a second
    /// Submit re-inserted the same record.
    ///
    /// THE ORDER IS NOT ENOUGH ON ITS OWN (audit round). Setting `cardNumber` to
    /// "" schedules the number field's `onChange`, which runs on the NEXT update
    /// — AFTER this function has finished — and its else-branch blanks
    /// `selectedStatus`. So in job-box mode the "Packed" set below was silently
    /// reset to "" a moment later, and the cleared form came back missing the one
    /// default it is supposed to have. `isClearingAfterSave` is consumed by that
    /// `onChange`, which skips the blanking exactly once.
    private func clearFormAfterSave() {
        // Raised only when the assignment below will REALLY change the value —
        // `onChange` does not fire on an unchanged one, and a flag nobody
        // consumes would swallow the user's next keystroke. (Submit already
        // requires four digits, so this is belt-and-braces.)
        isClearingAfterSave = !cardNumber.isEmpty
        cardNumber = ""
        selectedSchool = ""
        selectedStatus = isJobBoxMode ? "Packed" : ""
        selectedSession = nil
        lastRecord = nil
        lastJobBoxRecord = nil
        uploadedFromJasonsHouse = false
        uploadedFromAndysHouse = false
        pendingPickupSchoolId = nil
    }

    func submitSDCardData(cardNumber: String, jasonValue: String, andyValue: String) {
        let timestamp = Date()
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            isSubmitting = false
            alertMessage = "User organization not found."
            showAlert = true
            return
        }

        DatabaseManager.shared.saveRecord(
            timestamp: timestamp,
            photographer: localPhotographer,
            cardNumber: cardNumber,
            school: selectedSchool,
            status: selectedStatus,
            uploadedFromJasonsHouse: jasonValue,
            uploadedFromAndysHouse: andyValue,
            organizationID: orgID,
            userId: userManager.getCurrentUserID() ?? ""
        ) { result in
            switch result {
            case .success(let message):
                // THE DATA LAYER'S OWN WORDS (audit round). This discarded them
                // for a flat "SD Card record saved" — but the OFFLINE branch
                // returns "…saved offline. Will sync when connection is
                // restored.", so a queued scan was reported as a completed save.
                // Same passthrough as `ScanView`. The form still clears on both
                // paths: the queue is holding the data.
                alertMessage = message
                showAlert = true
                isSubmitting = false
                clearFormAfterSave()

            case .failure(let error):
                alertMessage = "Failed to save record: \(error.localizedDescription)"
                showAlert = true
                isSubmitting = false
            }
        }
    }

    /// The job link this submission will actually get — the picked session, or
    /// what submitJobBoxData would safely inherit (same rule, so the check and
    /// the save agree).
    private var effectiveTargetShiftUid: String? {
        selectedSession?.id ?? JobBoxPickupRules.inheritableShiftUid(
            lastStatus: lastJobBoxRecord?.status,
            lastSchool: lastJobBoxRecord?.school,
            lastShiftUid: lastJobBoxRecord?.shiftUid,
            newStatus: selectedStatus,
            selectedSchool: selectedSchool
        )
    }

    @MainActor
    private func checkPickupThenSubmit(schoolId: String?) async {
        let target = effectiveTargetShiftUid
        var packedBoxNumber: String? = nil
        var lookupFailed = false
        if let target, !target.isEmpty {
            if OfflineDataManager.shared.isOnline {
                do {
                    packedBoxNumber = try await JobBoxService.shared.fetchLatestPackedRecord(
                        forShift: target,
                        organizationID: userManager.currentUserOrganizationID
                    )?.boxNumber
                } catch {
                    lookupFailed = true
                }
            } else {
                lookupFailed = true
            }
        }

        if let warning = JobBoxPickupRules.pickupWarning(
            scannedBox: cardNumber,
            targetShiftUid: target,
            selectedSchool: selectedSchool,
            packedBoxNumber: packedBoxNumber,
            packedLookupFailed: lookupFailed,
            lastStatus: lastJobBoxRecord?.status,
            lastSchool: lastJobBoxRecord?.school
        ) {
            isSubmitting = false
            pendingPickupSchoolId = schoolId
            pickupWarning = warning
            showPickupWarning = true
        } else {
            submitJobBoxData(boxNumber: cardNumber, schoolId: schoolId)
        }
    }

    func submitJobBoxData(boxNumber: String, schoolId: String?) {
        let timestamp = Date()
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            isSubmitting = false
            alertMessage = "User organization not found."
            showAlert = true
            return
        }

        // Determine the shiftUid. A non-Packed scan with no session picked may
        // inherit the box's previous job link — but only within the current trip
        // and (for a pickup) the same school (JobBoxPickupRules; the live
        // Pinckneyville/Mt Vernon mislink, 2026-07-29).
        let effectiveShiftUid: String?
        if selectedStatus.lowercased() == "packed" {
            effectiveShiftUid = selectedSession?.id
        } else {
            effectiveShiftUid = selectedSession?.id ?? JobBoxPickupRules.inheritableShiftUid(
                lastStatus: lastJobBoxRecord?.status,
                lastSchool: lastJobBoxRecord?.school,
                lastShiftUid: lastJobBoxRecord?.shiftUid,
                newStatus: selectedStatus,
                selectedSchool: selectedSchool
            )
        }

        DatabaseManager.shared.saveJobBoxRecord(
            timestamp: timestamp,
            photographer: localPhotographer,
            boxNumber: boxNumber,
            school: selectedSchool,
            schoolId: schoolId,
            status: selectedStatus,
            organizationID: orgID,
            userId: userManager.getCurrentUserID() ?? "",
            shiftUid: effectiveShiftUid
        ) { result in
            switch result {
            case .success(let message):
                // The data layer's own words, as above — the offline branch says
                // the record was QUEUED, and that must reach the photographer.
                alertMessage = message
                showAlert = true
                isSubmitting = false
                clearFormAfterSave()

            case .failure(let error):
                alertMessage = "Failed to save job box record: \(error.localizedDescription)"
                showAlert = true
                isSubmitting = false
            }
        }
    }
}
