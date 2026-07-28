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
        // FLG.2: flagged_by is no longer sent from here -- the flag_user database function
        // records auth.uid() itself, so the attribution cannot be spoofed and the old
        // "unknown" fallback can no longer be persisted. This guard stays because the screen
        // should still refuse to act when there is no session, rather than surfacing a
        // permission error from the server.
        guard currentUserID != "unknown" else {
            errorMessage = "You appear to be signed out. Sign in again before flagging."
            return
        }
        errorMessage = ""
        successMessage = ""

        Task {
            do {
                try await TeamService.shared.flagUser(
                    userId: target.id,
                    note: flagNote
                )

                // The push is fired by the trg_user_flagged_notification database trigger on
                // the is_flagged transition, not from here -- sending from the app would mean
                // calling send-notification, and that function is locked to service-role
                // callers because it accepts an arbitrary recipient list and arbitrary text
                // on a database shared with the web app and Captura.
                //
                // CORRECTION (FLG.1): the comment here previously said PSH.1 had done this.
                // It had not. PSH.1 created that trigger against flag_note and flagged_by,
                // which did not exist, then DROPPED it live when testing showed it would
                // raise and roll back every is_flagged update on a shared table. The trigger
                // is real as of FLG.1, which added the columns first:
                // 20260727_flg1_user_flag_notification.sql. Its payload follows PSH.1's own,
                // recovered from the sendFlagNotification function deleted from this file in
                // d61d475 -- same title, type and data, and the same note as the body except
                // that the trigger caps it at 300 characters so an over-long note cannot
                // blow the 4KB APNs payload limit invisibly.
                await MainActor.run {
                    successMessage = "\(target.name) flagged successfully."
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
