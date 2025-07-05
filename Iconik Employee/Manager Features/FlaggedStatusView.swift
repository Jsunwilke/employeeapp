import SwiftUI
import Firebase
import FirebaseFirestore

struct FlaggedStatusView: View {
    // Assume the current user's UID is available.
    var currentUserID: String
    
    // These properties might be loaded from Firestore in your app’s user listener.
    @State private var isFlagged: Bool = false
    @State private var flagNote: String = ""
    
    // For unflag request.
    @State private var unflagRequestNote: String = ""
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    
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
        let db = Firestore.firestore()
        db.collection("users").document(currentUserID)
            .addSnapshotListener { snapshot, error in
                if let data = snapshot?.data() {
                    isFlagged = data["isFlagged"] as? Bool ?? false
                    flagNote = data["flagNote"] as? String ?? ""
                }
            }
    }
    
    func requestUnflag() {
        let db = Firestore.firestore()
        let userDocRef = db.collection("users").document(currentUserID)
        
        // Update the document to record the unflag request.
        userDocRef.updateData([
            "unflagRequestNote": unflagRequestNote,
            "isUnflagRequested": true
        ]) { error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                successMessage = "Unflag request sent. Please wait for approval."
                // TODO: Trigger a notification to the flagging user (or admin) via FCM or Cloud Functions.
            }
        }
    }
}

