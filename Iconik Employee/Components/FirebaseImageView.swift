//
//  FirebaseImageView.swift
//  Iconik Employee
//
//  A reusable component for displaying images from Firebase Storage URLs
//  with proper error handling and loading states
//

import SwiftUI

struct FirebaseImageView: View {
    let imageURL: String
    let width: CGFloat?
    let height: CGFloat?
    let contentMode: ContentMode
    
    @State private var hasError = false
    @State private var errorMessage = ""
    
    init(imageURL: String, 
         width: CGFloat? = nil, 
         height: CGFloat? = nil, 
         contentMode: ContentMode = .fit) {
        self.imageURL = imageURL
        self.width = width
        self.height = height
        self.contentMode = contentMode
    }
    
    var body: some View {
        Group {
            if hasError {
                VStack(spacing: 4) {
                    Image(systemName: "photo.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 30))
                    Text("Unable to load image")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(width: width, height: height)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            } else {
                AsyncImage(url: URL(string: imageURL)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: width, height: height)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                            .frame(width: width, height: height)
                            .clipped()
                            .cornerRadius(8)
                    case .failure(let error):
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 30))
                            Text("Error loading image")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(width: width, height: height)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .onAppear {
                            print("FirebaseImageView error: \(error.localizedDescription)")
                            hasError = true
                            errorMessage = error.localizedDescription
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }
}

// Thumbnail version for lists
struct FirebaseImageThumbnail: View {
    let imageURL: String
    let size: CGFloat
    
    init(imageURL: String, size: CGFloat = 50) {
        self.imageURL = imageURL
        self.size = size
    }
    
    var body: some View {
        FirebaseImageView(
            imageURL: imageURL,
            width: size,
            height: size,
            contentMode: .fill
        )
    }
}

// Photo gallery grid for multiple images
struct FirebasePhotoGallery: View {
    let photoURLs: [String]
    let columns: Int
    @State private var selectedPhotoURL: String? = nil
    
    init(photoURLs: [String], columns: Int = 3) {
        self.photoURLs = photoURLs
        self.columns = columns
    }
    
    var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !photoURLs.isEmpty {
                Text("Photos (\(photoURLs.count))")
                    .font(.headline)
                    .padding(.horizontal)
                
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(photoURLs, id: \.self) { photoURL in
                        FirebaseImageView(
                            imageURL: photoURL,
                            width: nil,
                            height: 100,
                            contentMode: .fill
                        )
                        .onTapGesture {
                            selectedPhotoURL = photoURL
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .sheet(item: $selectedPhotoURL) { url in
            PhotoDetailView(imageURL: url, label: "Photo")
        }
    }
}

// Make String Identifiable for sheet presentation
extension String: Identifiable {
    public var id: String { self }
}

#if DEBUG
struct FirebaseImageView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            FirebaseImageView(
                imageURL: "https://example.com/test.jpg",
                width: 200,
                height: 200
            )
            
            FirebaseImageThumbnail(
                imageURL: "https://example.com/test.jpg"
            )
            
            FirebasePhotoGallery(
                photoURLs: [
                    "https://example.com/test1.jpg",
                    "https://example.com/test2.jpg",
                    "https://example.com/test3.jpg"
                ]
            )
        }
        .padding()
    }
}
#endif