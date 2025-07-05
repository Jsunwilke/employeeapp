import SwiftUI
import MapKit
import FirebaseFirestore
import Firebase

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
    
    // User's organization ID
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
    
    // Dismiss functionality
    @Environment(\.presentationMode) var presentationMode
    
    // Geocoder for converting address to coordinates
    private let geocoder = CLGeocoder()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("School Information")) {
                    TextField("School Name", text: $schoolName)
                    
                    // Address field with suggestions
                    TextField("School Address", text: $schoolAddress)
                        .onChange(of: schoolAddress) { newValue in
                            addressCompleter.queryFragment = newValue
                        }
                    
                    // Display suggestions if available
                    if !addressCompleter.suggestions.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(addressCompleter.suggestions, id: \.self) { suggestion in
                                    Button(action: {
                                        schoolAddress = suggestion.title + ", " + suggestion.subtitle
                                        addressCompleter.suggestions = []
                                        verifyAddress()
                                    }) {
                                        VStack(alignment: .leading) {
                                            Text(suggestion.title)
                                                .font(.body)
                                            Text(suggestion.subtitle)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .frame(height: min(CGFloat(addressCompleter.suggestions.count * 60), 200))
                    }
                    
                    Button("Verify Address") {
                        verifyAddress()
                    }
                    .disabled(schoolAddress.isEmpty)
                }
                
                if isMapView {
                    Section(header: Text("Confirm Location")) {
                        Text("Drag the pin to adjust the exact location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Use the enhanced MapView component
                        MapViewComponent(
                            centerCoordinate: $centerLocation,
                            pinCoordinate: $pinLocation,
                            region: $region,
                            isDragging: $isDragging
                        )
                        .frame(height: 300)
                        
                        HStack {
                            Text("Coordinates:")
                            Spacer()
                            Text(String(format: "%.6f, %.6f", pinLocation.latitude, pinLocation.longitude))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if isDragging {
                            Text("Dragging pin...")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                    }
                }
                
                Section {
                    Button(action: saveSchool) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Save School")
                        }
                    }
                    .disabled(isSubmitting || !isMapView || schoolName.isEmpty)
                }
                
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
                
                if !successMessage.isEmpty {
                    Section {
                        Text(successMessage)
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Add New School")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func verifyAddress() {
        guard !schoolAddress.isEmpty else {
            errorMessage = "Please enter a school address."
            return
        }
        
        geocoder.geocodeAddressString(schoolAddress) { placemarks, error in
            DispatchQueue.main.async {
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
        guard !schoolName.isEmpty else {
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
        
        // Create the school data - now using the correct field structure
        let schoolData: [String: Any] = [
            "type": "school",
            "value": schoolName,
            "address": schoolAddress,         // Human-readable address in 'address' field
            "schoolAddress": coordinatesString, // Coordinates in 'schoolAddress' field as requested
            "organizationID": storedUserOrganizationID
            // Timestamp field removed as requested
        ]
        
        // Save to Firestore
        let db = Firestore.firestore()
        db.collection("dropdownData").addDocument(data: schoolData) { error in
            DispatchQueue.main.async {
                isSubmitting = false
                
                if let error = error {
                    errorMessage = "Error saving school: \(error.localizedDescription)"
                } else {
                    successMessage = "School added successfully!"
                    
                    // Reset the form after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// Preview
struct AddSchoolView_Previews: PreviewProvider {
    static var previews: some View {
        AddSchoolView()
    }
}
