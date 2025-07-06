import SwiftUI
import Firebase
import FirebaseFirestore
import MessageUI
import MapKit
import CoreLocation

// MARK: - Model Structs

struct CoworkerProfile: Identifiable {
    let id: String
    let name: String
    let photoURL: String
}

struct CoworkerContactInfo: Identifiable {
    let id: String
    let name: String
    let phoneNumber: String
}

struct TravelPlan {
    var travelDuration: TimeInterval = 0
    var readyTime: TimeInterval = 0
    var suggestedLeaveTime: Date?
    var suggestedWakeupTime: Date?
    var arrivalTime: Date?
    var isCalculating: Bool = false
    var errorMessage: String = ""
}

struct LocationPhoto: Identifiable, Hashable {
    var id: String { url }
    let url: String
    let label: String
}

// MARK: - Main View

struct ShiftDetailView: View {
    @State private var session: Session
    @State private var allSessions: [Session]
    let currentUserID: String?
    
    // Primary initializer for Session
    init(session: Session, allSessions: [Session], currentUserID: String?) {
        self._session = State(initialValue: session)
        self._allSessions = State(initialValue: allSessions)
        self.currentUserID = currentUserID
    }
    
    // State properties
    @State private var coworkerProfiles: [CoworkerProfile] = []
    @State private var coworkerContacts: [CoworkerContactInfo] = []
    @State private var isShowingMessageComposer = false
    @State private var messageBody: String = ""
    @State private var isLoadingContacts = false
    @State private var employeeProfile: CoworkerProfile? = nil
    @State private var locationPhotos: [LocationPhoto] = []
    @State private var weatherData: WeatherData?
    @State private var weatherErrorMessage: String?
    @State private var isLoadingWeather: Bool = false
    @State private var travelPlan = TravelPlan()
    @State private var userHomeAddress: String = ""
    @State private var schoolAddress: String = ""
    @State private var errorMessage: String = ""
    @State private var showingMapsOptions = false
    @State private var showingShareSheet = false
    @State private var showingAddToCalendar = false
    @State private var scrollOffset: CGFloat = 0
    
    // Job box state
    @State private var jobBoxes: [JobBox] = []
    @State private var jobBoxListener: ListenerRegistration?
    @State private var latestJobBoxStatus: JobBoxStatus = .unknown
    @State private var latestJobBoxScannedBy: String = ""
    @State private var latestJobBoxTimestamp: Date?
    
    // State for photo detail management
    @State private var selectedPhoto: LocationPhoto? = nil
    @State private var showingPhotoDetail = false
    
    // Real-time listener
    @State private var sessionListener: ListenerRegistration?
    
    // Services
    private let weatherService = WeatherService()
    private let sessionService = SessionService.shared
    
    var body: some View {
        ZStack(alignment: .top) {
            // Fixed header at the top
            headerView
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .zIndex(1)
            
            // Scrollable content below the fixed header
            ScrollView {
                VStack(spacing: 16) {
                    // Minimal padding to create slight separation from header
                    Color.clear.frame(height: 10)
                    
                    // Action buttons
                    actionButtonsRow
                        .padding(.vertical, 8)
                    
                    // Shift details
                    VStack(spacing: 8) {
                        iconRow(systemName: "person.fill",
                                label: "Employee",
                                value: displayEmployeeName)
                        
                        if let startDate = session.startDate {
                            iconRow(systemName: "calendar",
                                    label: "Date",
                                    value: formattedFullDate)
                        }
                        
                        if let start = session.startDate, let end = session.endDate {
                            iconRow(systemName: "clock",
                                    label: "Time",
                                    value: timeRangeString)
                            
                            iconRow(systemName: "hourglass",
                                    label: "Duration",
                                    value: shiftDurationString(start: start, end: end))
                        }
                        
                        if let location = session.location, !location.isEmpty {
                            iconRow(systemName: "mappin.and.ellipse",
                                    label: "Location",
                                    value: location)
                        }
                        
                        iconRow(systemName: "camera.fill",
                                label: "Position",
                                value: session.position)
                        
                        iconRow(systemName: "person.2.fill",
                                label: "Coworkers",
                                value: "\(otherEmployeesSameJob().count)")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                    
                    
                    // Coworker photos
                    if !coworkerProfiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coworkers")
                                .font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(coworkerProfiles) { coworker in
                                        coworkerPhotoView(coworker)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Job Box Status section with pill shapes and full width
                    if latestJobBoxStatus != .unknown {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Job Box Status")
                                .font(.headline)
                            
                            // Status indicators as pills in a centered HStack
                            HStack(spacing: 8) {
                                let stepsCompleted = statusToStep(latestJobBoxStatus)
                                
                                Spacer(minLength: 0) // Add spacer for centering
                                
                                // Each step as a pill shape
                                VStack(spacing: 2) {
                                    ZStack {
                                        Capsule() // Pill shape instead of Circle
                                            .fill(getStepColor(isActive: stepsCompleted >= 1, isCompleted: stepsCompleted > 1))
                                            .frame(height: 24) // Fixed height
                                            .frame(maxWidth: .infinity) // Fill available width
                                        
                                        if stepsCompleted > 1 {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        } else {
                                            Text("1")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(stepsCompleted >= 1 ? .white : .gray)
                                        }
                                    }
                                    Text("Packed")
                                        .font(.caption2)
                                        .fontWeight(stepsCompleted >= 1 ? .medium : .regular)
                                        .foregroundColor(stepsCompleted >= 1 ? .primary : .gray)
                                }
                                
                                VStack(spacing: 2) {
                                    ZStack {
                                        Capsule()
                                            .fill(getStepColor(isActive: stepsCompleted >= 2, isCompleted: stepsCompleted > 2))
                                            .frame(height: 24)
                                            .frame(maxWidth: .infinity)
                                        
                                        if stepsCompleted > 2 {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        } else {
                                            Text("2")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(stepsCompleted >= 2 ? .white : .gray)
                                        }
                                    }
                                    Text("Picked Up")
                                        .font(.caption2)
                                        .fontWeight(stepsCompleted >= 2 ? .medium : .regular)
                                        .foregroundColor(stepsCompleted >= 2 ? .primary : .gray)
                                }
                                
                                VStack(spacing: 2) {
                                    ZStack {
                                        Capsule()
                                            .fill(getStepColor(isActive: stepsCompleted >= 3, isCompleted: stepsCompleted > 3))
                                            .frame(height: 24)
                                            .frame(maxWidth: .infinity)
                                        
                                        if stepsCompleted > 3 {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        } else {
                                            Text("3")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(stepsCompleted >= 3 ? .white : .gray)
                                        }
                                    }
                                    Text("Left Job")
                                        .font(.caption2)
                                        .fontWeight(stepsCompleted >= 3 ? .medium : .regular)
                                        .foregroundColor(stepsCompleted >= 3 ? .primary : .gray)
                                }
                                
                                VStack(spacing: 2) {
                                    ZStack {
                                        Capsule()
                                            .fill(getStepColor(isActive: stepsCompleted >= 4, isCompleted: stepsCompleted >= 4))
                                            .frame(height: 24)
                                            .frame(maxWidth: .infinity)
                                        
                                        if stepsCompleted >= 4 {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        } else {
                                            Text("4")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(stepsCompleted >= 4 ? .white : .gray)
                                        }
                                    }
                                    Text("Turned In")
                                        .font(.caption2)
                                        .fontWeight(stepsCompleted >= 4 ? .medium : .regular)
                                        .foregroundColor(stepsCompleted >= 4 ? .primary : .gray)
                                }
                                
                                Spacer(minLength: 0) // Add spacer for centering
                            }
                            .padding(.horizontal, 4) // Small horizontal padding inside the HStack
                            
                            // Combine last scanned info in one row with smaller fonts
                            if !latestJobBoxScannedBy.isEmpty {
                                HStack(spacing: 4) {
                                    Text("Last scanned by:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(latestJobBoxScannedBy)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    
                                    if let timestamp = latestJobBoxTimestamp {
                                        Text("•")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("Scan time:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(formatTimestamp(timestamp))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .padding(.horizontal, 16) // Match the outside padding of the card below
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity) // Ensure it fills the full width
                    }
                    
                    // Session notes (from session.description)
                    if let sessionNotes = session.description, !sessionNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Session Notes")
                                .font(.headline)
                            Text(sessionNotes)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    
                    // Photographer notes (from photographer array)
                    if let userInfo = currentUserPhotographerInfo, !userInfo.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Personal Notes")
                                .font(.headline)
                            Text(userInfo.notes)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    
                    // Weather section
                    weatherSection
                    
                    // Travel planning section
                    travelPlanningSection
                    
                    // Location photos
                    if !locationPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location Photos")
                                .font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(locationPhotos) { photo in
                                        locationPhotoView(photo)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Spacer(minLength: 30)
                }
                .padding()
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("scroll")).minY)
                })
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            .padding(.top, 80)
        }
        .navigationTitle("Shift Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadEmployeeProfile()
            loadCoworkerPhotos()
            loadLocationPhotos()
            loadUserHomeAddress()
            loadSchoolAddress()
            loadWeatherData()
            startJobBoxListener()
            setupNotificationObserver()
            startSessionListener() // Start real-time updates
        }
        .onDisappear {
            // Remove the job box listener
            jobBoxListener?.remove()
            // Remove the session listener
            sessionListener?.remove()
            // Remove notification observer
            NotificationCenter.default.removeObserver(self)
        }
        .alert(isPresented: .constant(!errorMessage.isEmpty)) {
            Alert(title: Text("Error"),
                  message: Text(errorMessage),
                  dismissButton: .default(Text("OK")) {
                      errorMessage = ""
                  })
        }
        .actionSheet(isPresented: $showingMapsOptions) {
            ActionSheet(
                title: Text("Get Directions"),
                message: Text("Choose a maps application"),
                buttons: [
                    .default(Text("Apple Maps")) {
                        openInAppleMaps()
                    },
                    .default(Text("Google Maps")) {
                        openInGoogleMaps()
                    },
                    .cancel()
                ]
            )
        }
        .sheet(isPresented: $isShowingMessageComposer) {
            messageComposerView
        }
        .sheet(isPresented: $showingPhotoDetail, onDismiss: {
            // Reset the selected photo when sheet is dismissed
            selectedPhoto = nil
        }) {
            if let photo = selectedPhoto {
                PhotoDetailView(imageURL: photo.url, label: photo.label)
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        HStack(alignment: .center, spacing: 16) {
            // Session info
            VStack(alignment: .leading, spacing: 4) {
                Text(session.schoolName)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let start = session.startDate, let end = session.endDate {
                    Text("\(dateFormatter.string(from: start))")
                        .font(.headline)
                    
                    Text("\(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Employee Profile Photo
            if let profile = employeeProfile, !profile.photoURL.isEmpty {
                AsyncImage(url: URL(string: profile.photoURL)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    case .failure(_):
                        Image(systemName: "person.crop.circle.badge.exclam")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "person.circle")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.gray)
            }
        }
    }
    
    // Action Buttons Row
    private var actionButtonsRow: some View {
        HStack(spacing: 0) {
            // Directions Button
            if let _ = session.location, !session.location!.isEmpty {
                ActionButton(
                    title: "Directions",
                    systemImage: "map.fill",
                    action: {
                        showingMapsOptions = true
                    }
                )
            }
            
            // Message Coworkers Button
            ActionButton(
                title: "Message Coworkers",
                systemImage: "message.fill",
                action: {
                    messageCoworkers()
                }
            )
            
            // Share Button
            ActionButton(
                title: "Share",
                systemImage: "square.and.arrow.up",
                action: {
                    shareShift()
                }
            )
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // Weather section
    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "thermometer.sun")
                    .font(.title3)
                    .foregroundColor(.orange)
                if let sessionDate = session.startDate {
                    Text("Weather Forecast for \(formatDateForDisplay(sessionDate))")
                        .font(.headline)
                } else {
                    Text("Weather Forecast")
                        .font(.headline)
                }
                Spacer()
                
                if isLoadingWeather {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if let weather = weatherData {
                WeatherBar(weather: weather, errorMessage: weatherErrorMessage)
            } else if !isLoadingWeather {
                Button(action: {
                    loadWeatherData()
                }) {
                    HStack {
                        Spacer()
                        Text("Load Weather Forecast")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    // Helper function to format date for display
    private func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    // Format timestamp for display
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    // Travel planning section
    private var travelPlanningSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "alarm.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Travel Planning")
                    .font(.headline)
                Spacer()
                
                if travelPlan.isCalculating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 8)
                } else {
                    Button(action: {
                        calculateTravelPlan()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                    }
                    .padding(.trailing, 8)
                }
            }
            
            if !travelPlan.errorMessage.isEmpty {
                Text(travelPlan.errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            } else if travelPlan.isCalculating {
                HStack {
                    Spacer()
                    Text("Calculating travel times...")
                    Spacer()
                }
                .font(.subheadline)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else if let leave = travelPlan.suggestedLeaveTime, let arrival = travelPlan.arrivalTime {
                VStack(spacing: 12) {
                    // Only show wake-up time if ready time is available and this is the first shift
                    if let wakeup = travelPlan.suggestedWakeupTime, travelPlan.readyTime > 0, isFirstShiftOfDay() {
                        HStack {
                            Image(systemName: "bed.double.fill")
                                .frame(width: 30)
                                .foregroundColor(.blue)
                            Text("Wake up at:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(shortTimeFormatter.string(from: wakeup))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "figure.walk")
                            .frame(width: 30)
                            .foregroundColor(.green)
                        Text("Leave by:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(shortTimeFormatter.string(from: leave))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.down.to.line")
                            .frame(width: 30)
                            .foregroundColor(.orange)
                        Text("Arrive at:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(shortTimeFormatter.string(from: arrival))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    // Display travel duration
                    HStack {
                        Image(systemName: "car.fill")
                            .frame(width: 30)
                            .foregroundColor(.red)
                        Text("Travel time:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatDuration(travelPlan.travelDuration))
                            .font(.subheadline)
                    }
                    
                    // Display ready time only if it's set and this is the first shift
                    if travelPlan.readyTime > 0 && isFirstShiftOfDay() {
                        HStack {
                            Image(systemName: "clock.fill")
                                .frame(width: 30)
                                .foregroundColor(.purple)
                            Text("Getting ready:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatDuration(travelPlan.readyTime))
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else {
                Button(action: {
                    calculateTravelPlan()
                }) {
                    HStack {
                        Spacer()
                        Text("Calculate Travel Plan")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private var messageComposerView: some View {
        VStack(spacing: 20) {
            if isLoadingContacts {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading contact information...")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if MFMessageComposeViewController.canSendText() {
                MessageComposeView(
                    recipients: coworkerContacts.map { $0.phoneNumber },
                    body: messageBody,
                    isShowing: $isShowingMessageComposer
                )
            } else {
                Text("Messaging is not available on this device")
                    .font(.headline)
                    .padding(.top, 30)
                
                if coworkerContacts.isEmpty {
                    Text("No coworker phone numbers found")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Text("Coworker phone numbers:")
                        .font(.subheadline)
                        .padding(.top, 10)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(coworkerContacts) { contact in
                                HStack {
                                    Text(contact.name)
                                        .font(.body)
                                    Spacer()
                                    Text(contact.phoneNumber)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 20)
                                Divider()
                            }
                        }
                        .padding(.vertical)
                    }
                    .frame(height: 200)
                }
                
                Button("Close") {
                    isShowingMessageComposer = false
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
        }
        .padding()
    }
    
    // MARK: - Reusable Components
    
    // Button for action row
    struct ActionButton: View {
        let title: String
        let systemImage: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.system(size: 22))
                    Text(title)
                        .font(.caption)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
        }
    }
    
    private func iconRow(systemName: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: systemName)
                .frame(width: 24)
                .foregroundColor(colorForPosition)
            Text(label + ":")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
    
    private func coworkerPhotoView(_ profile: CoworkerProfile) -> some View {
        // Check if this is the coworker who scanned the job box
        let shouldHighlight = isMatchingUser(profileName: profile.name, scannedByName: latestJobBoxScannedBy)
        
        return VStack(spacing: 4) {
            ZStack {
                if !profile.photoURL.isEmpty {
                    AsyncImage(url: URL(string: profile.photoURL)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        case .failure(_):
                            // Show initials when image fails to load
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: 60, height: 60)
                                
                                Text(getInitials(from: profile.name))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    // Show initials instead of generic icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 60, height: 60)
                        
                        Text(getInitials(from: profile.name))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                // Show highlight if this person scanned the job box
                if shouldHighlight {
                    Circle()
                        .stroke(getHighlightColor(), lineWidth: 3)
                        .frame(width: 66, height: 66)
                }
            }
            
            Text(profile.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 60)
        }
    }
    
    // Using a better approach for location photo view with proper state management
    private func locationPhotoView(_ photo: LocationPhoto) -> some View {
        VStack(spacing: 4) {
            Button(action: {
                // First set the selected photo
                selectedPhoto = photo
                // Then show the photo detail view after a small delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showingPhotoDetail = true
                }
            }) {
                AsyncImage(url: URL(string: photo.url)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .cornerRadius(8)
                    case .failure(_):
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .cornerRadius(8)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .overlay(
                    // Magnifying glass icon in the corner to indicate the photo is zoomable
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(4),
                    alignment: .bottomTrailing
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(photo.label)
                .font(.caption)
                .lineLimit(1)
        }
    }
    
    // Job Box Status components
    
    // Convert JobBoxStatus to step number (1-4)
    private func statusToStep(_ status: JobBoxStatus) -> Int {
        switch status {
        case .packed:
            return 1
        case .pickedUp:
            return 2
        case .leftJob:
            return 3
        case .turnedIn:
            return 4
        case .unknown:
            return 0
        }
    }
    
    // A view for each step in the job box status flow
    private func statusStep(number: Int, title: String, isActive: Bool, isCompleted: Bool) -> some View {
        VStack(spacing: 4) {
            // Circle with number or checkmark
            ZStack {
                Circle()
                    .fill(getStepColor(isActive: isActive, isCompleted: isCompleted))
                    .frame(width: 30, height: 30)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isActive ? .white : .gray)
                }
            }
            
            // Step title
            Text(title)
                .font(.caption)
                .fontWeight(isActive ? .medium : .regular)
                .foregroundColor(isActive ? .primary : .gray)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    // Get the color for a step based on its state
    private func getStepColor(isActive: Bool, isCompleted: Bool) -> Color {
        if isCompleted {
            return .green
        } else if isActive {
            return .blue
        } else {
            return Color(.systemGray4)
        }
    }
    
    // Get highlight color based on job box status
    private func getHighlightColor() -> Color {
        switch latestJobBoxStatus {
        case .pickedUp:
            return .blue
        case .leftJob:
            return .orange
        case .turnedIn:
            return .green
        default:
            return .gray
        }
    }
    
    // MARK: - Job Box Methods
    
    // Start listening for job box updates
    private func startJobBoxListener() {
        // Remove any existing listener
        jobBoxListener?.remove()
        
        // Convert Session to ICSEvent for JobBoxService compatibility
        let compatibilityEvent = ICSEvent(
            id: session.id,
            summary: "\(session.employeeName) - \(session.position) - \(session.schoolName)",
            startDate: session.startDate,
            endDate: session.endDate,
            description: session.description,
            location: session.location,
            url: nil
        )
        
        // Start a new listener
        jobBoxListener = JobBoxService.shared.listenForJobBoxes(forShift: compatibilityEvent) { jobBoxes in
            DispatchQueue.main.async {
                self.jobBoxes = jobBoxes
                
                // Find the latest job box record based on timestamp
                if let latestBox = jobBoxes.sorted(by: { $0.timestamp > $1.timestamp }).first {
                    self.latestJobBoxStatus = latestBox.status
                    self.latestJobBoxScannedBy = latestBox.scannedBy
                    self.latestJobBoxTimestamp = latestBox.timestamp // Store the timestamp
                }
            }
        }
    }
    
    // Set up notification observer for job box updates
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("didReceiveJobBoxNotification"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let shiftUid = userInfo["shiftUid"] as? String else {
                return
            }
            
            // Check if the notification is for this shift
            let currentShiftUid = JobBoxService.generateCustomShiftID(
                schoolName: self.session.schoolName,
                date: self.session.startDate ?? Date()
            )
            
            if shiftUid == currentShiftUid {
                // Process the notification to update UI
                if let notificationInfo = JobBoxService.shared.processJobBoxNotification(userInfo: userInfo) {
                    self.latestJobBoxStatus = notificationInfo.status
                    self.latestJobBoxScannedBy = notificationInfo.scannedBy
                    
                    // Use the current time for the timestamp if not provided in the notification
                    // In a production app, we would ideally get this from the notification
                    self.latestJobBoxTimestamp = Date()
                }
            }
        }
    }
    
    // MARK: - Properties
    
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
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var shortTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }
    
    private var formattedFullDate: String {
        guard let start = session.startDate else { return "" }
        return dateFormatter.string(from: start)
    }
    
    private var timeRangeString: String {
        guard let start = session.startDate, let end = session.endDate else { return "" }
        return "\(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))"
    }
    
    // Get the current user's photographer info from the session
    private var currentUserPhotographerInfo: (name: String, notes: String)? {
        guard let userID = currentUserID else { return nil }
        return session.getPhotographerInfo(for: userID)
    }
    
    private var displayEmployeeName: String {
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
    
    // MARK: - Helper Methods
    
    private func shiftDurationString(start: Date, end: Date) -> String {
        let interval = end.timeIntervalSince(start)
        if interval <= 0 { return "0m" }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours) hr \(mins) min"
            }
        }
    }
    
    private func isFirstShiftOfDay() -> Bool {
        guard let currentShiftDate = session.startDate else { return false }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: currentShiftDate)
        
        // Find all sessions for the same employee on the same day
        let employeeSessions = allSessions.filter { evt in
            guard let eventDate = evt.startDate,
                  evt.employeeName == self.session.employeeName else {
                return false
            }
            
            // Check if the session is on the same day
            return calendar.isDate(eventDate, inSameDayAs: currentShiftDate)
        }
        
        // Sort sessions by start time
        let sortedSessions = employeeSessions.sorted { (a, b) -> Bool in
            guard let aStart = a.startDate, let bStart = b.startDate else {
                return false
            }
            return aStart < bStart
        }
        
        // Check if the current session is the first one
        if let firstSession = sortedSessions.first,
           let firstSessionDate = firstSession.startDate,
           let currentSessionDate = session.startDate {
            
            // Compare times using timeIntervalSince1970 to handle possible millisecond differences
            let isFirst = abs(firstSessionDate.timeIntervalSince1970 - currentSessionDate.timeIntervalSince1970) < 60 // Within a minute
            return isFirst
        }
        
        return true // If we can't determine, assume it's the first shift
    }
    
    private func loadEmployeeProfile() {
        // Use current user's ID directly instead of querying by name
        guard let userID = currentUserID else {
            print("🔐 Cannot load employee profile: no current user ID")
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users")
            .document(userID)
            .getDocument { snapshot, error in
                if let error = error {
                    print("⚠️ Employee profile unavailable: \(error.localizedDescription)")
                    // Continue without employee profile photo
                    return
                }
                
                if let data = snapshot?.data() {
                    let photoURL = data["photoURL"] as? String ?? ""
                    let firstName = data["firstName"] as? String ?? ""
                    let lastName = data["lastName"] as? String ?? ""
                    let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                    
                    DispatchQueue.main.async {
                        self.employeeProfile = CoworkerProfile(
                            id: userID,
                            name: fullName.isEmpty ? self.displayEmployeeName : fullName,
                            photoURL: photoURL
                        )
                    }
                } else {
                    DispatchQueue.main.async {
                        self.employeeProfile = CoworkerProfile(
                            id: userID,
                            name: self.displayEmployeeName,
                            photoURL: ""
                        )
                    }
                }
            }
    }
    
    private func loadCoworkerPhotos() {
        coworkerProfiles = []
        
        // Get all photographers from the session (excluding current user)
        guard let currentUserID = currentUserID else { return }
        
        // Get organization ID to comply with security rules
        let orgID = UserManager.shared.getCachedOrganizationID()
        guard !orgID.isEmpty else {
            print("🔐 Cannot load coworker photos: no organization ID found")
            return
        }
        
        let db = Firestore.firestore()
        
        for photographer in session.photographers {
            guard let photographerID = photographer["id"] as? String,
                  let photographerName = photographer["name"] as? String,
                  photographerID != currentUserID else {
                continue // Skip current user
            }
            
            // Load actual photo URL from users collection
            db.collection("users")
                .document(photographerID)
                .getDocument { snapshot, error in
                    if let error = error {
                        print("⚠️ Coworker photo unavailable: \(error.localizedDescription)")
                        // Create profile with initials fallback
                        DispatchQueue.main.async {
                            let profile = CoworkerProfile(
                                id: photographerID,
                                name: photographerName,
                                photoURL: ""
                            )
                            if !self.coworkerProfiles.contains(where: { $0.id == photographerID }) {
                                self.coworkerProfiles.append(profile)
                            }
                        }
                        return
                    }
                    
                    let photoURL = snapshot?.data()?["photoURL"] as? String ?? ""
                    DispatchQueue.main.async {
                        let profile = CoworkerProfile(
                            id: photographerID,
                            name: photographerName,
                            photoURL: photoURL
                        )
                        if !self.coworkerProfiles.contains(where: { $0.id == photographerID }) {
                            self.coworkerProfiles.append(profile)
                        }
                    }
                }
        }
        
        // Also check for coworkers from other sessions on the same day/location
        let calendar = Calendar.current
        guard let sessionDate = session.startDate else { return }
        let sessionDay = calendar.startOfDay(for: sessionDate)
        
        for otherSession in allSessions {
            guard let otherSessionDate = otherSession.startDate,
                  otherSession.id != session.id,
                  calendar.startOfDay(for: otherSessionDate) == sessionDay,
                  otherSession.schoolName == session.schoolName else {
                continue
            }
            
            // Add photographers from other sessions on same day
            for photographer in otherSession.photographers {
                guard let photographerID = photographer["id"] as? String,
                      let photographerName = photographer["name"] as? String,
                      photographerID != currentUserID,
                      !coworkerProfiles.contains(where: { $0.id == photographerID }) else {
                    continue
                }
                
                // Load actual photo URL from users collection for other session photographers too
                db.collection("users")
                    .document(photographerID)
                    .getDocument { snapshot, error in
                        if let error = error {
                            print("⚠️ Other session coworker photo unavailable: \(error.localizedDescription)")
                            // Create profile with initials fallback
                            DispatchQueue.main.async {
                                let profile = CoworkerProfile(
                                    id: photographerID,
                                    name: photographerName,
                                    photoURL: ""
                                )
                                if !self.coworkerProfiles.contains(where: { $0.id == photographerID }) {
                                    self.coworkerProfiles.append(profile)
                                }
                            }
                            return
                        }
                        
                        let photoURL = snapshot?.data()?["photoURL"] as? String ?? ""
                        DispatchQueue.main.async {
                            let profile = CoworkerProfile(
                                id: photographerID,
                                name: photographerName,
                                photoURL: photoURL
                            )
                            if !self.coworkerProfiles.contains(where: { $0.id == photographerID }) {
                                self.coworkerProfiles.append(profile)
                            }
                        }
                    }
            }
        }
    }
    
    private func loadLocationPhotos() {
        let db = Firestore.firestore()
        
        // Get organization ID to comply with security rules
        UserManager.shared.getCurrentUserOrganizationID { organizationID in
            guard let orgID = organizationID else {
                print("🔐 Cannot load location photos: no organization ID found")
                return
            }
            
            db.collection("schools")
                .whereField("organizationID", isEqualTo: orgID)
                .whereField("value", isEqualTo: self.session.schoolName)
                .getDocuments { snapshot, error in
                    if let error = error {
                        print("⚠️ Location photos unavailable: \(error.localizedDescription)")
                        // Don't show error to user, just fail silently for location photos
                        return
                    }
                    guard let docs = snapshot?.documents,
                          let doc = docs.first,
                          let photoDicts = doc.data()["locationPhotos"] as? [[String: String]] else {
                        return
                    }
                    // Map each dictionary to a LocationPhoto.
                    let photos = photoDicts.compactMap { dict -> LocationPhoto? in
                        if let url = dict["url"], let label = dict["label"] {
                            return LocationPhoto(url: url, label: label)
                        }
                        return nil
                    }
                    DispatchQueue.main.async {
                        self.locationPhotos = photos
                    }
                }
        }
    }
    
    private func loadUserHomeAddress() {
        guard let userId = Auth.auth().currentUser?.uid else {
            travelPlan.errorMessage = "User not signed in"
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                print("⚠️ User home address unavailable: \(error.localizedDescription)")
                // Continue without user home address data
                return
            }
            
            if let data = snapshot?.data() {
                let homeAddress = data["homeAddress"] as? String ?? ""
                
                // Check if readyTime exists and is greater than zero
                if let readyTimeMinutes = data["readyTime"] as? Double, readyTimeMinutes > 0 {
                    self.travelPlan.readyTime = readyTimeMinutes * 60 // Convert to seconds
                } else {
                    self.travelPlan.readyTime = 0
                }
                
                self.userHomeAddress = homeAddress
                
                // Calculate travel plan if we already have the school address
                if !self.schoolAddress.isEmpty {
                    self.calculateTravelPlan()
                }
            }
        }
    }
    
    private func loadSchoolAddress() {
        let db = Firestore.firestore()
        
        // Get organization ID to comply with security rules
        UserManager.shared.getCurrentUserOrganizationID { organizationID in
            guard let orgID = organizationID else {
                print("🔐 Cannot load school address: no organization ID found")
                self.travelPlan.errorMessage = "Could not load school data"
                return
            }
            
            db.collection("schools")
                .whereField("organizationID", isEqualTo: orgID)
                .whereField("value", isEqualTo: self.session.schoolName)
                .getDocuments { snapshot, error in
                    if let error = error {
                        self.travelPlan.errorMessage = "Could not load school data"
                        return
                    }
                    
                    if let doc = snapshot?.documents.first {
                        let data = doc.data()
                        
                        // First try to use coordinates field for maximum accuracy
                        if let coordinates = data["coordinates"] as? String, !coordinates.isEmpty {
                            self.schoolAddress = coordinates
                        }
                        // Fall back to schoolAddress field
                        else if let address = data["schoolAddress"] as? String, !address.isEmpty {
                            self.schoolAddress = address
                        }
                        // Finally fall back to session location
                        else if let location = self.session.location, !location.isEmpty {
                            self.schoolAddress = location
                        }
                        else {
                            self.travelPlan.errorMessage = "School location not found"
                            return
                        }
                        
                        // Calculate travel plan if we already have the user home address
                        if !self.userHomeAddress.isEmpty {
                            self.calculateTravelPlan()
                        }
                    } else if let location = self.session.location, !location.isEmpty {
                        // Use the session location if no school document found
                        self.schoolAddress = location
                        
                        if !self.userHomeAddress.isEmpty {
                            self.calculateTravelPlan()
                        }
                    } else {
                        self.travelPlan.errorMessage = "School location not found"
                    }
                }
        }
    }
    
    private func loadWeatherData() {
        guard let sessionDate = session.startDate else { return }
        
        // Only load weather if the session is within the next 7 days
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysFromNow = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        
        if sessionDate > sevenDaysFromNow {
            weatherErrorMessage = "Weather forecast only available for next 7 days"
            return // Don't attempt to load weather for dates more than 7 days away
        }
        
        isLoadingWeather = true
        
        // Load school data to get the best location for weather
        loadSchoolDataForWeather { latitude, longitude, addressFallback in
            // Use coordinates if available for maximum accuracy
            if let lat = latitude, let lng = longitude {
                self.weatherService.getWeatherData(latitude: lat, longitude: lng, date: sessionDate) { weatherData, errorMessage in
                    DispatchQueue.main.async {
                        self.weatherData = weatherData
                        self.weatherErrorMessage = errorMessage
                        self.isLoadingWeather = false
                    }
                }
            }
            // Use address if coordinates not available
            else if !addressFallback.isEmpty {
                self.weatherService.getWeatherData(for: addressFallback, date: sessionDate) { weatherData, errorMessage in
                    DispatchQueue.main.async {
                        self.weatherData = weatherData
                        self.weatherErrorMessage = errorMessage
                        self.isLoadingWeather = false
                    }
                }
            }
            // Final fallback to school name
            else {
                self.weatherService.getWeatherData(for: self.session.schoolName, date: sessionDate) { weatherData, errorMessage in
                    DispatchQueue.main.async {
                        self.weatherData = weatherData
                        self.weatherErrorMessage = errorMessage
                        self.isLoadingWeather = false
                    }
                }
            }
        }
    }
    
    private func loadSchoolDataForWeather(completion: @escaping (Double?, Double?, String) -> Void) {
        let db = Firestore.firestore()
        
        // Get organization ID to comply with security rules
        UserManager.shared.getCurrentUserOrganizationID { organizationID in
            guard let orgID = organizationID else {
                print("🔐 Cannot load school data for weather: no organization ID found")
                completion(nil, nil, "")
                return
            }
            
            db.collection("schools")
                .whereField("organizationID", isEqualTo: orgID)
                .whereField("value", isEqualTo: self.session.schoolName)
                .getDocuments { snapshot, error in
                    if let error = error {
                        print("⚠️ School data for weather unavailable: \(error.localizedDescription)")
                        completion(nil, nil, "")
                        return
                    }
                    
                    if let doc = snapshot?.documents.first {
                        let data = doc.data()
                        
                        // First priority: Use coordinates field for maximum accuracy
                        if let coordinates = data["coordinates"] as? String, !coordinates.isEmpty,
                           let parsedCoords = self.parseCoordinateString(coordinates) {
                            // Return coordinates directly - most accurate for weather
                            completion(parsedCoords.latitude, parsedCoords.longitude, "")
                            return
                        }
                        
                        // Second priority: city + state for weather data (good for geocoding)
                        if let city = data["city"] as? String, !city.isEmpty,
                           let state = data["state"] as? String, !state.isEmpty {
                            completion(nil, nil, "\(city), \(state)")
                            return
                        }
                        
                        // Third priority: street address
                        if let street = data["street"] as? String, !street.isEmpty,
                           let city = data["city"] as? String, !city.isEmpty {
                            completion(nil, nil, "\(street), \(city)")
                            return
                        }
                        
                        // Fourth priority: schoolAddress field (if not coordinates)
                        if let address = data["schoolAddress"] as? String, !address.isEmpty,
                           self.parseCoordinateString(address) == nil { // Not coordinates
                            completion(nil, nil, address)
                            return
                        }
                        
                        // Final fallback: session location
                        if let location = self.session.location, !location.isEmpty {
                            completion(nil, nil, location)
                            return
                        }
                        
                        completion(nil, nil, "")
                    } else {
                        // Use session location if no school document found
                        if let location = self.session.location, !location.isEmpty {
                            completion(nil, nil, location)
                        } else {
                            completion(nil, nil, "")
                        }
                    }
                }
        }
    }
    
    private func calculateTravelPlan() {
        // Check for required data
        guard !userHomeAddress.isEmpty else {
            travelPlan.errorMessage = "Home address not available"
            return
        }
        
        guard !schoolAddress.isEmpty else {
            travelPlan.errorMessage = "School address not available"
            return
        }
        
        guard let startTime = determineStartTime() else {
            travelPlan.errorMessage = "Could not determine start time"
            return
        }
        
        // Set calculating state
        travelPlan.isCalculating = true
        travelPlan.errorMessage = ""
        
        // Use MapKit to calculate the route and travel time
        calculateTravelTime(from: userHomeAddress, to: schoolAddress) { duration, error in
            DispatchQueue.main.async {
                self.travelPlan.isCalculating = false
                
                if let error = error {
                    self.travelPlan.errorMessage = "Travel calculation error: \(error.localizedDescription)"
                    return
                }
                
                guard let travelDuration = duration else {
                    self.travelPlan.errorMessage = "Could not calculate travel time"
                    return
                }
                
                // Store the travel time
                self.travelPlan.travelDuration = travelDuration
                
                // Calculate arrival time (30 minutes before start time)
                let arrivalTime = startTime.addingTimeInterval(-30 * 60)
                self.travelPlan.arrivalTime = arrivalTime
                
                // Calculate leave time (travel duration before arrival time)
                let leaveTime = arrivalTime.addingTimeInterval(-travelDuration)
                self.travelPlan.suggestedLeaveTime = leaveTime
                
                // Only calculate wake-up time if:
                // 1. This is the first shift of the day
                // 2. The user has a ready time set
                if self.isFirstShiftOfDay() && self.travelPlan.readyTime > 0 {
                    // Calculate wake-up time (ready time before leave time)
                    let wakeupTime = leaveTime.addingTimeInterval(-self.travelPlan.readyTime)
                    self.travelPlan.suggestedWakeupTime = wakeupTime
                } else {
                    self.travelPlan.suggestedWakeupTime = nil
                }
            }
        }
    }
    
    // Determine the actual start time from either shift notes or session time
    private func determineStartTime() -> Date? {
        // Check shift notes for a start time
        if let notes = session.description, !notes.isEmpty {
            // First try simple scanning for a line with "Start Time" followed by a number
            let lines = notes.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            
            for line in lines {
                // Check if line contains "Start Time" or similar
                if line.lowercased().contains("start time") || line.lowercased().contains("start at") || line.lowercased().contains("begins at") {
                    // Try to extract number after any separator like ":", "-", or just spaces
                    // First extract everything after "start time" (case insensitive)
                    if let range = line.range(of: "time", options: .caseInsensitive) {
                        let afterTime = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                        
                        // Look for first number in this substring
                        let numberPattern = "\\d{1,2}(?::\\d{2})?"  // Matches "8", "8:00", "12", "12:30" etc.
                        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []),
                           let match = regex.firstMatch(in: String(afterTime), options: [], range: NSRange(afterTime.startIndex..<afterTime.endIndex, in: afterTime)),
                           let matchRange = Range(match.range, in: afterTime) {
                            
                            let timeStr = String(afterTime[matchRange])
                            
                            // If it's just a number like "8", assume it's an hour
                            if let hour = Int(timeStr) {
                                // Convert to Date
                                let calendar = Calendar.current
                                if let sessionDate = session.startDate {
                                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: sessionDate)
                                    dateComponents.hour = hour
                                    dateComponents.minute = 0
                                    if let date = calendar.date(from: dateComponents) {
                                        return date
                                    }
                                }
                            }
                            
                            // If it's a time like "8:00", parse it
                            let formats = ["h:mm", "H:mm"]
                            for format in formats {
                                let formatter = DateFormatter()
                                formatter.dateFormat = format
                                
                                if let date = formatter.date(from: timeStr) {
                                    // We have a time without a date, so need to set the date to the session date
                                    let calendar = Calendar.current
                                    if let sessionDate = session.startDate {
                                        let startTimeComponents = calendar.dateComponents([.hour, .minute], from: date)
                                        var sessionDateComponents = calendar.dateComponents([.year, .month, .day], from: sessionDate)
                                        sessionDateComponents.hour = startTimeComponents.hour
                                        sessionDateComponents.minute = startTimeComponents.minute
                                        
                                        if let finalDate = calendar.date(from: sessionDateComponents) {
                                            return finalDate
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // If we get here, we found a line with "Start Time" but couldn't parse it
                    // Let's try a more aggressive approach to extract any number
                    let numberPattern = "\\d{1,2}"  // Match any 1 or 2 digit number
                    if let regex = try? NSRegularExpression(pattern: numberPattern, options: []),
                       let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..<line.endIndex, in: line)),
                       let matchRange = Range(match.range, in: line) {
                        
                        let timeStr = String(line[matchRange])
                        
                        if let hour = Int(timeStr) {
                            // Convert to Date
                            let calendar = Calendar.current
                            if let sessionDate = session.startDate {
                                var dateComponents = calendar.dateComponents([.year, .month, .day], from: sessionDate)
                                dateComponents.hour = hour
                                dateComponents.minute = 0
                                if let date = calendar.date(from: dateComponents) {
                                    return date
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Fall back to the session start time
        return session.startDate
    }

    // Calculate travel time between two addresses using MapKit
    private func calculateTravelTime(from origin: String, to destination: String, completion: @escaping (TimeInterval?, Error?) -> Void) {
        // Check if inputs are coordinate strings in format "latitude,longitude"
        let originCoordinate = parseCoordinateString(origin)
        let destinationCoordinate = parseCoordinateString(destination)
        
        // If both are already coordinates, skip geocoding
        if let originCoord = originCoordinate, let destCoord = destinationCoordinate {
            // Create a route request directly
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: originCoord))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
            request.transportType = .automobile
            
            // Calculate the route
            let directions = MKDirections(request: request)
            directions.calculate { response, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                if let route = response?.routes.first {
                    // Return the expected travel time
                    let travelTimeSeconds = route.expectedTravelTime
                    completion(travelTimeSeconds, nil)
                } else {
                    let error = NSError(domain: "TravelPlanning", code: -2, userInfo: [NSLocalizedDescriptionKey: "No route found"])
                    completion(nil, error)
                }
            }
            return
        }
        
        // If one or both aren't coordinates, continue with geocoding
        let geocoder = CLGeocoder()
        var geocodedOriginCoordinate: CLLocationCoordinate2D?
        var geocodedDestinationCoordinate: CLLocationCoordinate2D?
        
        let group = DispatchGroup()
        var geocodeError: Error?
        
        // Geocode origin address if needed
        if originCoordinate == nil {
            group.enter()
            geocoder.geocodeAddressString(origin) { placemarks, error in
                defer { group.leave() }
                
                if let error = error {
                    geocodeError = error
                    return
                }
                
                if let location = placemarks?.first?.location {
                    geocodedOriginCoordinate = location.coordinate
                }
            }
        } else {
            geocodedOriginCoordinate = originCoordinate
        }
        
        // Geocode destination address if needed
        if destinationCoordinate == nil {
            group.enter()
            geocoder.geocodeAddressString(destination) { placemarks, error in
                defer { group.leave() }
                
                if let error = error {
                    geocodeError = error
                    return
                }
                
                if let location = placemarks?.first?.location {
                    geocodedDestinationCoordinate = location.coordinate
                }
            }
        } else {
            geocodedDestinationCoordinate = destinationCoordinate
        }
        
        group.notify(queue: .global()) {
            // Check for geocoding errors
            if let error = geocodeError {
                completion(nil, error)
                return
            }
            
            // Use the geocoded coordinates or the parsed coordinates
            let finalOriginCoord = geocodedOriginCoordinate ?? originCoordinate
            let finalDestinationCoord = geocodedDestinationCoordinate ?? destinationCoordinate
            
            // Check if both coordinates were obtained
            guard let originCoord = finalOriginCoord, let destinationCoord = finalDestinationCoord else {
                let error = NSError(domain: "TravelPlanning", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not geocode addresses"])
                completion(nil, error)
                return
            }
            
            // Create a route request
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: originCoord))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoord))
            request.transportType = .automobile
            
            // Calculate the route
            let directions = MKDirections(request: request)
            directions.calculate { response, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                if let route = response?.routes.first {
                    // Return the expected travel time
                    let travelTimeSeconds = route.expectedTravelTime
                    completion(travelTimeSeconds, nil)
                } else {
                    let error = NSError(domain: "TravelPlanning", code: -2, userInfo: [NSLocalizedDescriptionKey: "No route found"])
                    completion(nil, error)
                }
            }
        }
    }
    
    // Helper function to parse coordinate strings in format "latitude,longitude"
    private func parseCoordinateString(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else {
            return nil
        }
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    // Message coworkers implementation
    private func messageCoworkers() {
        // Set up the message text first
        let messageText = createMessageText()
        messageBody = messageText
        
        // Check if we need to load contacts
        if coworkerContacts.isEmpty {
            // Show loading state and load contacts
            isLoadingContacts = true
            isShowingMessageComposer = true // Show sheet with loading indicator
            
            // Load real contacts from Firestore
            loadCoworkerPhoneNumbers { success in
                DispatchQueue.main.async {
                    self.isLoadingContacts = false
                }
            }
        } else {
            // We already have contacts, just show the composer
            isShowingMessageComposer = true
        }
    }
    
    // Helper to create the message text
    private func createMessageText() -> String {
        var message = "Hi team!\n\n"
        
        if let start = session.startDate, let end = session.endDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            
            message += "We're scheduled for a shoot at \(session.schoolName) on \(dateFormatter.string(from: start)) from \(timeFormatter.string(from: start)) to \(timeFormatter.string(from: end)).\n\n"
        } else {
            message += "We're scheduled for a shoot at \(session.schoolName).\n\n"
        }
        
        // Add more details if available
        if let location = session.location, !location.isEmpty {
            message += "Location: \(location)\n"
        }
        
        message += "Position: \(session.position)\n\n"
        
        if let description = session.description, !description.isEmpty {
            message += "Notes: \(description)\n\n"
        }
        
        // Add travel planning information if available
        if let leaveTime = travelPlan.suggestedLeaveTime, let arrivalTime = travelPlan.arrivalTime {
            message += "Suggested leave time: \(shortTimeFormatter.string(from: leaveTime))\n"
            message += "Arrival time: \(shortTimeFormatter.string(from: arrivalTime))\n\n"
        }
        
        // Add weather info if available
        if let weather = weatherData {
            message += "Weather: \(weather.condition ?? "Unknown"), \(weather.temperatureString)\n\n"
        }
        
        // Add job box status if available
        if latestJobBoxStatus != .unknown {
            message += "Job Box Status: \(latestJobBoxStatus.rawValue)\n"
            if !latestJobBoxScannedBy.isEmpty {
                message += "Last scanned by: \(latestJobBoxScannedBy)\n"
                if let timestamp = latestJobBoxTimestamp {
                    message += "Scan time: \(formatTimestamp(timestamp))\n\n"
                }
            }
        }
        
        message += "See you there!"
        
        return message
    }
    
    // Load phone numbers from Firestore with completion handler
    private func loadCoworkerPhoneNumbers(completion: @escaping (Bool) -> Void = { _ in }) {
        let db = Firestore.firestore()
        coworkerContacts = [] // Reset the array
        
        // Get all coworkers on this shoot
        let coworkerNames = otherEmployeesSameJob()
        
        if coworkerNames.isEmpty {
            completion(false)
            return // No coworkers to message
        }
        
        // Get organization ID to comply with security rules
        let orgID = UserManager.shared.getCachedOrganizationID()
        guard !orgID.isEmpty else {
            print("🔐 Cannot load coworker contacts: no organization ID found")
            completion(false)
            return
        }
        
        var loadedCount = 0
        var foundPhoneNumber = false
        
        for fullName in coworkerNames {
            let queryName = firstName(from: fullName)
            db.collection("users")
                .whereField("organizationID", isEqualTo: orgID)
                .whereField("firstName", isEqualTo: queryName)
                .getDocuments { snapshot, error in
                    defer {
                        loadedCount += 1
                        // Check if we're done loading
                        if loadedCount == coworkerNames.count {
                            DispatchQueue.main.async {
                                completion(foundPhoneNumber)
                            }
                        }
                    }
                    
                    if let error = error {
                        print("⚠️ Coworker contact unavailable: \(error.localizedDescription)")
                        // Continue without coworker contact data
                        return
                    }
                    
                    if let docs = snapshot?.documents, let doc = docs.first {
                        let data = doc.data()
                        let phone = data["phone"] as? String ?? ""
                        
                        if !phone.isEmpty {
                            DispatchQueue.main.async {
                                let contact = CoworkerContactInfo(
                                    id: doc.documentID,
                                    name: fullName,
                                    phoneNumber: phone
                                )
                                self.coworkerContacts.append(contact)
                                foundPhoneNumber = true
                            }
                        }
                    }
                }
        }
    }
    
    // Action Methods
    
    private func openInAppleMaps() {
        guard let location = session.location, !location.isEmpty else { return }
        
        let addressString = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mapsString = "http://maps.apple.com/?address=\(addressString)"
        
        if let url = URL(string: mapsString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openInGoogleMaps() {
        guard let location = session.location, !location.isEmpty else { return }
        
        let addressString = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mapsString = "comgooglemaps://?q=\(addressString)"
        
        if let url = URL(string: mapsString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // Fallback to browser if Google Maps app is not installed
            let webURL = URL(string: "https://maps.google.com/?q=\(addressString)")!
            UIApplication.shared.open(webURL)
        }
    }
    
    private func shareShift() {
        guard let start = session.startDate, let end = session.endDate else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        var textToShare = "Shift: \(session.position)\n"
        textToShare += "Date: \(dateFormatter.string(from: start)) - \(dateFormatter.string(from: end))\n"
        textToShare += "Location: \(session.schoolName)"
        
        if let location = session.location, !location.isEmpty {
            textToShare += "\nAddress: \(location)"
        }
        
        // Add weather info if available
        if let weather = weatherData {
            textToShare += "\nWeather: \(weather.condition ?? "Unknown"), \(weather.temperatureString)"
        }
        
        // Add job box status if available
        if latestJobBoxStatus != .unknown {
            textToShare += "\nJob Box Status: \(latestJobBoxStatus.rawValue)"
            if !latestJobBoxScannedBy.isEmpty {
                textToShare += " (Last handled by: \(latestJobBoxScannedBy))"
                if let timestamp = latestJobBoxTimestamp {
                    textToShare += " at \(formatTimestamp(timestamp))"
                }
            }
        }
        
        // Add travel planning information if available
        if let leaveTime = travelPlan.suggestedLeaveTime, let wakeupTime = travelPlan.suggestedWakeupTime {
            textToShare += "\n\nSuggested wake-up: \(shortTimeFormatter.string(from: wakeupTime))"
            textToShare += "\nSuggested departure: \(shortTimeFormatter.string(from: leaveTime))"
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [textToShare],
            applicationActivities: nil
        )
        
        // Find the current UIWindow and present from it
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    func otherEmployeesSameJob() -> [String] {
        guard let shiftStart = session.startDate else { return [] }
        let cal = Calendar.current
        let shiftDay = cal.startOfDay(for: shiftStart)
        
        // Get all photographers working on the same session (same date, school, time)
        var coworkerNames: [String] = []
        
        // First, get all photographers from the current session (excluding current user)
        let sessionPhotographers = session.getPhotographerNames()
        if let currentUserInfo = currentUserPhotographerInfo {
            // Exclude current user from the list
            for photographerName in sessionPhotographers {
                if photographerName != currentUserInfo.name {
                    coworkerNames.append(photographerName)
                }
            }
        } else {
            // If we can't identify current user, include all photographers except the first one
            coworkerNames = Array(sessionPhotographers.dropFirst())
        }
        
        // Also check other sessions on the same day at the same school (for different session types)
        let otherSessionCoworkers = allSessions.filter { other in
            guard let otherStart = other.startDate,
                  other.id != session.id else { return false }
            let otherDay = cal.startOfDay(for: otherStart)
            return otherDay == shiftDay && other.schoolName == session.schoolName
        }
        .flatMap { $0.getPhotographerNames() }
        
        // Add unique names from other sessions
        for name in otherSessionCoworkers {
            if !coworkerNames.contains(name) {
                coworkerNames.append(name)
            }
        }
        
        return coworkerNames
    }
    
    // Check if a user profile name matches the job box scanner name
    private func isMatchingUser(profileName: String, scannedByName: String) -> Bool {
        // Don't attempt to match if scannedByName is empty
        if scannedByName.isEmpty {
            return false
        }
        
        // Get first names for comparison
        let profileFirstName = firstName(from: profileName).lowercased()
        let scannedByFirstName = firstName(from: scannedByName).lowercased()
        
        // Guard against empty strings
        if profileFirstName.isEmpty || scannedByFirstName.isEmpty {
            return false
        }
        
        // Perform exact match (case insensitive)
        return profileFirstName == scannedByFirstName
    }
    
    // Extract first name from a full name
    func firstName(from fullName: String) -> String {
        // Return empty string for empty input
        if fullName.isEmpty {
            return ""
        }
        
        // Clean the input - remove any leading/trailing whitespace
        let cleanedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Special case for "from" which appears in logs
        if cleanedName == "from" {
            return ""
        }
        
        // If the name contains ellipsis, only use the part before it
        if cleanedName.contains("...") {
            let components = cleanedName.components(separatedBy: "...")
            let nameBeforeEllipsis = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            // Get the first part of the name
            let firstPart = nameBeforeEllipsis.components(separatedBy: .whitespaces).first ?? nameBeforeEllipsis
            return firstPart
        }
        
        // Otherwise just get the first name (first part before any whitespace)
        let firstPart = cleanedName.components(separatedBy: .whitespaces).first ?? cleanedName
        return firstPart
    }
    
    // Get initials from a full name
    private func getInitials(from name: String) -> String {
        let components = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        
        if components.count >= 2 {
            // First and last name initials
            let firstInitial = String(components.first?.prefix(1) ?? "")
            let lastInitial = String(components.last?.prefix(1) ?? "")
            return (firstInitial + lastInitial).uppercased()
        } else if let first = components.first {
            // Just first name initial
            return String(first.prefix(1)).uppercased()
        } else {
            return "?"
        }
    }
    
    // MARK: - Real-time Session Updates
    
    private func startSessionListener() {
        // Listen for updates to all sessions
        sessionListener = sessionService.listenForSessions { sessions in
            DispatchQueue.main.async {
                
                // Update the current session if it changed
                if let updatedSession = sessions.first(where: { $0.id == self.session.id }) {
                    self.session = updatedSession
                    
                    // Reload related data that might have changed
                    self.loadCoworkerPhotos()
                    self.loadWeatherData()
                }
                
                // Update all sessions for coworker calculations
                self.allSessions = sessions
            }
        }
    }
}

// MARK: - Message Compose View

struct MessageComposeView: UIViewControllerRepresentable {
    var recipients: [String]
    var body: String
    @Binding var isShowing: Bool
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var parent: MessageComposeView
        
        init(_ parent: MessageComposeView) {
            self.parent = parent
        }
        
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.isShowing = false
        }
    }
    
    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }
}

// Define ScrollOffsetKey for tracking scroll position
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
