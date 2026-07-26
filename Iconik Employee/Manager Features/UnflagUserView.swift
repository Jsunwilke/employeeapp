import SwiftUI

// Model representing a flagged user.
struct FlaggedUser: Identifiable, Hashable {
    let id: String
    let name: String
    let flagNote: String
}

struct UnflagUserView: View {
    @State private var flaggedUsers: [FlaggedUser] = []
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    
    // User role from AppStorage
    @AppStorage("userRole") private var storedUserRole: String = "employee"
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
    
    // Phase 7 RBAC — unflagging team members is a users-edit operation
    var hasPermission: Bool {
        return Permissions.has("users", level: .edit)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if !hasPermission {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        Text("Access Denied")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Only administrators and managers can unflag users.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    }
                    if !successMessage.isEmpty {
                        Text(successMessage)
                            .foregroundColor(.green)
                            .padding()
                    }
                    
                    if flaggedUsers.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            Text("No Flagged Users")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("All users are currently in good standing")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(flaggedUsers) { user in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(user.name)
                                        .font(.headline)
                                    Text("Flag Note: \(user.flagNote)")
                                        .font(.subheadline)
                                }
                                Spacer()
                                Button(action: {
                                    unflagUser(user)
                                }) {
                                    Text("Unflag")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Unflag Users")
            .homeToolbarItem()
            // Room for the app's floating bar. Applied inside this screen's own
            // navigation container, because the shell cannot reach into a self-nav
            // feature (AMB.4).
            .tabBarClearance()
            .onAppear {
                loadFlaggedUsers()
            }
        }
    }
    
    // Fetch flagged users from Supabase.
    func loadFlaggedUsers() {
        Task {
            do {
                let members = try await TeamService.shared.getFlaggedUsers(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    flaggedUsers = members.map { member in
                        FlaggedUser(
                            id: member.id,
                            name: member.firstName,
                            flagNote: member.flagNote ?? ""
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // Unflag the selected user.
    func unflagUser(_ user: FlaggedUser) {
        // Check permission first
        guard hasPermission else {
            errorMessage = "You don't have permission to unflag users."
            return
        }

        Task {
            do {
                try await TeamService.shared.unflagUser(userId: user.id)
                await MainActor.run {
                    successMessage = "\(user.name) has been unflagged."
                    // Refresh the list.
                    loadFlaggedUsers()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct UnflagUserView_Previews: PreviewProvider {
    static var previews: some View {
        UnflagUserView()
    }
}

