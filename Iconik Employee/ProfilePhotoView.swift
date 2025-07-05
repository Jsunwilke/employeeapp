import SwiftUI
import Firebase
import FirebaseStorage
import FirebaseFirestore

struct ProfilePhotoView: View {
    // Where we store the downloaded photo URL locally so we can display it.
    @AppStorage("userPhotoURL") var storedUserPhotoURL: String = ""
    
    // Temporary for newly selected image
    @State private var tempImage: UIImage? = nil
    @State private var showingImagePicker = false
    
    // For user feedback
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Profile Photo")
                .font(.headline)
            
            // Display current photo if we have a URL
            if let url = URL(string: storedUserPhotoURL), !storedUserPhotoURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    case .failure(_):
                        Image(systemName: "person.crop.circle.badge.exclam")
                            .resizable()
                            .frame(width: 120, height: 120)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                // Fallback if no photo set
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.gray)
            }
            
            // Button to pick a new photo
            Button("Select New Photo") {
                showingImagePicker = true
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $tempImage)
            }
            
            // If the user has chosen an image, show an "upload" button
            if let chosenImage = tempImage {
                Text("Ready to upload new image.")
                Button("Upload Profile Photo") {
                    uploadProfilePhoto(image: chosenImage)
                }
            }
            
            // Show errors/success
            if !errorMessage.isEmpty {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
            }
            if !successMessage.isEmpty {
                Text(successMessage)
                    .foregroundColor(.green)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func uploadProfilePhoto(image: UIImage) {
        // Must be signed in or we can't upload
        guard let user = Auth.auth().currentUser else {
            errorMessage = "No authenticated user. Please sign in."
            return
        }
        
        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Could not compress image."
            return
        }
        
        // Use a fixed path so that the new image overwrites the old one.
        let storageRef = Storage.storage().reference()
        let filePath = "profilePhotos/\(user.uid)/profile.jpg"
        let photoRef = storageRef.child(filePath)
        
        // Upload the image (this will overwrite any existing file at that path)
        photoRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            // Once uploaded, get the download URL
            photoRef.downloadURL { url, error in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let downloadURL = url else {
                    self.errorMessage = "No download URL returned."
                    return
                }
                // Save the URL in Firestore, and also in local AppStorage
                savePhotoURLToFirestore(downloadURL.absoluteString, userId: user.uid)
            }
        }
    }
    
    private func savePhotoURLToFirestore(_ urlString: String, userId: String) {
        let db = Firestore.firestore()
        db.collection("users").document(userId).updateData([
            "photoURL": urlString
        ]) { error in
            if let error = error {
                self.errorMessage = error.localizedDescription
            } else {
                // Store locally for immediate display
                self.storedUserPhotoURL = urlString
                // Reset
                self.tempImage = nil
                self.successMessage = "Profile photo updated!"
            }
        }
    }
}
