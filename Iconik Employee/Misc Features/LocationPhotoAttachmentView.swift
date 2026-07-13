import SwiftUI
import Supabase
import UIKit
import CoreLocation
import MapKit

// Helper struct for pairing a photo with its label.
struct LabeledImage: Identifiable, Hashable {
    let id = UUID()
    var image: UIImage
    var label: String
    var source: PhotoSource = .library
}

// Enum to track where a photo came from
enum PhotoSource {
    case camera
    case library
}

struct LocationPhotoAttachmentView: View {
    // School selection
    @State private var schoolOptions: [SchoolItem] = []
    @State private var selectedSchool: SchoolItem? = nil
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
    
    // Photo management
    @State private var labeledImages: [LabeledImage] = []
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
    
    // UI State
    @State private var uploadStatusMessage: String = ""
    @State private var errorMessage: String = ""
    @State private var isUploading: Bool = false
    @State private var showingOptions = false
    
    // Location detection
    @StateObject private var locationManager = LocationManager()
    @State private var isDetectingLocation: Bool = false
    @State private var locationDetectionMessage: String = ""
    
    // For animations
    @State private var animateSuccess = false
    
    // Environment
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
                // Main content
                VStack(spacing: 0) {
                    // Header with location selector
                    VStack(spacing: 20) {
                        schoolSelectorSection
                        
                        // Photo grid or empty state
                        if labeledImages.isEmpty {
                            emptyStateView
                        } else {
                            photoGridSection
                        }
                        
                        // Upload button
                        if selectedSchool != nil && !labeledImages.isEmpty {
                            uploadButton
                        }
                    }
                    .padding()
                }
                
                // Success overlay
                if animateSuccess {
                    successOverlay
                }
                
                // Loading overlay
                if isUploading || isDetectingLocation {
                    loadingOverlay
                }
            }
            .navigationTitle("Location Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingOptions = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .disabled(selectedSchool == nil)
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: detectCurrentLocation) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
            }
            .actionSheet(isPresented: $showingOptions) {
                ActionSheet(
                    title: Text("Add Photo"),
                    message: Text("Choose a source"),
                    buttons: [
                        .default(Text("Take Photo")) {
                            self.sourceType = .camera
                            self.showingCamera = true
                        },
                        .default(Text("Photo Library")) {
                            self.sourceType = .photoLibrary
                            self.showingImagePicker = true
                        },
                        .cancel()
                    ]
                )
            }
            .sheet(isPresented: $showingImagePicker) {
                CustomImagePicker(selectedImage: Binding(
                    get: { nil },
                    set: { newImage in
                        if let image = newImage {
                            // Append a new labeled image with an empty label
                            labeledImages.append(LabeledImage(image: image, label: "", source: .library))
                        }
                    }
                ), sourceType: .photoLibrary)
            }
            .sheet(isPresented: $showingCamera) {
                CustomImagePicker(selectedImage: Binding(
                    get: { nil },
                    set: { newImage in
                        if let image = newImage {
                            // Append a new labeled image with an empty label
                            labeledImages.append(LabeledImage(image: image, label: "", source: .camera))
                        }
                    }
                ), sourceType: .camera)
            }
            .alert(isPresented: .constant(!errorMessage.isEmpty)) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK")) {
                        errorMessage = ""
                    }
                )
            }
        .onAppear {
            loadSchoolOptions()
            
            // Request location authorization
            locationManager.requestAuthorization()
        }
    }
    
    // MARK: - UI Components
    
    private var schoolSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Select Location")
                    .font(.headline)
                    .padding(.horizontal, 4)
                
                Spacer()
                
                if !locationDetectionMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        
                        Text(locationDetectionMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6).opacity(0.7))
                    .cornerRadius(12)
                }
            }
            
            if schoolOptions.isEmpty {
                HStack {
                    Text("Loading locations...")
                        .foregroundColor(.secondary)
                    Spacer()
                    ProgressView()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                )
            } else {
                HStack {
                    SearchableSchoolPicker(
                        selection: $selectedSchool,
                        schools: $schoolOptions,
                        title: "Select Location",
                        organizationID: storedUserOrganizationID
                    )
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button(action: detectCurrentLocation) {
                        Image(systemName: "location.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(isDetectingLocation)
                    .padding(.trailing, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 70))
                    .foregroundColor(.gray.opacity(0.7))
                
                Text("No Photos Added")
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text("Add photos to help others identify this location")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if selectedSchool != nil {
                Button(action: {
                    showingOptions = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Photo")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            } else {
                Button(action: detectCurrentLocation) {
                    HStack {
                        Image(systemName: "location.circle.fill")
                        Text("Detect Current School")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isDetectingLocation)
                .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
    
    private var photoGridSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Photos")
                .font(.headline)
                .padding(.horizontal, 4)
                .padding(.top, 8)
            
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
                ], spacing: 16) {
                    ForEach(Array(labeledImages.enumerated()), id: \.element.id) { index, labeledImage in
                        photoGridItem(labeledImage: labeledImage, index: index)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 500)
        }
    }
    
    private func photoGridItem(labeledImage: LabeledImage, index: Int) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: labeledImage.image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .clipped()
                    .cornerRadius(12)
                
                Button(action: {
                    labeledImages.remove(at: index)
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(8)
            }
            
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: labeledImage.source == .camera ? "camera.fill" : "photo.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Text(labeledImage.source == .camera ? "Camera" : "Library")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                TextField("Enter label", text: Binding(
                    get: { labeledImage.label },
                    set: { newValue in
                        if let index = labeledImages.firstIndex(where: { $0.id == labeledImage.id }) {
                            labeledImages[index].label = newValue
                        }
                    }
                ))
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .font(.subheadline)
            }
        }
    }
    
    private var uploadButton: some View {
        Button(action: uploadLocationPhotos) {
            HStack {
                Text("Upload Photos")
                    .fontWeight(.semibold)
                
                if isUploading {
                    ProgressView()
                        .padding(.leading, 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue)
            )
            .foregroundColor(.white)
        }
        .disabled(isUploading)
        .padding(.top, 16)
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text(isDetectingLocation ? "Detecting Location..." : "Uploading Photos...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground).opacity(0.8))
            )
        }
    }
    
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Photos Uploaded!")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("Your photos have been successfully uploaded to \(selectedSchool?.name ?? "the location")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 10)
            )
            .transition(.scale.combined(with: .opacity))
        }
        .onAppear {
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    animateSuccess = false
                    // Reset photos
                    labeledImages = []
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6).opacity(0.5)
    }
    
    // MARK: - Location Detection Functions
    
    private func detectCurrentLocation() {
        // Make sure we have location authorization
        guard locationManager.authorizationStatus == .authorizedWhenInUse ||
              locationManager.authorizationStatus == .authorizedAlways else {
            locationDetectionMessage = "Location access required for auto-detection"
            return
        }
        
        // Make sure we have schools loaded
        guard !schoolOptions.isEmpty else {
            locationDetectionMessage = "No schools available to match location"
            return
        }
        
        isDetectingLocation = true
        locationDetectionMessage = ""
        
        // Get the current location
        locationManager.requestLocation()
        
        // Continue processing after we get a location update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let currentLocation = locationManager.location else {
                isDetectingLocation = false
                locationDetectionMessage = "Could not determine your location"
                return
            }
            
            findNearestSchool(to: currentLocation) { nearestSchool, distance in
                isDetectingLocation = false
                
                if let school = nearestSchool {
                    withAnimation {
                        selectedSchool = school
                    }
                    
                    if distance < 500 {
                        // Within 500 meters, so likely at the school
                        locationDetectionMessage = "You are at \(school.name)"
                    } else if distance < 5000 {
                        // Within 5km, so nearby
                        locationDetectionMessage = "Nearest school: \(school.name) (\(Int(distance))m away)"
                    } else {
                        // More than 5km away
                        locationDetectionMessage = "Selected \(school.name) (\(Int(distance/1000))km away)"
                    }
                } else {
                    locationDetectionMessage = "No nearby schools found"
                }
            }
        }
    }
    
    private func findNearestSchool(to currentLocation: CLLocation, completion: @escaping (SchoolItem?, Double) -> Void) {
        var nearestSchool: SchoolItem? = nil
        var shortestDistance: CLLocationDistance = Double.greatestFiniteMagnitude
        
        // Create a dispatch group to track async operations
        let group = DispatchGroup()
        
        for school in schoolOptions {
            group.enter()
            
            // Try to parse coordinates from the school address
            if let coordinates = parseCoordinates(from: school.address) {
                let schoolLocation = CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
                let distance = currentLocation.distance(from: schoolLocation)
                
                if distance < shortestDistance {
                    shortestDistance = distance
                    nearestSchool = school
                }
                
                group.leave()
            } else {
                // If we can't parse coordinates, try to geocode the address
                geocodeAddress(school.address) { coordinate in
                    if let coordinate = coordinate {
                        let schoolLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        let distance = currentLocation.distance(from: schoolLocation)
                        
                        if distance < shortestDistance {
                            shortestDistance = distance
                            nearestSchool = school
                        }
                    }
                    
                    group.leave()
                }
            }
        }
        
        // Once all schools have been processed, return the nearest one
        group.notify(queue: .main) {
            completion(nearestSchool, shortestDistance)
        }
    }
    
    private func parseCoordinates(from addressString: String) -> CLLocationCoordinate2D? {
        // Try to parse strings like "37.7749,-122.4194"
        let components = addressString.split(separator: ",").compactMap { Double(String($0).trimmingCharacters(in: .whitespaces)) }

        guard components.count == 2,
              let latitude = components.first,
              let longitude = components.last else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    private func geocodeAddress(_ address: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let geocoder = CLGeocoder()
        
        geocoder.geocodeAddressString(address) { placemarks, error in
            if let error = error {
                print("Geocoding error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            if let placemark = placemarks?.first, let location = placemark.location {
                completion(location.coordinate)
            } else {
                completion(nil)
            }
        }
    }
    
    // MARK: - Data Functions
    
    private func loadSchoolOptions() {
        // Check for organization ID
        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "User organization not found"
            return
        }

        Task {
            do {
                let schools = try await SchoolService.shared.getSchools(organizationID: storedUserOrganizationID)

                // Convert to SchoolItem format
                let items = schools.map { school in
                    SchoolItem(
                        id: school.id,
                        name: school.name,
                        address: school.address ?? "",
                        coordinates: school.coordinates
                    )
                }.sorted { $0.name.lowercased() < $1.name.lowercased() }

                await MainActor.run {
                    self.schoolOptions = items
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error loading schools: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func uploadLocationPhotos() {
        guard let school = selectedSchool else {
            errorMessage = "Please select a location."
            return
        }

        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "User organization not found"
            return
        }

        isUploading = true

        Task {
            do {
                let supabase = SupabaseManager.shared.client
                var uploadedPhotoDicts: [[String: String]] = []

                for labeledImage in self.labeledImages {
                    guard let imageData = labeledImage.image.downsampledJPEGData(maxDimension: 2048, quality: 0.8) else { continue }

                    // Use lowercase IDs per CLAUDE.md guidelines
                    let path = "location-photos/\(storedUserOrganizationID.lowercased())/\(school.id.lowercased())/\(Date().timeIntervalSince1970)_\(UUID().uuidString).jpg"

                    print("📸 Uploading location photo to Supabase Storage: \(path)")

                    // Upload to Supabase Storage
                    _ = try await supabase.storage
                        .from("daily-reports")
                        .upload(
                            path: path,
                            file: imageData,
                            options: FileOptions(contentType: "image/jpeg")
                        )

                    // Get signed URL (1 year expiry for private access)
                    let signedURL = try await supabase.storage
                        .from("daily-reports")
                        .createSignedURL(path: path, expiresIn: 31536000)

                    // Create a dictionary with URL and label
                    let dict: [String: String] = [
                        "url": signedURL.absoluteString,
                        "label": labeledImage.label.isEmpty ? "Location Photo" : labeledImage.label
                    ]
                    uploadedPhotoDicts.append(dict)
                    print("📸 Photo uploaded: \(signedURL.absoluteString.prefix(80))...")
                }

                // Get existing photos and append new ones
                if let existingSchool = try await SchoolService.shared.getSchool(schoolId: school.id) {
                    let existingPhotos = existingSchool.parsedLocationPhotos.map { ["url": $0.url, "label": $0.label] }
                    let allPhotos = existingPhotos + uploadedPhotoDicts

                    try await SchoolService.shared.updateLocationPhotos(schoolId: school.id, photos: allPhotos)
                } else {
                    // No existing school found, just save the new photos
                    try await SchoolService.shared.updateLocationPhotos(schoolId: school.id, photos: uploadedPhotoDicts)
                }

                await MainActor.run {
                    self.isUploading = false
                    // Show success animation
                    withAnimation(.spring()) {
                        self.animateSuccess = true
                    }
                }
                print("✅ Location photos saved to Supabase")

            } catch {
                print("❌ Location photo upload failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.isUploading = false
                    self.errorMessage = "Upload error: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus
    
    override init() {
        authorizationStatus = locationManager.authorizationStatus
        
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }
    
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        locationManager.requestLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        self.location = location
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
    }
}

// MARK: - Custom Image Picker

struct CustomImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selectedImage: UIImage?
    var sourceType: UIImagePickerController.SourceType
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        
        // Only set camera if it's available
        if sourceType == .camera && UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CustomImagePicker
        
        init(_ parent: CustomImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.selectedImage = uiImage
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Preview Provider

struct LocationPhotoAttachmentView_Previews: PreviewProvider {
    static var previews: some View {
        LocationPhotoAttachmentView()
    }
}
