import SwiftUI
import Firebase
import FirebaseFirestore

struct SignInView: View {
  @Binding var isSignedIn: Bool
  
  @State private var email = ""
  @State private var password = ""
  @State private var errorMessage = ""
  
  // AppStorage for user data (now including last name)
  @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
  @AppStorage("userFirstName") var storedUserFirstName: String = ""
  @AppStorage("userLastName") var storedUserLastName: String = ""
  @AppStorage("userHomeAddress") var storedUserHomeAddress: String = ""
  @AppStorage("userRole") var userRole: String = "employee"
  
  var body: some View {
    NavigationView {
      VStack(spacing: 20) {
        Text("Sign In")
          .font(.largeTitle)
          .padding(.top, 40)
        
        TextField("Email", text: $email)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .keyboardType(.emailAddress)
          .autocapitalization(.none)
        
        SecureField("Password", text: $password)
          .textFieldStyle(RoundedBorderTextFieldStyle())
        
        Button("Sign In", action: signIn)
          .padding()
          .frame(maxWidth: .infinity)
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(8)
        
        NavigationLink(destination: CreateAccountView()) {
          Text("Don't have an account? Create one.")
            .foregroundColor(.blue)
        }
        
        if !errorMessage.isEmpty {
          Text(errorMessage)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
        }
        
        Spacer()
      }
      .padding()
    }
  }
  
  func signIn() {
    errorMessage = ""
    Auth.auth().signIn(withEmail: email, password: password) { result, error in
      if let error = error {
        errorMessage = error.localizedDescription
        return
      }
      guard let uid = result?.user.uid else { return }
      let db = Firestore.firestore()
      db.collection("users").document(uid).getDocument { snapshot, error in
        if let error = error {
          errorMessage = error.localizedDescription
          return
        }
        guard let data = snapshot?.data() else {
          errorMessage = "User data not found."
          return
        }
        // Save user data
        storedUserOrganizationID = data["organizationID"] as? String ?? ""
        storedUserFirstName = data["firstName"] as? String ?? ""
        storedUserLastName = data["lastName"] as? String ?? ""
        storedUserHomeAddress = data["homeAddress"] as? String ?? ""
        userRole = data["role"] as? String ?? "employee"
        
        isSignedIn = true
      }
    }
  }
}

struct SignInView_Previews: PreviewProvider {
  static var previews: some View {
    SignInView(isSignedIn: .constant(false))
  }
}

