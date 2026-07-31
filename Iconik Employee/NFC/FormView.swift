//  FormView.swift
//  Iconik Employee — the SD-card sheet the Scan screen presents
//
//  AMB.11 conversion, from the approved `JobBoxLabSDForm`.
//
//  IT HAS A TITLE BAR NOW (N36). It declared `.navigationTitle("Enter Info")`
//  with no enclosing container, so the title never rendered at all. The sheet now
//  owns a real `NavigationView` titled "SD Card <n>" with Cancel / Submit in the
//  toolbar, and the two body buttons it replaces are deleted.
//
//  DROPPED: the Photographer picker (approved with the design; §0.26). The
//  `records` table HAS NO `photographer` COLUMN — proved by live query — so
//  `saveRecord` discards the value on the online path and `fetchRecords`
//  hardcodes `""` on every row read back. It was a real control whose value went
//  nowhere. The signed-in photographer's first name is still passed to `onSubmit`
//  so the save signature and ScanView's validation are untouched, and so the
//  OFFLINE queue path — the one place the value is persisted — keeps recording
//  who did it.
//
//  Also changed: the School picker is the SEARCHABLE one the rest of the app uses
//  (N38 — a plain `Picker` is unusable at real school counts), the alert is
//  titled "Error" instead of `Text("")` (N37), and the unreachable
//  `if alertMessage == "Scan saved"` branch is DELETED with its `isSubmitting`
//  trap (N13).
//
//  The status ring pre-select is unchanged and now comes from
//  `NFCRoutingRules.nextSDStatus(variant: .form)`.

import SwiftUI

struct FormView: View {
    let cardNumber: String
    @Binding var selectedSchool: String
    @Binding var selectedStatus: String
    let localStatuses: [String]
    let lastRecord: NFCRecord?
    /// True when the card's history fetch FAILED, so this form is starting from
    /// nothing rather than from the card's last scan. Disclosed here, inside the
    /// sheet — `ScanView` used to raise a toast underneath it.
    var historyUnavailable: Bool = false

    /// The completion now carries the FAILURE MESSAGE (audit round). ScanView
    /// validates the submission and used to report a rejection through its own
    /// alert — raised beneath this sheet, where it could not be read, while the
    /// sheet showed the generic "Submission failed. Please try again."
    var onSubmit: (String, String, String, String, @escaping (Bool, String?) -> Void) -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userManager = UserManager.shared
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""

    @State private var uploadedFromJasonsHouse: Bool = false
    @State private var uploadedFromAndysHouse: Bool = false

    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    @State private var schools: [SchoolItem] = []
    /// The dropdown-listener subscription this sheet established. See
    /// `DatabaseManager.stopListening(ifGeneration:)`.
    @State private var listenerGeneration = 0

    private var tint: Color { FeatureTheme.color(for: "scan") }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if historyUnavailable {
                            AmbientNoteCard(
                                title: "Couldn't load this card's history",
                                text: "The form starts fresh — school and status are not carried over from the card's last scan. Check them before you submit.",
                                accent: .orange,
                                density: .compact)
                        }
                        cardSection
                        detailsSection
                    }
                    .padding(16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("SD Card \(cardNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submit() }
                        .disabled(isSubmitting)
                }
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) { isSubmitting = false }
            } message: {
                Text(alertMessage)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: load)
        // LISTENER TOKEN SYMMETRY (audit round), the same as the other three NFC
        // screens: this sheet subscribes the shared schools channel and never
        // handed it back. Generation-guarded, so a teardown for channels a later
        // screen owns is a no-op.
        .onDisappear {
            DatabaseManager.shared.stopListening(ifGeneration: listenerGeneration)
        }
    }

    // MARK: - Sections

    private var cardSection: some View {
        AmbientFormSection(title: "Card information",
                           status: "#\(cardNumber)",
                           statusTint: tint) {
            VStack(alignment: .leading, spacing: 6) {
                Text(lastSeenLine)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Status pre-selects the next step in the ring. A card sitting in Camera Bag or Personal lands on Camera or Cleared rather than on a successor — deliberately.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var lastSeenLine: String {
        guard let last = lastRecord else { return "No earlier scan on this card." }
        var parts = ["Last seen", last.status]
        if !last.school.isEmpty { parts.append(last.school) }
        parts.append(Formatters.mediumDateTime.string(from: last.timestamp))
        return parts.joined(separator: " · ")
    }

    private var detailsSection: some View {
        AmbientFormSection(title: "Details",
                           status: selectedStatus.isEmpty ? "required" : selectedStatus,
                           statusTint: selectedStatus.isEmpty ? .orange : nil) {
            VStack(alignment: .leading, spacing: 10) {
                if schools.isEmpty {
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
                    ForEach(localStatuses, id: \.self) { status in
                        Text(status).tag(status)
                    }
                }
                // If "Cleared" is picked, default the school to "Iconik"
                .onChange(of: selectedStatus) { newVal in
                    if newVal.lowercased() == "cleared" {
                        selectedSchool = "Iconik"
                    }
                }

                // Conditionally show toggles if status is "uploaded". The
                // hardcoded organization gate is KEPT.
                if selectedStatus.lowercased() == "uploaded",
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

    // MARK: - Behaviour

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        let jasonValue = uploadedFromJasonsHouse ? "Yes" : ""
        let andyValue = uploadedFromAndysHouse ? "Yes" : ""

        onSubmit(cardNumber, storedUserFirstName, jasonValue, andyValue) { success, failure in
            DispatchQueue.main.async {
                isSubmitting = false
                if success {
                    dismiss()
                } else {
                    // The caller's own words when it has them — a validation
                    // rejection names the field that is empty, which the generic
                    // sentence cannot.
                    alertMessage = failure ?? (alertMessage.isEmpty ? "Submission failed. Please try again." : alertMessage)
                    showAlert = true
                }
            }
        }
    }

    private func load() {
        updateDefaults()

        // Load schools from cached data and listen for live updates
        if let data = UserDefaults.standard.data(forKey: "nfcSchools"),
           let cachedSchools = try? JSONDecoder().decode([SchoolItem].self, from: data) {
            self.schools = cachedSchools
        }
        let schoolOrgID = userManager.currentUserOrganizationID
        if !schoolOrgID.isEmpty {
            DatabaseManager.shared.listenForSchoolsData(forOrgID: schoolOrgID) { records in
                DispatchQueue.main.async {
                    self.schools = records
                    // Ensure a default school is selected if none exists.
                    if selectedSchool.isEmpty {
                        if let firstSchool = schools.sorted(by: { $0.name < $1.name }).first?.name {
                            selectedSchool = firstSchool
                        }
                    }
                }
            }

            // Recorded AFTER subscribing, which is what makes the token mean
            // "the channel I started".
            listenerGeneration = DatabaseManager.shared.currentNFCListenerGeneration
        }
    }

    private func updateDefaults() {
        if let last = lastRecord {
            // If the last record was "cleared", default the school to "Iconik"
            if last.status.lowercased() == "cleared" {
                selectedSchool = "Iconik"
            } else {
                selectedSchool = last.school
            }

            selectedStatus = NFCRoutingRules.nextSDStatus(after: last.status, variant: .form)
        } else {
            // If no last record exists, and no school has been selected, set the
            // default to the first available school.
            if selectedSchool.isEmpty {
                if let firstSchool = schools.sorted(by: { $0.name < $1.name }).first?.name {
                    selectedSchool = firstSchool
                }
            }
        }
    }
}
