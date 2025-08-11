import SwiftUI

struct CritiqueGridCard: View {
    let critique: Critique
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image with badges
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: critique.thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_):
                        Rectangle()
                            .foregroundColor(.gray.opacity(0.2))
                            .overlay(
                                VStack {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                    Text("Image unavailable")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            )
                    case .empty:
                        Rectangle()
                            .foregroundColor(.gray.opacity(0.2))
                            .overlay(ProgressView())
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 150)
                .clipped()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Example type badge
                    ExampleTypeBadge(type: critique.exampleType)
                        .scaleEffect(0.9)
                    
                    // Image count if multiple
                    if critique.imageCount > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.stack")
                            Text("\(critique.imageCount)")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                }
                .padding(8)
            }
            
            // Info section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(critique.submitterName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Text(critique.managerNotes)
                    .font(.system(size: 14))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                Text(critique.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

struct CritiqueGridCard_Previews: PreviewProvider {
    static var previews: some View {
        CritiqueGridCard(critique: Critique(
            organizationId: "test",
            submitterId: "1",
            submitterName: "John Manager",
            submitterEmail: "john@test.com",
            targetPhotographerId: "2",
            targetPhotographerName: "Jane Photographer",
            imageUrls: ["https://example.com/image.jpg"],
            thumbnailUrls: ["https://example.com/thumb.jpg"],
            imageUrl: "https://example.com/image.jpg",
            thumbnailUrl: "https://example.com/thumb.jpg",
            imageCount: 2,
            managerNotes: "Great composition and lighting in this shot. Notice how the subject is positioned using the rule of thirds.",
            exampleType: "example",
            status: "published"
        ))
        .frame(width: 200)
        .padding()
    }
}