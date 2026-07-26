import SwiftUI
import MessageUI
import MapKit
import CoreLocation
import UniformTypeIdentifiers
import Supabase
import Combine

// Widget identifier for drag and drop
enum DashboardWidget: String, CaseIterable, Identifiable, Transferable, Codable {
    // iPhone widgets (personal tracking)
    case hours = "hours"
    case mileage = "mileage"
    case shifts = "shifts"
    case tasks = "tasks"

    // iPad widgets (job tasks)
    case sportsRosters = "sportsRosters"
    case classGroups = "classGroups"
    case photoshootNotes = "photoshootNotes"

    var id: String { self.rawValue }

    // Device-specific widget lists
    static var iPhoneWidgets: [DashboardWidget] = [.hours, .mileage, .shifts, .tasks]
    static var iPadWidgets: [DashboardWidget] = [.sportsRosters, .classGroups, .photoshootNotes]
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}

/// Everywhere the home screen can push to.
///
/// One destination type behind ONE `ambientPush`, rather than the three separate
/// `NavigationLink(isActive:)` this screen used to keep live at once (Settings,
/// the design lab, and a tapped shift). Two live `isActive` links competing for
/// one container is the exact shape of the dead tap AMB.1 shipped, and AMB.3's
/// review gate turned it into a standing rule for the rest of the arc: one push
/// per view; more than one target means an enum.
enum HomeDestination: Identifiable {
    case settings
    /// TEMPORARY — the AMB arc's design lab. Removed at AMB.12 with the lab.
    case designLab
    case shift(Session)

    /// Required by `ambientPush(item:)`, which constrains its item to
    /// `Identifiable`. Nothing currently READS it — the wrapper only tests the
    /// binding for nil — so this is a conformance, not a behaviour. The view's
    /// own `.id()` at the push site is what actually decides identity.
    var id: String {
        switch self {
        case .settings: return "settings"
        case .designLab: return "designLab"
        case .shift(let session): return "shift-\(session.dayOccurrenceKey)"
        }
    }
}

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
    /// Holds the PULL CONTROL only. Distinct from `isLoadingSchedule`, which blanks
    /// the widget for its first paint — a refresh keeps the rows on screen.
    ///
    /// The listener clears this when data lands, and it cannot double as the mutex
    /// for that exact reason: the listener fires on ANY realtime delivery, so an
    /// unrelated edit somewhere in the org would clear it and re-open the guard
    /// mid-refresh, allowing the concurrent re-subscribe that leaks a channel.
    @Published var isRefreshing: Bool = false

    /// The mutex. Only `refreshUpcomingEvents` touches it, and only via `defer`, so
    /// nothing outside that function can re-open the guard while it is running.
    private var refreshInFlight = false

    // Weather service and data
    private let weatherService = WeatherService()
    @Published var weatherDataBySession: [String: WeatherData] = [:] // Key is location-date

    // Session service for Supabase operations
    private let sessionService = SessionService.shared

    // Unique subscription ID for this view model
    private let subscriptionId = UUID()

    // Track if we have an active listener
    @Published var hasActiveListener: Bool = false

    // Organization ID for session filtering
    private var organizationID: String = ""

    // Organization service to check feature flags
    private let organizationService = OrganizationService.shared
    private var organizationCancellable: AnyCancellable?

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
        FeatureItem(id: "capture", title: "Capture", systemImage: "camera.fill", description: "Poser station for portrait and sports shoots"),
        FeatureItem(id: "sportsShoot", title: "Sports Shoots", systemImage: "sportscourt", description: "Manage sports shoot rosters and images"),
        FeatureItem(id: "focalPointSports", title: "FP Sports", systemImage: "figure.run", description: "Focal Point Sports — direct subject management via Production"),
        FeatureItem(id: "yearbookChecklists", title: "Yearbook Checklists", systemImage: "list.clipboard", description: "Track yearbook photo requirements"),
        FeatureItem(id: "classGroups", title: "Groups", systemImage: "person.3", description: "Track class group, candid, and club photos"),
        FeatureItem(id: "training", title: "Training", systemImage: "graduationcap.fill", description: "View your training photos and feedback"),
        FeatureItem(id: "tasks", title: "Tasks", systemImage: "checklist", description: "Manage team tasks and to-dos"),
        FeatureItem(id: "equipment", title: "Equipment", systemImage: "camera.fill", description: "Manage photography equipment"),
        FeatureItem(id: "routePlanner", title: "Route Planner", systemImage: "map.fill", description: "Plan optimized routes between schools")
    ]
    
    private let employeeOrderKey = "employeeFeatureOrder"

    // Observer for app becoming active
    private var foregroundObserver: NSObjectProtocol?

    // Removed: ICS URL no longer needed - using Supabase sessions

    init() {
        Task { @MainActor in
            loadEmployeeFeatureOrder()
        }

        // Listen for app returning to foreground to re-subscribe
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: .appDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppBecameActive()
            }
        }

        // Watch for changes to organization settings
        Task { @MainActor in
            organizationCancellable = organizationService.$usePhotoshootNotesOnly
                .dropFirst() // Skip initial value to avoid race condition
                .sink { [weak self] newValue in
                    print("🔔 Organization setting changed: usePhotoshootNotesOnly = \(newValue)")
                    // Reload features when the setting changes
                    self?.loadEmployeeFeatureOrder()
                    // Force view update
                    self?.objectWillChange.send()
                }
        }
    }
    
    deinit {
        // Remove notification observer
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Clean up the session listener
        // Capture values BEFORE the Task closure to avoid capturing self
        // This prevents recursive deallocation that was causing the crash
        let subId = subscriptionId
        let service = sessionService

        // Use Task with pre-captured values - service and subId don't reference self
        // The stopListeningToSessions method will handle if there's no active listener
        Task { @MainActor in
            service.stopListeningToSessions(subscriptionId: subId)
        }
    }

    // Called when app returns to foreground - re-establish subscription
    private func handleAppBecameActive() {
        // Reset flag so fetchUpcomingEvents will re-subscribe
        hasActiveListener = false
        fetchUpcomingEvents(employeeName: "")
    }
    
    @MainActor
    func loadEmployeeFeatureOrder() {
        print("📋 loadEmployeeFeatureOrder called")
        let saved = UserDefaults.standard.string(forKey: employeeOrderKey) ?? ""

        // Get filtered features based on organization settings
        let availableFeatures = getAvailableFeatures()

        var newFeatures: [FeatureItem] = []

        if saved.isEmpty {
            newFeatures = availableFeatures
        } else {
            let ids = saved.split(separator: ",").map { String($0) }
            newFeatures = ids.compactMap { id in
                availableFeatures.first(where: { $0.id == id })
            }
            // Append any missing features.
            for feature in availableFeatures {
                if !newFeatures.contains(feature) {
                    newFeatures.append(feature)
                }
            }
        }

        // Force a new array assignment to trigger @Published update
        employeeFeatures = newFeatures

        print("📋 employeeFeatures now has \(employeeFeatures.count) items: \(employeeFeatures.map { $0.id })")
    }

    /// Get available features based on organization settings
    @MainActor
    private func getAvailableFeatures() -> [FeatureItem] {
        let usePhotoshootNotesOnly = organizationService.usePhotoshootNotesOnly
        print("🔍 getAvailableFeatures: usePhotoshootNotesOnly = \(usePhotoshootNotesOnly)")

        let filtered = defaultEmployeeFeatures.filter { feature in
            // If organization uses photoshoot notes only, hide daily report features
            if usePhotoshootNotesOnly {
                // Hide daily report, custom daily reports, and my daily job reports
                let shouldShow = feature.id != "dailyJobReport" &&
                       feature.id != "customDailyReports" &&
                       feature.id != "myDailyJobReports"
                if !shouldShow {
                    print("🚫 Filtering out feature: \(feature.id)")
                }
                return shouldShow
            }

            // Show all features if not using photoshoot notes only
            return true
        }

        print("✅ Returning \(filtered.count) features (filtered from \(defaultEmployeeFeatures.count))")
        return filtered
    }

    /// Check if a specific feature is currently available based on organization settings
    @MainActor
    func isFeatureAvailable(_ featureId: String) -> Bool {
        let usePhotoshootNotesOnly = organizationService.usePhotoshootNotesOnly

        // If using photoshoot notes only, block daily report features
        if usePhotoshootNotesOnly {
            let disabledFeatures = ["dailyJobReport", "customDailyReports", "myDailyJobReports"]
            return !disabledFeatures.contains(featureId)
        }

        return true
    }
    
    func saveEmployeeFeatureOrder() {
        let orderString = employeeFeatures.map { $0.id }.joined(separator: ",")
        UserDefaults.standard.set(orderString, forKey: employeeOrderKey)
    }

    func moveEmployeeFeatures(from source: IndexSet, to destination: Int) {
        employeeFeatures.move(fromOffsets: source, toOffset: destination)
        saveEmployeeFeatureOrder()
    }

    // Function to fetch upcoming events from Supabase
    ///
    /// `showLoading` exists because a REFRESH must not raise the loading flag.
    /// `isLoadingSchedule` is only ever cleared from the listener's callback, and
    /// there are real paths where that callback never fires at all — offline
    /// with a warm in-memory cache, or a failed fetch with a warm cache. On a
    /// first load that is survivable. On a refresh it is not: the flag would
    /// stick true, and because the re-subscribe also sets hasActiveListener,
    /// every later fetch returns at the guard, so the spinner could never be
    /// cleared for the rest of the session. A refresh keeps the rows (or the
    /// empty state) on screen and holds only the pull control.
    func fetchUpcomingEvents(employeeName: String = "", showLoading: Bool = true) {
        // The listener guard comes FIRST, and the order matters. It used to run
        // after the loading flag was raised, so an early return left
        // isLoadingSchedule stuck true with nothing downstream to clear it —
        // every reset lives past this point. Anyone with no upcoming shifts who
        // triggered a second fetch got a spinner that never stopped, in place of
        // the empty state. Harmless while the only trigger was a refresh button
        // nobody could reach; a real hang once pull-to-refresh works.
        if hasActiveListener {
            return
        }

        // Don't show loading if we already have sessions
        if showLoading && upcomingShifts.isEmpty {
            isLoadingSchedule = true
        }

        // Get organization ID from UserDefaults
        organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""

        guard !organizationID.isEmpty else {
            isLoadingSchedule = false
            // Nothing is going to call back, so end any refresh now rather than
            // leaving the pull control held for the full timeout.
            isRefreshing = false
            return
        }

        // Load sessions from Supabase with real-time updates
        Task { @MainActor in
            sessionService.startListeningToSessions(subscriptionId: subscriptionId, organizationID: organizationID, includeUnpublished: false) { [weak self] sessions in
                // Get current user ID for filtering
                guard let currentUserID = UserManager.shared.getCurrentUserIDUnified() else {
                    self?.upcomingShifts = []
                    self?.isLoadingSchedule = false
                    self?.isRefreshing = false
                    return
                }

                // Get current user email for fallback matching
                let currentUserEmail = UserDefaults.standard.string(forKey: "userEmail")

                // Filter sessions for today, tomorrow, and day after tomorrow where current user is assigned
                let calendar = Calendar.current
                let now = Date()
                let startOfToday = calendar.startOfDay(for: now)
                let endOfDayAfterTomorrow = calendar.date(byAdding: .day, value: 3, to: startOfToday) ?? startOfToday

                // Expand each session into one occurrence per day, then keep the
                // days THIS user works (MD7: crew is per-day — an occurrence
                // carries its own day's photographers, so a multi-day session
                // appears only on the user's own days).
                let userSessions = sessions
                    .flatMap { $0.dayOccurrences() }
                    .filter { $0.isUserAssigned(userID: currentUserID, userEmail: currentUserEmail) }
                    .filter { session in
                        guard let startDate = session.startDate else {
                            return false
                        }

                        // Check if this day is within the 3-day range
                        let isInTimeRange = startDate >= startOfToday && startDate < endOfDayAfterTomorrow

                        if !isInTimeRange {
                            return false
                        }

                        // For today's sessions, check if they've already ended
                        if calendar.isDateInToday(startDate) {
                            // Estimate session end time (assuming 2 hour duration if not specified)
                            let estimatedDuration: TimeInterval = 2 * 60 * 60 // 2 hours in seconds
                            let endDate = startDate.addingTimeInterval(estimatedDuration)

                            if endDate < now {
                                return false
                            }
                        }

                        return true
                    }

                // Store all sessions for coworker data
                self?.allSessions = sessions

                // Sort by start date
                let sorted = userSessions.sorted {
                    (($0.startDate ?? Date()) < ($1.startDate ?? Date()))
                }

                self?.upcomingShifts = sorted
                self?.isLoadingSchedule = false
                // A pull-to-refresh is finished when data has actually landed,
                // which is here — not when the re-subscribe call returns.
                self?.isRefreshing = false

                // Load weather data for upcoming shifts
                self?.loadWeatherForSessions(sorted)
            }

            hasActiveListener = true
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
    
    /// What pull-to-refresh actually does.
    ///
    /// `fetchUpcomingEvents` returns immediately once a listener is up, which is
    /// always after the first load — so calling it directly from a refresh
    /// gesture fetches nothing and lies to the user. Dropping the subscription
    /// first makes the re-subscribe do a real round trip.
    ///
    /// The wait exists so the spinner tells the truth. Without it the gesture
    /// returns instantly and the control snaps back before anything has
    /// arrived, which reads as "refreshed" when nothing has. Bounded, because a
    /// refresh that never resolves must still end.
    @MainActor
    func refreshUpcomingEvents() async {
        // Two controls call this — the pull gesture and the widget's button —
        // and overlapping runs are not harmless. Both would clear
        // hasActiveListener and re-subscribe on the SAME subscription id, and
        // the unsubscribe inside startListeningToSessionsAsync is not atomic
        // with its subscribe: the second run can look for a channel to stop
        // before the first has recorded one, then overwrite it. The first
        // channel is then never unsubscribed and its change loop lives for the
        // rest of the process, refetching the whole org on every edit.
        guard !refreshInFlight else { return }
        refreshInFlight = true
        isRefreshing = true
        defer {
            refreshInFlight = false
            isRefreshing = false
        }

        // Drop the guard flag ONLY — do not call cleanup() here. cleanup()
        // enqueues its unsubscribe on a detached Task while fetchUpcomingEvents
        // enqueues the re-subscribe on another; if the stop landed second it
        // would tear down the listener that had just been created, and the
        // dashboard would silently stop receiving updates until the app was
        // backgrounded. There is nothing to clean up by hand anyway:
        // startListeningToSessionsAsync unsubscribes the same subscription id
        // before it subscribes (SessionService.swift:236).
        hasActiveListener = false
        fetchUpcomingEvents(showLoading: false)

        // Hold the pull control until data lands, so it does not snap back
        // claiming a refresh that has not happened. Bounded, because several
        // paths through the listener never call back at all.
        let deadline = Date().addingTimeInterval(8)
        while isRefreshing && Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                // Cancelled — the user navigated away. Without this the sleep
                // throws instantly on every iteration and the "poll" becomes a
                // main-actor busy loop for the rest of the deadline.
                break
            }
        }
    }

    // Cleanup method to remove listener
    func cleanup() {
        if hasActiveListener {
            Task { @MainActor in
                sessionService.stopListeningToSessions(subscriptionId: subscriptionId)
            }
            hasActiveListener = false
        }
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
    @AppStorage("dashboardWidgetOrder") private var widgetOrderString: String = ""
    @AppStorage("iPadDashboardWidgetOrder") private var iPadWidgetOrderString: String = ""
    
    // Separate view model for employee features
    @StateObject private var viewModel = MainEmployeeViewModel()
    
    // Shared time tracking service for header button
    @ObservedObject private var timeTrackingService = TimeTrackingService.shared
    
    // Tab bar management
    @StateObject private var tabBarManager = TabBarManager.shared
    @StateObject private var chatManager = ChatManager.shared
    @ObservedObject private var authService = SupabaseAuthService.shared

    /// The tab we are leaving. `onChange` sees the observed object already holding
    /// the NEW value, so the outgoing tab has to be tracked here.
    @State private var previousTab: String = TabBarManager.shared.selectedTab

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
    
    
    // State for Sports Shoots feature
    @State private var selectedSportsShootID: String? = nil
    
    // The one thing home is currently pushing to (see HomeDestination).
    @State private var homeDestination: HomeDestination? = nil
    
    // Flag status
    @State private var isFlagged: Bool = false
    @State private var flagNote: String = ""
    @State private var flaggedByName: String = ""
    
    // Widget order management
    @State private var widgetOrder: [DashboardWidget] = []
    @State private var draggedWidget: DashboardWidget?
    @State private var flagChannel: RealtimeChannelV2?
    @State private var isBannerDismissed: Bool = false
    @State private var currentListeningUserID: String? = nil
    
    @State private var showThemePicker = false
    @State private var showToast = false
    @State private var toastMessage = ""
    
    // Track initialization state to prevent duplicate loads
    @State private var hasInitializedData = false
    
    // Environment
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Device detection
    private var isIPad: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    /// The bar is only taken away for a genuine full-screen overlay — the photo
    /// viewer. Since AMB.4 a screen that merely wants room says so by letting the
    /// user tuck the bar, rather than removing their navigation for them.
    private var showsTabBar: Bool { !tabBarManager.isFullScreenOverlayActive }
    
    var body: some View {
        ZStack {
            // Main content with tab bar. The shell no longer owns a global
            // NavigationView — each screen provides its own nav bar (see
            // mainContent), so nothing stacks a second bar on top of a
            // feature that brings its own.
            // THE BAR FLOATS (AMB.4). It used to be a row in this stack, so it
            // owned a strip of the screen and nothing could ever pass behind it —
            // which also meant its glass had nothing to refract. Operator's
            // reasoning: "what would be the point of glass if the bar reserved its
            // own space?" So it is an overlay now, and content scrolls underneath.
            ZStack(alignment: .bottom) {
                // Main content area — routed to its own nav container per feature.
                // The clearance that keeps content out from under the capsule is
                // applied INSIDE each container (see tabBarClearance), not here.
                mainContent

                // Hidden outright only for a genuine full-screen overlay, like the
                // photo viewer. Everywhere else it is present and the user can tuck
                // it away by hand.
                if showsTabBar {
                    BottomTabBar(
                        selectedTab: $tabBarManager.selectedTab,
                        tabBarManager: tabBarManager,
                        chatManager: chatManager,
                        timeTrackingService: timeTrackingService
                    )
                }
            }

            // Flag notification banner overlay
            if isFlagged && !flagNote.isEmpty && !isBannerDismissed {
                flagNotificationBanner
            }
        }
        .onChange(of: tabBarManager.selectedTab) { newTab in
            // Clean up chat if we're leaving it.
            //
            // This compared `tabBarManager.selectedTab` against `newTab`, but by
            // the time onChange runs the observed object ALREADY holds the new
            // value — so the test read "newTab == chat && newTab != chat" and
            // could never be true. cleanup() had therefore never run once, which
            // also meant the chat cache was never pruned. `previousTab` is
            // captured explicitly rather than read back off the manager.
            if previousTab == "chat" && newTab != "chat" {
                ChatManager.shared.cleanup()
            }
            previousTab = newTab
            // Leaving home tears down its NavigationView but NOT this state, so
            // a destination left set here re-pushed itself the next time home
            // was selected — tap a shift, switch to Tasks, come back, and the
            // detail opened again on its own. The bottom bar stays live while a
            // detail is pushed, so this is an ordinary thing to do by accident.
            if newTab != "home" {
                homeDestination = nil
            }
        }
        .onAppear {
            onAppearActions()
        }
        .onDisappear {
            viewModel.saveEmployeeFeatureOrder()
            // Keep listeners active to continue receiving real-time updates
        }
        .toast(isPresented: $showToast, message: toastMessage, isSuccess: true)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowReportSuccessToast"))) { _ in
            toastMessage = "Report submitted successfully"
            showToast = true
        }
    }
    
    // MARK: - Main Content View
    
    private var mainContent: some View {
        Group {
            if tabBarManager.selectedTab == "home" {
                homeContainer
            } else if viewModel.isFeatureAvailable(tabBarManager.selectedTab) {
                featureContainer(for: tabBarManager.selectedTab)
            } else {
                // Feature is disabled, redirect to home
                Color.clear
                    .onAppear {
                        tabBarManager.selectedTab = "home"
                    }
            }
        }
    }

    // MARK: - Per-screen navigation containers
    //
    // Every screen owns exactly one nav bar. The shell used to wrap the whole
    // app in a single NavigationView, which stacked a second bar on top of any
    // feature that brought its own (the "double back button"). Now the shell
    // hands each screen its own container instead.

    /// Home dashboard in its own nav container. The profile menu (Settings /
    /// Appearance / Logout) lives here rather than on top of every feature.
    private var homeContainer: some View {
        NavigationView {
            homeView
                .navigationBarTitle("", displayMode: .inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    homeProfileToolbar
                }
                .tabBarClearance(showsTabBar, keyboardVisible: tabBarManager.isKeyboardVisible)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    /// Wrap a feature in exactly one nav bar. Self-nav features already own
    /// one, so they render bare; everything else gets a shell-provided
    /// NavigationView that shows the feature's own title/toolbar.
    @ViewBuilder
    private func featureContainer(for featureId: String) -> some View {
        if isSelfNavFeature(featureId) {
            // Self-nav features own their bar and add their own Home button
            // (via .homeToolbarItem() inside each view).
            //
            // NO clearance from out here. Each self-nav feature applies its own
            // INSIDE its container, which is the only position that works for a
            // legacy NavigationView. Applying it here as well would be harmless for
            // those — the outer inset is simply ignored — but EquipmentView uses a
            // real NavigationStack, which DOES honour an outer inset, so the two
            // stacked and it reserved 168pt instead of 84.
            featureView(for: featureId)
        } else {
            NavigationView {
                featureView(for: featureId)
                    .homeToolbarItem() // top-left Home on every shell-wrapped feature
                    .tabBarClearance(showsTabBar, keyboardVisible: tabBarManager.isKeyboardVisible)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }

    /// Features whose root view already provides its own NavigationView /
    /// NavigationStack (verified against each view's body, 2026-07-14).
    /// Wrapping these would re-create the doubled nav bar.
    private func isSelfNavFeature(_ featureId: String) -> Bool {
        switch featureId {
        case "capture", "training", "unflagUser", "tasks", "equipment":
            // Self-nav on every device.
            return true
        case "sportsShoot", "focalPointSports":
            // Self-nav on iPad (sidebar NavigationView); a bare VStack on
            // iPhone that needs a shell wrap. Match the views' own `isIPhone`
            // predicate exactly (UIDevice idiom) so an iPad in Split View
            // still counts as self-nav.
            return UIDevice.current.userInterfaceIdiom != .phone
        default:
            return false
        }
    }
    
    // MARK: - Home View (Dashboard)
    
    /// The ambient wash behind home.
    ///
    /// D11 gives every converted screen its feature's colour, but home is not a
    /// feature — it is the container — so it takes the COMPANY blue, at 90%
    /// (operator, 2026-07-25). The blue came from Logo.svg, the only place it
    /// was ever written down; the app's AccentColor asset is empty, so before
    /// AMB.2 the app had been running on Apple's default blue.
    ///
    /// Being flagged still turns the page red, because that is the one state on
    /// this screen that has to be visible from across a room.
    private var homeBackground: some View {
        AmbientBackdrop(tint: isFlagged ? .red : AmbientStyle.brand,
                        intensity: isFlagged ? 1 : 0.9)
    }

    @ViewBuilder
    private var flagNotificationView: some View {
        if isFlagged && !flagNote.isEmpty {
            AmbientNoteCard(
                title: flaggedByName.isEmpty ? "Flag note" : "Flag note from \(flaggedByName)",
                text: flagNote,
                accent: .red
            )
            .padding(.horizontal, 16)
        }
    }

    private var dashboardWidgetsView: some View {
        VStack(spacing: 16) {
            ForEach(widgetOrder) { widget in
                widgetView(for: widget)
                    // Drag to reorder, saved per device. The approved mockup drew
                    // a fixed stack with no reordering at all; this is the single
                    // largest capability on the shell and it stays.
                    .onDrag {
                        draggedWidget = widget
                        return NSItemProvider(object: widget.rawValue as NSString)
                    }
                    .onDrop(of: [.plainText], delegate: WidgetDropDelegate(
                        widget: widget,
                        widgetOrder: $widgetOrder,
                        draggedWidget: $draggedWidget,
                        onReorder: saveWidgetOrder
                    ))
            }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func widgetView(for widget: DashboardWidget) -> some View {
        Group {
            switch widget {
            // iPhone widgets
            case .hours:
                HoursWidget(timeTrackingService: timeTrackingService)
            case .mileage:
                MileageWidget(userName: storedUserFirstName)
            case .shifts:
                UpcomingShiftsWidget(
                    sessions: viewModel.upcomingShifts,
                    isLoading: viewModel.isLoadingSchedule,
                    weatherDataBySession: viewModel.weatherDataBySession,
                    // The widget's own refresh button had the same dead
                    // behaviour as the pull gesture — it called straight into
                    // the listener guard and returned. Same real path now.
                    onRefresh: { Task { await viewModel.refreshUpcomingEvents() } },
                    onSessionTap: { session in
                        homeDestination = .shift(session)
                    }
                )
            case .tasks:
                TasksWidget(tabBarManager: tabBarManager)

            // iPad widgets
            case .sportsRosters:
                SportsRostersWidget(tabBarManager: tabBarManager)
            case .classGroups:
                ClassGroupsWidget(tabBarManager: tabBarManager)
            case .photoshootNotes:
                PhotoshootNotesWidget()
            }
        }
    }
    
    
    private var homeView: some View {
        ZStack {
            homeBackground

            ScrollView {
                VStack(spacing: 16) {
                    flagNotificationView
                    dashboardWidgetsView
                    allFeaturesRow
                }
                .padding(.top, 9)
                // No hand-rolled room for the bar any more — the shell's
                // safeAreaInset does it for every screen, and leaving this at 100
                // would double the gap.
                .padding(.bottom, 12)
            }
            // ON THE SCROLL VIEW, not on its content. This was previously
            // attached to the inner VStack, which cannot work: a refresh action
            // travels to a scroll view through ITS OWN environment, and the
            // environment flows downward, so a child cannot install one on its
            // parent. The converted schedule (ScheduleView) has always had it in
            // the right place; home did not.
            .refreshable {
                await viewModel.refreshUpcomingEvents()
            }
        }
        .sheet(isPresented: $showThemePicker) {
            themePickerSheet
        }
        // The screen's ONE push. See HomeDestination.
        .ambientPush(item: $homeDestination) { destination in
            switch destination {
            case .settings:
                SettingsView()
            case .designLab:
                // Pushed into the Home screen's real NavigationView on purpose:
                // a mockup has to run inside the same navigation container its
                // real screen will get, or it is testing a frame that does not
                // exist. See DesignLabView.swift.
                DesignLabView()
            case .shift(let session):
                ShiftDetailView(
                    session: session,
                    allSessions: viewModel.allSessions, // ALL sessions, not just the upcoming ones
                    currentUserID: UserManager.shared.getCurrentUserID(),
                    // This screen's listener asks for published sessions only,
                    // so nothing here is ever a draft and nothing has been
                    // redacted on the way in.
                    crewHidden: false
                )
                // Keyed by DAY OCCURRENCE, not session id. A multi-day job is
                // several rows sharing one id, so keying on the id let SwiftUI
                // reuse the detail across days — open day 1, go back, open day 2
                // and you kept day 1's loaded state under day 2's data. This is
                // the identity ShiftDetailView documents for itself, and the
                // one ScheduleView already uses.
                .id(session.dayOccurrenceKey)
            }
        }
    }

    private var allFeaturesRow: some View {
        NavigationLink(destination: AllFeaturesView(
            viewModel: viewModel,
            tabBarManager: tabBarManager,
            userRole: storedUserRole
        )) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AmbientStyle.brand)
                Text("All Features").font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .ambientCard(density: .roomy, fillWidth: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
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
        case "capture":
            CaptureGalleryListView()
        case "sportsShoot":
            CapturaSportsView()
        case "focalPointSports":
            FPSportsRosterView_iPad()
        case "yearbookChecklists":
            YearbookShootListsView()
        case "classGroups":
            ClassGroupJobsListView()
        case "training":
            PhotoCritiqueListView()
        case "customDailyReports":
            CustomDailyReportsView()
        case "myDailyJobReports":
            MyJobReportsView()
        case "mileageReports":
            MileageReportsView(userName: storedUserFirstName)
        case "schedule":
            ScheduleView()
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
        case "tasks":
            TasksView()
        case "equipment":
            EquipmentView()
        case "routePlanner":
            RoutePlannerView()
        default:
            homeView
        }
    }
    
    // MARK: - Home Profile Toolbar

    /// Profile menu shown only on the Home screen. Home is reachable from the
    /// permanent Home button in the bottom bar, so there is no top-left Home
    /// button and no per-feature back-override anymore.
    @ToolbarContentBuilder
    private var homeProfileToolbar: some ToolbarContent {
        // Right toolbar: profile info
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 10) {
                    Text(storedUserFirstName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !storedUserPhotoURL.isEmpty {
                        SupabaseAvatarView(storageURL: storedUserPhotoURL, size: 28)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.gray)
                    }
                    Menu {
                        Button(action: { homeDestination = .settings }) {
                            Label("Settings", systemImage: "gear")
                        }
                        Button(action: { showThemePicker = true }) {
                            Label("Appearance", systemImage: "paintbrush")
                        }
                        // TEMPORARY — removed at AMB.12 with the lab itself.
                        Button(action: { homeDestination = .designLab }) {
                            Label("Design Lab", systemImage: "paintpalette")
                        }
                        Button("Logout") {
                            Task {
                                do {
                                    try await authService.signOut()
                                    await MainActor.run {
                                        isSignedIn = false
                                    }
                                } catch {
                                    print("Logout error: \(error.localizedDescription)")
                                }
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
        
        // Load widget order
        loadWidgetOrder()
        
        // Check if user has changed
        let currentUID = UserManager.shared.getCurrentUserIDUnified()
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

            // Start listening to organization settings
            let orgID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
            if !orgID.isEmpty {
                OrganizationService.shared.startListeningToOrganization(organizationID: orgID)
            }

            // Refresh time tracking service and initialize chat manager
            Task {
                await timeTrackingService.refreshUserAndStatus()
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
        
        // NOT clearing homeDestination here. The old code cleared its selected
        // session on every appear, and carrying that forward would mean any
        // re-fire of this onAppear pops the user out of a screen they are
        // reading. The stale-destination case it was really guarding — coming
        // back to Home and having the last screen re-push itself — is handled
        // where it actually happens, on the tab change.
        
        // Apply the saved theme when the app starts or the view appears
        applyAppTheme()
    }
    
    // MARK: - Computed Properties & UI Components
    
    /// The flag banner that floats over the whole shell, not just home.
    ///
    /// It is deliberately a SECOND rendering of the same note: the inline card
    /// inside the scroll (flagNotificationView) can be scrolled past, and this
    /// one cannot be missed. Only this one can be dismissed, and dismissing it
    /// leaves the inline card in place — that pairing is why both exist.
    private var flagNotificationBanner: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(flaggedByName.isEmpty ? "Flag note" : "Flag note from \(flaggedByName)")
                        .font(.headline)
                    Spacer(minLength: 0)
                    Button(action: {
                        withAnimation { isBannerDismissed = true }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss flag note")
                }
                Text(flagNote)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ambientCard(density: .roomy, state: .highlighted,
                         border: .strong(Color.red.opacity(0.55)),
                         glow: .red, fillWidth: true)
            .padding(.horizontal, 16)
            // Clears the floating bar. This banner is bottom-anchored in the same
            // stack, and it was already drawn over the old bar — now that the bar
            // floats and is the only route home on iPad, a banner sitting on top of
            // it would cover navigation rather than just decoration.
            .padding(.bottom, showsTabBar ? TabBarMetrics.clearance + 8 : 24)
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
        FeatureTheme.color(for: id)  // single source of truth — see DesignTokens.swift
    }

    private func loadSchedule() {
        viewModel.fetchUpcomingEvents(employeeName: "")
    }

    // Supabase listener for flag status
    func listenForFlagStatus() {
        // Remove previous listener if exists
        Task {
            await flagChannel?.unsubscribe()
        }

        guard let currentUID = UserManager.shared.getCurrentUserIDUnified() else {
            return
        }

        // Initial fetch
        Task {
            await loadFlagStatusFromSupabase(userId: currentUID)
        }

        // Set up realtime subscription using realtimeV2
        let supabase = SupabaseManager.shared.client
        let channel = supabase.realtimeV2.channel("user_flag_\(currentUID)")

        let changeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "users",
            filter: "id=eq.\(currentUID)"
        )

        Task {
            for await _ in changeStream {
                await loadFlagStatusFromSupabase(userId: currentUID)
            }
        }

        Task {
            await channel.subscribe()
        }

        flagChannel = channel
    }

    @MainActor
    private func loadFlagStatusFromSupabase(userId: String) async {
        let supabase = SupabaseManager.shared.client

        do {
            struct UserFlagData: Decodable {
                let is_flagged: Bool?
                let flag_note: String?
                let flagged_by: String?
                let photo_url: String?
            }

            let response: UserFlagData = try await supabase
                .from("users")
                .select("is_flagged, flag_note, flagged_by, photo_url")
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            self.isFlagged = response.is_flagged ?? false
            self.flagNote = response.flag_note ?? ""

            if let flaggedByID = response.flagged_by, !flaggedByID.isEmpty {
                await loadFlaggedByName(flaggedByID: flaggedByID)
            } else {
                self.flaggedByName = ""
            }

            if let updatedPhotoURL = response.photo_url,
               !updatedPhotoURL.isEmpty,
               updatedPhotoURL != self.storedUserPhotoURL {
                self.storedUserPhotoURL = updatedPhotoURL
            }

            // Reset banner dismissal when flag status changes
            if self.isFlagged && !self.flagNote.isEmpty {
                self.isBannerDismissed = false
            }
        } catch {
            print("Error loading flag status: \(error.localizedDescription)")
        }
    }

    @MainActor
    func loadFlaggedByName(flaggedByID: String) async {
        let supabase = SupabaseManager.shared.client

        do {
            struct UserName: Decodable {
                let first_name: String?
            }

            let response: UserName = try await supabase
                .from("users")
                .select("first_name")
                .eq("id", value: flaggedByID)
                .single()
                .execute()
                .value

            self.flaggedByName = response.first_name ?? ""
        } catch {
            self.flaggedByName = ""
        }
    }
    
    // MARK: - Widget Order Management
    
    private func loadWidgetOrder() {
        let availableWidgets = isIPad ? DashboardWidget.iPadWidgets : DashboardWidget.iPhoneWidgets
        let currentOrderString = isIPad ? iPadWidgetOrderString : widgetOrderString
        
        if currentOrderString.isEmpty {
            // Default order based on device type
            widgetOrder = availableWidgets
        } else {
            // Parse saved order and filter by available widgets
            let savedOrder = currentOrderString.split(separator: ",")
                .compactMap { DashboardWidget(rawValue: String($0)) }
                .filter { availableWidgets.contains($0) }
            
            // Add any new widgets not in saved order
            let missingWidgets = availableWidgets.filter { !savedOrder.contains($0) }
            widgetOrder = savedOrder + missingWidgets
        }
    }
    
    private func saveWidgetOrder() {
        let orderString = widgetOrder.map { $0.rawValue }.joined(separator: ",")
        if isIPad {
            iPadWidgetOrderString = orderString
        } else {
            widgetOrderString = orderString
        }
    }
}

// MARK: - Drop Delegate for Widget Reordering

struct WidgetDropDelegate: DropDelegate {
    let widget: DashboardWidget
    @Binding var widgetOrder: [DashboardWidget]
    @Binding var draggedWidget: DashboardWidget?
    let onReorder: () -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        draggedWidget = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedWidget = draggedWidget,
              draggedWidget != widget,
              let fromIndex = widgetOrder.firstIndex(of: draggedWidget),
              let toIndex = widgetOrder.firstIndex(of: widget) else {
            return
        }
        
        withAnimation(.spring()) {
            widgetOrder.move(fromOffsets: IndexSet(integer: fromIndex),
                           toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }

        onReorder()
    }
}
