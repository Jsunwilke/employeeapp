import SwiftUI
import Firebase
import FirebaseMessaging

struct RootView: View {
    @State private var isSignedIn = false
    @StateObject private var userManager = UserManager.shared
    @StateObject private var profileService = UserProfileService.shared
    
    var body: some View {
        Group {
            if isSignedIn {
                MainEmployeeView(isSignedIn: $isSignedIn)
            } else {
                SignInView(isSignedIn: $isSignedIn)
            }
        }
        .onAppear {
            if Auth.auth().currentUser != nil {
                isSignedIn = true
                // Refresh user profile when already signed in
                profileService.refreshCurrentUserProfile()
                userManager.initializeOrganizationID()
                // Ensure FCM token is saved on app startup
                requestAndSaveFCMToken()
            }
            
            Auth.auth().addStateDidChangeListener { _, user in
                isSignedIn = (user != nil)
                
                if user != nil {
                    // Refresh user profile when signing in
                    profileService.refreshCurrentUserProfile()
                    userManager.initializeOrganizationID()
                    // Save FCM token when user signs in
                    requestAndSaveFCMToken()
                }
            }
        }
    }
    
    /// Request FCM token and save it to Firestore
    private func requestAndSaveFCMToken() {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("No authenticated user to save FCM token for")
            return
        }
        
        // Get the current FCM token
        Messaging.messaging().token { token, error in
            if let error = error {
                print("Error fetching FCM token: \(error.localizedDescription)")
                return
            }
            
            guard let token = token else {
                print("No FCM token available")
                return
            }
            
            print("FCM token retrieved: \(token)")
            
            // Save token to Firestore
            let db = Firestore.firestore()
            db.collection("users").document(uid).updateData([
                "fcmToken": token,
                "fcmTokenUpdatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("Error updating FCM token in Firestore: \(error.localizedDescription)")
                } else {
                    print("Successfully updated FCM token in Firestore on app startup")
                }
            }
        }
    }
}

