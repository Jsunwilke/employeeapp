import SwiftUI

struct SearchView: View {
    // Initial values for navigation from other views
    var initialStatus: String? = nil
    var initialIsJobBoxMode: Bool = false
    
    @State private var searchField = "cardNumber"
    @State private var searchValue = ""
    @State private var searchResults: [FirestoreRecord] = []
    @State private var jobBoxSearchResults: [JobBox] = []
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isJobBoxMode = false
    
    // For schools and photographers
    @State private var schools: [SchoolItem] = []
    @State private var photographerNames: [String] = []
    
    @State private var statusSearchPerformed = false
    @State private var recordToDelete: FirestoreRecord? = nil
    @State private var jobBoxRecordToDelete: JobBox? = nil
    @State private var showDeleteConfirmation = false
    
    // Flag to prevent clearing search value during initialization
    @State private var isInitializingFromStatistics = false
    
    // For custom confirmation dialog
    @State private var showConfirmationDialog = false
    @State private var confirmationConfig = AlertConfiguration(
        title: "",
        message: "",
        primaryButtonTitle: "",
        secondaryButtonTitle: nil,
        isDestructive: false,
        primaryAction: {},
        secondaryAction: nil
    )
    
    // For network status indicator
    @ObservedObject private var offlineManager = OfflineDataManager.shared
    @ObservedObject private var userManager = UserManager.shared
    
    let localStatuses = ["Job Box", "Camera", "Envelope", "Uploaded", "Cleared", "Camera Bag", "Personal"]
    let jobBoxStatuses = ["Packed", "Picked Up", "Left Job", "Turned In"]
    
    let searchFields = [
        "cardNumber": "Card/Box #",
        "photographer": "Photographer",
        "school": "School",
        "status": "Status"
    ]
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                // Network status indicator
                if !offlineManager.isOnline {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.white)
                        Text("Offline Mode")
                            .foregroundColor(.white)
                            .font(.subheadline)
                        if offlineManager.syncPending {
                            Text("• Sync Pending")
                                .foregroundColor(.yellow)
                                .font(.subheadline)
                        }
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                // Toggle between SD Cards and Job Boxes
                Picker("Search Type", selection: $isJobBoxMode) {
                    Text("SD Cards").tag(false)
                    Text("Job Boxes").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: isJobBoxMode) { _ in
                    // Clear results when switching modes
                    searchResults = []
                    jobBoxSearchResults = []
                    if !searchValue.isEmpty {
                        performSearch()
                    }
                }
                
                Picker("Search Field", selection: $searchField) {
                    ForEach(searchFields.keys.sorted(), id: \.self) { key in
                        Text(searchFields[key]!)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .onChange(of: searchField) { _ in
                    // Only clear values if we're not initializing from statistics
                    if !isInitializingFromStatistics {
                        searchValue = ""
                        statusSearchPerformed = false
                        searchResults = []
                        jobBoxSearchResults = []
                    }
                }
                
                if searchField == "cardNumber" {
                    TextField(isJobBoxMode ? "Enter Box Number" : "Enter Card Number", text: $searchValue)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                } else if searchField == "photographer" {
                    DropdownSearchField(
                        placeholder: "Select Photographer",
                        selectedText: searchValue,
                        options: photographerNames,
                        onSelect: { selected in
                            searchValue = selected
                        }
                    )
                } else if searchField == "school" {
                    DropdownSearchField(
                        placeholder: "Select School",
                        selectedText: searchValue,
                        options: schools
                            .map { $0.name }
                            .sorted(),
                        onSelect: { selected in
                            searchValue = selected
                        }
                    )
                } else if searchField == "status" {
                    DropdownSearchField(
                        placeholder: "Select Status",
                        selectedText: searchValue,
                        options: isJobBoxMode ? jobBoxStatuses : localStatuses,
                        onSelect: { selected in
                            searchValue = selected
                        }
                    )
                }
                
                Button(action: performSearch) {
                    if isLoading {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Searching...")
                                .foregroundColor(.white)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .cornerRadius(10)
                    } else {
                        Text("Search")
                            .font(.title2)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 5)
                
                if searchField == "status" && statusSearchPerformed {
                    if isJobBoxMode {
                        Text("\(jobBoxSearchResults.count) \(jobBoxSearchResults.count == 1 ? "job box" : "job boxes") in \(searchValue) status")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        Text("\(searchResults.count) \(searchResults.count == 1 ? "card" : "cards") in \(searchValue) status")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                }
                
                // List of results
                List {
                    if isJobBoxMode {
                        ForEach(jobBoxSearchResults) { record in
                            JobBoxBubbleView(record: record)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        jobBoxRecordToDelete = record
                                        confirmDeleteJobBoxRecord(record)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } else {
                        ForEach(searchResults) { record in
                            RecordBubbleView(record: record)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        recordToDelete = record
                                        confirmDeleteRecord(record)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .refreshable {
                    if searchValue.isEmpty {
                        fetchInitialData()
                    } else {
                        performSearch()
                    }
                }
                .listStyle(PlainListStyle())
            }
            
            // Custom confirmation dialog
            ConfirmationDialogView(isPresented: $showConfirmationDialog, config: confirmationConfig)
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Info"),
                  message: Text(alertMessage),
                  dismissButton: .default(Text("OK")))
        }
        .onAppear {
            fetchInitialData()
            
            // Apply initial values if coming from statistics
            if let status = initialStatus {
                isInitializingFromStatistics = true
                isJobBoxMode = initialIsJobBoxMode
                searchField = "status"
                searchValue = status
                
                // Perform search after a slight delay to ensure UI is updated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInitializingFromStatistics = false
                    performSearch()
                }
            }
        }
    }
    
    func fetchInitialData() {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else { return }
        
        // Load cached photographer names
        if let data = UserDefaults.standard.data(forKey: "photographerNames"),
           let cachedNames = try? JSONDecoder().decode([String].self, from: data) {
            self.photographerNames = cachedNames
        }
        FirestoreManager.shared.listenForPhotographers(inOrgID: orgID) { names in
            self.photographerNames = names
        }
        
        // Load cached dropdown data for schools
        if let data = UserDefaults.standard.data(forKey: "nfcSchools"),
           let cachedSchools = try? JSONDecoder().decode([SchoolItem].self, from: data) {
            self.schools = cachedSchools
        }
        FirestoreManager.shared.listenForSchoolsData(forOrgID: orgID) { schoolItems in
            self.schools = schoolItems
        }
        
        // Fetch the most recent 50 records
        if isJobBoxMode {
            fetchInitialJobBoxRecords(orgID: orgID)
        } else {
            fetchInitialSDCardRecords(orgID: orgID)
        }
    }
    
    func fetchInitialSDCardRecords(orgID: String) {
        FirestoreManager.shared.fetchRecords(field: "all", value: "", organizationID: orgID) { result in
            switch result {
            case .success(let records):
                let sortedRecords = records.sorted { $0.timestamp > $1.timestamp }
                self.searchResults = Array(sortedRecords.prefix(50))
            case .failure(let error):
                alertMessage = "Error fetching records: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    func fetchInitialJobBoxRecords(orgID: String) {
        FirestoreManager.shared.fetchJobBoxRecords(field: "all", value: "", organizationID: orgID) { result in
            switch result {
            case .success(let records):
                let sortedRecords = records.sorted { $0.timestamp > $1.timestamp }
                self.jobBoxSearchResults = Array(sortedRecords.prefix(50))
            case .failure(let error):
                alertMessage = "Error fetching job box records: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    func performSearch() {
        UIApplication.shared.endEditing()
        
        let orgID = userManager.currentUserOrganizationID
        guard !searchValue.isEmpty && !orgID.isEmpty else {
            alertMessage = "Please enter/select a value to search."
            showAlert = true
            return
        }
        
        isLoading = true
        
        if isJobBoxMode {
            performJobBoxSearch(orgID: orgID)
        } else {
            performSDCardSearch(orgID: orgID)
        }
    }
    
    func performSDCardSearch(orgID: String) {
        if searchField.lowercased() == "status" {
            statusSearchPerformed = true
            FirestoreManager.shared.fetchRecords(field: "all", value: "", organizationID: orgID) { result in
                isLoading = false
                switch result {
                case .success(let records):
                    let latestRecordsDict = Dictionary(grouping: records, by: { $0.cardNumber })
                        .compactMapValues { recs in
                            recs.sorted { $0.timestamp > $1.timestamp }.first
                        }
                    let filteredRecords = latestRecordsDict.values.filter {
                        $0.status.lowercased() == searchValue.lowercased()
                    }
                    let sortedRecords = filteredRecords.sorted { $0.timestamp > $1.timestamp }
                    searchResults = sortedRecords
                    if sortedRecords.isEmpty {
                        alertMessage = "No records found."
                        showAlert = true
                    }
                case .failure(let error):
                    alertMessage = "Error fetching records: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        } else {
            FirestoreManager.shared.fetchRecords(field: searchField, value: searchValue, organizationID: orgID) { result in
                isLoading = false
                switch result {
                case .success(let records):
                    let sortedRecords = records.sorted { $0.timestamp > $1.timestamp }
                    searchResults = sortedRecords
                    if sortedRecords.isEmpty {
                        alertMessage = "No records found."
                        showAlert = true
                    }
                case .failure(let error):
                    alertMessage = "Error fetching records: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    func performJobBoxSearch(orgID: String) {
        let fieldToSearch = searchField == "cardNumber" ? "boxNumber" : searchField
        
        if fieldToSearch.lowercased() == "status" {
            statusSearchPerformed = true
            FirestoreManager.shared.fetchJobBoxRecords(field: "all", value: "", organizationID: orgID) { result in
                isLoading = false
                switch result {
                case .success(let records):
                    let latestRecordsDict = Dictionary(grouping: records, by: { $0.boxNumber })
                        .compactMapValues { recs in
                            recs.sorted { $0.timestamp > $1.timestamp }.first
                        }
                    let filteredRecords = latestRecordsDict.values.filter { record in
                        record.status.rawValue.lowercased() == searchValue.lowercased()
                    }
                    let sortedRecords = filteredRecords.sorted { $0.timestamp > $1.timestamp }
                    jobBoxSearchResults = sortedRecords
                    if sortedRecords.isEmpty {
                        alertMessage = "No job box records found."
                        showAlert = true
                    }
                case .failure(let error):
                    alertMessage = "Error fetching job box records: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        } else {
            FirestoreManager.shared.fetchJobBoxRecords(field: fieldToSearch, value: searchValue, organizationID: orgID) { result in
                isLoading = false
                switch result {
                case .success(let records):
                    let sortedRecords = records.sorted { $0.timestamp > $1.timestamp }
                    jobBoxSearchResults = sortedRecords
                    if sortedRecords.isEmpty {
                        alertMessage = "No job box records found."
                        showAlert = true
                    }
                case .failure(let error):
                    alertMessage = "Error fetching job box records: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    // Function to show confirmation dialog for SD card record
    func confirmDeleteRecord(_ record: FirestoreRecord) {
        confirmationConfig = AlertConfiguration(
            title: "Confirm Deletion",
            message: "Are you sure you want to delete the record for card #\(record.cardNumber)? This action cannot be undone.",
            primaryButtonTitle: "Delete",
            secondaryButtonTitle: "Cancel",
            isDestructive: true,
            primaryAction: {
                if let recordID = record.id {
                    deleteRecord(recordID: recordID)
                }
            },
            secondaryAction: {
                // Cancel action
            }
        )
        
        showConfirmationDialog = true
    }
    
    // Function to show confirmation dialog for job box record
    func confirmDeleteJobBoxRecord(_ record: JobBox) {
        confirmationConfig = AlertConfiguration(
            title: "Confirm Deletion",
            message: "Are you sure you want to delete the record for job box #\(record.boxNumber)? This action cannot be undone.",
            primaryButtonTitle: "Delete",
            secondaryButtonTitle: "Cancel",
            isDestructive: true,
            primaryAction: {
                deleteJobBoxRecord(recordID: record.id)
            },
            secondaryAction: {
                // Cancel action
            }
        )
        
        showConfirmationDialog = true
    }
    
    func deleteRecord(recordID: String) {
        FirestoreManager.shared.deleteRecord(recordID: recordID) { result in
            switch result {
            case .success(let message):
                alertMessage = message
                if let index = searchResults.firstIndex(where: { $0.id == recordID }) {
                    searchResults.remove(at: index)
                }
            case .failure(let error):
                alertMessage = "Failed to delete record: \(error.localizedDescription)"
            }
            showAlert = true
        }
    }
    
    func deleteJobBoxRecord(recordID: String) {
        FirestoreManager.shared.deleteJobBoxRecord(recordID: recordID) { result in
            switch result {
            case .success(let message):
                alertMessage = message
                if let index = jobBoxSearchResults.firstIndex(where: { $0.id == recordID }) {
                    jobBoxSearchResults.remove(at: index)
                }
            case .failure(let error):
                alertMessage = "Failed to delete job box record: \(error.localizedDescription)"
            }
            showAlert = true
        }
    }
}

// Helper extension
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}