//  EmployeeInfoView.swift
//  Iconik Employee — "Account Info", converted to Ambient in AMB.12
//
//  WHAT CHANGED, and why each one is a change rather than a repaint:
//
//    · EMAIL IS READ-ONLY. It was editable and wrote `users.email` — while Supabase
//      Auth's email was NEVER changed. The two diverge and sign-in still needs the
//      old address, so a photographer who "fixed" their email locked the account's
//      display value away from the credential (G6). Changing an account's email is
//      an auth operation, not a profile edit, and it is out of scope for a design
//      phase. The field is drawn read-only and no longer sent in the update.
//
//    · ROLE, MILEAGE RATE AND ORGANIZATION STAY VISIBLE IN EDIT MODE (G22).
//      Entering Edit removed all three with no substitute, so the one screen that
//      tells a photographer their mileage rate hid it the moment they touched
//      anything.
//
//    · THE ORGANIZATION IS NAMED, NOT NUMBERED. The raw uuid was on screen for
//      support; it is not something a photographer can use, and the name identifies
//      the same thing.
//
//  KEPT: the "Not set" orange empty-value fallback, the Edit/Save toolbar, the
//  saving overlay and its `.disabled(isSaving)`, the address autocomplete with its
//  draggable map in edit mode and the read-only map with hit testing off in view
//  mode, the Bio editor, and every alert string.
//
//  NAMED, NOT FIXED (service-layer, out of this phase's scope): the background
//  profile refresh lands AFTER the form is seeded and nothing re-seeds it, so Edit
//  can save stale values over fresher server data (G5); `city`/`state`/`zip` are
//  saved but only the autocomplete can set them (G23); the `[String:Any]` → AnyJSON
//  conversion silently drops a value it cannot map (G24); and the update does not
//  prove a row matched (G-series/UUID rule) because that proof belongs in
//  `UserProfileService.updateUserFields`.

import SwiftUI
import MapKit

struct EmployeeInfoView: View {
    // State for editing
    @State private var isEditing = false
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var isSaving = false

    // Observable objects
    @StateObject private var profileService = UserProfileService.shared

    // Editable fields
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var displayName = ""
    @State private var phone = ""
    @State private var fullAddress = ""  // Full formatted address
    @State private var coordinates = ""  // Lat,lng format
    @State private var city = ""
    @State private var state = ""
    @State private var zipCode = ""
    @State private var bio = ""
    @State private var position = ""

    // NOTE: there is no `email` edit buffer. The field is read-only and is drawn
    // straight from the profile (see `displayedEmail`) — a buffer for a value that
    // cannot be typed into is exactly the kind of state that drifts.

    // Map state
    @State private var showMap = false

    /// The organization's NAME, replacing the raw uuid. Nil while the lookup is in
    /// flight; a failed lookup says so rather than drawing a blank or a zero.
    @State private var organizationName: String?
    @State private var organizationLookupFailed = false

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

    private var profile: UserProfile? { profileService.currentUserProfile }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    personalSection
                    addressSection
                    professionalSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .disabled(isSaving)
        .overlay { savingOverlay }
        .tabBarClearance()
        .navigationTitle("Account Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { editButton }
        }
        .onAppear {
            loadUserData()
            loadOrganizationName()
            // Refresh profile when view appears
            Task {
                await profileService.refreshCurrentUserProfile()
            }
        }
        .alert(isPresented: $showingSaveAlert) {
            Alert(
                title: Text("Profile Update"),
                message: Text(saveAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Sections

    private var personalSection: some View {
        AmbientFormSection(title: "Personal information",
                           status: isEditing ? "editing" : displayedName,
                           statusTint: isEditing ? .orange : nil) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsField(label: "First Name", text: $firstName, isEditing: isEditing,
                              displayValue: profile?.firstName ?? storedUserFirstName)
                SettingsField(label: "Last Name", text: $lastName, isEditing: isEditing,
                              displayValue: profile?.lastName ?? storedUserLastName)
                SettingsField(label: "Display Name", text: $displayName, isEditing: isEditing,
                              displayValue: profile?.displayName ?? storedUserDisplayName)
                SettingsField(label: "Phone", text: $phone, isEditing: isEditing,
                              keyboardType: .phonePad,
                              displayValue: profile?.phone ?? storedUserPhone)

                Divider()

                // READ-ONLY in both modes, and not sent in the update.
                AmbientStatLine(label: "Email", value: displayedEmail.isEmpty ? "Not set" : displayedEmail,
                                valueTint: displayedEmail.isEmpty ? .orange : nil)
                Text("Your email is the address you sign in with. Changing it is an account change, not a profile edit — contact your manager.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var addressSection: some View {
        AmbientFormSection(title: "Address",
                           status: isEditing ? "editing" : (displayedAddress.isEmpty ? "not set" : "set"),
                           statusTint: isEditing ? .orange : nil) {
            VStack(alignment: .leading, spacing: 8) {
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
                    AmbientStatLine(label: "Address",
                                    value: displayedAddress.isEmpty ? "Not set" : displayedAddress,
                                    valueTint: displayedAddress.isEmpty ? .orange : nil)

                    if isValidCoordinates(coordinates) {
                        Button {
                            withAnimation(AmbientMotion.snappy) { showMap.toggle() }
                            AmbientHaptics.selection()
                        } label: {
                            Label(showMap ? "Hide Map" : "Show Map", systemImage: "map")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SettingsStyle.tint)
                        }
                        .buttonStyle(.plain)

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
        }
    }

    /// Role, mileage rate and organization are drawn in BOTH modes (G22).
    private var professionalSection: some View {
        AmbientFormSection(title: "Professional",
                           status: displayedPosition.isEmpty ? "no position" : displayedPosition,
                           statusTint: nil) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsField(label: "Position", text: $position, isEditing: isEditing,
                              displayValue: profile?.position ?? storedUserPosition)

                bioField

                Divider()

                AmbientStatLine(label: "Role", value: userRole.capitalized)

                if let mileageRate = profile?.amountPerMile {
                    AmbientStatLine(label: "Mileage Rate",
                                    value: "\(Formatters.currency(mileageRate))/mile")
                }

                AmbientStatLine(label: "Organization", value: organizationValue)
            }
        }
    }

    @ViewBuilder
    private var bioField: some View {
        if isEditing {
            VStack(alignment: .leading, spacing: 3) {
                Text("Bio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $bio)
                    .font(.subheadline)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
            }
        } else {
            let value = profile?.bio ?? storedUserBio
            AmbientStatLine(label: "Bio",
                            value: value.isEmpty ? "Not set" : value,
                            valueTint: value.isEmpty ? .orange : nil)
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var editButton: some View {
        if isEditing {
            Button("Save") { saveChanges() }
                .disabled(isSaving)
        } else {
            Button("Edit") {
                withAnimation { isEditing = true }
            }
        }
    }

    @ViewBuilder
    private var savingOverlay: some View {
        if isSaving {
            ProgressView("Saving...")
                .ambientCard(density: .roomy, state: .highlighted)
        }
    }

    // MARK: - Displayed values

    private var displayedName: String {
        let name = (profile?.displayName ?? storedUserDisplayName)
        if !name.isEmpty { return name }
        let composed = [profile?.firstName ?? storedUserFirstName,
                        profile?.lastName ?? storedUserLastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return composed.isEmpty ? "not set" : composed
    }

    private var displayedEmail: String { profile?.email ?? storedUserEmail }
    private var displayedAddress: String { profile?.address ?? storedUserAddress }
    private var displayedPosition: String { profile?.position ?? storedUserPosition }

    private var organizationValue: String {
        if let organizationName, !organizationName.isEmpty { return organizationName }
        return organizationLookupFailed ? "Couldn't load" : "Loading…"
    }

    // MARK: - Data

    private func loadUserData() {
        if let profile = profileService.currentUserProfile {
            firstName = profile.firstName
            lastName = profile.lastName
            displayName = profile.displayName
            phone = profile.phone ?? ""
            coordinates = profile.homeAddress  // homeAddress stores coordinates
            fullAddress = profile.address ?? ""  // address stores the full formatted address
            city = profile.city ?? ""
            state = profile.state ?? ""
            zipCode = profile.zipCode
            bio = profile.bio ?? ""
            position = profile.position ?? ""
        } else {
            // Load from AppStorage as fallback
            firstName = storedUserFirstName
            lastName = storedUserLastName
            displayName = storedUserDisplayName
            phone = storedUserPhone
            coordinates = storedUserHomeAddress  // Coordinates
            fullAddress = storedUserAddress  // Full address
            city = storedUserCity
            state = storedUserState
            zipCode = storedUserZipCode
            bio = storedUserBio
            position = storedUserPosition
        }

        // Show map if we have valid coordinates
        showMap = isValidCoordinates(coordinates)
    }

    /// The name behind `userOrganizationID`. `organizations.id` carries mixed-case
    /// Firebase ids, so the stored string is passed through EXACTLY as held — no
    /// case folding (this repo's UUID rule).
    private func loadOrganizationName() {
        guard !storedUserOrganizationID.isEmpty else {
            organizationLookupFailed = true
            return
        }
        Task {
            do {
                let organization = try await OrganizationService.shared
                    .getOrganization(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    organizationName = organization?.name
                    organizationLookupFailed = (organization?.name ?? "").isEmpty
                }
            } catch {
                await MainActor.run { organizationLookupFailed = true }
            }
        }
    }

    private func saveChanges() {
        guard let _ = UserManager.shared.getCurrentUserIDUnified() else {
            saveAlertMessage = "No authenticated user found"
            showingSaveAlert = true
            return
        }

        isSaving = true

        // Use snake_case field names to match Supabase schema.
        // NOTE: "email" is deliberately absent. The field is read-only now, and
        // writing `users.email` without changing Supabase Auth's email is what made
        // the two diverge in the first place (G6).
        let updatedFields: [String: Any] = [
            "first_name": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "last_name": lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            "display_name": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "home_address": coordinates,  // Store coordinates in home_address
            "bio": bio.trimmingCharacters(in: .whitespacesAndNewlines),
            "position": position.trimmingCharacters(in: .whitespacesAndNewlines),
            "address": fullAddress.trimmingCharacters(in: .whitespacesAndNewlines),  // Store full address as single string
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),  // Keep individual components
            "state": state.trimmingCharacters(in: .whitespacesAndNewlines),
            "zip_code": zipCode.trimmingCharacters(in: .whitespacesAndNewlines),
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

    /// One validator, in `Utilities/CoordinateString.swift`. This was a verbatim
    /// copy of the same eight lines that also sat in `AddressAutocompleteField`
    /// and `CreateAccountView`.
    private func isValidCoordinates(_ coordString: String) -> Bool {
        CoordinateString.isValid(coordString)
    }
}
