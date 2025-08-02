import SwiftUI

// MARK: - Unified Status Color Scheme
// These colors should be used consistently across iOS and web apps

struct StatusColors {
    // MARK: - SD Card Status Colors
    static let sdCardColors: [String: Color] = [
        "job box": Color(red: 255/255, green: 149/255, blue: 0/255),      // Orange
        "camera": Color(red: 52/255, green: 199/255, blue: 89/255),       // Green
        "envelope": Color(red: 255/255, green: 204/255, blue: 0/255),     // Yellow
        "uploaded": Color(red: 0/255, green: 122/255, blue: 255/255),     // Blue
        "cleared": Color(red: 142/255, green: 142/255, blue: 147/255),    // Gray
        "camera bag": Color(red: 175/255, green: 82/255, blue: 222/255),  // Purple
        "personal": Color(red: 88/255, green: 86/255, blue: 214/255)      // Indigo
    ]
    
    // MARK: - Job Box Status Colors
    static let jobBoxColors: [String: Color] = [
        "packed": Color(red: 0/255, green: 122/255, blue: 255/255),       // Blue
        "picked up": Color(red: 52/255, green: 199/255, blue: 89/255),    // Green
        "left job": Color(red: 255/255, green: 149/255, blue: 0/255),     // Orange
        "turned in": Color(red: 142/255, green: 142/255, blue: 147/255)   // Gray
    ]
    
    // MARK: - Get color for any status
    static func color(for status: String, isJobBox: Bool = false) -> Color {
        let lowercasedStatus = status.lowercased()
        
        if isJobBox {
            return jobBoxColors[lowercasedStatus] ?? Color.gray
        } else {
            return sdCardColors[lowercasedStatus] ?? Color.gray
        }
    }
    
    // MARK: - Hex values for web compatibility
    static let sdCardHexColors: [String: String] = [
        "job box": "#FF9500",     // Orange
        "camera": "#34C759",      // Green
        "envelope": "#FFCC00",    // Yellow
        "uploaded": "#007AFF",    // Blue
        "cleared": "#8E8E93",     // Gray
        "camera bag": "#AF52DE",  // Purple
        "personal": "#5856D6"     // Indigo
    ]
    
    static let jobBoxHexColors: [String: String] = [
        "packed": "#007AFF",      // Blue
        "picked up": "#34C759",   // Green
        "left job": "#FF9500",    // Orange
        "turned in": "#8E8E93"    // Gray
    ]
    
    // MARK: - Get hex color for web
    static func hexColor(for status: String, isJobBox: Bool = false) -> String {
        let lowercasedStatus = status.lowercased()
        
        if isJobBox {
            return jobBoxHexColors[lowercasedStatus] ?? "#8E8E93"
        } else {
            return sdCardHexColors[lowercasedStatus] ?? "#8E8E93"
        }
    }
}

// MARK: - Color Extension for RGB values
extension Color {
    var rgbComponents: (red: Double, green: Double, blue: Double) {
        // This is a placeholder - actual implementation would extract RGB values
        // For now, returning dummy values
        return (red: 0, green: 0, blue: 0)
    }
}

// MARK: - Usage Examples
/*
 
 iOS Usage:
 -----------
 // In your views:
 Circle()
     .fill(StatusColors.color(for: "job box"))
 
 // For job boxes:
 Circle()
     .fill(StatusColors.color(for: "packed", isJobBox: true))
 
 
 Web Usage (JavaScript/CSS):
 ---------------------------
 // Create a matching object in your web app:
 const StatusColors = {
     sdCard: {
         "job box": "#FF9500",
         "camera": "#34C759",
         "envelope": "#FFCC00",
         "uploaded": "#007AFF",
         "cleared": "#8E8E93",
         "camera bag": "#AF52DE",
         "personal": "#5856D6"
     },
     jobBox: {
         "packed": "#007AFF",
         "picked up": "#34C759",
         "left job": "#FF9500",
         "turned in": "#8E8E93"
     }
 };
 
 // Usage in React/Vue/etc:
 style={{ backgroundColor: StatusColors.sdCard["job box"] }}
 
 */