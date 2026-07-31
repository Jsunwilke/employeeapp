//  ScanView.swift
//  Iconik Employee — the scan surface of the job box / NFC feature
//
//  AMB.11 conversion. THE BUSINESS RULES DID NOT CHANGE (D12); where a rule was
//  written out longhand here it now comes from `NFC/NFCRoutingRules.swift`, the
//  SwiftUI-free constants file with its own test harness
//  (`scripts/test_nfc_routing_rules.sh`). Adopted here and DELETED locally:
//    - the 3001 routing comparison   -> `NFCRoutingRules.isJobBoxNumber`
//    - the SD status advance ring    -> `NFCRoutingRules.nextSDStatus(variant: .scan)`
//    - the job box status advance    -> `NFCRoutingRules.nextJobBoxStatus`
//    - the 43200s left-job threshold -> `NFCRoutingRules.leftJobAlertThreshold`
//
//  WHAT CHANGED ON SCREEN, all of it from the operator-approved `JobBoxMockup`:
//    - the 200pt disc is the REGISTERED feature colour #2AA7D8, not a hand-rolled
//      orange gradient;
//    - the Job Box Alert banner is REBUILT here from kit components and is now a
//      TAP TARGET. The old `NFC/JobBoxNotification.swift` is DELETED in the same
//      change, and with it its private `formatTime` (finding N51) and its
//      hardcoded "12 hours" (N27) — the threshold's words are now DERIVED from
//      the number;
//    - ONE error surface: an NFC read error is a single `AmbientNoteCard`, no
//      longer an inline box AND a toast at once (N52);
//    - a pre-emptive NFC availability check (approved PROPOSED) — the disc used
//      to be live on hardware that cannot scan and the device answered after the
//      fact.
//
//  OPERATOR RULING 2026-07-31: the banner tap OFFERS THE FIX. It used to open
//  Search filtered to "Left Job" — a filtered list of a problem, with no way to
//  act on it, for boxes that are typically months-old strays nobody will ever
//  re-scan. It now presents the "Left-behind boxes" sheet, one card per stalled
//  box with a "Mark Turned In" button that writes the Turned In scan through the
//  app's standard job-box writer. The Search deep link is DELETED with it
//  (delete-first): `onNavigateToSearch` is gone from this view and from the
//  container's `.scan` case. Statistics keeps its own deep link.
//
//  The three sheets are ONE `.sheet(item:)` (the AMB.10 rule) — the two form
//  sheets used to be stacked `.sheet(isPresented:)` modifiers.
//
//  Fixed in passing: N23 (the realtime `for await` Task is stored and cancelled —
//  the wrapper only unsubscribes the channel), N25 (an empty organization id says
//  so instead of returning silently), N26 (neither sheet can present blank).
//  Deleted per N48: the unused `isSaving`, `jobBoxesLoaded` and `colorScheme`.

import SwiftUI
import CoreNFC
import Supabase

/// One stalled "Left Job" box, resolved to concrete values AT THE MOMENT THE
/// SHEET IS PRESENTED.
///
/// A snapshot, deliberately (the AMB.10 wrong-row class): `leftJobBoxes` is
/// re-computed by `checkForLeftJobBoxes()` on every realtime change, so a list
/// that read through to it could reorder or replace a row under a finger that
/// was already on its way down — and the button writes a row that names a school
/// and a job. What the sheet shows and what the button writes are the same
/// values, fixed when the sheet opened.
private struct LeftBehindBox: Identifiable {
    /// The `job_boxes` row id of the box's latest scan — the identity the sheet
    /// tracks its in-flight writes and its removals by.
    let id: String
    let boxNumber: String
    let school: String
    let schoolId: String?
    let shiftUid: String?
    let photographer: String
    let leftAt: Date
}

struct ScanView: View {
    /// The sheets this screen can present. ONE presentation mechanism (the
    /// AMB.10 rule): this used to be two separate `.sheet(isPresented:)`
    /// modifiers, and the operator ruling added a third surface — stacked
    /// `isPresented` sheets are the pair that fails on device.
    private enum ScanSheet: Identifiable {
        case sdCardForm
        case jobBoxForm
        /// Carries its rows, so the sheet is built from the snapshot rather than
        /// from live state. See `LeftBehindBox`.
        case leftBehind([LeftBehindBox])

        var id: String {
            switch self {
            case .sdCardForm: return "sdCardForm"
            case .jobBoxForm: return "jobBoxForm"
            case .leftBehind: return "leftBehind"
            }
        }
    }

    @StateObject var nfcReader = NFCReaderCoordinator()

    @State private var sheet: ScanSheet?

    /// WHICH sheet was up, for `onDismiss` — `sheet(item:onDismiss:)` hands the
    /// dismissal closure nothing and `sheet` is already nil by the time it runs.
    /// Same pattern as the manager tracker.
    @State private var lastPresented: ScanSheet?

    @State private var school = ""
    @State private var schoolId: String? = nil
    @State private var status = "Job Box"
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var lastRecord: NFCRecord? = nil
    @State private var lastJobBoxRecord: JobBox? = nil

    /// Whether the history fetch behind the sheet about to open FAILED.
    ///
    /// It used to be disclosed by a toast raised at the same moment the sheet
    /// was presented — i.e. underneath it — so the one thing the photographer
    /// needed to know (this form is starting fresh; it has inherited nothing)
    /// was said where it could not be read. The sheets render it themselves.
    @State private var historyUnavailable = false

    // State for loading overlay
    @State private var isLoading = false
    @State private var loadingMessage = ""

    // State for toast notification
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var isSuccessToast = true

    // Offline status
    @ObservedObject private var offlineManager = OfflineDataManager.shared

    // State for job box left on job alerts
    @State private var leftJobBoxes: [(JobBox, TimeInterval)] = []

    // Supabase realtime listener
    @State private var jobBoxListener: ListenerRegistrationWrapper?
    /// N23: the wrapper only unsubscribes the channel, so the stream-consuming
    /// Task outlived the view. Held here and cancelled in `onDisappear`.
    @State private var jobBoxStreamTask: Task<Void, Never>? = nil

    // Debug mode for easier testing - set to false for production
    @State private var debugMode = false

    let localStatuses = ["Job Box", "Camera", "Envelope", "Uploaded", "Cleared", "Camera Bag", "Personal"]
    let jobBoxStatuses = NFCRoutingRules.jobBoxStatusRing

    // Access to shared services
    @ObservedObject private var userManager = UserManager.shared
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""

    private var tint: Color { FeatureTheme.color(for: "scan") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !offlineManager.isOnline { offlineBanner }
                if !leftJobBoxes.isEmpty { alertBanner }

                scanDisc

                if let error = nfcReader.errorMessage {
                    // ONE error surface (N52). This used to be drawn twice at
                    // once — an inline red box AND a red toast from the same
                    // source. The 10s auto-clear below is unchanged.
                    AmbientNoteCard(title: "Couldn't read that tag",
                                    text: error,
                                    accent: .red,
                                    density: .compact)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
        // When the scanned tag number changes, determine if it's a job box or SD card
        .onReceive(nfcReader.$scannedCardNumber) { newValue in
            guard let number = newValue else { return }
            isLoading = true

            // 3001 and above is a job box; ANYTHING else — a lower integer, a
            // non-number, an empty string — is an SD card. The rule and its
            // boundary live in NFCRoutingRules, tested.
            if NFCRoutingRules.isJobBoxNumber(number) {
                loadingMessage = "Fetching job box history..."
                fetchLastJobBoxRecord(for: number)
            } else {
                loadingMessage = "Fetching card history..."
                fetchLastRecord(for: number)
            }
        }
        // Load cached school data and check for job boxes onAppear
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: "dropdownRecords"),
               let cachedDropdowns = try? JSONDecoder().decode([DropdownRecord].self, from: data) {
                if !cachedDropdowns.isEmpty, school.isEmpty {
                    // Default to the first school alphabetically if not already set
                    self.school = cachedDropdowns.sorted { $0.value < $1.value }.first?.value ?? ""
                }
            }

            // Initial check for job boxes in "Left Job" status
            checkForLeftJobBoxes()

            // Set up real-time listener for job box changes
            setupJobBoxListener()
        }
        .onDisappear {
            // Remove the Supabase realtime listener when view disappears
            jobBoxListener?.remove()
            jobBoxListener = nil
            jobBoxStreamTask?.cancel()
            jobBoxStreamTask = nil
            nfcReader.errorMessage = nil
        }
        .sheet(item: $sheet, onDismiss: {
            // The FORM sheets reset the scan state they were built from. The
            // left-behind sheet is not a scan and owns none of it, so it must
            // not clear the school/status a scan in progress is holding.
            switch lastPresented {
            case .sdCardForm, .jobBoxForm:
                nfcReader.scannedCardNumber = nil
                school = ""
                schoolId = nil
                status = "Job Box"
            case .leftBehind, .none:
                break
            }
        }) { which in
            switch which {
            case .sdCardForm: sdCardFormSheet
            case .jobBoxForm: jobBoxFormSheet
            case .leftBehind(let boxes):
                JobBoxLeftBehindSheet(
                    boxes: boxes,
                    markTurnedIn: { box, done in markTurnedIn(box, completion: done) },
                    onAllCleared: {
                        sheet = nil
                        // Offline the write is QUEUED, and the toast must say so —
                        // the same gate WriteNFCView uses (the AMB.11 review's
                        // offline-claims-success class).
                        toastMessage = offlineManager.isOnline
                            ? "Marked turned in"
                            : "Marked turned in — will sync when you're back online"
                        isSuccessToast = true
                        showToast = true
                    }
                )
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Info"),
                  message: Text(alertMessage),
                  dismissButton: .default(Text("OK")))
        }
        .loadingOverlay(isPresented: $isLoading, message: loadingMessage)
        .toast(isPresented: $showToast, message: toastMessage, isSuccess: isSuccessToast)
        .onChange(of: nfcReader.errorMessage) { newValue in
            // Clear any error message after 10 seconds. NOT toasted any more —
            // the card above is the one place this is said (N52).
            if newValue != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    if nfcReader.errorMessage == newValue {
                        nfcReader.errorMessage = nil
                    }
                }
            }
        }
    }

    /// Present a sheet, remembering which one for `onDismiss`.
    private func present(_ next: ScanSheet) {
        lastPresented = next
        sheet = next
    }

    // MARK: - Sheets

    /// `Group` rather than `@ViewBuilder`: the branch is the sheet's whole
    /// body, and the group keeps that one expression.
    private var sdCardFormSheet: some View {
        Group {
            if let cardNumber = nfcReader.scannedCardNumber {
                FormView(
                    cardNumber: cardNumber,
                    selectedSchool: $school,
                    selectedStatus: $status,
                    localStatuses: localStatuses,
                    lastRecord: lastRecord,
                    historyUnavailable: historyUnavailable,
                    onSubmit: { cardNum, chosenPhotographer, jasonVal, andyVal, completion in
                        isLoading = true
                        loadingMessage = "Saving card data..."

                        // Validation goes back INTO the sheet: this view's alert
                        // would be raised underneath it.
                        if let failure = validationFailure(
                            cardNumber: cardNum,
                            photographer: chosenPhotographer,
                            school: school,
                            status: status,
                            // The SD sheet has no photographer control to fix an
                            // empty one with — see `validationFailure`.
                            requiresPhotographer: false
                        ) {
                            isLoading = false
                            completion(false, failure)
                            return
                        }

                        submitSDCardData(
                            cardNumber: cardNum,
                            photographer: chosenPhotographer,
                            jasonValue: jasonVal,
                            andyValue: andyVal,
                            completion: completion
                        )
                    },
                    onCancel: {
                        nfcReader.scannedCardNumber = nil
                        sheet = nil
                    }
                )
            } else {
                // N26: both sheet bodies were `if let` with no `else`, so a blank
                // sheet was reachable whenever the number was cleared between the
                // presentation decision and the body running.
                sheetFallback { sheet = nil }
            }
        }
    }

    /// `Group` rather than `@ViewBuilder`: the branch is the sheet's whole
    /// body, and the group keeps that one expression.
    private var jobBoxFormSheet: some View {
        Group {
            if let boxNumber = nfcReader.scannedCardNumber {
                JobBoxFormView(
                    boxNumber: boxNumber,
                    selectedSchool: $school,
                    selectedStatus: $status,
                    lastRecord: lastJobBoxRecord,
                    historyUnavailable: historyUnavailable,
                    onSubmit: { chosenPhotographer, schoolId, shiftUid, completion in
                        isLoading = true
                        loadingMessage = "Saving job box data..."

                        // Validation goes back INTO the sheet, as above.
                        if let failure = validationFailure(
                            cardNumber: boxNumber,
                            photographer: chosenPhotographer,
                            school: school,
                            status: status,
                            // KEPT for job boxes: `job_boxes.photographer` is a
                            // real, load-bearing column and this sheet has the
                            // control to fill it.
                            requiresPhotographer: true
                        ) {
                            isLoading = false
                            completion(false, failure)
                            return
                        }

                        submitJobBoxData(
                            boxNumber: boxNumber,
                            photographer: chosenPhotographer,
                            schoolId: schoolId,
                            shiftUid: shiftUid,
                            completion: completion
                        )
                    },
                    onCancel: {
                        nfcReader.scannedCardNumber = nil
                        sheet = nil
                    }
                )
            } else {
                sheetFallback { sheet = nil }
            }
        }
    }

    // MARK: - Surfaces

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline Mode").font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            if offlineManager.syncPending {
                Text("• Sync Pending").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
            }
        }
        .foregroundStyle(.white)
        .ambientCard(density: .compact, fill: .tint(.red), fillWidth: true)
    }

    /// The "Job Box Alert" banner, rebuilt from kit components — and given the tap
    /// target it has never had. It used to report a problem and offer no route to
    /// fix it: no button, no tap gesture, not dismissible.
    ///
    /// The tap now opens the FIX (operator, 2026-07-31), not a filtered list: the
    /// boxes here are typically months-old strays that will never be re-scanned,
    /// so the sheet lets each one be marked Turned In from where the problem is
    /// reported. The snapshot is taken HERE, at the tap, and nothing the sheet
    /// shows or writes can change under it afterwards.
    ///
    /// The threshold's WORDS come from `NFCRoutingRules` rather than being typed,
    /// so the sentence cannot disagree with the number it describes (the old copy
    /// said "over 12 hours" while the threshold drops to 5 minutes in debug).
    private var alertBanner: some View {
        Button {
            AmbientHaptics.impact(.light)
            present(.leftBehind(leftBehindSnapshot))
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Job Box Alert").font(.subheadline.weight(.bold))
                    Text(alertSummary).font(.caption)
                    ForEach(leftJobBoxes.prefix(3), id: \.0.id) { record, _ in
                        Text("Box #\(record.boxNumber) · \(JobBoxFormat.elapsed(since: record.timestampDate))"
                             + ((record.school ?? "").isEmpty ? "" : " · \(record.school ?? "")"))
                            .font(.caption)
                    }
                    if leftJobBoxes.count > 3 {
                        Text("…and \(leftJobBoxes.count - 3) more").font(.caption)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .ambientCard(density: .compact, fill: .tint(.orange), fillWidth: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the list of boxes left at a job, where each one can be marked turned in")
    }

    /// The banner's boxes, resolved to concrete values for the sheet. Read once,
    /// at the tap — see `LeftBehindBox`.
    private var leftBehindSnapshot: [LeftBehindBox] {
        leftJobBoxes.map { record, _ in
            LeftBehindBox(id: record.id,
                          boxNumber: record.boxNumber,
                          school: record.school ?? "",
                          schoolId: record.schoolId.isEmpty ? nil : record.schoolId,
                          shiftUid: record.shiftUid.isEmpty ? nil : record.shiftUid,
                          photographer: record.scannedBy,
                          leftAt: record.timestampDate)
        }
    }

    private var alertSummary: String {
        let words = NFCRoutingRules.leftJobAlertThresholdDescription
        if leftJobBoxes.count == 1 {
            return "1 job box has been in 'Left Job' status for over \(words)"
        }
        return "\(leftJobBoxes.count) job boxes have been in 'Left Job' status for over \(words)"
    }

    @ViewBuilder
    private var scanDisc: some View {
        if !NFCNDEFReaderSession.readingAvailable {
            // APPROVED PROPOSED. There was no pre-emptive check anywhere: the disc
            // was always live, you tapped it, and CoreNFC answered "NFC scanning
            // is not supported on this device." into a red box after the fact.
            VStack(spacing: 10) {
                Image(systemName: "wave.3.right.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("This device can't scan tags")
                    .font(.headline)
                Text("iPads have no NFC hardware. Search, Stats and Manual Entry all work here — use Manual Entry to record a box or a card by number.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .ambientCard(density: .roomy, fillWidth: true, contentAlignment: .center)
        } else {
            VStack(spacing: 12) {
                if let cardNumber = nfcReader.scannedCardNumber {
                    Text("Tag #\(cardNumber)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.primary)
                }

                Button {
                    AmbientHaptics.impact(.medium)
                    nfcReader.beginScanning()
                } label: {
                    ZStack {
                        // ambient-allow: the scan target — a control, and
                        // deliberately the biggest one on the screen. 200pt, as
                        // shipped, but in the REGISTERED feature colour rather
                        // than a hand-rolled orange gradient.
                        Circle()
                            .fill(tint.gradient)
                            .frame(width: 200, height: 200)
                            .shadow(color: tint.opacity(0.35), radius: 18, y: 8)
                        VStack(spacing: 10) {
                            Image(systemName: "wave.3.right.circle.fill")
                                .font(.system(size: 72, weight: .light))
                            Text("Scan Tag").font(.title2.bold())
                        }
                        .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan Tag")
                .accessibilityHint("Tap to scan an NFC tag")

                Text("Hold your iPhone near the NFC tag.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// N26. A sheet that has lost its number says so and closes, instead of
    /// presenting an empty card.
    private func sheetFallback(dismiss: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            AmbientNoteCard(title: "That scan is gone",
                            text: "The tag number was cleared before the form could open. Scan the tag again.",
                            accent: .red,
                            density: .compact)
            Button("Close") { dismiss() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
    }

    // MARK: - Realtime

    // Set up an efficient real-time listener for job box changes
    func setupJobBoxListener() {
        guard jobBoxListener == nil else { return }
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            return
        }

        // Use Supabase realtime for job box updates (realtimeV2)
        let supabase = SupabaseManager.shared.client
        let channelKey = "job_boxes_scan_\(orgID)"
        let channel = supabase.realtimeV2.channel(channelKey)

        let changeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "job_boxes",
            filter: "organization_id=eq.\(orgID)"
        )

        jobBoxStreamTask = Task {
            for await _ in changeStream {
                await MainActor.run {
                    // Refresh left job boxes when changes are detected
                    self.checkForLeftJobBoxes()
                }
            }
        }

        Task {
            await channel.subscribe()
        }

        jobBoxListener = ListenerRegistrationWrapper {
            Task {
                await channel.unsubscribe()
            }
        }
    }

    // Function to check for job boxes in "Left Job" status
    func checkForLeftJobBoxes() {
        // Make sure we have the necessary user info
        let orgID = userManager.currentUserOrganizationID
        let currentUserName = storedUserFirstName
        guard !orgID.isEmpty && !currentUserName.isEmpty else {
            return
        }

        let currentTime = Date()

        // First, we need to find all box numbers
        DatabaseManager.shared.fetchJobBoxRecords(field: "all", value: "", organizationID: orgID) { result in
            switch result {
            case .success(let allRecords):
                // Group by box number to find the most recent status for each box
                let boxGroups = Dictionary(grouping: allRecords, by: { $0.boxNumber })

                // Find boxes that are still in "Left Job" status
                var leftJobBoxRecords: [JobBox] = []

                for (_, records) in boxGroups {
                    // Get the most recent record for this box number
                    if let mostRecent = records.sorted(by: { $0.timestampDate > $1.timestampDate }).first {
                        if mostRecent.jobBoxStatus == .leftJob {
                            // Check if this box belongs to the current user — matched
                            // on FIRST NAME, as shipped.
                            if mostRecent.scannedBy.lowercased() == currentUserName.lowercased() {
                                leftJobBoxRecords.append(mostRecent)
                            }
                        }
                    }
                }

                // If no boxes are currently in "Left Job" status, clear the notifications
                if leftJobBoxRecords.isEmpty {
                    DispatchQueue.main.async {
                        self.leftJobBoxes = []
                    }
                    return
                }

                // Process the boxes that are still in "Left Job" status
                let processedRecords = leftJobBoxRecords.map { record -> (JobBox, TimeInterval) in
                    (record, currentTime.timeIntervalSince(record.timestampDate))
                }

                // Filter to show boxes that have been in "Left Job" past the
                // threshold. Debug builds drop it to 5 minutes so the banner can
                // be exercised without waiting half a day.
                let threshold = self.debugMode ? 300.0 : NFCRoutingRules.leftJobAlertThreshold
                let filteredBoxes = processedRecords.filter { _, timeDiff in
                    timeDiff > threshold
                }

                DispatchQueue.main.async {
                    self.leftJobBoxes = filteredBoxes.sorted(by: { $0.1 > $1.1 })
                }

            case .failure(let error):
                print("DEBUG: Failed to fetch job boxes: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Validation and saving

    /// Validate the fields a submission needs.
    ///
    /// - Parameter requiresPhotographer: the JOB BOX path passes `true` — that
    ///   column exists on `job_boxes`, carries who scanned the box, and the
    ///   tracker, the alert banner and the statistics all read it. The SD path
    ///   passes `false`: the SD sheet no longer HAS a photographer control (the
    ///   approved §0.26 drop — `records` has no photographer column, so the value
    ///   is discarded on the online path), and the value it still passes comes
    ///   from the signed-in profile. Requiring it there could only produce a
    ///   dead-end: a rejection the sheet gives no way to fix.
    /// - Returns: whether the submission may proceed. On failure the message is
    ///   returned to the SHEET through `onSubmit`'s completion (see the sheet
    ///   presentations above) — this view's own alert cannot be seen underneath
    ///   the sheet that raised it.
    func validationFailure(cardNumber: String,
                           photographer: String,
                           school: String,
                           status: String,
                           requiresPhotographer: Bool) -> String? {
        var errorMessages: [String] = []

        if cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessages.append("Card/Box number cannot be empty")
        }

        if requiresPhotographer, photographer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessages.append("Photographer cannot be empty")
        }

        if school.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessages.append("School cannot be empty")
        }

        if status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessages.append("Status cannot be empty")
        }

        return errorMessages.isEmpty ? nil : errorMessages.joined(separator: "\n")
    }

    func submitSDCardData(
        cardNumber: String,
        photographer: String,
        jasonValue: String,
        andyValue: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let timestamp = Date()
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            isLoading = false
            toastMessage = "User organization not found."
            isSuccessToast = false
            showToast = true
            completion(false, "User organization not found.")
            return
        }

        DatabaseManager.shared.saveRecord(
            timestamp: timestamp,
            photographer: photographer,
            cardNumber: cardNumber,
            school: school,
            status: status,
            uploadedFromJasonsHouse: jasonValue,
            uploadedFromAndysHouse: andyValue,
            organizationID: orgID,
            userId: UserManager.shared.getCurrentUserID() ?? ""
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false

                switch result {
                case .success(let message):
                    self.toastMessage = message
                    self.isSuccessToast = true
                    self.showToast = true

                    // Close form and reset state
                    self.sheet = nil
                    self.nfcReader.scannedCardNumber = nil

                    // Then notify completion
                    completion(true, nil)

                case .failure(let error):
                    let message = "Failed to save record: \(error.localizedDescription)"
                    self.toastMessage = message
                    self.isSuccessToast = false
                    self.showToast = true
                    // The sheet is still open on failure, so the message has to
                    // reach it — the toast is behind it.
                    completion(false, message)
                }
            }
        }
    }

    func submitJobBoxData(
        boxNumber: String,
        photographer: String,
        schoolId: String? = nil,
        shiftUid: String? = nil, // Updated to include shiftUid
        completion: @escaping (Bool, String?) -> Void
    ) {
        let timestamp = Date()
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            isLoading = false
            toastMessage = "User organization not found."
            isSuccessToast = false
            showToast = true
            completion(false, "User organization not found.")
            return
        }

        // Check if the job box was previously in "Left Job" status
        let wasInLeftJobStatus = lastJobBoxRecord?.jobBoxStatus == .leftJob
        let wasNotificationBox = leftJobBoxes.contains { record, _ in
            return record.boxNumber == boxNumber
        }

        // Without an explicitly chosen session, a non-Packed scan may inherit the
        // box's previous job link — but only within the current trip and (for a
        // pickup) the same school. Unconditional inheritance is how a Pinckneyville
        // pickup got filed under Mt Vernon's finished job (live, 2026-07-29).
        let effectiveShiftUid = shiftUid ?? JobBoxPickupRules.inheritableShiftUid(
            lastStatus: lastJobBoxRecord?.status,
            lastSchool: lastJobBoxRecord?.school,
            lastShiftUid: lastJobBoxRecord?.shiftUid,
            newStatus: status,
            selectedSchool: school
        )

        DatabaseManager.shared.saveJobBoxRecord(
            timestamp: timestamp,
            photographer: photographer,
            boxNumber: boxNumber,
            school: school,
            schoolId: schoolId,
            status: status,
            organizationID: orgID,
            userId: UserManager.shared.getCurrentUserID() ?? "",
            shiftUid: effectiveShiftUid // Pass the effective shiftUid (either from parameter or last record)
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false

                switch result {
                case .success(let message):
                    self.toastMessage = message
                    self.isSuccessToast = true
                    self.showToast = true

                    // For immediate UI update if a notification box is being updated
                    if wasInLeftJobStatus || wasNotificationBox {
                        // Filter out this specific box from the notifications
                        self.leftJobBoxes = self.leftJobBoxes.filter { record, _ in
                            return record.boxNumber != boxNumber
                        }
                    }

                    // Close form and reset state
                    self.sheet = nil
                    self.nfcReader.scannedCardNumber = nil

                    // No need to manually refresh since the Supabase realtime listener
                    // will automatically pick up changes for cross-device updates

                    // Then notify completion
                    completion(true, nil)

                case .failure(let error):
                    let message = "Failed to save job box record: \(error.localizedDescription)"
                    self.toastMessage = message
                    self.isSuccessToast = false
                    self.showToast = true
                    // The sheet is still open on failure, so the message has to
                    // reach it — the toast is behind it.
                    completion(false, message)
                }
            }
        }
    }

    // MARK: - Marking a left-behind box turned in

    /// Write the Turned In scan for one stalled box.
    ///
    /// A scan ROW, not an edit — the same semantics as every other writer on this
    /// shared table (the NFC scan path, the web app, and the manager tracker's
    /// correction in `ManagerJobBoxViewModel.recordScan`): one row per status
    /// change, read latest-by-timestamp, so the history stays true and the crew
    /// push trigger fires. It goes through `DatabaseManager.saveJobBoxRecord`,
    /// the app's standard job-box insert, so this write queues offline and writes
    /// the session back exactly like a scanned one.
    ///
    /// The school, school id and shift link are carried from the box's LATEST
    /// record — the same fields the tracker's correction carries — so the Turned
    /// In row lands on the job the box was left at rather than on nothing.
    ///
    /// - Parameter completion: nil on success, a message on failure. Always on
    ///   the main actor: `saveJobBoxRecord` answers on main on the ONLINE path
    ///   but calls back on the caller's thread when it queues offline.
    private func markTurnedIn(_ box: LeftBehindBox, completion: @escaping (String?) -> Void) {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            completion("User organization not found.")
            return
        }

        DatabaseManager.shared.saveJobBoxRecord(
            timestamp: Date(),
            // The signed-in photographer, exactly as `checkForLeftJobBoxes`
            // matched the box to them in the first place — the banner cannot be
            // on screen with an empty first name.
            photographer: storedUserFirstName,
            boxNumber: box.boxNumber,
            school: box.school,
            schoolId: box.schoolId,
            status: JobBoxStatus.turnedIn.rawValue,
            organizationID: orgID,
            userId: UserManager.shared.getCurrentUserID() ?? "",
            shiftUid: box.shiftUid
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // The banner shrinks immediately, and the re-run confirms it
                    // against the server (a realtime change would do it too, but
                    // only when the device is online).
                    self.leftJobBoxes.removeAll { record, _ in record.boxNumber == box.boxNumber }
                    self.checkForLeftJobBoxes()
                    completion(nil)

                case .failure(let error):
                    completion("Box #\(box.boxNumber) didn't save: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - History

    func fetchLastRecord(for cardNumber: String) {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            // N25: this used to return silently, leaving the scan with no form
            // and no explanation.
            isLoading = false
            toastMessage = "User organization not found."
            isSuccessToast = false
            showToast = true
            return
        }

        DatabaseManager.shared.fetchRecords(field: "cardNumber", value: cardNumber, organizationID: orgID) { result in
            isLoading = false

            switch result {
            case .success(let records):
                self.historyUnavailable = false
                let sortedRecords = records.sorted { $0.timestamp > $1.timestamp }
                self.lastRecord = sortedRecords.first

                if let last = self.lastRecord {
                    // If last record was "cleared", default school to "Iconik"
                    if last.status.lowercased() == "cleared" {
                        self.school = "Iconik"
                    } else {
                        self.school = last.school
                    }

                    // Advance the status in the default status cycle. The scan
                    // variant deliberately lets "Camera Bag"/"Personal" fall
                    // through to the head of the ring.
                    self.status = NFCRoutingRules.nextSDStatus(after: last.status, variant: .scan)
                } else {
                    // If no last record is found, attempt to use the locally cached school list
                    if let data = UserDefaults.standard.data(forKey: "dropdownRecords"),
                       let cachedDropdowns = try? JSONDecoder().decode([DropdownRecord].self, from: data) {
                        if !cachedDropdowns.isEmpty {
                            self.school = cachedDropdowns.sorted { $0.value < $1.value }.first?.value ?? ""
                        }
                    }
                }
                self.present(.sdCardForm)

            case .failure(let error):
                print("DEBUG: Error fetching last record: \(error.localizedDescription)")
                self.lastRecord = nil

                // Still show the form even if we couldn't fetch history — and
                // the form SAYS SO, in itself. The toast this replaces was
                // raised at the same moment the sheet was presented, so it was
                // covered by the very form it was describing.
                self.historyUnavailable = true
                self.present(.sdCardForm)
            }
        }
    }

    func fetchLastJobBoxRecord(for boxNumber: String) {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            // N25, as above.
            isLoading = false
            toastMessage = "User organization not found."
            isSuccessToast = false
            showToast = true
            return
        }

        DatabaseManager.shared.fetchJobBoxRecords(field: "boxNumber", value: boxNumber, organizationID: orgID) { result in
            isLoading = false

            switch result {
            case .success(let records):
                self.historyUnavailable = false
                let sortedRecords = records.sorted { $0.timestampDate > $1.timestampDate }
                self.lastJobBoxRecord = sortedRecords.first

                if let last = self.lastJobBoxRecord {
                    self.school = last.school ?? ""
                    self.schoolId = last.schoolId

                    // Advance the status in the job box status cycle
                    self.status = NFCRoutingRules.nextJobBoxStatus(after: last.status)
                } else {
                    // For new job boxes, don't pre-select values - let them be chosen via session
                    self.school = ""
                    self.schoolId = nil
                    self.status = "" // Will be set when session is selected
                }

                self.present(.jobBoxForm)

            case .failure(let error):
                print("DEBUG: Error fetching last job box record: \(error.localizedDescription)")
                self.lastJobBoxRecord = nil

                // Still show the form even if we couldn't fetch history — the
                // form says so itself (the toast this replaces was covered by
                // the sheet it described).
                self.historyUnavailable = true

                // For new job boxes, don't pre-select values
                self.school = ""
                self.schoolId = nil
                self.status = ""

                self.present(.jobBoxForm)
            }
        }
    }
}

// MARK: - The left-behind sheet

/// The Job Box Alert banner's fix (operator, 2026-07-31): every stalled box, and
/// a button per box that writes its Turned In scan.
///
/// It works on a SNAPSHOT handed to it at presentation and never reads the live
/// list — see `LeftBehindBox`. Rows leave this list when their write succeeds,
/// not when the underlying query changes, so a tap always writes the box that was
/// under the finger.
private struct JobBoxLeftBehindSheet: View {
    /// Writes one box's Turned In scan; answers nil on success or a message on
    /// failure, on the main actor.
    let markTurnedIn: (LeftBehindBox, @escaping (String?) -> Void) -> Void
    /// The last box cleared. The caller closes the sheet and says so — a toast
    /// raised from in here would be raised underneath this sheet.
    let onAllCleared: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// The snapshot, owned and mutated by this sheet.
    @State private var remaining: [LeftBehindBox]

    /// The boxes whose write is in flight, by row id — a per-box guard, because
    /// several can be marked one after another without waiting.
    @State private var inFlight: Set<String> = []

    /// THE SHEET'S OWN FAILURE SURFACE (the AMB.11 review class): a toast raised
    /// by the caller would be drawn under this sheet, where the one person who
    /// needs it cannot read it.
    @State private var errorText: String?

    init(boxes: [LeftBehindBox],
         markTurnedIn: @escaping (LeftBehindBox, @escaping (String?) -> Void) -> Void,
         onAllCleared: @escaping () -> Void) {
        self.markTurnedIn = markTurnedIn
        self.onAllCleared = onAllCleared
        _remaining = State(initialValue: boxes)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let errorText {
                            AmbientNoteCard(title: "That didn't save",
                                            text: errorText,
                                            accent: .red,
                                            density: .compact)
                        }

                        if remaining.isEmpty {
                            // Momentary — clearing the last box closes this sheet
                            // — but a sheet must never be able to present blank
                            // (N26).
                            AmbientNoteCard(title: "All clear",
                                            text: "Every box you left at a job has been marked turned in.",
                                            density: .compact)
                        } else {
                            ForEach(remaining) { box in
                                card(for: box)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Left-behind boxes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func card(for box: LeftBehindBox) -> some View {
        let working = inFlight.contains(box.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AmbientBadge(text: "Box \(box.boxNumber)",
                             tint: JobBoxTripStage.leftJob.meterTint)
                Spacer(minLength: 8)
                Text("Left \(JobBoxFormat.elapsed(since: box.leftAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !box.school.isEmpty {
                Text(box.school)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(box.photographer.isEmpty ? "Photographer not recorded" : box.photographer)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                turnIn(box)
            } label: {
                HStack(spacing: 8) {
                    if working { ProgressView().tint(.white) }
                    Text(working ? "Marking…" : "Mark Turned In")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                // ambient-allow: a completion control, not a container. The fill
                // is the Turned In stage colour from the status contract — this
                // finishes the box's trip, so it wears the colour that says so
                // rather than the red of a destructive action.
                .background(Capsule().fill(JobBoxTripStage.turnedIn.meterTint))
            }
            .buttonStyle(.plain)
            .disabled(working)
            .accessibilityLabel("Mark box \(box.boxNumber) turned in")
        }
        .ambientCard(fillWidth: true)
    }

    private func turnIn(_ box: LeftBehindBox) {
        guard !inFlight.contains(box.id) else { return }
        errorText = nil
        inFlight.insert(box.id)

        markTurnedIn(box) { failure in
            inFlight.remove(box.id)

            if let failure {
                withAnimation(AmbientMotion.snappy) { errorText = failure }
                return
            }

            AmbientHaptics.impact(.medium)
            withAnimation(AmbientMotion.snappy) {
                remaining.removeAll { $0.id == box.id }
            }
            if remaining.isEmpty { onAllCleared() }
        }
    }
}

struct ScanView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScanView()
        }
    }
}
