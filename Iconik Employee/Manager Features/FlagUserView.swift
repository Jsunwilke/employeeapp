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
    ///
    /// PSH.1 (2026-07-27) found this call broken three independent ways at once, each of
    /// which alone was enough to guarantee no notification: the field was named `user_ids`
    /// where the function reads `userIds`, so the recipient list was always empty; the type
    /// was `flag_notification` where the app's own handler only knows `flag`, so even a
    /// delivered payload routed to `.unknown`; and the function was not deployed at all.
    /// The catch block then reported success regardless. The two contract bugs and the
    /// false success are fixed in this file; the function was deployed separately on
    /// 2026-07-27 and verified delivering to a real device.
    private func sendFlagNotification(targetId: String, targetName: String, note: String) async {
        struct NotificationRequest: Encodable {
            let title: String
            let body: String
            let type: String
            // Must match the edge function's field name exactly. It reads `userIds`;
            // sending `user_ids` silently produced an empty recipient list and a
            // "sent 0" that the caller reported as success.
            let userIds: [String]
            let data: [String: String]
        }

        // Must match PushNotificationManager.NotificationType.flag ("flag"), which is what
        // routes the tap to the flag handler on the device.
        let request = NotificationRequest(
            title: "You've Been Flagged",
            body: note,
            type: "flag",
            userIds: [targetId.lowercased()],
            data: [
                "flaggedBy": currentUserID,
                "note": note
            ]
        )

        // The function answers HTTP 200 with success:false when nobody could be reached —
        // for instance when the flagged person has no device token stored. `invoke` only
        // throws on a non-2xx status, so the body has to be read or that case would land in
        // the success branch. This audit caught exactly that: the catch block below was
        // unreachable for the most likely failure.
        struct NotificationResponse: Decodable {
            let success: Bool?
            let reason: String?
            let sent: Int?
        }

        do {
            let supabase = SupabaseManager.shared.client

            let response: NotificationResponse = try await supabase.functions.invoke(
                "send-notification",
                options: .init(body: request)
            )

            let delivered = (response.success ?? false) && (response.sent ?? 0) > 0

            await MainActor.run {
                successMessage = delivered
                    ? "\(targetName) flagged successfully."
                    : "\(targetName) was flagged, but could not be notified."
            }
            if !delivered {
                print("⚠️ [Flag] flag saved, but nobody was notified: \(response.reason ?? "unknown")")
            }
        } catch {
            print("‼️ [Flag] flag saved, but the notification FAILED: \(error.localizedDescription)")
            // The flag itself DID save — that happens before this call and is what matters
            // most. But do not claim the person was told, because they were not. Saying
            // "flagged successfully" on a failed notify is the same class of lie that let
            // this stay broken: every layer reported success while nothing was delivered.
            await MainActor.run {
                successMessage = "\(targetName) was flagged, but could not be notified."
            }
        }
    }
}

