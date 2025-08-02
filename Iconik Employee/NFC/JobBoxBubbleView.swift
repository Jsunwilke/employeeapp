import SwiftUI

struct JobBoxBubbleView: View {
    let record: JobBox
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: record.timestamp)
    }
    
    private var statusColor: Color {
        switch record.status {
        case .packed: return .blue
        case .pickedUp: return .orange
        case .leftJob: return .red
        case .turnedIn: return .green
        case .unknown: return .gray
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
                    Text(record.status.rawValue)
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
                
                Text("Photographer: \(record.scannedBy)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Show warning if left job for too long
                if record.status == .leftJob {
                    let timeDiff = Date().timeIntervalSince(record.timestamp)
                    if timeDiff > 43200 { // 12 hours
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Left for \(formatTimeDifference(timeDiff))")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func formatTimeDifference(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        if hours > 24 {
            let days = hours / 24
            return "\(days) day\(days > 1 ? "s" : "")"
        } else {
            return "\(hours) hour\(hours > 1 ? "s" : "")"
        }
    }
}