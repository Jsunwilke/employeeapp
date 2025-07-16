import SwiftUI
import FirebaseFirestore

enum ScheduleMode: String, CaseIterable {
    case myShifts = "My Shifts"
    case allShifts = "All Shifts"
}

struct SlingWeeklyView: View {
    // Session service for Firestore operations
    private let sessionService = SessionService.shared
    
    @State private var sessions: [Session] = []  // All sessions loaded from Firestore
    @State private var filteredSessions: [Session] = []  // Sessions for display after filtering
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    
    // Current date & navigation state
    @State private var currentDate: Date = Date()
    @State private var weekOffset: Int = 0
    @State private var selectedDay: Date? = nil
    
    // Selected session for detail view
    @State private var selectedSession: Session? = nil
    
    // Selected time off entry for detail view
    @State private var selectedTimeOffEntry: TimeOffCalendarEntry? = nil
    @State private var showingTimeOffDetail = false
    
    @State private var scheduleMode: ScheduleMode = .myShifts
    
    // Weather service and data
    private let weatherService = WeatherService()
    @State private var weatherDataBySession: [String: WeatherData] = [:] // Key is location-date
    @State private var isLoadingWeather: Bool = false
    
    // Firestore listener
    @State private var sessionListener: ListenerRegistration? = nil
    
    // User's first and last name from AppStorage (used in filtering "My Shifts")
    @AppStorage("userFirstName") var storedUserFirstName: String = ""
    @AppStorage("userLastName") var storedUserLastName: String = ""
    
    // User manager for getting current user ID
    private let userManager = UserManager.shared
    
    // Time off service and data
    private let timeOffService = TimeOffService.shared
    @State private var timeOffEntries: [TimeOffCalendarEntry] = []
    @State private var timeOffListener: ListenerRegistration? = nil
    
    // Environment for color scheme
    @Environment(\.colorScheme) var colorScheme
    
    // Interactive drag state
    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @State private var isAnimating = false
    
    // Animation parameters
    private let transitionDuration: Double = 0.3
    private let screenWidth = UIScreen.main.bounds.width
    
    var body: some View {
        VStack(spacing: 0) {
            // Week range and Today button header
            weekRangeHeader
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            // Schedule mode toggle - Clickable pill
            scheduleToggle
                .padding(.horizontal)
                .padding(.bottom, 12)
            
            if isLoading {
                loadingView
            } else if !errorMessage.isEmpty {
                errorView
            } else {
                // Improved carousel with rounded corners and interactive dragging
                ZStack {
                    // Current week view
                    calendarWeekView(weekOffset: weekOffset)
                        .offset(x: offset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !isAnimating {
                                        isDragging = true
                                        offset = value.translation.width
                                    }
                                }
                                .onEnded { value in
                                    isDragging = false
                                    let threshold = screenWidth * 0.3
                                    
                                    if value.translation.width < -threshold {
                                        // Next week
                                        animateToNextWeek()
                                    } else if value.translation.width > threshold {
                                        // Previous week
                                        animateToPreviousWeek()
                                    } else {
                                        // Return to current position
                                        withAnimation(.spring()) {
                                            offset = 0
                                        }
                                    }
                                }
                        )
                }
                .frame(height: 120)
                .padding(.horizontal)
                
                // Selected day header with shift count
                if let selectedDate = selectedDay {
                    selectedDayHeader(for: selectedDate)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }
                
                // Events list for selected day
                if let selectedDate = selectedDay {
                    eventsListView(for: selectedDate)
                }
                
                Spacer() // Push content to the top
            }
        }
        .background(Color(.systemGroupedBackground)) // Add background color to the entire view
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSessions()
            if selectedDay == nil {
                selectedDay = Date()
            }
            loadTimeOffForVisibleWeek()
        }
        .onDisappear {
            sessionListener?.remove()
            timeOffListener?.remove()
        }
        .onChange(of: weekOffset) { _ in
            updateDisplayedSessions()
            if let selectedDay = selectedDay, !isDateInVisibleWeek(selectedDay) {
                // If selected day is no longer in visible week after a week change,
                // select the closest date in the new week
                self.selectedDay = getClosestVisibleDate(to: selectedDay)
            }
            loadWeatherForVisibleSessions()
            loadTimeOffForVisibleWeek()
        }
        .onChange(of: selectedDay) { _ in
            loadWeatherForVisibleSessions()
        }
        // Handle navigation to session details
        .background(
            NavigationLink(
                destination: selectedSession.map { session in
                    ShiftDetailView(session: session, allSessions: sessions, currentUserID: userManager.getCurrentUserID())
                },
                isActive: Binding(
                    get: { selectedSession != nil },
                    set: { if !$0 { selectedSession = nil } }
                )
            ) { EmptyView() }
        )
        // Handle time off detail modal
        .sheet(isPresented: $showingTimeOffDetail) {
            if let timeOffEntry = selectedTimeOffEntry {
                TimeOffDetailView(
                    timeOffEntry: timeOffEntry,
                    onCancel: {
                        showingTimeOffDetail = false
                        selectedTimeOffEntry = nil
                        // Refresh time off data
                        loadTimeOffForVisibleWeek()
                    },
                    onDelete: {
                        showingTimeOffDetail = false
                        selectedTimeOffEntry = nil
                        // Refresh time off data
                        loadTimeOffForVisibleWeek()
                    }
                )
            }
        }
    }
    
    // MARK: - UI Components
    
    // Week range header with Today button
    private var weekRangeHeader: some View {
        HStack {
            Text(weekRangeString())
                .font(.headline)
            
            Spacer()
            
            Button(action: {
                withAnimation(.spring()) {
                    weekOffset = 0
                    selectedDay = Date()
                    updateDisplayedSessions()
                    loadWeatherForVisibleSessions()
                }
            }) {
                Text("Today")
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(16)
            }
        }
    }
    
    // Schedule mode toggle - Clickable pill
    private var scheduleToggle: some View {
        HStack {
            // Swipe instruction hint
            HStack(spacing: 4) {
                Image(systemName: "hand.draw")
                    .font(.caption)
                Text("Swipe to change weeks")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            
            Spacer()
            
            // Interactive pill button that toggles between My Shifts and All Shifts
            Button(action: {
                withAnimation(.spring()) {
                    scheduleMode = scheduleMode == .myShifts ? .allShifts : .myShifts
                    filterSessions()
                }
            }) {
                Text(scheduleMode.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // Calendar week view with rounded corners
    private func calendarWeekView(weekOffset: Int) -> some View {
        let dates = getDaysInWeek(forOffset: weekOffset)
        
        return VStack(spacing: 12) {
            // Day headers (Sun, Mon, etc)
            HStack(spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    Text(formatWeekday(date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Day cells
            HStack(spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    Button(action: {
                        selectedDay = date
                    }) {
                        VStack(spacing: 4) {
                            // Day number with circle background if selected
                            ZStack {
                                if isSelectedDay(date) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 32, height: 32)
                                } else if isToday(date) {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                }
                                
                                Text(formatDayNumber(date))
                                    .font(.system(size: 16, weight: isToday(date) ? .bold : .regular))
                                    .foregroundColor(isSelectedDay(date) ? .white : (isToday(date) ? .blue : .primary))
                            }
                            
                            // Green dot if there are events
                            if hasEvents(on: date) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                            } else {
                                Spacer()
                                    .frame(height: 6)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)  // Rounded corners
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
    
    // Selected day header with number of shifts and time off
    private func selectedDayHeader(for date: Date) -> some View {
        let daySessions = getSessionsForDay(date)
        let dayTimeOff = getTimeOffForDay(date)
        let totalEvents = daySessions.count + dayTimeOff.count
        
        return HStack {
            Text(formatFullDate(date))
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if totalEvents > 0 {
                    Text("\(totalEvents) event\(totalEvents != 1 ? "s" : "")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        if daySessions.count > 0 {
                            Text("\(daySessions.count) shift\(daySessions.count != 1 ? "s" : "")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if dayTimeOff.count > 0 {
                            Text("\(dayTimeOff.count) time off")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("No events")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // Sessions and time off list for selected day
    private func eventsListView(for date: Date) -> some View {
        let daySessions = getSessionsForDay(date)
        let dayTimeOff = getTimeOffForDay(date)
        
        return ScrollView {
            LazyVStack(spacing: 12) {
                if daySessions.isEmpty && dayTimeOff.isEmpty {
                    Text("No shifts or time off scheduled for this day")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                } else {
                    // Time off entries
                    ForEach(dayTimeOff) { timeOffEntry in
                        TimeOffCard(
                            timeOffEntry: timeOffEntry,
                            isMyShiftsMode: scheduleMode == .myShifts
                        )
                        .padding(.horizontal)
                        .onTapGesture {
                            selectedTimeOffEntry = timeOffEntry
                            showingTimeOffDetail = true
                        }
                    }
                    
                    // Session entries
                    ForEach(daySessions) { session in
                        SessionCard(
                            session: session,
                            isMyShiftsMode: scheduleMode == .myShifts,
                            weatherData: getWeatherDataForSession(session),
                            currentUserID: userManager.getCurrentUserID()
                        )
                        .padding(.horizontal)
                        .onTapGesture {
                            selectedSession = session
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    // Loading state view
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .padding(.bottom, 8)
            
            Text("Loading your schedule...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // Error state view
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
                .padding(.bottom, 8)
            
            Text("Error loading schedule")
                .font(.headline)
            
            Text(errorMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: {
                loadSessions()
            }) {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Animation Functions
    
    private func animateToNextWeek() {
        isAnimating = true
        
        // First animate off screen to the left
        withAnimation(.easeInOut(duration: transitionDuration/2)) {
            offset = -screenWidth
        }
        
        // Then reset position and increment week
        DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration/2) {
            offset = screenWidth
            weekOffset += 1
            
            // Now animate back to center from right
            withAnimation(.easeInOut(duration: transitionDuration/2)) {
                offset = 0
            }
            
            // Animation complete
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration/2) {
                isAnimating = false
            }
        }
    }
    
    private func animateToPreviousWeek() {
        isAnimating = true
        
        // First animate off screen to the right
        withAnimation(.easeInOut(duration: transitionDuration/2)) {
            offset = screenWidth
        }
        
        // Then reset position and decrement week
        DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration/2) {
            offset = -screenWidth
            weekOffset -= 1
            
            // Now animate back to center from left
            withAnimation(.easeInOut(duration: transitionDuration/2)) {
                offset = 0
            }
            
            // Animation complete
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration/2) {
                isAnimating = false
            }
        }
    }
    
    // MARK: - Session Card
    
    struct SessionCard: View {
        let session: Session
        let isMyShiftsMode: Bool
        let weatherData: WeatherData? // Weather specific to this event's location
        let currentUserID: String?
        
        @Environment(\.colorScheme) var colorScheme
        
        private var timeFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter
        }
        
        // Get the current user's photographer info from the session
        private var currentUserPhotographerInfo: (name: String, notes: String)? {
            guard let userID = currentUserID else { return nil }
            return session.getPhotographerInfo(for: userID)
        }
        
        private var displayName: String {
            if let userInfo = currentUserPhotographerInfo {
                return userInfo.name
            }
            return session.employeeName // Fallback to session's employee name
        }
        
        private var displayNotes: String {
            var notes: [String] = []
            
            // Add session-level notes if they exist
            if let sessionNotes = session.description, !sessionNotes.isEmpty {
                notes.append("Session: \(sessionNotes)")
            }
            
            // Add photographer-specific notes if they exist
            if let userInfo = currentUserPhotographerInfo, !userInfo.notes.isEmpty {
                notes.append("Personal: \(userInfo.notes)")
            }
            
            return notes.joined(separator: "\n")
        }
        
        private var colorForPosition: Color {
            if let positionColor = positionColorMap[session.position] {
                return positionColor
            }
            
            let colorMap: [String: Color] = [
                "Photographer 1": .red,
                "Photographer 2": .pink,
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
        
        // Background color based on color scheme
        private var cardBackground: Color {
            colorScheme == .dark ? Color(.systemGray6) : Color.white
        }
        
        // Shadow based on color scheme
        private var cardShadow: Color {
            colorScheme == .dark ? Color.black.opacity(0.2) : Color.black.opacity(0.1)
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Time range and position label
                HStack {
                    if let start = session.startDate, let end = session.endDate {
                        Text("\(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))")
                            .font(.headline)
                            .foregroundColor(.primary)
                    } else if let start = session.startDate {
                        Text(timeFormatter.string(from: start))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Position tag with rounded background
                    Text(session.position)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(colorForPosition.opacity(0.2))
                        .foregroundColor(colorForPosition)
                        .cornerRadius(16)
                }
                .padding(.bottom, 8)
                
                // School/location name
                HStack(alignment: .top) {
                    // Vertical color bar
                    Rectangle()
                        .fill(colorForPosition)
                        .frame(width: 4)
                        .cornerRadius(2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // School name
                        Text(session.schoolName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // Display user's name if in "My Shifts" mode
                        if isMyShiftsMode, let userInfo = currentUserPhotographerInfo {
                            Text("Photographer: \(userInfo.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Show notes if they exist
                        if !displayNotes.isEmpty {
                            Text(displayNotes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                        
                        // Location address with icon if available
                        if let location = session.location, !location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(location)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Weather information if available AND we have a valid location for this event
                            if let weather = weatherData {
                                HStack(spacing: 6) {
                                    // Weather icon
                                    if let iconName = weather.iconSystemName {
                                        Image(systemName: iconName)
                                            .foregroundColor(weather.conditionColor)
                                            .font(.caption)
                                    }
                                    
                                    // Temperature
                                    Text(weather.temperatureString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    // Condition description
                                    Text(weather.condition ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    // Wind info if available
                                    if let _ = weather.windSpeed {
                                        Text("• \(weather.windString)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 8)
                    
                    Spacer()
                    
                    // Chevron indicator for navigation
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackground)
                    .shadow(color: cardShadow, radius: 4, x: 0, y: 2)
            )
            .padding(.bottom, 2) // Add padding to separate cards better
        }
    }
    
    // MARK: - Time Off Card
    
    struct TimeOffCard: View {
        let timeOffEntry: TimeOffCalendarEntry
        let isMyShiftsMode: Bool
        
        @Environment(\.colorScheme) var colorScheme
        
        private var timeFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter
        }
        
        // Background color based on color scheme
        private var cardBackground: Color {
            colorScheme == .dark ? Color(.systemGray6) : Color.white
        }
        
        // Shadow based on color scheme
        private var cardShadow: Color {
            colorScheme == .dark ? Color.black.opacity(0.2) : Color.black.opacity(0.1)
        }
        
        // Visual styling based on status and type
        private var timeOffStyle: (backgroundColor: Color, borderColor: Color, borderStyle: StrokeStyle, textColor: Color) {
            switch timeOffEntry.status {
            case .pending:
                // Pending: Dotted blue border, transparent background
                return (
                    backgroundColor: Color.clear,
                    borderColor: Color.blue,
                    borderStyle: StrokeStyle(lineWidth: 2, dash: [5]),
                    textColor: Color.blue
                )
            case .approved:
                if timeOffEntry.isPartialDay {
                    // Approved partial day: Orange diagonal stripes
                    return (
                        backgroundColor: Color.orange.opacity(0.15),
                        borderColor: Color.orange,
                        borderStyle: StrokeStyle(lineWidth: 1),
                        textColor: Color.orange
                    )
                } else {
                    // Approved full day: Gray diagonal stripes
                    return (
                        backgroundColor: Color.gray.opacity(0.15),
                        borderColor: Color.gray,
                        borderStyle: StrokeStyle(lineWidth: 1),
                        textColor: Color.primary
                    )
                }
            default:
                // Denied/cancelled - shouldn't appear on calendar
                return (
                    backgroundColor: Color.gray.opacity(0.1),
                    borderColor: Color.gray,
                    borderStyle: StrokeStyle(lineWidth: 1),
                    textColor: Color.gray
                )
            }
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Time range and status
                HStack {
                    // Time display
                    if timeOffEntry.isPartialDay {
                        let startTime = timeFromString(timeOffEntry.startTime)
                        let endTime = timeFromString(timeOffEntry.endTime)
                        if let start = startTime, let end = endTime {
                            Text("\(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))")
                                .font(.headline)
                                .foregroundColor(timeOffStyle.textColor)
                        } else {
                            Text("Partial Day")
                                .font(.headline)
                                .foregroundColor(timeOffStyle.textColor)
                        }
                    } else {
                        Text("All Day")
                            .font(.headline)
                            .foregroundColor(timeOffStyle.textColor)
                    }
                    
                    Spacer()
                    
                    // Status indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(timeOffStyle.borderColor)
                            .frame(width: 8, height: 8)
                        Text(timeOffEntry.status.rawValue.capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(timeOffStyle.textColor)
                    }
                }
                .padding(.bottom, 8)
                
                // Time off details
                HStack(alignment: .top) {
                    // Vertical color bar
                    Rectangle()
                        .fill(timeOffStyle.borderColor)
                        .frame(width: 4)
                        .cornerRadius(2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Time off reason with icon
                        HStack(spacing: 6) {
                            Image(systemName: timeOffEntry.reason.systemImageName)
                                .foregroundColor(timeOffStyle.textColor)
                                .font(.title3)
                            Text("Time Off: \(timeOffEntry.reason.displayName)")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(timeOffStyle.textColor)
                        }
                        
                        // Show photographer name if not in "My Shifts" mode
                        if !isMyShiftsMode {
                            Text("Photographer: \(timeOffEntry.photographerName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Show notes if they exist
                        if !timeOffEntry.notes.isEmpty {
                            Text("Note: \(timeOffEntry.notes)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.leading, 8)
                    
                    Spacer()
                    
                    // Interaction indicator
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(timeOffStyle.backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(timeOffStyle.borderColor, style: timeOffStyle.borderStyle)
                    )
                    .shadow(color: cardShadow, radius: 2, x: 0, y: 1)
            )
            .padding(.bottom, 2)
        }
        
        // Helper to convert time string to Date for formatting
        private func timeFromString(_ timeString: String) -> Date? {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.date(from: timeString)
        }
    }
    
    // MARK: - Weather Methods
    
    // Get weather data for a specific session
    private func getWeatherDataForSession(_ session: Session) -> WeatherData? {
        guard let sessionDate = session.startDate,
              let location = session.location,
              !location.isEmpty else {
            // Skip if no location or date
            return nil
        }
        
        // Create a unique key for this session's location and date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: sessionDate)
        let cacheKey = "\(location)-\(dateString)"
        
        return weatherDataBySession[cacheKey]
    }
    
    // Load weather data for all sessions in the current view
    private func loadWeatherForVisibleSessions() {
        print("Loading weather for visible sessions...")
        
        // Get sessions for the selected day only
        guard let selectedDate = selectedDay else { return }
        let daySessions = getSessionsForDay(selectedDate)
        
        // No sessions means no weather to load
        if daySessions.isEmpty {
            return
        }
        
        isLoadingWeather = true
        
        // For each session with a location, load its specific weather
        for session in daySessions {
            // Skip if no date or location
            guard let sessionDate = session.startDate,
                  let location = session.location,
                  !location.isEmpty else {
                continue
            }
            
            // Create a unique key for this session's location and date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: sessionDate)
            let cacheKey = "\(location)-\(dateString)"
            
            // Only fetch if we don't already have data for this session location and date
            if weatherDataBySession[cacheKey] == nil {
                print("Fetching weather for location: \(location) on \(dateString)")
                
                // Get weather for this specific session location and date
                weatherService.getWeatherData(for: location, date: sessionDate) { weatherData, errorMessage in
                    DispatchQueue.main.async {
                        if let weatherData = weatherData {
                            // Store the weather data with the unique key
                            self.weatherDataBySession[cacheKey] = weatherData
                            print("Weather data loaded for: \(location) on \(dateString)")
                        } else if let error = errorMessage {
                            print("Error loading weather for \(location): \(error)")
                        }
                    }
                }
            } else {
                print("Using cached weather data for: \(location) on \(dateString)")
            }
        }
        
        // After 3 seconds, set loading to false regardless
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.isLoadingWeather = false
        }
    }
    
    // MARK: - Time Off Methods
    
    private func loadTimeOffForVisibleWeek() {
        print("Loading time off for visible week...")
        
        // Get the current visible week date range
        let dates = getDaysInWeek(forOffset: weekOffset)
        guard let startDate = dates.first, let endDate = dates.last else { return }
        
        // Remove existing listener
        timeOffListener?.remove()
        
        // Set up real-time listener for the current week
        timeOffListener = timeOffService.startListeningToCalendarTimeOff(
            dateRange: (start: startDate, end: endDate)
        ) { entries in
            DispatchQueue.main.async {
                self.timeOffEntries = entries
                print("Loaded \(entries.count) time off entries for week")
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadSessions() {
        isLoading = true
        errorMessage = ""
        
        // Remove any existing listener
        sessionListener?.remove()
        
        // Start listening for sessions
        sessionListener = sessionService.listenForSessions { sessions in
            DispatchQueue.main.async {
                print("📊 SlingWeeklyView: Loaded \(sessions.count) sessions")
                for session in sessions {
                    print("📊 Session: \(session.schoolName) on \(session.date ?? "nil") at \(session.startTime ?? "nil")")
                    print("📊 Employee name: '\(session.employeeName)'")
                }
                
                self.sessions = sessions
                self.updateDisplayedSessions()
                self.loadWeatherForVisibleSessions()
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateDisplayedSessions() {
        filterSessions()
    }
    
    private func filterSessions() {
        print("📊 filterSessions: Starting with \(sessions.count) sessions")
        print("📊 Schedule mode: \(scheduleMode)")
        
        // Get all sessions
        var filtered = sessions
        
        // Filter by user if in "My Shifts" mode
        if scheduleMode == .myShifts {
            guard let currentUserID = userManager.getCurrentUserID() else {
                print("📊 Cannot filter sessions: no current user ID")
                filteredSessions = []
                return
            }
            
            print("📊 Filtering for user ID: '\(currentUserID)'")
            
            let originalCount = filtered.count
            filtered = filtered.filter { session in
                let isAssigned = session.isUserAssigned(userID: currentUserID)
                if !isAssigned {
                    print("📊 Session \(session.schoolName) user '\(currentUserID)' not assigned")
                } else {
                    print("📊 ✅ Session \(session.schoolName) matches user '\(currentUserID)'")
                }
                return isAssigned
            }
            print("📊 After filtering: \(filtered.count) sessions (was \(originalCount))")
        }
        
        // Sort by date
        filtered.sort { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
        
        filteredSessions = filtered
        print("📊 Final filteredSessions count: \(filteredSessions.count)")
    }
    
    private func getDaysInWeek(forOffset offset: Int = 0) -> [Date] {
        let calendar = Calendar.current
        let today = Date()
        
        // Calculate the start of the week (Sunday)
        var weekdayOffset = 0 // Sunday is 1 in many Calendar configurations
        let currentWeekday = calendar.component(.weekday, from: today)
        let daysToSubtract = (currentWeekday - 1) // Sunday(1) - 1 = 0, Monday(2) - 1 = 1, etc.
        
        guard let startOfCurrentWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: today)) else {
            return []
        }
        
        // Apply week offset
        guard let startOfDisplayedWeek = calendar.date(byAdding: .day, value: 7 * offset, to: startOfCurrentWeek) else {
            return []
        }
        
        // Generate 7 days (Sunday to Saturday)
        var dates: [Date] = []
        for dayOffset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfDisplayedWeek) {
                dates.append(date)
            }
        }
        
        return dates
    }
    
    private func isDateInVisibleWeek(_ date: Date) -> Bool {
        let visibleDates = getDaysInWeek(forOffset: weekOffset)
        let calendar = Calendar.current
        
        guard let firstDay = visibleDates.first,
              let lastDay = visibleDates.last else {
            return false
        }
        
        let startOfFirstDay = calendar.startOfDay(for: firstDay)
        // Get end of last day by adding 1 day to the start of the last day and subtracting 1 second
        let endOfLastDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay))!.addingTimeInterval(-1)
        
        return date >= startOfFirstDay && date <= endOfLastDay
    }
    
    private func getClosestVisibleDate(to date: Date) -> Date {
        let visibleDates = getDaysInWeek(forOffset: weekOffset)
        let calendar = Calendar.current
        
        guard let firstDay = visibleDates.first,
              let lastDay = visibleDates.last else {
            return Date()
        }
        
        let startOfFirstDay = calendar.startOfDay(for: firstDay)
        let endOfLastDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay))!.addingTimeInterval(-1)
        
        if date < startOfFirstDay {
            return firstDay
        } else if date > endOfLastDay {
            return lastDay
        }
        
        return date
    }
    
    private func getSessionsForDay(_ day: Date) -> [Session] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return filteredSessions.filter { session in
            guard let sessionDate = session.startDate else { return false }
            return sessionDate >= startOfDay && sessionDate < endOfDay
        }.sorted(by: { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) })
    }
    
    private func getTimeOffForDay(_ day: Date) -> [TimeOffCalendarEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        
        var timeOffToShow = timeOffEntries
        
        // Filter by user if in "My Shifts" mode
        if scheduleMode == .myShifts {
            guard let currentUserID = userManager.getCurrentUserID() else {
                return []
            }
            
            timeOffToShow = timeOffToShow.filter { entry in
                entry.photographerId == currentUserID
            }
        }
        
        return timeOffToShow.filter { entry in
            let entryDate = calendar.startOfDay(for: entry.date)
            return entryDate == startOfDay
        }.sorted { $0.startTime < $1.startTime }
    }
    
    private func hasEvents(on date: Date) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        var sessionsToCheck = sessions
        
        if scheduleMode == .myShifts {
            guard let currentUserID = userManager.getCurrentUserID() else {
                return false
            }
            
            sessionsToCheck = sessionsToCheck.filter { session in
                session.isUserAssigned(userID: currentUserID)
            }
        }
        
        let hasSessions = sessionsToCheck.contains { session in
            guard let sessionDate = session.startDate else { return false }
            return sessionDate >= startOfDay && sessionDate < endOfDay
        }
        
        // Check for time off on this date
        let hasTimeOff = timeOffEntries.contains { timeOffEntry in
            let entryDate = calendar.startOfDay(for: timeOffEntry.date)
            let targetDate = calendar.startOfDay(for: date)
            return entryDate == targetDate
        }
        
        return hasSessions || hasTimeOff
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private func isSelectedDay(_ date: Date) -> Bool {
        guard let selectedDate = selectedDay else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }
    
    private func weekRangeString() -> String {
        let dates = getDaysInWeek(forOffset: weekOffset)
        guard let first = dates.first, let last = dates.last else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
    }
    
    // MARK: - Formatting
    
    private func formatWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private func formatDayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}
