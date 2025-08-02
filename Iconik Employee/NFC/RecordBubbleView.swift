import SwiftUI

struct RecordBubbleView: View {
    let record: FirestoreRecord
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: record.timestamp)
    }
    
    private var statusColor: Color {
        switch record.status.lowercased() {
        case "job box": return .blue
        case "camera": return .orange
        case "envelope": return .purple
        case "uploaded": return .green
        case "cleared": return .gray
        case "camera bag": return .brown
        case "personal": return .indigo
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: 4) {
                // Header row
                HStack {
                    Text(record.status)
                        .font(.headline)
                        .foregroundColor(statusColor)
                    
                    Spacer()
                    
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Details
                Text("School: \(record.school)")
                    .font(.subheadline)
                
                Text("Photographer: \(record.photographer)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Upload location if applicable
                if record.status.lowercased() == "uploaded" {
                    if let jasonHouse = record.uploadedFromJasonsHouse, !jasonHouse.isEmpty {
                        Text("📍 Uploaded from Jason's house")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let andyHouse = record.uploadedFromAndysHouse, !andyHouse.isEmpty {
                        Text("📍 Uploaded from Andy's house")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}