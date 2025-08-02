import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct JobBoxFormView: View {
    let boxNumber: String
    @Binding var selectedSchool: String
    @Binding var selectedStatus: String
    let lastRecord: JobBox?
    
    var onSubmit: (String, String?, String?, @escaping (Bool) -> Void) -> Void
    var onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userManager = UserManager.shared
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    
    @State private var localPhotographer: String = ""
    @State private var selectedSession: Session? = nil
    @State private var selectedSchoolId: String? = nil
    
    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
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
            FirestoreManager.shared.listenForPhotographers(inOrgID: orgID) { names in
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
            FirestoreManager.shared.listenForSchoolsData(forOrgID: schoolOrgID) { records in
                DispatchQueue.main.async {
                    self.schools = records
                }
            }
        }
        
        // Load sessions
        updateAvailableSessions()
    }
    
    private func updateAvailableSessions() {
        // Get today's sessions for the selected photographer
        let today = Date()
        let calendar = Calendar.current
        
        // Load sessions from Firestore
        let db = Firestore.firestore()
        let orgID = userManager.currentUserOrganizationID
        
        guard !orgID.isEmpty else { return }
        
        // Query for today's sessions
        db.collection("sessions")
            .whereField("organizationID", isEqualTo: orgID)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error loading sessions: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let allSessions = documents.map { doc -> Session in
                    let data = doc.data()
                    return Session(id: doc.documentID, data: data)
                }
                
                self.availableSessions = allSessions.filter { session in
                    // Check if session is today
                    if let sessionDate = session.startDate ?? session.endDate {
                        let isToday = calendar.isDate(sessionDate, inSameDayAs: today)
                        
                        // Check if photographer is assigned
                        let isAssigned = session.photographers.contains { photographerData in
                            if let name = photographerData["name"] as? String {
                                return name.lowercased() == localPhotographer.lowercased()
                            }
                            return false
                        }
                        
                        return isToday && isAssigned
                    }
                    return false
                }
                .sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
                
                // If there's a last record with a shiftUid, try to select that session
                if let lastShiftUid = lastRecord?.shiftUid {
                    selectedSession = availableSessions.first { $0.id == lastShiftUid }
                } else if availableSessions.count == 1 {
                    // Auto-select if only one session
                    selectedSession = availableSessions.first
                }
            }
    }
    
    private func updateDefaults() {
        if let last = lastRecord {
            selectedSchool = last.school
            selectedSchoolId = last.schoolId
            
            // Advance status
            let currentStatusString = last.status.rawValue
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