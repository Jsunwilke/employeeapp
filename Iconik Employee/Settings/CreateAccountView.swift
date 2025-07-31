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
    @State private var fullAddress = ""  // Full formatted address
    @State private var coordinates = ""  // Lat,lng format
    @State private var city = ""
    @State private var state = ""
    @State private var zipCode = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    @State private var errorMessage = ""
    @State private var accountCreated = false
    @State private var showMap = false
    
    // Google Places service for address autocomplete
    @StateObject private var placesService = GooglePlacesService.shared
    
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
                // Address field with Google Places autocomplete
                AddressAutocompleteField(
                    address: $fullAddress,
                    coordinates: $coordinates,
                    showMap: $showMap,
                    city: $city,
                    state: $state,
                    zipCode: $zipCode,
                    country: .constant("United States")
                )
                
                if showMap && isValidCoordinates(coordinates) {
                    AddressMapView(
                        coordinates: $coordinates,
                        address: $fullAddress
                    ) { newCoordinate in
                        // Update coordinates when pin is dragged
                        coordinates = "\(newCoordinate.latitude),\(newCoordinate.longitude)"
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
              !fullAddress.isEmpty,
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
        
        // Verify we have coordinates
        guard !coordinates.isEmpty else {
            self.errorMessage = "Please select a valid address from the suggestions."
            return
        }
        
        // Proceed to create the account
        self.createAccount()
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
                "homeAddress": coordinates,  // Store coordinates in homeAddress
                "address": fullAddress,  // Store full formatted address
                "city": city,
                "state": state,
                "zipCode": zipCode,
                "country": "United States",
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
    
    private func isValidCoordinates(_ coordString: String) -> Bool {
        let parts = coordString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        
        if parts.count == 2,
           let lat = Double(parts[0]),
           let lng = Double(parts[1]),
           lat.isFinite && lng.isFinite,
           lat >= -90 && lat <= 90,
           lng >= -180 && lng <= 180 {
            return true
        }
        return false
    }
}

struct CreateAccountView_Previews: PreviewProvider {
    static var previews: some View {
        CreateAccountView()
    }
}

