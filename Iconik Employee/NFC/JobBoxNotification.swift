import SwiftUI

struct JobBoxNotification: View {
    let jobBoxes: [(JobBox, TimeInterval)]
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)
                
                Text("Job Box Alert")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            if jobBoxes.count == 1 {
                let (record, timeDiff) = jobBoxes[0]
                Text("Box #\(record.boxNumber) has been in 'Left Job' status for \(formatTime(timeDiff))")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(jobBoxes.count) job boxes have been in 'Left Job' status for over 12 hours")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                
                ForEach(jobBoxes.prefix(3), id: \.0.id) { record, timeDiff in
                    HStack {
                        Text("• Box #\(record.boxNumber)")
                        Spacer()
                        Text(formatTime(timeDiff))
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                }
                
                if jobBoxes.count > 3 {
                    Text("...and \(jobBoxes.count - 3) more")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.orange.opacity(0.8),
                            Color.red.opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 20)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        
        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            if remainingHours > 0 {
                return "\(days)d \(remainingHours)h"
            } else {
                return "\(days) day\(days > 1 ? "s" : "")"
            }
        } else if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours) hour\(hours > 1 ? "s" : "")"
            }
        } else {
            return "\(minutes) min"
        }
    }
}