import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseFunctions

/// A simple model for a user in the same organization.
struct Photographer: Identifiable, Hashable {
    let id: String      // User's UID (Firestore doc ID)
    let name: String    // User's first name
}

struct FlagUserView: View {
    // Current user (flagger)'s UID.
    var currentUserID: String {
        Auth.auth().currentUser?.uid ?? "unknown"
    }
    
    // The current user's organization, from AppStorage.
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
    
    // List of potential users to flag.
    @State private var photographers: [Photographer] = []
    @State private var selectedPhotographer: Photographer? = nil
    
    // Note for why we're flagging.
    @State private var flagNote: String = ""
    
    // Error/success feedback.
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Flag a Photographer")
                .font(.headline)
            
            if photographers.isEmpty {
                Text("Loading users...")
                    .onAppear(perform: loadPhotographers)
            } else {
                Picker("Select a User to Flag", selection: $selectedPhotographer) {
                    ForEach(photographers) { user in
                        Text(user.name).tag(user as Photographer?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
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
    
    /// Load photographers from Firestore, excluding current user.
    func loadPhotographers() {
        let db = Firestore.firestore()
        db.collection("users")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID)
            .getDocuments { snapshot, error in
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else { return }
                
                var temp: [Photographer] = []
                for doc in docs {
                    // Exclude self.
                    if doc.documentID == currentUserID { continue }
                    if let firstName = doc.data()["firstName"] as? String {
                        let user = Photographer(id: doc.documentID, name: firstName)
                        temp.append(user)
                    }
                }
                temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                photographers = temp
            }
    }
    
    /// Flag the selected user by setting isFlagged to true and calling the callable function.
    func flagSelectedUser() {
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
        
        let db = Firestore.firestore()
        db.collection("users").document(target.id)
            .updateData([
                "isFlagged": true,
                "flagNote": flagNote,
                "flaggedBy": currentUserID
            ]) { error in
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    successMessage = "\(target.name) flagged successfully."
                    
                    // Now call the callable Cloud Function to send the push notification.
                    let functions = Functions.functions()
                    functions.httpsCallable("sendFlagNotificationCallable").call([
                        "targetUserID": target.id,
                        "flagNote": flagNote,
                        "flaggedBy": self.currentUserID
                    ]) { result, error in
                        if let error = error {
                            print("Error calling sendFlagNotificationCallable: \(error.localizedDescription)")
                        } else if let data = result?.data as? [String: Any] {
                            print("Notification callable function result: \(data)")
                        }
                    }
                }
            }
    }
}

