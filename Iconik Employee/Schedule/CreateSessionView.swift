import SwiftUI

struct CreateSessionView: View {
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
    
    private var canCreateSessions: Bool {
        // Phase 7 RBAC — managers + admins have schedule edit
        Permissions.has("schedule", level: .edit)
    }
    
    var body: some View {
        NavigationView {
            Group {
                if !canCreateSessions {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("Access Denied")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Only administrators and managers can create sessions.")
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
                            isEditing: false
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
            .navigationTitle("Create Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
                
                if canCreateSessions {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Create") {
                            createSession()
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
    
    // MARK: - Session Creation
    
    private func createSession() {
        // Validate input
        validationErrors = SessionService.shared.validateSessionInput(formData: formData)
        
        if !validationErrors.isEmpty {
            errorMessage = validationErrors.values.joined(separator: "\n")
            showError = true
            return
        }
        
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified() else {
            errorMessage = "User not authenticated"
            showError = true
            return
        }

        isLoading = true

        Task {
            do {
                // Get user info from UserDefaults
                let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
                let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
                let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                let currentUserName = fullName.isEmpty ? "Unknown User" : fullName
                let currentUserEmail = UserDefaults.standard.string(forKey: "userEmail") ?? ""

                let sessionId = try await SessionService.shared.createSession(
                    organizationID: organizationID,
                    formData: formData,
                    currentUserID: currentUserId,
                    currentUserName: currentUserName,
                    currentUserEmail: currentUserEmail,
                    teamMembers: teamService.teamMembers,
                    schools: schoolService.schools
                )
                
                print("✅ Created session with ID: \(sessionId)")
                
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

struct CreateSessionView_Previews: PreviewProvider {
    static var previews: some View {
        CreateSessionView()
    }
}