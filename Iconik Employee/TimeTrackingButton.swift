import SwiftUI

struct TimeTrackingButton: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @State private var showingTimeTrackingView = false
    @State private var showingSessionSelection = false
    
    var body: some View {
        Button(action: {
            if timeTrackingService.isClockIn {
                // If clocked in, show the main view to allow clock out
                showingTimeTrackingView = true
            } else {
                // If clocked out, go directly to session selection
                showingSessionSelection = true
            }
        }) {
            HStack(spacing: 6) {
                // Main timer icon or status
                Image(systemName: timeTrackingService.isClockIn ? "pause.circle.fill" : "play.circle.fill")
                    .font(.body)
                    .foregroundColor(.white)
                
                // Show elapsed time when clocked in, "Clock In" when clocked out
                if timeTrackingService.isClockIn {
                    Text(timeTrackingService.formatElapsedTime())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Clock In")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(timeTrackingService.isClockIn ? Color.orange : Color.blue)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(showingTimeTrackingView ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: showingTimeTrackingView)
        .sheet(isPresented: $showingTimeTrackingView) {
            NavigationView {
                TimeTrackingMainView(timeTrackingService: timeTrackingService)
            }
        }
        .sheet(isPresented: $showingSessionSelection) {
            SessionSelectionView(
                timeTrackingService: timeTrackingService,
                onClockIn: { sessionId, notes in
                    clockIn(sessionId: sessionId, notes: notes)
                }
            )
        }
        .onAppear {
            // Check current status when button appears
            timeTrackingService.checkCurrentStatus()
        }
    }
    
    // MARK: - Helper Functions
    
    private func clockIn(sessionId: String?, notes: String?) {
        timeTrackingService.clockIn(sessionId: sessionId, notes: notes) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    showingSessionSelection = false
                }
            }
        }
    }
}

struct TimeTrackingFloatingButton: View {
    @StateObject private var timeTrackingService = TimeTrackingService()
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                TimeTrackingButton(timeTrackingService: timeTrackingService)
                    .padding(.trailing, 20)
                    .padding(.bottom, 100) // Adjust based on tab bar height
            }
        }
        .allowsHitTesting(true)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1)
            .ignoresSafeArea()
        
        TimeTrackingFloatingButton()
    }
}