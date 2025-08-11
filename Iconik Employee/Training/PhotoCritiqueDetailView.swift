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
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Image Gallery Section
                    imageGallerySection
                    
                    // Information Section
                    informationSection
                    
                    // Manager Notes Section
                    managerNotesSection
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Training Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: saveToPhotos) {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                        
                        Button(action: shareImage) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Save to Photos", isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveAlertMessage)
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = imageToShare {
                ShareSheet(activityItems: [image])
            }
        }
    }
    
    // MARK: - Image Gallery Section
    
    private var imageGallerySection: some View {
        VStack(spacing: 12) {
            // Main image viewer
            TabView(selection: $selectedImageIndex) {
                ForEach(Array(critique.imageUrls.enumerated()), id: \.offset) { index, imageUrl in
                    GeometryReader { geometry in
                        AsyncImage(url: URL(string: imageUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: geometry.size.width)
                                    .scaleEffect(zoomScale)
                                    .gesture(
                                        MagnificationGesture()
                                            .onChanged { value in
                                                zoomScale = value
                                            }
                                            .onEnded { _ in
                                                withAnimation(.spring()) {
                                                    zoomScale = max(1.0, min(zoomScale, 3.0))
                                                }
                                            }
                                    )
                                    .onTapGesture(count: 2) {
                                        withAnimation {
                                            zoomScale = zoomScale == 1.0 ? 2.0 : 1.0
                                        }
                                    }
                            case .failure(_):
                                VStack {
                                    Image(systemName: "photo")
                                        .font(.system(size: 50))
                                        .foregroundColor(.gray)
                                    Text("Image unavailable")
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemGray6))
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color(.systemGray6))
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            .frame(height: UIScreen.main.bounds.height * 0.5)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Image counter and type badge
            HStack {
                if critique.imageCount > 1 {
                    Text("\(selectedImageIndex + 1) of \(critique.imageCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                }
                
                Spacer()
                
                ExampleTypeBadge(type: critique.exampleType)
            }
            .padding(.horizontal)
            
            // Thumbnail strip for multiple images
            if critique.imageCount > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(critique.thumbnailUrls.enumerated()), id: \.offset) { index, thumbnailUrl in
                            AsyncImage(url: URL(string: thumbnailUrl)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .foregroundColor(.gray.opacity(0.2))
                                    .overlay(ProgressView())
                            }
                            .frame(width: 60, height: 60)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedImageIndex == index ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                withAnimation {
                                    selectedImageIndex = index
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    // MARK: - Information Section
    
    private var informationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Submitted by", systemImage: "person.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(critique.submitterName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            HStack {
                Label("Date", systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(critique.formattedDate)
                    .font(.subheadline)
            }
            
            HStack {
                Label("For", systemImage: "camera.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(critique.targetPhotographerName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Manager Notes Section
    
    private var managerNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(.orange)
                Text("Training Notes")
                    .font(.headline)
                Spacer()
            }
            
            Text(critique.managerNotes)
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Actions
    
    private func saveToPhotos() {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                let imageUrl = critique.imageUrls[selectedImageIndex]
                
                URLSession.shared.dataTask(with: URL(string: imageUrl)!) { data, _, error in
                    if let data = data, let image = UIImage(data: data) {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        DispatchQueue.main.async {
                            saveAlertMessage = "Image saved to Photos"
                            showSaveAlert = true
                        }
                    } else {
                        DispatchQueue.main.async {
                            saveAlertMessage = "Failed to save image"
                            showSaveAlert = true
                        }
                    }
                }.resume()
            } else {
                DispatchQueue.main.async {
                    saveAlertMessage = "Please allow access to Photos in Settings"
                    showSaveAlert = true
                }
            }
        }
    }
    
    private func shareImage() {
        let imageUrl = critique.imageUrls[selectedImageIndex]
        
        URLSession.shared.dataTask(with: URL(string: imageUrl)!) { data, _, error in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    imageToShare = image
                    showShareSheet = true
                }
            }
        }.resume()
    }
}

struct PhotoCritiqueDetailView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoCritiqueDetailView(critique: Critique(
            organizationId: "test",
            submitterId: "1",
            submitterName: "John Manager",
            submitterEmail: "john@test.com",
            targetPhotographerId: "2",
            targetPhotographerName: "Jane Photographer",
            imageUrls: ["https://example.com/image1.jpg", "https://example.com/image2.jpg"],
            thumbnailUrls: ["https://example.com/thumb1.jpg", "https://example.com/thumb2.jpg"],
            imageUrl: "https://example.com/image1.jpg",
            thumbnailUrl: "https://example.com/thumb1.jpg",
            imageCount: 2,
            managerNotes: "This is an excellent example of proper composition. Notice how the subject is positioned using the rule of thirds, and the background is properly blurred to create depth. The lighting is soft and flattering, avoiding harsh shadows.",
            exampleType: "example",
            status: "published"
        ))
    }
}