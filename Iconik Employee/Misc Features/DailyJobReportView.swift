import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import CoreLocation
import MapKit

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
    @State private var orgPhotographerNames: [String] = []
    @State private var schoolOptions: [SchoolItem] = []
    
    // ------------------------------------------------------------------
    // Selected fields
    // ------------------------------------------------------------------
    @State private var selectedPhotographer: String = ""
    // Dynamic list for multiple school selections
    @State private var selectedSchools: [SchoolItem?] = [nil] // Start with one dropdown
    
    // ------------------------------------------------------------------
    // Schedule data
    // ------------------------------------------------------------------
    @State private var selectedDateSessions: [Session] = []
    @State private var isLoadingSchedule: Bool = false
    @State private var scheduleError: String = ""
    @State private var scheduleListener: ListenerRegistration?
    
    // ------------------------------------------------------------------
    // Other report fields
    // ------------------------------------------------------------------
    @State private var reportDate: Date = Date()
    @State private var totalMileage: String = ""
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
    
    // ------------------------------------------------------------------
    // NEW: Success Alert
    // ------------------------------------------------------------------
    @State private var showSuccessAlert: Bool = false
    @Environment(\.presentationMode) var presentationMode
    
    // ------------------------------------------------------------------
    // UI State Management - All sections expanded by default
    // ------------------------------------------------------------------
    @State private var expandedSections: Set<FormSection> = Set(FormSection.allCases)
    
    // Arrays for the radio questions
    let yesNoNaOptions = ["Yes", "No", "NA"]
    let yesNoOptions   = ["Yes", "No"]
    
    // Full ICS URL from Sling
    private let sessionService = SessionService.shared
    
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
        ZStack {
            backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                
                // Progress bar
                progressView
                
                // Main content with sections
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(FormSection.allCases) { section in
                            let isExpanded = expandedSections.contains(section)
                            sectionCard(for: section, isExpanded: isExpanded)
                        }
                        
                        // Submit button
                        submitButton
                            .padding(.vertical, 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            loadData()
        }
        .onDisappear {
            // Clean up real-time listener
            scheduleListener?.remove()
        }
        .alert(isPresented: $showSuccessAlert) {
            Alert(
                title: Text("Success"),
                message: Text("Report submitted successfully."),
                dismissButton: .default(Text("OK")) {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
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
            
            DatePicker("Report Date", selection: $reportDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .onChange(of: reportDate) { newDate in
                    loadScheduleForDate(newDate)
                }
                .padding()
                .background(inputFieldBackground)
                .cornerRadius(8)
            
            if orgPhotographerNames.isEmpty {
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
                    
                    Picker("", selection: $selectedPhotographer) {
                        ForEach(orgPhotographerNames, id: \.self) { name in
                            Text(name).tag(name)
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
            } else if photoshootNotes.count == 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Using note from \(photoshootNotes.first!.timestamp, style: .time)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(photoshootNotes.first!.school)
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
                            Picker("", selection: Binding(
                                get: { selectedSchools[index] },
                                set: { newValue in
                                    selectedSchools[index] = newValue
                                    calculateMultiStopMileage()
                                }
                            )) {
                                Text("Select a school").tag(nil as SchoolItem?)
                                ForEach(schoolOptions, id: \.id) { school in
                                    Text(school.name).tag(school as SchoolItem?)
                                }
                            }
                            .pickerStyle(.menu)
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
    
    private var submitButton: some View {
        Button(action: submitReport) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Submit Report")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding()
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 16)
        }
        .disabled(isSubmitting)
    }
    
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
            return !selectedPhotographer.isEmpty && reportDate != nil
            
        case .photoshootNote:
            // This section is optional, marked complete if a note is selected
            return selectedPhotoshootNote != nil
            
        case .schools:
            // Complete if at least one school is selected and mileage is entered
            return selectedSchools.first != nil &&
                   selectedSchools.first! != nil &&
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
        selectedPhotographer = storedUserFirstName
        calculateMultiStopMileage()
    }
    
    // MARK: - Load Schedule for Default School Selection
    
    func loadScheduleForDate(_ date: Date) {
        isLoadingSchedule = true
        scheduleError = ""
        selectedDateSessions = []
        
        // Remove any existing listener
        scheduleListener?.remove()
        
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
        
        // Load sessions from Firestore with real-time updates
        scheduleListener = sessionService.listenForSessions { sessions in
            DispatchQueue.main.async {
                
                // Filter sessions for the selected date where current user is assigned
                let sessionsForDay = sessions.filter { session in
                    guard let sessionDate = session.startDate else { return false }
                    let isSelectedDay = sessionDate >= startOfDay && sessionDate < endOfDay
                    let isUserAssigned = session.isUserAssigned(userID: currentUserID)
                    return isSelectedDay && isUserAssigned
                }
                
                self.selectedDateSessions = sessionsForDay
                
                // Check if we have completed a report for this date and school already
                self.checkExistingReports { completedSchools in
                    // Try to set the default school from schedule
                    self.setDefaultSchoolFromSchedule(completedSchools: completedSchools)
                    self.isLoadingSchedule = false
                }
            }
        }
    }
    
    func checkExistingReports(completion: @escaping ([String]) -> Void) {
        // Get start and end of the selected day for Firestore query
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: reportDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Query Firestore for reports on this date by this user
        let db = Firestore.firestore()
        db.collection("dailyJobReports")
            .whereField("yourName", isEqualTo: selectedPhotographer)
            .whereField("date", isGreaterThanOrEqualTo: startOfDay)
            .whereField("date", isLessThanOrEqualTo: endOfDay)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error checking existing reports: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                // Extract school names from completed reports
                let schoolNames = documents.compactMap { doc -> String? in
                    let data = doc.data()
                    return data["schoolOrDestination"] as? String
                }
                
                completion(schoolNames)
            }
    }
    
    func setDefaultSchoolFromSchedule(completedSchools: [String]) {
        // No sessions for selected date in schedule
        if selectedDateSessions.isEmpty {
            if selectedPhotoshootNote != nil {
                // Already have a photoshoot note selected, use that
                if let note = selectedPhotoshootNote,
                   let matchIndex = schoolOptions.firstIndex(where: { $0.name == note.school }) {
                    if !selectedSchools.isEmpty {
                        selectedSchools[0] = schoolOptions[matchIndex]
                    }
                }
            }
            return
        }
        
        // Sort sessions by start time, so we get the earliest one first
        let sortedSessions = selectedDateSessions.sorted { (a, b) -> Bool in
            guard let aStart = a.startDate, let bStart = b.startDate else { return false }
            return aStart < bStart
        }
        
        // Look for the first session at a school we haven't already completed
        for session in sortedSessions {
            let schoolName = session.schoolName
            
            // Skip if we've already completed a report for this school today
            if completedSchools.contains(schoolName) {
                continue
            }
            
            // Find matching school in our options
            if let matchIndex = schoolOptions.firstIndex(where: { $0.name == schoolName }) {
                // Found a match - set it as the selected school
                if !selectedSchools.isEmpty {
                    selectedSchools[0] = schoolOptions[matchIndex]
                    
                    // Try to find matching photoshoot note
                    let matchingNote = photoshootNotes.first { note in
                        note.school == schoolName
                    }
                    
                    if let note = matchingNote {
                        selectedPhotoshootNote = note
                        
                        // Load photos from the selected note
                        loadPhotosFromNote(note)
                    }
                    
                    // Calculate mileage with the new school selection
                    calculateMultiStopMileage()
                    return
                }
            }
        }
        
        // If we get here, we either didn't find a valid school, or all schools already have reports
        // We'll leave the current selection in place
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
            return
        }
        let db = Firestore.firestore()
        db.collection("users")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID)
            .getDocuments { snapshot, error in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else { return }
                var names: [String] = []
                for doc in docs {
                    let data = doc.data()
                    if let fname = data["firstName"] as? String {
                        names.append(fname)
                    }
                }
                names.sort { $0.lowercased() < $1.lowercased() }
                self.orgPhotographerNames = names
                if names.contains(self.storedUserFirstName) {
                    self.selectedPhotographer = self.storedUserFirstName
                } else if let first = names.first {
                    self.selectedPhotographer = first
                }
            }
    }
    
    // MARK: - Load Schools
    func loadSchools() {
        let db = Firestore.firestore()
        db.collection("schools")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID)
            .getDocuments { snapshot, error in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else { return }
                var temp: [SchoolItem] = []
                for doc in docs {
                    let data = doc.data()
                    if let value = data["value"] as? String,
                       let address = data["schoolAddress"] as? String {
                        temp.append(SchoolItem(id: doc.documentID, name: value, address: address))
                    }
                }
                temp.sort { $0.name.lowercased() < $1.name.lowercased() }
                self.schoolOptions = temp
                
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
                
                // Try to set school from schedule
                if self.isLoadingSchedule == false && !self.selectedDateSessions.isEmpty {
                    self.checkExistingReports { completedSchools in
                        self.setDefaultSchoolFromSchedule(completedSchools: completedSchools)
                    }
                }
                
                self.calculateMultiStopMileage()
            }
    }
    
    // MARK: - Helper Functions
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
        guard !storedUserHomeAddress.isEmpty else { return }
        
        var stops: [String] = [storedUserHomeAddress]
        let selectedAddresses = selectedSchools.compactMap { $0?.address }
        stops.append(contentsOf: selectedAddresses)
        stops.append(storedUserHomeAddress)
        
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
    
    func submitReport() {
        guard let user = Auth.auth().currentUser else {
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
            
            // Include photo URLs from the selected photoshoot note if available
            if let note = selectedPhotoshootNote {
                photoURLs.append(contentsOf: note.photoURLs)
            }
            
            let db = Firestore.firestore()
            let reportData: [String: Any] = [
                "organizationID": storedUserOrganizationID,
                "date": reportDate,
                "yourName": selectedPhotographer,
                "userId": user.uid,  // New field for user ID
                "photoshootNoteID": selectedPhotoshootNote?.id.uuidString ?? "",
                "photoshootNoteText": selectedPhotoshootNote?.noteText ?? "",
                "schoolOrDestination": combinedSchoolNames,
                "totalMileage": mileage,
                "jobDescriptions": jobDescriptionArray,
                "extraItems": extraItemsArray,
                "cardsScannedChoice": cardsScannedChoice,
                "jobBoxAndCameraCards": jobBoxAndCameraCards,
                "sportsBackgroundShot": sportsBackgroundShot,
                "jobDescriptionText": jobDescription,
                "photoURLs": photoURLs,
                "timestamp": FieldValue.serverTimestamp()
            ]
            
            db.collection("dailyJobReports").addDocument(data: reportData) { error in
                self.isSubmitting = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    if let selectedNote = self.selectedPhotoshootNote,
                       let index = self.photoshootNotes.firstIndex(of: selectedNote) {
                        self.photoshootNotes.remove(at: index)
                        self.savePhotoshootNotes()
                    }
                    self.showSuccessAlert = true
                }
            }
        }
        
        guard !selectedImages.isEmpty else {
            finishSubmission()
            return
        }
        
        let storageRef = Storage.storage().reference()
        let dispatchGroup = DispatchGroup()
        
        for image in selectedImages {
            dispatchGroup.enter()
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                let fileName = "dailyReports/\(user.uid)/\(Date().timeIntervalSince1970)_\(UUID().uuidString).jpg"
                let imageRef = storageRef.child(fileName)
                
                imageRef.putData(imageData, metadata: nil) { _, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.errorMessage = "Upload error: \(error.localizedDescription)"
                        }
                        dispatchGroup.leave()
                        return
                    }
                    imageRef.downloadURL { url, error in
                        if let error = error {
                            DispatchQueue.main.async {
                                self.errorMessage = "URL error: \(error.localizedDescription)"
                            }
                        } else if let urlString = url?.absoluteString {
                            photoURLs.append(urlString)
                        }
                        dispatchGroup.leave()
                    }
                }
            } else {
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            finishSubmission()
        }
    }
}

// MARK: - Custom UI Components

/// Modern Checkbox Row
struct ModernCheckboxRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.blue : Color.gray, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                    }
                }
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Modern Segmented Button
struct ModernSegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected ?
                        Color.blue.opacity(colorScheme == .dark ? 0.3 : 0.2) :
                        Color.clear
                )
                .foregroundColor(isSelected ? .blue : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

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
