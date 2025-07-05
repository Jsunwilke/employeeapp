import SwiftUI
import FirebaseFirestore

enum ScheduleMode: String, CaseIterable {
    case myShifts = "My Shifts"
    case allShifts = "All Shifts"
}

struct SlingWeeklyView: View {
    // Full ICS URL from Sling
    private let icsURL = "https://calendar.getsling.com/564097/18fffd515e88999522da2876933d36a9d9d83a7eeca9c07cd58890a8/Sling_Calendar_all.ics"
    
    @State private var events: [ICSEvent] = []  // All ICS events loaded
    @State private var filteredEvents: [ICSEvent] = []  // Events for display after filtering
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    
    // Current date & navigation state
    @State private var currentDate: Date = Date()
    @State private var weekOffset: Int = 0
    @State private var selectedDay: Date? = nil
    
    // Selected event for detail view
    @State private var selectedEvent: ICSEvent? = nil
    
    @State private var scheduleMode: ScheduleMode = .myShifts
    
    // Weather service and data
    private let weatherService = WeatherService()
    @State private var weatherDataByEvent: [String: WeatherData] = [:] // Key is location-date
    @State private var isLoadingWeather: Bool = false
    
    // User's first and last name from AppStorage (used in filtering "My Shifts")
    @AppStorage("userFirstName") var storedUserFirstName: String = ""
    @AppStorage("userLastName") var storedUserLastName: String = ""
    
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
            loadICS()
            if selectedDay == nil {
                selectedDay = Date()
            }
        }
        .onChange(of: weekOffset) { _ in
            updateDisplayedEvents()
            if let selectedDay = selectedDay, !isDateInVisibleWeek(selectedDay) {
                // If selected day is no longer in visible week after a week change,
                // select the closest date in the new week
                self.selectedDay = getClosestVisibleDate(to: selectedDay)
            }
            loadWeatherForVisibleEvents()
        }
        .onChange(of: selectedDay) { _ in
            loadWeatherForVisibleEvents()
        }
        // Handle navigation to event details
        .background(
            NavigationLink(
                destination: selectedEvent.map { event in
                    ShiftDetailView(event: event, allEvents: events)
                },
                isActive: Binding(
                    get: { selectedEvent != nil },
                    set: { if !$0 { selectedEvent = nil } }
                )
            ) { EmptyView() }
        )
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
                    updateDisplayedEvents()
                    loadWeatherForVisibleEvents()
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
                    filterEvents()
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
    
    // Selected day header with number of shifts
    private func selectedDayHeader(for date: Date) -> some View {
        let dayEvents = getEventsForDay(date)
        
        return HStack {
            Text(formatFullDate(date))
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text("\(dayEvents.count) shift\(dayEvents.count != 1 ? "s" : "")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // Events list for selected day
    private func eventsListView(for date: Date) -> some View {
        let dayEvents = getEventsForDay(date)
        
        return ScrollView {
            LazyVStack(spacing: 12) {
                if dayEvents.isEmpty {
                    Text("No shifts scheduled for this day")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                } else {
                    ForEach(dayEvents) { event in
                        EventCard(
                            event: event,
                            isMyShiftsMode: scheduleMode == .myShifts,
                            weatherData: getWeatherDataForEvent(event)
                        )
                        .padding(.horizontal)
                        .onTapGesture {
                            selectedEvent = event
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
                loadICS()
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
    
    // MARK: - Event Card
    
    struct EventCard: View {
        let event: ICSEvent
        let isMyShiftsMode: Bool
        let weatherData: WeatherData? // Weather specific to this event's location
        
        @Environment(\.colorScheme) var colorScheme
        
        private var timeFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter
        }
        
        private var colorForPosition: Color {
            if let positionColor = positionColorMap[event.position] {
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
            
            return colorMap[event.position] ?? .blue
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
                    if let start = event.startDate, let end = event.endDate {
                        Text("\(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))")
                            .font(.headline)
                            .foregroundColor(.primary)
                    } else if let start = event.startDate {
                        Text(timeFormatter.string(from: start))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Position tag with rounded background
                    Text(event.position)
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
                        Text(event.schoolName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // Location address with icon if available
                        if let location = event.location, !location.isEmpty {
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
    
    // MARK: - Weather Methods
    
    // Get weather data for a specific event
    private func getWeatherDataForEvent(_ event: ICSEvent) -> WeatherData? {
        guard let eventDate = event.startDate,
              let location = event.location,
              !location.isEmpty else {
            // Skip if no location or date
            return nil
        }
        
        // Create a unique key for this event's location and date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: eventDate)
        let cacheKey = "\(location)-\(dateString)"
        
        return weatherDataByEvent[cacheKey]
    }
    
    // Load weather data for all events in the current view
    private func loadWeatherForVisibleEvents() {
        print("Loading weather for visible events...")
        
        // Get events for the selected day only
        guard let selectedDate = selectedDay else { return }
        let dayEvents = getEventsForDay(selectedDate)
        
        // No events means no weather to load
        if dayEvents.isEmpty {
            return
        }
        
        isLoadingWeather = true
        
        // For each event with a location, load its specific weather
        for event in dayEvents {
            // Skip if no date or location
            guard let eventDate = event.startDate,
                  let location = event.location,
                  !location.isEmpty else {
                continue
            }
            
            // Create a unique key for this event's location and date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: eventDate)
            let cacheKey = "\(location)-\(dateString)"
            
            // Only fetch if we don't already have data for this event location and date
            if weatherDataByEvent[cacheKey] == nil {
                print("Fetching weather for location: \(location) on \(dateString)")
                
                // Get weather for this specific event location and date
                weatherService.getWeatherData(for: location, date: eventDate) { weatherData, errorMessage in
                    DispatchQueue.main.async {
                        if let weatherData = weatherData {
                            // Store the weather data with the unique key
                            self.weatherDataByEvent[cacheKey] = weatherData
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
    
    // MARK: - Data Loading
    
    private func loadICS() {
        isLoading = true
        errorMessage = ""
        
        guard let url = URL(string: icsURL) else {
            errorMessage = "Invalid ICS URL."
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    errorMessage = "Error loading ICS: \(error.localizedDescription)"
                    isLoading = false
                }
                return
            }
            
            guard let data = data, let content = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    errorMessage = "Unable to load ICS data."
                    isLoading = false
                }
                return
            }
            
            let parsed = ICSParser.parseICS(from: content)
            
            DispatchQueue.main.async {
                events = parsed
                updateDisplayedEvents()
                loadWeatherForVisibleEvents()
                isLoading = false
            }
        }.resume()
    }
    
    // MARK: - Helper Methods
    
    private func updateDisplayedEvents() {
        filterEvents()
    }
    
    private func filterEvents() {
        // Get all events
        var filtered = events
        
        // Filter by user if in "My Shifts" mode
        if scheduleMode == .myShifts {
            let fullName = "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespacesAndNewlines)
            filtered = filtered.filter { event in
                event.employeeName.lowercased() == fullName.lowercased()
            }
        }
        
        // Sort by date
        filtered.sort { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
        
        filteredEvents = filtered
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
    
    private func getEventsForDay(_ day: Date) -> [ICSEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return filteredEvents.filter { event in
            guard let eventDate = event.startDate else { return false }
            return eventDate >= startOfDay && eventDate < endOfDay
        }.sorted(by: { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) })
    }
    
    private func hasEvents(on date: Date) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        var eventsToCheck = events
        
        if scheduleMode == .myShifts {
            let fullName = "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespacesAndNewlines)
            eventsToCheck = eventsToCheck.filter { event in
                event.employeeName.lowercased() == fullName.lowercased()
            }
        }
        
        return eventsToCheck.contains { event in
            guard let eventDate = event.startDate else { return false }
            return eventDate >= startOfDay && eventDate < endOfDay
        }
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
