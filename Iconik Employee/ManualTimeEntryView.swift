import SwiftUI

struct ManualTimeEntryView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedDate = Date()
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var selectedSession: Session?
    @State private var notes = ""
    @State private var availableSessions: [Session] = []
    
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var characterCount = 0
    
    private let maxCharacters = 500
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Time Entry Details")) {
                    // Date picker
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .onChange(of: selectedDate) { _ in
                            updateTimesForNewDate()
                            loadSessionsForDate()
                        }
                    
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
                    Section(header: Text("Associated Session (Optional)")) {
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
                Section(header: Text("Notes (Optional)")) {
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
            }
            .navigationTitle("Add Manual Entry")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    createManualEntry()
                }
                .disabled(!isValidEntry || isLoading)
            )
        }
        .onAppear {
            setupDefaultTimes()
            loadSessionsForDate()
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
        // Use the same date+time combination logic for duration display
        let startDateTime = createDateTime(from: selectedDate, time: startTime)
        let endDateTime = createDateTime(from: selectedDate, time: endTime)
        let duration = endDateTime.timeIntervalSince(startDateTime)
        return duration.formatAsHoursMinutes()
    }
    
    private var isValidEntry: Bool {
        // Create proper date+time combinations
        let calendar = Calendar.current
        let startDateTime = createDateTime(from: selectedDate, time: startTime)
        let endDateTime = createDateTime(from: selectedDate, time: endTime)
        
        // End time must be after start time
        guard endDateTime > startDateTime else { return false }
        
        // Duration must be at least 1 minute
        let duration = endDateTime.timeIntervalSince(startDateTime)
        guard duration >= 60 else { return false }
        
        // Duration must not exceed 16 hours
        guard duration <= 16 * 3600 else { return false }
        
        // Cannot create future entries - check the end date+time against current moment
        guard endDateTime <= Date() else { return false }
        
        return true
    }
    
    // Helper function to combine date and time properly
    private func createDateTime(from date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: date) ?? date
    }
    
    private var validationMessage: String {
        // Create proper date+time combinations
        let startDateTime = createDateTime(from: selectedDate, time: startTime)
        let endDateTime = createDateTime(from: selectedDate, time: endTime)
        
        if endDateTime <= startDateTime {
            return "End time must be after start time"
        }
        
        let duration = endDateTime.timeIntervalSince(startDateTime)
        if duration < 60 {
            return "Duration must be at least 1 minute"
        }
        
        if duration > 16 * 3600 {
            return "Duration cannot exceed 16 hours"
        }
        
        if endDateTime > Date() {
            return "Cannot create entries for future times"
        }
        
        return ""
    }
    
    // MARK: - Functions
    
    private func setupDefaultTimes() {
        let calendar = Calendar.current
        let now = Date()
        
        // If selected date is today, use current time as starting point
        // Otherwise, use a reasonable default time (9 AM)
        let defaultHour: Int
        if calendar.isDate(selectedDate, inSameDayAs: now) {
            defaultHour = calendar.component(.hour, from: now)
        } else {
            defaultHour = 9 // 9 AM default for past dates
        }
        
        // Create start time by combining selected date with default hour
        startTime = calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        
        // Set end time to one hour later on the same date
        endTime = calendar.date(byAdding: .hour, value: 1, to: startTime) ?? startTime
    }
    
    private func updateTimesForNewDate() {
        let calendar = Calendar.current
        
        // Get the current hour and minute from existing time pickers
        let startHour = calendar.component(.hour, from: startTime)
        let startMinute = calendar.component(.minute, from: startTime)
        let endHour = calendar.component(.hour, from: endTime)
        let endMinute = calendar.component(.minute, from: endTime)
        
        // Combine the new selected date with the existing times
        startTime = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: selectedDate) ?? selectedDate
        endTime = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: selectedDate) ?? selectedDate
    }
    
    private func loadSessionsForDate() {
        timeTrackingService.getSessionsForDate(selectedDate) { sessions in
            DispatchQueue.main.async {
                self.availableSessions = sessions.sorted { session1, session2 in
                    guard let start1 = session1.startDate,
                          let start2 = session2.startDate else {
                        return false
                    }
                    return start1 < start2
                }
            }
        }
    }
    
    private func createManualEntry() {
        isLoading = true
        
        // Create proper date+time combinations for the service call
        let startDateTime = createDateTime(from: selectedDate, time: startTime)
        let endDateTime = createDateTime(from: selectedDate, time: endTime)
        
        timeTrackingService.createManualTimeEntry(
            date: selectedDate,
            startTime: startDateTime,
            endTime: endDateTime,
            sessionId: selectedSession?.id,
            notes: notes.isEmpty ? nil : notes
        ) { success, errorMessage in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if success {
                    self.presentationMode.wrappedValue.dismiss()
                } else {
                    self.alertMessage = errorMessage ?? "Failed to create time entry"
                    self.showingAlert = true
                }
            }
        }
    }
}

#Preview {
    ManualTimeEntryView(timeTrackingService: TimeTrackingService())
}