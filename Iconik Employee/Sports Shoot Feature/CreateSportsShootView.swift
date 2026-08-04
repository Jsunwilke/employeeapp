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
    @State private var sportName: String = ""
    @State private var seasonType: String = "Fall Sports"
    @State private var shootDate = Date()
    @State private var location: String = ""
    @State private var photographer: String = ""
    @State private var additionalNotes: String = ""
    
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
                Section(header: Text("Scheduled Sports Session")) {
                    Picker("Select Session", selection: $selectedSession) {
                        Text("Select a sports session").tag(nil as Session?)
                        ForEach(sessions, id: \.id) { session in
                            VStack(alignment: .leading) {
                                Text(session.schoolName)
                                    .font(.system(size: 14))
                                Text(session.date)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            .tag(session as Session?)
                        }
                    }
                    .onChange(of: selectedSession) { newSession in
                        guard let session = newSession else { return }
                        applyDerivedSessionFields(session)
                    }

                    if sessions.isEmpty && !isLoading {
                        Text("No unused sports sessions are available in the next two weeks.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if selectedSession != nil {
                        Text("School, date, and location come from the scheduled session.")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }

                // Basic information section
                Section(header: Text("Basic Information")) {
                    LabeledContent("School", value: selectedSession?.schoolName ?? "Select a session above")
                    
                    // Season type picker
                    Picker("Season/Type", selection: $seasonType) {
                        ForEach(seasonTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    
                    TextField("Sport Name (Optional)", text: $sportName)
                    DatePicker("Shoot Date", selection: $shootDate, displayedComponents: .date)
                        .disabled(true)
                    TextField("Location", text: $location)
                        .disabled(true)
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
                    .disabled(isLoading || selectedSession == nil)

                    if selectedSession == nil {
                        Text("Required: Scheduled sports session")
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

        guard let session = selectedSession else {
            alertTitle = "Error"
            alertMessage = "Select a scheduled sports session before creating the job."
            showAlert = true
            return
        }

        guard session.organizationID == storedUserOrganizationID else {
            selectedSession = nil
            alertTitle = "Sessions Changed"
            alertMessage = "Reload the Sports Job form and select a session for the current organization."
            showAlert = true
            return
        }

        guard let sessionDate = session.startDate else {
            alertTitle = "Error"
            alertMessage = "The selected session does not have a valid date."
            showAlert = true
            return
        }

        let sessionLocation = derivedLocation(for: session)
        applyDerivedSessionFields(session)

        // Create a new SportsShoot with UUID
        let newShoot = SportsShoot(
            id: UUID(),
            organizationId: storedUserOrganizationID,
            schoolName: session.schoolName,
            schoolId: session.schoolId,
            sportName: sportName,
            seasonType: seasonType,
            shootDate: sessionDate,
            location: sessionLocation,
            photographer: photographer,
            additionalNotes: additionalNotes,
            sessionId: session.id,
            isArchived: false
        )

        // Create sports shoot via service (requires network)
        isLoading = true
        Task {
            do {
                try await SportsShootService.shared.createSportsShoot(newShoot)
                await MainActor.run {
                    isLoading = false
                    alertTitle = "Success"
                    alertMessage = "Sports shoot created successfully."
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    alertTitle = "Error"
                    let rawError = String(describing: error).lowercased()
                    alertMessage = rawError.contains("23505") || rawError.contains("duplicate key")
                        ? "That scheduled session already has a Sports Job."
                        : "Failed to create sports shoot. \(error.userFacingMessage)"
                    showAlert = true
                }
            }
        }
    }

    private func loadSessions() {
        guard !storedUserOrganizationID.isEmpty else { return }
        let organizationID = storedUserOrganizationID

        isLoading = true
        Task {
            do {
                async let fetchedSessions = SessionService.shared.fetchSessions(
                    organizationID: organizationID,
                    forceRefresh: true
                )
                async let existingShoots = SportsShootService.shared.fetchAllSportsShoots(
                    forOrganization: organizationID
                )

                let (upcomingSessions, sportsShoots) = try await (fetchedSessions, existingShoots)
                let usedSessionIDs = Set(sportsShoots.compactMap { shoot in
                    normalizedSessionID(shoot.sessionId)
                }.filter { !$0.isEmpty })
                let now = Date()
                let twoWeeksFromNow = Calendar.current.date(
                    byAdding: .weekOfYear,
                    value: 2,
                    to: now
                ) ?? now
                let availableSessions = upcomingSessions.filter { session in
                    guard let sessionDate = session.startDate else { return false }
                    return session.organizationID == organizationID
                        && sessionDate >= now
                        && sessionDate <= twoWeeksFromNow
                        && isSportsSession(session)
                        && !usedSessionIDs.contains(normalizedSessionID(session.id))
                }

                await MainActor.run {
                    guard storedUserOrganizationID == organizationID else {
                        sessions = []
                        selectedSession = nil
                        isLoading = false
                        return
                    }
                    sessions = availableSessions
                    if let selectedSession,
                       !availableSessions.contains(where: { $0.id == selectedSession.id }) {
                        self.selectedSession = nil
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    sessions = []
                    selectedSession = nil
                    isLoading = false
                    alertTitle = "Couldn't Load Sessions"
                    alertMessage = error.userFacingMessage
                    showAlert = true
                }
            }
        }
    }

    private func applyDerivedSessionFields(_ session: Session) {
        if let sessionDate = session.startDate {
            shootDate = sessionDate
        }
        location = derivedLocation(for: session)
    }

    private func derivedLocation(for session: Session) -> String {
        guard let sessionLocation = session.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionLocation.isEmpty else {
            return session.schoolName
        }
        return sessionLocation
    }

    private func normalizedSessionID(_ sessionID: String?) -> String {
        sessionID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func isSportsSession(_ session: Session) -> Bool {
        let sportsTypes: Set<String> = ["sports", "sports_photography"]
        return session.sessionType.contains { sessionType in
            sportsTypes.contains(normalizedSessionID(sessionType))
        }
    }
}

struct CreateSportsShootView_Previews: PreviewProvider {
    static var previews: some View {
        CreateSportsShootView(onComplete: { _ in })
    }
}
