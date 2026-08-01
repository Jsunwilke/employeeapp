//  PhotoCritiqueDetailView.swift
//  Iconik Employee — one training photo, converted to Ambient in AMB.12
//
//  Still a SHEET with its own `NavigationView` and its own "Close" — that is what
//  the design approved, and the list presents it with `.sheet(item:)`.
//
//  WHAT THIS SCREEN GAINED:
//    · IT NO LONGER CRASHES ON A LEGACY ROW. `imageUrls` was indexed unguarded and
//      the URL force-unwrapped, so Save and Share CRASHED on critiques written
//      before the app stored a list of images (`Models.swift:880` defaults that
//      list to `[]`). The state is drawn, both actions are disabled with it, and
//      every force-unwrap on this screen is gone.
//    · THE PAGER COUNTS THE IMAGES IT HAS. The counter and the whole thumbnail
//      strip were gated on `image_count`, which decodes to 0 when NULL — so a
//      genuinely multi-image critique drew as a single photo with no strip and no
//      counter. Everything counts `Critique.resolvedImageUrls` now (TrainingKit).
//    · THE CONFIRMATION DESCRIBES THE SAVE. `UIImageWriteToSavedPhotosAlbum` was
//      passed no completion target, so "Image saved to Photos" was reporting that
//      the DOWNLOAD had finished and a failed WRITE was silent. It has a target
//      now, the button shows the write in progress, and LIMITED photo access is
//      treated as granted — an add-only write is permitted under it.
//    · A PHOTO WELL SIZED BY ITS LAYOUT. The pager was `UIScreen.main.bounds.height
//      * 0.5` — half the SCREEN, not half the sheet, which overflows on iPad.
//    · A THUMBNAIL THAT CAN FAIL. The strip's two-closure `AsyncImage` had no
//      failure branch, so a broken thumbnail spun forever.
//
//  WHAT IS DELIBERATELY NOT ADDED: any way to reply to a critique or mark it read.
//  Neither exists in the service and both would be features (D12).
//
//  SHARING: this used to call `ShareSheet`, a wrapper declared in the YEARBOOK
//  module — a cross-feature dependency on a type Training does not own, which a
//  rename or a `private` over there would have broken at compile time. The same
//  twelve lines also existed in Chat and in Settings' metrics dashboard under two
//  other names. All three are now `Components/ActivityShareSheet.swift`, owned by
//  no feature.

import SwiftUI
import Photos

struct PhotoCritiqueDetailView: View {
    let critique: Critique
    @Environment(\.dismiss) var dismiss

    @State private var selectedImageIndex = 0
    @State private var zoomScale: CGFloat = 1.0
    @State private var showShareSheet = false
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var imageToShare: UIImage?
    @State private var isSaving = false
    @State private var isPreparingShare = false

    private var tint: Color { TrainingStyle.tint }

    /// The images this row REALLY has — the plural list, or the legacy singular
    /// field, or nothing at all. Everything on this screen is counted off it.
    private var imageUrls: [String] { critique.resolvedImageUrls }

    var body: some View {
        NavigationView {
            ZStack {
                // D14: ONE wash for the whole app. Training's colour is an accent
                // and reaches the badge, the buttons and the selected ring only.
                AmbientBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if imageUrls.isEmpty { noImagesState } else { gallery }
                        meta
                        if let notes = critique.trimmedNotes {
                            AmbientNoteCard(title: "Training Notes",
                                            text: notes,
                                            accent: .orange,
                                            density: .roomy)
                        }
                        actions
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle("Training Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        // The sheet's own container, for the same reason the list's has one: an
        // unstyled `NavigationView` splits at regular width, which on iPad drew this
        // sheet as an empty pane.
        .navigationViewStyle(StackNavigationViewStyle())
        .alert("Save to Photos", isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveAlertMessage)
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = imageToShare {
                ActivityShareSheet(items: [image])
            }
        }
    }

    // MARK: - The row with no images

    /// A REAL ROW, not a crash and not an empty pager at half the screen's height.
    private var noImagesState: some View {
        AmbientEmptyState(
            title: "This photo is no longer attached",
            message: "The critique's note is below. The image was stored before the app kept a list of them and cannot be shown.",
            systemImage: "exclamationmark.triangle")
    }

    // MARK: - Gallery

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 8) {
            pager
            if imageUrls.count > 1 {
                thumbnailStrip
            }
        }
    }

    /// A FIXED well inside the layout. The old `UIScreen.main.bounds.height * 0.5`
    /// is half the DEVICE, which on an iPad is taller than the sheet it is in.
    private var pager: some View {
        TabView(selection: $selectedImageIndex) {
            ForEach(Array(imageUrls.enumerated()), id: \.offset) { index, imageUrl in
                pageContent(for: imageUrl)
                    .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: imageUrls.count > 1 ? .automatic : .never))
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func pageContent(for imageUrl: String) -> some View {
        // ambient-allow: the photo well — the subject of the screen, not a card.
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemFill))

            if let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(zoomScale)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        zoomScale = value
                                    }
                                    .onEnded { _ in
                                        withAnimation(AmbientMotion.snappy) {
                                            zoomScale = max(1.0, min(zoomScale, 3.0))
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(AmbientMotion.snappy) {
                                    zoomScale = zoomScale == 1.0 ? 2.0 : 1.0
                                }
                            }
                    case .failure:
                        unavailable
                    case .empty:
                        ProgressView()
                    @unknown default:
                        unavailable
                    }
                }
            } else {
                // A URL the row stores but that cannot be parsed. Said, not spun.
                unavailable
            }
        }
        .clipped()
    }

    private var unavailable: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Image unavailable")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    /// The strip and the counter, both counting the REAL images. The strip scrolls
    /// so a row with a dozen images does not squeeze the counter off the line.
    private var thumbnailStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(imageUrls.indices, id: \.self) { index in
                        thumbnail(at: index)
                    }
                }
                .padding(.vertical, 1)
            }

            Text("\(selectedImageIndex + 1) of \(imageUrls.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private func thumbnail(at index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let url = critique.resolvedThumbnailUrl(at: index).flatMap { URL(string: $0) }

        return ZStack {
            // ambient-allow: a thumbnail strip cell, not a container.
            shape.fill(Color(.tertiarySystemFill))

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    // THE BRANCH THAT DID NOT EXIST: the old two-closure form had a
                    // placeholder and no failure case, so a broken thumbnail spun
                    // forever.
                    Image(systemName: "photo").font(.caption).foregroundStyle(.tertiary)
                case .empty:
                    ProgressView()
                @unknown default:
                    Image(systemName: "photo").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(index == selectedImageIndex ? tint : .clear, lineWidth: 2)
        }
        .onTapGesture {
            withAnimation(AmbientMotion.snappy) { selectedImageIndex = index }
        }
        .accessibilityLabel("Image \(index + 1) of \(imageUrls.count)")
    }

    // MARK: - Meta

    private var meta: some View {
        VStack(alignment: .leading, spacing: 6) {
            CritiqueTypeBadge(isGood: critique.isGoodExample)
            AmbientStatLine(label: "Submitted by", value: critique.submitterName)
            // ADDED: already decoded on the model and displayed nowhere, and "who do
            // I ask about this" is the obvious next question after reading a
            // critique. No new query.
            AmbientStatLine(label: "Email", value: critique.submitterEmail)
            AmbientStatLine(label: "Date", value: dateText)
            AmbientStatLine(label: "For", value: critique.targetPhotographerName)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private var dateText: String {
        guard let created = critique.createdAt else { return "—" }
        return Formatters.mediumDate.string(from: created)
    }

    // MARK: - Actions

    /// BOTH ACTIONS ARE VISIBLE. They are the only two things this screen does, and
    /// a `Menu` hiding two items is a tap spent on discovery.
    private var actions: some View {
        HStack(spacing: 8) {
            AmbientActionButton(title: isSaving ? "Saving…" : "Save to Photos",
                                systemImage: "square.and.arrow.down",
                                role: .primary,
                                size: .small,
                                tint: tint,
                                isLoading: isSaving,
                                isEnabled: !imageUrls.isEmpty,
                                action: saveToPhotos)

            AmbientActionButton(title: "Share",
                                systemImage: "square.and.arrow.up",
                                role: .secondary,
                                size: .small,
                                isLoading: isPreparingShare,
                                isEnabled: !imageUrls.isEmpty,
                                action: shareImage)
        }
    }

    /// The image the pager is on, or nil — the guard the old `imageUrls[index]` and
    /// `URL(string:)!` did not have.
    private var currentImageURL: URL? {
        guard imageUrls.indices.contains(selectedImageIndex) else { return nil }
        return URL(string: imageUrls[selectedImageIndex])
    }

    private func saveToPhotos() {
        guard let url = currentImageURL else { return }
        isSaving = true

        // `.addOnly` rather than the deprecated whole-library request, and LIMITED
        // counts as granted: adding a photo IS permitted under limited access, so
        // telling that user to go to Settings was both wrong and a dead end.
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                finishSave(message: "Please allow access to Photos in Settings")
                return
            }

            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let image = UIImage(data: data) else {
                    finishSave(message: "Failed to save image")
                    return
                }
                // The confirmation now waits for the WRITE, not the download.
                CritiqueImageSaver.save(image) { error in
                    finishSave(message: error == nil ? "Image saved to Photos"
                                                     : "Failed to save image")
                }
            }.resume()
        }
    }

    private func finishSave(message: String) {
        DispatchQueue.main.async {
            isSaving = false
            saveAlertMessage = message
            showSaveAlert = true
        }
    }

    private func shareImage() {
        guard let url = currentImageURL else { return }
        isPreparingShare = true

        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                isPreparingShare = false
                guard let data, let image = UIImage(data: data) else { return }
                imageToShare = image
                showShareSheet = true
            }
        }.resume()
    }
}

// MARK: - Save completion

/// The completion target `UIImageWriteToSavedPhotosAlbum` needs.
///
/// A SwiftUI `View` is a struct and cannot be an Objective-C selector target, which
/// is how that call came to be passed `nil` for all three of its completion
/// arguments — so the alert reported the DOWNLOAD finishing and a photo library
/// that refused the write said nothing at all.
///
/// It keeps itself alive until the callback fires, because nothing else holds it
/// for the duration of an asynchronous write.
private final class CritiqueImageSaver: NSObject {
    private var completion: ((Error?) -> Void)?
    private var retained: CritiqueImageSaver?

    static func save(_ image: UIImage, completion: @escaping (Error?) -> Void) {
        let saver = CritiqueImageSaver()
        saver.completion = completion
        saver.retained = saver
        UIImageWriteToSavedPhotosAlbum(
            image, saver,
            #selector(CritiqueImageSaver.didFinishSaving(_:error:contextInfo:)), nil)
    }

    @objc private func didFinishSaving(_ image: UIImage,
                                       error: Error?,
                                       contextInfo: UnsafeRawPointer?) {
        let finish = completion
        completion = nil
        retained = nil
        DispatchQueue.main.async { finish?(error) }
    }
}

struct PhotoCritiqueDetailView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoCritiqueDetailView(critique: Critique(
            id: "preview-1",
            organization_id: "test",
            submitter_id: "1",
            submitter_name: "John Manager",
            submitter_email: "john@test.com",
            target_photographer_id: "2",
            target_photographer_name: "Jane Photographer",
            image_urls: ["https://example.com/image1.jpg", "https://example.com/image2.jpg"],
            thumbnail_urls: ["https://example.com/thumb1.jpg", "https://example.com/thumb2.jpg"],
            image_url: "https://example.com/image1.jpg",
            thumbnail_url: "https://example.com/thumb1.jpg",
            image_count: 2,
            manager_notes: "This is an excellent example of proper composition. Notice how the subject is positioned using the rule of thirds, and the background is properly blurred to create depth. The lighting is soft and flattering, avoiding harsh shadows.",
            example_type: "example",
            status: "published",
            created_at: Date(),
            updated_at: Date()
        ))
    }
}
