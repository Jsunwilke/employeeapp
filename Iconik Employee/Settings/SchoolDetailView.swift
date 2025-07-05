import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import Firebase
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
        let db = Firestore.firestore()
        db.collection("schools").document(schoolId).getDocument { snapshot, error in
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            guard let data = snapshot?.data() else { return }
            name = data["value"] as? String ?? ""
            address = data["schoolAddress"] as? String ?? ""
            coordinates = data["coordinates"] as? String ?? ""
            
            // Parse coordinates if available
            if !coordinates.isEmpty {
                let parts = coordinates.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                    let location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    pinLocation = location
                    region = MKCoordinateRegion(
                        center: location,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                }
            }
            
            if let photoDicts = data["locationPhotos"] as? [[String: String]] {
                let photos = photoDicts.compactMap { dict -> LocationPhoto? in
                    if let url = dict["url"], let label = dict["label"] {
                        return LocationPhoto(url: url, label: label)
                    }
                    return nil
                }
                locationPhotos = photos
            }
            loadMileageForSchool()
            loadDailyReportsForSchool()
        }
    }
    
    // Load total mileage for the school in the current season.
    func loadMileageForSchool() {
        guard let seasonDates = currentSchoolSeasonDates() else { return }
        let seasonStart = seasonDates.start
        let seasonEnd = seasonDates.end
        let db = Firestore.firestore()
        
        db.collection("dailyJobReports")
            .whereField("schoolOrDestination", isEqualTo: name)
            .whereField("organizationID", isEqualTo: storedUserOrganizationID) // Filter by organization ID
            .whereField("date", isGreaterThanOrEqualTo: seasonStart)
            .whereField("date", isLessThanOrEqualTo: seasonEnd)
            .getDocuments { snapshot, error in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else { return }
                var total: Double = 0.0
                for doc in docs {
                    let data = doc.data()
                    let mileage = data["totalMileage"] as? Double ?? 0.0
                    total += mileage
                }
                DispatchQueue.main.async {
                    self.seasonMileage = total
                }
            }
    }
    
    // Load daily job reports (with photographer name) for the current season.
    func loadDailyReportsForSchool() {
        guard let seasonDates = currentSchoolSeasonDates() else { return }
        let seasonStart = seasonDates.start
        let seasonEnd = seasonDates.end
        let db = Firestore.firestore()
        
        db.collection("dailyJobReports")
            .whereField("schoolOrDestination", isEqualTo: name)
            .whereField("organizationID", isEqualTo: storedUserOrganizationID) // Filter by organization ID
            .whereField("date", isGreaterThanOrEqualTo: seasonStart)
            .whereField("date", isLessThanOrEqualTo: seasonEnd)
            .getDocuments { snapshot, error in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else { return }
                var reports: [Report] = []
                for doc in docs {
                    let data = doc.data()
                    if let timestamp = data["date"] as? Timestamp {
                        let date = timestamp.dateValue()
                        let mileage = data["totalMileage"] as? Double ?? 0.0
                        let photographerName = data["yourName"] as? String ?? "Unknown"
                        let newReport = Report(id: doc.documentID, date: date, totalMileage: mileage, photographerName: photographerName)
                        reports.append(newReport)
                    }
                }
                DispatchQueue.main.async {
                    self.dailyReports = reports
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
        let db = Firestore.firestore()
        db.collection("schools").document(schoolId).updateData([
            "value": name,
            "schoolAddress": address,
            "organizationID": storedUserOrganizationID // Always ensure org ID is set
        ]) { error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                successMessage = "School info updated!"
            }
        }
    }
    
    func deletePhoto(_ photo: LocationPhoto) {
        locationPhotos.removeAll { $0.id == photo.id }
        let db = Firestore.firestore()
        db.collection("schools").document(schoolId).updateData([
            "locationPhotos": locationPhotos.map { ["url": $0.url, "label": $0.label] }
        ]) { error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                successMessage = "Photo deleted."
            }
        }
    }
    
    func uploadNewPhoto() {
        guard let newLabeledImage = newLabeledImage else { return }
        guard let imageData = newLabeledImage.image.jpegData(compressionQuality: 0.8) else { return }
        let storageRef = Storage.storage().reference()
        // Include organization ID in the storage path
        let fileName = "locationPhotos/\(storedUserOrganizationID)/\(schoolId)/\(Date().timeIntervalSince1970)_\(UUID().uuidString).jpg"
        let photoRef = storageRef.child(fileName)
        photoRef.putData(imageData, metadata: nil) { _, error in
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            photoRef.downloadURL { url, error in
                if let error = error {
                    errorMessage = error.localizedDescription
                } else if let downloadURL = url {
                    let newPhoto = LocationPhoto(url: downloadURL.absoluteString, label: newLabeledImage.label)
                    locationPhotos.append(newPhoto)
                    let db = Firestore.firestore()
                    db.collection("schools").document(schoolId).updateData([
                        "locationPhotos": FieldValue.arrayUnion([
                            ["url": newPhoto.url, "label": newPhoto.label]
                        ])
                    ]) { error in
                        if let error = error {
                            errorMessage = error.localizedDescription
                        } else {
                            successMessage = "New photo uploaded."
                            self.newLabeledImage = nil
                        }
                    }
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
    
    @State private var reportData: [String: Any] = [:]
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
            } else {
                VStack(spacing: 20) {
                    headerSection
                    detailsSection
                    if let photoURLs = reportData["photoURLs"] as? [String], !photoURLs.isEmpty {
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
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            if let timestamp = reportData["date"] as? Timestamp {
                let date = timestamp.dateValue()
                Text(date, style: .date)
                    .font(.largeTitle)
                    .bold()
            }
            Text("Photographer: \(reportData["yourName"] as? String ?? "Unknown")")
                .font(.headline)
            Text("School: \(reportData["schoolOrDestination"] as? String ?? "Unknown")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mileage:")
                    .font(.headline)
                Spacer()
                Text("\(reportData["totalMileage"] as? Double ?? 0, specifier: "%.1f") miles")
                    .font(.body)
            }
            if let jobNotes = reportData["jobDescriptionText"] as? String, !jobNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Job Notes:")
                        .font(.headline)
                    Text(jobNotes)
                        .font(.body)
                }
            }
            if let jobDescriptions = reportData["jobDescriptions"] as? [String], !jobDescriptions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Job Descriptions:")
                        .font(.headline)
                    Text(jobDescriptions.joined(separator: ", "))
                        .font(.body)
                }
            }
            if let extraItems = reportData["extraItems"] as? [String], !extraItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extra Items:")
                        .font(.headline)
                    Text(extraItems.joined(separator: ", "))
                        .font(.body)
                }
            }
            if let cardsScanned = reportData["cardsScannedChoice"] as? String {
                HStack {
                    Text("Cards Scanned:")
                        .font(.headline)
                    Spacer()
                    Text(cardsScanned)
                        .font(.body)
                }
            }
            if let boxCards = reportData["jobBoxAndCameraCards"] as? String {
                HStack {
                    Text("Job Box/Camera Cards:")
                        .font(.headline)
                    Spacer()
                    Text(boxCards)
                        .font(.body)
                }
            }
            if let sportsShot = reportData["sportsBackgroundShot"] as? String {
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
        let db = Firestore.firestore()
        db.collection("dailyJobReports").document(docID).getDocument { snapshot, error in
            if let error = error {
                self.errorMessage = "Error: \(error.localizedDescription)"
            } else if let data = snapshot?.data() {
                self.reportData = data
            } else {
                self.errorMessage = "No data found."
            }
            self.isLoading = false
        }
    }
}
