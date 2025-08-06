import SwiftUI
import Firebase

// MARK: - Hours Widget
struct HoursWidget: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @State private var regularHours: Double = 0
    @State private var overtimeHours: Double = 0
    @State private var totalHours: Double = 0
    @State private var currentWeekHours: Double = 0
    @State private var isLoadingHours = false
    @StateObject private var payPeriodService = PayPeriodService.shared
    @State private var activeHours: Double = 0
    @State private var timer: Timer?
    
    // Format hours as "XXh XXm"
    private func formatHours(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(h)h \(m)m"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundColor(.yellow)
                    .background(
                        Circle()
                            .fill(Color.yellow.opacity(0.2))
                            .frame(width: 28, height: 28)
                    )
                Text("Hours Tracking")
                    .font(.headline)
                Spacer()
                
                // Clock In/Out Button
                Button(action: {
                    if timeTrackingService.isClockIn {
                        timeTrackingService.clockOut { success, error in
                            if !success {
                                print("Clock out error: \(error ?? "Unknown")")
                            }
                        }
                    } else {
                        timeTrackingService.clockIn { success, error in
                            if !success {
                                print("Clock in error: \(error ?? "Unknown")")
                            }
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: timeTrackingService.isClockIn ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 18))
                        
                        if timeTrackingService.isClockIn {
                            Text(formatHours(activeHours))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .foregroundColor(timeTrackingService.isClockIn ? .red : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(timeTrackingService.isClockIn ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    )
                }
            }
            
            if isLoadingHours {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 30)
            } else {
                VStack(spacing: 20) {
                    // This Week
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This Week:")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        GeometryReader { geometry in
                            HStack(spacing: 12) {
                                // Progress bar with fixed width
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 24)
                                    
                                    // Progress including active hours
                                    let totalWithActive = currentWeekHours + activeHours
                                    let weekProgress = min(currentWeekHours / 40.0, 1.0)
                                    let activeProgress = min(totalWithActive / 40.0, 1.0)
                                    let barWidth = geometry.size.width - 100 // Reserve 100 points for text
                                    
                                    // Logged hours bar
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.blue)
                                        .frame(width: barWidth * CGFloat(weekProgress), height: 24)
                                    
                                    // Active hours overlay (lighter blue)
                                    if activeHours > 0 {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue.opacity(0.4))
                                            .frame(width: barWidth * CGFloat(activeProgress), height: 24)
                                    }
                                }
                                .frame(width: geometry.size.width - 100, height: 24)
                                
                                // Hours and percentage with fixed width
                                VStack(alignment: .trailing, spacing: 0) {
                                    if activeHours > 0 {
                                        Text("\(formatHours(currentWeekHours + activeHours))/40h")
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        Text("Active: \(formatHours(activeHours))")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    } else {
                                        Text("\(formatHours(currentWeekHours))/40h")
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        Text("\(Int((currentWeekHours / 40.0) * 100))%")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(width: 88, alignment: .trailing)
                            }
                        }
                        .frame(height: 24)
                    }
                    
                    // Pay Period
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pay Period:")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        GeometryReader { geometry in
                            HStack(spacing: 12) {
                                // Progress bar with overtime and fixed width
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 24)
                                    
                                    // Regular hours progress
                                    let barWidth = geometry.size.width - 100 // Same as This Week
                                    let regularProgress = min(regularHours / 80.0, 1.0)
                                    let totalWithActive = totalHours + activeHours
                                    let activeProgress = min(totalWithActive / 80.0, 1.0)
                                    
                                    if overtimeHours > 0 {
                                        // Blue segment with square right corners when overtime exists
                                        UnevenRoundedRectangle(
                                            topLeadingRadius: 8,
                                            bottomLeadingRadius: 8,
                                            bottomTrailingRadius: 0,
                                            topTrailingRadius: 0
                                        )
                                        .fill(Color.blue)
                                        .frame(width: barWidth * CGFloat(regularProgress), height: 24)
                                    } else {
                                        // Blue segment with rounded corners when no overtime
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue)
                                            .frame(width: barWidth * CGFloat(regularProgress), height: 24)
                                    }
                                    
                                    // Overtime hours progress (if any)
                                    if overtimeHours > 0 {
                                        let overtimeProgress = overtimeHours / 80.0
                                        let overtimeWidth = barWidth * CGFloat(overtimeProgress)
                                        
                                        UnevenRoundedRectangle(
                                            topLeadingRadius: 0,
                                            bottomLeadingRadius: 0,
                                            bottomTrailingRadius: 8,
                                            topTrailingRadius: 8
                                        )
                                        .fill(Color.orange)
                                        .frame(width: overtimeWidth, height: 24)
                                        .offset(x: barWidth * CGFloat(regularProgress))
                                    }
                                    
                                    // Active hours overlay (lighter blue on top)
                                    if activeHours > 0 {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue.opacity(0.4))
                                            .frame(width: barWidth * CGFloat(activeProgress), height: 24)
                                    }
                                }
                                .frame(width: geometry.size.width - 100, height: 24)
                                
                                // Hours and percentage with fixed width
                                VStack(alignment: .trailing, spacing: 0) {
                                    let totalWithActive = totalHours + activeHours
                                    
                                    // Always show total hours
                                    Text("\(formatHours(totalWithActive))/80h")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    // Show active hours if clocked in
                                    if activeHours > 0 {
                                        Text("Active: \(formatHours(activeHours))")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                            .lineLimit(1)
                                    }
                                    
                                    // Always show overtime if present
                                    if overtimeHours > 0 {
                                        Text("(\(formatHours(overtimeHours)) OT)")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                            .lineLimit(1)
                                    } else if activeHours == 0 {
                                        // Only show percentage if no active hours and no overtime
                                        Text("\(Int((totalHours / 80.0) * 100))%")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(width: 88, alignment: .trailing)
                            }
                        }
                        .frame(height: 24)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .task {
            // Use task modifier for async operations to avoid publishing warnings
            timeTrackingService.refreshUserAndStatus()
            
            // Give a moment for the service to initialize
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                loadHoursData()
                startActiveHoursTimer()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func startActiveHoursTimer() {
        timer?.invalidate()
        updateActiveHours()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateActiveHours()
        }
    }
    
    private func updateActiveHours() {
        if timeTrackingService.isClockIn,
           let activeEntry = timeTrackingService.currentTimeEntry {
            // currentTimeEntry doesn't have startTime directly, use elapsedTime instead
            activeHours = timeTrackingService.elapsedTime / 3600.0 // Convert to hours
        } else {
            activeHours = 0
        }
    }
    
    private func loadHoursData() {
        isLoadingHours = true
        
        // Ensure TimeTrackingService has user/org IDs
        timeTrackingService.refreshUserAndStatus()
        
        // First load pay period settings if not already loaded
        payPeriodService.loadPayPeriodSettings { success in
            let calendar = Calendar.current
            let now = Date()
            
            // Get pay period from service
            guard let (payPeriodStart, payPeriodEnd) = payPeriodService.getCurrentPayPeriod() else {
                print("Error getting pay period from service")
                isLoadingHours = false
                return
            }
            
            // Format dates for queries
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            let payPeriodStartStr = dateFormatter.string(from: payPeriodStart)
            let payPeriodEndStr = dateFormatter.string(from: payPeriodEnd)
            
            print("📅 HoursWidget querying pay period: \(payPeriodStartStr) to \(payPeriodEndStr)")
            
            // Load all pay period entries
            timeTrackingService.getTimeEntries(startDate: payPeriodStartStr, endDate: payPeriodEndStr) { entries in
                // Calculate overtime breakdown
                let breakdown = self.calculateOvertimeBreakdown(entries: entries, payPeriodStart: payPeriodStart)
                
                DispatchQueue.main.async {
                    self.regularHours = breakdown.regular
                    self.overtimeHours = breakdown.overtime
                    self.totalHours = breakdown.total
                    self.currentWeekHours = breakdown.currentWeek
                    self.isLoadingHours = false
                }
            }
        }
    }
    
    private func calculateOvertimeBreakdown(entries: [TimeEntry], payPeriodStart: Date) -> (regular: Double, overtime: Double, total: Double, currentWeek: Double) {
        let calendar = Calendar.current
        let now = Date()
        
        // Group entries by week
        var weeklyHours: [Date: Double] = [:]
        var currentWeekTotal: Double = 0
        
        for entry in entries {
            // Parse entry date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            guard let entryDate = dateFormatter.date(from: entry.date) else { continue }
            
            // Find the start of the week for this entry
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: entryDate)?.start else { continue }
            
            // Add hours to the appropriate week
            weeklyHours[weekStart, default: 0] += entry.durationInHours
            
            // Check if this entry is in the current week
            if calendar.isDate(entryDate, equalTo: now, toGranularity: .weekOfYear) {
                currentWeekTotal += entry.durationInHours
            }
        }
        
        // Calculate regular and overtime hours
        var totalRegular: Double = 0
        var totalOvertime: Double = 0
        
        for (_, hours) in weeklyHours {
            if hours > 40 {
                totalRegular += 40
                totalOvertime += hours - 40
            } else {
                totalRegular += hours
            }
        }
        
        let total = totalRegular + totalOvertime
        
        return (regular: totalRegular, overtime: totalOvertime, total: total, currentWeek: currentWeekTotal)
    }
}

// MARK: - Mileage Widget
struct MileageWidget: View {
    let userName: String
    @State private var isLoading = true
    @StateObject private var mileageViewModel: MileageReportsViewModel
    
    init(userName: String) {
        self.userName = userName
        self._mileageViewModel = StateObject(wrappedValue: MileageReportsViewModel(userName: userName))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Mileage")
                    .font(.headline)
                Spacer()
                
                NavigationLink(destination: MileageReportsView(userName: userName)) {
                    HStack(spacing: 4) {
                        Text("View All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                // Mileage stats
                VStack(spacing: 12) {
                    // Pay Period
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pay Period")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(mileageViewModel.currentPeriodMileage)) mi")
                                .font(.system(size: 24, weight: .semibold))
                        }
                        Spacer()
                    }
                    
                    Divider()
                    
                    // Month and Year
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This Month")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(mileageViewModel.monthMileage)) mi")
                                .font(.system(size: 18, weight: .medium))
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("This Year")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(mileageViewModel.yearMileage)) mi")
                                .font(.system(size: 18, weight: .medium))
                        }
                    }
                }
                
                // Info text
                Text("Enter mileage via Daily Job Reports")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .task {
            await MainActor.run {
                loadMileageData()
            }
        }
    }
    
    private func loadMileageData() {
        print("📊 MileageWidget: Starting to load mileage data for user: \(userName)")
        mileageViewModel.loadRecords()
        
        // Give it a moment to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("📊 MileageWidget: Loaded - Pay Period: \(mileageViewModel.currentPeriodMileage) mi, Month: \(mileageViewModel.monthMileage) mi, Year: \(mileageViewModel.yearMileage) mi")
            isLoading = false
        }
    }
}

// MARK: - Upcoming Shifts Widget
struct UpcomingShiftsWidget: View {
    let sessions: [Session]
    let isLoading: Bool
    let weatherDataBySession: [String: WeatherData]
    let onRefresh: () -> Void
    let onSessionTap: (Session) -> Void
    
    private var currentUserID: String? {
        UserManager.shared.getCurrentUserID()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundColor(.red)
                Text("Upcoming Shifts")
                    .font(.headline)
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No upcoming shifts")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Next 2 days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(sessions.prefix(3)) { session in
                        Button(action: { onSessionTap(session) }) {
                            CompactShiftRow(
                                session: session,
                                weatherData: getWeatherForSession(session),
                                currentUserID: currentUserID
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if sessions.count > 3 {
                        NavigationLink(destination: SlingWeeklyView()) {
                            HStack {
                                Spacer()
                                Text("View All (\(sessions.count) shifts)")
                                    .font(.caption)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                Spacer()
                            }
                            .foregroundColor(.blue)
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    private func getWeatherForSession(_ session: Session) -> WeatherData? {
        guard let sessionDate = session.startDate,
              let location = session.location,
              !location.isEmpty else {
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: sessionDate)
        let cacheKey = "\(location)-\(dateString)"
        
        return weatherDataBySession[cacheKey]
    }
}

// MARK: - Compact Shift Row
struct CompactShiftRow: View {
    let session: Session
    let weatherData: WeatherData?
    let currentUserID: String?
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
        return formatter
    }
    
    private var currentUserPhotographerInfo: (name: String, notes: String)? {
        guard let userID = currentUserID else { return nil }
        return session.getPhotographerInfo(for: userID)
    }
    
    private var colorForPosition: Color {
        if let positionColor = positionColorMap[session.position] {
            return positionColor
        }
        
        let colorMap: [String: Color] = [
            "Photographer 1": .red,
            "Photographer 2": .blue,
            "Photographer 3": .green,
            "Photographer 4": .orange,
            "Photographer 5": .purple,
            "Poser 1": .pink,
            "Poser 2": .teal,
            "Production": .mint,
            "Delivery": .gray
        ]
        
        return colorMap[session.position] ?? .blue
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(colorForPosition)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                // School name and position
                HStack {
                    Text(session.schoolName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(session.position)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(colorForPosition.opacity(0.2))
                        .foregroundColor(colorForPosition)
                        .cornerRadius(10)
                }
                
                // Date and time
                HStack {
                    if let start = session.startDate {
                        Text(dateFormatter.string(from: start))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let end = session.endDate {
                            Text("• \(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Weather
                    if let weather = weatherData, let iconName = weather.iconSystemName {
                        HStack(spacing: 2) {
                            Image(systemName: iconName)
                                .font(.caption)
                                .foregroundColor(weather.conditionColor)
                            Text(weather.temperatureString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}