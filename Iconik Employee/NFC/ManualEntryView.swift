import SwiftUI

struct ManualEntryView: View {
    @State private var cardNumber: String = ""
    @State private var selectedSchool: String = ""
    @State private var selectedStatus: String = ""
    @State private var isJobBoxMode: Bool = false
    
    // Optional closure for custom cancel handling
    var onCancel: (() -> Void)?
    
    let localStatuses: [String] = ["Job Box", "Camera", "Envelope", "Uploaded", "Cleared", "Camera Bag", "Personal"]
    let jobBoxStatuses = ["Packed", "Picked Up", "Left Job", "Turned In"]
    
    @State private var schools: [SchoolItem] = []
    @State private var photographerNames: [String] = []
    
    @State private var localPhotographer: String = ""
    @State private var uploadedFromJasonsHouse: Bool = false
    @State private var uploadedFromAndysHouse: Bool = false
    
    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var lastRecord: FirestoreRecord? = nil
    @State private var lastJobBoxRecord: JobBox? = nil
    
    // For session selection
    @State private var selectedSession: Session? = nil
    @State private var showSessionSelection = false
    @State private var availableSessions: [Session] = []
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userManager = UserManager.shared
    @StateObject private var timeTrackingService = TimeTrackingService()
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    
    var body: some View {
        Form {
            // Entry type selection
            Section {
                Picker("Entry Type", selection: $isJobBoxMode) {
                    Text("SD Card").tag(false)
                    Text("Job Box").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
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
            }
            
            // Number input section
            Section(header: Text(isJobBoxMode ? "Job Box Information" : "Card Information")) {
                TextField(isJobBoxMode ? "Enter 4-digit Box Number (3001+)" : "Enter 4-digit Card Number", text: $cardNumber)
                    .keyboardType(.numberPad)
                    .onChange(of: cardNumber) { newValue in
                        if newValue.count == 4, Int(newValue) != nil {
                            if isJobBoxMode {
                                fetchLastJobBoxRecord(for: newValue)
                            } else {
                                fetchLastRecord(for: newValue)
                            }
                        } else {
                            selectedSchool = ""
                            selectedStatus = isJobBoxMode ? "" : ""
                        }
                    }
            }
            
            // Photographer section
            Section(header: Text("Photographer")) {
                Picker("Photographer", selection: $localPhotographer) {
                    ForEach(photographerNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }
            
            if cardNumber.count == 4, Int(cardNumber) != nil {
                // Session selection for Job Box
                if isJobBoxMode {
                    Section(header: Text("Session Assignment")) {
                        Button(action: {
                            showSessionSelection = true
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Select Session")
                                        .font(.headline)
                                    
                                    if selectedSession == nil {
                                        Text("Choose from available sessions in the next 2 weeks")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if let session = selectedSession {
                                    VStack(alignment: .trailing) {
                                        Text(session.schoolName)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        
                                        if let dateStr = session.date {
                                            Text(dateStr)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(selectedSession == nil ? .blue : .primary)
                    }
                    .onChange(of: selectedSession) { newSession in
                        if let session = newSession {
                            print("Session selected: \(session.schoolName), schoolId: \(session.schoolId ?? "nil")")
                            print("Available schools: \(schools.map { "id: \($0.id), name: \($0.name)" })")
                            
                            // Find the school by ID
                            if let schoolId = session.schoolId,
                               let school = schools.first(where: { $0.id == schoolId }) {
                                // Set the school name from the school record to ensure exact match
                                selectedSchool = school.name
                                print("Found matching school: \(school.name)")
                            } else {
                                // Fallback to session's school name if not found
                                selectedSchool = session.schoolName
                                print("No matching school found, using session school name: \(session.schoolName)")
                            }
                            selectedStatus = "Packed"
                        }
                    }
                }
                
                // Additional information section
                Section(header: Text("Additional Information")) {
                    // School
                    if schools.isEmpty {
                        Text("Loading schools...")
                            .foregroundColor(.gray)
                    } else {
                        Picker("School", selection: $selectedSchool) {
                            Text("Select School").tag("")
                            ForEach(schools.sorted { $0.name < $1.name }) { school in
                                Text(school.name).tag(school.name)
                            }
                        }
                        .disabled(isJobBoxMode && selectedSession != nil)
                    }
                    
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
                    
                    // Conditional toggles for SD Card
                    if !isJobBoxMode && selectedStatus.lowercased() == "uploaded",
                       userManager.currentUserOrganizationID == "T6XeeaUNoOp8VJqq36wi" {
                        Toggle("Uploaded from Jason's house", isOn: $uploadedFromJasonsHouse)
                            .onChange(of: uploadedFromJasonsHouse) { newValue in
                                if newValue { uploadedFromAndysHouse = false }
                            }
                        
                        Toggle("Uploaded from Andy's house", isOn: $uploadedFromAndysHouse)
                            .onChange(of: uploadedFromAndysHouse) { newValue in
                                if newValue { uploadedFromJasonsHouse = false }
                            }
                    }
                }
            } else {
                Section {
                    Text("Enter a valid 4-digit \(isJobBoxMode ? "box" : "card") number to load additional information.")
                        .foregroundColor(.gray)
                }
            }
            
            // Action buttons at the bottom
            Section {
                HStack(spacing: 16) {
                    Button(action: {
                        print("ManualEntryView - Cancel button pressed")
                        if let onCancel = onCancel {
                            onCancel()
                        } else {
                            dismiss()
                        }
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
                        submitData()
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(isSubmitting ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(isSubmitting || cardNumber.count != 4)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle(isJobBoxMode ? "Manual Job Box Entry" : "Manual SD Card Entry")
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Info"),
                  message: Text(alertMessage),
                  dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showSessionSelection) {
            NFCSessionSelectionView(
                sessions: availableSessions,
                selectedSession: $selectedSession,
                isPresented: $showSessionSelection
            )
        }
        .onAppear {
            localPhotographer = storedUserFirstName
            loadInitialData()
        }
    }
    
    func loadInitialData() {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else { 
            print("ManualEntryView: No organization ID found")
            return 
        }
        
        print("ManualEntryView: Loading initial data for org: \(orgID)")
        
        // Load photographers
        if let data = UserDefaults.standard.data(forKey: "photographerNames"),
           let cachedNames = try? JSONDecoder().decode([String].self, from: data) {
            self.photographerNames = cachedNames
            print("ManualEntryView: Loaded \(cachedNames.count) cached photographers")
        }
        FirestoreManager.shared.listenForPhotographers(inOrgID: orgID) { names in
            DispatchQueue.main.async {
                self.photographerNames = names
                print("ManualEntryView: Updated photographers list with \(names.count) names")
            }
        }
        
        // Load schools
        if let data = UserDefaults.standard.data(forKey: "nfcSchools"),
           let cachedSchools = try? JSONDecoder().decode([SchoolItem].self, from: data) {
            self.schools = cachedSchools
            print("ManualEntryView: Loaded \(cachedSchools.count) cached schools")
        }
        FirestoreManager.shared.listenForSchoolsData(forOrgID: orgID) { schoolItems in
            DispatchQueue.main.async {
                self.schools = schoolItems
                print("ManualEntryView: Updated schools list with \(schoolItems.count) schools: \(schoolItems.map { $0.name })")
            }
        }
    }
    
    func loadAvailableSessionsForJobBox() {
        timeTrackingService.getAvailableSessionsForJobBox { sessions in
            DispatchQueue.main.async {
                self.availableSessions = sessions
            }
        }
    }
    
    func fetchLastRecord(for cardNumber: String) {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else { return }
        
        FirestoreManager.shared.fetchRecords(field: "cardNumber", value: cardNumber, organizationID: orgID) { result in
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
        
        FirestoreManager.shared.fetchJobBoxRecords(field: "boxNumber", value: boxNumber, organizationID: orgID) { result in
            switch result {
            case .success(let records):
                let sortedRecords = records.sorted { $0.timestamp > $1.timestamp }
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
            
            let lastStatus = last.status.lowercased()
            if lastStatus == "camera bag" {
                selectedStatus = "Camera"
                return
            }
            if lastStatus == "personal" {
                selectedStatus = "Cleared"
                return
            }
            
            let defaultStatuses = localStatuses.filter {
                let s = $0.lowercased()
                return s != "camera bag" && s != "personal"
            }
            if let index = defaultStatuses.firstIndex(where: { $0.lowercased() == lastStatus }) {
                let nextIndex = (index + 1) % defaultStatuses.count
                selectedStatus = defaultStatuses[nextIndex]
            } else {
                selectedStatus = defaultStatuses.first ?? ""
            }
        } else {
            selectedSchool = ""
            selectedStatus = ""
        }
    }
    
    private func updateJobBoxDefaults() {
        if let last = lastJobBoxRecord {
            selectedSchool = last.school
            
            // If last status was "Turned In", default school to "Iconik"
            if last.status == .turnedIn {
                selectedSchool = "Iconik"
            }
            
            // Calculate next status in the cycle
            if let currentIndex = jobBoxStatuses.firstIndex(where: { $0 == last.status.rawValue }) {
                let nextIndex = (currentIndex + 1) % jobBoxStatuses.count
                selectedStatus = jobBoxStatuses[nextIndex]
            } else {
                selectedStatus = jobBoxStatuses.first ?? ""
            }
            
            // If there's a shiftUid and we're not in Packed status, try to find the session
            if selectedStatus.lowercased() != "packed" && !last.shiftUid.isEmpty {
                // Find the session in available sessions
                if let matchingSession = availableSessions.first(where: { $0.id == last.shiftUid }) {
                    selectedSession = matchingSession
                }
            }
        } else {
            // Default for new job box
            if selectedSchool.isEmpty {
                if let firstSchool = schools.sorted(by: { $0.name < $1.name }).first?.name {
                    selectedSchool = firstSchool
                }
            }
            selectedStatus = "Packed"
        }
        
        // Load available sessions when in Packed status
        if selectedStatus.lowercased() == "packed" {
            loadAvailableSessionsForJobBox()
        }
    }
    
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
            submitJobBoxData(boxNumber: cardNumber, schoolId: schoolId)
        } else {
            // Submit SD card
            let jasonValue = uploadedFromJasonsHouse ? "Yes" : ""
            let andyValue = uploadedFromAndysHouse ? "Yes" : ""
            submitSDCardData(cardNumber: cardNumber, jasonValue: jasonValue, andyValue: andyValue)
        }
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
        
        FirestoreManager.shared.saveRecord(
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
            case .success:
                alertMessage = "SD Card record saved"
                showAlert = true
                isSubmitting = false
                
            case .failure(let error):
                alertMessage = "Failed to save record: \(error.localizedDescription)"
                showAlert = true
                isSubmitting = false
            }
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
        
        // Determine the shiftUid
        let effectiveShiftUid: String?
        if selectedStatus.lowercased() == "packed" && selectedSession != nil {
            // For Packed status, use the selected session
            effectiveShiftUid = selectedSession?.id
        } else if selectedStatus.lowercased() != "packed" && lastJobBoxRecord?.shiftUid != nil {
            // For other statuses, maintain the existing shiftUid
            effectiveShiftUid = lastJobBoxRecord?.shiftUid
        } else {
            effectiveShiftUid = nil
        }
        
        FirestoreManager.shared.saveJobBoxRecord(
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
            case .success:
                alertMessage = "Job Box record saved"
                showAlert = true
                isSubmitting = false
                
            case .failure(let error):
                alertMessage = "Failed to save job box record: \(error.localizedDescription)"
                showAlert = true
                isSubmitting = false
            }
        }
    }
}