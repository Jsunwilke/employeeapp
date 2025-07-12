import SwiftUI

struct SessionSelectionView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @Environment(\.presentationMode) var presentationMode
    
    let onClockIn: (String?, String?) -> Void
    
    @State private var selectedSession: Session?
    @State private var notes = ""
    @State private var availableSessions: [Session] = []
    @State private var isLoading = true
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView("Loading today's sessions...")
                        .padding()
                } else {
                    if availableSessions.isEmpty {
                        emptySessionsView
                    } else {
                        sessionListView
                    }
                    
                    Spacer()
                    
                    notesSection
                    
                    clockInButton
                }
            }
            .padding()
            .navigationTitle("Clock In")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .onAppear {
            loadTodaysSessions()
        }
    }
    
    // MARK: - UI Components
    
    private var emptySessionsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No sessions assigned for today")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("You can still clock in without selecting a session")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var sessionListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Sessions")
                .font(.headline)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(availableSessions, id: \.id) { session in
                        SessionRow(
                            session: session,
                            isSelected: selectedSession?.id == session.id,
                            timeFormatter: timeFormatter
                        )
                        .onTapGesture {
                            selectedSession = session
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes (optional)")
                .font(.headline)
            
            TextField("Add notes for this time entry...", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
    }
    
    private var clockInButton: some View {
        Button(action: {
            onClockIn(selectedSession?.id, notes.isEmpty ? nil : notes)
        }) {
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                Text("Clock In")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Functions
    
    private func loadTodaysSessions() {
        timeTrackingService.getTodayAssignedSessions { sessions in
            DispatchQueue.main.async {
                self.availableSessions = sessions.sorted { session1, session2 in
                    guard let start1 = session1.startDate,
                          let start2 = session2.startDate else {
                        return false
                    }
                    return start1 < start2
                }
                self.isLoading = false
            }
        }
    }
}

struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let timeFormatter: DateFormatter
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.schoolName)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(session.position)
                    .font(.subheadline)
                    .foregroundColor(.blue)
                
                if let start = session.startDate, let end = session.endDate {
                    Text("\(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let location = session.location, !location.isEmpty {
                    HStack {
                        Image(systemName: "location")
                            .font(.caption)
                        Text(location)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
                    .font(.title2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    SessionSelectionView(
        timeTrackingService: TimeTrackingService(),
        onClockIn: { _, _ in }
    )
}