import SwiftUI
import FirebaseFirestore

/// Real-time sync status indicator
/// Shows users when data is syncing, last updated, or if offline
struct RealTimeSyncIndicator: View {
    @State private var isOnline: Bool = true
    @State private var lastUpdateTime: Date = Date()
    @State private var isAnimating: Bool = false
    
    let style: IndicatorStyle
    
    enum IndicatorStyle {
        case compact    // Small dot with optional text
        case detailed   // Full status with timestamp
        case minimal    // Just the status dot
    }
    
    init(style: IndicatorStyle = .compact) {
        self.style = style
    }
    
    var body: some View {
        switch style {
        case .minimal:
            minimalIndicator
        case .compact:
            compactIndicator
        case .detailed:
            detailedIndicator
        }
    }
    
    // MARK: - Indicator Styles
    
    private var minimalIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 1.2 : 1.0)
            .animation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                if isOnline {
                    isAnimating = true
                }
            }
            .onChange(of: isOnline) { newValue in
                isAnimating = newValue
            }
    }
    
    private var compactIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )
            
            Text(statusText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .onAppear {
            if isOnline {
                isAnimating = true
            }
        }
        .onChange(of: isOnline) { newValue in
            isAnimating = newValue
        }
    }
    
    private var detailedIndicator: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAnimating ? 1.3 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            if isOnline {
                Text("Last updated: \(timeAgoString)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.secondarySystemBackground))
        )
        .onAppear {
            if isOnline {
                isAnimating = true
            }
            startUpdateTimer()
        }
        .onChange(of: isOnline) { newValue in
            isAnimating = newValue
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        isOnline ? .green : .orange
    }
    
    private var statusText: String {
        isOnline ? "Live" : "Offline"
    }
    
    private var timeAgoString: String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastUpdateTime)
        
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        }
    }
    
    // MARK: - Methods
    
    /// Call this when data is updated to refresh the timestamp
    func dataUpdated() {
        lastUpdateTime = Date()
        isOnline = true
    }
    
    /// Call this when connection is lost
    func connectionLost() {
        isOnline = false
    }
    
    /// Call this when connection is restored
    func connectionRestored() {
        isOnline = true
        lastUpdateTime = Date()
    }
    
    private func startUpdateTimer() {
        // Update the time display every minute for the detailed view
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            // This will trigger a UI update to refresh the "time ago" text
            lastUpdateTime = lastUpdateTime
        }
    }
}

// MARK: - Preview

struct RealTimeSyncIndicator_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Minimal Style")
                .font(.headline)
            RealTimeSyncIndicator(style: .minimal)
            
            Text("Compact Style")
                .font(.headline)
            RealTimeSyncIndicator(style: .compact)
            
            Text("Detailed Style")
                .font(.headline)
            RealTimeSyncIndicator(style: .detailed)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}