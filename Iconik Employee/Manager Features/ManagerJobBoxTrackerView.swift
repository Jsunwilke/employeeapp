import SwiftUI
import Firebase
import FirebaseFirestore

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
        let threshold = JobBoxSettingsManager.shared.getStalledThreshold(for: jobBox.status)
        let thresholdDate = Date().addingTimeInterval(-threshold)
        return jobBox.timestamp < thresholdDate && jobBox.status != .turnedIn
    }
    
    // Time since last status change
    var timeSinceUpdate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: jobBox.timestamp, relativeTo: Date())
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

class ManagerJobBoxViewModel: ObservableObject {
    @Published var allJobBoxes: [JobBoxWithEvent] = []
    @Published var selectedFilter: JobBoxFilter = .active
    @Published var selectedSort: JobBoxSort = .newestFirst
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    
    @Published var selectedDate: Date = Date()
    @Published var showDatePicker: Bool = false
    
    // Flag to indicate if we're searching by card number
    private var isSearchingByCardNumber: Bool = false
    
    private var db = Firestore.firestore()
    
    init() {
        loadJobBoxes()
    }
    
    // Load all job boxes
    func loadJobBoxes() {
        isLoading = true
        errorMessage = ""
        
        // Check if we're searching by card number (numeric search)
        isSearchingByCardNumber = !searchText.isEmpty && searchText.rangeOfCharacter(from: .decimalDigits) != nil &&
            searchText.rangeOfCharacter(from: .letters) == nil
        
        // Query all job boxes
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        var query: Query = db.collection("jobBoxes")
            .whereField("timestamp", isGreaterThan: Timestamp(date: thirtyDaysAgo))
        
        // Get today's date bounds for the "today" filter
        if selectedFilter == .today && !isSearchingByCardNumber {
            let startOfDay = calendar.startOfDay(for: Date())
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            query = query.whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
                .whereField("timestamp", isLessThan: Timestamp(date: endOfDay))
        }
        
        query.getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Error loading job boxes: \(error.localizedDescription)"
                }
                return
            }
            
            guard let documents = snapshot?.documents else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.allJobBoxes = []
                }
                return
            }
            
            self.processJobBoxDocuments(documents)
        }
    }
    
    private func processJobBoxDocuments(_ documents: [QueryDocumentSnapshot]) {
        // This will hold all job boxes
        var allBoxes: [JobBoxWithEvent] = []
        
        // Process each document
        for document in documents {
            let data = document.data()
            let jobBox = JobBox(id: document.documentID, data: data)
            
            var schoolName = "Unknown School"
            var jobboxNumber = ""
            var cardNumber = ""
            var date = jobBox.timestamp
            var photographerName = jobBox.scannedBy
            var position = "Unknown"
            
            // Extract fields from the document
            
            // Get school name
            if let school = data["school"] as? String, !school.isEmpty {
                schoolName = school
            }
            
            // Get jobbox number
            if let boxNum = data["jobboxNumber"] as? String, !boxNum.isEmpty {
                jobboxNumber = boxNum
            } else if let boxNum = data["boxNumber"] as? String, !boxNum.isEmpty {
                jobboxNumber = boxNum
            } else if let boxNum = data["jobbox"] as? String, !boxNum.isEmpty {
                jobboxNumber = boxNum
            }
            
            // Get card number
            if let card = data["cardNumber"] as? String, !card.isEmpty {
                cardNumber = card
            } else if let card = data["cardId"] as? String, !card.isEmpty {
                cardNumber = card
            }
            
            // Get event date if available
            if let eventDate = data["eventDate"] as? Timestamp {
                date = eventDate.dateValue()
            }
            
            // Create JobBoxWithEvent object
            let jobBoxWithEvent = JobBoxWithEvent(
                id: jobBox.id,
                jobBox: jobBox,
                schoolName: schoolName,
                date: date,
                photographerName: photographerName,
                position: position,
                jobboxNumber: jobboxNumber,
                cardNumber: cardNumber
            )
            
            // Add to the array
            allBoxes.append(jobBoxWithEvent)
        }
        
        DispatchQueue.main.async {
            // First apply search filter to all boxes
            var filteredBoxes = self.filterJobBoxesBySearch(allBoxes)
            
            // If we're searching for a specific card number, show all results for that card
            if self.isSearchingByCardNumber {
                self.allJobBoxes = self.sortJobBoxes(filteredBoxes)
                self.isLoading = false
                return
            }
            
            // Otherwise, group by card number and show only the latest status
            let groupedBoxes = Dictionary(grouping: filteredBoxes) { box -> String in
                // Group by card number, or use jobbox number as fallback
                return !box.cardNumber.isEmpty ? box.cardNumber : box.jobboxNumber
            }
            
            // For each group, get only the latest status
            var latestStatusBoxes: [JobBoxWithEvent] = []
            
            for (_, boxes) in groupedBoxes {
                // Sort by timestamp (newest first) and take only the first one
                if let latestBox = boxes.sorted(by: { $0.jobBox.timestamp > $1.jobBox.timestamp }).first {
                    latestStatusBoxes.append(latestBox)
                }
            }
            
            // Process the 'stalled' filter separately
            if self.selectedFilter == .stalled {
                latestStatusBoxes = latestStatusBoxes.filter { $0.isStalled }
            }
            
            // Apply active/completed filter after getting the latest status
            if self.selectedFilter == .active {
                // For Active tab, filter out cards where most recent status is "turned in"
                latestStatusBoxes = latestStatusBoxes.filter { $0.jobBox.status != .turnedIn }
            } else if self.selectedFilter == .completed {
                // For Completed tab, only show cards where most recent status is "turned in"
                latestStatusBoxes = latestStatusBoxes.filter { $0.jobBox.status == .turnedIn }
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
            return jobBoxes.sorted { $0.jobBox.timestamp > $1.jobBox.timestamp }
            
        case .oldestFirst:
            return jobBoxes.sorted { $0.jobBox.timestamp < $1.jobBox.timestamp }
            
        case .schoolName:
            return jobBoxes.sorted { $0.schoolName < $1.schoolName }
            
        case .photographer:
            return jobBoxes.sorted { $0.photographerName < $1.photographerName }
            
        case .jobboxNumber:
            return jobBoxes.sorted { $0.jobboxNumber < $1.jobboxNumber }
            
        case .status:
            return jobBoxes.sorted { statusPriority($0.jobBox.status) < statusPriority($1.jobBox.status) }
        }
    }
    
    // Helper function to determine status priority for sorting
    private func statusPriority(_ status: JobBoxStatus) -> Int {
        switch status {
        case .packed: return 0
        case .pickedUp: return 1
        case .leftJob: return 2
        case .turnedIn: return 3
        case .unknown: return 4
        }
    }
    
    // Apply filters and sorting
    func applyFiltersAndSort() {
        loadJobBoxes()
    }
    
    // Manually update a job box status
    func updateJobBoxStatus(jobBox: JobBoxWithEvent, newStatus: JobBoxStatus) {
        db.collection("jobBoxes").document(jobBox.id).updateData([
            "status": newStatus.rawValue,
            "timestamp": Timestamp(date: Date())
        ]) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Error updating job box: \(error.localizedDescription)"
                }
            } else {
                // Reload data on success
                self?.loadJobBoxes()
            }
        }
    }
    
    // Flag a job box for attention
    func flagJobBox(jobBox: JobBoxWithEvent, note: String) {
        db.collection("jobBoxes").document(jobBox.id).updateData([
            "flagged": true,
            "flagNote": note,
            "flaggedAt": Timestamp(date: Date())
        ]) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Error flagging job box: \(error.localizedDescription)"
                }
            } else {
                // Reload data on success
                self?.loadJobBoxes()
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
    
    // State for the job box being edited
    @State private var selectedJobBox: JobBoxWithEvent? = nil
    @State private var showingEditSheet = false
    @State private var showingFlagSheet = false
    @State private var showingSettingsSheet = false
    @State private var flagNote = ""
    
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
            
            // Filter controls
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
            .padding(.bottom, 10)
            
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
            viewModel.loadJobBoxes()
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
                statusPillsView(for: jobBox.jobBox.status)
                
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
    
    // Background color for each row based on status
    private func rowBackground(for jobBox: JobBoxWithEvent) -> Color {
        if jobBox.isStalled {
            return Color.orange.opacity(0.1)
        }
        
        switch jobBox.jobBox.status {
        case .packed:
            return Color.blue.opacity(0.05)
        case .pickedUp:
            return Color.purple.opacity(0.05)
        case .leftJob:
            return Color.orange.opacity(0.05)
        case .turnedIn:
            return Color.green.opacity(0.05)
        case .unknown:
            return Color.gray.opacity(0.05)
        }
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
                    Text("Status: \(jobBox.jobBox.status.rawValue)")
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
                                
                                if status == jobBox.jobBox.status {
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
                    Text("Status: \(jobBox.jobBox.status.rawValue)")
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
    
    // Get color for status text
    private func getStatusColor(_ status: JobBoxStatus) -> Color {
        switch status {
        case .packed:
            return .blue
        case .pickedUp:
            return .purple
        case .leftJob:
            return .orange
        case .turnedIn:
            return .green
        case .unknown:
            return .gray
        }
    }
}

// Helper extension to make JobBoxStatus conform to CaseIterable
extension JobBoxStatus: CaseIterable {
    static var allCases: [JobBoxStatus] {
        return [.packed, .pickedUp, .leftJob, .turnedIn, .unknown]
    }
}
