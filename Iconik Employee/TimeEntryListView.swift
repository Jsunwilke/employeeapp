import SwiftUI

struct TimeEntryListView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @State private var timeEntries: [TimeEntry] = []
    @State private var selectedDateRange = DateRange.payPeriod
    @State private var isLoading = false
    @State private var showingManualEntry = false
    @State private var selectedTimeEntry: TimeEntry?
    
    enum DateRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case payPeriod = "Pay Period"
        
        var dateRange: (start: String, end: String) {
            let calendar = Calendar.current
            let now = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            
            switch self {
            case .today:
                let today = formatter.string(from: now)
                return (today, today)
            case .week:
                let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
                let endOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? now
                return (formatter.string(from: startOfWeek), formatter.string(from: endOfWeek))
            case .payPeriod:
                let (payPeriodStart, payPeriodEnd) = calculateCurrentPayPeriod()
                return (formatter.string(from: payPeriodStart), formatter.string(from: payPeriodEnd))
            }
        }
        
        // Calculate current pay period using same logic as mileage system
        private func calculateCurrentPayPeriod() -> (start: Date, end: Date) {
            let calendar = Calendar.current
            
            // Reference date: February 25, 2024 (same as mileage system)
            let payPeriodFormatter = DateFormatter()
            payPeriodFormatter.dateFormat = "M/d/yyyy"
            payPeriodFormatter.locale = Locale(identifier: "en_US_POSIX")
            guard let referenceDate = payPeriodFormatter.date(from: "2/25/2024") else {
                fatalError("Invalid reference date format.")
            }
            
            // Make sure reference date is start of day
            let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
            
            let today = Date()
            let daysSinceReference = calendar.dateComponents([.day], from: referenceStartOfDay, to: today).day ?? 0
            let periodLength = 14
            let periodsElapsed = daysSinceReference / periodLength
            
            guard let currentStart = calendar.date(byAdding: .day, value: periodsElapsed * periodLength, to: referenceStartOfDay) else {
                fatalError("Error calculating current pay period start date.")
            }
            
            // Calculate end date and set it to end of day (23:59:59)
            guard let tempEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: currentStart),
                  let currentEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
                fatalError("Error calculating current pay period end date.")
            }
            
            // Log for debugging and verification with mileage system
            let debugFormatter = DateFormatter()
            debugFormatter.dateStyle = .medium
            print("Time Tracking Pay Period: \(debugFormatter.string(from: currentStart)) to \(debugFormatter.string(from: currentEnd))")
            
            return (start: currentStart, end: currentEnd)
        }
    }
    
    // MARK: - Computed Properties
    
    private var totalHours: Double {
        return timeEntries.reduce(0.0) { total, entry in
            total + entry.durationInHours
        }
    }
    
    private var totalHoursView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Total Hours")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    if selectedDateRange == .payPeriod {
                        Text("(Pay Period)")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                Text(formatTotalHours(totalHours))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("Entries")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text("\(timeEntries.count)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
        )
    }
    
    private func formatTotalHours(_ hours: Double) -> String {
        let wholeHours = Int(hours)
        let minutes = Int((hours - Double(wholeHours)) * 60)
        
        if minutes == 0 {
            return "\(wholeHours)h"
        } else {
            return "\(wholeHours)h \(minutes)m"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Time Entries")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: {
                    showingManualEntry = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                        Text("Add")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }
            
            // Date range picker - more compact
            Picker("Date Range", selection: $selectedDateRange) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .scaleEffect(0.9) // Make segmented control slightly smaller
            
            // Total hours display
            totalHoursView
            
            // Time entries list - expanded to fill available space
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading entries...")
                        .font(.caption)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if timeEntries.isEmpty {
                Text("No time entries for \(selectedDateRange.rawValue.lowercased())")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(timeEntries) { entry in
                            TimeEntryRow(entry: entry)
                                .onTapGesture {
                                    selectedTimeEntry = entry
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Remove the maxHeight constraint to allow it to expand
            }
        }
        .onAppear {
            loadTimeEntries()
        }
        .onChange(of: selectedDateRange) { _ in
            loadTimeEntries()
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualTimeEntryView(timeTrackingService: timeTrackingService)
                .onDisappear {
                    // Refresh the list when manual entry view is dismissed
                    loadTimeEntries()
                }
        }
        .sheet(item: $selectedTimeEntry) { entry in
            EditTimeEntryView(timeEntry: entry, timeTrackingService: timeTrackingService)
                .onDisappear {
                    // Refresh the list when edit view is dismissed
                    loadTimeEntries()
                }
        }
    }
    
    private func loadTimeEntries() {
        isLoading = true
        let dateRange = selectedDateRange.dateRange
        
        timeTrackingService.getTimeEntries(
            startDate: dateRange.start,
            endDate: dateRange.end
        ) { entries in
            DispatchQueue.main.async {
                self.timeEntries = entries
                self.isLoading = false
            }
        }
    }
}

struct TimeEntryRow: View {
    let entry: TimeEntry
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var isEditable: Bool {
        TimeEntryValidator.canEditEntry(entry)
    }
    
    private var isManualEntry: Bool {
        // Manual entries have both clockInTime and clockOutTime and are not active
        entry.clockInTime != nil && entry.clockOutTime != nil && entry.status != "clocked-in"
    }
    
    private var entryTypeIcon: String {
        if entry.status == "clocked-in" {
            return "play.circle.fill"
        } else if isManualEntry {
            return "pencil.circle"
        } else {
            return "clock.circle"
        }
    }
    
    private var entryTypeColor: Color {
        if entry.status == "clocked-in" {
            return .green
        } else if isManualEntry && isEditable {
            return .blue
        } else if isManualEntry {
            return .orange
        } else {
            return .gray
        }
    }
    
    private var backgroundColorForEntry: Color {
        if entry.status == "clocked-in" {
            return Color.green.opacity(0.1)
        } else if isEditable {
            return Color(.systemGray6)
        } else {
            return Color(.systemGray5)
        }
    }
    
    private var borderColorForEntry: Color {
        if entry.status == "clocked-in" {
            return Color.green
        } else if isEditable {
            return Color.blue.opacity(0.3)
        } else {
            return Color.clear
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Header row with date and duration
            HStack {
                Text(formatDate(entry.date))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(entry.formattedDuration)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
            
            // Status and time info - more compact
            HStack {
                // Entry type and status indicator
                Image(systemName: entryTypeIcon)
                    .foregroundColor(entryTypeColor)
                    .font(.caption)
                
                // Time range
                Text(formatTimeRange())
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Status indicators - more compact
                HStack(spacing: 4) {
                    // Active indicator for current entry
                    if entry.status == "clocked-in" {
                        Text("• ACTIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    
                    // Edit status indicator
                    if entry.status != "clocked-in" {
                        if isEditable {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        } else {
                            Image(systemName: "lock")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            
            // Session info if available - only show if not too crowded
            if let sessionId = entry.sessionId {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                        .font(.caption2)
                    Text("Session: \(sessionId)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            // Notes if available - more compact
            if let notes = entry.notes, !notes.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "note.text")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text(notes)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColorForEntry)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColorForEntry, lineWidth: 1)
        )
    }
    
    // MARK: - Helper Functions
    
    private func formatDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        if let date = inputFormatter.date(from: dateString) {
            let calendar = Calendar.current
            if calendar.isDateInToday(date) {
                return "Today"
            } else if calendar.isDateInYesterday(date) {
                return "Yesterday"
            } else {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "MMM d"
                return outputFormatter.string(from: date)
            }
        }
        
        return dateString
    }
    
    private func formatTimeRange() -> String {
        guard let clockIn = entry.clockInTime else { return "" }
        
        if let clockOut = entry.clockOutTime {
            return "\(timeFormatter.string(from: clockIn)) - \(timeFormatter.string(from: clockOut))"
        } else {
            return "\(timeFormatter.string(from: clockIn)) - Present"
        }
    }
}

#Preview {
    VStack {
        TimeEntryListView(timeTrackingService: TimeTrackingService())
        Spacer()
    }
    .padding()
}