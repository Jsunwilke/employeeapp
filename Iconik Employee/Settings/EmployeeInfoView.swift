import SwiftUI

struct EmployeeInfoView: View {
  // Retrieve stored user data from AppStorage.
  @AppStorage("userFirstName") var storedUserFirstName: String = ""
  @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
  @AppStorage("userHomeAddress") var storedUserHomeAddress: String = ""
  @AppStorage("userRole") var userRole: String = "employee"
  
  var body: some View {
    Form {
      Section(header: Text("Personal Information")) {
        HStack {
          Text("First Name")
          Spacer()
          Text(storedUserFirstName)
            .foregroundColor(.secondary)
        }
        HStack {
          Text("Organization ID")
          Spacer()
          Text(storedUserOrganizationID)
            .foregroundColor(.secondary)
        }
        HStack {
          Text("Home Address")
          Spacer()
          Text(storedUserHomeAddress)
            .foregroundColor(.secondary)
        }
        HStack {
          Text("Role")
          Spacer()
          Text(userRole.capitalized)
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Account Info")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct EmployeeInfoView_Previews: PreviewProvider {
  static var previews: some View {
    EmployeeInfoView()
  }
}

