import SwiftUI
import FirebaseAuth

struct EditSessionView: View {
    let session: Session
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var schoolService = SchoolService.shared
    @StateObject private var teamService = TeamService.shared
    @StateObject private var organizationService = OrganizationService.shared
    
    @State private var formData = SessionFormData()
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var validationErrors: [String: String] = [:]
    
    @AppStorage("userOrganizationID") private var organizationID: String = ""
    @AppStorage("userRole") private var userRole: String = "employee"
    
    private var canEditSessions: Bool {
        userRole == "admin" || userRole == "manager"
    }
    
    var body: some View {
        NavigationView {
            if !canEditSessions {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Access Denied")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Only administrators and managers can edit sessions.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
                .navigationTitle("Edit Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            } else {
                ZStack {
                    SessionFormView(
                        formData: $formData,
                        schools: schoolService.schools,
                        teamMembers: teamService.teamMembers,
                        sessionTypes: organizationService.getOrganizationSessionTypes(
                            organization: Organization(
                                id: organizationID,
                                name: "",
                                sessionTypes: organizationService.sessionTypes.map { SessionType(id: $0.id, name: $0.name, color: $0.color, order: 0) },
                                sessionOrderColors: nil,
                                enableSessionPublishing: nil
                            )
                        ),
                        isEditing: true
                    )
                    .disabled(isLoading)
                    
                    if isLoading {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                    }
                }
                .navigationTitle("Edit Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .disabled(isLoading)
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            updateSession()
                        }
                        .fontWeight(.semibold)
                        .disabled(isLoading)
                    }
                }
                .alert("Error", isPresented: $showError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage)
                }
            }
        }
        .onAppear {
            Task {
                await loadData()
                populateFormData()
            }
        }
    }
    
    // MARK: - Data Loading
    
    @MainActor
    private func loadData() async {
        guard !organizationID.isEmpty else { return }
        
        await schoolService.loadSchools(organizationID: organizationID)
        await teamService.loadTeamMembers(organizationID: organizationID)
    }
    
    // MARK: - Form Population
    
    private func populateFormData() {
        formData.schoolId = session.schoolId ?? ""
        formData.date = session.date ?? ""
        formData.startTime = session.startTime ?? ""
        formData.endTime = session.endTime ?? ""
        formData.sessionTypes = session.sessionType ?? []
        formData.notes = session.description ?? ""
        formData.status = session.status ?? "scheduled"
        
        // Extract photographer IDs and notes
        for photographer in session.photographers {
            if let photographerId = photographer["id"] as? String {
                formData.photographerIds.insert(photographerId)
                
                if let notes = photographer["notes"] as? String, !notes.isEmpty {
                    formData.photographerNotes[photographerId] = notes
                }
            }
        }
        
        // Check for custom session type
        if formData.sessionTypes.contains("other") {
            // Custom session type might be stored in a separate field
            // For now, we'll leave it empty as it should be in the session data
        }
    }
    
    // MARK: - Session Update
    
    private func updateSession() {
        // Validate input
        validationErrors = SessionService.shared.validateSessionInput(formData: formData)
        
        if !validationErrors.isEmpty {
            errorMessage = validationErrors.values.joined(separator: "\n")
            showError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                try await SessionService.shared.updateSession(
                    sessionId: session.id,
                    formData: formData,
                    teamMembers: teamService.teamMembers,
                    schools: schoolService.schools
                )
                
                print("✅ Updated session with ID: \(session.id)")
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

struct EditSessionView_Previews: PreviewProvider {
    static var previews: some View {
        EditSessionView(session: Session(id: "preview", data: [:]))
    }
}