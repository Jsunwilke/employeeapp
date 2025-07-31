import SwiftUI
import FirebaseAuth
import MapKit

struct EmployeeInfoView: View {
    // State for editing
    @State private var isEditing = false
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var isSaving = false
    
    // Observable objects
    @StateObject private var profileService = UserProfileService.shared
    @StateObject private var userManager = UserManager.shared
    
    // Editable fields
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var fullAddress = ""  // Full formatted address
    @State private var coordinates = ""  // Lat,lng format
    @State private var city = ""
    @State private var state = ""
    @State private var zipCode = ""
    @State private var bio = ""
    @State private var position = ""
    
    // Map state
    @State private var showMap = false
    
    // AppStorage fields (read-only display)
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
    @AppStorage("userRole") var userRole: String = "employee"
    
    // AppStorage fields to update
    @AppStorage("userFirstName") var storedUserFirstName: String = ""
    @AppStorage("userLastName") var storedUserLastName: String = ""
    @AppStorage("userDisplayName") var storedUserDisplayName: String = ""
    @AppStorage("userEmail") var storedUserEmail: String = ""
    @AppStorage("userPhone") var storedUserPhone: String = ""
    @AppStorage("userHomeAddress") var storedUserHomeAddress: String = ""  // Coordinates
    @AppStorage("userAddress") var storedUserAddress: String = ""  // Full address
    @AppStorage("userCity") var storedUserCity: String = ""
    @AppStorage("userState") var storedUserState: String = ""
    @AppStorage("userZipCode") var storedUserZipCode: String = ""
    @AppStorage("userCountry") var storedUserCountry: String = ""
    @AppStorage("userBio") var storedUserBio: String = ""
    @AppStorage("userPosition") var storedUserPosition: String = ""
    
    var body: some View {
        Form {
            // Personal Information Section
            Section(header: Text("Personal Information")) {
                if isEditing {
                    editableField("First Name", text: $firstName)
                    editableField("Last Name", text: $lastName)
                    editableField("Display Name", text: $displayName)
                    editableField("Email", text: $email, keyboardType: .emailAddress)
                    editableField("Phone", text: $phone, keyboardType: .phonePad)
                } else {
                    infoRow("First Name", value: profileService.currentUserProfile?.firstName ?? storedUserFirstName)
                    infoRow("Last Name", value: profileService.currentUserProfile?.lastName ?? storedUserLastName)
                    infoRow("Display Name", value: profileService.currentUserProfile?.displayName ?? storedUserDisplayName)
                    infoRow("Email", value: profileService.currentUserProfile?.email ?? storedUserEmail)
                    infoRow("Phone", value: profileService.currentUserProfile?.phone ?? storedUserPhone)
                }
            }
            
            // Address Section
            Section(header: Text("Address")) {
                if isEditing {
                    AddressAutocompleteField(
                        address: $fullAddress,
                        coordinates: $coordinates,
                        showMap: $showMap,
                        city: $city,
                        state: $state,
                        zipCode: $zipCode,
                        country: $storedUserCountry
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
                } else {
                    infoRow("Address", value: profileService.currentUserProfile?.address ?? storedUserAddress)
                    if isValidCoordinates(coordinates) {
                        Button(action: {
                            showMap.toggle()
                        }) {
                            Label(showMap ? "Hide Map" : "Show Map", systemImage: "map")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        if showMap {
                            AddressMapView(
                                coordinates: .constant(coordinates),
                                address: .constant(fullAddress)
                            )
                            .allowsHitTesting(false)  // Read-only when not editing
                        }
                    }
                }
            }
            
            // Professional Information Section
            Section(header: Text("Professional Information")) {
                if isEditing {
                    editableField("Position", text: $position)
                    VStack(alignment: .leading) {
                        Text("Bio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $bio)
                            .frame(minHeight: 80)
                    }
                } else {
                    infoRow("Position", value: profileService.currentUserProfile?.position ?? storedUserPosition)
                    infoRow("Bio", value: profileService.currentUserProfile?.bio ?? storedUserBio)
                    infoRow("Role", value: userRole.capitalized)
                }
            }
            
            // Organization Information Section (Read-only)
            Section(header: Text("Organization")) {
                infoRow("Organization ID", value: storedUserOrganizationID)
                if let mileageRate = profileService.currentUserProfile?.amountPerMile {
                    infoRow("Mileage Rate", value: "$\(String(format: "%.2f", mileageRate))/mile")
                }
            }
        }
        .navigationTitle("Account Info")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: editButton)
        .onAppear {
            loadUserData()
            // Refresh profile when view appears
            profileService.refreshCurrentUserProfile()
        }
        .alert(isPresented: $showingSaveAlert) {
            Alert(
                title: Text("Profile Update"),
                message: Text(saveAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .disabled(isSaving)
        .overlay(
            Group {
                if isSaving {
                    ProgressView("Saving...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 5)
                }
            }
        )
    }
    
    @ViewBuilder
    private var editButton: some View {
        if isEditing {
            Button("Save") {
                saveChanges()
            }
            .disabled(isSaving)
        } else {
            Button("Edit") {
                withAnimation {
                    isEditing = true
                }
            }
        }
    }
    
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.isEmpty ? "Not set" : value)
                .foregroundColor(value.isEmpty ? .orange : .secondary)
                .multilineTextAlignment(.trailing)
        }
    }
    
    private func editableField(_ label: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(label, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(keyboardType)
                .autocapitalization(keyboardType == .emailAddress ? .none : .words)
        }
    }
    
    private func loadUserData() {
        if let profile = profileService.currentUserProfile {
            firstName = profile.firstName
            lastName = profile.lastName
            displayName = profile.displayName
            email = profile.email
            phone = profile.phone
            coordinates = profile.homeAddress  // homeAddress stores coordinates
            fullAddress = profile.address  // address stores the full formatted address
            city = profile.city
            state = profile.state
            zipCode = profile.zipCode
            bio = profile.bio
            position = profile.position
            
            // Show map if we have coordinates
            showMap = isValidCoordinates(coordinates)
        } else {
            // Load from AppStorage as fallback
            firstName = storedUserFirstName
            lastName = storedUserLastName
            displayName = storedUserDisplayName
            email = storedUserEmail
            phone = storedUserPhone
            coordinates = storedUserHomeAddress  // Coordinates
            fullAddress = storedUserAddress  // Full address
            city = storedUserCity
            state = storedUserState
            zipCode = storedUserZipCode
            bio = storedUserBio
            position = storedUserPosition
            
            // Show map if we have valid coordinates
            showMap = isValidCoordinates(coordinates)
        }
    }
    
    private func saveChanges() {
        guard let uid = Auth.auth().currentUser?.uid else {
            saveAlertMessage = "No authenticated user found"
            showingSaveAlert = true
            return
        }
        
        isSaving = true
        
        let updatedFields: [String: Any] = [
            "firstName": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "lastName": lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "homeAddress": coordinates,  // Store coordinates in homeAddress
            "bio": bio.trimmingCharacters(in: .whitespacesAndNewlines),
            "position": position.trimmingCharacters(in: .whitespacesAndNewlines),
            "address": fullAddress.trimmingCharacters(in: .whitespacesAndNewlines),  // Store full address as single string
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),  // Keep individual components
            "state": state.trimmingCharacters(in: .whitespacesAndNewlines),
            "zipCode": zipCode.trimmingCharacters(in: .whitespacesAndNewlines),
            "country": storedUserCountry
        ]
        
        profileService.updateUserFields(updatedFields) { result in
            DispatchQueue.main.async {
                isSaving = false
                
                switch result {
                case .success:
                    saveAlertMessage = "Profile updated successfully"
                    isEditing = false
                    // Update AppStorage values
                    storedUserFirstName = firstName
                    storedUserLastName = lastName
                    storedUserDisplayName = displayName
                    storedUserEmail = email
                    storedUserPhone = phone
                    storedUserHomeAddress = coordinates  // Store coordinates
                    storedUserAddress = fullAddress  // Store full address
                    storedUserCity = city
                    storedUserState = state
                    storedUserZipCode = zipCode
                    storedUserBio = bio
                    storedUserPosition = position
                    
                case .failure(let error):
                    saveAlertMessage = "Failed to update profile: \(error.localizedDescription)"
                }
                
                showingSaveAlert = true
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

struct EmployeeInfoView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            EmployeeInfoView()
        }
    }
}

