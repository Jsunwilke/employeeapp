import SwiftUI
import FirebaseFirestore

struct TimeEntryDetailView: View {
    let timeEntry: TimeEntry
    @Environment(\.presentationMode) var presentationMode
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Entry status section
                Section(header: Text("Entry Status")) {
                    HStack {
                        Image(systemName: entryTypeIcon)
                            .foregroundColor(entryTypeColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entryTypeDescription)
                                .font(.headline)
                            
                            if timeEntry.status == "clocked-in" {
                                Text("Currently active")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else if TimeEntryValidator.canEditEntry(timeEntry) {
                                Text("Editable (within 30-day window)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            } else {
                                Text("Read-only (outside edit window or system-generated)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Spacer()
                    }
                }
                
                // Time details section
                Section(header: Text("Time Details")) {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(formatDate(timeEntry.date))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Start Time")
                        Spacer()
                        Text(formatTime(timeEntry.clockInTime))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("End Time")
                        Spacer()
                        Text(formatTime(timeEntry.clockOutTime))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(timeEntry.formattedDuration)
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    
                    if let createdAt = timeEntry.createdAt {
                        HStack {
                            Text("Created")
                            Spacer()
                            Text(formatDateTime(createdAt))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let updatedAt = timeEntry.updatedAt, updatedAt != timeEntry.createdAt {
                        HStack {
                            Text("Last Modified")
                            Spacer()
                            Text(formatDateTime(updatedAt))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Session information
                if let sessionId = timeEntry.sessionId {
                    Section(header: Text("Associated Session")) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                            Text("Session ID: \(sessionId)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Notes section
                if let notes = timeEntry.notes, !notes.isEmpty {
                    Section(header: Text("Notes")) {
                        Text(notes)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Additional information
                Section(header: Text("Technical Details")) {
                    HStack {
                        Text("Entry ID")
                        Spacer()
                        Text(timeEntry.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(timeEntry.status.capitalized)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Organization")
                        Spacer()
                        Text(timeEntry.organizationID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("User ID")
                        Spacer()
                        Text(timeEntry.userId)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Time Entry Details")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    // MARK: - Computed Properties
    
    private var entryTypeIcon: String {
        if timeEntry.status == "clocked-in" {
            return "play.circle.fill"
        } else if isManualEntry {
            return "pencil.circle"
        } else {
            return "clock.circle"
        }
    }
    
    private var entryTypeColor: Color {
        if timeEntry.status == "clocked-in" {
            return .green
        } else if isManualEntry && TimeEntryValidator.canEditEntry(timeEntry) {
            return .blue
        } else if isManualEntry {
            return .orange
        } else {
            return .gray
        }
    }
    
    private var entryTypeDescription: String {
        if timeEntry.status == "clocked-in" {
            return "Active Clock Entry"
        } else if isManualEntry {
            return "Manual Time Entry"
        } else {
            return "Clock-based Entry"
        }
    }
    
    private var isManualEntry: Bool {
        // Manual entries have both clockInTime and clockOutTime and are not active
        timeEntry.clockInTime != nil && timeEntry.clockOutTime != nil && timeEntry.status != "clocked-in"
    }
    
    // MARK: - Helper Functions
    
    private func formatDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        if let date = inputFormatter.date(from: dateString) {
            return dateFormatter.string(from: date)
        }
        
        return dateString
    }
    
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        return timeFormatter.string(from: date)
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    // Create a sample TimeEntry directly for preview
    let sampleEntry = TimeEntry(
        id: "sample-entry-id",
        userId: "sample-user-id",
        organizationID: "sample-org-id",
        clockInTime: Calendar.current.date(byAdding: .hour, value: -8, to: Date()),
        clockOutTime: Calendar.current.date(byAdding: .hour, value: -2, to: Date()),
        date: "2024-07-12",
        status: "completed",
        sessionId: "sample-session-id",
        notes: "Sample time entry for preview",
        createdAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
        updatedAt: Date()
    )
    
    TimeEntryDetailView(timeEntry: sampleEntry)
}