import SwiftUI

/// A simple model for a user in the same organization.
struct Photographer: Identifiable, Hashable {
    let id: String      // User's UID
    let name: String    // User's first name
}

struct FlagUserView: View {
    // Current user (flagger)'s UID.
    var currentUserID: String {
        UserManager.shared.getCurrentUserIDUnified() ?? "unknown"
    }
    
    // The current user's organization, from AppStorage.
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
    @AppStorage("userRole") private var storedUserRole: String = "employee"
    
    // List of potential users to flag.
    @State private var photographers: [Photographer] = []
    @State private var selectedPhotographer: Photographer? = nil
    
    // Note for why we're flagging.
    @State private var flagNote: String = ""
    
    // Error/success feedback.
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    
    // Phase 7 RBAC — flagging team members is a users-edit operation
    var hasPermission: Bool {
        return Permissions.has("users", level: .edit)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Flag a Photographer")
                .font(.headline)
            
            if !hasPermission {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text("Access Denied")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Only administrators and managers can flag users.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if photographers.isEmpty {
                Text("Loading users...")
                    .onAppear(perform: loadPhotographers)
            } else {
                // Custom dropdown button
                Menu {
                    ForEach(photographers) { user in
                        Button(action: {
                            selectedPhotographer = user
                        }) {
                            Text(user.name)
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedPhotographer?.name ?? "Select a photographer")
                            .foregroundColor(selectedPhotographer == nil ? .gray : .primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            }
            
            TextField("Enter a note for flagging", text: $flagNote)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Button("Flag User") {
                flagSelectedUser()
            }
            .padding()
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if !successMessage.isEmpty {
                Text(successMessage)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Flag User")
    }
    
    /// Load photographers from Supabase, excluding current user.
    func loadPhotographers() {
        Task {
            do {
                let members = try await TeamService.shared.getTeamMembers(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    // Exclude self and map to Photographer model
                    var temp: [Photographer] = []
                    for member in members {
                        if member.id == currentUserID { continue }
                        temp.append(Photographer(id: member.id, name: member.firstName))
                    }
                    temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                    photographers = temp
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// Flag the selected user by setting isFlagged to true and calling the callable function.
    func flagSelectedUser() {
        // Check permission first
        guard hasPermission else {
            errorMessage = "You don't have permission to flag users."
            return
        }

        guard let target = selectedPhotographer else {
            errorMessage = "Please select a user to flag."
            return
        }
        guard !flagNote.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a flag note."
            return
        }
        errorMessage = ""
        successMessage = ""

        Task {
            do {
                try await TeamService.shared.flagUser(
                    userId: target.id,
                    note: flagNote,
                    flaggedBy: currentUserID
                )

                // Send push notification via Supabase Edge Function
                await sendFlagNotification(targetId: target.id, targetName: target.name, note: flagNote)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Send flag notification via Supabase Edge Function
    private func sendFlagNotification(targetId: String, targetName: String, note: String) async {
        do {
            let supabase = SupabaseManager.shared.client

            struct NotificationRequest: Encodable {
                let title: String
                let body: String
                let type: String
                let user_ids: [String]
                let data: [String: String]
            }

            let request = NotificationRequest(
                title: "You've Been Flagged",
                body: note,
                type: "flag_notification",
                user_ids: [targetId.lowercased()],
                data: [
                    "flaggedBy": currentUserID,
                    "note": note
                ]
            )

            try await supabase.functions.invoke(
                "send-notification",
                options: .init(body: request)
            )

            await MainActor.run {
                successMessage = "\(targetName) flagged successfully."
            }
        } catch {
            print("Error sending flag notification: \(error.localizedDescription)")
            // Still show success for the flag itself, notification is secondary
            await MainActor.run {
                successMessage = "\(targetName) flagged successfully."
            }
        }
    }
}

