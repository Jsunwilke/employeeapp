import SwiftUI
import FirebaseFirestore

struct EditTimeEntryView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @Environment(\.presentationMode) var presentationMode
    
    let timeEntry: TimeEntry
    
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedSession: Session?
    @State private var notes: String
    @State private var availableSessions: [Session] = []
    
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var characterCount = 0
    @State private var showingDeleteConfirmation = false
    
    private let maxCharacters = 500
    
    init(timeEntry: TimeEntry, timeTrackingService: TimeTrackingService) {
        self.timeEntry = timeEntry
        self.timeTrackingService = timeTrackingService
        
        // Initialize state with current values
        _startTime = State(initialValue: timeEntry.clockInTime ?? Date())
        _endTime = State(initialValue: timeEntry.clockOutTime ?? Date())
        _notes = State(initialValue: timeEntry.notes ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Entry info section
                Section(header: Text("Time Entry Information")) {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(formatDate(timeEntry.date))
                            .foregroundColor(.secondary)
                    }
                    
                    if !TimeEntryValidator.canEditEntry(timeEntry) {
                        Label("This entry cannot be edited", systemImage: "lock")
                            .foregroundColor(.orange)
                    }
                }
                
                if TimeEntryValidator.canEditEntry(timeEntry) {
                    Section(header: Text("Time Details")) {
                        // Start time picker
                        DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                            .onChange(of: startTime) { _ in
                                // Auto-adjust end time if it's before start time
                                if endTime <= startTime {
                                    endTime = Calendar.current.date(byAdding: .hour, value: 1, to: startTime) ?? startTime
                                }
                            }
                        
                        // End time picker
                        DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                        
                        // Duration display
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(formattedDuration)
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                    
                    // Session selection (if available)
                    if !availableSessions.isEmpty {
                        Section(header: Text("Associated Session")) {
                            Picker("Session", selection: $selectedSession) {
                                Text("No Session").tag(nil as Session?)
                                
                                ForEach(availableSessions, id: \.id) { session in
                                    VStack(alignment: .leading) {
                                        Text(session.schoolName)
                                            .font(.headline)
                                        Text(session.position)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .tag(session as Session?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    
                    // Notes section
                    Section(header: Text("Notes")) {
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                            .onChange(of: notes) { value in
                                // Limit character count
                                if value.count > maxCharacters {
                                    notes = String(value.prefix(maxCharacters))
                                }
                                characterCount = notes.count
                            }
                        
                        HStack {
                            Spacer()
                            Text("\(characterCount)/\(maxCharacters)")
                                .font(.caption)
                                .foregroundColor(characterCount > maxCharacters * 9/10 ? .red : .secondary)
                        }
                    }
                    
                    // Validation warnings
                    if !isValidEntry {
                        Section {
                            Label(validationMessage, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Delete section
                    Section {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Time Entry")
                            }
                            .foregroundColor(.red)
                        }
                    }
                } else {
                    // Read-only display for non-editable entries
                    Section(header: Text("Time Details")) {
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
                    }
                    
                    if let sessionId = timeEntry.sessionId {
                        Section(header: Text("Associated Session")) {
                            Text("Session: \(sessionId)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let entryNotes = timeEntry.notes, !entryNotes.isEmpty {
                        Section(header: Text("Notes")) {
                            Text(entryNotes)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Edit Time Entry")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: saveButton
            )
        }
        .onAppear {
            loadSessionsForDate()
            characterCount = notes.count
            
            // Find and set the current session if it exists
            if let sessionId = timeEntry.sessionId {
                selectedSession = availableSessions.first { $0.id == sessionId }
            }
        }
        .alert("Delete Time Entry", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteTimeEntry()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this time entry? This action cannot be undone.")
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Time Entry"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // MARK: - Computed Properties
    
    private var formattedDuration: String {
        let duration = endTime.timeIntervalSince(startTime)
        return duration.formatAsHoursMinutes()
    }
    
    private var isValidEntry: Bool {
        // End time must be after start time
        guard endTime > startTime else { return false }
        
        // Duration must be at least 1 minute
        let duration = endTime.timeIntervalSince(startTime)
        guard duration >= 60 else { return false }
        
        // Duration must not exceed 16 hours
        guard duration <= 16 * 3600 else { return false }
        
        // Cannot create future entries
        guard endTime <= Date() else { return false }
        
        return true
    }
    
    private var validationMessage: String {
        if endTime <= startTime {
            return "End time must be after start time"
        }
        
        let duration = endTime.timeIntervalSince(startTime)
        if duration < 60 {
            return "Duration must be at least 1 minute"
        }
        
        if duration > 16 * 3600 {
            return "Duration cannot exceed 16 hours"
        }
        
        if endTime > Date() {
            return "Cannot create entries for future times"
        }
        
        return ""
    }
    
    private var saveButton: some View {
        Button("Save") {
            updateTimeEntry()
        }
        .disabled(!isValidEntry || isLoading || !TimeEntryValidator.canEditEntry(timeEntry))
    }
    
    // MARK: - Functions
    
    private func loadSessionsForDate() {
        // Parse the date from the entry's date string
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let entryDate = formatter.date(from: timeEntry.date) else { return }
        
        timeTrackingService.getSessionsForDate(entryDate) { sessions in
            DispatchQueue.main.async {
                self.availableSessions = sessions.sorted { session1, session2 in
                    guard let start1 = session1.startDate,
                          let start2 = session2.startDate else {
                        return false
                    }
                    return start1 < start2
                }
                
                // Set selected session if it exists
                if let sessionId = self.timeEntry.sessionId {
                    self.selectedSession = self.availableSessions.first { $0.id == sessionId }
                }
            }
        }
    }
    
    private func updateTimeEntry() {
        isLoading = true
        
        timeTrackingService.updateTimeEntry(
            entryId: timeEntry.id,
            startTime: startTime,
            endTime: endTime,
            sessionId: selectedSession?.id,
            notes: notes.isEmpty ? nil : notes
        ) { success, errorMessage in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if success {
                    self.presentationMode.wrappedValue.dismiss()
                } else {
                    self.alertMessage = errorMessage ?? "Failed to update time entry"
                    self.showingAlert = true
                }
            }
        }
    }
    
    private func deleteTimeEntry() {
        isLoading = true
        
        timeTrackingService.deleteTimeEntry(entryId: timeEntry.id) { success, errorMessage in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if success {
                    self.presentationMode.wrappedValue.dismiss()
                } else {
                    self.alertMessage = errorMessage ?? "Failed to delete time entry"
                    self.showingAlert = true
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        if let date = inputFormatter.date(from: dateString) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateStyle = .full
            return outputFormatter.string(from: date)
        }
        
        return dateString
    }
    
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        
        let formatter = DateFormatter()
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
    
    EditTimeEntryView(timeEntry: sampleEntry, timeTrackingService: TimeTrackingService())
}