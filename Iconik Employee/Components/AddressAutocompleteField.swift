import SwiftUI
import MapKit
import Combine

struct AddressAutocompleteField: View {
    @Binding var address: String
    @Binding var coordinates: String  // Format: "lat,lng"
    @Binding var showMap: Bool
    
    // Address components
    @Binding var city: String
    @Binding var state: String
    @Binding var zipCode: String
    @Binding var country: String
    
    @StateObject private var placesService = GooglePlacesService.shared
    @StateObject private var organizationService = OrganizationService.shared
    @State private var sessionToken = UUID().uuidString
    @State private var isShowingSuggestions = false
    @State private var selectedPlaceId: String?
    @State private var geocodeWorkItem: DispatchWorkItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Address input field
            VStack(alignment: .leading, spacing: 4) {
                Text("Address")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Enter address", text: $address, onEditingChanged: { isEditing in
                    if isEditing {
                        isShowingSuggestions = true
                    } else {
                        // Delay hiding suggestions to allow tap events to register
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isShowingSuggestions = false
                            placesService.clearPredictions()
                        }
                    }
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.words)
                .disableAutocorrection(true)
                .onChange(of: address) { newValue in
                    // Cancel any existing geocode work
                    geocodeWorkItem?.cancel()
                    
                    // Only search if we have at least 3 characters
                    if newValue.count >= 3 {
                        placesService.searchPlaces(
                            query: newValue,
                            centerCoordinates: organizationService.organizationCoordinates.isEmpty ? nil : organizationService.organizationCoordinates,
                            sessionToken: sessionToken
                        )
                        
                        // Schedule geocoding after a delay
                        let workItem = DispatchWorkItem {
                            self.geocodeAddress(newValue)
                        }
                        geocodeWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
                    } else {
                        placesService.clearPredictions()
                        coordinates = ""
                        showMap = false
                    }
                }
            }
            
            // Suggestions dropdown
            if isShowingSuggestions {
                if placesService.isLoading && address.count >= 3 {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Searching...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .padding(.top, 2)
                } else if !placesService.predictions.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(placesService.predictions) { prediction in
                                Button(action: {
                                    selectPlace(prediction)
                                }) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(prediction.primaryText)
                                            .font(.system(size: 15))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        
                                        Text(prediction.secondaryText)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if prediction.id != placesService.predictions.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .padding(.top, 2)
                }
            }
            
            // Show map button if valid coordinates are available
            if isValidCoordinates(coordinates) && !showMap {
                Button(action: {
                    showMap = true
                }) {
                    Label("View on Map", systemImage: "map")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.top, 4)
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
    
    private func selectPlace(_ prediction: GooglePlacesService.PlacePrediction) {
        print("🏠 Selected place: \(prediction.fullText)")
        
        // Hide suggestions
        isShowingSuggestions = false
        placesService.clearPredictions()
        
        // Cancel any pending geocode
        geocodeWorkItem?.cancel()
        
        // Set the address temporarily to the prediction text
        address = prediction.fullText
        selectedPlaceId = prediction.id
        
        // Get place details
        placesService.getPlaceDetails(placeId: prediction.id, sessionToken: sessionToken) { result in
            switch result {
            case .success(let details):
                // Update coordinates
                coordinates = "\(details.coordinate.latitude),\(details.coordinate.longitude)"
                
                // Update address components
                if let cityValue = details.city {
                    city = cityValue
                }
                if let stateValue = details.state {
                    state = stateValue
                }
                if let zipValue = details.postalCode {
                    zipCode = zipValue
                }
                if let countryValue = details.country {
                    country = countryValue
                }
                
                // Update address to formatted version
                address = details.formattedAddress
                print("🏠 Updated address to: \(address)")
                
                // Show map
                showMap = true
                
                // Generate new session token for next search
                sessionToken = UUID().uuidString
                
            case .failure(let error):
                print("Failed to get place details: \(error.localizedDescription)")
            }
        }
    }
    
    private func geocodeAddress(_ addressString: String) {
        // Don't geocode if we just selected from autocomplete
        guard selectedPlaceId == nil else {
            selectedPlaceId = nil
            return
        }
        
        print("🗺️ Geocoding address: \(addressString)")
        
        placesService.geocodeAddress(addressString) { result in
            switch result {
            case .success(let coordinate):
                DispatchQueue.main.async {
                    self.coordinates = "\(coordinate.latitude),\(coordinate.longitude)"
                    self.showMap = true
                    print("📍 Geocoded to: \(coordinate.latitude), \(coordinate.longitude)")
                }
            case .failure(let error):
                print("❌ Geocoding failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Address Map View

struct AddressMapView: View {
    @Binding var coordinates: String  // Format: "lat,lng"
    @Binding var address: String
    let onCoordinatesChanged: ((CLLocationCoordinate2D) -> Void)?
    
    @State private var region: MKCoordinateRegion
    @State private var pinLocation: CLLocationCoordinate2D
    @State private var centerLocation: CLLocationCoordinate2D
    @State private var isDragging = false
    
    init(coordinates: Binding<String>, address: Binding<String>, onCoordinatesChanged: ((CLLocationCoordinate2D) -> Void)? = nil) {
        self._coordinates = coordinates
        self._address = address
        self.onCoordinatesChanged = onCoordinatesChanged
        
        // Parse initial coordinates with validation
        let coordString = coordinates.wrappedValue
        let coord: CLLocationCoordinate2D
        
        if !coordString.isEmpty {
            coord = Self.parseCoordinates(coordString)
        } else {
            // Default to a safe coordinate if empty
            coord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        }
        
        self._pinLocation = State(initialValue: coord)
        self._centerLocation = State(initialValue: coord)
        self._region = State(initialValue: MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Map with satellite view
            MapViewComponent(
                centerCoordinate: $centerLocation,
                pinCoordinate: $pinLocation,
                region: $region,
                isDragging: $isDragging,
                mapType: .hybrid  // Satellite with street labels
            )
            .frame(height: 250)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            // Instructions
            Text("Drag the pin to adjust location")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Coordinates display
            HStack {
                Text("Coordinates:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(String(format: "%.6f, %.6f", pinLocation.latitude, pinLocation.longitude))
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 4)
        }
        .onChange(of: pinLocation.latitude) { _ in
            updateCoordinates()
        }
        .onChange(of: pinLocation.longitude) { _ in
            updateCoordinates()
        }
        .onChange(of: coordinates) { newValue in
            // Update map when coordinates change externally (e.g., from autocomplete)
            guard !newValue.isEmpty else { return }
            
            let newCoord = Self.parseCoordinates(newValue)
            // Only update if we got valid coordinates
            if newCoord.latitude.isFinite && newCoord.longitude.isFinite &&
               (newCoord.latitude != pinLocation.latitude || newCoord.longitude != pinLocation.longitude) {
                pinLocation = newCoord
                centerLocation = newCoord
                region = MKCoordinateRegion(
                    center: newCoord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
        }
    }
    
    private func updateCoordinates() {
        // Update coordinates string
        coordinates = "\(pinLocation.latitude),\(pinLocation.longitude)"
        
        // Call the callback if provided
        onCoordinatesChanged?(pinLocation)
    }
    
    private static func parseCoordinates(_ coordString: String) -> CLLocationCoordinate2D {
        let parts = coordString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        
        if parts.count == 2,
           let lat = Double(parts[0]),
           let lng = Double(parts[1]),
           lat.isFinite && lng.isFinite,
           lat >= -90 && lat <= 90,
           lng >= -180 && lng <= 180 {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        
        // Default to San Francisco if parsing fails
        return CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    }
}