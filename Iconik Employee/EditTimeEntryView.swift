import SwiftUI
import FirebaseFirestore

struct EditTimeEntryView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @Environment(\.presentationMode) var presentationMode
    
    let timeEntry: TimeEntry
    
    @State private var clockInDate: Date
    @State private var clockInTime: Date
    @State private var clockOutDate: Date
    @State private var clockOutTime: Date
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
        let clockIn = timeEntry.clockInTime ?? Date()
        let clockOut = timeEntry.clockOutTime ?? Date()
        
        _clockInDate = State(initialValue: clockIn)
        _clockInTime = State(initialValue: clockIn)
        _clockOutDate = State(initialValue: clockOut)
        _clockOutTime = State(initialValue: clockOut)
        _notes = State(initialValue: timeEntry.notes ?? "")
    }
    
    // Computed properties for combined date/time
    private var combinedClockIn: Date {
        combineDateAndTime(date: clockInDate, time: clockInTime)
    }
    
    private var combinedClockOut: Date {
        combineDateAndTime(date: clockOutDate, time: clockOutTime)
    }
    
    private func combineDateAndTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        
        return calendar.date(from: combined) ?? Date()
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
                    Section(header: Text("Clock In")) {
                        DatePicker("Date", selection: $clockInDate, 
                                  in: ...Date(), // Cannot be in the future
                                  displayedComponents: .date)
                            .disabled(timeEntry.status == "clocked-in") // Don't allow date change for active entries
                        
                        DatePicker("Time", selection: $clockInTime, 
                                  displayedComponents: .hourAndMinute)
                    }
                    
                    // Only show Clock Out section for completed entries
                    if timeEntry.status != "clocked-in" {
                        Section(header: Text("Clock Out")) {
                        DatePicker("Date", selection: $clockOutDate,
                                  in: clockInDate...Date(), // Must be after clock in, not in future
                                  displayedComponents: .date)
                            .onChange(of: clockOutDate) { _ in
                                validateDuration()
                            }
                        
                        DatePicker("Time", selection: $clockOutTime,
                                  displayedComponents: .hourAndMinute)
                            .onChange(of: clockOutTime) { _ in
                                validateDuration()
                            }
                        
                        // Duration display with validation
                        HStack {
                            Text("Duration")
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(formattedDuration)
                                    .foregroundColor(isDurationValid ? .blue : .red)
                                    .fontWeight(.semibold)
                                
                                if combinedClockOut > combinedClockIn && 
                                   !Calendar.current.isDate(clockInDate, inSameDayAs: clockOutDate) {
                                    Label("Crosses midnight", systemImage: "moon.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                
                                if !isDurationValid {
                                    Text(durationError)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    }
                    
                    // Session selection (if available) - disabled for active entries
                    if !availableSessions.isEmpty && timeEntry.status != "clocked-in" {
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
                    
                    // Notes section - always editable
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
                    
                    // Validation warnings - only for completed entries
                    if !isValidEntry && timeEntry.status != "clocked-in" {
                        Section {
                            Label(validationMessage, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Show info for active entries
                    if timeEntry.status == "clocked-in" {
                        Section {
                            Label("You can only edit the clock-in time and notes while actively clocked in", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
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
        let duration = combinedClockOut.timeIntervalSince(combinedClockIn)
        return duration.formatAsHoursMinutes()
    }
    
    private var isDurationValid: Bool {
        let duration = combinedClockOut.timeIntervalSince(combinedClockIn)
        return duration > 0 && duration <= 24 * 60 * 60
    }
    
    private var durationError: String {
        let duration = combinedClockOut.timeIntervalSince(combinedClockIn)
        if duration <= 0 {
            return "End must be after start"
        } else if duration > 24 * 60 * 60 {
            return "Exceeds 24 hour limit"
        }
        return ""
    }
    
    private var isValidEntry: Bool {
        // For active entries, only validate clock-in time
        if timeEntry.status == "clocked-in" {
            // Validate clock-in time is not in future and within 48 hours
            let validation = TimeEntryValidator.canEditActiveClockIn(timeEntry, newClockInTime: combinedClockIn)
            return validation.isValid
        }
        
        // Clock out must be after clock in
        guard combinedClockOut > combinedClockIn else { return false }
        
        // Duration must be at least 1 minute
        let duration = combinedClockOut.timeIntervalSince(combinedClockIn)
        guard duration >= 60 else { return false }
        
        // Duration must not exceed 24 hours (for cross-midnight support)
        guard duration <= 24 * 3600 else { return false }
        
        // Cannot create future entries
        guard combinedClockOut <= Date() else { return false }
        
        return true
    }
    
    private func validateDuration() {
        // Auto-adjust if needed
        if combinedClockOut <= combinedClockIn {
            // Move clock out to next day if times suggest crossing midnight
            let calendar = Calendar.current
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: clockInDate) {
                clockOutDate = nextDay
            }
        }
    }
    
    private var validationMessage: String {
        if combinedClockOut <= combinedClockIn {
            return "Clock out time must be after clock in time"
        }
        
        let duration = combinedClockOut.timeIntervalSince(combinedClockIn)
        if duration < 60 {
            return "Duration must be at least 1 minute"
        }
        
        if duration > 24 * 3600 {
            return "Duration cannot exceed 24 hours"
        }
        
        if combinedClockOut > Date() {
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
        
        // Use combined date/time values for cross-midnight support
        timeTrackingService.updateTimeEntry(
            entryId: timeEntry.id,
            startTime: combinedClockIn,
            endTime: combinedClockOut,
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