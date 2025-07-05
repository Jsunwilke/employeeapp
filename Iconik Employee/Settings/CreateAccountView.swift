import SwiftUI
import Firebase
import FirebaseFirestore
import MapKit

struct CreateAccountView: View {
    @Environment(\.dismiss) var dismiss

    // User input fields
    @State private var organizationID = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var homeAddress = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    @State private var errorMessage = ""
    @State private var accountCreated = false
    
    // Geocoder for verifying the home address
    private let geocoder = CLGeocoder()
    
    // Address completer for suggestions
    @StateObject private var addressCompleter = AddressCompleter()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .padding()
                }
                
                Text("Create Account")
                    .font(.largeTitle)
                
                TextField("Organization ID", text: $organizationID)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                
                TextField("First Name", text: $firstName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Last Name", text: $lastName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                // Home Address field with suggestions
                TextField("Home Address", text: $homeAddress)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: homeAddress) { newValue in
                        addressCompleter.queryFragment = newValue
                    }
                
                // Display suggestions if available
                if !addressCompleter.suggestions.isEmpty {
                    ForEach(addressCompleter.suggestions, id: \.self) { suggestion in
                        Button(action: {
                            homeAddress = suggestion.title + ", " + suggestion.subtitle
                            addressCompleter.suggestions = []
                        }) {
                            VStack(alignment: .leading) {
                                Text(suggestion.title)
                                    .font(.body)
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.newPassword)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                
                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.newPassword)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                
                Button(action: validateAndCreateAccount) {
                    Text("Create Account")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                if accountCreated {
                    Text("Account created successfully. Please sign in.")
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func validateAndCreateAccount() {
        errorMessage = ""
        
        // Ensure no field is empty
        guard !organizationID.isEmpty,
              !firstName.isEmpty,
              !lastName.isEmpty,
              !homeAddress.isEmpty,
              !email.isEmpty,
              !password.isEmpty else {
            self.errorMessage = "Please fill in all fields."
            return
        }
        
        // Ensure the passwords match
        guard password == confirmPassword else {
            self.errorMessage = "Passwords do not match."
            return
        }
        
        // Use the geocoder to verify the address
        geocoder.geocodeAddressString(homeAddress) { placemarks, error in
            if let error = error {
                self.errorMessage = "Address not recognized: \(error.localizedDescription)"
                return
            }
            
            if let placemark = placemarks?.first {
                print("Address validated: \(placemark)")
                // Proceed to create the account if address is validated
                self.createAccount()
            } else {
                self.errorMessage = "Address not recognized. Please check it."
            }
        }
    }
    
    private func createAccount() {
        Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            
            guard let user = authResult?.user else { return }
            let db = Firestore.firestore()
            
            let userData: [String: Any] = [
                "organizationID": organizationID,
                "firstName": firstName,
                "lastName": lastName,
                "homeAddress": homeAddress,
                "email": email,
                "role": "employee"
            ]
            
            db.collection("users").document(user.uid).setData(userData) { error in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.errorMessage = ""
                    self.accountCreated = true
                }
            }
        }
    }
}

struct CreateAccountView_Previews: PreviewProvider {
    static var previews: some View {
        CreateAccountView()
    }
}

