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
    @Published var upcomingShifts: [ICSEvent] = []
    @Published var allEvents: [ICSEvent] = [] // Store all events for coworker data
    @Published var isLoadingSchedule: Bool = false
    
    // Weather service and data
    private let weatherService = WeatherService()
    @Published var weatherDataByEvent: [String: WeatherData] = [:] // Key is location-date
    
    // Default employee features – re-orderable by the user.
    let defaultEmployeeFeatures: [FeatureItem] = [
        FeatureItem(id: "photoshootNotes", title: "Photoshoot Notes", systemImage: "note.text", description: "Create and manage notes for your photoshoots"),
        FeatureItem(id: "dailyJobReport", title: "Daily Job Report", systemImage: "doc.text", description: "Submit your daily job report"),
        FeatureItem(id: "myDailyJobReports", title: "My Daily Job Reports", systemImage: "doc.text.magnifyingglass", description: "View and edit your job reports"),
        FeatureItem(id: "mileageReports", title: "Mileage Reports", systemImage: "car.fill", description: "Track your mileage"),
        FeatureItem(id: "schedule", title: "Schedule", systemImage: "calendar", description: "View your upcoming shifts"),
        FeatureItem(id: "locationPhotos", title: "Location Photos", systemImage: "photo.on.rectangle", description: "Manage photos for locations"),
        FeatureItem(id: "sportsShoot", title: "Sports Shoots", systemImage: "sportscourt", description: "Manage sports shoot rosters and images")
    ]
    
    private let employeeOrderKey = "employeeFeatureOrder"
    
    // Full ICS URL from Sling
    private let icsURL = "https://calendar.getsling.com/564097/18fffd515e88999522da2876933d36a9d9d83a7eeca9c07cd58890a8/Sling_Calendar_all.ics"
    
    init() {
        loadEmployeeFeatureOrder()
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
    
    // Function to fetch upcoming events
    func fetchUpcomingEvents(employeeName: String) {
        isLoadingSchedule = true
        upcomingShifts = []
        allEvents = []
        
        guard let url = URL(string: icsURL) else {
            print("Invalid ICS URL")
            isLoadingSchedule = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                print("Error loading ICS: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isLoadingSchedule = false
                }
                return
            }
            
            guard let data = data, let content = String(data: data, encoding: .utf8) else {
                print("Unable to load ICS data")
                DispatchQueue.main.async {
                    self?.isLoadingSchedule = false
                }
                return
            }
            
            // Parse the ICS content
            let allEvents = ICSParser.parseICS(from: content)
            
            // Store all events for coworker data
            DispatchQueue.main.async {
                self?.allEvents = allEvents
            }
            
            // Filter events for the next 2 days and for the specific employee
            let calendar = Calendar.current
            let now = Date()
            let twoDaysFromNow = calendar.date(byAdding: .day, value: 2, to: now) ?? now
            
            let filtered = allEvents.filter { event in
                guard let startDate = event.startDate else { return false }
                return startDate >= now &&
                       startDate <= twoDaysFromNow &&
                       event.employeeName.lowercased() == employeeName.lowercased()
            }
            
            // Sort by start date
            let sorted = filtered.sorted {
                (($0.startDate ?? Date()) < ($1.startDate ?? Date()))
            }
            
            DispatchQueue.main.async {
                self?.upcomingShifts = sorted
                self?.isLoadingSchedule = false
                
                // Load weather data for upcoming shifts
                self?.loadWeatherForEvents(sorted)
            }
        }.resume()
    }
    
    // Load weather data for events
    func loadWeatherForEvents(_ events: [ICSEvent]) {
        for event in events {
            loadWeatherForEvent(event)
        }
    }
    
    // Load weather for a specific event
    func loadWeatherForEvent(_ event: ICSEvent) {
        guard let eventDate = event.startDate,
              let location = event.location,
              !location.isEmpty else {
            return
        }
        
        // Create a unique key for this event
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: eventDate)
        let cacheKey = "\(location)-\(dateString)"
        
        // Check if we already have weather data for this location and date
        if weatherDataByEvent[cacheKey] != nil {
            return
        }
        
        // Get weather data
        weatherService.getWeatherData(for: location, date: eventDate) { [weak self] weatherData, errorMessage in
            if let weatherData = weatherData {
                DispatchQueue.main.async {
                    self?.weatherDataByEvent[cacheKey] = weatherData
                }
            }
        }
    }
    
    // Get weather data for specific event
    func getWeatherForEvent(_ event: ICSEvent) -> WeatherData? {
        guard let eventDate = event.startDate,
              let location = event.location,
              !location.isEmpty else {
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: eventDate)
        let cacheKey = "\(location)-\(dateString)"
        
        return weatherDataByEvent[cacheKey]
    }
}

// MARK: - Compact Event Row for MainEmployeeView

struct CompactEventRow: View {
    let event: ICSEvent
    let weatherData: WeatherData?
    
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
    
    private var colorForPosition: Color {
        if let positionColor = positionColorMap[event.position] {
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
        
        return colorMap[event.position] ?? .blue
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
                    if let start = event.startDate {
                        Text(dateFormatter.string(from: start))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Position label
                    Text(event.position)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(colorForPosition.opacity(0.2))
                        .foregroundColor(colorForPosition)
                        .cornerRadius(12)
                }
                
                Text(event.schoolName)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    if let start = event.startDate, let end = event.endDate {
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
    
    // Fixed manager features
    let managerFeatures: [FeatureItem] = [
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
    
    // State to track which shift is selected for navigation
    @State private var selectedShift: ICSEvent? = nil
    
    // Flag status
    @State private var isFlagged: Bool = false
    @State private var flagNote: String = ""
    @State private var flaggedByName: String = ""
    
    // For navigating to Settings and appearance
    @State private var showSettings = false
    @State private var showThemePicker = false
    
    // Local edit mode for reordering
    @State private var localEditMode: EditMode = .inactive
    
    // Environment
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background with proper flag coloring
                if isFlagged {
                    Color.red.opacity(0.1).ignoresSafeArea()
                } else {
                    backgroundGradient.ignoresSafeArea()
                }
                
                VStack(spacing: 0) {
                    List {
                        // Upcoming schedule section
                        Section(header: Text("Your Schedule (Next 2 Days)")) {
                            if viewModel.isLoadingSchedule {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                            } else if viewModel.upcomingShifts.isEmpty {
                                Text("No upcoming shifts in the next 2 days")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(viewModel.upcomingShifts) { shift in
                                    // Make each shift row clickable
                                    Button(action: {
                                        selectedShift = shift
                                    }) {
                                        CompactEventRow(
                                            event: shift,
                                            weatherData: viewModel.getWeatherForEvent(shift)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            
                            Button("Refresh Schedule") {
                                loadSchedule()
                            }
                        }
                        
                        // Employee Features Section (re-orderable)
                        Section(header: Text("Employee Features")) {
                            ForEach(viewModel.employeeFeatures) { feature in
                                if localEditMode == .active {
                                    // Simple row in edit mode
                                    HStack {
                                        Image(systemName: feature.systemImage)
                                            .foregroundColor(.white)
                                            .frame(width: 30, height: 30)
                                            .background(Circle().fill(featureColorFor(feature.id)))
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(feature.title)
                                                .font(.headline)
                                            Text(feature.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        .padding(.leading, 8)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "line.3.horizontal")
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.vertical, 4)
                                } else {
                                    // Use Button instead of NavigationLink directly
                                    Button(action: {
                                        selectedFeatureID = feature.id
                                    }) {
                                        HStack {
                                            Image(systemName: feature.systemImage)
                                                .foregroundColor(.white)
                                                .frame(width: 30, height: 30)
                                                .background(Circle().fill(featureColorFor(feature.id)))
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(feature.title)
                                                    .font(.headline)
                                                Text(feature.description)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .padding(.leading, 8)
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(.gray)
                                                .font(.caption)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        Button(action: {
                                            withAnimation {
                                                localEditMode = .active
                                            }
                                        }) {
                                            Label("Rearrange Features", systemImage: "arrow.up.arrow.down")
                                        }
                                    }
                                    .onLongPressGesture {
                                        withAnimation {
                                            localEditMode = .active
                                        }
                                    }
                                }
                            }
                            .onMove(perform: viewModel.moveEmployeeFeatures)
                        }
                        
                        // Manager Features Section (fixed order) if user is a manager
                        if storedUserRole == "manager" {
                            Section(header: Text("Management Features")) {
                                ForEach(managerFeatures) { feature in
                                    Button(action: {
                                        selectedFeatureID = feature.id
                                    }) {
                                        HStack {
                                            Image(systemName: feature.systemImage)
                                                .foregroundColor(.white)
                                                .frame(width: 30, height: 30)
                                                .background(Circle().fill(featureColorFor(feature.id)))
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(feature.title)
                                                    .font(.headline)
                                                Text(feature.description)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .padding(.leading, 8)
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(.gray)
                                                .font(.caption)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .refreshable {
                        loadSchedule()
                    }
                }
                
                // Flag notification banner
                if isFlagged && !flagNote.isEmpty {
                    flagNotificationBanner
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
                        destination: PhotoshootNotesView(),
                        tag: "photoshootNotes",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    NavigationLink(
                        destination: DailyJobReportView(),
                        tag: "dailyJobReport",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    NavigationLink(
                        destination: MyJobReportsView(),
                        tag: "myDailyJobReports",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    NavigationLink(
                        destination: MileageReportsView(userName: storedUserFirstName),
                        tag: "mileageReports",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
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
                    
                    // Sports Shoots navigation link
                    NavigationLink(
                        destination: SportsShootListView(),
                        tag: "sportsShoot",
                        selection: $selectedFeatureID
                    ) { EmptyView() }
                    
                    // Manager features navigation links
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
                
                // Hidden navigation link for shift details
                if let shift = selectedShift {
                    NavigationLink(
                        destination: ShiftDetailView(
                            event: shift,
                            allEvents: viewModel.allEvents // Pass ALL events, not just the upcoming ones
                        ),
                        isActive: Binding(
                            get: { selectedShift != nil },
                            set: { if !$0 { selectedShift = nil } }
                        )
                    ) { EmptyView() }
                    .hidden()
                }
            }
            .navigationBarTitle("", displayMode: .inline)
            .toolbar {
                // Left toolbar: optional logo
                ToolbarItem(placement: .navigationBarLeading) {
                    Image("employeeStaff")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 44)
                }
                
                // Right toolbar: edit/done button or profile info
                ToolbarItem(placement: .navigationBarTrailing) {
                    if localEditMode == .active {
                        Button("Done") {
                            withAnimation { localEditMode = .inactive }
                            viewModel.saveEmployeeFeatureOrder()
                        }
                    } else {
                        HStack(spacing: 12) {
                            Text(storedUserFirstName).font(.headline)
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
            }
            .environment(\.editMode, $localEditMode)
            .onAppear {
                if #available(iOS 16.0, *) {
                    UITableView.appearance().backgroundColor = .clear
                }
                listenForFlagStatus() // Listen for Firebase updates
                loadSchedule()
                
                // Reset selections when view appears
                selectedFeatureID = nil
                selectedShift = nil
                
                // Apply the saved theme when the app starts or the view appears
                applyAppTheme()
            }
            .onDisappear {
                viewModel.saveEmployeeFeatureOrder()
            }
            .sheet(isPresented: $showThemePicker) {
                themePickerSheet
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
                        // Hide the flag temporarily in the UI
                        withAnimation {
                            flagNote = ""
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
        case "photoshootNotes": return .purple
        case "dailyJobReport": return .blue
        case "myDailyJobReports": return .green
        case "mileageReports": return .orange
        case "schedule": return .red
        case "locationPhotos": return .pink
        case "sportsShoot": return .indigo  // Color for Sports Shoot
        case "flagUser": return .red
        case "unflagUser": return .green
        case "managerMileage": return .blue
        case "stats": return .indigo
        case "galleryCreator": return .green
        case "jobBoxTracker": return .teal  // Color for Job Box Tracker
        default: return .gray
        }
    }
    
    private func loadSchedule() {
        let fullName = "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.fetchUpcomingEvents(employeeName: fullName)
    }
    
    // Firebase listener for flag status
    func listenForFlagStatus() {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            print("No current user UID.")
            return
        }
        let db = Firestore.firestore()
        db.collection("users").document(currentUID)
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
                    isFlagged = boolVal
                } else if let intVal = data["isFlagged"] as? Int {
                    isFlagged = (intVal == 1)
                } else {
                    isFlagged = false
                }
                flagNote = data["flagNote"] as? String ?? ""
                if let flaggedByID = data["flaggedBy"] as? String, !flaggedByID.isEmpty {
                    loadFlaggedByName(flaggedByID: flaggedByID)
                } else {
                    flaggedByName = ""
                }
                if let updatedPhotoURL = data["photoURL"] as? String,
                   !updatedPhotoURL.isEmpty,
                   updatedPhotoURL != storedUserPhotoURL {
                    storedUserPhotoURL = updatedPhotoURL
                }
            }
    }
    
    func loadFlaggedByName(flaggedByID: String) {
        let db = Firestore.firestore()
        db.collection("users").document(flaggedByID).getDocument { snapshot, error in
            if let error = error {
                print("Error fetching flaggedBy user: \(error.localizedDescription)")
                flaggedByName = ""
                return
            }
            guard let data = snapshot?.data() else {
                flaggedByName = ""
                return
            }
            flaggedByName = data["firstName"] as? String ?? ""
        }
    }
}
