//  AddSchoolView.swift
//  Iconik Employee — "Add New School", converted to Ambient in AMB.12
//
//  STAYS A SHEET with its own `NavigationView` — it is presented from the school
//  list's toolbar and from that list's empty state, and a sheet owns its own bar.
//
//  THE FIX (G18): Save was gated on `isMapView` with NO MESSAGE SAYING WHY, so a
//  user who typed an address and never tapped "Verify Address" saw a permanently
//  grey Save and no explanation anywhere on the screen. The gate is unchanged — a
//  school without coordinates is a school with no map — but it now says which step
//  is missing, and it says the RIGHT one when more than one is.
//
//  ALSO: verifying an address shows that it is working. The geocode had no
//  indicator at all, so a slow lookup looked like a dead button and invited a
//  second tap.
//
//  KEPT: the verify-then-drag-the-pin flow, the suggestion list and its height cap,
//  "Drag the pin to adjust the exact location", the coordinates read-out, "Dragging
//  pin...", and every message string.
//
//  NAMED, NOT FIXED: `city`/`state`/`zip` are never captured here even though
//  `createSchool` accepts them (G33), and this screen uses MapKit's
//  `AddressCompleter` while two other address autocompletes exist in the same
//  directory (G32).

import SwiftUI
import MapKit

struct AddSchoolView: View {
    // User input fields
    @State private var schoolName: String = ""
    @State private var schoolAddress: String = ""

    // Map coordination
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to San Francisco
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var pinLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    @State private var centerLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    @State private var isMapView: Bool = false
    @State private var isDragging: Bool = false

    // For address suggestions
    @StateObject private var addressCompleter = AddressCompleter()

    // State
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    @State private var isSubmitting: Bool = false
    @State private var isVerifying: Bool = false

    // User's organization ID
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""

    // Dismiss functionality
    @Environment(\.presentationMode) var presentationMode

    // Geocoder for converting address to coordinates
    private let geocoder = CLGeocoder()

    private var trimmedName: String {
        schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Why Save cannot be tapped yet — nil when it can. Ordered so the user is told
    /// the FIRST thing they need to do, not all of them at once.
    private var saveBlockedReason: String? {
        if trimmedName.isEmpty { return "Enter the school's name." }
        if !isMapView { return "Tap \"Verify Address\" to place the school on the map. A school is saved with its coordinates, so it needs a verified address." }
        return nil
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        informationSection
                        if isMapView { locationSection }
                        saveSection
                        messages
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Add New School")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var informationSection: some View {
        AmbientFormSection(title: "School Information",
                           status: isMapView ? "address verified" : "",
                           statusTint: isMapView ? .green : nil) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("School Name")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("School Name", text: $schoolName).font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("School Address")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("School Address", text: $schoolAddress)
                        .font(.subheadline)
                        .onChange(of: schoolAddress) { newValue in
                            addressCompleter.queryFragment = newValue
                        }
                }

                // Display suggestions if available
                if !addressCompleter.suggestions.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(addressCompleter.suggestions, id: \.self) { suggestion in
                                Button {
                                    schoolAddress = suggestion.title + ", " + suggestion.subtitle
                                    addressCompleter.suggestions = []
                                    verifyAddress()
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(suggestion.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(suggestion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(addressCompleter.suggestions.count * 60), 200))
                }

                AmbientActionButton(title: "Verify Address",
                                    systemImage: "mappin.and.ellipse",
                                    role: .secondary,
                                    size: .small,
                                    fillWidth: false,
                                    isLoading: isVerifying,
                                    isEnabled: !schoolAddress.isEmpty,
                                    action: verifyAddress)
            }
        }
    }

    private var locationSection: some View {
        AmbientFormSection(title: "Confirm Location",
                           status: isDragging ? "Dragging pin..." : "",
                           statusTint: isDragging ? .blue : nil) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Drag the pin to adjust the exact location")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Use the enhanced MapView component
                MapViewComponent(
                    centerCoordinate: $centerLocation,
                    pinCoordinate: $pinLocation,
                    region: $region,
                    isDragging: $isDragging
                )
                .frame(height: 300)
                // ambient-allow: a map is a clipped view, not a container.
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                AmbientStatLine(label: "Coordinates:",
                                value: String(format: "%.6f, %.6f", pinLocation.latitude, pinLocation.longitude))
            }
        }
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientActionButton(title: "Save School",
                                role: .primary,
                                tint: SettingsStyle.tint,
                                isLoading: isSubmitting,
                                isEnabled: saveBlockedReason == nil,
                                action: saveSchool)

            // G18 — a grey button that never says why is the defect this fixes.
            if let saveBlockedReason {
                Text(saveBlockedReason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if !errorMessage.isEmpty {
            AmbientFailureCard(message: errorMessage, tint: .red, action: nil)
        }
        if !successMessage.isEmpty {
            AmbientNoteCard(title: "Done", text: successMessage, accent: .green, density: .compact)
        }
    }

    // MARK: - Helper Methods

    private func verifyAddress() {
        guard !schoolAddress.isEmpty else {
            errorMessage = "Please enter a school address."
            return
        }
        guard !isVerifying else { return }

        isVerifying = true
        geocoder.geocodeAddressString(schoolAddress) { placemarks, error in
            DispatchQueue.main.async {
                isVerifying = false

                if let error = error {
                    errorMessage = "Address not found: \(error.localizedDescription)"
                    return
                }

                guard let placemark = placemarks?.first,
                      let location = placemark.location?.coordinate else {
                    errorMessage = "Could not determine location from address."
                    return
                }

                // Update the map region and pin location
                region = MKCoordinateRegion(
                    center: location,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                pinLocation = location
                centerLocation = location
                isMapView = true
                errorMessage = ""
            }
        }
    }

    private func saveSchool() {
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a school name."
            return
        }

        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "No organization ID found. Please sign in again."
            return
        }

        isSubmitting = true
        errorMessage = ""

        // Create the coordinates string
        let coordinatesString = "\(pinLocation.latitude),\(pinLocation.longitude)"

        Task {
            do {
                _ = try await SchoolService.shared.createSchool(
                    organizationID: storedUserOrganizationID,
                    name: trimmedName,
                    address: schoolAddress,
                    coordinates: coordinatesString
                )

                await MainActor.run {
                    isSubmitting = false
                    successMessage = "School added successfully!"

                    // Reset the form after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Error saving school: \(error.localizedDescription)"
                }
            }
        }
    }
}
