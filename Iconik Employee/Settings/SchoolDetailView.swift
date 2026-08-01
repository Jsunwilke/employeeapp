//  SchoolDetailView.swift
//  Iconik Employee — one school, converted to Ambient in AMB.12
//
//  A SCHOOL SCREEN IS ABOUT A SCHOOL. The bar said "School Detail" on every school
//  in the organization; the school's name is the title now, and the hero carries the
//  name and address so the screen identifies itself before anything is tapped.
//
//  THE IMPORTANT FIX (G7): `loadMileageForSchool` and `loadDailyReportsForSchool`
//  keyed off `name` — the LIVE EDITABLE `@State` bound to the School Name field —
//  so typing in that field re-queried the half-typed name on every keystroke. The
//  queries key off `loadedName`, the name as the server stored it, which is also the
//  name the reports are actually filed under.
//
//  THE RENAME WARNING IS REAL, not a caution label. Every school↔report join in this
//  tree is by NAME (`SchoolInfoListView`, `DailyJobReportService.getReportsForSchool`),
//  and the rename was offered with no warning and no migration (G8). Rename still
//  happens behind the explicit Save.
//
//  ALSO FIXED HERE:
//    · A LOADING STATE. The form rendered immediately with an EMPTY name, an empty
//      address and 0.0 miles until the fetch landed, so a school with no data and a
//      school still loading looked identical.
//    · DELETING A LOCATION PHOTO ASKS FIRST, AND WRITES FIRST (G9/G30). The row was
//      removed from local state BEFORE the write, so a failed delete left the photo
//      gone from the UI and still in the database with no restore.
//    · SAVE HAS AN IN-FLIGHT DISABLE AND A NAME CHECK (G31). An empty name saved,
//      and repeated taps issued repeated UPDATEs.
//    · TWO FILE-SCOPE TYPES RENAMED (G48). `struct MapPin` SHADOWED SwiftUI's own
//      `MapPin`, and `struct Report` was a generic name at file scope.
//
//  NAMED, NOT FIXED: each location photo's URL is a SIGNED url with a one-year
//  expiry persisted into the database, so every location photo silently stops
//  loading a year after upload (G10); deleting a photo does not delete the storage
//  object, so files accumulate (G30); and `coordinates` is displayed and mapped but
//  can never be edited, and `updateSchool` is not called with it, so a mis-geocoded
//  school is unfixable from iOS (G29). All three are data-layer.
//
//  KEPT: every section, the season window label, the read-only report rows and the
//  "Report Details" screen behind them, and every message string.

import SwiftUI
import Supabase
import MapKit

/// One daily job report as this screen lists it. Renamed from `Report`, which was a
/// generic name sitting at file scope in a codebase full of reports (G48).
struct SchoolSeasonReport: Identifiable {
    let id: String
    let date: Date
    let totalMileage: Double
    let photographerName: String
}

/// The single map annotation. Renamed from `MapPin`, which SHADOWED SwiftUI's own
/// `MapPin` type across this whole module (G48).
struct SchoolLocationPin: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
}

struct SchoolDetailView: View {
    let schoolId: String

    /// The name as the SERVER stores it. Every query keys off this — never off the
    /// edit buffer below (G7).
    @State private var loadedName: String = ""

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var coordinates: String = ""
    @State private var locationPhotos: [LocationPhoto] = []

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isDeletingPhoto = false
    @State private var isUploadingPhoto = false

    /// Nil while in flight. A figure that has not arrived is not zero.
    @State private var seasonMileage: Double?
    @State private var mileageFailed = false
    @State private var dailyReports: [SchoolSeasonReport] = []
    @State private var reportsLoaded = false
    @State private var reportsFailed = false

    // Map state
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var pinLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    @State private var showMap: Bool = false

    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""

    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""

    // For adding a new photo.
    @State private var newLabeledImage: LabeledImage? = nil
    @State private var showingImagePicker = false
    @State private var pendingPhotoDelete: LocationPhoto?

    @State private var destination: ReportRoute?

    private struct ReportRoute: Identifiable, Hashable {
        let id: String
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isRenaming: Bool {
        !loadedName.isEmpty && trimmedName != loadedName
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isLoading {
                        AmbientLoadingRow(message: "Loading school…")
                    } else {
                        hero
                        detailsSection
                        renameWarning
                        seasonSection
                        reportsSection
                        photosSection
                        saveSection
                        messages
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .tabBarClearance()
        // THE TITLE IS THE SCHOOL'S NAME. Falls back to the shipped title only while
        // there is genuinely nothing to name it with.
        .navigationTitle(loadedName.isEmpty ? "School Detail" : loadedName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadSchoolInfo)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: Binding(
                get: { nil },
                set: { image in
                    if let image = image {
                        newLabeledImage = LabeledImage(image: image, label: "")
                    }
                }
            ))
        }
        .alert("Delete this photo?", isPresented: Binding(
            get: { pendingPhotoDelete != nil },
            set: { if !$0 { pendingPhotoDelete = nil } }
        ), presenting: pendingPhotoDelete) { photo in
            Button("Cancel", role: .cancel) { pendingPhotoDelete = nil }
            Button("Delete", role: .destructive) { deletePhoto(photo) }
        } message: { photo in
            Text(photo.label.isEmpty
                 ? "This removes the photo from this school for everyone."
                 : "“\(photo.label)” will be removed from this school for everyone.")
        }
        .ambientPush(item: $destination) { route in
            DailyReportDetailView(docID: route.id)
        }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loadedName.isEmpty ? "Unnamed school" : loadedName)
                .font(.system(size: 22, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(address.isEmpty ? "No address on file" : address)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private var detailsSection: some View {
        AmbientFormSection(title: "School Info",
                           status: isRenaming ? "renaming" : "",
                           statusTint: isRenaming ? .orange : nil) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("School Name")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("School Name", text: $name).font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Address")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("Address", text: $address).font(.subheadline)
                }

                if !coordinates.isEmpty {
                    Divider()
                    AmbientStatLine(label: "Coordinates", value: coordinates)

                    Button {
                        withAnimation(AmbientMotion.snappy) { showMap.toggle() }
                        AmbientHaptics.selection()
                    } label: {
                        Label(showMap ? "Hide Map" : "View on Map", systemImage: "map")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SettingsStyle.tint)
                    }
                    .buttonStyle(.plain)

                    if showMap {
                        Map(coordinateRegion: $region,
                            annotationItems: [SchoolLocationPin(coordinate: pinLocation)]) { pin in
                            MapAnnotation(coordinate: pin.coordinate) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(height: 200)
                        // ambient-allow: a map is a clipped view, not a container.
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    /// The warning sits WITH the field it is about. It is drawn always, not only
    /// once the name has been touched — by the time the name has been changed the
    /// reader has already decided to change it.
    private var renameWarning: some View {
        AmbientNoteCard(
            title: "Renaming a school",
            text: "Reports are matched to a school by its NAME. Renaming this school hides every daily job report and every mileage figure already filed under the old name.",
            accent: .orange,
            density: .compact)
    }

    private var seasonSection: some View {
        AmbientFormSection(title: "Season Mileage",
                           status: SettingsSeason.label,
                           statusTint: nil) {
            VStack(alignment: .leading, spacing: 6) {
                AmbientStatLine(label: "Total Miles Driven", value: mileageValue)
                AmbientStatLine(label: "Daily job reports this season", value: reportCountValue)
            }
        }
    }

    private var mileageValue: String {
        if let seasonMileage { return String(format: "%.1f miles", seasonMileage) }
        return mileageFailed ? "Couldn't load" : "Loading…"
    }

    private var reportCountValue: String {
        if reportsLoaded { return "\(dailyReports.count)" }
        return reportsFailed ? "Couldn't load" : "Loading…"
    }

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
            AmbientSectionTitle("Daily Job Reports (Current Season)")

            if !reportsLoaded && !reportsFailed {
                AmbientLoadingRow(message: "Loading reports…", density: .compact)
            } else if reportsFailed {
                AmbientFailureCard(message: "Couldn't load this school's reports.",
                                   action: loadDailyReportsForSchool)
            } else if dailyReports.isEmpty {
                Text("No reports found for this season.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dailyReports.sorted(by: { $0.date > $1.date })) { report in
                    Button {
                        destination = ReportRoute(id: report.id)
                    } label: {
                        reportRow(report)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func reportRow(_ report: SchoolSeasonReport) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(report.date, style: .date)
                    .font(AmbientDensity.compact.titleFont)
                Text("Mileage: \(report.totalMileage, specifier: "%.1f") miles • \(report.photographerName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var photosSection: some View {
        AmbientFormSection(title: "Location Photos",
                           status: locationPhotos.isEmpty ? "none" : "\(locationPhotos.count)",
                           statusTint: locationPhotos.isEmpty ? nil : .blue) {
            VStack(alignment: .leading, spacing: 10) {
                if locationPhotos.isEmpty {
                    Text("No photos attached.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(locationPhotos) { photo in
                                photoTile(photo)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }

                // New photo entry UI
                if let newImage = newLabeledImage {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(uiImage: newImage.image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            // ambient-allow: a staged photo thumbnail, not a container.
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        TextField("Enter photo label", text: Binding(
                            get: { newImage.label },
                            set: { newValue in
                                newLabeledImage?.label = newValue
                            }
                        ))
                        .font(.subheadline)
                    }
                }

                HStack(spacing: 8) {
                    AmbientActionButton(title: "Add Photo",
                                        systemImage: "photo.on.rectangle",
                                        role: .secondary,
                                        size: .small,
                                        fillWidth: false,
                                        isEnabled: !isUploadingPhoto,
                                        action: addPhoto)

                    if newLabeledImage != nil {
                        AmbientActionButton(title: "Upload New Photo",
                                            systemImage: "arrow.up.circle.fill",
                                            role: .primary,
                                            size: .small,
                                            tint: SettingsStyle.tint,
                                            fillWidth: false,
                                            isLoading: isUploadingPhoto,
                                            action: uploadNewPhoto)
                    }
                }
            }
        }
    }

    private func photoTile(_ photo: LocationPhoto) -> some View {
        VStack(spacing: 6) {
            AsyncImage(url: URL(string: photo.url)) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(width: 100, height: 100)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipped()
                        // ambient-allow: a photo thumbnail, not a container.
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                case .failure(_):
                    Image(systemName: "photo")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.gray)
                @unknown default:
                    EmptyView()
                }
            }
            Text(photo.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button {
                pendingPhotoDelete = photo
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(isDeletingPhoto)
            .accessibilityLabel("Delete photo")
        }
        .frame(width: 100)
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientActionButton(title: "Save Changes",
                                role: .primary,
                                tint: SettingsStyle.tint,
                                isLoading: isSaving,
                                isEnabled: !trimmedName.isEmpty,
                                action: saveChanges)

            if trimmedName.isEmpty {
                Text("Enter a school name before saving.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

    // MARK: - Data

    // Load school info then trigger mileage and report queries.
    func loadSchoolInfo() {
        Task {
            do {
                guard let school = try await SchoolService.shared.getSchool(schoolId: schoolId) else {
                    await MainActor.run {
                        errorMessage = "School not found"
                        isLoading = false
                    }
                    return
                }

                await MainActor.run {
                    loadedName = school.name
                    name = school.name
                    address = school.address ?? ""
                    coordinates = school.coordinates ?? ""

                    // Parse coordinates if available
                    if let coords = school.parsedCoordinates {
                        let location = CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng)
                        pinLocation = location
                        region = MKCoordinateRegion(
                            center: location,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    }

                    // Parse location photos from JSONB
                    locationPhotos = school.parsedLocationPhotos
                    isLoading = false

                    // Load mileage and reports
                    loadMileageForSchool()
                    loadDailyReportsForSchool()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    /// Keyed off `loadedName` — see G7 in the file header.
    func loadMileageForSchool() {
        guard let season = SettingsSeason.currentWindow(), !loadedName.isEmpty else { return }
        let schoolName = loadedName

        mileageFailed = false
        Task {
            do {
                let mileage = try await DailyJobReportService.shared.getMileageForSchool(
                    schoolName: schoolName,
                    organizationID: storedUserOrganizationID,
                    startDate: season.start,
                    endDate: season.end
                )
                await MainActor.run { self.seasonMileage = mileage }
            } catch {
                await MainActor.run { self.mileageFailed = true }
            }
        }
    }

    /// Keyed off `loadedName` — see G7 in the file header.
    func loadDailyReportsForSchool() {
        guard let season = SettingsSeason.currentWindow(), !loadedName.isEmpty else { return }
        let schoolName = loadedName

        reportsFailed = false
        Task {
            do {
                let supabaseReports = try await DailyJobReportService.shared.getReportsForSchool(
                    schoolName: schoolName,
                    organizationID: storedUserOrganizationID,
                    startDate: season.start,
                    endDate: season.end
                )

                let reports = supabaseReports.map { report in
                    SchoolSeasonReport(
                        id: report.id,
                        date: report.date,
                        totalMileage: report.total_mileage,
                        photographerName: report.your_name
                    )
                }

                await MainActor.run {
                    self.dailyReports = reports
                    self.reportsLoaded = true
                }
            } catch {
                await MainActor.run { self.reportsFailed = true }
            }
        }
    }

    func saveChanges() {
        // G31: an empty name used to save, and repeated taps issued repeated UPDATEs.
        guard !trimmedName.isEmpty, !isSaving else { return }
        let newName = trimmedName
        let newAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        errorMessage = ""
        successMessage = ""

        Task {
            do {
                try await SchoolService.shared.updateSchool(
                    schoolId: schoolId,
                    name: newName,
                    address: newAddress
                )
                await MainActor.run {
                    isSaving = false
                    successMessage = "School info updated!"
                    // The rename has landed, so the queries follow it — otherwise
                    // the screen would keep reporting the OLD name's mileage under
                    // the new name.
                    let renamed = newName != loadedName
                    loadedName = newName
                    address = newAddress
                    if renamed {
                        seasonMileage = nil
                        reportsLoaded = false
                        dailyReports = []
                        loadMileageForSchool()
                        loadDailyReportsForSchool()
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Asks first, then WRITES first. The row used to disappear from the screen
    /// before the write, so a failed delete left the photo gone from the UI and
    /// still in the database, with no way back (G9).
    func deletePhoto(_ photo: LocationPhoto) {
        pendingPhotoDelete = nil
        guard !isDeletingPhoto else { return }
        let remaining = locationPhotos.filter { $0.id != photo.id }
        isDeletingPhoto = true
        errorMessage = ""
        successMessage = ""

        Task {
            do {
                let photoDicts = remaining.map { ["url": $0.url, "label": $0.label] }
                try await SchoolService.shared.updateLocationPhotos(schoolId: schoolId, photos: photoDicts)
                await MainActor.run {
                    locationPhotos = remaining
                    isDeletingPhoto = false
                    successMessage = "Photo deleted."
                }
            } catch {
                await MainActor.run {
                    isDeletingPhoto = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Same permission gate as the profile photo screen — `ImagePicker` wraps
    /// `UIImagePickerController`, which needs authorisation (G35).
    private func addPhoto() {
        SettingsPhotoAccess.request { granted in
            if granted {
                errorMessage = ""
                showingImagePicker = true
            } else {
                errorMessage = SettingsPhotoAccess.deniedMessage
            }
        }
    }

    func uploadNewPhoto() {
        guard let newLabeledImage = newLabeledImage, !isUploadingPhoto else { return }
        guard let imageData = newLabeledImage.image.downsampledJPEGData(maxDimension: 2048, quality: 0.8) else {
            errorMessage = "Could not compress image."
            return
        }

        isUploadingPhoto = true
        errorMessage = ""
        successMessage = ""

        Task {
            do {
                let supabase = SupabaseManager.shared.client

                // A storage OBJECT KEY, not a database filter — folding the case
                // here buys a stable path and matches nothing in a column.
                let path = "location-photos/\(storedUserOrganizationID.lowercased())/\(schoolId.lowercased())/\(Date().timeIntervalSince1970)_\(UUID().uuidString).jpg"

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

                let urlString = signedURL.absoluteString
                print("📸 Location photo uploaded. URL: \(urlString.prefix(80))...")

                let newPhoto = LocationPhoto(url: urlString, label: newLabeledImage.label)
                let updated = self.locationPhotos + [newPhoto]

                // Update Supabase with the new photos array BEFORE the screen shows
                // it, for the same reason the delete does.
                let photoDicts = updated.map { ["url": $0.url, "label": $0.label] }
                try await SchoolService.shared.updateLocationPhotos(schoolId: self.schoolId, photos: photoDicts)

                await MainActor.run {
                    self.locationPhotos = updated
                    self.successMessage = "New photo uploaded."
                    self.newLabeledImage = nil
                    self.isUploadingPhoto = false
                }
                print("✅ Location photo saved to Supabase")

            } catch {
                print("❌ Location photo upload failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isUploadingPhoto = false
                }
            }
        }
    }
}

// MARK: - Report Details

/// READ-ONLY, and it stays read-only: no edit, no delete, no share, no toolbar.
/// Every conditional row it draws is kept.
struct DailyReportDetailView: View {
    let docID: String

    @State private var report: DailyJobReport?
    @State private var isLoading = true
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isLoading {
                        AmbientLoadingRow(message: "Loading Report...")
                    } else if !errorMessage.isEmpty {
                        AmbientFailureCard(message: errorMessage, tint: .red, action: loadReport)
                    } else if let report = report {
                        headerSection(report: report)
                        detailsSection(report: report)
                        if let photoURLs = report.photo_urls, !photoURLs.isEmpty {
                            photosSection(photoURLs: photoURLs)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .tabBarClearance()
        .navigationTitle("Report Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadReport)
    }

    private func headerSection(report: DailyJobReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.date, style: .date)
                .font(.system(size: 22, weight: .bold))
            Text("Photographer: \(report.your_name)")
                .font(.subheadline.weight(.semibold))
            Text("School: \(report.school_or_destination ?? "Unknown")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .ambientCard(density: .hero, state: .highlighted, fillWidth: true)
    }

    private func detailsSection(report: DailyJobReport) -> some View {
        AmbientFormSection(title: "Details", status: "", statusTint: nil) {
            VStack(alignment: .leading, spacing: 8) {
                AmbientStatLine(label: "Mileage:",
                                value: String(format: "%.1f miles", report.total_mileage))

                if let jobNotes = report.job_description_text, !jobNotes.isEmpty {
                    block(title: "Job Notes:", body: jobNotes)
                }
                if let jobDescriptions = report.job_descriptions, !jobDescriptions.isEmpty {
                    block(title: "Job Descriptions:", body: jobDescriptions.joined(separator: ", "))
                }
                if let extraItems = report.extra_items, !extraItems.isEmpty {
                    block(title: "Extra Items:", body: extraItems.joined(separator: ", "))
                }
                if let cardsScanned = report.cards_scanned_choice {
                    AmbientStatLine(label: "Cards Scanned:", value: cardsScanned)
                }
                if let boxCards = report.job_box_and_camera_cards {
                    AmbientStatLine(label: "Job Box/Camera Cards:", value: boxCards)
                }
                if let sportsShot = report.sports_background_shot {
                    AmbientStatLine(label: "Sports Background Shot:", value: sportsShot)
                }
            }
        }
    }

    private func block(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func photosSection(photoURLs: [String]) -> some View {
        AmbientFormSection(title: "Attached Photos:",
                           status: "\(photoURLs.count)",
                           statusTint: .blue) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photoURLs, id: \.self) { urlStr in
                        if let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 100, height: 100)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipped()
                                        // ambient-allow: a photo thumbnail, not a container.
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                case .failure(_):
                                    Image(systemName: "photo")
                                        .resizable()
                                        .frame(width: 100, height: 100)
                                        .foregroundColor(.gray)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func loadReport() {
        isLoading = true
        errorMessage = ""
        Task {
            do {
                let fetchedReport = try await DailyJobReportService.shared.getReport(reportId: docID)
                await MainActor.run {
                    if let fetchedReport = fetchedReport {
                        self.report = fetchedReport
                    } else {
                        self.errorMessage = "No data found."
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
