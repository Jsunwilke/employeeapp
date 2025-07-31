import SwiftUI
import Firebase

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
            }
            
            Auth.auth().addStateDidChangeListener { _, user in
                isSignedIn = (user != nil)
                
                if user != nil {
                    // Refresh user profile when signing in
                    profileService.refreshCurrentUserProfile()
                    userManager.initializeOrganizationID()
                }
            }
        }
    }
}

