# iOS Photo Critique Viewer - Implementation Manual

## Overview
Create a read-only view for photographers to see their training examples and feedback from managers. Photographers can view critiques assigned to them but cannot create new ones.

## Firebase Data Structure

### Collection: `photoCritiques`
```javascript
{
  id: string,
  organizationId: string,
  
  // Submission Info
  submitterId: string,        // Manager's auth UID
  submitterName: string,       // Manager's name
  submitterEmail: string,
  
  // Target Photographer
  targetPhotographerId: string,     // Photographer this is for
  targetPhotographerName: string,   // Photographer's name
  
  // Images (supports multiple)
  imageUrls: string[],         // Array of full-size image URLs
  thumbnailUrls: string[],     // Array of thumbnail URLs
  imageUrl: string,            // First image (backward compat)
  thumbnailUrl: string,        // First thumbnail (backward compat)
  imageCount: number,          // Number of images
  
  // Content
  managerNotes: string,        // Training feedback/notes
  exampleType: string,         // "example" or "improvement"
  status: string,              // "published"
  
  // Timestamps
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

## Views to Implement

### 1. Main List View
**Purpose**: Show all critiques for the logged-in photographer

**Firestore Query**:
```swift
db.collection("photoCritiques")
    .whereField("targetPhotographerId", isEqualTo: currentUser.uid)
    .whereField("organizationId", isEqualTo: currentUser.organizationId)
    .order(by: "createdAt", descending: true)
```

**Display Elements**:
- Grid or list layout (user preference toggle)
- Thumbnail image (first image if multiple)
- Badge: "Good Example" (green) or "Needs Improvement" (orange)
- Submitter name and date
- Preview of manager notes (truncated to 2 lines)
- Image count badge if multiple images (e.g., "3 photos")

### 2. Detail View Modal/Screen

**Header Section**:
- Title: "Training Photo for [Your Name]"
- Badge showing example type with icon
- Close button (X)

**Image Gallery**:
- Large image viewer with aspect ratio preserved
- If multiple images: 
  - Horizontal scrolling thumbnail strip below main image
  - Tap thumbnail to switch images
  - Current image indicator (e.g., "1 of 3")
- Pinch to zoom functionality
- Swipe left/right to navigate between images
- Double-tap to zoom

**Information Panel**:
- **Submitted by**: [Manager Name]
- **Date**: [Formatted date - "Jan 15, 2024, 3:30 PM"]
- **Training Notes**: 
  - Full manager notes in readable text
  - Scrollable if long
  - Clear typography with good line height

### 3. Statistics Header
Display three cards showing:
1. **Total Submissions**: All training examples
2. **Good Examples**: Count of "example" type
3. **Needs Improvement**: Count of "improvement" type

## UI Components & Styling

### Color Scheme
```swift
// Status Colors
let goodExampleColor = UIColor(hex: "#10b981")      // Green
let goodExampleBg = UIColor(hex: "#d1fae5")         // Light green background
let improvementColor = UIColor(hex: "#f59e0b")      // Orange  
let improvementBg = UIColor(hex: "#fed7aa")         // Light orange background

// General Colors
let primaryBlue = UIColor(hex: "#3b82f6")
let borderColor = UIColor(hex: "#e5e7eb")
let textPrimary = UIColor(hex: "#111827")
let textSecondary = UIColor(hex: "#6b7280")
```

### Badge Styling
- Corner radius: 20px
- Padding: 6px horizontal, 4px vertical
- Font size: 14px
- Font weight: Semibold
- Include icon (checkmark for good, alert for improvement)

### Image Display Guidelines
- Maintain aspect ratio
- Show loading placeholder (gray box with spinner)
- Error state: Show camera icon with "Image unavailable"
- Cache images using SDWebImage or similar
- Thumbnail size: 300x200 (approximate)
- Full size: Device width, max height 60% of screen

## Features to Include

### 1. Filtering & Sorting
**Filter Options** (Segmented Control):
- All Examples
- Good Examples
- Needs Improvement

**Sort Options**:
- Newest First (default)
- Oldest First

### 2. View Toggle
- Grid View: 2 columns on iPhone, 3-4 on iPad
- List View: Full width cards with larger preview

### 3. Image Viewer Features
- Full-screen mode on tap
- Save to Photos (request permission first)
- Share sheet integration
- Zoom controls (pinch or double-tap)
- Pan when zoomed
- Smooth animations between images

### 4. Pull to Refresh
- Standard iOS pull-to-refresh gesture
- Fetches latest critiques from Firestore

### 5. Empty States
When no critiques exist:
- Icon: Camera or training-related icon
- Title: "No Training Photos Yet"
- Message: "Your training examples will appear here when managers submit them."

## Navigation Flow

```
Tab Bar
  └── Training (New Tab)
      ├── Header: "Training Photos"
      ├── Statistics Cards (3 cards in row)
      ├── Filter Segmented Control
      ├── View Toggle (Grid/List icons)
      └── Scrollable Content Area
          └── Critique Cards → Tap → Detail View (Modal Presentation)
              ├── Navigation Bar with Close
              ├── Image Gallery Section
              ├── Information Section
              └── Manager Notes Section
```

## SwiftUI Implementation Examples

### Statistics Card
```swift
struct StatsCard: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
```

### Critique Card (Grid View)
```swift
struct CritiqueGridCard: View {
    let critique: Critique
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image with badges
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: critique.thumbnailUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .foregroundColor(.gray.opacity(0.2))
                        .overlay(ProgressView())
                }
                .frame(height: 150)
                .clipped()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Example type badge
                    ExampleTypeBadge(type: critique.exampleType)
                    
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
                }
                
                Text(critique.managerNotes)
                    .font(.system(size: 14))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                Text(critique.createdAt.formatted())
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
```

### Example Type Badge
```swift
struct ExampleTypeBadge: View {
    let type: String
    
    var isGoodExample: Bool {
        type == "example"
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isGoodExample ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            
            Text(isGoodExample ? "Good Example" : "Needs Improvement")
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isGoodExample ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
        .foregroundColor(isGoodExample ? .green : .orange)
        .cornerRadius(20)
    }
}
```

## Firebase Service Implementation

```swift
class PhotoCritiqueService: ObservableObject {
    @Published var critiques: [Critique] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()
    
    func startListening(for userId: String, organizationId: String) {
        isLoading = true
        
        listener = db.collection("photoCritiques")
            .whereField("targetPhotographerId", isEqualTo: userId)
            .whereField("organizationId", isEqualTo: organizationId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                self?.isLoading = false
                
                if let error = error {
                    self?.error = error
                    return
                }
                
                self?.critiques = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: Critique.self)
                } ?? []
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    var statistics: CritiqueStats {
        CritiqueStats(
            total: critiques.count,
            goodExamples: critiques.filter { $0.exampleType == "example" }.count,
            needsImprovement: critiques.filter { $0.exampleType == "improvement" }.count
        )
    }
}
```

## Data Models

```swift
struct Critique: Codable, Identifiable {
    @DocumentID var id: String?
    let organizationId: String
    
    // Submission info
    let submitterId: String
    let submitterName: String
    let submitterEmail: String
    
    // Target photographer
    let targetPhotographerId: String
    let targetPhotographerName: String
    
    // Images
    let imageUrls: [String]
    let thumbnailUrls: [String]
    let imageUrl: String  // Backward compatibility
    let thumbnailUrl: String
    let imageCount: Int
    
    // Content
    let managerNotes: String
    let exampleType: String  // "example" or "improvement"
    let status: String
    
    // Timestamps
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

struct CritiqueStats {
    let total: Int
    let goodExamples: Int
    let needsImprovement: Int
}
```

## Performance Considerations

1. **Image Caching**: Use SDWebImage or Kingfisher for efficient image loading
2. **Pagination**: If photographer has >50 critiques, implement pagination
3. **Lazy Loading**: Use LazyVGrid or LazyVStack for large lists
4. **Thumbnail First**: Always load thumbnails in list, full images only in detail
5. **Memory Management**: Clear image cache when app enters background

## Testing Checklist

- [ ] App correctly queries only critiques for logged-in photographer
- [ ] All critiques within organization are visible
- [ ] Grid and list views toggle correctly
- [ ] Filter by example type works
- [ ] Images load and display with correct aspect ratio
- [ ] Multiple images can be viewed and navigated
- [ ] Manager notes display completely in detail view
- [ ] Statistics calculate accurately
- [ ] Real-time updates when new critiques are added
- [ ] Pull-to-refresh updates the list
- [ ] Empty state shows when no critiques exist
- [ ] Network error handling shows appropriate messages
- [ ] Image loading states and errors handled gracefully
- [ ] Save to Photos works with permission
- [ ] Share functionality works correctly

## Notes for Implementation

1. **Authentication Check**: Ensure user is authenticated and has `isPhotographer: true` in their profile
2. **Read-Only**: No create, edit, or delete functionality needed
3. **Real-time Updates**: Use Firestore listeners for immediate updates when managers add critiques
4. **Offline Support**: Enable Firestore offline persistence for viewing cached critiques
5. **iPad Support**: Adjust grid columns and modal presentation for iPad
6. **Accessibility**: Add proper labels for VoiceOver support
7. **Dark Mode**: Ensure all colors work in both light and dark mode

This implementation will provide photographers with a clean, intuitive interface to view their training feedback while maintaining the read-only access appropriate for their role.