import SwiftUI
import Supabase

struct CreateSportsShootView: View {
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    // PowerSync for connectivity status
    @StateObject private var powerSync = PowerSyncManager.shared

    // Match the expected function signature
    let onComplete: (_ success: Bool) -> Void

    // Form fields
    @State private var selectedSession: Session?
    @State private var sessions: [Session] = []
    @State private var selectedSchool: School?
    @State private var schools: [School] = []
    @State private var sportName: String = ""
    @State private var seasonType: String = "Fall Sports"
    @State private var shootDate = Date()
    @State private var location: String = ""
    @State private var photographer: String = ""
    @State private var additionalNotes: String = ""
    @State private var linkToSession: Bool = false
    
    // Season type options
    private let seasonTypes = ["Fall Sports", "Winter Sports", "Spring Sports", "League"]
    
    // State
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    init(onComplete: @escaping (_ success: Bool) -> Void) {
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Session linking section (optional)
                Section(header: Text("Link to Session (Optional)")) {
                    Toggle("Link to upcoming session", isOn: $linkToSession)

                    if linkToSession {
                        Picker("Select Session", selection: $selectedSession) {
                            Text("No Session").tag(nil as Session?)
                            ForEach(sessions, id: \.id) { session in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(session.schoolName)
                                            .font(.system(size: 14))
                                        Text(session.date ?? "")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                }
                                .tag(session as Session?)
                            }
                        }
                        .onChange(of: selectedSession) { newSession in
                            // Auto-populate fields from selected session
                            if let session = newSession {
                                // Find and select the matching school
                                if let school = schools.first(where: { $0.id == session.schoolId }) {
                                    selectedSchool = school
                                } else if !session.schoolName.isEmpty {
                                    // Try to match by name if ID doesn't match
                                    selectedSchool = schools.first(where: { $0.value == session.schoolName })
                                }

                                // Set date from session
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy-MM-dd"
                                if let date = formatter.date(from: session.date) {
                                    shootDate = date
                                }

                                // Set location from session
                                if let loc = session.location, !loc.isEmpty {
                                    location = loc
                                }
                            }
                        }

                        if selectedSession != nil {
                            Text("Fields auto-populated from session")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }

                // Basic information section
                Section(header: Text("Basic Information")) {
                    // School picker
                    Picker("School", selection: $selectedSchool) {
                        Text("Select School").tag(nil as School?)
                        ForEach(schools, id: \.id) { school in
                            Text(school.value).tag(school as School?)
                        }
                    }
                    .disabled(linkToSession && selectedSession != nil)
                    
                    // Season type picker
                    Picker("Season/Type", selection: $seasonType) {
                        ForEach(seasonTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    
                    TextField("Sport Name (Optional)", text: $sportName)
                    DatePicker("Shoot Date", selection: $shootDate, displayedComponents: .date)
                    TextField("Location", text: $location)
                    TextField("Photographer", text: $photographer)
                }
                
                // Notes section
                Section(header: Text("Additional Notes")) {
                    TextEditor(text: $additionalNotes)
                        .frame(minHeight: 100)
                }
                
                // Create button section
                Section {
                    Button(action: {
                        createSportsShoot()
                    }) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Create Sports Shoot")
                                .bold()
                                .foregroundColor(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isLoading || selectedSchool == nil)

                    // Debug info
                    if selectedSchool == nil {
                        Text("Required: School")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Sports Shoot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        if alertTitle == "Success" {
                            onComplete(true)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                )
            }
            .onAppear {
                loadSchools()
                loadSessions()
            }
        }
    }
    
    private func createSportsShoot() {
        guard !storedUserOrganizationID.isEmpty else {
            alertTitle = "Error"
            alertMessage = "No organization ID found. Please sign in again."
            showAlert = true
            return
        }

        guard let school = selectedSchool else {
            alertTitle = "Error"
            alertMessage = "School is required."
            showAlert = true
            return
        }

        // Create a new SportsShoot with UUID
        let newShoot = SportsShoot(
            id: UUID(),
            organizationId: storedUserOrganizationID,
            schoolName: school.value,
            schoolId: school.id,
            sportName: sportName,
            seasonType: seasonType,
            shootDate: shootDate,
            location: location,
            photographer: photographer,
            additionalNotes: additionalNotes,
            sessionId: linkToSession ? selectedSession?.id : nil,
            isArchived: false
        )

        // Create sports shoot via service (requires network)
        Task {
            do {
                try await SportsShootService.shared.createSportsShoot(newShoot)
                await MainActor.run {
                    alertTitle = "Success"
                    alertMessage = "Sports shoot created successfully."
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    alertTitle = "Error"
                    alertMessage = "Failed to create sports shoot: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func loadSchools() {
        guard !storedUserOrganizationID.isEmpty else { return }

        Task {
            do {
                schools = try await SchoolService.shared.getSchools(organizationID: storedUserOrganizationID)
            } catch {
            }
        }
    }

    private func loadSessions() {
        guard !storedUserOrganizationID.isEmpty else { return }

        Task {
            do {
                let fetchedSessions = try await SportsShootService.shared.fetchUpcomingSessions(forOrganization: storedUserOrganizationID)
                await MainActor.run {
                    self.sessions = fetchedSessions
                }
            } catch {
                print("Failed to load sessions: \(error)")
            }
        }
    }
}

struct CreateSportsShootView_Previews: PreviewProvider {
    static var previews: some View {
        CreateSportsShootView(onComplete: { _ in })
    }
}
