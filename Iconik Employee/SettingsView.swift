import SwiftUI
import FirebaseAuth

/// A simple settings view that provides a navigation link to the FlagUserView.
/// In a production app you might show a list of users to flag;
/// for now, this example uses a hard-coded target UID.
struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: FlagUserView(targetUserID: "TARGET_USER_UID", currentUserID: Auth.auth().currentUser?.uid ?? "unknown")) {
                    Label("Flag User", systemImage: "flag.fill")
                }
                // Add other settings options here as needed.
            }
            .navigationTitle("Settings")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
