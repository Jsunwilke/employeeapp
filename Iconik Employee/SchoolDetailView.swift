import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import Firebase

struct SchoolDetailView: View {
    let schoolId: String
    
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var locationPhotos: [LocationPhoto] = []
    
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
            }
            
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
                
                // New photo entry UI.
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
    
    func loadSchoolInfo() {
        let db = Firestore.firestore()
        db.collection("dropdownData").document(schoolId).getDocument { snapshot, error in
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            guard let data = snapshot?.data() else { return }
            name = data["value"] as? String ?? ""
            address = data["schoolAddress"] as? String ?? ""
            if let photoDicts = data["locationPhotos"] as? [[String: String]] {
                let photos = photoDicts.compactMap { dict -> LocationPhoto? in
                    if let url = dict["url"], let label = dict["label"] {
                        return LocationPhoto(url: url, label: label)
                    }
                    return nil
                }
                locationPhotos = photos
            }
        }
    }
    
    func saveChanges() {
        let db = Firestore.firestore()
        db.collection("dropdownData").document(schoolId).updateData([
            "value": name,
            "schoolAddress": address
        ]) { error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                successMessage = "School info updated!"
            }
        }
    }
    
    func deletePhoto(_ photo: LocationPhoto) {
        // Remove the photo locally and update Firestore.
        locationPhotos.removeAll { $0.id == photo.id }
        let db = Firestore.firestore()
        db.collection("dropdownData").document(schoolId).updateData([
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
        let fileName = "locationPhotos/\(schoolId)/\(Date().timeIntervalSince1970)_\(UUID().uuidString).jpg"
        let photoRef = storageRef.child(fileName)
        photoRef.putData(imageData, metadata: nil) { metadata, error in
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
                    db.collection("dropdownData").document(schoolId).updateData([
                        "locationPhotos": FieldValue.arrayUnion([[ "url": newPhoto.url, "label": newPhoto.label ]])
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

// Helper struct for location photos (used in ShiftDetailView as well).
struct LocationPhoto: Identifiable, Hashable {
    var id: String { url }
    let url: String
    let label: String
}

// Helper struct for new photo entry.
struct LabeledImage: Identifiable, Hashable {
    let id = UUID()
    var image: UIImage
    var label: String
}
