import SwiftUI
import Photos

struct FullScreenImageViewer: View {
    let imageURL: String
    @Binding var isPresented: Bool
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showShareSheet = false
    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = ""
    
    // For drag to dismiss
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .opacity(1.0 - min(abs(dragOffset.height) / 500.0, 0.5))
                .ignoresSafeArea()
            
            // Image viewer
            GeometryReader { geometry in
                AsyncImage(url: URL(string: imageURL)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onAppear { isLoading = true }
                        
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .scaleEffect(scale)
                            .offset(x: offset.width + dragOffset.width, 
                                   y: offset.height + dragOffset.height)
                            .gesture(
                                // Drag to dismiss when not zoomed
                                scale == 1.0 ? 
                                DragGesture()
                                    .onChanged { value in
                                        isDragging = true
                                        dragOffset = value.translation
                                    }
                                    .onEnded { value in
                                        if abs(value.translation.height) > 100 {
                                            withAnimation(.easeOut(duration: 0.3)) {
                                                isPresented = false
                                            }
                                        } else {
                                            withAnimation(.spring()) {
                                                dragOffset = .zero
                                            }
                                        }
                                        isDragging = false
                                    }
                                : nil
                            )
                            .gesture(
                                // Pan gesture when zoomed
                                scale > 1.0 ?
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                                : nil
                            )
                            .gesture(
                                // Pinch to zoom
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        scale *= delta
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                        withAnimation(.spring()) {
                                            scale = min(max(scale, 1), 4)
                                            if scale == 1.0 {
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                    }
                            )
                            .onTapGesture(count: 2) {
                                // Double tap to zoom
                                withAnimation(.spring()) {
                                    if scale > 1 {
                                        scale = 1
                                        offset = .zero
                                        lastOffset = .zero
                                    } else {
                                        scale = 2
                                    }
                                }
                            }
                            .onAppear {
                                isLoading = false
                                // Convert SwiftUI Image to UIImage for sharing
                                loadImageFromURL()
                            }
                        
                    case .failure(_):
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                            Text("Failed to load image")
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { isLoading = false }
                        
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            
            // Top toolbar
            VStack {
                HStack {
                    // Close button
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Share button
                    if loadedImage != nil {
                        Menu {
                            Button(action: saveToPhotos) {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                            }
                            
                            Button(action: { showShareSheet = true }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding()
                
                Spacer()
            }
        }
        .alert("Save Photo", isPresented: $showSaveAlert) {
            Button("OK") { }
        } message: {
            Text(saveAlertMessage)
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = loadedImage {
                ImageShareSheet(items: [image])
            }
        }
    }
    
    private func loadImageFromURL() {
        guard let url = URL(string: imageURL) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let uiImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.loadedImage = uiImage
                }
            }
        }.resume()
    }
    
    private func saveToPhotos() {
        guard let image = loadedImage else { return }
        
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                DispatchQueue.main.async {
                    saveAlertMessage = "Photo saved to your library"
                    showSaveAlert = true
                }
            } else {
                DispatchQueue.main.async {
                    saveAlertMessage = "Please grant photo library access in Settings"
                    showSaveAlert = true
                }
            }
        }
    }
}

// Share Sheet for sharing images
struct ImageShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}