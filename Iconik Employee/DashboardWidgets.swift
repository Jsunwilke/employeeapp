import SwiftUI
import Firebase
import FirebaseFirestore

// MARK: - Hours Widget
struct HoursWidget: View {
    @ObservedObject var timeTrackingService: TimeTrackingService
    
    // Initialize with cached values for instant display (will be validated when settings load)
    @State private var regularHours: Double = UserDefaults.standard.double(forKey: "cached_regularHours")
    @State private var overtimeHours: Double = UserDefaults.standard.double(forKey: "cached_overtimeHours")
    @State private var totalHours: Double = UserDefaults.standard.double(forKey: "cached_totalHours")
    @State private var currentWeekHours: Double = UserDefaults.standard.double(forKey: "cached_currentWeekHours")
    @State private var isLoadingHours = false
    @State private var hasInitialData = false
    @StateObject private var payPeriodService = PayPeriodService.shared
    @State private var activeHours: Double = 0
    @State private var timer: Timer?
    @State private var listenerSetUp = false // Prevent duplicate listeners
    @State private var currentListenerPeriodStart: Date? // Track what period the listener is using
    
    // Sheet presentation states
    @State private var showingSessionSelection = false
    @State private var showingNotesInput = false
    
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
                        // Show notes input for clock out
                        showingNotesInput = true
                    } else {
                        // Show session selection for clock in
                        showingSessionSelection = true
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
                                    let barWidth = geometry.size.width - 100 // Reserve 100 points for text
                                    
                                    if totalWithActive <= 40 {
                                        // Under 40h: Show actual progress
                                        let progress = totalWithActive / 40.0
                                        
                                        // Logged hours bar
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue)
                                            .frame(width: barWidth * CGFloat(currentWeekHours / 40.0), height: 24)
                                        
                                        // Active hours overlay (lighter blue)
                                        if activeHours > 0 {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.blue.opacity(0.4))
                                                .frame(width: barWidth * CGFloat(progress), height: 24)
                                        }
                                    } else {
                                        // Over 40h: Full bar with proportional segments
                                        let regularHours = min(currentWeekHours, 40.0)
                                        let overtimeHours = max(currentWeekHours - 40.0, 0)
                                        let totalHours = regularHours + overtimeHours
                                        let regularRatio = regularHours / totalHours
                                        
                                        // Blue segment (regular hours proportion)
                                        UnevenRoundedRectangle(
                                            topLeadingRadius: 8,
                                            bottomLeadingRadius: 8,
                                            bottomTrailingRadius: 0,
                                            topTrailingRadius: 0
                                        )
                                        .fill(Color.blue)
                                        .frame(width: barWidth * CGFloat(regularRatio), height: 24)
                                        
                                        // Orange segment (overtime proportion)
                                        if overtimeHours > 0 {
                                            UnevenRoundedRectangle(
                                                topLeadingRadius: 0,
                                                bottomLeadingRadius: 0,
                                                bottomTrailingRadius: 8,
                                                topTrailingRadius: 8
                                            )
                                            .fill(Color.orange)
                                            .frame(width: barWidth * CGFloat(1.0 - regularRatio), height: 24)
                                            .offset(x: barWidth * CGFloat(regularRatio))
                                        }
                                        
                                        // Active hours overlay on top
                                        if activeHours > 0 {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.white.opacity(0.3))
                                                .frame(width: barWidth, height: 24)
                                        }
                                    }
                                }
                                .frame(width: geometry.size.width - 100, height: 24)
                                
                                // Hours and percentage with fixed width
                                VStack(alignment: .trailing, spacing: 0) {
                                    let totalWithActive = currentWeekHours + activeHours
                                    if totalWithActive > 40 {
                                        // Show total with overtime indicator
                                        Text("\(formatHours(totalWithActive))/40h")
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        let overtime = totalWithActive - 40
                                        Text("+\(formatHours(overtime)) OT")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    } else if activeHours > 0 {
                                        Text("\(formatHours(totalWithActive))/40h")
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
                                    
                                    let barWidth = geometry.size.width - 100 // Same as This Week
                                    let totalWithActive = totalHours + activeHours
                                    
                                    if totalWithActive <= 80 {
                                        // Under 80h: Show actual progress
                                        let progress = totalWithActive / 80.0
                                        
                                        // Just blue bar for regular hours
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue)
                                            .frame(width: barWidth * CGFloat(totalHours / 80.0), height: 24)
                                        
                                        // Active hours overlay
                                        if activeHours > 0 {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.blue.opacity(0.4))
                                                .frame(width: barWidth * CGFloat(progress), height: 24)
                                        }
                                    } else {
                                        // Over 80h: Full bar with proportional segments
                                        let totalForRatio = totalHours // Use only logged hours for ratio
                                        let regularRatio = regularHours / totalForRatio
                                        let overtimeRatio = overtimeHours / totalForRatio
                                        
                                        // Blue segment (regular hours proportion)
                                        UnevenRoundedRectangle(
                                            topLeadingRadius: 8,
                                            bottomLeadingRadius: 8,
                                            bottomTrailingRadius: overtimeHours > 0 ? 0 : 8,
                                            topTrailingRadius: overtimeHours > 0 ? 0 : 8
                                        )
                                        .fill(Color.blue)
                                        .frame(width: barWidth * CGFloat(regularRatio), height: 24)
                                        
                                        // Orange segment (overtime proportion)
                                        if overtimeHours > 0 {
                                            UnevenRoundedRectangle(
                                                topLeadingRadius: 0,
                                                bottomLeadingRadius: 0,
                                                bottomTrailingRadius: 8,
                                                topTrailingRadius: 8
                                            )
                                            .fill(Color.orange)
                                            .frame(width: barWidth * CGFloat(overtimeRatio), height: 24)
                                            .offset(x: barWidth * CGFloat(regularRatio))
                                        }
                                        
                                        // Active hours overlay on top
                                        if activeHours > 0 {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.white.opacity(0.3))
                                                .frame(width: barWidth, height: 24)
                                        }
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
            // Load data immediately without delay
            timeTrackingService.refreshUserAndStatus()
            
            await MainActor.run {
                loadHoursData()
                startActiveHoursTimer()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            // Keep listener active for instant data when returning
            // timeTrackingService.stopListeningForDashboardEntries()
        }
        .sheet(isPresented: $showingSessionSelection) {
            SessionSelectionView(
                timeTrackingService: timeTrackingService,
                onClockIn: { sessionId, notes in
                    // Clock in with selected session
                    timeTrackingService.clockIn(sessionId: sessionId, notes: notes) { success, error in
                        if success {
                            showingSessionSelection = false
                        } else {
                            print("Clock in error: \(error ?? "Unknown")")
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showingNotesInput) {
            NotesInputView(
                isClockOut: true,
                onComplete: { notes in
                    // Clock out with optional notes
                    timeTrackingService.clockOut(notes: notes) { success, error in
                        if success {
                            showingNotesInput = false
                        } else {
                            print("Clock out error: \(error ?? "Unknown")")
                        }
                    }
                }
            )
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
        // Only show loading if we have no cached data
        if regularHours == 0 && totalHours == 0 {
            isLoadingHours = true
        }
        
        // Ensure TimeTrackingService has user/org IDs
        timeTrackingService.refreshUserAndStatus()
        
        // Load pay period settings FIRST, then set up listener
        payPeriodService.loadPayPeriodSettings { success in
            print("📅 HoursWidget: Pay period settings loaded, success: \(success)")
            
            // Now that settings are loaded, check if we need to clear cache
            self.checkAndClearCacheIfNewPeriod()
            
            // Set up the listener with the correct pay period
            if !self.listenerSetUp {
                self.listenerSetUp = true
                self.setupHoursListener()
            } else {
                print("📅 HoursWidget: Listener already set up, skipping duplicate setup")
            }
        }
        
        // Fallback: If settings take too long, set up with defaults after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !self.listenerSetUp {
                print("⚠️ HoursWidget: Settings load timeout, using defaults")
                self.checkAndClearCacheIfNewPeriod()
                self.listenerSetUp = true
                self.setupHoursListener()
            }
        }
    }
    
    private func checkAndClearCacheIfNewPeriod() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let now = Date()
        
        // Get the last cached period start date
        let lastCachedPeriodStart = UserDefaults.standard.object(forKey: "cached_period_start") as? Date
        
        // Get current pay period
        let currentPeriod = payPeriodService.getCurrentPayPeriod() ?? getDefaultPayPeriod()
        
        // Check if we're in a different pay period than cached
        let shouldClearCache = lastCachedPeriodStart == nil || 
            !calendar.isDate(lastCachedPeriodStart!, equalTo: currentPeriod.0, toGranularity: .day)
        
        if shouldClearCache {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            dateFormatter.timeZone = TimeZone.current
            
            print("📅 Pay period change detected, clearing cached hours")
            print("   Last period start: \(lastCachedPeriodStart != nil ? dateFormatter.string(from: lastCachedPeriodStart!) : "none")")
            print("   Current period: \(dateFormatter.string(from: currentPeriod.0)) to \(dateFormatter.string(from: currentPeriod.1))")
            print("   Current date: \(dateFormatter.string(from: now))")
            
            // Clear all cached values
            UserDefaults.standard.set(0.0, forKey: "cached_regularHours")
            UserDefaults.standard.set(0.0, forKey: "cached_overtimeHours")
            UserDefaults.standard.set(0.0, forKey: "cached_totalHours")
            UserDefaults.standard.set(0.0, forKey: "cached_currentWeekHours")
            
            // Reset state values to force reload
            regularHours = 0
            overtimeHours = 0
            totalHours = 0
            currentWeekHours = 0
            
            // Store the new period start date
            UserDefaults.standard.set(currentPeriod.0, forKey: "cached_period_start")
            UserDefaults.standard.synchronize() // Force immediate write
        }
    }
    
    private func setupHoursListener() {
        // Refresh again in case orgId was just fetched
        timeTrackingService.refreshUserAndStatus()
        
        // Try to get pay period immediately if available, otherwise use default
        let (payPeriodStart, payPeriodEnd) = payPeriodService.getCurrentPayPeriod() ?? getDefaultPayPeriod()
        
        // Check if we need to restart the listener with new dates
        if let existingStart = currentListenerPeriodStart {
            let calendar = Calendar.current
            if !calendar.isDate(existingStart, equalTo: payPeriodStart, toGranularity: .day) {
                print("📅 HoursWidget: Period changed! Restarting listener...")
                print("   Old period start: \(existingStart)")
                print("   New period start: \(payPeriodStart)")
                timeTrackingService.stopListeningForDashboardEntries()
                
                // Clear the cached values since we're in a new period
                regularHours = 0
                overtimeHours = 0
                totalHours = 0
                currentWeekHours = 0
            }
        }
        
        currentListenerPeriodStart = payPeriodStart
        
        // Format dates for queries
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        
        let payPeriodStartStr = dateFormatter.string(from: payPeriodStart)
        let payPeriodEndStr = dateFormatter.string(from: payPeriodEnd)
        
        print("📅 HoursWidget setting up listener for pay period: \(payPeriodStartStr) to \(payPeriodEndStr)")
        
        // Set up real-time listener immediately
        timeTrackingService.listenForTimeEntries(startDate: payPeriodStartStr, endDate: payPeriodEndStr) { entries in
            // Calculate overtime breakdown
            let breakdown = self.calculateOvertimeBreakdown(entries: entries, payPeriodStart: payPeriodStart)
            
            DispatchQueue.main.async {
                self.regularHours = breakdown.regular
                self.overtimeHours = breakdown.overtime
                self.totalHours = breakdown.total
                self.currentWeekHours = breakdown.currentWeek
                
                // Cache values for instant display next time
                UserDefaults.standard.set(breakdown.regular, forKey: "cached_regularHours")
                UserDefaults.standard.set(breakdown.overtime, forKey: "cached_overtimeHours")
                UserDefaults.standard.set(breakdown.total, forKey: "cached_totalHours")
                UserDefaults.standard.set(breakdown.currentWeek, forKey: "cached_currentWeekHours")
                
                // Also save the current period start so we can validate cache later
                if let periodStart = self.currentListenerPeriodStart {
                    UserDefaults.standard.set(periodStart, forKey: "cached_period_start")
                }
                UserDefaults.standard.synchronize() // Force immediate write
                
                // Only set loading to false on first load
                if self.isLoadingHours {
                    self.isLoadingHours = false
                }
                
                self.hasInitialData = true
            }
        }
    }
    
    private func getDefaultPayPeriod() -> (Date, Date) {
        // Use the same default calculation as PayPeriodService
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        // Reference date: 2/25/2024 (Sunday - start of a pay period)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yyyy"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let referenceDate = dateFormatter.date(from: "2/25/2024") else {
            print("❌ HoursWidget: Failed to parse reference date, using fallback")
            let now = Date()
            let twoWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -2, to: now) ?? now
            return (twoWeeksAgo, now)
        }
        
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)
        let targetStartOfDay = calendar.startOfDay(for: Date())
        
        // Calculate days between dates
        let components = calendar.dateComponents([.day], from: referenceStartOfDay, to: targetStartOfDay)
        let daysSinceReference = components.day ?? 0
        
        let periodLength = 14
        
        // Calculate complete periods elapsed
        let periodsElapsed = daysSinceReference >= 0 ? 
            daysSinceReference / periodLength : 
            ((daysSinceReference - periodLength + 1) / periodLength)
        
        // Calculate the start of the current period
        guard let periodStart = calendar.date(byAdding: .day, value: periodsElapsed * periodLength, to: referenceStartOfDay) else {
            print("❌ HoursWidget: Failed to calculate period start")
            let now = Date()
            let twoWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -2, to: now) ?? now
            return (twoWeeksAgo, now)
        }
        
        // Calculate the end of the period (13 days later, end of day)
        guard let tempEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: periodStart),
              let periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: tempEnd) else {
            print("❌ HoursWidget: Failed to calculate period end")
            return (periodStart, Date())
        }
        
        print("📅 HoursWidget Default Pay Period:")
        print("   Reference: 2/25/2024 (Sunday)")
        print("   Target: \(dateFormatter.string(from: Date()))")
        print("   Days since reference: \(daysSinceReference)")
        print("   Periods elapsed: \(periodsElapsed)")
        print("   Period: \(dateFormatter.string(from: periodStart)) to \(dateFormatter.string(from: periodEnd))")
        
        return (periodStart, periodEnd)
    }
    
    private func calculateOvertimeBreakdown(entries: [TimeEntry], payPeriodStart: Date) -> (regular: Double, overtime: Double, total: Double, currentWeek: Double) {
        let calendar = Calendar.current
        let now = Date()
        
        // Calculate which week of the pay period we're currently in
        let daysSincePeriodStart = calendar.dateComponents([.day], from: calendar.startOfDay(for: payPeriodStart), to: calendar.startOfDay(for: now)).day ?? 0
        let currentWeekOfPeriod = (daysSincePeriodStart / 7) + 1 // 1 for first week, 2 for second week
        
        print("📅 Current week calculation: Days since period start: \(daysSincePeriodStart), Current week: \(currentWeekOfPeriod)")
        
        // Group entries by week within the pay period
        var weeklyHours: [Int: Double] = [:] // Week number -> hours
        var currentWeekTotal: Double = 0
        
        for entry in entries {
            // Parse entry date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            guard let entryDate = dateFormatter.date(from: entry.date) else { continue }
            
            // Calculate which week of the pay period this entry belongs to
            let entryDaysSincePeriodStart = calendar.dateComponents([.day], from: calendar.startOfDay(for: payPeriodStart), to: calendar.startOfDay(for: entryDate)).day ?? 0
            let entryWeekOfPeriod = (entryDaysSincePeriodStart / 7) + 1
            
            // Add hours to the appropriate week
            weeklyHours[entryWeekOfPeriod, default: 0] += entry.durationInHours
            
            // Check if this entry is in the current week of the pay period
            if entryWeekOfPeriod == currentWeekOfPeriod {
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
    // Initialize with cached values for instant display
    @State private var currentPeriodMileage: Double = UserDefaults.standard.double(forKey: "cached_currentPeriodMileage")
    @State private var monthMileage: Double = UserDefaults.standard.double(forKey: "cached_monthMileage")
    @State private var yearMileage: Double = UserDefaults.standard.double(forKey: "cached_yearMileage")
    @State private var isLoading = false
    @State private var hasInitialData = false
    @StateObject private var mileageViewModel: MileageReportsViewModel
    @State private var mileageRate: Double = 0.30 // Default rate
    
    private let db = Firestore.firestore()
    
    init(userName: String) {
        self.userName = userName
        self._mileageViewModel = StateObject(wrappedValue: MileageReportsViewModel.shared)
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pay Period")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(currentPeriodMileage)) mi")
                                .font(.system(size: 24, weight: .semibold))
                            Text("$\(currentPeriodMileage * mileageRate, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        Spacer()
                    }
                    
                    Divider()
                    
                    // Month and Year
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("This Month")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(monthMileage)) mi")
                                .font(.system(size: 18, weight: .medium))
                            Text("$\(monthMileage * mileageRate, specifier: "%.2f")")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("This Year")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(yearMileage)) mi")
                                .font(.system(size: 18, weight: .medium))
                            Text("$\(yearMileage * mileageRate, specifier: "%.2f")")
                                .font(.caption2)
                                .foregroundColor(.green)
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
        // Only show loading if we have no cached data
        if currentPeriodMileage == 0 && monthMileage == 0 && yearMileage == 0 {
            isLoading = true
        }
        
        print("📊 MileageWidget: Setting up mileage listener for user: \(userName)")
        
        // Fetch user's mileage rate from Firebase
        fetchUserMileageRate()
        
        // Listen for changes to the view model
        mileageViewModel.listenForMileageUpdates {
            DispatchQueue.main.async {
                self.currentPeriodMileage = self.mileageViewModel.currentPeriodMileage
                self.monthMileage = self.mileageViewModel.monthMileage
                self.yearMileage = self.mileageViewModel.yearMileage
                
                // Cache values for instant display next time
                UserDefaults.standard.set(self.currentPeriodMileage, forKey: "cached_currentPeriodMileage")
                UserDefaults.standard.set(self.monthMileage, forKey: "cached_monthMileage")
                UserDefaults.standard.set(self.yearMileage, forKey: "cached_yearMileage")
                
                print("📊 MileageWidget: Updated - Pay Period: \(self.currentPeriodMileage) mi, Month: \(self.monthMileage) mi, Year: \(self.yearMileage) mi")
                
                if self.isLoading {
                    self.isLoading = false
                }
                self.hasInitialData = true
            }
        }
        
        // Trigger initial load
        mileageViewModel.loadRecords()
    }
    
    private func fetchUserMileageRate() {
        // Get current user ID
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ MileageWidget: No authenticated user")
            return
        }
        
        // Fetch amountPerMile from users collection
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                print("❌ MileageWidget: Error fetching user profile: \(error)")
                return
            }
            
            guard let data = snapshot?.data() else {
                print("⚠️ MileageWidget: No user data found")
                return
            }
            
            // Get amountPerMile field, default to 0.30 if not set
            let rate = data["amountPerMile"] as? Double ?? 0.30
            
            DispatchQueue.main.async {
                self.mileageRate = rate
                print("💰 MileageWidget: Mileage rate set to $\(rate) per mile")
            }
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
                    
                    Text(session.getSessionTypeDisplayName())
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

// MARK: - iPad Widgets

struct SportsRostersWidget: View {
    @State private var todaysSportsShoots: [SportsShoot] = []
    @State private var isLoading = true
    @ObservedObject var tabBarManager: TabBarManager
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }
    
    // Break down complex view into computed properties
    private var headerView: some View {
        HStack {
            Image(systemName: "sportscourt")
                .font(.title2)
                .foregroundColor(.orange)
            Text("Sports Rosters")
                .font(.headline)
            Spacer()
            
            Button(action: {
                // Navigate to sports shoots feature
                tabBarManager.selectedTab = "sportsShoot"
            }) {
                HStack(spacing: 4) {
                    Text("View All")
                    Image(systemName: "chevron.right")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
    }
    
    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 40)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sportscourt")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text("No sports rosters today")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
    
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(todaysSportsShoots.prefix(3)) { shoot in
                shootRowView(for: shoot)
            }
            
            if todaysSportsShoots.count > 3 {
                HStack {
                    Spacer()
                    Text("\(todaysSportsShoots.count - 3) more rosters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
    
    private func shootRowView(for shoot: SportsShoot) -> some View {
        Button(action: {
            // Set selected shoot and navigate to sports shoots feature
            TabBarManager.shared.selectedSportsShoot = shoot
            tabBarManager.selectedTab = "sportsShoot"
        }) {
            HStack {
                // Sports icon
                Image(systemName: getSportsIcon(for: shoot.sportName))
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(shoot.schoolName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        // Sport name
                        Text(shoot.sportName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Time
                        Text("• \(dateFormatter.string(from: shoot.shootDate))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Roster count
                Group {
                    if shoot.roster.count > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.3.fill")
                                .font(.caption2)
                            Text("\(shoot.roster.count)")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    } else {
                        Text("No roster")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            
            if isLoading {
                loadingView
            } else if todaysSportsShoots.isEmpty {
                emptyStateView
            } else {
                contentView
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
        .onAppear {
            loadSportsRosters()
        }
    }
    
    private func loadSportsRosters() {
        guard !storedUserOrganizationID.isEmpty else {
            print("No organization ID found for sports rosters widget")
            self.isLoading = false
            return
        }
        
        isLoading = true
        
        // Fetch all sports shoots for the organization
        SportsShootService.shared.fetchAllSportsShoots(forOrganization: storedUserOrganizationID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let shoots):
                    // Filter for today's shoots
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
                    
                    self.todaysSportsShoots = shoots.filter { shoot in
                        let shootDay = calendar.startOfDay(for: shoot.shootDate)
                        // Filter out archived shoots and only show today's shoots
                        return !shoot.isArchived && shootDay >= today && shootDay < tomorrow
                    }.sorted { $0.shootDate < $1.shootDate }
                    
                    print("Loaded \(self.todaysSportsShoots.count) sports shoots for today")
                    
                case .failure(let error):
                    print("Error loading sports shoots: \(error.localizedDescription)")
                    self.todaysSportsShoots = []
                }
                
                self.isLoading = false
            }
        }
    }
    
    private func getSportsIcon(for sportName: String) -> String {
        let sessionTypeString = sportName.lowercased()
        
        if sessionTypeString.contains("basketball") {
            return "basketball"
        } else if sessionTypeString.contains("football") {
            return "football"
        } else if sessionTypeString.contains("soccer") {
            return "soccerball"
        } else if sessionTypeString.contains("baseball") || sessionTypeString.contains("softball") {
            return "baseball"
        } else if sessionTypeString.contains("tennis") {
            return "tennis.racket"
        } else if sessionTypeString.contains("golf") {
            return "flag"
        } else if sessionTypeString.contains("swim") {
            return "drop"
        } else if sessionTypeString.contains("track") || sessionTypeString.contains("cross country") {
            return "figure.run"
        } else if sessionTypeString.contains("volleyball") {
            return "volleyball"
        } else {
            return "sportscourt"
        }
    }
}

struct ClassGroupsWidget: View {
    @StateObject private var service = ClassGroupJobService.shared
    @State private var organizationId: String?
    @State private var todaysJobs: [ClassGroupJob] = []
    @State private var isLoading = true
    @State private var showingCreateJob = false
    @ObservedObject var tabBarManager: TabBarManager
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                Text("Class Group Jobs")
                    .font(.headline)
                Spacer()
                
                Button(action: {
                    showingCreateJob = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Jobs")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple)
                    .cornerRadius(15)
                }
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if todaysJobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No class group jobs today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showingCreateJob = true
                    }) {
                        Text("Add Class Group Jobs")
                            .font(.caption)
                            .foregroundColor(.purple)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(20)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(todaysJobs.prefix(3)) { job in
                        Button(action: {
                            // Set selected job and navigate to class groups feature
                            tabBarManager.selectedClassGroupJobId = job.id
                            tabBarManager.selectedTab = "classGroups"
                        }) {
                            VStack(alignment: .leading, spacing: 6) {
                                // School name and time
                                HStack {
                                    Text(job.schoolName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(dateFormatter.string(from: job.sessionDate))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                // Group count and type
                                HStack {
                                    if job.classGroupCount > 0 {
                                        Label("\(job.classGroupCount) group\(job.classGroupCount == 1 ? "" : "s")", 
                                              systemImage: "person.3")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    } else {
                                        Text("No groups added")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    
                                    Spacer()
                                    
                                    if job.totalImageCount > 0 {
                                        Label("\(job.totalImageCount)", systemImage: "photo")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                    
                                    // Job type badge
                                    Text(job.jobType == "classGroups" ? "Groups" : "Candids")
                                        .font(.caption)
                                        .foregroundColor(.purple)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.purple.opacity(0.1))
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if todaysJobs.count > 3 {
                        Button(action: {
                            // Navigate to class groups feature to view all
                            tabBarManager.selectedClassGroupJobId = nil
                            tabBarManager.selectedTab = "classGroups"
                        }) {
                            HStack {
                                Spacer()
                                Text("View All (\(todaysJobs.count) jobs)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Spacer()
                            }
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
        .onAppear {
            loadClassGroupJobs()
        }
        .sheet(isPresented: $showingCreateJob) {
            CreateClassGroupJobView(initialJobType: "classGroups") { _ in
                // Refresh jobs after creation
                loadClassGroupJobs()
            }
        }
    }
    
    private func loadClassGroupJobs() {
        isLoading = true
        
        UserManager.shared.getCurrentUserOrganizationID { orgId in
            guard let organizationId = orgId else {
                print("Failed to get organization ID")
                self.isLoading = false
                return
            }
            
            self.organizationId = organizationId
            
            // Fetch all jobs for the organization
            service.fetchAllClassGroupJobs(forOrganization: organizationId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let jobs):
                        // Filter for today's jobs
                        let calendar = Calendar.current
                        let today = calendar.startOfDay(for: Date())
                        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
                        
                        self.todaysJobs = jobs.filter { job in
                            job.sessionDate >= today && job.sessionDate < tomorrow
                        }.sorted { $0.sessionDate < $1.sessionDate }
                        
                    case .failure(let error):
                        print("Error loading class group jobs: \(error)")
                        self.todaysJobs = []
                    }
                    
                    self.isLoading = false
                }
            }
        }
    }
}

struct PhotoshootNotesWidget: View {
    // Access the same storage as PhotoshootNotesView
    @AppStorage("photoshootNotes") private var storedNotesData: Data = Data()
    @State private var notes: [PhotoshootNote] = []
    @State private var selectedNote: PhotoshootNote? = nil
    @State private var schoolOptions: [SchoolItem] = []
    @State private var todaySessions: [Session] = []
    @State private var isLoading = false
    @State private var showingFullView = false
    
    private let sessionService = SessionService.shared
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
    
    private var todayDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "note.text")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Photoshoot Notes")
                    .font(.headline)
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: createNewNote) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        showingFullView = true
                    }) {
                        Image(systemName: "arrow.up.forward.circle")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // Notes list or empty state
            if notes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No notes created yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: createNewNote) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Add Note")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(20)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                // Horizontal scrollable list of notes
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(notes.sorted(by: { $0.timestamp > $1.timestamp }).prefix(5)) { note in
                            Button(action: {
                                selectedNote = note
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(dateFormatter.string(from: note.timestamp))
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                        if note.photoURLs.count > 0 {
                                            Image(systemName: "photo")
                                                .font(.caption2)
                                            Text("\(note.photoURLs.count)")
                                                .font(.caption2)
                                        }
                                    }
                                    .foregroundColor(.blue)
                                    
                                    Text(note.school.isEmpty ? "No school" : note.school)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    Text(note.noteText.isEmpty ? "(No content)" : note.noteText)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(8)
                                .frame(width: 120, height: 70)
                                .background(selectedNote?.id == note.id ? Color.blue.opacity(0.1) : Color(.systemGray6))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedNote?.id == note.id ? Color.blue : Color.clear, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .frame(height: 75)
            }
            
            // Selected note editor
            if let note = selectedNote {
                VStack(alignment: .leading, spacing: 8) {
                    // School selector
                    if schoolOptions.isEmpty {
                        HStack {
                            Text("Loading schools...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                    } else {
                        HStack {
                            Text("School:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: Binding(
                                get: {
                                    schoolOptions.first(where: { $0.name == note.school }) ?? schoolOptions.first!
                                },
                                set: { newSchool in
                                    if let index = notes.firstIndex(where: { $0.id == note.id }) {
                                        notes[index].school = newSchool.name
                                        selectedNote = notes[index]
                                        saveNotes()
                                    }
                                }
                            )) {
                                ForEach(schoolOptions, id: \.id) { school in
                                    Text(school.name).tag(school)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .font(.caption)
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                    }
                    
                    // Note content editor
                    VStack(alignment: .trailing, spacing: 4) {
                        TextEditor(text: Binding(
                            get: { note.noteText },
                            set: { newValue in
                                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                                    notes[index].noteText = newValue
                                    selectedNote = notes[index]
                                    saveNotes()
                                }
                            }
                        ))
                        .font(.caption)
                        .padding(4)
                        .background(Color(.systemBackground))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .frame(height: 60)
                        
                        Text("\(note.noteText.count) characters")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Photo indicator and action buttons
                    HStack {
                        if note.photoURLs.count > 0 {
                            Label("\(note.photoURLs.count) photo\(note.photoURLs.count == 1 ? "" : "s")", systemImage: "photo")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            deleteNote(note)
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(8)
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
        .onAppear {
            loadNotes()
            loadSchoolOptions()
            loadScheduleForToday()
        }
        .sheet(isPresented: $showingFullView) {
            NavigationView {
                PhotoshootNotesView()
                    .navigationBarTitle("Photoshoot Notes", displayMode: .inline)
                    .navigationBarItems(
                        leading: Button("Done") {
                            showingFullView = false
                        }
                    )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createNewNote() {
        let newNote = PhotoshootNote(id: UUID(), timestamp: Date(), school: "", noteText: "", photoURLs: [])
        notes.append(newNote)
        selectedNote = newNote
        
        // Try to set school from today's schedule
        setSchoolFromSchedule(for: newNote)
        
        saveNotes()
    }
    
    private func deleteNote(_ note: PhotoshootNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: index)
            if selectedNote?.id == note.id {
                selectedNote = nil
            }
            saveNotes()
        }
    }
    
    private func loadNotes() {
        if let decoded = try? JSONDecoder().decode([PhotoshootNote].self, from: storedNotesData) {
            notes = decoded
        }
    }
    
    private func saveNotes() {
        if let encoded = try? JSONEncoder().encode(notes) {
            storedNotesData = encoded
        }
    }
    
    private func loadSchoolOptions() {
        let db = Firestore.firestore()
        
        UserManager.shared.getCurrentUserOrganizationID { organizationID in
            guard let orgID = organizationID else { return }
            
            db.collection("schools")
                .whereField("organizationID", isEqualTo: orgID)
                .whereField("type", isEqualTo: "school")
                .getDocuments { snapshot, error in
                    guard let docs = snapshot?.documents else { return }
                    var temp: [SchoolItem] = []
                    for doc in docs {
                        let data = doc.data()
                        if let value = data["value"] as? String,
                           let address = data["schoolAddress"] as? String {
                            let coordinates = data["coordinates"] as? String
                            let item = SchoolItem(id: doc.documentID, name: value, address: address, coordinates: coordinates)
                            temp.append(item)
                        }
                    }
                    temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                    self.schoolOptions = temp
                    
                    // Auto-set school for selected note if empty
                    if let note = self.selectedNote, note.school.isEmpty {
                        self.setSchoolFromSchedule(for: note)
                    }
                }
        }
    }
    
    private func loadScheduleForToday() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        guard let currentUserID = UserManager.shared.getCurrentUserID() else { return }
        
        // Use listenForSessions with immediate removal for one-time fetch
        let listener = sessionService.listenForSessions { sessions in
            let sessionsForToday = sessions.filter { session in
                guard let sessionDate = session.startDate else { return false }
                let isToday = sessionDate >= startOfDay && sessionDate < endOfDay
                let isUserAssigned = session.isUserAssigned(userID: currentUserID)
                return isToday && isUserAssigned
            }
            
            DispatchQueue.main.async {
                self.todaySessions = sessionsForToday
                
                // Auto-set school for selected note if needed
                if let note = self.selectedNote, note.school.isEmpty {
                    self.setSchoolFromSchedule(for: note)
                }
            }
        }
        
        // Remove listener after first callback for one-time fetch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            listener.remove()
        }
    }
    
    private func setSchoolFromSchedule(for note: PhotoshootNote) {
        guard !todaySessions.isEmpty && !schoolOptions.isEmpty else { return }
        
        let sortedSessions = todaySessions.sorted { (a, b) -> Bool in
            guard let aStart = a.startDate, let bStart = b.startDate else { return false }
            return aStart < bStart
        }
        
        if let firstSession = sortedSessions.first,
           schoolOptions.contains(where: { $0.name == firstSession.schoolName }) {
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index].school = firstSession.schoolName
                selectedNote = notes[index]
                saveNotes()
            }
        }
    }
}