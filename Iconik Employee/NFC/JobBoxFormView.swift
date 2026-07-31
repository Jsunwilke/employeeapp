//  JobBoxFormView.swift
//  Iconik Employee — the job box sheet the Scan screen presents
//
//  AMB.11 conversion, from the approved `JobBoxLabBoxForm`.
//
//  IT HAS A TITLE BAR NOW (N36): it declared `.navigationTitle("Job Box Entry")`
//  with nothing to render it. The sheet owns a real `NavigationView` titled
//  "Job Box <n>" with Cancel / Submit in the toolbar; the two body buttons they
//  replace are deleted.
//
//  THE SHIPPED PROGRESS CARD IS AT THE TOP. `JobBoxProgressCard` and the whole
//  `JobBoxProgressRules` vocabulary already shipped and are FROZEN — this embeds
//  them, it does not redesign them. The box's rows are fetched on appear and
//  `JobBoxProgressReading(rows:)` cuts the log to the CURRENT TRIP itself (at the
//  last Packed scan), which is the rule that stops June's trip being drawn as
//  part of October's. While the fetch is in flight a compact placeholder stands
//  in; if it fails the card is simply omitted — it is supplementary, and a box
//  can still be recorded without it.
//
//  ONE SESSION-CHOOSING UI (approved): the inline `Picker` with its "None" tag is
//  DELETED and this sheet now opens the same searchable `NFCSessionSelectionView`
//  Manual Entry uses. It also has a visible LOADING state — the old Picker was
//  not rendered AT ALL while sessions were in flight or when there were none
//  (N14), so the two looked identical on the one control that links a box to a job.
//
//  EVERY RULE IS UNCHANGED (D12): a new box arrives with no school and no status,
//  session selection sets school/schoolId and forces "Packed" for a new box,
//  school is read-only when a session is selected and a SEARCHABLE picker
//  otherwise (N38), the pickup guard runs through `checkPickupThenSubmit` with
//  its exact copy, and `performSubmit` passes ONLY `selectedSession?.id` — the
//  inheritance rule is applied for the SAVE in `ScanView`, and that stays true.

import SwiftUI

struct JobBoxFormView: View {
    let boxNumber: String
    @Binding var selectedSchool: String
    @Binding var selectedStatus: String
    let lastRecord: JobBox?
    /// True when the box's history fetch FAILED, so this form knows nothing
    /// about the box's current trip. Disclosed here, inside the sheet —
    /// `ScanView` used to raise a toast underneath it.
    var historyUnavailable: Bool = false

    /// The completion now carries the FAILURE MESSAGE (audit round). ScanView
    /// validates the submission and used to report a rejection through its own
    /// alert — raised beneath this sheet, where it could not be read.
    var onSubmit: (String, String?, String?, @escaping (Bool, String?) -> Void) -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var timeTrackingService = TimeTrackingService.shared
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""

    @State private var localPhotographer: String = ""
    @State private var selectedSession: Session? = nil
    @State private var selectedSchoolId: String? = nil

    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    // Pickup mismatch check (JobBoxPickupRules): set when Submit finds the
    // scanned box doesn't match what was packed for the chosen job.
    @State private var pickupWarning: JobBoxPickupWarning? = nil
    @State private var showPickupWarning = false

    /// Raised by `updateAvailableSessions` immediately before it assigns
    /// `selectedSession` itself, and consumed by the `onChange` below.
    ///
    /// THIS RESTORES SHIPPED BEHAVIOUR (audit round). The session control used to
    /// be an inline `Picker` whose `.onChange` was installed in the SAME update
    /// that pre-selected the session, so it never fired for the PROGRAMMATIC
    /// pre-select — only for a user's pick. The always-mounted `onChange` this
    /// conversion introduced does fire, which would let an auto-selected session
    /// rewrite school/schoolId and force "Packed" on a box the photographer never
    /// touched. A user's choice keeps every one of those side effects.
    @State private var programmaticSessionChange = false

    // For data loading
    @State private var photographerNames: [String] = []
    @State private var schools: [SchoolItem] = []
    /// The dropdown-listener subscription this view established. See
    /// `DatabaseManager.stopListening(ifGeneration:)`.
    @State private var listenerGeneration = 0
    @State private var availableSessions: [Session] = []
    @State private var sessionsLoading = false
    @State private var sessionsLoadFailed = false
    @State private var showSessionSelection = false

    // The shipped progress card's reading for this box's current trip.
    @State private var progressReading: JobBoxProgressReading? = nil
    @State private var progressLoading = true

    let jobBoxStatuses = NFCRoutingRules.jobBoxStatusRing

    private var tint: Color { FeatureTheme.color(for: "scan") }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if historyUnavailable {
                            AmbientNoteCard(
                                title: "Couldn't load this box's history",
                                text: "The form starts fresh: no school, no status, and this scan will not inherit the box's existing session link. Pick the session yourself before you submit.",
                                accent: .orange,
                                density: .compact)
                        }
                        boxSection
                        sessionSection
                        detailsSection
                    }
                    .padding(16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Job Box \(boxNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submitTapped() }
                        .disabled(isSubmitting)
                }
            }
            // ONE ALERT API on this view (audit round — the AMB.10
            // mixed-presentation class). This was the deprecated `Alert(...)`
            // initializer stacked on the modern `alert(_:isPresented:)` below it;
            // every string is unchanged.
            .alert("Error", isPresented: $showAlert) {
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
                    performSubmit()
                }
                Button("Go Back", role: .cancel) {}
            } message: { warning in
                Text(warning.message)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            loadInitialData()
        }
        // LISTENER TOKEN SYMMETRY (audit round): this sheet subscribes the shared
        // photographer/school channels and never handed them back. Generation-
        // guarded, so a teardown for channels a later screen owns is a no-op.
        .onDisappear {
            DatabaseManager.shared.stopListening(ifGeneration: listenerGeneration)
        }
        .onChange(of: localPhotographer) { _ in
            updateAvailableSessions()
        }
        .sheet(isPresented: $showSessionSelection) {
            NFCSessionSelectionView(
                sessions: availableSessions,
                selectedSession: $selectedSession,
                isPresented: $showSessionSelection,
                isLoading: sessionsLoading,
                loadFailed: sessionsLoadFailed,
                onRetry: { updateAvailableSessions() }
            )
        }
        .onChange(of: selectedSession) { session in
            // A PROGRAMMATIC pre-select is not a choice: consume the flag and
            // leave school, schoolId and status exactly as the last record set
            // them. See `programmaticSessionChange`.
            if programmaticSessionChange {
                programmaticSessionChange = false
                return
            }
            if let session = session {
                selectedSchool = session.schoolName
                selectedSchoolId = session.schoolId

                // If this is a new box (no last record), set status to "Packed"
                if lastRecord == nil {
                    selectedStatus = "Packed"
                }
            } else {
                // CLEARED via the sheet's "No session" row. `updateDefaults()` IS
                // the pre-session state — school, schoolId and the advanced
                // status from the last record, or a new box's deliberate blanks —
                // so replaying it is the exact inverse of the branch above rather
                // than a second set of rules. It cannot re-select a session:
                // session pre-selection lives in `updateAvailableSessions`, which
                // this does not call. The school picker returns to editable on
                // its own, because that is keyed off `selectedSession != nil`.
                updateDefaults()
            }
        }
    }

    // MARK: - Sections

    private var boxSection: some View {
        AmbientFormSection(title: "Job box information",
                           status: "#\(boxNumber)",
                           statusTint: tint) {
            Group {
                if let reading = progressReading {
                    JobBoxProgressCard(reading: reading, boxNumber: boxNumber)
                } else if progressLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading this box's trip…").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    // The card is supplementary — a failed history fetch omits it
                    // silently rather than blocking the scan being recorded.
                    Text("Box #\(boxNumber)").font(.subheadline)
                }
            }
        }
    }

    private var sessionSection: some View {
        AmbientFormSection(title: "Session",
                           status: sessionStatus,
                           statusTint: sessionStatusTint) {
            VStack(alignment: .leading, spacing: 10) {
                if sessionsLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading sessions…").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if sessionsLoadFailed {
                    HStack(spacing: 8) {
                        Label("Couldn't load sessions.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Spacer(minLength: 8)
                        Button("Retry") { updateAvailableSessions() }
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
                            if let session = selectedSession {
                                Text(formatSessionTime(session))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Text("A brand-new box deliberately arrives with no school and no status, so the session supplies them.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sessionStatus: String {
        if sessionsLoading { return "loading" }
        if sessionsLoadFailed { return "unavailable" }
        return selectedSession?.schoolName ?? "none selected"
    }

    private var sessionStatusTint: Color? {
        if sessionsLoading || sessionsLoadFailed { return .orange }
        return selectedSession == nil ? .orange : nil
    }

    private var detailsSection: some View {
        AmbientFormSection(title: "Details",
                           status: selectedStatus.isEmpty ? "required" : selectedStatus,
                           statusTint: selectedStatus.isEmpty ? .orange : nil) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Photographer", selection: $localPhotographer) {
                    ForEach(photographerNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                Divider()

                // School is read-only when a session supplies it; otherwise the
                // SEARCHABLE picker, the same control Manual Entry uses.
                if selectedSession != nil {
                    HStack {
                        Text("School")
                        Spacer()
                        Text(selectedSchool)
                            .foregroundStyle(.secondary)
                    }
                } else if schools.isEmpty {
                    Text("Loading schools...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    SearchableSchoolPickerString(
                        selection: $selectedSchool,
                        schools: $schools,
                        title: "School",
                        disabled: false,
                        organizationID: userManager.currentUserOrganizationID
                    )
                }

                Divider()

                Picker("Status", selection: $selectedStatus) {
                    ForEach(jobBoxStatuses, id: \.self) { status in
                        Text(status).tag(status)
                    }
                }
            }
        }
    }

    // MARK: - Submitting

    private func submitTapped() {
        guard !isSubmitting else { return }
        isSubmitting = true

        if selectedStatus == "Picked Up" {
            // Check the scanned box against what was packed for the job this
            // pickup will file under.
            Task { await checkPickupThenSubmit() }
        } else {
            performSubmit()
        }
    }

    /// The job link this submission will actually get: the picked session, or —
    /// when none is picked — whatever ScanView's save path would safely inherit
    /// from the box's last record (same rule, so the check and the save agree).
    private var effectiveTargetShiftUid: String? {
        selectedSession?.id ?? JobBoxPickupRules.inheritableShiftUid(
            lastStatus: lastRecord?.status,
            lastSchool: lastRecord?.school,
            lastShiftUid: lastRecord?.shiftUid,
            newStatus: selectedStatus,
            selectedSchool: selectedSchool
        )
    }

    @MainActor
    private func checkPickupThenSubmit() async {
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
            scannedBox: boxNumber,
            targetShiftUid: target,
            selectedSchool: selectedSchool,
            packedBoxNumber: packedBoxNumber,
            packedLookupFailed: lookupFailed,
            lastStatus: lastRecord?.status,
            lastSchool: lastRecord?.school
        ) {
            isSubmitting = false
            pickupWarning = warning
            showPickupWarning = true
        } else {
            performSubmit()
        }
    }

    private func performSubmit() {
        // Pass the session UID if a session is selected
        let shiftUid = selectedSession?.id

        onSubmit(localPhotographer, selectedSchoolId, shiftUid) { success, failure in
            DispatchQueue.main.async {
                isSubmitting = false
                if success {
                    dismiss()
                } else {
                    // The caller's own words when it has them — a validation
                    // rejection names the field that is empty.
                    alertMessage = failure ?? (alertMessage.isEmpty ? "Submission failed. Please try again." : alertMessage)
                    showAlert = true
                }
            }
        }
    }

    // MARK: - Loading

    private func loadInitialData() {
        // Set default photographer
        localPhotographer = storedUserFirstName

        // Update defaults from last record
        updateDefaults()

        // Load photographers
        if let data = UserDefaults.standard.data(forKey: "photographerNames"),
           let cachedNames = try? JSONDecoder().decode([String].self, from: data) {
            self.photographerNames = cachedNames
        }

        let orgID = userManager.currentUserOrganizationID
        if !orgID.isEmpty {
            DatabaseManager.shared.listenForPhotographers(inOrgID: orgID) { names in
                DispatchQueue.main.async {
                    self.photographerNames = names
                }
            }
        }

        // Load schools
        if let data = UserDefaults.standard.data(forKey: "nfcSchools"),
           let cachedSchools = try? JSONDecoder().decode([SchoolItem].self, from: data) {
            self.schools = cachedSchools
        }

        let schoolOrgID = userManager.currentUserOrganizationID
        if !schoolOrgID.isEmpty {
            DatabaseManager.shared.listenForSchoolsData(forOrgID: schoolOrgID) { records in
                DispatchQueue.main.async {
                    self.schools = records
                }
            }
        }

        // Recorded AFTER subscribing, which is what makes the token mean "the
        // channels I started".
        listenerGeneration = DatabaseManager.shared.currentNFCListenerGeneration

        // Load sessions
        updateAvailableSessions()

        // Load this box's scan log for the progress card
        loadProgress()
    }

    private func loadProgress() {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            progressLoading = false
            return
        }

        DatabaseManager.shared.fetchJobBoxRecords(field: "boxNumber",
                                                  value: boxNumber,
                                                  organizationID: orgID) { result in
            DispatchQueue.main.async {
                self.progressLoading = false
                switch result {
                case .success(let rows):
                    // `init(rows:)` drops rows whose status maps to no stage and
                    // cuts the log to the current trip itself.
                    let reading = JobBoxProgressReading(rows: rows)
                    self.progressReading = reading.isEmpty ? nil : reading
                case .failure:
                    self.progressReading = nil
                }
            }
        }
    }

    private func updateAvailableSessions() {
        sessionsLoading = true
        sessionsLoadFailed = false
        Task {
            do {
                let sessions = try await timeTrackingService.getAvailableSessionsForJobBox()
                await MainActor.run {
                    self.availableSessions = sessions.sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
                    self.sessionsLoading = false

                    // Pre-select the box's current trip's session — but a Turned In
                    // record means the trip is OVER, and defaulting to it would seed
                    // the next scan with a finished job (same trap as inheritance).
                    //
                    // Both assignments are PROGRAMMATIC: the flag is raised only
                    // when the value will really change, because `onChange` does
                    // not fire on an unchanged one and a flag nobody consumes
                    // would swallow the user's next pick.
                    if let last = self.lastRecord, !last.shiftUid.isEmpty, last.jobBoxStatus != .turnedIn {
                        let match = self.availableSessions.first { $0.id == last.shiftUid }
                        if match?.id != self.selectedSession?.id {
                            self.programmaticSessionChange = true
                            self.selectedSession = match
                        }
                    } else if self.availableSessions.count == 1 {
                        // Auto-select if only one session
                        let match = self.availableSessions.first
                        if match?.id != self.selectedSession?.id {
                            self.programmaticSessionChange = true
                            self.selectedSession = match
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.sessionsLoading = false
                    self.sessionsLoadFailed = true
                }
            }
        }
    }

    private func updateDefaults() {
        if let last = lastRecord {
            selectedSchool = last.school ?? ""
            selectedSchoolId = last.schoolId

            // Advance status
            selectedStatus = NFCRoutingRules.nextJobBoxStatus(after: last.status)
        } else {
            // For new job boxes, don't pre-select values - they'll be set via session selection
            selectedSchool = ""
            selectedSchoolId = nil
            selectedStatus = "" // Will be set to "Packed" when session is selected
        }
    }

    /// Shared formatters rather than a `DateFormatter` allocated per body (N42).
    private func formatSessionTime(_ session: Session) -> String {
        if let startDate = session.startDate, let endDate = session.endDate {
            return "\(Formatters.shortTime.string(from: startDate)) - \(Formatters.shortTime.string(from: endDate))"
        } else if let startDate = session.startDate {
            return Formatters.mediumDateTime.string(from: startDate)
        }
        return ""
    }
}
