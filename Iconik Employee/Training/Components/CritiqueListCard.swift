import SwiftUI

struct CritiqueListCard: View {
    let critique: Critique
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
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
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            )
                    case .empty:
                        Rectangle()
                            .foregroundColor(.gray.opacity(0.2))
                            .overlay(ProgressView())
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 100, height: 100)
                .clipped()
                .cornerRadius(8)
                
                // Image count badge if multiple
                if critique.imageCount > 1 {
                    HStack(spacing: 2) {
                        Image(systemName: "photo.stack")
                            .font(.caption2)
                        Text("\(critique.imageCount)")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                    .padding(4)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Type badge and date
                HStack {
                    ExampleTypeBadge(type: critique.exampleType)
                        .scaleEffect(0.85)
                    Spacer()
                    Text(critique.formattedDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Manager info
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(critique.submitterName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Notes preview
                Text(critique.managerNotes)
                    .font(.system(size: 14))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct CritiqueListCard_Previews: PreviewProvider {
    static var previews: some View {
        CritiqueListCard(critique: Critique(
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
            imageCount: 3,
            managerNotes: "Pay attention to the exposure settings here. The highlights are blown out which loses detail in the important areas.",
            exampleType: "improvement",
            status: "published"
        ))
        .padding()
    }
}