//  LocationPhotosView.swift
//  Iconik Employee — Location Photos, converted in AMB.7
//
//  Replaces Misc Features/LocationPhotoAttachmentView.swift, deleted in the same
//  commit. `LabeledImage`, `PhotoSource`, `LocationManager` and
//  `CustomImagePicker` live here now because that file was their only home and
//  `Settings/SchoolDetailView` still uses `LabeledImage`.
//
//  THE THING TO NOTICE WHILE USING IT, AND THE REASON THE SCREEN SAYS SO
//      Staged photos exist only in memory until Upload is pressed, so leaving
//      loses them — unlike its sibling Photoshoot Notes, which saves on every
//      keystroke. Two screens in one family with opposite promises about your
//      work is worth a sentence rather than a surprise.
//
//  THE SCREEN CAN ONLY ADD
//      Deleting an already-uploaded location photo lives in
//      Settings/SchoolDetailView, a different screen entirely. Unchanged, said
//      out loud.
//
//  A LIVE DATA-LOSS PATH THAT IS RECORDED AND NOT REPAIRED HERE
//      Finding R7: the upload does a read-modify-write of the whole
//      `schools.location_photos` array, and the parser it reads through
//      SWALLOWS a decode failure and returns an empty array — so a blob it
//      cannot parse is REPLACED by just the new photos. That writes to `schools`,
//      a table SHARED with the web app and Captura, which is exactly why a
//      design phase does not touch it. It needs its own change with the shared-DB
//      blast radius thought through.
//
//  ONE THING THE OLD SCREEN DID THAT IS GONE ON PURPOSE
//      It put a location button in the LEADING toolbar slot — where the shell
//      also injects Home, so the screen showed two leading items. The detect
//      button now sits beside the school picker, where the thing it changes is.

import SwiftUI
import CoreLocation

/// A staged photo and the label typed under it.
/// Also used by `Settings/SchoolDetailView`.
struct LabeledImage: Identifiable, Hashable {
    let id = UUID()
    var image: UIImage
    var label: String
    var source: PhotoSource = .library
}

enum PhotoSource {
    case camera
    case library
}

struct LocationPhotosView: View {

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    @State private var schoolOptions: [SchoolItem] = []
    @State private var selectedSchool: SchoolItem?
    @State private var isLoadingSchools = true
    @State private var showSchoolPicker = false

    @State private var staged: [LabeledImage] = []
    @State private var showSourceDialog = false
    @State private var showCamera = false
    @State private var showLibrary = false

    @State private var isUploading = false
    @State private var didUpload = false
    @State private var isDetecting = false
    @State private var detectMessage = ""
    @State private var errorMessage = ""

    @StateObject private var locationManager = LocationManager()

    private var feature: Color { FeatureTheme.color(for: "locationPhotos") }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    locationSection
                    if staged.isEmpty { emptyState } else { grid }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()

            if isUploading || isDetecting { loadingOverlay }
            if didUpload { uploadedOverlay }
        }
        .navigationTitle("Location Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSourceDialog = true } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                }
                .disabled(selectedSchool == nil)
            }
        }
        .onAppear {
            loadSchools()
            locationManager.requestAuthorization()
        }
        .sheet(isPresented: $showSchoolPicker) {
            ReportSchoolPickerSheet(
                schools: $schoolOptions,
                chosen: [],
                organizationID: storedUserOrganizationID,
                onPick: { school in
                    withAnimation(AmbientMotion.gentle) { selectedSchool = school }
                    showSchoolPicker = false
                },
                onCancel: { showSchoolPicker = false })
        }
        .sheet(isPresented: $showCamera) {
            CustomImagePicker(selectedImage: Binding(
                get: { nil },
                set: { image in
                    if let image { staged.append(LabeledImage(image: image, label: "", source: .camera)) }
                }), sourceType: .camera)
        }
        .sheet(isPresented: $showLibrary) {
            CustomImagePicker(selectedImage: Binding(
                get: { nil },
                set: { image in
                    if let image { staged.append(LabeledImage(image: image, label: "", source: .library)) }
                }), sourceType: .photoLibrary)
        }
        .confirmationDialog("Add Photo", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            Button("Photo Library") { showLibrary = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose a source")
        }
        .alert("Error", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Location")

            if isLoadingSchools && schoolOptions.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading locations…").font(.subheadline).foregroundStyle(.secondary)
                }
                .ambientCard(density: .compact, fillWidth: true)
            } else {
                HStack(spacing: 8) {
                    Button { showSchoolPicker = true } label: {
                        HStack {
                            Text(selectedSchool?.name ?? "Select a school")
                                .font(.subheadline)
                                .foregroundStyle(selectedSchool == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .ambientCard(density: .compact, fillWidth: true)
                    }
                    .buttonStyle(.plain)

                    Button(action: detectCurrentLocation) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(feature)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDetecting)
                    .accessibilityLabel("Detect current school")
                }
            }

            if !detectMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.caption2)
                    Text(detectMessage).font(.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        AmbientEmptyState(
            title: "No Photos Added",
            message: "Add photos to help others identify this location.",
            systemImage: "photo.on.rectangle.angled",
            // The call to action switches on whether a school is chosen yet,
            // which is the shipped behaviour.
            actionTitle: selectedSchool == nil ? "Detect Current School" : "Add Photo",
            actionIcon: selectedSchool == nil ? "location.circle.fill" : "plus.circle.fill",
            action: {
                if selectedSchool == nil { detectCurrentLocation() } else { showSourceDialog = true }
            },
            actionTint: feature)
    }

    /// The one adaptive grid in the family — kept, because a location photo is
    /// being looked AT rather than counted, so it earns the size.
    private var grid: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Photos", trailing: "\(staged.count) staged")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], spacing: 12) {
                ForEach($staged) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        Image(uiImage: item.image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130)
                            // ambient-allow: a photo is content, not a card.
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    withAnimation(AmbientMotion.snappy) {
                                        staged.removeAll { $0.id == item.id }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove photo")
                            }

                        HStack(spacing: 4) {
                            Image(systemName: item.source == .camera ? "camera.fill" : "photo.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(feature)
                            Text(item.source == .camera ? "Camera" : "Library")
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        TextField("Enter label", text: $item.label)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 7)
                            // ambient-allow: an input well, not a card.
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.1)))
                    }
                }
            }

            Button(action: uploadPhotos) {
                Text("Upload Photos")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    // ambient-allow: a filled primary action is a control.
                    .background(Capsule().fill(selectedSchool == nil ? Color.gray : feature))
            }
            .buttonStyle(.plain)
            .disabled(selectedSchool == nil || isUploading)

            Text("An unlabelled photo is stored as “Location Photo”. These exist only in memory until Upload is pressed — leaving the screen loses them. Deleting an already-uploaded photo happens in Settings, not here.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Overlays

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text(isDetecting ? "Detecting Location…" : "Uploading Photos…")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
        }
    }

    private var uploadedOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(.green)
                Text("Photos Uploaded!").font(.title3.weight(.bold))
                Text("Your photos have been successfully uploaded to \(selectedSchool?.name ?? "the location").")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .ambientCard(density: .hero, state: .highlighted, contentAlignment: .center)
            .padding(.horizontal, 32)
        }
        .task(id: didUpload) {
            guard didUpload else { return }
            // Auto-dismisses after 2 seconds and CLEARS the staged photos — the
            // screen's only reset, and it is the shipped behaviour.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(AmbientMotion.gentle) {
                didUpload = false
                staged.removeAll()
            }
        }
    }

    // MARK: - Data

    private func loadSchools() {
        guard !storedUserOrganizationID.isEmpty else {
            isLoadingSchools = false
            errorMessage = "User organization not found"
            return
        }
        Task {
            do {
                let schools = try await SchoolService.shared.getSchools(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    schoolOptions = ReportSchoolItem.make(from: schools)
                    isLoadingSchools = false
                }
            } catch {
                await MainActor.run {
                    isLoadingSchools = false
                    errorMessage = "Error loading schools: \(error.localizedDescription)"
                }
            }
        }
    }

    private func uploadPhotos() {
        guard let school = selectedSchool else {
            errorMessage = "Please select a location."
            return
        }
        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "User organization not found"
            return
        }

        isUploading = true
        let items = staged
        let organizationID = storedUserOrganizationID

        Task {
            do {
                let storage = SupabaseManager.shared.client.storage
                var uploaded: [[String: String]] = []

                for item in items {
                    guard let data = item.image.downsampledJPEGData(maxDimension: 2048, quality: 0.8) else { continue }
                    let path = "location-photos/\(organizationID.lowercased())/\(school.id.lowercased())/\(Date().timeIntervalSince1970)_\(UUID().uuidString).jpg"
                    _ = try await storage.from("daily-reports").upload(path, data: data)
                    let signed = try await storage.from("daily-reports")
                        .createSignedURL(path: path, expiresIn: 31_536_000)
                    uploaded.append([
                        "url": signed.absoluteString,
                        "label": item.label.isEmpty ? "Location Photo" : item.label
                    ])
                }

                // Read-modify-write of the whole array, unchanged — see finding
                // R7 in the header. Repairing it is a shared-DB change.
                if let existing = try await SchoolService.shared.getSchool(schoolId: school.id) {
                    let previous = existing.parsedLocationPhotos.map { ["url": $0.url, "label": $0.label] }
                    try await SchoolService.shared.updateLocationPhotos(schoolId: school.id,
                                                                        photos: previous + uploaded)
                } else {
                    try await SchoolService.shared.updateLocationPhotos(schoolId: school.id, photos: uploaded)
                }

                await MainActor.run {
                    isUploading = false
                    withAnimation(AmbientMotion.gentle) { didUpload = true }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    errorMessage = "Upload error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Detection

    private func detectCurrentLocation() {
        guard locationManager.authorizationStatus == .authorizedWhenInUse
                || locationManager.authorizationStatus == .authorizedAlways else {
            detectMessage = "Location access required for auto-detection"
            return
        }
        guard !schoolOptions.isEmpty else {
            detectMessage = "No schools available to match location"
            return
        }

        isDetecting = true
        detectMessage = ""
        locationManager.requestLocation()

        Task {
            // The delegate delivers asynchronously; the live screen waited half a
            // second for it and this keeps that timing rather than changing what
            // the operator has been using.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let here = locationManager.location else {
                await MainActor.run {
                    isDetecting = false
                    detectMessage = "Could not determine your location"
                }
                return
            }
            let (nearest, distance) = await nearestSchool(to: here)
            await MainActor.run {
                isDetecting = false
                guard let nearest else {
                    detectMessage = "No nearby schools found"
                    return
                }
                withAnimation(AmbientMotion.gentle) { selectedSchool = nearest }
                if distance < 500 {
                    detectMessage = "You are at \(nearest.name)"
                } else if distance < 5000 {
                    detectMessage = "Nearest school: \(nearest.name) (\(Int(distance))m away)"
                } else {
                    detectMessage = "Selected \(nearest.name) (\(Int(distance / 1000))km away)"
                }
            }
        }
    }

    private func nearestSchool(to here: CLLocation) async -> (SchoolItem?, CLLocationDistance) {
        var nearest: SchoolItem?
        var shortest = CLLocationDistance.greatestFiniteMagnitude
        let geocoder = CLGeocoder()

        for school in schoolOptions {
            // Prefer the school's own coordinates; the address is the fallback
            // and needs geocoding, exactly as before.
            var coordinate = Self.parseCoordinate(school.coordinates ?? "")
                ?? Self.parseCoordinate(school.address)
            if coordinate == nil, !school.address.isEmpty {
                coordinate = (try? await geocoder.geocodeAddressString(school.address))?
                    .first?.location?.coordinate
            }
            guard let coordinate else { continue }
            let distance = here.distance(from: CLLocation(latitude: coordinate.latitude,
                                                          longitude: coordinate.longitude))
            if distance < shortest {
                shortest = distance
                nearest = school
            }
        }
        return (nearest, shortest)
    }

    private static func parseCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Location manager

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestLocation() { manager.requestLocation() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        DispatchQueue.main.async { self.location = last }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async { self.authorizationStatus = status }
    }
}

// MARK: - Picker

/// Camera or library, with a simulator-safe fallback.
struct CustomImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selectedImage: UIImage?
    let sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = (sourceType == .camera && UIImagePickerController.isSourceTypeAvailable(.camera))
            ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CustomImagePicker
        init(_ parent: CustomImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.selectedImage = image }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
