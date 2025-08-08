import SwiftUI
import FirebaseFirestore

struct ActiveClockInEditView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @Environment(\.presentationMode) var presentationMode
    
    let currentEntry: TimeEntry
    
    @State private var clockInDate: Date
    @State private var clockInTime: Date
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    init(timeEntry: TimeEntry, timeTrackingService: TimeTrackingService) {
        self.currentEntry = timeEntry
        self.timeTrackingService = timeTrackingService
        
        // Initialize with current clock-in time
        let clockIn = timeEntry.clockInTime ?? Date()
        _clockInDate = State(initialValue: clockIn)
        _clockInTime = State(initialValue: clockIn)
    }
    
    private var combinedClockIn: Date {
        combineDateAndTime(date: clockInDate, time: clockInTime)
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
    
    private var isValidTime: Bool {
        let validation = TimeEntryValidator.canEditActiveClockIn(currentEntry, newClockInTime: combinedClockIn)
        return validation.isValid
    }
    
    private var elapsedTime: String {
        let duration = Date().timeIntervalSince(combinedClockIn)
        return formatDuration(duration)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return String(format: "%dh %dm", hours, minutes)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Current status section
                Section(header: Text("Current Status")) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("Currently Clocked In")
                                .font(.headline)
                                .foregroundColor(.green)
                            Text("Adjusting clock-in time will update your total hours")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Clock-in time adjustment
                Section(header: Text("Adjust Clock-In Time")) {
                    DatePicker("Date", selection: $clockInDate,
                              in: ...Date(), // Cannot be in the future
                              displayedComponents: .date)
                    
                    DatePicker("Time", selection: $clockInTime,
                              displayedComponents: .hourAndMinute)
                    
                    // Show validation message
                    if !isValidTime {
                        let validation = TimeEntryValidator.canEditActiveClockIn(currentEntry, newClockInTime: combinedClockIn)
                        if let error = validation.error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                
                // Preview section
                Section(header: Text("Preview")) {
                    HStack {
                        Text("New Clock-In")
                        Spacer()
                        Text(formatDateTime(combinedClockIn))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Time Elapsed")
                        Spacer()
                        Text(elapsedTime)
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    
                    if let originalClockIn = currentEntry.clockInTime {
                        HStack {
                            Text("Original Clock-In")
                            Spacer()
                            Text(formatDateTime(originalClockIn))
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }
                
                // Info section
                Section {
                    Label("Clock-in time can only be adjusted within the last 48 hours", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Clock-In Time")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    updateClockInTime()
                }
                .disabled(!isValidTime || isLoading)
            )
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Update Failed"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func updateClockInTime() {
        isLoading = true
        
        // Call the service to update the active clock-in time
        timeTrackingService.updateActiveClockInTime(newClockInTime: combinedClockIn) { success, error in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    presentationMode.wrappedValue.dismiss()
                } else {
                    alertMessage = error ?? "Failed to update clock-in time"
                    showingAlert = true
                }
            }
        }
    }
}