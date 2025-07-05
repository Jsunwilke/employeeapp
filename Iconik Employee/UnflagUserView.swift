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
    
    var body: some View {
        NavigationView {
            VStack {
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
            .whereField("isFlagged", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else {
                    errorMessage = "No flagged users found."
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

