import SwiftUI
import Supabase

struct FlaggedStatusView: View {
    // Assume the current user's UID is available.
    var currentUserID: String

    // These properties might be loaded from Supabase in your app's user listener.
    @State private var isFlagged: Bool = false
    @State private var flagNote: String = ""

    // For unflag request.
    @State private var unflagRequestNote: String = ""
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""

    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    var body: some View {
        VStack(spacing: 20) {
            if isFlagged {
                Text("Your account has been flagged!")
                    .font(.headline)
                    .foregroundColor(.red)
                Text("Flag note: \(flagNote)")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("Enter a note to request unflag", text: $unflagRequestNote)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                Button("Request Unflag") {
                    requestUnflag()
                }
                .padding()
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
                if !successMessage.isEmpty {
                    Text(successMessage)
                        .foregroundColor(.green)
                }
            } else {
                Text("Your account is in good standing.")
            }
        }
        .padding()
        .onAppear(perform: loadFlagStatus)
    }

    func loadFlagStatus() {
        Task {
            do {
                // Use snake_case field names for Supabase
                struct UserFlagData: Decodable {
                    let is_flagged: Bool?
                    let flag_note: String?
                }

                let response: UserFlagData = try await supabase
                    .from("users")
                    .select("is_flagged, flag_note")
                    .eq("id", value: currentUserID.lowercased())
                    .single()
                    .execute()
                    .value

                await MainActor.run {
                    self.isFlagged = response.is_flagged ?? false
                    self.flagNote = response.flag_note ?? ""
                }
            } catch {
                print("Error loading flag status: \(error.localizedDescription)")
            }
        }
    }

    func requestUnflag() {
        Task {
            do {
                // Use snake_case field names for Supabase
                let updateData: [String: AnyJSON] = [
                    "unflag_request_note": .string(unflagRequestNote),
                    "is_unflag_requested": .bool(true)
                ]
                try await supabase
                    .from("users")
                    .update(updateData)
                    .eq("id", value: currentUserID.lowercased())
                    .execute()

                await MainActor.run {
                    self.successMessage = "Unflag request sent. Please wait for approval."
                    // TODO: Trigger a notification to the flagging user (or admin) via push notification
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
