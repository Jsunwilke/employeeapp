import SwiftUI
import Supabase
import MapKit

// Inline struct for daily reports used only in this view.
struct Report: Identifiable {
    let id: String
    let date: Date
    let totalMileage: Double
    let photographerName: String
}

struct SchoolDetailView: View {
    let schoolId: String
    
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var coordinates: String = ""
    @State private var locationPhotos: [LocationPhoto] = []
    @State private var seasonMileage: Double = 0.0  // Total season mileage
    @State private var dailyReports: [Report] = []  // Daily reports for current season
    
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
    
    var body: some View {
        Form {
            Section(header: Text("School Info")) {
                TextField("School Name", text: $name)
                TextField("Address", text: $address)
                
                if !coordinates.isEmpty {
                    HStack {
                        Text("Coordinates")
                        Spacer()
                        Text(coordinates)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("View on Map") {
                        showMap.toggle()
                    }
                    
                    if showMap {
                        Map(coordinateRegion: $region, annotationItems: [MapPin(coordinate: pinLocation)]) { pin in
                            MapAnnotation(coordinate: pin.coordinate) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(height: 200)
                        .cornerRadius(8)
                    }
                }
            }
            
            Section(header: Text("Season Mileage (Jul 15 - Jun 1)")) {
                Text("Total Miles Driven: \(seasonMileage, specifier: "%.1f") miles")
                    .font(.body)
            }
            
            // Daily Job Reports Section
            Section(header: Text("Daily Job Reports (Current Season)")) {
                if dailyReports.isEmpty {
                    Text("No reports found for this season.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(dailyReports.sorted(by: { $0.date > $1.date })) { report in
                        NavigationLink(destination: DailyReportDetailView(docID: report.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(report.date, style: .date)
                                    .font(.headline)
                                Text("Mileage: \(report.totalMileage, specifier: "%.1f") miles • \(report.photographerName)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            
            // Location Photos Section
            Section(header: Text("Location Photos")) {
                if locationPhotos.isEmpty {
                    Text("No photos attached.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(locationPhotos) { photo in
                                VStack {
                                    AsyncImage(url: URL(string: photo.url)) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipped()
                                                .cornerRadius(8)
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
                                        .foregroundColor(.secondary)
                                    Button(action: {
                                        deletePhoto(photo)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // New photo entry UI
                if let newImage = newLabeledImage {
                    VStack {
                        Image(uiImage: newImage.image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .cornerRadius(8)
                        TextField("Enter photo label", text: Binding(
                            get: { newImage.label },
                            set: { newValue in
                                newLabeledImage?.label = newValue
                            }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                Button("Add Photo") {
                    showingImagePicker = true
                }
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
                if newLabeledImage != nil {
                    Button("Upload New Photo") {
                        uploadNewPhoto()
                    }
                }
            }
            
            Section {
                Button("Save Changes") {
                    saveChanges()
                }
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            if !successMessage.isEmpty {
                Text(successMessage)
                    .foregroundColor(.green)
            }
        }
        .navigationTitle("School Detail")
        .onAppear {
            loadSchoolInfo()
        }
    }
    
    // Load school info then trigger mileage and report queries.
    func loadSchoolInfo() {
        Task {
            do {
                guard let school = try await SchoolService.shared.getSchool(schoolId: schoolId) else {
                    await MainActor.run {
                        errorMessage = "School not found"
                    }
                    return
                }

                await MainActor.run {
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

                    // Load mileage and reports
                    loadMileageForSchool()
                    loadDailyReportsForSchool()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // Load total mileage for the school in the current season.
    func loadMileageForSchool() {
        guard let seasonDates = currentSchoolSeasonDates() else { return }
        let seasonStart = seasonDates.start
        let seasonEnd = seasonDates.end

        Task {
            do {
                let mileage = try await DailyJobReportService.shared.getMileageForSchool(
                    schoolName: name,
                    organizationID: storedUserOrganizationID,
                    startDate: seasonStart,
                    endDate: seasonEnd
                )
                await MainActor.run {
                    self.seasonMileage = mileage
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // Load daily job reports (with photographer name) for the current season.
    func loadDailyReportsForSchool() {
        guard let seasonDates = currentSchoolSeasonDates() else { return }
        let seasonStart = seasonDates.start
        let seasonEnd = seasonDates.end

        Task {
            do {
                let supabaseReports = try await DailyJobReportService.shared.getReportsForSchool(
                    schoolName: name,
                    organizationID: storedUserOrganizationID,
                    startDate: seasonStart,
                    endDate: seasonEnd
                )

                // Convert to local Report struct
                let reports = supabaseReports.map { report in
                    Report(
                        id: report.id,
                        date: report.date,
                        totalMileage: report.total_mileage,
                        photographerName: report.your_name
                    )
                }

                await MainActor.run {
                    self.dailyReports = reports
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // Compute the current school season based on today's date.
    func currentSchoolSeasonDates() -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let today = Date()
        let year = calendar.component(.year, from: today)
        guard let july15ThisYear = calendar.date(from: DateComponents(year: year, month: 7, day: 15)),
              let june1ThisYear = calendar.date(from: DateComponents(year: year, month: 6, day: 1))
        else { return nil }
        
        if today >= july15ThisYear {
            let seasonStart = july15ThisYear
            let seasonEnd = calendar.date(from: DateComponents(year: year + 1, month: 6, day: 1))!
            return (seasonStart, seasonEnd)
        } else {
            let seasonStart = calendar.date(from: DateComponents(year: year - 1, month: 7, day: 15))!
            let seasonEnd = june1ThisYear
            return (seasonStart, seasonEnd)
        }
    }
    
    func saveChanges() {
        Task {
            do {
                try await SchoolService.shared.updateSchool(
                    schoolId: schoolId,
                    name: name,
                    address: address
                )
                await MainActor.run {
                    successMessage = "School info updated!"
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func deletePhoto(_ photo: LocationPhoto) {
        locationPhotos.removeAll { $0.id == photo.id }

        Task {
            do {
                let photoDicts = locationPhotos.map { ["url": $0.url, "label": $0.label] }
                try await SchoolService.shared.updateLocationPhotos(schoolId: schoolId, photos: photoDicts)
                await MainActor.run {
                    successMessage = "Photo deleted."
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func uploadNewPhoto() {
        guard let newLabeledImage = newLabeledImage else { return }
        guard let imageData = newLabeledImage.image.downsampledJPEGData(maxDimension: 2048, quality: 0.8) else { return }

        Task {
            do {
                let supabase = SupabaseManager.shared.client

                // Use lowercase IDs per CLAUDE.md guidelines
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

                await MainActor.run {
                    let newPhoto = LocationPhoto(url: urlString, label: newLabeledImage.label)
                    self.locationPhotos.append(newPhoto)
                }

                // Update Supabase with new photos array
                let photoDicts = self.locationPhotos.map { ["url": $0.url, "label": $0.label] }
                try await SchoolService.shared.updateLocationPhotos(schoolId: self.schoolId, photos: photoDicts)

                await MainActor.run {
                    self.successMessage = "New photo uploaded."
                    self.newLabeledImage = nil
                }
                print("✅ Location photo saved to Supabase")

            } catch {
                print("❌ Location photo upload failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// Simple struct for map annotation
struct MapPin: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
}

struct DailyReportDetailView: View {
    let docID: String

    @State private var report: DailyJobReport?
    @State private var isLoading = true
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading Report...")
                    .padding()
            } else if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if let report = report {
                VStack(spacing: 20) {
                    headerSection(report: report)
                    detailsSection(report: report)
                    if let photoURLs = report.photo_urls, !photoURLs.isEmpty {
                        photosSection(photoURLs: photoURLs)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Report Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadReport()
        }
    }

    private func headerSection(report: DailyJobReport) -> some View {
        VStack(spacing: 8) {
            Text(report.date, style: .date)
                .font(.largeTitle)
                .bold()
            Text("Photographer: \(report.your_name)")
                .font(.headline)
            Text("School: \(report.school_or_destination ?? "Unknown")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func detailsSection(report: DailyJobReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mileage:")
                    .font(.headline)
                Spacer()
                Text("\(report.total_mileage, specifier: "%.1f") miles")
                    .font(.body)
            }
            if let jobNotes = report.job_description_text, !jobNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Job Notes:")
                        .font(.headline)
                    Text(jobNotes)
                        .font(.body)
                }
            }
            if let jobDescriptions = report.job_descriptions, !jobDescriptions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Job Descriptions:")
                        .font(.headline)
                    Text(jobDescriptions.joined(separator: ", "))
                        .font(.body)
                }
            }
            if let extraItems = report.extra_items, !extraItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extra Items:")
                        .font(.headline)
                    Text(extraItems.joined(separator: ", "))
                        .font(.body)
                }
            }
            if let cardsScanned = report.cards_scanned_choice {
                HStack {
                    Text("Cards Scanned:")
                        .font(.headline)
                    Spacer()
                    Text(cardsScanned)
                        .font(.body)
                }
            }
            if let boxCards = report.job_box_and_camera_cards {
                HStack {
                    Text("Job Box/Camera Cards:")
                        .font(.headline)
                    Spacer()
                    Text(boxCards)
                        .font(.body)
                }
            }
            if let sportsShot = report.sports_background_shot {
                HStack {
                    Text("Sports Background Shot:")
                        .font(.headline)
                    Spacer()
                    Text(sportsShot)
                        .font(.body)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func photosSection(photoURLs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attached Photos:")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
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
                                        .cornerRadius(8)
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
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func loadReport() {
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
