import SwiftUI

struct CustomClockOutView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    let clockInTime: Date
    let onComplete: (Date, String?) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedDate = Date()
    @State private var selectedTime = Date()
    @State private var notes = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Computed property for combined date and time
    private var combinedDateTime: Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
        
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        
        return calendar.date(from: combined) ?? Date()
    }
    
    // Calculate duration
    private var duration: TimeInterval {
        combinedDateTime.timeIntervalSince(clockInTime)
    }
    
    private var durationString: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 24 {
            return "\(hours)h \(minutes)m ⚠️ Exceeds 24 hours"
        } else if hours > 12 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }
    
    private var isValidDuration: Bool {
        duration > 0 && duration <= 24 * 60 * 60
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Clock In Time")) {
                    HStack {
                        Image(systemName: "clock.badge.checkmark")
                            .foregroundColor(.green)
                        Text(formatDateTime(clockInTime))
                            .font(.system(.body, design: .monospaced))
                    }
                }
                
                Section(header: Text("Clock Out Date & Time")) {
                    DatePicker("Date", selection: $selectedDate, 
                              in: Calendar.current.startOfDay(for: clockInTime)...Date(),
                              displayedComponents: .date)
                    
                    DatePicker("Time", selection: $selectedTime,
                              displayedComponents: .hourAndMinute)
                    
                    // Quick presets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            quickPresetButton("End of Yesterday", date: endOfYesterday())
                            quickPresetButton("Start of Today", date: startOfToday())
                            quickPresetButton("Now", date: Date())
                        }
                    }
                }
                
                Section(header: Text("Duration")) {
                    HStack {
                        Image(systemName: duration > 24 * 60 * 60 ? "exclamationmark.triangle.fill" : 
                                        duration > 12 * 60 * 60 ? "moon.fill" : "clock.fill")
                            .foregroundColor(duration > 24 * 60 * 60 ? .red : 
                                           duration > 12 * 60 * 60 ? .orange : .blue)
                        Text(durationString)
                            .foregroundColor(duration > 24 * 60 * 60 ? .red : .primary)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    if duration > 12 * 60 * 60 && duration <= 24 * 60 * 60 {
                        Label("Long shift - crosses midnight", systemImage: "moon")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Section(header: Text("Notes (Optional)")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Set Clock Out Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clock Out") {
                        performClockOut()
                    }
                    .disabled(!isValidDuration)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func quickPresetButton(_ title: String, date: Date) -> some View {
        Button(action: {
            let calendar = Calendar.current
            selectedDate = calendar.startOfDay(for: date)
            selectedTime = date
        }) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(15)
        }
    }
    
    private func endOfYesterday() -> Date {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        var components = calendar.dateComponents([.year, .month, .day], from: yesterday)
        components.hour = 23
        components.minute = 59
        return calendar.date(from: components) ?? Date()
    }
    
    private func startOfToday() -> Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
    
    private func performClockOut() {
        let finalDateTime = combinedDateTime
        
        // Validate again before submitting
        if finalDateTime <= clockInTime {
            errorMessage = "Clock out time must be after clock in time"
            showingError = true
            return
        }
        
        if finalDateTime > Date() {
            errorMessage = "Clock out time cannot be in the future"
            showingError = true
            return
        }
        
        let duration = finalDateTime.timeIntervalSince(clockInTime)
        if duration > 24 * 60 * 60 {
            errorMessage = "Shift duration cannot exceed 24 hours"
            showingError = true
            return
        }
        
        // Call the manual clock out function
        timeTrackingService.clockOutManual(
            clockOutDateTime: finalDateTime,
            notes: notes.isEmpty ? nil : notes
        ) { success, error in
            if success {
                dismiss()
                onComplete(finalDateTime, notes.isEmpty ? nil : notes)
            } else {
                errorMessage = error ?? "Failed to clock out"
                showingError = true
            }
        }
    }
}