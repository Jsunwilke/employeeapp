import SwiftUI

struct PhotoDetailView: View {
    let imageURL: String
    let label: String
    
    @Environment(\.presentationMode) var presentationMode
    @State private var position = CGSize.zero
    @State private var scale: CGFloat = 1.0
    @State private var imageLoaded = false
    @GestureState private var zoom: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                // Close button
                HStack {
                    Spacer()
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                
                Spacer()
                
                // Photo with zoom and drag capabilities
                GeometryReader { geometry in
                    AsyncImage(url: URL(string: imageURL)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .offset(position)
                                .scaleEffect(scale * zoom)
                                .onAppear {
                                    imageLoaded = true
                                }
                                .gesture(
                                    MagnificationGesture()
                                        .updating($zoom) { value, gestureState, _ in
                                            gestureState = value
                                        }
                                        .onEnded { value in
                                            scale *= value
                                            // Don't let it get too small
                                            scale = max(1, scale)
                                            // Or too large
                                            scale = min(4, scale)
                                        }
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { gesture in
                                            if imageLoaded {
                                                position = CGSize(
                                                    width: position.width + gesture.translation.width,
                                                    height: position.height + gesture.translation.height
                                                )
                                            }
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation {
                                        // Double tap to reset zoom and position
                                        position = .zero
                                        scale = 1.0
                                    }
                                }
                                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        case .failure(_):
                            VStack {
                                Image(systemName: "photo.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                Text("Failed to load image")
                                    .foregroundColor(.gray)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Spacer()
                
                // Photo label
                if !label.isEmpty {
                    Text(label)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.bottom)
                }
            }
        }
        .statusBar(hidden: true)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // Reset state when view appears
            position = .zero
            scale = 1.0
            imageLoaded = false
        }
    }
}
