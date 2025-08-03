import SwiftUI
import Firebase
import FirebaseFirestore

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
    
    // Check if user has permission to unflag
    var hasPermission: Bool {
        return storedUserRole == "admin" || storedUserRole == "manager"
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
            .onAppear {
                loadFlaggedUsers()
            }
        }
    }
    
    // Fetch flagged users from Firestore.
    func loadFlaggedUsers() {
        let db = Firestore.firestore()
        db.collection("users")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID)
            .whereField("isFlagged", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else {
                    return
                }
                flaggedUsers = docs.compactMap { doc in
                    let data = doc.data()
                    if let firstName = data["firstName"] as? String {
                        let note = data["flagNote"] as? String ?? ""
                        return FlaggedUser(id: doc.documentID, name: firstName, flagNote: note)
                    }
                    return nil
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
        
        let db = Firestore.firestore()
        db.collection("users").document(user.id)
            .updateData([
                "isFlagged": false,
                "flagNote": "",
                "flaggedBy": FieldValue.delete()
            ]) { error in
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    successMessage = "\(user.name) has been unflagged."
                    // Refresh the list.
                    loadFlaggedUsers()
                }
            }
    }
}

struct UnflagUserView_Previews: PreviewProvider {
    static var previews: some View {
        UnflagUserView()
    }
}

