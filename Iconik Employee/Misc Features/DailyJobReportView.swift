import SwiftUI
import CoreLocation
import MapKit
import Combine

// MARK: - Keyboard Height Publisher
extension Publishers {
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { notification -> CGFloat in
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
            }
        
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ -> CGFloat in 0 }
        
        return MergeMany(willShow, willHide)
            .eraseToAnyPublisher()
    }
}

// MARK: - Auto-Dismiss Date Picker Sheet
/// A date picker sheet that automatically dismisses after selection
private struct AutoDismissDatePickerSheet: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    var onDateSelected: (Date) -> Void

    @State private var tempDate: Date = Date()
    @State private var hasInitialized: Bool = false

    var body: some View {
        NavigationView {
            DatePicker("Select Date", selection: $tempDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Report Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                }
                .onChange(of: tempDate) { newDate in
                    // Only auto-dismiss if user actually changed the date (not initial setup)
                    guard hasInitialized else { return }

                    // Auto-dismiss after a brief delay when date changes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedDate = newDate
                        isPresented = false
                        onDateSelected(newDate)
                    }
                }
        }
        .presentationDetents([.medium])
        .onAppear {
            tempDate = selectedDate
            // Mark as initialized after a brief delay to ignore the initial onChange
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasInitialized = true
            }
        }
    }
}

// Photographer struct to handle duplicate names
struct PhotographerOption: Identifiable {
    let id: String  // User document ID
    let firstName: String
    let lastName: String

    var displayName: String {
        "\(firstName) \(lastName)"
    }
}

struct DailyJobReportView: View {
    // ------------------------------------------------------------------
    // Photoshoot Notes / Multi-Note logic
    // ------------------------------------------------------------------
    @AppStorage("photoshootNotes") var storedNotesData: Data = Data()
    @State private var photoshootNotes: [PhotoshootNote] = []
    @State private var selectedPhotoshootNote: PhotoshootNote? = nil
    
    // ------------------------------------------------------------------
    // User account data
    // ------------------------------------------------------------------
    @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
    @AppStorage("userFirstName") var storedUserFirstName: String = ""
    @AppStorage("userLastName") var storedUserLastName: String = ""
    @AppStorage("userHomeAddress") var storedUserHomeAddress: String = ""
    
    // ------------------------------------------------------------------
    // Photographer & School data
    // ------------------------------------------------------------------
    @State private var photographers: [PhotographerOption] = []
    @State private var schoolOptions: [SchoolItem] = []
    
    // ------------------------------------------------------------------
    // Selected fields
    // ------------------------------------------------------------------
    @State private var selectedPhotographerId: String = ""
    // Session-primary selection: the scheduled session this report is for.
    // nil = off-schedule (manual location). Location/mileage derive from this (D1, D4, D6).
    @State private var selectedSession: Session? = nil
    // Auto-select runs once per date. The session listener re-fires (cache → fresh →
    // realtime), so this guards against clobbering the photographer's manual pick.
    @State private var sessionAutoSelected: Bool = false
    // Dynamic list for multiple school selections (off-schedule manual entry)
    @State private var selectedSchools: [SchoolItem?] = [nil] // Start with one dropdown
    
    // ------------------------------------------------------------------
    // Schedule data
    // ------------------------------------------------------------------
    @State private var selectedDateSessions: [Session] = []
    @State private var isLoadingSchedule: Bool = false
    @State private var scheduleError: String = ""
    
    // ------------------------------------------------------------------
    // Other report fields
    // ------------------------------------------------------------------
    @State private var reportDate: Date = Date()
    @State private var showDatePicker: Bool = false
    @State private var totalMileage: String = ""
    @State private var vehicleType: String = ""  // "" = not yet chosen; must be "personal" or "company" before submit
    @State private var showVehicleConfirm: Bool = false
    @State private var jobDescription: String = ""  // Optional free text
    
    // ------------------------------------------------------------------
    // Multi-select: Job Description (scheduled)
    // ------------------------------------------------------------------
    @State private var selectedJobDescriptions: Set<String> = []
    let jobDescriptionOptions = [
        "Fall Original Day",
        "Fall Makeup Day",
        "Classroom Groups",
        "Fall Sports",
        "Winter Sports",
        "Spring Sports",
        "Spring Photos",
        "Homecoming",
        "Prom",
        "Graduation",
        "Yearbook Candid's",
        "Yearbook Groups and Clubs",
        "Sports League",
        "District Office Photos",
        "Banner Photos",
        "In Studio Photos",
        "School Board Photos",
        "Dr. Office Head Shots",
        "Dr. Office Cards",
        "Dr. Office Candid's",
        "Deliveries",
        "NONE"
    ]
    
    // ------------------------------------------------------------------
    // Multi-select: Extra Items (not on schedule)
    // ------------------------------------------------------------------
    @State private var selectedExtraItems: Set<String> = []
    let extraItemsOptions = [
        "Underclass Makeup",
        "Staff Makeup",
        "ID card Images",
        "Sports Makeup",
        "Class Groups",
        "Yearbook Groups and Clubs",
        "Class Candids",
        "Students from other schools",
        "Siblings",
        "Office Staff Photos",
        "Deliveries",
        "NONE"
    ]
    
    // ------------------------------------------------------------------
    // Single-choice (radio) questions - initialize as empty string (no selection)
    // ------------------------------------------------------------------
    @State private var jobBoxAndCameraCards: String = ""  // "Yes", "No", or "NA", empty = no selection
    @State private var sportsBackgroundShot: String = ""  // "Yes", "No", or "NA", empty = no selection
    @State private var cardsScannedChoice: String = ""    // "Yes" or "No", empty = no selection
    
    // We'll use 2 columns for each multi-select grid
    let columns = [
        GridItem(.flexible(minimum: 100), spacing: 10),
        GridItem(.flexible(minimum: 100), spacing: 10)
    ]
    
    // ------------------------------------------------------------------
    // MULTIPLE Images
    // ------------------------------------------------------------------
    @State private var selectedImages: [UIImage] = [] // All selected images
    @State private var showImagePicker: Bool = false
    @State private var tempImage: UIImage? = nil      // Temporary for new picks
    
    // ------------------------------------------------------------------
    // Error / State
    // ------------------------------------------------------------------
    @State private var errorMessage: String = ""
    @State private var isSubmitting: Bool = false
    @State private var calculatedMileage: Double = 0.0
    @State private var showPermissionError: Bool = false
    
    // ------------------------------------------------------------------
    // Toast for success feedback
    // ------------------------------------------------------------------
    @State private var showToast = false
    @State private var toastMessage = ""
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var tabBarManager = TabBarManager.shared
    
    // ------------------------------------------------------------------
    // Keyboard handling
    // ------------------------------------------------------------------
    @FocusState private var isTextFieldFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    
    // ------------------------------------------------------------------
    // UI State Management - All sections expanded by default
    // ------------------------------------------------------------------
    @State private var expandedSections: Set<FormSection> = Set(FormSection.allCases)
    
    // Arrays for the radio questions
    let yesNoNaOptions = ["Yes", "No", "NA"]
    let yesNoOptions   = ["Yes", "No"]
    
    // Helper to get selected photographer's name
    private var selectedPhotographerName: String {
        photographers.first(where: { $0.id == selectedPhotographerId })?.displayName ?? ""
    }
    
    // Full ICS URL from Sling
    private let sessionService = SessionService.shared
    private let subscriptionId = UUID()

    // MARK: - Form Sections Enum
    
    enum FormSection: String, CaseIterable, Identifiable {
        case basicInfo = "Basic Information"
        case photoshootNote = "Photoshoot Note"
        case schools = "Schools & Mileage"
        case jobDescription = "Job Description"
        case extraItems = "Extra Items"
        case scanStatus = "Scan Status"
        case notes = "Notes"
        case photos = "Photos"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .basicInfo: return "info.circle"
            case .photoshootNote: return "note.text"
            case .schools: return "building.2"
            case .jobDescription: return "list.bullet"
            case .extraItems: return "plus.circle"
            case .scanStatus: return "barcode.viewfinder"
            case .notes: return "text.bubble"
            case .photos: return "photo"
            }
        }
        
        var color: Color {
            switch self {
            case .basicInfo: return .blue
            case .photoshootNote: return .purple
            case .schools: return .green
            case .jobDescription: return .orange
            case .extraItems: return .pink
            case .scanStatus: return .teal
            case .notes: return .indigo
            case .photos: return .red
            }
        }
    }
    
    // Added for dark mode detection
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header section with background
                ZStack {
                    backgroundGradient
                        .frame(maxHeight: 200)
                    
                    VStack(spacing: 0) {
                        headerView
                        progressView
                    }
                }
                
                // Main content with sections
                VStack(spacing: 16) {
                    ForEach(FormSection.allCases) { section in
                        let isExpanded = expandedSections.contains(section)
                        sectionCard(for: section, isExpanded: isExpanded)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .background(backgroundGradient)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: keyboardHeight)
                .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        }
        .onAppear {
            loadData()
        }
        .onReceive(Publishers.keyboardHeight) { height in
            self.keyboardHeight = height
        }
        .onDisappear {
            sessionService.stopListeningToSessions(subscriptionId: subscriptionId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            // Re-subscribe when app returns to foreground
            loadScheduleForDate(reportDate)
        }
        .alert("Permission Error", isPresented: $showPermissionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Unable to access daily job reports. Please contact your administrator.")
        }
        .alert("Error", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog("Confirm Vehicle", isPresented: $showVehicleConfirm, titleVisibility: .visible) {
            Button("Personal") { vehicleType = "personal" }
            Button("Company") { vehicleType = "company" }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select the vehicle again to confirm — this sets your mileage reimbursement and can't be changed by an accidental tap.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: attemptSubmit) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Text("Submit")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isSubmitting)
            }
        }
        .toast(isPresented: $showToast, message: toastMessage, isSuccess: true)
    }
    
    // MARK: - UI Components
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                colorScheme == .dark ? Color(UIColor.systemBackground).opacity(0.9) : Color(UIColor.systemBackground),
                colorScheme == .dark ? Color(UIColor.systemBackground).opacity(0.7) : Color(UIColor.systemBackground).opacity(0.8)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var headerView: some View {
        VStack(spacing: 4) {
            Text("Daily Job Report")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            
            if !selectedDateSessions.isEmpty {
                Text("\(selectedDateSessions.count) sessions scheduled today")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            colorScheme == .dark ?
                Color(UIColor.secondarySystemBackground).opacity(0.9) :
                Color(UIColor.secondarySystemBackground).opacity(0.7)
        )
    }
    
    private var progressView: some View {
        let completedSections = calculateCompletedSections()
        let progress = Double(completedSections) / Double(FormSection.allCases.count - 1) // Excluding Photos from the count
        
        return VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .foregroundColor(progressBarBackgroundColor)
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .foregroundColor(progressBarFillColor)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text("\(completedSections)/\(FormSection.allCases.count - 1) Completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // New computed properties for better dark mode contrast
    private var progressBarBackgroundColor: Color {
        colorScheme == .dark ? Color(UIColor.systemGray4) : Color(UIColor.systemGray5)
    }
    
    private var progressBarFillColor: Color {
        colorScheme == .dark ? Color.blue.opacity(0.9) : Color.blue
    }
    
    private var cardBackground: some View {
        Group {
            if colorScheme == .dark {
                Color(UIColor.systemGray6)
            } else {
                Color(UIColor.systemBackground)
            }
        }
    }
    
    private var inputFieldBackground: some View {
        Group {
            if colorScheme == .dark {
                Color(UIColor.systemGray5)
            } else {
                Color(UIColor.systemGray6)
            }
        }
    }
    
    // MARK: - Section Cards
    
    private func sectionCard(for section: FormSection, isExpanded: Bool) -> some View {
        VStack(spacing: 0) {
            // Section header
            sectionHeader(for: section, isExpanded: isExpanded)
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background(sectionHeaderBackground(for: section))
                .cornerRadius(12, corners: isExpanded ? [.topLeft, .topRight] : .allCorners)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        toggleSection(section)
                    }
                }
            
            // Section content (when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    sectionContent(for: section)
                }
                .padding(16)
                .background(cardBackground)
                .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            }
        }
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private func sectionHeader(for section: FormSection, isExpanded: Bool) -> some View {
        HStack {
            Image(systemName: section.icon)
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(iconColor(for: section))
                )
            
            Text(section.rawValue)
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Only show completion indicators for sections that the user has explicitly completed
            if isSectionCompleted(section) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            // Expand/collapse icon
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .foregroundColor(.secondary)
        }
    }
    
    private func iconColor(for section: FormSection) -> Color {
        let baseColor = section.color
        return colorScheme == .dark ? baseColor.opacity(0.9) : baseColor
    }
    
    private func sectionHeaderBackground(for section: FormSection) -> some View {
        Group {
            if isSectionCompleted(section) {
                LinearGradient(
                    gradient: Gradient(colors: [
                        colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemBackground),
                        Color(UIColor.systemGray6)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemBackground)
            }
        }
    }
    
    // MARK: - Section Content Views
    
    private func sectionContent(for section: FormSection) -> some View {
        Group {
            switch section {
            case .basicInfo:
                basicInfoSection
            case .photoshootNote:
                photoshootNoteSection
            case .schools:
                schoolsSection
            case .jobDescription:
                jobDescriptionSection
            case .extraItems:
                extraItemsSection
            case .scanStatus:
                scanStatusSection
            case .notes:
                notesSection
            case .photos:
                photosSection
            }
        }
    }
    
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Date & Photographer")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Button {
                showDatePicker = true
            } label: {
                HStack {
                    Text("Report Date")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(reportDate, style: .date)
                        .foregroundColor(.secondary)
                    Image(systemName: "calendar")
                        .foregroundColor(.accentColor)
                }
                .padding()
                .background(inputFieldBackground)
                .cornerRadius(8)
            }
            .sheet(isPresented: $showDatePicker) {
                AutoDismissDatePickerSheet(selectedDate: $reportDate, isPresented: $showDatePicker) { newDate in
                    loadScheduleForDate(newDate, isDateChange: true)
                }
            }
            
            if photographers.isEmpty {
                HStack {
                    Text("Loading photographers...")
                    Spacer()
                    ProgressView()
                }
                .padding()
                .background(inputFieldBackground)
                .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedPhotographerId) {
                        ForEach(photographers) { photographer in
                            Text(photographer.displayName).tag(photographer.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(inputFieldBackground)
                    .cornerRadius(8)
                }
            }
            
            // Show loading indicator for schedule
            if isLoadingSchedule {
                HStack {
                    Text("Checking your schedule...")
                    Spacer()
                    ProgressView()
                }
                .padding()
                .background(inputFieldBackground)
                .cornerRadius(8)
            }
            
            if !scheduleError.isEmpty {
                Text(scheduleError)
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
    }
    
    private var photoshootNoteSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if photoshootNotes.isEmpty {
                Text("No photoshoot notes available")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(inputFieldBackground)
                    .cornerRadius(8)
            } else if photoshootNotes.count == 1, let firstNote = photoshootNotes.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Using note from \(firstNote.timestamp, style: .time)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(firstNote.school)
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(inputFieldBackground)
                        .cornerRadius(8)
                        .onAppear {
                            selectedPhotoshootNote = photoshootNotes.first
                            if let note = selectedPhotoshootNote {
                                loadPhotosFromNote(note)
                            }
                        }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Photoshoot Note")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedPhotoshootNote) {
                        Text("None").tag(nil as PhotoshootNote?)
                        ForEach(photoshootNotes) { note in
                            Text("\(note.timestamp, style: .time) - \(note.school)")
                                .tag(note as PhotoshootNote?)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(inputFieldBackground)
                    .cornerRadius(8)
                    .onChange(of: selectedPhotoshootNote) { newNote in
                        guard let note = newNote else { return }
                        if let matchIndex = schoolOptions.firstIndex(where: { $0.name == note.school }) {
                            if !selectedSchools.isEmpty {
                                selectedSchools[0] = schoolOptions[matchIndex]
                            }
                        }
                        
                        // Load photos from the selected note
                        loadPhotosFromNote(note)
                    }
                }
            }
        }
    }
    
    private var schoolsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Session selector — the photographer picks the session this report is
            // for; location + mileage derive from it (D1). Only shown when the
            // photographer has sessions scheduled this day; otherwise off-schedule.
            if !selectedDateSessions.isEmpty {
                sessionSelectorView
            }

            if let session = selectedSession {
                // Session selected → location is read-only, derived from the session (D4)
                derivedSchoolView(for: session)
            } else {
                // Off-schedule (none scheduled or "no scheduled session") → manual picker (D4)
                manualSchoolsView
            }

            mileageView
        }
    }

    // Sorted sessions for the picker (earliest first), matching auto-select order (D2)
    private var sortedSessionsForPicker: [Session] {
        selectedDateSessions.sorted {
            ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture)
        }
    }

    private var sessionSelectorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("", selection: Binding(
                get: { selectedSession },
                set: { newValue in
                    // User-driven change only; programmatic auto-select calls
                    // applySessionSelection directly (no double-fire). Mark as
                    // resolved so listener re-fires don't overwrite this pick.
                    sessionAutoSelected = true
                    selectedSession = newValue
                    applySessionSelection(newValue)
                }
            )) {
                Text("No scheduled session (off-schedule)").tag(nil as Session?)
                ForEach(sortedSessionsForPicker) { session in
                    Text(session.reportDisplayLabel).tag(session as Session?)
                }
            }
            .pickerStyle(.menu)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(inputFieldBackground)
            .cornerRadius(8)
        }
    }

    private func derivedSchoolView(for session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("School (from schedule)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: "building.2")
                    .foregroundColor(.secondary)
                Text(selectedSchools.first.flatMap { $0?.name } ?? session.schoolName)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(inputFieldBackground)
            .cornerRadius(8)
        }
    }

    private var manualSchoolsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<selectedSchools.count, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Text("School \(index + 1)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        if schoolOptions.isEmpty {
                            Text("Loading schools...")
                                .foregroundColor(.secondary)
                        } else {
                            SearchableSchoolPicker(
                                selection: Binding(
                                    get: { selectedSchools[index] },
                                    set: { newValue in
                                        selectedSchools[index] = newValue
                                        calculateMultiStopMileage()
                                    }
                                ),
                                schools: $schoolOptions,
                                title: "Select School",
                                organizationID: storedUserOrganizationID
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if selectedSchools.count > 1 {
                            Button(action: {
                                selectedSchools.remove(at: index)
                                calculateMultiStopMileage()
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title3)
                            }
                        }
                    }
                    .padding()
                    .background(inputFieldBackground)
                    .cornerRadius(8)
                }
            }

            Button(action: {
                selectedSchools.append(nil)
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                    Text("Add School")
                        .fontWeight(.medium)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(inputFieldBackground)
                .cornerRadius(8)
            }
        }
    }

    private var mileageView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Mileage")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("Mileage", text: $totalMileage)
                        .keyboardType(.decimalPad)
                        .padding()

                    Text("miles")
                        .foregroundColor(.secondary)
                        .padding(.trailing)
                }
                .background(inputFieldBackground)
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Vehicle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("*")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }

                // Tapping a segment does NOT commit — it opens a confirmation
                // where the vehicle must be selected again. Only that second
                // selection sets vehicleType, so an accidental tap can't stick.
                Picker("Vehicle", selection: Binding(
                    get: { vehicleType },
                    set: { _ in showVehicleConfirm = true }
                )) {
                    Text("Personal").tag("personal")
                    Text("Company").tag("company")
                }
                .pickerStyle(.segmented)

                if vehicleType.isEmpty {
                    Text("Required — tap a vehicle, then confirm the selection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if totalMileage == "Calculating..." {
                HStack {
                    Text("Calculating route distances...")
                    Spacer()
                    ProgressView()
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
    
    private var jobDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What are you scheduled to shoot?")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(jobDescriptionOptions, id: \.self) { option in
                    ModernCheckboxRow(
                        title: option,
                        isSelected: selectedJobDescriptions.contains(option),
                        action: {
                            if selectedJobDescriptions.contains(option) {
                                selectedJobDescriptions.remove(option)
                            } else {
                                selectedJobDescriptions.insert(option)
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var extraItemsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Extra items not on your schedule")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(extraItemsOptions, id: \.self) { option in
                    ModernCheckboxRow(
                        title: option,
                        isSelected: selectedExtraItems.contains(option),
                        action: {
                            if selectedExtraItems.contains(option) {
                                selectedExtraItems.remove(option)
                            } else {
                                selectedExtraItems.insert(option)
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var scanStatusSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cards Scanned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 0) {
                    ForEach(yesNoOptions, id: \.self) { option in
                        ModernSegmentButton(
                            title: option,
                            isSelected: cardsScannedChoice == option,
                            action: { cardsScannedChoice = option }
                        )
                    }
                }
                .background(inputFieldBackground)
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Job Box and Camera Cards Turned In")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 0) {
                    ForEach(yesNoNaOptions, id: \.self) { option in
                        ModernSegmentButton(
                            title: option,
                            isSelected: jobBoxAndCameraCards == option,
                            action: { jobBoxAndCameraCards = option }
                        )
                    }
                }
                .background(inputFieldBackground)
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Sports Background Shot")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 0) {
                    ForEach(yesNoNaOptions, id: \.self) { option in
                        ModernSegmentButton(
                            title: option,
                            isSelected: sportsBackgroundShot == option,
                            action: { sportsBackgroundShot = option }
                        )
                    }
                }
                .background(inputFieldBackground)
                .cornerRadius(8)
            }
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Additional Notes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $jobDescription)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(inputFieldBackground)
                    .cornerRadius(8)
                    .focused($isTextFieldFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isTextFieldFocused = false
                            }
                        }
                    }
            }
            
            if let note = selectedPhotoshootNote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Photoshoot Note for \(note.school)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: Binding(
                        get: { note.noteText },
                        set: { newValue in
                            if let index = photoshootNotes.firstIndex(of: note) {
                                photoshootNotes[index].noteText = newValue
                                selectedPhotoshootNote = photoshootNotes[index]
                                savePhotoshootNotes()
                            }
                        }
                    ))
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(inputFieldBackground)
                    .cornerRadius(8)
                    .focused($isTextFieldFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isTextFieldFocused = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Attach Photos")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if selectedImages.isEmpty {
                Button(action: {
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.title2)
                        Text("Add Photos")
                            .fontWeight(.medium)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(inputFieldBackground)
                    .cornerRadius(8)
                    .foregroundColor(.blue)
                }
                .sheet(isPresented: $showImagePicker) {
                    ImagePicker(selectedImage: $tempImage)
                        .onDisappear {
                            if let newImg = tempImage {
                                selectedImages.append(newImg)
                                tempImage = nil
                            }
                        }
                }
            } else {
                // Photo gallery grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            Button(action: {
                                selectedImages.remove(at: index)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.7))
                                        .frame(width: 24, height: 24)
                                    
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(4)
                        }
                    }
                    
                    // Add more photos button
                    Button(action: {
                        showImagePicker = true
                    }) {
                        VStack {
                            Image(systemName: "plus")
                                .font(.title)
                                .foregroundColor(.blue)
                        }
                        .frame(width: 100, height: 100)
                        .background(inputFieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .sheet(isPresented: $showImagePicker) {
                        ImagePicker(selectedImage: $tempImage)
                            .onDisappear {
                                if let newImg = tempImage {
                                    selectedImages.append(newImg)
                                    tempImage = nil
                                }
                            }
                    }
                }
                
                Text("\(selectedImages.count) photo\(selectedImages.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // Submit button moved to navigation bar - keeping this for reference
    // private var submitButton: some View { ... }
    
    // MARK: - Helper Functions for UI
    
    private func toggleSection(_ section: FormSection) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }
    
    // This function determines if a section is completed based on its content
    // Only sections that have been explicitly filled out should be marked as completed
    private func isSectionCompleted(_ section: FormSection) -> Bool {
        switch section {
        case .basicInfo:
            return !selectedPhotographerId.isEmpty && reportDate != nil
            
        case .photoshootNote:
            // This section is optional, marked complete if a note is selected
            return selectedPhotoshootNote != nil
            
        case .schools:
            // Complete if at least one school is selected and mileage is entered
            return !selectedSchools.isEmpty &&
                   selectedSchools.first != nil &&
                   !totalMileage.isEmpty &&
                   totalMileage != "Calculating..."
            
        case .jobDescription:
            // Complete if at least one job description is selected
            return !selectedJobDescriptions.isEmpty
            
        case .extraItems:
            // This section is optional, marked complete if any extra items are selected
            return !selectedExtraItems.isEmpty
            
        case .scanStatus:
            // Complete if all radio selections have been made
            return !cardsScannedChoice.isEmpty &&
                   !jobBoxAndCameraCards.isEmpty &&
                   !sportsBackgroundShot.isEmpty
            
        case .notes:
            // Consider notes section complete if there's a photoshoot note OR if there are manual notes
            return selectedPhotoshootNote != nil || !jobDescription.isEmpty
            
        case .photos:
            // This section is always considered "complete" since it's optional and rarely used
            return true
        }
    }
    
    private func calculateCompletedSections() -> Int {
        // Count completed sections excluding the Photos section
        var count = 0
        for section in FormSection.allCases {
            if section != .photos && isSectionCompleted(section) {
                count += 1
            }
        }
        return count
    }
    
    // MARK: - Data Loading and Initialization
    
    private func loadData() {
        loadPhotoshootNotes()
        loadOrganizationPhotographers()
        loadSchools()
        loadScheduleForDate(reportDate)
        // selectedPhotographerId will be set in loadOrgPhotographers
        calculateMultiStopMileage()
    }
    
    // MARK: - Load Schedule for Default School Selection
    
    /// Loads the photographer's sessions for `date`. `isDateChange` resets the
    /// auto-select so a new date re-picks; foreground re-subscribes (isDateChange
    /// false) must NOT reset, or they'd clobber a manual pick.
    func loadScheduleForDate(_ date: Date, isDateChange: Bool = false) {
        print("📋 loadScheduleForDate called for date: \(date)")
        if isDateChange {
            sessionAutoSelected = false
            selectedSession = nil
        }
        isLoadingSchedule = true
        scheduleError = ""
        selectedDateSessions = []

        // Supabase uses async/await, no listener to stop

        // Create date range for the selected day
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Get current user ID for filtering
        guard let currentUserID = UserManager.shared.getCurrentUserID() else {
            print("🔐 Cannot filter sessions: no current user ID")
            self.isLoadingSchedule = false
            return
        }
        print("📋 Current user ID: \(currentUserID)")

        // Get current user email for fallback matching
        let currentUserEmail = UserDefaults.standard.string(forKey: "userEmail")

        let organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        guard !organizationID.isEmpty else {
            print("❌ Cannot load sessions: no organization ID")
            self.isLoadingSchedule = false
            return
        }
        print("📋 Organization ID: \(organizationID), calling startListeningToSessions...")

        // Load sessions from Supabase with real-time updates
        sessionService.startListeningToSessions(
            subscriptionId: subscriptionId,
            organizationID: organizationID,
            includeUnpublished: false  // Regular users see only published
        ) { sessions in
            DispatchQueue.main.async {
                print("📋 DailyJobReportView: Received \(sessions.count) total sessions")
                print("📋 Looking for sessions on: \(startOfDay) to \(endOfDay)")
                print("📋 Current user ID: \(currentUserID), email: \(currentUserEmail ?? "nil")")

                // Filter sessions for the selected date where current user is assigned
                let sessionsForDay = sessions.filter { session in
                    guard let sessionDate = session.startDate else {
                        print("📋 Session \(session.id) has no startDate (date: \(session.date), time: \(session.start_time))")
                        return false
                    }
                    let isSelectedDay = sessionDate >= startOfDay && sessionDate < endOfDay
                    let isUserAssigned = session.isUserAssigned(userID: currentUserID, userEmail: currentUserEmail)

                    if isSelectedDay {
                        print("📋 Session on selected day: \(session.schoolName) - photographers: \(session.photographers.map { "\($0.id):\($0.name)" })")
                        print("   isUserAssigned: \(isUserAssigned)")
                    }

                    return isSelectedDay && isUserAssigned
                }

                print("📋 Filtered to \(sessionsForDay.count) sessions for user on this day")
                self.selectedDateSessions = sessionsForDay

                // Auto-select the first session this photographer hasn't reported yet (D2, D3)
                self.isLoadingSchedule = false
                self.runAutoSelectIfReady()
            }
        }
    }
    
    /// Fetch the session IDs this photographer has ALREADY reported for the selected
    /// date. Keyed on session_id (D3) — precise, fixes same-school-twice-in-a-day.
    /// Legacy NULL-linked reports contribute nothing.
    func checkExistingReports(completion: @escaping ([String]) -> Void) {
        // Get start and end of the selected day
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: reportDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Get the selected photographer's name
        guard let photographer = photographers.first(where: { $0.id == selectedPhotographerId }) else {
            completion([])
            return
        }

        Task {
            do {
                // Query Supabase for reports on this date by this photographer
                let reports = try await DailyJobReportService.shared.getReports(
                    yourName: photographer.firstName,
                    organizationID: storedUserOrganizationID,
                    startDate: startOfDay,
                    endDate: endOfDay
                )

                // Extract the session IDs already reported (non-null only)
                let reportedSessionIds = reports.compactMap { $0.session_id }

                await MainActor.run {
                    completion(reportedSessionIds)
                }
            } catch {
                print("Error checking existing reports: \(error.localizedDescription)")
                await MainActor.run {
                    completion([])
                }
            }
        }
    }

    /// Runs auto-select exactly once per date, only when the inputs it depends on
    /// are ready: the photographer is known (so "already reported" is accurate, D3),
    /// the schedule has finished loading, and schools are loaded (so a session can
    /// resolve to a SchoolItem for the derived location/mileage). The session
    /// listener and the three async loaders all call this; the guard flag + the
    /// inner re-check make repeated calls idempotent and protect a manual pick.
    func runAutoSelectIfReady() {
        guard !sessionAutoSelected,
              !selectedPhotographerId.isEmpty,
              !isLoadingSchedule,
              !schoolOptions.isEmpty else { return }

        checkExistingReports { reportedSessionIds in
            guard !self.sessionAutoSelected else { return }
            self.autoSelectSession(reportedSessionIds: reportedSessionIds)
            self.sessionAutoSelected = true
        }
    }

    /// Auto-select the first un-reported session in schedule order (D2). If all
    /// sessions are reported, default to none and let the photographer pick (D5).
    /// With no sessions for the day, stay off-schedule and keep the existing
    /// photoshoot-note → manual-school fallback.
    func autoSelectSession(reportedSessionIds: [String]) {
        guard !selectedDateSessions.isEmpty else {
            selectedSession = nil
            // Off-schedule: keep the photoshoot-note → manual-school convenience
            if let note = selectedPhotoshootNote,
               let matchIndex = schoolOptions.firstIndex(where: { $0.name == note.school }),
               !selectedSchools.isEmpty {
                selectedSchools[0] = schoolOptions[matchIndex]
            }
            return
        }

        if let next = sortedSessionsForPicker.first(where: { !reportedSessionIds.contains($0.id) }) {
            selectedSession = next
            applySessionSelection(next)
        } else {
            // All sessions already reported → default to none (D5)
            selectedSession = nil
        }
    }

    /// Resolve location + mileage from the chosen session (D4, D6). A nil session
    /// reveals the manual off-schedule picker. The session's school_id resolves to
    /// the already-loaded SchoolItem (coordinates) → existing mileage calculation.
    func applySessionSelection(_ session: Session?) {
        guard let session = session else {
            // Off-schedule: reset to a single empty manual slot for the picker
            selectedSchools = [nil]
            calculateMultiStopMileage()
            return
        }

        // Prefer school_id match (robust); fall back to name match
        let match = schoolOptions.first(where: { $0.id == session.school_id })
            ?? schoolOptions.first(where: { $0.name == session.schoolName })
        selectedSchools = [match]

        // Attach a matching photoshoot note if one exists (existing convenience)
        if let note = photoshootNotes.first(where: { $0.school == session.schoolName }) {
            selectedPhotoshootNote = note
            loadPhotosFromNote(note)
        }

        // Session selection is the mileage trigger (D6)
        calculateMultiStopMileage()
    }
    
    // MARK: - Load / Save Photoshoot Notes
    func loadPhotoshootNotes() {
        if let decoded = try? JSONDecoder().decode([PhotoshootNote].self, from: storedNotesData) {
            photoshootNotes = decoded
            if photoshootNotes.count == 1 {
                selectedPhotoshootNote = photoshootNotes.first
                if let note = selectedPhotoshootNote {
                    loadPhotosFromNote(note)
                }
            }
        } else {
            photoshootNotes = []
        }
    }
    
    func savePhotoshootNotes() {
        if let encoded = try? JSONEncoder().encode(photoshootNotes) {
            storedNotesData = encoded
        }
    }
    
    // MARK: - Load Photographers
    func loadOrganizationPhotographers() {
        guard !storedUserOrganizationID.isEmpty else {
            print("No organizationID in AppStorage.")
            errorMessage = "Unable to load photographers: not signed in or organization not found"
            return
        }

        Task {
            do {
                let members = try await TeamService.shared.getTeamMembers(organizationID: storedUserOrganizationID)

                await MainActor.run {
                    var photogs: [PhotographerOption] = []
                    for member in members {
                        let photographer = PhotographerOption(
                            id: member.id,
                            firstName: member.firstName,
                            lastName: member.lastName ?? ""
                        )
                        photogs.append(photographer)
                    }
                    photogs.sort { $0.displayName.lowercased() < $1.displayName.lowercased() }
                    self.photographers = photogs

                    // Try to find and select the current user
                    if let currentUser = photogs.first(where: {
                        $0.firstName == self.storedUserFirstName &&
                        $0.lastName == self.storedUserLastName
                    }) {
                        self.selectedPhotographerId = currentUser.id
                    } else if let first = photogs.first {
                        self.selectedPhotographerId = first.id
                    }

                    // Photographer just resolved — "already reported" can now be keyed
                    // correctly, so attempt auto-select (no-op if it already ran).
                    self.runAutoSelectIfReady()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Load Schools
    func loadSchools() {
        guard !storedUserOrganizationID.isEmpty else {
            print("No organizationID in AppStorage - cannot load schools.")
            errorMessage = "Unable to load schools: not signed in or organization not found"
            return
        }

        Task {
            do {
                let schools = try await SchoolService.shared.getSchools(organizationID: storedUserOrganizationID)

                await MainActor.run {
                    // Convert School models to SchoolItem
                    var temp: [SchoolItem] = []
                    for school in schools {
                        // Build address from available fields
                        var addressComponents: [String] = []
                        if let street = school.street, !street.isEmpty {
                            addressComponents.append(street)
                        }
                        if let city = school.city, !city.isEmpty {
                            addressComponents.append(city)
                        }
                        if let state = school.state, !state.isEmpty {
                            addressComponents.append(state)
                        }
                        if let zip = school.zip, !zip.isEmpty {
                            addressComponents.append(zip)
                        }
                        let address = addressComponents.isEmpty ? school.value : addressComponents.joined(separator: ", ")

                        temp.append(SchoolItem(
                            id: school.id,
                            name: school.value,
                            address: address,
                            coordinates: school.coordinates
                        ))
                    }
                    temp.sort { $0.name.lowercased() < $1.name.lowercased() }

                    // Only update schoolOptions if the data actually changed to prevent re-renders
                    if !areSchoolListsEqual(self.schoolOptions, temp) {
                        self.schoolOptions = temp
                    }

                    // Now that we have schools loaded, check if we need to set defaults
                    if let note = self.selectedPhotoshootNote,
                       let match = temp.first(where: { $0.name == note.school }) {
                        if !self.selectedSchools.isEmpty {
                            self.selectedSchools[0] = match
                        }
                    } else if let first = temp.first {
                        if self.selectedSchools[0] == nil {
                            self.selectedSchools[0] = first
                        }
                    }

                    // Schools just loaded — a session can now resolve to a SchoolItem
                    self.runAutoSelectIfReady()

                    self.calculateMultiStopMileage()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    func areSchoolListsEqual(_ list1: [SchoolItem], _ list2: [SchoolItem]) -> Bool {
        guard list1.count == list2.count else { return false }
        for i in 0..<list1.count {
            if list1[i].id != list2[i].id || 
               list1[i].name != list2[i].name ||
               list1[i].address != list2[i].address {
                return false
            }
        }
        return true
    }
    
    func parseCoordinateString(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    func requestDirections(from originCoord: CLLocationCoordinate2D,
                           to destCoord: CLLocationCoordinate2D,
                           completion: @escaping (Double?) -> Void) {
        let request = MKDirections.Request()
        request.transportType = .automobile
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: originCoord))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
        
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            if let error = error {
                print("Directions error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let route = response?.routes.first else {
                print("No route found.")
                completion(nil)
                return
            }
            let distanceMiles = route.distance * 0.000621371
            print("Route distance (meters): \(route.distance)")
            print("Calculated one-way distance in miles: \(distanceMiles)")
            completion(distanceMiles)
        }
    }
    
    func geocodeAndRequestDirections(
        originString: String? = nil,
        destinationString: String? = nil,
        originCoord: CLLocationCoordinate2D? = nil,
        destinationCoord: CLLocationCoordinate2D? = nil,
        completion: @escaping (Double?) -> Void
    ) {
        let geocoder = CLGeocoder()
        
        var finalOrigin: CLLocationCoordinate2D?
        var finalDestination: CLLocationCoordinate2D?
        
        let group = DispatchGroup()
        
        if let originString = originString, originCoord == nil {
            group.enter()
            geocoder.geocodeAddressString(originString) { placemarks, error in
                defer { group.leave() }
                if let loc = placemarks?.first?.location {
                    finalOrigin = loc.coordinate
                } else {
                    print("Origin geocoding failed for: \(originString)")
                }
            }
        } else if let originCoord = originCoord {
            finalOrigin = originCoord
        }
        
        if let destinationString = destinationString, destinationCoord == nil {
            group.enter()
            geocoder.geocodeAddressString(destinationString) { placemarks, error in
                defer { group.leave() }
                if let loc = placemarks?.first?.location {
                    finalDestination = loc.coordinate
                } else {
                    print("Destination geocoding failed for: \(destinationString)")
                }
            }
        } else if let destinationCoord = destinationCoord {
            finalDestination = destinationCoord
        }
        
        group.notify(queue: .main) {
            guard let oCoord = finalOrigin, let dCoord = finalDestination else {
                completion(nil)
                return
            }
            self.requestDirections(from: oCoord, to: dCoord, completion: completion)
        }
    }
    
    func calculateOneWayMileage(from origin: String, to destination: String, completion: @escaping (Double?) -> Void) {
        if let originCoord = parseCoordinateString(origin) {
            print("Parsed origin as lat/lon: \(originCoord.latitude), \(originCoord.longitude)")
            if let destCoord = parseCoordinateString(destination) {
                print("Parsed destination as lat/lon: \(destCoord.latitude), \(destCoord.longitude)")
                requestDirections(from: originCoord, to: destCoord, completion: completion)
            } else {
                geocodeAndRequestDirections(
                    originString: nil,
                    destinationString: destination,
                    originCoord: originCoord,
                    destinationCoord: nil,
                    completion: completion
                )
            }
        } else {
            if let destCoord = parseCoordinateString(destination) {
                geocodeAndRequestDirections(
                    originString: origin,
                    destinationString: nil,
                    originCoord: nil,
                    destinationCoord: destCoord,
                    completion: completion
                )
            } else {
                geocodeAndRequestDirections(
                    originString: origin,
                    destinationString: destination,
                    originCoord: nil,
                    destinationCoord: nil,
                    completion: completion
                )
            }
        }
    }
    
    func calculateMultiStopMileage() {
        guard !storedUserHomeAddress.isEmpty else { 
            print("Cannot calculate mileage: No home address set for user")
            totalMileage = ""
            return 
        }
        
        var stops: [String] = [storedUserHomeAddress]

        // Use coordinates when available for reliable distance calculation
        // Fall back to address only if coordinates are missing
        let selectedStops = selectedSchools.compactMap { school -> String? in
            guard let school = school else { return nil }
            // Prefer coordinates (format: "lat,lng") - can be parsed directly, no geocoding needed
            if let coords = school.coordinates, !coords.isEmpty {
                return coords
            }
            // Fall back to address (requires geocoding, may fail for bare school names)
            return school.address.isEmpty ? nil : school.address
        }

        stops.append(contentsOf: selectedStops)
        stops.append(storedUserHomeAddress)
        
        print("Calculating mileage with stops: \(stops)")
        
        totalMileage = "Calculating..."
        var totalDistance: Double = 0.0
        let group = DispatchGroup()
        
        for i in 0..<stops.count - 1 {
            group.enter()
            calculateOneWayMileage(from: stops[i], to: stops[i+1]) { miles in
                if let miles = miles {
                    totalDistance += miles
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.totalMileage = String(format: "%.1f", totalDistance)
            let combinedSchoolNames = self.selectedSchools.compactMap { $0?.name }.joined(separator: ", ")
            print("Combined school names: \(combinedSchoolNames)")
        }
    }
    
    // MARK: - New Function to Load Photos from Photoshoot Note
    
    private func loadPhotosFromNote(_ note: PhotoshootNote) {
        // Check if the note has photoURLs field
        guard !note.photoURLs.isEmpty else {
            return
        }
        
        // Convert the URL strings to UIImages and add them to selectedImages
        for urlString in note.photoURLs {
            if let url = URL(string: urlString) {
                URLSession.shared.dataTask(with: url) { data, response, error in
                    if let error = error {
                        print("Error downloading image: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let data = data, let image = UIImage(data: data) else {
                        print("Error converting data to image")
                        return
                    }
                    
                    DispatchQueue.main.async {
                        // Add the image to the selected images if it's not already there
                        if !self.selectedImages.contains(where: { existingImage in
                            // Compare images by their data since UIImage doesn't conform to Equatable
                            let existingData = existingImage.jpegData(compressionQuality: 1.0)
                            let newData = image.jpegData(compressionQuality: 1.0)
                            return existingData == newData
                        }) {
                            self.selectedImages.append(image)
                        }
                    }
                }.resume()
            }
        }
    }
    
    // The vehicle type is confirmed at selection time (a tap opens a dialog that
    // requires re-selecting it). Here we only guard that a choice was made at all.
    func attemptSubmit() {
        guard vehicleType == "personal" || vehicleType == "company" else {
            errorMessage = "Please select whether this was your Personal vehicle or a Company vehicle before submitting."
            return
        }
        submitReport()
    }

    func submitReport() {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified() else {
            errorMessage = "User not signed in."
            return
        }
        isSubmitting = true
        errorMessage = ""

        let mileage = Double(totalMileage) ?? calculatedMileage
        var photoURLs: [String] = []

        func finishSubmission() {
            let jobDescriptionArray = Array(selectedJobDescriptions)
            let extraItemsArray = Array(selectedExtraItems)
            let combinedSchoolNames = selectedSchools.compactMap { $0?.name }.joined(separator: ", ")
            // Always store school_or_destination (D7). When a session is selected but
            // its school didn't resolve to a SchoolItem, fall back to the session's
            // own school name so the destination is never lost.
            let schoolOrDestination = combinedSchoolNames.isEmpty
                ? selectedSession?.schoolName
                : combinedSchoolNames

            // Include photo URLs from the selected photoshoot note if available
            if let note = selectedPhotoshootNote {
                photoURLs.append(contentsOf: note.photoURLs)
            }

            let yourName = photographers.first(where: { $0.id == selectedPhotographerId })?.firstName ?? ""

            // Create DailyJobReport for Supabase
            let report = DailyJobReport(
                id: UUID().uuidString,
                organizationID: storedUserOrganizationID,
                userId: currentUserId,
                date: reportDate,
                yourName: yourName,
                schoolOrDestination: schoolOrDestination,
                sessionId: selectedSession?.id,
                sessionName: selectedSession?.reportDisplayLabel,
                totalMileage: mileage,
                vehicleType: vehicleType,
                jobDescriptions: jobDescriptionArray.isEmpty ? nil : jobDescriptionArray,
                extraItems: extraItemsArray.isEmpty ? nil : extraItemsArray,
                cardsScannedChoice: cardsScannedChoice.isEmpty ? nil : cardsScannedChoice,
                jobBoxAndCameraCards: jobBoxAndCameraCards.isEmpty ? nil : jobBoxAndCameraCards,
                sportsBackgroundShot: sportsBackgroundShot.isEmpty ? nil : sportsBackgroundShot,
                jobDescriptionText: jobDescription.isEmpty ? nil : jobDescription,
                photoshootNoteID: selectedPhotoshootNote?.id.uuidString,
                photoshootNoteText: selectedPhotoshootNote?.noteText,
                photoURLs: photoURLs.isEmpty ? nil : photoURLs,
                reportType: "standard"
            )

            Task {
                do {
                    let createdReport = try await DailyJobReportService.shared.createReport(report)

                    // If note is attached, link it to the report in the photoshoot_notes table
                    if let selectedNote = self.selectedPhotoshootNote {
                        do {
                            try await PhotoshootNoteService.shared.attachToReport(
                                noteId: selectedNote.id,
                                reportId: createdReport.id
                            )
                            print("✅ Linked note \(selectedNote.id) to report \(createdReport.id)")
                        } catch {
                            print("⚠️ Failed to link note to report: \(error.localizedDescription)")
                            // Don't fail the entire submission if this fails
                        }
                    }

                    await MainActor.run {
                        self.isSubmitting = false

                        // Remove the used note now that its content is saved in the report.
                        // Do NOT delete its photos — those URLs were copied into the report above.
                        if let selectedNote = self.selectedPhotoshootNote,
                           let index = self.photoshootNotes.firstIndex(of: selectedNote) {
                            self.photoshootNotes.remove(at: index)
                            self.savePhotoshootNotes()
                            print("✅ Removed used photoshoot note from local storage")
                            Task {
                                try? await PhotoshootNoteService.shared.deleteNote(id: selectedNote.id)
                            }
                        }

                        // Post notification to show toast on main view
                        NotificationCenter.default.post(name: Notification.Name("ShowReportSuccessToast"), object: nil)

                        // Return to home tab
                        self.tabBarManager.selectedTab = "home"
                    }
                } catch {
                    await MainActor.run {
                        self.isSubmitting = false
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }

        guard !selectedImages.isEmpty else {
            print("📋 No photos to upload, submitting report directly")
            finishSubmission()
            return
        }

        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "Cannot upload photos: no organization ID found"
            finishSubmission()
            return
        }

        print("📸 Starting upload of \(selectedImages.count) photo(s) to Supabase Storage...")

        // Upload photos to Supabase Storage
        Task {
            let supabase = SupabaseManager.shared.client

            for (index, image) in selectedImages.enumerated() {
                print("📸 Processing photo \(index + 1) of \(selectedImages.count)...")

                guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                    print("❌ Photo \(index + 1): Failed to convert UIImage to JPEG data")
                    continue
                }

                print("📸 Photo \(index + 1): Created JPEG data (\(imageData.count) bytes)")

                // Create unique file path: orgId/userId/timestamp_uuid.jpg
                let fileName = "\(storedUserOrganizationID)/\(currentUserId)/\(Date().timeIntervalSince1970)_\(UUID().uuidString).jpg"
                print("📸 Photo \(index + 1): Uploading to path: \(fileName)")

                do {
                    // Upload to Supabase Storage bucket "daily-reports" (private bucket)
                    // File extension .jpg tells Supabase the content type
                    _ = try await supabase.storage
                        .from("daily-reports")
                        .upload(path: fileName, file: imageData)

                    print("📸 Photo \(index + 1): Upload complete, getting signed URL...")

                    // Get a signed URL for the uploaded file (valid for 1 year)
                    let signedURL = try await supabase.storage
                        .from("daily-reports")
                        .createSignedURL(path: fileName, expiresIn: 31536000) // 1 year in seconds

                    print("✅ Photo \(index + 1): Upload successful: \(signedURL.absoluteString.prefix(80))...")
                    photoURLs.append(signedURL.absoluteString)

                } catch {
                    print("❌ Photo \(index + 1): Supabase Storage upload failed: \(error.localizedDescription)")
                    await MainActor.run {
                        self.errorMessage = "Upload error: \(error.localizedDescription)"
                    }
                }
            }

            print("📸 Photo upload complete. \(photoURLs.count) URL(s) ready for report")

            await MainActor.run {
                finishSubmission()
            }
        }
    }
}

// MARK: - Custom UI Components



// MARK: - Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
