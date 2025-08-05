import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
import MessageUI
import MapKit
import CoreLocation

/// Simple model for a menu feature.
struct FeatureItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let description: String
    
    static func == (lhs: FeatureItem, rhs: FeatureItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// ViewModel that manages feature ordering for employee features.
class MainEmployeeViewModel: ObservableObject {
    @Published var employeeFeatures: [FeatureItem] = []
    @Published var upcomingShifts: [Session] = []
    @Published var allSessions: [Session] = [] // Store all sessions for coworker data
    @Published var isLoadingSchedule: Bool = false
    
    // Weather service and data
    private let weatherService = WeatherService()
    @Published var weatherDataBySession: [String: WeatherData] = [:] // Key is location-date
    
    // Session service for Firestore operations
    private let sessionService = SessionService.shared
    
    // Firestore listener for real-time updates
    @Published var sessionListener: ListenerRegistration?
    
    // Default employee features – re-orderable by the user.
    let defaultEmployeeFeatures: [FeatureItem] = [
        FeatureItem(id: "timeTracking", title: "Time Tracking", systemImage: "clock.fill", description: "Clock in/out and track your hours"),
        FeatureItem(id: "scan", title: "Scan", systemImage: "wave.3.right.circle.fill", description: "Scan SD cards and job boxes"),
        FeatureItem(id: "timeOffRequests", title: "Time Off Requests", systemImage: "calendar.badge.plus", description: "Request time off and view your requests"),
        FeatureItem(id: "photoshootNotes", title: "Photoshoot Notes", systemImage: "note.text", description: "Create and manage notes for your photoshoots"),
        FeatureItem(id: "dailyJobReport", title: "Daily Job Report", systemImage: "doc.text", description: "Submit your daily job report"),
        FeatureItem(id: "customDailyReports", title: "Custom Daily Reports", systemImage: "doc.text.below.ecg", description: "Create reports using custom templates"),
        FeatureItem(id: "myDailyJobReports", title: "My Daily Job Reports", systemImage: "doc.text.magnifyingglass", description: "View and edit your job reports"),
        FeatureItem(id: "mileageReports", title: "Mileage Reports", systemImage: "car.fill", description: "Track your mileage"),
        FeatureItem(id: "schedule", title: "Schedule", systemImage: "calendar", description: "View your upcoming shifts"),
        FeatureItem(id: "locationPhotos", title: "Location Photos", systemImage: "photo.on.rectangle", description: "Manage photos for locations"),
        FeatureItem(id: "sportsShoot", title: "Sports Shoots", systemImage: "sportscourt", description: "Manage sports shoot rosters and images"),
        FeatureItem(id: "yearbookChecklists", title: "Yearbook Checklists", systemImage: "list.clipboard", description: "Track yearbook photo requirements"),
        FeatureItem(id: "classGroups", title: "Class Groups", systemImage: "person.3", description: "Track class photos by grade and teacher")
    ]
    
    private let employeeOrderKey = "employeeFeatureOrder"
    
    // Removed: ICS URL no longer needed - using Firestore sessions
    
    init() {
        loadEmployeeFeatureOrder()
    }
    
    deinit {
        // Clean up the session listener
        sessionListener?.remove()
    }
    
    func loadEmployeeFeatureOrder() {
        let saved = UserDefaults.standard.string(forKey: employeeOrderKey) ?? ""
        if saved.isEmpty {
            employeeFeatures = defaultEmployeeFeatures
        } else {
            let ids = saved.split(separator: ",").map { String($0) }
            employeeFeatures = ids.compactMap { id in
                defaultEmployeeFeatures.first(where: { $0.id == id })
            }
            // Append any missing features.
            for feature in defaultEmployeeFeatures {
                if !employeeFeatures.contains(feature) {
                    employeeFeatures.append(feature)
                }
            }
        }
    }
    
    func saveEmployeeFeatureOrder() {
        let orderString = employeeFeatures.map { $0.id }.joined(separator: ",")
        UserDefaults.standard.set(orderString, forKey: employeeOrderKey)
        print("Saved employee feature order: \(orderString)")
    }
    
    func moveEmployeeFeatures(from source: IndexSet, to destination: Int) {
        employeeFeatures.move(fromOffsets: source, toOffset: destination)
        saveEmployeeFeatureOrder()
    }
    
    // Function to fetch upcoming events from Firestore
    func fetchUpcomingEvents(employeeName: String = "") {
        // Don't show loading if we already have sessions
        if upcomingShifts.isEmpty {
            isLoadingSchedule = true
        }
        
        // Check if we already have a listener - avoid creating duplicates
        if sessionListener != nil {
            print("📅 MainEmployeeView: Already have active listener, skipping fetch")
            return
        }
        
        // Load sessions from Firestore with real-time updates
        sessionListener = sessionService.listenForSessions { [weak self] sessions in
            DispatchQueue.main.async {
                // Get current user ID for filtering
                guard let currentUserID = UserManager.shared.getCurrentUserID() else {
                    print("🔐 Cannot filter sessions: no current user ID")
                    self?.upcomingShifts = []
                    self?.isLoadingSchedule = false
                    return
                }
                
                // Filter sessions for today and tomorrow where current user is assigned
                let calendar = Calendar.current
                let startOfToday = calendar.startOfDay(for: Date())
                let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? startOfToday
                
                print("📅 Date range filter: \(startOfToday) to \(endOfTomorrow)")
                print("📅 Processing \(sessions.count) sessions for filtering")
                
                let userSessions = sessions.filter { session in
                    print("📅 Checking session: \(session.schoolName)")
                    print("📅 Raw date: \(session.date ?? "nil"), startTime: \(session.startTime ?? "nil")")
                    print("📅 Parsed startDate: \(session.startDate?.description ?? "nil")")
                    
                    guard let startDate = session.startDate else { 
                        print("❌ Session \(session.schoolName) has nil startDate - FILTERED OUT")
                        return false 
                    }
                    
                    let isInTimeRange = startDate >= startOfToday && startDate < endOfTomorrow
                    print("📅 Session \(session.schoolName) time range check: \(isInTimeRange) (date: \(startDate))")
                    
                    if !isInTimeRange {
                        print("❌ Session \(session.schoolName) outside time range - FILTERED OUT")
                        return false
                    }
                    
                    let isUserAssigned = session.isUserAssigned(userID: currentUserID)
                    
                    if isUserAssigned {
                        print("✅ Session \(session.schoolName) PASSED all filters")
                        return true
                    } else {
                        print("❌ Session \(session.schoolName) user not assigned - FILTERED OUT")
                        return false
                    }
                }
                
                // Store all sessions for coworker data
                self?.allSessions = sessions
                
                // Debug: Check what sessions were found
                for session in userSessions {
                    print("🎯 User session ID: \(session.id), school: \(session.schoolName)")
                }
                
                // Sort by start date
                let sorted = userSessions.sorted {
                    (($0.startDate ?? Date()) < ($1.startDate ?? Date()))
                }
                
                print("📅 Final filtered sessions: \(sorted.count) for user \(currentUserID)")
                self?.upcomingShifts = sorted
                self?.isLoadingSchedule = false
                
                // Load weather data for upcoming shifts
                self?.loadWeatherForSessions(sorted)
            }
        }
    }
    
    // Load weather data for sessions - optimized to batch by location
    func loadWeatherForSessions(_ sessions: [Session]) {
        // Group sessions by location and date to reduce API calls
        var locationDateGroups: [String: Date] = [:]
        
        for session in sessions {
            guard let sessionDate = session.startDate,
                  let location = session.location,
                  !location.isEmpty else {
                continue
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: sessionDate)
            let cacheKey = "\(location)-\(dateString)"
            
            // Skip if we already have weather data
            if weatherDataBySession[cacheKey] == nil {
                locationDateGroups[cacheKey] = sessionDate
            }
        }
        
        // Load weather for unique location-date combinations (max 5 to prevent overloading)
        for (index, (cacheKey, date)) in locationDateGroups.prefix(5).enumerated() {
            let location = String(cacheKey.split(separator: "-").dropLast().joined(separator: "-"))
            
            // Stagger requests slightly to avoid rate limiting
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) { [weak self] in
                self?.weatherService.getWeatherData(for: location, date: date) { weatherData, errorMessage in
                    if let weatherData = weatherData {
                        DispatchQueue.main.async {
                            self?.weatherDataBySession[cacheKey] = weatherData
                        }
                    }
                }
            }
        }
    }
    
    // Load weather for a specific session
    func loadWeatherForSession(_ session: Session) {
        guard let sessionDate = session.startDate,
              let location = session.location,
              !location.isEmpty else {
            return
        }
        
        // Create a unique key for this session
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: sessionDate)
        let cacheKey = "\(location)-\(dateString)"
        
        // Check if we already have weather data for this location and date
        if weatherDataBySession[cacheKey] != nil {
            return
        }
        
        // Get weather data
        weatherService.getWeatherData(for: location, date: sessionDate) { [weak self] weatherData, errorMessage in
            if let weatherData = weatherData {
                DispatchQueue.main.async {
                    self?.weatherDataBySession[cacheKey] = weatherData
                }
            }
        }
    }
    
    // Get weather data for specific session
    func getWeatherForSession(_ session: Session) -> WeatherData? {
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
    
    // Cleanup method to remove listener
    func cleanup() {
        sessionListener?.remove()
        sessionListener = nil
    }
}

// MARK: - Compact Session Row for MainEmployeeView

struct CompactSessionRow: View {
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
        HStack {
            // Left color bar
            Rectangle()
                .fill(colorForPosition)
                .frame(width: 4)
                .cornerRadius(2)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let start = session.startDate {
                        Text(dateFormatter.string(from: start))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Position label
                    Text(session.position)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(colorForPosition.opacity(0.2))
                        .foregroundColor(colorForPosition)
                        .cornerRadius(12)
                }
                
                Text(session.schoolName)
                    .font(.headline)
                    .lineLimit(1)
                
                // Show user's name
                Text("Photographer: \(displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack {
                    if let start = session.startDate, let end = session.endDate {
                        Text("\(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Weather info if available
                    if let weather = weatherData, let iconName = weather.iconSystemName {
                        HStack(spacing: 4) {
                            Image(systemName: iconName)
                                .foregroundColor(weather.conditionColor)
                            
                            Text(weather.temperatureString)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.leading, 8)
            
            // Chevron
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Main Employee View

struct MainEmployeeView: View {
    @Binding var isSignedIn: Bool
    
    // User info stored in AppStorage
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""
    @AppStorage("userRole") private var storedUserRole: String = "employee"
    @AppStorage("userPhotoURL") private var storedUserPhotoURL: String = ""
    @AppStorage("appTheme") private var appTheme: String = "system"
    
    // Separate view model for employee features
    @StateObject private var viewModel = MainEmployeeViewModel()
    
    // Shared time tracking service for header button
    @StateObject private var timeTrackingService = TimeTrackingService()
    
    // Tab bar management
    @StateObject private var tabBarManager = TabBarManager.shared
    @StateObject private var chatManager = ChatManager.shared
    
    // Fixed manager features
    let managerFeatures: [FeatureItem] = [
        FeatureItem(id: "timeOffApprovals", title: "Time Off Approvals", systemImage: "checkmark.circle.fill", description: "Approve or deny time off requests"),
        FeatureItem(id: "flagUser", title: "Flag User", systemImage: "flag.fill", description: "Flag a user in your organization"),
        FeatureItem(id: "unflagUser", title: "Unflag User", systemImage: "flag.slash.fill", description: "Unflag a previously flagged user"),
        FeatureItem(id: "managerMileage", title: "Manager Mileage", systemImage: "car.2.fill", description: "View mileage reports for all employees"),
        FeatureItem(id: "stats", title: "Statistics", systemImage: "chart.bar.fill", description: "View business analytics and statistics"),
        FeatureItem(id: "galleryCreator", title: "Gallery Creator", systemImage: "photo.on.rectangle.angled", description: "Create galleries in Captura and Google Sheets"),
        FeatureItem(id: "jobBoxTracker", title: "Job Box Tracker", systemImage: "cube.box.fill", description: "Track and manage job box status")
    ]
    
    // State to track which feature is selected
    @State private var selectedFeatureID: String? = nil
    
    // State for Sports Shoots feature
    @State private var selectedSportsShootID: String? = nil
    
    // State to track which session is selected for navigation
    @State private var selectedSession: Session? = nil
    
    // Flag status
    @State private var isFlagged: Bool = false
    @State private var flagNote: String = ""
    @State private var flaggedByName: String = ""
    @State private var flagListener: ListenerRegistration?
    @State private var isBannerDismissed: Bool = false
    @State private var currentListeningUserID: String? = nil
    
    // For navigating to Settings and appearance
    @State private var showSettings = false
    @State private var showThemePicker = false
    
    // Track initialization state to prevent duplicate loads
    @State private var hasInitializedData = false
    
    // Environment
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main content with tab bar
                VStack(spacing: 0) {
                    // Main content area
                    mainContent
                    
                    // Bottom tab bar
                    BottomTabBar(
                        selectedTab: $tabBarManager.selectedTab,
                        tabBarManager: tabBarManager,
                        chatManager: chatManager,
                        timeTrackingService: timeTrackingService
                    )
                }
                .ignoresSafeArea(edges: .bottom)
                
                // Flag notification banner overlay
                if isFlagged && !flagNote.isEmpty && !isBannerDismissed {
                    flagNotificationBanner
                }
            }
            .navigationBarTitle("", displayMode: .inline)
            .toolbar {
                toolbarContent
            }
            .onChange(of: tabBarManager.selectedTab) { newTab in
                // Clean up chat if we're leaving it
                if tabBarManager.selectedTab == "chat" && newTab != "chat" {
                    ChatManager.shared.cleanup()
                }
                
                // Handle tab selection
                if newTab != "home" {
                    selectedFeatureID = newTab
                }
            }
            .onAppear {
                onAppearActions()
            }
            .onDisappear {
                viewModel.saveEmployeeFeatureOrder()
                // Keep listeners active to continue receiving real-time updates
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Main Content View
    
    private var mainContent: some View {
        Group {
            if tabBarManager.selectedTab == "home" || tabBarManager.selectedTab == "" {
                homeView
            } else {
                // Show selected feature view
                featureView(for: tabBarManager.selectedTab)
            }
        }
    }
    
    // MARK: - Home View (Dashboard)
    
    private var homeView: some View {
        ZStack {
                // Background with proper flag coloring
                if isFlagged {
                    Color.red.opacity(0.3).ignoresSafeArea()
                } else {
                    backgroundGradient.ignoresSafeArea()
                }
                
            ScrollView {
                VStack(spacing: 16) {
                    // Dashboard content
                    VStack(spacing: 16) {
                        // Flag notification section
                        if isFlagged && !flagNote.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "flag.fill").foregroundColor(.red)
                                        if flaggedByName.isEmpty {
                                            Text("Flag Note").font(.headline)
                                        } else {
                                            Text("Flag Note from \(flaggedByName)").font(.headline)
                                        }
                                        Spacer()
                                    }
                                    Text(flagNote)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding()
                                .background(Color.red.opacity(0.2))
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }
                    
                        // Dashboard Widgets
                        VStack(spacing: 16) {
                            // Hours Widget
                            HoursWidget(timeTrackingService: timeTrackingService)
                            
                            // Mileage Widget
                            MileageWidget(userName: storedUserFirstName)
                            
                            // Upcoming Shifts Widget
                            UpcomingShiftsWidget(
                                sessions: viewModel.upcomingShifts,
                                isLoading: viewModel.isLoadingSchedule,
                                weatherDataBySession: viewModel.weatherDataBySession,
                                onRefresh: { loadSchedule() },
                                onSessionTap: { session in
                                    selectedSession = session
                                }
                            )
                        }
                        .padding(.horizontal)
                        
                        // All Features Button
                        NavigationLink(destination: AllFeaturesView(
                            viewModel: viewModel,
                            selectedFeatureID: $selectedFeatureID,
                            userRole: storedUserRole
                        )) {
                            HStack {
                                Image(systemName: "square.grid.2x2")
                                    .font(.title2)
                                Text("All Features")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .foregroundColor(.primary)
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    .padding(.bottom, 100) // Space for tab bar
                }
                .refreshable {
                    loadSchedule()
                }
            }
                
                // Navigation links for sheets
                NavigationLink(destination: SettingsView(), isActive: $showSettings) {
                    EmptyView()
                }
                
                // Theme picker sheet
                if showThemePicker {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            showThemePicker = false
                        }
                        .sheet(isPresented: $showThemePicker) {
                            themePickerSheet
                        }
                }
                
                // HIDDEN NAVIGATION LINKS - For feature navigation
                Group {
                    // Employee features navigation links
                    NavigationLink(
                        destination: TimeTrackingMainView(timeTrackingService: timeTrackingService),
                        tag: "timeTracking",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    .isDetailLink(false)
                    
                    NavigationLink(
                        destination: MyTimeOffRequestsView(),
                        tag: "timeOffRequests",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    .isDetailLink(false)
                    
                    NavigationLink(
                        destination: PhotoshootNotesView(),
                        tag: "photoshootNotes",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    .isDetailLink(false)
                    
                    NavigationLink(
                        destination: DailyJobReportView(),
                        tag: "dailyJobReport",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    NavigationLink(
                        destination: CustomDailyReportsView(),
                        tag: "customDailyReports",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    .isDetailLink(false)
                    
                    NavigationLink(
                        destination: MyJobReportsView(),
                        tag: "myDailyJobReports",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    .isDetailLink(false)
                    
                    NavigationLink(
                        destination: MileageReportsView(userName: storedUserFirstName),
                        tag: "mileageReports",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    .isDetailLink(false)
                    
                    NavigationLink(
                        destination: SlingWeeklyView(),
                        tag: "schedule",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    NavigationLink(
                        destination: LocationPhotoAttachmentView(),
                        tag: "locationPhotos",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    .isDetailLink(false)
                    
                    // Sports Shoots navigation link
                    NavigationLink(
                        destination: SportsShootListView(),
                        tag: "sportsShoot",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    // Yearbook Checklists navigation link
                    NavigationLink(
                        destination: YearbookShootListsView(),
                        tag: "yearbookChecklists",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    // Class Groups navigation link
                    NavigationLink(
                        destination: ClassGroupJobsListView(),
                        tag: "classGroups",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    // Chat navigation link
                    NavigationLink(
                        destination: ConversationListView(),
                        tag: "chat",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    .isDetailLink(false)
                    
                    // Scan navigation link
                    NavigationLink(
                        destination: NFCContainerView(),
                        tag: "scan",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    .isDetailLink(false)
                    
                    // Manager features navigation links
                    NavigationLink(
                        destination: TimeOffApprovalView(),
                        tag: "timeOffApprovals",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    .isDetailLink(false)
                    
                    NavigationLink(
                        destination: FlagUserView(),
                        tag: "flagUser",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    NavigationLink(
                        destination: UnflagUserView(),
                        tag: "unflagUser",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    NavigationLink(
                        destination: ManagerMileageView(),
                        tag: "managerMileage",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    // Stats view navigation link
                    NavigationLink(
                        destination: StatsView(),
                        tag: "stats",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    // Gallery Creator navigation link
                    NavigationLink(
                        destination: GalleryCreatorView(),
                        tag: "galleryCreator",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    // Job Box Tracker navigation link
                    NavigationLink(
                        destination: ManagerJobBoxTrackerView(),
                        tag: "jobBoxTracker",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                }
                .hidden()  // Hide these navigation links
                
                // Hidden navigation link for session details
                if let session = selectedSession {
                    NavigationLink(
                        destination: ShiftDetailView(
                            session: session,
                            allSessions: viewModel.allSessions, // Pass ALL sessions, not just the upcoming ones
                            currentUserID: UserManager.shared.getCurrentUserID()
                        )
                        .id(session.id), // Force SwiftUI to create fresh view for each session
                        isActive: Binding(
                            get: { selectedSession != nil },
                            set: { if !$0 { selectedSession = nil } }
                        )
                    ) { EmptyView() }
                    .hidden()
                }
            }
        }
    
    // MARK: - Feature View Navigation
    
    @ViewBuilder
    private func featureView(for featureId: String) -> some View {
        switch featureId {
        case "timeTracking":
            TimeTrackingMainView(timeTrackingService: timeTrackingService)
        case "chat":
            ConversationListView()
        case "scan":
            NFCContainerView()
        case "photoshootNotes":
            PhotoshootNotesView()
        case "dailyJobReport":
            DailyJobReportView()
        case "sportsShoot":
            SportsShootListView()
        case "yearbookChecklists":
            YearbookShootListsView()
        case "classGroups":
            ClassGroupJobsListView()
        case "customDailyReports":
            CustomDailyReportsView()
        case "myDailyJobReports":
            MyJobReportsView()
        case "mileageReports":
            MileageReportsView(userName: storedUserFirstName)
        case "schedule":
            SlingWeeklyView()
        case "locationPhotos":
            LocationPhotoAttachmentView()
        case "timeOffRequests":
            MyTimeOffRequestsView()
        case "timeOffApprovals":
            TimeOffApprovalView()
        case "flagUser":
            FlagUserView()
        case "unflagUser":
            UnflagUserView()
        case "managerMileage":
            ManagerMileageView()
        case "stats":
            StatsView()
        case "galleryCreator":
            GalleryCreatorView()
        case "jobBoxTracker":
            ManagerJobBoxTrackerView()
        default:
            homeView
        }
    }
    
    // MARK: - Toolbar Content
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Left toolbar: optional logo
        ToolbarItem(placement: .navigationBarLeading) {
            if tabBarManager.selectedTab == "home" || tabBarManager.selectedTab == "" {
                Image("employeeStaff")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 44)
            } else {
                Button(action: {
                    tabBarManager.selectedTab = "home"
                    selectedFeatureID = nil
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Home")
                    }
                }
            }
        }
        
        // Right toolbar: profile info
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 10) {
                    Text(storedUserFirstName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let url = URL(string: storedUserPhotoURL), !storedUserPhotoURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image.resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            case .failure(_):
                                Image(systemName: "person.crop.circle.badge.exclam")
                                    .resizable()
                                    .frame(width: 40, height: 40)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "person.crop.circle")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.gray)
                    }
                    Menu {
                        Button(action: { showSettings = true }) {
                            Label("Settings", systemImage: "gear")
                        }
                        Button(action: { showThemePicker = true }) {
                            Label("Appearance", systemImage: "paintbrush")
                        }
                        Button("Logout") {
                            do {
                                try Auth.auth().signOut()
                                isSignedIn = false
                            } catch {
                                print("Logout error: \(error.localizedDescription)")
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
        }
    
    // MARK: - On Appear Actions
    
    private func onAppearActions() {
        if #available(iOS 16.0, *) {
            UITableView.appearance().backgroundColor = .clear
        }
        
        // Check if user has changed
        let currentUID = Auth.auth().currentUser?.uid
        if currentUID != currentListeningUserID {
            // User changed, update flag listener
            currentListeningUserID = currentUID
            listenForFlagStatus()
        }
        
        // Only initialize data once to prevent duplicate loads
        if !hasInitializedData {
            hasInitializedData = true
            
            // Initialize user organization ID for session filtering
            UserManager.shared.initializeOrganizationID()
            
            // Refresh time tracking service to ensure proper user setup
            timeTrackingService.refreshUserAndStatus()
            
            // Initialize chat manager
            Task {
                await chatManager.initialize()
            }
            
            // Delay data loading slightly to ensure organization ID is cached
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                loadSchedule()
            }
        } else {
            // On subsequent appears, only refresh if needed
            if viewModel.upcomingShifts.isEmpty {
                loadSchedule()
            }
        }
        
        // Reset selections when view appears
        if tabBarManager.selectedTab == "home" {
            selectedFeatureID = nil
        }
        selectedSession = nil
        
        // Apply the saved theme when the app starts or the view appears
        applyAppTheme()
    }
    
    // MARK: - Computed Properties & UI Components
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color(UIColor.systemBackground).opacity(0.9),
                    Color(UIColor.systemBackground).opacity(0.85)
                ]
            ),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var flagNotificationBanner: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "flag.fill").foregroundColor(.red)
                    if flaggedByName.isEmpty {
                        Text("Flag Note").font(.headline)
                    } else {
                        Text("Flag Note from \(flaggedByName)").font(.headline)
                    }
                    Spacer()
                    Button(action: {
                        // Dismiss the banner overlay
                        withAnimation {
                            isBannerDismissed = true
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                Text(flagNote).font(.body)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground).opacity(0.95))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
        .transition(.move(edge: .bottom))
        .animation(.easeInOut, value: isFlagged)
    }
    
    private var themePickerSheet: some View {
        NavigationView {
            List {
                Button(action: { setTheme("system") }) {
                    HStack {
                        Label("System", systemImage: "gear")
                        Spacer()
                        if appTheme == "system" {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Button(action: { setTheme("light") }) {
                    HStack {
                        Label("Light", systemImage: "sun.max")
                        Spacer()
                        if appTheme == "light" {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Button(action: { setTheme("dark") }) {
                    HStack {
                        Label("Dark", systemImage: "moon")
                        Spacer()
                        if appTheme == "dark" {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .navigationTitle("Appearance")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showThemePicker = false
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    // Modified setTheme function to properly save and apply theme
    private func setTheme(_ theme: String) {
        self.appTheme = theme
        showThemePicker = false
        
        // Apply the theme
        applyAppTheme()
    }
    
    // New function to apply the theme based on the appTheme value
    private func applyAppTheme() {
        // Set the app's appearance mode
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                for window in windowScene.windows {
                    switch appTheme {
                    case "light":
                        window.overrideUserInterfaceStyle = .light
                    case "dark":
                        window.overrideUserInterfaceStyle = .dark
                    default:
                        window.overrideUserInterfaceStyle = .unspecified
                    }
                }
            }
        }
        
        // Also set the app-wide appearance through UIApplication
        let userDefaultsKey = "AppleInterfaceStyle"
        switch appTheme {
        case "light":
            UserDefaults.standard.set("Light", forKey: userDefaultsKey)
        case "dark":
            UserDefaults.standard.set("Dark", forKey: userDefaultsKey)
        default:
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
        
        // Update the app's interface style through notification
        NotificationCenter.default.post(name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }
    
    private func featureColorFor(_ id: String) -> Color {
        switch id {
        case "timeTracking": return .cyan
        case "photoshootNotes": return .purple
        case "dailyJobReport": return .blue
        case "customDailyReports": return .mint
        case "myDailyJobReports": return .green
        case "mileageReports": return .orange
        case "schedule": return .red
        case "locationPhotos": return .pink
        case "sportsShoot": return .indigo
        case "yearbookChecklists": return .purple
        case "chat": return .blue
        case "scan": return .orange
        case "flagUser": return .red
        case "unflagUser": return .green
        case "managerMileage": return .blue
        case "stats": return .indigo
        case "galleryCreator": return .green
        case "jobBoxTracker": return .teal
        default: return .gray
        }
    }
    
    private func loadSchedule() {
        let currentUserID = UserManager.shared.getCurrentUserID() ?? "unknown"
        print("🔍 Searching for events for user ID: '\(currentUserID)'")
        viewModel.fetchUpcomingEvents(employeeName: "") // employeeName parameter no longer used
    }
    
    // Firebase listener for flag status
    func listenForFlagStatus() {
        // Remove previous listener if exists
        flagListener?.remove()
        
        guard let currentUID = Auth.auth().currentUser?.uid else {
            print("No current user UID.")
            return
        }
        let db = Firestore.firestore()
        flagListener = db.collection("users").document(currentUID)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening for user doc changes: \(error.localizedDescription)")
                    return
                }
                guard let data = snapshot?.data() else {
                    print("No user data in snapshot.")
                    return
                }
                if let boolVal = data["isFlagged"] as? Bool {
                    self.isFlagged = boolVal
                } else if let intVal = data["isFlagged"] as? Int {
                    self.isFlagged = (intVal == 1)
                } else {
                    self.isFlagged = false
                }
                self.flagNote = data["flagNote"] as? String ?? ""
                if let flaggedByID = data["flaggedBy"] as? String, !flaggedByID.isEmpty {
                    self.loadFlaggedByName(flaggedByID: flaggedByID)
                } else {
                    self.flaggedByName = ""
                }
                if let updatedPhotoURL = data["photoURL"] as? String,
                   !updatedPhotoURL.isEmpty,
                   updatedPhotoURL != self.storedUserPhotoURL {
                    self.storedUserPhotoURL = updatedPhotoURL
                }
                
                // Reset banner dismissal when flag status changes
                if self.isFlagged && !self.flagNote.isEmpty {
                    self.isBannerDismissed = false
                }
                
                // Debug logging
                print("🚩 Flag status updated - isFlagged: \(self.isFlagged), note: '\(self.flagNote)', flaggedBy: '\(self.flaggedByName)'")
            }
    }
    
    func loadFlaggedByName(flaggedByID: String) {
        let db = Firestore.firestore()
        db.collection("users").document(flaggedByID).getDocument { snapshot, error in
            if let error = error {
                print("Error fetching flaggedBy user: \(error.localizedDescription)")
                self.flaggedByName = ""
                return
            }
            guard let data = snapshot?.data() else {
                self.flaggedByName = ""
                return
            }
            self.flaggedByName = data["firstName"] as? String ?? ""
        }
    }
}
