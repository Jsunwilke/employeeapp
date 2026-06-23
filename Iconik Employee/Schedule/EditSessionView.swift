import SwiftUI

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
        // Phase 7 RBAC — managers + admins have schedule edit
        Permissions.has("schedule", level: .edit)
    }
    
    var body: some View {
        NavigationView {
            Group {
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
                } else {
                    ZStack {
                        SessionFormView(
                            formData: $formData,
                            schools: schoolService.schools,
                            teamMembers: teamService.teamMembers,
                            sessionTypes: {
                                // Convert SessionTypeDefinition array to SessionType array with proper ordering
                                var types = organizationService.sessionTypes.map { SessionType(id: $0.id, name: $0.name, color: $0.color, order: 0) }
                                // Ensure "Other" is available
                                if !types.contains(where: { $0.id == "other" }) {
                                    types.append(SessionType(id: "other", name: "Other", color: "#000000", order: 9999))
                                }
                                return types
                            }(),
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
                
                if canEditSessions {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            updateSession()
                        }
                        .fontWeight(.semibold)
                        .disabled(isLoading)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
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
            formData.photographerIds.insert(photographer.id)

            if let notes = photographer.notes, !notes.isEmpty {
                formData.photographerNotes[photographer.id] = notes
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
                    // `session` is the per-day occurrence the user opened; its `date` is
                    // the tapped day. Pass that day's row id so a multi-day edit updates
                    // the correct day instead of overwriting day 1.
                    dayId: session.day(onDate: session.date ?? "")?.id,
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
        EditSessionView(session: Session(
            id: "preview",
            organization_id: "org123",
            school_id: "school123",
            school_name: "Sample School",
            date: "2024-01-15",
            start_time: "09:00",
            end_time: "12:00",
            session_types: ["sports"],
            photographers: [],
            status: "scheduled",
            session_color: "#3b82f6",
            is_published: true,
            created_at: Date()
        ))
    }
}