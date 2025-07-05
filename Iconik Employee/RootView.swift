import SwiftUI
import Firebase

struct RootView: View {
    @State private var isSignedIn = false
    
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
            }
            Auth.auth().addStateDidChangeListener { _, user in
                isSignedIn = (user != nil)
            }
        }
    }
}

