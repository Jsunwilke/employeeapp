//  ProfilePhotoView.swift
//  Iconik Employee — the profile photo, converted to Ambient in AMB.12
//
//  TWO FIXES THE CONVERSION MADE UNAVOIDABLE:
//
//    · THE SCREEN GETS A NAV TITLE. It set none, so it inherited a blank bar and
//      printed "Profile Photo" into its own content instead — a heading drawn twice
//      in two different places, one of them empty.
//
//    · A PHOTO-LIBRARY PERMISSION CHECK (G35). There was none, and `ImagePicker`
//      wraps `UIImagePickerController`, which runs in process and DOES need
//      authorisation — so a user who had refused it got an empty picker and no
//      explanation. The gate lives in `SettingsKit.SettingsPhotoAccess` because the
//      school screen picks photos too.
//
//  NOT PROMISED AND NOT BUILT: cropping, removing the photo, or a cancel once an
//  image is chosen. None of the three exists today and each is a feature.
//
//  NAMED, NOT FIXED (G34): the upload writes to a FIXED path with `upsert: true` and
//  stores a PUBLIC url, so the URL never changes and a replaced photo can serve from
//  cache indefinitely. That is a storage decision, not a layout one.
//
//  EVERY MESSAGE IS THE SHIPPED MESSAGE, verbatim.

import SwiftUI
import Supabase

struct ProfilePhotoView: View {
    // Where we store the downloaded photo URL locally so we can display it.
    @AppStorage("userPhotoURL") var storedUserPhotoURL: String = ""
    @AppStorage("userDisplayName") private var storedUserDisplayName: String = ""

    // Temporary for newly selected image
    @State private var tempImage: UIImage? = nil
    @State private var showingImagePicker = false
    @State private var isUploading = false

    // For user feedback
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""

    private let supabase = SupabaseManager.shared.client

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    photoCard

                    if let chosenImage = tempImage {
                        pendingUpload(chosenImage)
                    }

                    if !errorMessage.isEmpty {
                        AmbientFailureCard(message: errorMessage, tint: .red, action: nil)
                    }

                    if !successMessage.isEmpty {
                        AmbientNoteCard(title: "Done",
                                        text: successMessage,
                                        accent: .green,
                                        density: .compact)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .tabBarClearance()
        .navigationTitle("Profile Photo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $tempImage)
        }
    }

    // MARK: - Content

    private var photoCard: some View {
        VStack(spacing: 14) {
            // `SupabaseAvatarView` is what actually resolves the stored URL out of
            // the `user-photos` bucket, so it stays; `AmbientAvatar` draws the
            // initials fallback the grey `person.crop.circle` used to.
            if !storedUserPhotoURL.isEmpty {
                SupabaseAvatarView(storageURL: storedUserPhotoURL, size: 120)
            } else {
                AmbientAvatar(name: storedUserDisplayName, size: 120)
            }

            AmbientActionButton(title: "Select New Photo",
                                systemImage: "photo.on.rectangle",
                                role: .primary,
                                tint: SettingsStyle.tint,
                                fillWidth: false,
                                isEnabled: !isUploading,
                                action: selectPhoto)

            if isUploading {
                ProgressView("Uploading...")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .ambientCard(density: .roomy, fillWidth: true, contentAlignment: .center)
    }

    private func pendingUpload(_ image: UIImage) -> some View {
        AmbientFormSection(title: "New photo", status: "ready", statusTint: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                    Text("Ready to upload new image.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                AmbientActionButton(title: "Upload Profile Photo",
                                    systemImage: "arrow.up.circle.fill",
                                    role: .primary,
                                    tint: SettingsStyle.tint,
                                    isLoading: isUploading) {
                    Task { await uploadProfilePhoto(image: image) }
                }
            }
        }
    }

    // MARK: - Actions

    /// Ask BEFORE presenting the picker. Presenting first is what produced the empty
    /// picker with no explanation.
    private func selectPhoto() {
        SettingsPhotoAccess.request { granted in
            if granted {
                errorMessage = ""
                showingImagePicker = true
            } else {
                errorMessage = SettingsPhotoAccess.deniedMessage
            }
        }
    }

    private func uploadProfilePhoto(image: UIImage) async {
        // Must be signed in or we can't upload
        guard let userId = UserManager.shared.getCurrentUserIDUnified() else {
            errorMessage = "No authenticated user. Please sign in."
            return
        }

        // Convert image to data
        guard let imageData = image.downsampledJPEGData(maxDimension: 512, quality: 0.8) else {
            errorMessage = "Could not compress image."
            return
        }

        isUploading = true
        errorMessage = ""
        successMessage = ""

        do {
            // Upload to Supabase Storage - user-photos bucket.
            // The bucket path is not a database filter, so folding the case here is
            // about a stable object key rather than about matching a stored column.
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
            // A failure must not leave the previous success on screen beside it
            // (G49) — the two used to be able to show at once.
            successMessage = ""
        }

        isUploading = false
    }
}
