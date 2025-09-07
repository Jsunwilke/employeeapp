import SwiftUI

struct SessionTypePill: View {
    let sessionType: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            // Icon based on session type
            if let icon = iconForSessionType(sessionType) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
            }
            
            Text(sessionType)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
        )
        .foregroundColor(color)
    }
    
    private func iconForSessionType(_ type: String) -> String? {
        let lowercased = type.lowercased()
        
        if lowercased.contains("photographer") {
            return "camera.fill"
        } else if lowercased.contains("poser") {
            return "person.fill"
        } else if lowercased.contains("production") {
            return "gearshape.fill"
        } else if lowercased.contains("delivery") {
            return "shippingbox.fill"
        } else if lowercased.contains("office") {
            return "building.2.fill"
        } else if lowercased.contains("sales") {
            return "chart.line.uptrend.xyaxis"
        } else if lowercased.contains("yearbook") {
            return "book.fill"
        } else if lowercased.contains("graphic") {
            return "paintbrush.fill"
        } else if lowercased.contains("leader") {
            return "star.fill"
        }
        
        return nil
    }
}

// Preview
struct SessionTypePill_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            SessionTypePill(sessionType: "Photographer 1", color: .blue)
            SessionTypePill(sessionType: "Poser 1", color: .green)
            SessionTypePill(sessionType: "Production", color: .orange)
            SessionTypePill(sessionType: "Sales Representative", color: .purple)
        }
        .padding()
    }
}