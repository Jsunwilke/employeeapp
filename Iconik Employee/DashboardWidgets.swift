import SwiftUI
import Firebase

// MARK: - Hours Widget
struct HoursWidget: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    @State private var payPeriodHours: Double = 0
    @State private var weekHours: Double = 0
    @State private var isLoadingHours = false
    @StateObject private var payPeriodService = PayPeriodService.shared
    
    private var elapsedTimeString: String {
        let hours = Int(timeTrackingService.elapsedTime) / 3600
        let minutes = Int(timeTrackingService.elapsedTime) % 3600 / 60
        let seconds = Int(timeTrackingService.elapsedTime) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundColor(.cyan)
                Text("Hours")
                    .font(.headline)
                Spacer()
                
                // Clock in/out button
                Button(action: {
                    if timeTrackingService.isClockIn {
                        clockOut()
                    } else {
                        clockIn()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: timeTrackingService.isClockIn ? "stop.circle.fill" : "play.circle.fill")
                        Text(timeTrackingService.isClockIn ? "Clock Out" : "Clock In")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(timeTrackingService.isClockIn ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Current status
            if timeTrackingService.isClockIn {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Currently Clocked In")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(elapsedTimeString)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                    if let sessionName = timeTrackingService.currentTimeEntry?.sessionName {
                        Text(sessionName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Divider()
            
            // Hours summary
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Pay Period")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if isLoadingHours {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(String(format: "%.1f hrs", payPeriodHours))
                                .font(.system(size: 20, weight: .semibold))
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("This Week")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if isLoadingHours {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(String(format: "%.1f hrs", weekHours))
                                .font(.system(size: 20, weight: .semibold))
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .task {
            // Use task modifier for async operations to avoid publishing warnings
            timeTrackingService.refreshUserAndStatus()
            
            // Give a moment for the service to initialize
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                loadHoursData()
            }
        }
    }
    
    private func clockIn() {
        timeTrackingService.clockIn { success, error in
            if !success {
                print("Failed to clock in: \(error ?? "Unknown error")")
            }
        }
    }
    
    private func clockOut() {
        timeTrackingService.clockOut { success, error in
            if !success {
                print("Failed to clock out: \(error ?? "Unknown error")")
            }
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
            
            // Calculate week start
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            
            // Format dates for queries
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            let payPeriodStartStr = dateFormatter.string(from: payPeriodStart)
            let payPeriodEndStr = dateFormatter.string(from: payPeriodEnd)
            let weekStartStr = dateFormatter.string(from: weekStart)
            let todayStr = dateFormatter.string(from: now)
            
            print("📅 HoursWidget querying pay period: \(payPeriodStartStr) to \(payPeriodEndStr)")
            print("📅 HoursWidget querying week: \(weekStartStr) to \(todayStr)")
            
            // Load pay period hours
            timeTrackingService.getTimeEntries(startDate: payPeriodStartStr, endDate: payPeriodEndStr) { entries in
                let totalHours = entries.reduce(0.0) { total, entry in
                    total + entry.durationInHours
                }
                DispatchQueue.main.async {
                    self.payPeriodHours = totalHours
                }
            }
            
            // Load week hours
            timeTrackingService.getTimeEntries(startDate: weekStartStr, endDate: todayStr) { entries in
                let totalHours = entries.reduce(0.0) { total, entry in
                    total + entry.durationInHours
                }
                DispatchQueue.main.async {
                    self.weekHours = totalHours
                    self.isLoadingHours = false
                }
            }
        }
    }
}

// MARK: - Mileage Widget
struct MileageWidget: View {
    let userName: String
    @StateObject private var mileageViewModel = MileageReportsViewModel(userName: "")
    @State private var isLoading = true
    @State private var hasInitialized = false
    
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
                
                NavigationLink(destination: MileageReportsView(userName: mileageViewModel.userName)) {
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
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .task {
            if !hasInitialized {
                hasInitialized = true
                // Initialize the view model with the correct userName
                mileageViewModel.userName = userName
                await MainActor.run {
                    loadMileageData()
                }
            }
        }
    }
    
    private func loadMileageData() {
        mileageViewModel.loadRecords()
        
        // Give it a moment to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
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