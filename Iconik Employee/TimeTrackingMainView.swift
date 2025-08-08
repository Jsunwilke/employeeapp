import SwiftUI

struct TimeTrackingMainView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    
    @State private var showingSessionSelection = false
    @State private var showingNotesInput = false
    @State private var showingCustomClockOut = false
    @State private var showingLongShiftAlert = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var pendingClockOutNotes: String? = nil
    @State private var showingActiveClockInEdit = false
    
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
        .onAppear {
            // Update existing entries with session names if needed
            timeTrackingService.updateExistingEntriesWithSessionNames()
        }
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
            .sheet(isPresented: $showingCustomClockOut) {
                if let entry = timeTrackingService.currentTimeEntry,
                   let clockInTime = entry.clockInTime {
                    CustomClockOutView(
                        timeTrackingService: timeTrackingService,
                        clockInTime: clockInTime,
                        onComplete: { _, _ in
                            // Completion handled in CustomClockOutView
                        }
                    )
                }
            }
            .sheet(isPresented: $showingActiveClockInEdit) {
                if let entry = timeTrackingService.currentTimeEntry {
                    ActiveClockInEditView(
                        timeEntry: entry,
                        timeTrackingService: timeTrackingService
                    )
                }
            }
            .alert("Long Shift Detected", isPresented: $showingLongShiftAlert) {
                Button("Clock Out Now") {
                    showingNotesInput = true
                }
                Button("Set Custom Time") {
                    showingCustomClockOut = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You've been clocked in for over 24 hours. Would you like to set a custom clock out time?")
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
                    checkForLongShift()
                }) {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                            .font(.body)
                        Text("Clock Out")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        // Add indicator for long shifts
                        if let entry = timeTrackingService.currentTimeEntry,
                           let clockInTime = entry.clockInTime {
                            let elapsed = Date().timeIntervalSince(clockInTime)
                            if elapsed > 24 * 60 * 60 {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                
                // Edit Clock-In Time Button
                Button(action: {
                    showingActiveClockInEdit = true
                }) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.body)
                        Text("Edit Clock-In Time")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.blue)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
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
                    if let sessionName = entry.sessionName, sessionName != sessionId {
                        // Show the session name if it's different from the ID
                        Text(sessionName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        // Show just "Session" if we couldn't find the session details
                        Text("Session")
                            .font(.caption)
                    }
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
    
    private func checkForLongShift() {
        // Check if user has been clocked in for over 24 hours
        if let entry = timeTrackingService.currentTimeEntry,
           let clockInTime = entry.clockInTime {
            let elapsed = Date().timeIntervalSince(clockInTime)
            
            if elapsed > 24 * 60 * 60 { // Over 24 hours
                showingLongShiftAlert = true
            } else {
                // Normal clock out flow
                showingNotesInput = true
            }
        } else {
            // No active entry, shouldn't happen but handle gracefully
            showingNotesInput = true
        }
    }
    
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