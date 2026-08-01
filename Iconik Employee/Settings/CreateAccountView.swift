//  CreateAccountView.swift
//  Iconik Employee — signup, converted to Ambient in AMB.12
//
//  CONTAINMENT. This screen is PUSHED from `SignInView`'s `NavigationView` and
//  owns no container of its own. It used to carry a "Cancel" button in its own
//  content BESIDE the system back button — two ways back off one screen — so
//  "Cancel" moved into the toolbar and the system back button is hidden. One way
//  back, and the shipped word is kept.
//
//  WHAT IS FIXED HERE: the live password checklist and a client-side minimum,
//  shared with Reset Password so the two screens stop holding the same password
//  to two different standards (G36); errors through the app's user-facing mapper
//  instead of raw `localizedDescription` (a duplicate key or an RLS violation
//  used to print Postgrest text on screen); and a success that LEAVES, instead of
//  a green line under a form still holding the password (G38).
//
//  WHAT IS NOT FIXED HERE, and is not pretended to be: this screen inserts the
//  user row with a USER-TYPED `organization_id` and a client-supplied
//  `role: "employee"`, with no check that the organization exists and no
//  membership check (G2); and a signup that creates the auth user then fails on
//  the profile insert orphans that auth user, after which every retry hits
//  "already exists" forever (G4). Both are server-side concerns — nothing in this
//  file changes them, and nothing in this file should be read as changing them.

import SwiftUI
import MapKit

struct CreateAccountView: View {
    @Environment(\.dismiss) var dismiss

    /// Handed the confirmation on success so Sign In can show it after this
    /// screen pops (G38).
    var onAccountCreated: (String) -> Void = { _ in }

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
    @State private var showMap = false
    @State private var isLoading = false

    @FocusState private var focusedField: AuthFormField?

    // Supabase auth service
    @ObservedObject private var authService = SupabaseAuthService.shared

    /// The confirmation this screen has always shown. It travels to Sign In now
    /// rather than being drawn under a filled-in form.
    private static let successMessage = "Account created successfully. Please sign in."

    var body: some View {
        AuthScreen {
            formSection

            AmbientActionButton(title: "Create Account",
                                tint: AuthStyle.tint,
                                isLoading: isLoading,
                                action: validateAndCreateAccount)

            if !errorMessage.isEmpty {
                AuthErrorText(errorMessage)
            }
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.large)
        // The system back button would be a second way off this screen; the
        // shipped "Cancel" is the one that stays.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isLoading)
            }
        }
    }

    // MARK: - Sections

    /// ONE section, as the approved design draws it: the six shipped fields plus
    /// the address, then a divider, the two password fields and the live rule
    /// checklist — the same checklist Reset Password draws, from the same place
    /// (G36).
    private var formSection: some View {
        AmbientFormSection(title: "Create account", status: "", statusTint: nil) {
            VStack(alignment: .leading, spacing: 10) {
                AuthTextField(placeholder: "Organization ID",
                              text: $organizationID,
                              isEnabled: !isLoading,
                              focus: $focusedField,
                              field: .organization) {
                    focusedField = .firstName
                }

                Divider()

                AuthTextField(placeholder: "First Name",
                              text: $firstName,
                              capitalization: .words,
                              isEnabled: !isLoading,
                              focus: $focusedField,
                              field: .firstName) {
                    focusedField = .lastName
                }

                AuthTextField(placeholder: "Last Name",
                              text: $lastName,
                              capitalization: .words,
                              isEnabled: !isLoading,
                              focus: $focusedField,
                              field: .lastName) {
                    focusedField = .email
                }

                Divider()

                // KEPT WHOLE. The address is not decoration on this screen: the
                // coordinates it produces are what `home_address` is written
                // from, and signup refuses to proceed without them.
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

                Divider()

                AuthTextField(placeholder: "Email",
                              text: $email,
                              keyboard: .emailAddress,
                              contentType: .username,
                              isEnabled: !isLoading,
                              focus: $focusedField,
                              field: .email) {
                    focusedField = .password
                }

                Divider()

                AuthTextField(placeholder: "Password",
                              text: $password,
                              isSecure: true,
                              contentType: .newPassword,
                              isEnabled: !isLoading,
                              focus: $focusedField,
                              field: .password) {
                    focusedField = .confirmPassword
                }

                AuthTextField(placeholder: "Confirm Password",
                              text: $confirmPassword,
                              isSecure: true,
                              contentType: .newPassword,
                              submitLabel: .done,
                              isEnabled: !isLoading,
                              focus: $focusedField,
                              field: .confirmPassword) {
                    focusedField = nil
                }

                Divider()

                AuthPasswordChecklist(password: password, confirmation: confirmPassword)
            }
        }
    }

    // MARK: - Actions

    private func validateAndCreateAccount() {
        errorMessage = ""
        focusedField = nil

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

        // G36 — the same minimum Reset Password has always enforced. Without it
        // an account could be created with a password its owner could never set
        // again from the reset screen.
        guard AuthPasswordRules.isLongEnough(password) else {
            self.errorMessage = AuthPasswordRules.tooShortMessage
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
        isLoading = true

        Task {
            do {
                // Create account with Supabase Auth
                try await authService.signUp(email: email, password: password)

                guard let userId = authService.currentUserId else {
                    await MainActor.run {
                        errorMessage = "Failed to get user ID after signup"
                        isLoading = false
                    }
                    return
                }

                // Create user profile in Supabase database
                // Note: Using snake_case for Supabase fields
                struct NewUserProfile: Encodable {
                    let id: String
                    let email: String
                    let organization_id: String
                    let first_name: String
                    let last_name: String
                    let home_address: String  // Store coordinates
                    let address: String  // Store full formatted address
                    let city: String
                    let state: String
                    let zip_code: String
                    let country: String
                    let role: String
                }

                let newProfile = NewUserProfile(
                    id: userId,
                    email: email,
                    organization_id: organizationID,
                    first_name: firstName,
                    last_name: lastName,
                    home_address: coordinates,
                    address: fullAddress,
                    city: city,
                    state: state,
                    zip_code: zipCode,
                    country: "United States",
                    role: "employee"
                )

                let supabase = SupabaseManager.shared.client
                try await supabase
                    .from("users")
                    .insert(newProfile)
                    .execute()

                await MainActor.run {
                    errorMessage = ""
                    isLoading = false
                    // G38 — hand the confirmation back and LEAVE. Standing here
                    // with the form still populated left a typed password on a
                    // screen the user had no reason to return to.
                    onAccountCreated(Self.successMessage)
                    dismiss()
                }

            } catch {
                await MainActor.run {
                    // One error treatment across the four auth screens: the raw
                    // `localizedDescription` here used to put Postgrest text on
                    // screen.
                    errorMessage = error.userFacingMessage
                    isLoading = false
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
        NavigationView {
            CreateAccountView()
        }
    }
}
