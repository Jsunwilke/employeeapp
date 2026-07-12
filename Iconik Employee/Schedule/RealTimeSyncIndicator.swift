import SwiftUI

/// Real-time sync status indicator
/// Shows users when data is syncing, last updated, or if offline
struct RealTimeSyncIndicator: View {
    // Backed by the app's real connectivity signal (an NWPathMonitor lives on
    // SessionService), so "Live"/"Offline" reflects actual network state
    // instead of being hardcoded.
    @ObservedObject private var sessionService = SessionService.shared
    @State private var lastUpdateTime: Date = Date()
    @State private var isAnimating: Bool = false

    private var isOnline: Bool { sessionService.isConnected }

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
            .onChange(of: sessionService.isConnected) { newValue in
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
        .onChange(of: sessionService.isConnected) { newValue in
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
        }
        .onChange(of: sessionService.isConnected) { newValue in
            isAnimating = newValue
        }
        .task {
            // Update the time display every minute using async/await (auto-cancelled on view disappear)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                // Force a UI refresh by updating the state
                lastUpdateTime = lastUpdateTime
            }
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