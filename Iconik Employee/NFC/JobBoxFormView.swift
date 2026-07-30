import SwiftUI

struct JobBoxFormView: View {
    let boxNumber: String
    @Binding var selectedSchool: String
    @Binding var selectedStatus: String
    let lastRecord: JobBox?
    
    var onSubmit: (String, String?, String?, @escaping (Bool) -> Void) -> Void
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
    
    // For data loading
    @State private var photographerNames: [String] = []
    @State private var schools: [SchoolItem] = []
    @State private var availableSessions: [Session] = []
    
    let jobBoxStatuses = ["Packed", "Picked Up", "Left Job", "Turned In"]
    
    var body: some View {
        Form {
                Section(header: Text("Job Box Information")) {
                    Text("Box Number: \(boxNumber)")
                }
                
                Section(header: Text("Details")) {
                    // Photographer Picker
                    Picker("Photographer", selection: $localPhotographer) {
                        ForEach(photographerNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    
                    // Session Picker - Shows today's sessions for photographer
                    if !availableSessions.isEmpty {
                        Picker("Select Session", selection: $selectedSession) {
                            Text("None").tag(nil as Session?)
                            ForEach(availableSessions, id: \.id) { session in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(session.schoolName)
                                            .font(.headline)
                                        Text(formatSessionTime(session))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .tag(session as Session?)
                            }
                        }
                        .onChange(of: selectedSession) { session in
                            if let session = session {
                                selectedSchool = session.schoolName
                                selectedSchoolId = session.schoolId
                                
                                // If this is a new box (no last record), set status to "Packed"
                                if lastRecord == nil {
                                    selectedStatus = "Packed"
                                }
                            }
                        }
                    }
                    
                    // School Display (read-only when session selected)
                    if selectedSession != nil {
                        HStack {
                            Text("School")
                            Spacer()
                            Text(selectedSchool)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // Manual school picker if no session
                        Picker("School", selection: $selectedSchool) {
                            ForEach(schools.sorted { $0.name < $1.name }) { school in
                                Text(school.name).tag(school.name)
                            }
                        }
                    }
                    
                    // Status Picker
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(jobBoxStatuses, id: \.self) { status in
                            Text(status).tag(status)
                        }
                    }
                }
                
                // Action buttons at the bottom
                Section {
                    HStack(spacing: 16) {
                        Button(action: {
                            print("JobBoxFormView - Cancel button pressed")
                            onCancel()
                        }) {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button("Submit") {
                            guard !isSubmitting else { return }
                            isSubmitting = true

                            if selectedStatus == "Picked Up" {
                                // Check the scanned box against what was packed
                                // for the job this pickup will file under.
                                Task { await checkPickupThenSubmit() }
                            } else {
                                performSubmit()
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(isSubmitting ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .disabled(isSubmitting)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
        }
        // These modifiers hang off the Form itself, like ManualEntryView's do.
        // They used to hang off the last Section, which left the two alerts
        // attached to a list row — an attachment point never verified to present.
        .navigationTitle("Job Box Entry")
        .onAppear {
            loadInitialData()
        }
        .onChange(of: localPhotographer) { _ in
            updateAvailableSessions()
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Error"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
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

        onSubmit(localPhotographer, selectedSchoolId, shiftUid) { success in
            DispatchQueue.main.async {
                isSubmitting = false
                if success {
                    dismiss()
                } else {
                    if alertMessage.isEmpty {
                        alertMessage = "Submission failed. Please try again."
                    }
                    showAlert = true
                }
            }
        }
    }

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
        
        // Load sessions
        updateAvailableSessions()
    }
    
    private func updateAvailableSessions() {
        Task {
            do {
                let sessions = try await timeTrackingService.getAvailableSessionsForJobBox()
                await MainActor.run {
                    self.availableSessions = sessions.sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }

                    // Pre-select the box's current trip's session — but a Turned In
                    // record means the trip is OVER, and defaulting to it would seed
                    // the next scan with a finished job (same trap as inheritance).
                    if let last = self.lastRecord, !last.shiftUid.isEmpty, last.jobBoxStatus != .turnedIn {
                        self.selectedSession = self.availableSessions.first { $0.id == last.shiftUid }
                    } else if self.availableSessions.count == 1 {
                        // Auto-select if only one session
                        self.selectedSession = self.availableSessions.first
                    }
                }
            } catch {
                print("Error getting available sessions for job box: \(error)")
            }
        }
    }
    
    private func updateDefaults() {
        if let last = lastRecord {
            selectedSchool = last.school ?? ""
            selectedSchoolId = last.schoolId
            
            // Advance status
            let currentStatusString = last.status
            if let index = jobBoxStatuses.firstIndex(where: { $0 == currentStatusString }) {
                let nextIndex = (index + 1) % jobBoxStatuses.count
                selectedStatus = jobBoxStatuses[nextIndex]
            } else {
                selectedStatus = jobBoxStatuses.first ?? ""
            }
        } else {
            // For new job boxes, don't pre-select values - they'll be set via session selection
            selectedSchool = ""
            selectedSchoolId = nil
            selectedStatus = "" // Will be set to "Packed" when session is selected
        }
    }
    
    private func formatSessionTime(_ session: Session) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        if let startDate = session.startDate, let endDate = session.endDate {
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        } else if let startDate = session.startDate {
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: startDate)
        }
        return ""
    }
}