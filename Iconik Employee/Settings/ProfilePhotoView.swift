import SwiftUI
import Supabase

struct ProfilePhotoView: View {
    // Where we store the downloaded photo URL locally so we can display it.
    @AppStorage("userPhotoURL") var storedUserPhotoURL: String = ""

    // Temporary for newly selected image
    @State private var tempImage: UIImage? = nil
    @State private var showingImagePicker = false
    @State private var isUploading = false

    // For user feedback
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""

    private let supabase = SupabaseManager.shared.client

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
            .disabled(isUploading)
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $tempImage)
            }

            // If the user has chosen an image, show an "upload" button
            if let chosenImage = tempImage {
                Text("Ready to upload new image.")
                Button("Upload Profile Photo") {
                    Task {
                        await uploadProfilePhoto(image: chosenImage)
                    }
                }
                .disabled(isUploading)
            }

            if isUploading {
                ProgressView("Uploading...")
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

    private func uploadProfilePhoto(image: UIImage) async {
        // Must be signed in or we can't upload
        guard let userId = UserManager.shared.getCurrentUserIDUnified() else {
            errorMessage = "No authenticated user. Please sign in."
            return
        }

        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Could not compress image."
            return
        }

        isUploading = true
        errorMessage = ""
        successMessage = ""

        do {
            // Upload to Supabase Storage - user-photos bucket
            // Use lowercase userId per CLAUDE.md guidelines
            let path = "\(userId.lowercased())/profile.jpg"

            print("📸 Uploading profile photo to Supabase Storage: \(path)")

            // Upload with upsert to overwrite existing photo
            _ = try await supabase.storage
                .from("user-photos")
                .upload(
                    path: path,
                    file: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )

            // Get public URL for the uploaded image
            let publicUrl = try supabase.storage
                .from("user-photos")
                .getPublicURL(path: path)

            let urlString = publicUrl.absoluteString
            print("📸 Profile photo uploaded. URL: \(urlString)")

            // Save URL to Supabase users table via UserProfileService
            try await UserProfileService.shared.updateUserFields([
                "photo_url": AnyJSON.string(urlString)
            ])

            // Update local AppStorage for immediate display
            storedUserPhotoURL = urlString
            tempImage = nil
            successMessage = "Profile photo updated!"
            print("✅ Profile photo saved to Supabase")

        } catch {
            print("❌ Profile photo upload failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isUploading = false
    }
}
