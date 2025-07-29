import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    var body: some View {
        List {
            // Account Info
            NavigationLink(destination: EmployeeInfoView()) {
                Label("Account Info", systemImage: "person.crop.circle")
            }
            
            // PTO Balance
            NavigationLink(destination: PTOBalanceView()) {
                Label("PTO Balance", systemImage: "clock.fill")
            }
            
            // Profile Photo
            NavigationLink(destination: ProfilePhotoView()) {
                Label("Upload Profile Photo", systemImage: "photo")
            }
            
            // School Info
            NavigationLink(destination: SchoolInfoListView()) {
                Label("School Info", systemImage: "building.2")
            }
            
            // Logout
            Button("Logout") {
                do {
                    try Auth.auth().signOut()
                } catch {
                    print("Error signing out: \(error.localizedDescription)")
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Settings")
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

