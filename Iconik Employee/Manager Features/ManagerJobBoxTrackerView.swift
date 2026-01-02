import SwiftUI
import Supabase

struct JobBoxWithEvent: Identifiable {
    let id: String
    let jobBox: JobBox
    let schoolName: String
    let date: Date
    let photographerName: String
    let position: String
    let jobboxNumber: String
    let cardNumber: String
    
    // Computed property to determine if the job box is stalled
    var isStalled: Bool {
        let threshold = JobBoxSettingsManager.shared.getStalledThreshold(for: jobBox.jobBoxStatus)
        let thresholdDate = Date().addingTimeInterval(-threshold)
        return jobBox.timestampDate < thresholdDate && jobBox.jobBoxStatus != .turnedIn
    }

    // Time since last status change
    var timeSinceUpdate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: jobBox.timestampDate, relativeTo: Date())
    }
}

enum JobBoxFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case stalled = "Stalled"
    case today = "Today"
    case completed = "Completed"
}

enum JobBoxSort: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case schoolName = "School Name"
    case photographer = "Photographer"
    case jobboxNumber = "Job Box Number"
    case status = "Status"
}

enum JobBoxStatusFilter: String, CaseIterable {
    case all = "All Statuses"
    case packed = "Packed"
    case pickedUp = "Picked Up"
    case leftJob = "Left Job"
    case turnedIn = "Turned In"
    
    var correspondingStatus: JobBoxStatus? {
        switch self {
        case .all:
            return nil
        case .packed:
            return .packed
        case .pickedUp:
            return .pickedUp
        case .leftJob:
            return .leftJob
        case .turnedIn:
            return .turnedIn
        }
    }
}

class ManagerJobBoxViewModel: ObservableObject {
    // Supabase model for job boxes (must be at class scope)
    struct SupabaseJobBox: Decodable {
        let id: String
        let shift_uid: String?
        let status: String?
        let photographer: String?
        let updated_at: Date?
        let box_number: String?
        let organization_id: String?
        let school: String?
        let school_id: String?
        let user_id: String?
        let jobbox_number: String?
        let card_number: String?
        let card_id: String?
        let event_date: Date?
        let scanned_by: String?
    }

    @Published var allJobBoxes: [JobBoxWithEvent] = []
    @Published var selectedFilter: JobBoxFilter = .active
    @Published var selectedSort: JobBoxSort = .newestFirst
    @Published var selectedStatusFilter: JobBoxStatusFilter = .all
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""

    @Published var selectedDate: Date = Date()
    @Published var showDatePicker: Bool = false

    // Flag to indicate if we're searching by card number
    private var isSearchingByCardNumber: Bool = false

    // Store organization ID
    private var organizationID: String = ""

    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    init() {
        // Don't load job boxes until organization ID is set
    }
    
    func setOrganizationID(_ orgID: String) {
        self.organizationID = orgID
        if !orgID.isEmpty {
            loadJobBoxes()
        }
    }
    
    // Load all job boxes
    func loadJobBoxes() {
        // Don't load if organization ID is not set
        guard !organizationID.isEmpty else {
            errorMessage = "Organization ID not set"
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = ""

        // Check if we're searching by card number (numeric search)
        isSearchingByCardNumber = !searchText.isEmpty && searchText.rangeOfCharacter(from: .decimalDigits) != nil &&
            searchText.rangeOfCharacter(from: .letters) == nil

        // Query all job boxes
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        Task {
            do {
                var jobBoxes: [SupabaseJobBox]

                // Build query based on filters
                if selectedFilter == .today && !isSearchingByCardNumber {
                    let startOfDay = calendar.startOfDay(for: Date())
                    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

                    jobBoxes = try await supabase
                        .from("job_boxes")
                        .select()
                        .eq("organization_id", value: organizationID)
                        .gte("updated_at", value: startOfDay.ISO8601Format())
                        .lt("updated_at", value: endOfDay.ISO8601Format())
                        .execute()
                        .value
                } else {
                    jobBoxes = try await supabase
                        .from("job_boxes")
                        .select()
                        .eq("organization_id", value: organizationID)
                        .gte("updated_at", value: thirtyDaysAgo.ISO8601Format())
                        .execute()
                        .value
                }

                await self.processJobBoxRecords(jobBoxes)
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Error loading job boxes: \(error.localizedDescription)"
                }
            }
        }
    }

    private func processJobBoxRecords(_ records: [SupabaseJobBox]) async {
        // This will hold all job boxes
        var allBoxes: [JobBoxWithEvent] = []

        // Process each record
        for record in records {
            // Create JobBox from Supabase record
            let jobBox = JobBox(
                id: record.id,
                shift_uid: record.shift_uid ?? "",
                status: record.status ?? "Unknown",
                photographer: record.photographer ?? record.scanned_by ?? "Unknown",
                updated_at: record.updated_at,
                box_number: record.box_number ?? record.jobbox_number,
                organization_id: record.organization_id ?? "",
                school: record.school,
                school_id: record.school_id,
                user_id: record.user_id
            )

            let schoolName = record.school ?? "Unknown School"
            let jobboxNumber = record.jobbox_number ?? record.box_number ?? ""
            let cardNumber = record.card_number ?? record.card_id ?? ""
            let date = record.event_date ?? jobBox.updated_at ?? Date()
            let photographerName = record.scanned_by ?? record.photographer ?? "Unknown"

            // Create JobBoxWithEvent object
            let jobBoxWithEvent = JobBoxWithEvent(
                id: jobBox.id,
                jobBox: jobBox,
                schoolName: schoolName,
                date: date,
                photographerName: photographerName,
                position: "Unknown",
                jobboxNumber: jobboxNumber,
                cardNumber: cardNumber
            )

            // Add to the array
            allBoxes.append(jobBoxWithEvent)
        }

        await MainActor.run {
            // First apply search filter to all boxes
            let filteredBoxes = self.filterJobBoxesBySearch(allBoxes)

            // If we're searching for a specific card number, show all results for that card
            if self.isSearchingByCardNumber {
                self.allJobBoxes = self.sortJobBoxes(filteredBoxes)
                self.isLoading = false
                return
            }

            // Group by card number and get only the latest status for each
            let groupedBoxes = Dictionary(grouping: filteredBoxes) { box -> String in
                // Group by card number, or use jobbox number as fallback
                return !box.cardNumber.isEmpty ? box.cardNumber : box.jobboxNumber
            }

            // For each group, get only the latest status
            var latestStatusBoxes: [JobBoxWithEvent] = []

            for (_, boxes) in groupedBoxes {
                // Sort by timestamp (newest first) and take only the first one
                if let latestBox = boxes.sorted(by: { $0.jobBox.timestampDate > $1.jobBox.timestampDate }).first {
                    latestStatusBoxes.append(latestBox)
                }
            }

            // IMPORTANT: Apply status filter AFTER determining the latest status
            // This ensures we only see boxes currently at a specific status
            if self.selectedStatusFilter != .all {
                if let status = self.selectedStatusFilter.correspondingStatus {
                    latestStatusBoxes = latestStatusBoxes.filter { $0.jobBox.jobBoxStatus == status }
                }
            }

            // Process the 'stalled' filter separately
            if self.selectedFilter == .stalled {
                latestStatusBoxes = latestStatusBoxes.filter { $0.isStalled }
            }

            // Apply active/completed filter after getting the latest status
            if self.selectedFilter == .active {
                // For Active tab, filter out cards where most recent status is "turned in"
                latestStatusBoxes = latestStatusBoxes.filter { $0.jobBox.jobBoxStatus != .turnedIn }
            } else if self.selectedFilter == .completed {
                // For Completed tab, only show cards where most recent status is "turned in"
                latestStatusBoxes = latestStatusBoxes.filter { $0.jobBox.jobBoxStatus == .turnedIn }
            }

            // Apply sort
            self.allJobBoxes = self.sortJobBoxes(latestStatusBoxes)
            self.isLoading = false
        }
    }

    // Filter job boxes based on search text
    func filterJobBoxesBySearch(_ jobBoxes: [JobBoxWithEvent]) -> [JobBoxWithEvent] {
        if searchText.isEmpty {
            return jobBoxes
        }
        
        let searchTextLower = searchText.lowercased()
        return jobBoxes.filter { jobBox in
            // If searching by card number (only digits), match only that
            if isSearchingByCardNumber {
                return jobBox.cardNumber.lowercased().contains(searchTextLower) ||
                       jobBox.jobboxNumber.lowercased().contains(searchTextLower)
            } else {
                // Otherwise, search across all fields
                return jobBox.schoolName.lowercased().contains(searchTextLower) ||
                       jobBox.photographerName.lowercased().contains(searchTextLower) ||
                       jobBox.jobboxNumber.lowercased().contains(searchTextLower) ||
                       jobBox.cardNumber.lowercased().contains(searchTextLower)
            }
        }
    }
    
    // Sort job boxes based on the selected sort option
    func sortJobBoxes(_ jobBoxes: [JobBoxWithEvent]) -> [JobBoxWithEvent] {
        switch selectedSort {
        case .newestFirst:
            return jobBoxes.sorted { $0.jobBox.timestampDate > $1.jobBox.timestampDate }

        case .oldestFirst:
            return jobBoxes.sorted { $0.jobBox.timestampDate < $1.jobBox.timestampDate }

        case .schoolName:
            return jobBoxes.sorted { $0.schoolName < $1.schoolName }

        case .photographer:
            return jobBoxes.sorted { $0.photographerName < $1.photographerName }

        case .jobboxNumber:
            return jobBoxes.sorted { $0.jobboxNumber < $1.jobboxNumber }

        case .status:
            return jobBoxes.sorted { statusPriority($0.jobBox.jobBoxStatus) < statusPriority($1.jobBox.jobBoxStatus) }
        }
    }
    
    // Helper function to determine status priority for sorting (optimized version)
    private func statusPriority(_ status: JobBoxStatus) -> Int {
        if status == .packed { return 0 }
        if status == .pickedUp { return 1 }
        if status == .leftJob { return 2 }
        return 3 // Must be .turnedIn
    }
    
    // Apply filters and sorting
    func applyFiltersAndSort() {
        loadJobBoxes()
    }
    
    // Manually update a job box status
    func updateJobBoxStatus(jobBox: JobBoxWithEvent, newStatus: JobBoxStatus) {
        Task {
            do {
                let updateData: [String: AnyJSON] = [
                    "status": .string(newStatus.rawValue),
                    "updated_at": .string(Date().ISO8601Format())
                ]

                try await supabase
                    .from("job_boxes")
                    .update(updateData)
                    .eq("id", value: jobBox.id)
                    .execute()

                await MainActor.run {
                    self.loadJobBoxes()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error updating job box: \(error.localizedDescription)"
                }
            }
        }
    }

    // Flag a job box for attention
    func flagJobBox(jobBox: JobBoxWithEvent, note: String) {
        Task {
            do {
                let updateData: [String: AnyJSON] = [
                    "flagged": .bool(true),
                    "flag_note": .string(note),
                    "flagged_at": .string(Date().ISO8601Format())
                ]

                try await supabase
                    .from("job_boxes")
                    .update(updateData)
                    .eq("id", value: jobBox.id)
                    .execute()

                await MainActor.run {
                    self.loadJobBoxes()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error flagging job box: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Format date for display
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct ManagerJobBoxTrackerView: View {
    @StateObject private var viewModel = ManagerJobBoxViewModel()
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    
    // State for the job box being edited
    @State private var selectedJobBox: JobBoxWithEvent? = nil
    @State private var showingEditSheet = false
    @State private var showingFlagSheet = false
    @State private var showingSettingsSheet = false
    @State private var flagNote = ""
    
    // State for expanded filters
    @State private var showAdvancedFilters: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Dashboard header
            VStack(spacing: 8) {
                Text("Job Box Tracker")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Text("\(viewModel.allJobBoxes.count) job boxes loaded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search schools, photographers or card #", text: $viewModel.searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: viewModel.searchText) { _ in
                        viewModel.applyFiltersAndSort()
                    }
                
                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                        viewModel.applyFiltersAndSort()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            // Main filter controls
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(JobBoxFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            viewModel.selectedFilter = filter
                            viewModel.applyFiltersAndSort()
                        }) {
                            Text(filter.rawValue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.selectedFilter == filter ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(viewModel.selectedFilter == filter ? .white : .primary)
                                .cornerRadius(20)
                        }
                    }
                    
                    // Advanced filters toggle button
                    Button(action: {
                        withAnimation {
                            showAdvancedFilters.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: showAdvancedFilters ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                                .font(.footnote)
                            Text("Advanced")
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(showAdvancedFilters ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(showAdvancedFilters ? .white : .primary)
                        .cornerRadius(20)
                    }
                    
                    Button(action: {
                        viewModel.showDatePicker.toggle()
                    }) {
                        HStack {
                            Image(systemName: "calendar")
                                .font(.footnote)
                            Text("Date Filter")
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(viewModel.showDatePicker ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(viewModel.showDatePicker ? .white : .primary)
                        .cornerRadius(20)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 5)
            
            // Advanced filters section - conditionally show
            if showAdvancedFilters {
                VStack {
                    // Status filter controls
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            Text("Status:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ForEach(JobBoxStatusFilter.allCases, id: \.self) { statusFilter in
                                Button(action: {
                                    viewModel.selectedStatusFilter = statusFilter
                                    viewModel.applyFiltersAndSort()
                                }) {
                                    Text(statusFilter.rawValue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(viewModel.selectedStatusFilter == statusFilter ? Color.green : Color.gray.opacity(0.2))
                                        .foregroundColor(viewModel.selectedStatusFilter == statusFilter ? .white : .primary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.05))
                .transition(.opacity)
            }
            
            // Date picker (if enabled)
            if viewModel.showDatePicker {
                DatePicker(
                    "Filter by date",
                    selection: $viewModel.selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(CompactDatePickerStyle())
                .labelsHidden()
                .padding()
                .onChange(of: viewModel.selectedDate) { _ in
                    viewModel.applyFiltersAndSort()
                }
            }
            
            // Sort controls
            HStack {
                Text("Sort by:")
                    .font(.subheadline)
                
                Picker("Sort by", selection: $viewModel.selectedSort) {
                    ForEach(JobBoxSort.allCases, id: \.self) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: viewModel.selectedSort) { _ in
                    viewModel.applyFiltersAndSort()
                }
                
                Spacer()
                
                // Settings button
                Button(action: {
                    showingSettingsSheet = true
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                
                // Refresh button
                Button(action: {
                    viewModel.loadJobBoxes()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            // Error message
            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding()
            }
            
            // Job box list
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading job boxes...")
                    Spacer()
                }
            } else if viewModel.allJobBoxes.isEmpty {
                VStack {
                    Spacer()
                    Text("No job boxes found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        viewModel.loadJobBoxes()
                    }) {
                        Text("Refresh")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.top)
                    
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.allJobBoxes) { jobBox in
                        jobBoxRow(jobBox)
                            .listRowBackground(rowBackground(for: jobBox))
                            .swipeActions {
                                Button {
                                    selectedJobBox = jobBox
                                    showingEditSheet = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                                
                                Button {
                                    selectedJobBox = jobBox
                                    showingFlagSheet = true
                                } label: {
                                    Label("Flag", systemImage: "flag")
                                }
                                .tint(.orange)
                            }
                            .contextMenu {
                                Button {
                                    selectedJobBox = jobBox
                                    showingEditSheet = true
                                } label: {
                                    Label("Edit Status", systemImage: "pencil")
                                }
                                
                                Button {
                                    selectedJobBox = jobBox
                                    showingFlagSheet = true
                                } label: {
                                    Label("Flag for Attention", systemImage: "flag")
                                }
                                
                                Divider()
                                
                                Text("Last Updated: \(jobBox.timeSinceUpdate)")
                            }
                    }
                }
                .refreshable {
                    viewModel.loadJobBoxes()
                }
            }
        }
        .navigationTitle("Job Box Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditSheet) {
            if let jobBox = selectedJobBox {
                editJobBoxView(jobBox)
            }
        }
        .sheet(isPresented: $showingFlagSheet) {
            if let jobBox = selectedJobBox {
                flagJobBoxView(jobBox)
            }
        }
        .sheet(isPresented: $showingSettingsSheet) {
            NavigationView {
                JobBoxSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingSettingsSheet = false
                                viewModel.loadJobBoxes()
                            }
                        }
                    }
            }
        }
        .onAppear {
            viewModel.setOrganizationID(storedUserOrganizationID)
        }
    }
    
    // Row for each job box
    private func jobBoxRow(_ jobBox: JobBoxWithEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row with school name and date
            HStack {
                Text(jobBox.schoolName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(viewModel.formatDate(jobBox.date))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Middle row with photographer and card/jobbox info
            HStack {
                Label(jobBox.photographerName, systemImage: "person.fill")
                    .font(.subheadline)
                
                Spacer()
                
                // Display card or box number
                if !jobBox.cardNumber.isEmpty {
                    Text("Card \(jobBox.cardNumber)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                } else if !jobBox.jobboxNumber.isEmpty {
                    Text("Box \(jobBox.jobboxNumber)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
            }
            
            // Bottom row with status
            HStack(spacing: 8) {
                statusPillsView(for: jobBox.jobBox.jobBoxStatus)
                
                Spacer()
                
                // Show time since update
                if jobBox.isStalled {
                    Label(jobBox.timeSinceUpdate, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Updated \(jobBox.timeSinceUpdate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // Background color for each row based on status (optimized version)
    private func rowBackground(for jobBox: JobBoxWithEvent) -> Color {
        if jobBox.isStalled {
            return Color.orange.opacity(0.1)
        }

        let status = jobBox.jobBox.jobBoxStatus
        if status == .packed { return Color.blue.opacity(0.05) }
        if status == .pickedUp { return Color.purple.opacity(0.05) }
        if status == .leftJob { return Color.orange.opacity(0.05) }
        return Color.green.opacity(0.05) // Must be .turnedIn
    }
    
    // Status pills visualization
    private func statusPillsView(for status: JobBoxStatus) -> some View {
        let stepsCompleted = statusToStep(status)
        
        return HStack(spacing: 4) {
            ForEach(1...4, id: \.self) { step in
                Capsule()
                    .fill(getStepColor(isActive: stepsCompleted >= step, isCompleted: stepsCompleted > step))
                    .frame(width: step == stepsCompleted ? 24 : 16, height: 8)
            }
            
            Text(status.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(getStatusColor(status))
                .padding(.leading, 4)
        }
    }
    
    private func editJobBoxView(_ jobBox: JobBoxWithEvent) -> some View {
        NavigationView {
            Form {
                Section(header: Text("Job Box Details")) {
                    Text("School: \(jobBox.schoolName)")
                    if !jobBox.cardNumber.isEmpty {
                        Text("Card Number: \(jobBox.cardNumber)")
                    }
                    Text("Job Box Number: \(jobBox.jobboxNumber)")
                    Text("Date: \(viewModel.formatDate(jobBox.date))")
                    Text("Photographer: \(jobBox.photographerName)")
                }
                
                Section(header: Text("Current Status")) {
                    Text("Status: \(jobBox.jobBox.jobBoxStatus.rawValue)")
                    Text("Last Updated: \(jobBox.timeSinceUpdate)")
                }
                
                Section(header: Text("Update Status")) {
                    ForEach(JobBoxStatus.allCases.filter { $0 != .unknown }, id: \.self) { status in
                        Button(action: {
                            viewModel.updateJobBoxStatus(jobBox: jobBox, newStatus: status)
                            showingEditSheet = false
                        }) {
                            HStack {
                                Text(status.rawValue)
                                
                                Spacer()
                                
                                if status == jobBox.jobBox.jobBoxStatus {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Job Box")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        showingEditSheet = false
                    }
                }
            }
        }
    }
    
    private func flagJobBoxView(_ jobBox: JobBoxWithEvent) -> some View {
        NavigationView {
            Form {
                Section(header: Text("Job Box Details")) {
                    Text("School: \(jobBox.schoolName)")
                    if !jobBox.cardNumber.isEmpty {
                        Text("Card Number: \(jobBox.cardNumber)")
                    }
                    Text("Job Box Number: \(jobBox.jobboxNumber)")
                    Text("Date: \(viewModel.formatDate(jobBox.date))")
                    Text("Photographer: \(jobBox.photographerName)")
                    Text("Status: \(jobBox.jobBox.jobBoxStatus.rawValue)")
                }
                
                Section(header: Text("Flag Note")) {
                    TextEditor(text: $flagNote)
                        .frame(height: 100)
                    
                    Button(action: {
                        viewModel.flagJobBox(jobBox: jobBox, note: flagNote)
                        showingFlagSheet = false
                        flagNote = ""
                    }) {
                        Text("Flag for Attention")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(flagNote.isEmpty)
                }
            }
            .navigationTitle("Flag Job Box")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingFlagSheet = false
                        flagNote = ""
                    }
                }
            }
        }
    }
    
    // Helper functions
    
    // Convert JobBoxStatus to step number (1-4) (optimized version)
    private func statusToStep(_ status: JobBoxStatus) -> Int {
        if status == .packed { return 1 }
        if status == .pickedUp { return 2 }
        if status == .leftJob { return 3 }
        return 4 // Must be .turnedIn
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
    
    // Get color for status text (optimized version)
    private func getStatusColor(_ status: JobBoxStatus) -> Color {
        if status == .packed { return .blue }
        if status == .pickedUp { return .purple }
        if status == .leftJob { return .orange }
        return .green // Must be .turnedIn
    }
}

// Helper extension to make JobBoxStatus conform to CaseIterable
extension JobBoxStatus: CaseIterable {
    static var allCases: [JobBoxStatus] {
        return [.packed, .pickedUp, .leftJob, .turnedIn]
    }
}
