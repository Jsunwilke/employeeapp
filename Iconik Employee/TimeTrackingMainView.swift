import SwiftUI

struct TimeTrackingMainView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    
    @State private var showingSessionSelection = false
    @State private var showingNotesInput = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 8) {
            // Header with current status
            statusHeaderView
            
            // Main clock in/out interface
            clockStatusView
            
            // Time entries list - expanded to show more entries
            TimeEntryListView(timeTrackingService: timeTrackingService)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .navigationTitle("Time Tracking")
        .navigationBarTitleDisplayMode(.inline) // Make title more compact
            .sheet(isPresented: $showingSessionSelection) {
                SessionSelectionView(
                    timeTrackingService: timeTrackingService,
                    onClockIn: { sessionId, notes in
                        clockIn(sessionId: sessionId, notes: notes)
                    }
                )
            }
            .sheet(isPresented: $showingNotesInput) {
                NotesInputView(
                    isClockOut: true,
                    onComplete: { notes in
                        clockOut(notes: notes)
                    }
                )
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("Time Tracking"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
    }
    
    // MARK: - UI Components
    
    private var statusHeaderView: some View {
        VStack(spacing: 4) {
            if timeTrackingService.isClockIn {
                Text("Currently Clocked In")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                
                Text(timeTrackingService.formatElapsedTime())
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                if let entry = timeTrackingService.currentTimeEntry,
                   let clockInTime = entry.clockInTime {
                    Text("Since \(formatTime(clockInTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Currently Clocked Out")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
                
                Text("Ready to start")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
        )
    }
    
    private var clockStatusView: some View {
        VStack(spacing: 8) {
            if timeTrackingService.isClockIn {
                // Clock Out Button
                Button(action: {
                    showingNotesInput = true
                }) {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                            .font(.body)
                        Text("Clock Out")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                
                // Current session info if available - more compact
                if let entry = timeTrackingService.currentTimeEntry {
                    currentSessionInfoView(entry: entry)
                }
            } else {
                // Clock In Button
                Button(action: {
                    showingSessionSelection = true
                }) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .font(.body)
                        Text("Clock In")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private func currentSessionInfoView(entry: TimeEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current Session")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            if let sessionId = entry.sessionId {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Session: \(sessionId)")
                        .font(.caption)
                }
            }
            
            if let notes = entry.notes, !notes.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "note.text")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(notes)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray6))
        )
    }
    
    // MARK: - Actions
    
    private func clockIn(sessionId: String?, notes: String?) {
        timeTrackingService.clockIn(sessionId: sessionId, notes: notes) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    showingSessionSelection = false
                } else {
                    alertMessage = errorMessage ?? "Failed to clock in"
                    showingAlert = true
                }
            }
        }
    }
    
    private func clockOut(notes: String?) {
        timeTrackingService.clockOut(notes: notes) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    showingNotesInput = false
                } else {
                    alertMessage = errorMessage ?? "Failed to clock out"
                    showingAlert = true
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    TimeTrackingMainView(timeTrackingService: TimeTrackingService())
}