import SwiftUI
import FirebaseAuth

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
        userRole == "admin" || userRole == "manager"
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
                            sessionTypes: organizationService.getOrganizationSessionTypes(
                                organization: Organization(
                                    id: organizationID,
                                    name: "",
                                    sessionTypes: organizationService.sessionTypes.map { SessionType(id: $0.id, name: $0.name, color: $0.color, order: 0) },
                                    sessionOrderColors: nil,
                                    enableSessionPublishing: nil,
                                    payPeriodSettings: nil
                                )
                            ),
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
        
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "User not authenticated"
            showError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let sessionId = try await SessionService.shared.createSession(
                    organizationID: organizationID,
                    formData: formData,
                    currentUser: currentUser,
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