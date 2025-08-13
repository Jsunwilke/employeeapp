import SwiftUI
import CoreNFC
import FirebaseFirestore
import FirebaseAuth

struct ScanView: View {
    @StateObject var nfcReader = NFCReaderCoordinator()
    @State private var showingForm = false
    @State private var showingJobBoxForm = false
    @State private var school = ""
    @State private var schoolId: String? = nil
    @State private var status = "Job Box"
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var lastRecord: FirestoreRecord? = nil
    @State private var lastJobBoxRecord: JobBox? = nil
    
    // State for loading overlay
    @State private var isLoading = false
    @State private var loadingMessage = ""
    
    // State for toast notification
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var isSuccessToast = true
    
    // Offline status
    @ObservedObject private var offlineManager = OfflineDataManager.shared
    
    // State for job box left on job alerts
    @State private var leftJobBoxes: [(JobBox, TimeInterval)] = []
    @State private var jobBoxesLoaded = false
    
    // Firestore listener
    @State private var jobBoxListener: ListenerRegistration?
    
    // Debug mode for easier testing - set to false for production
    @State private var debugMode = false
    
    let localStatuses = ["Job Box", "Camera", "Envelope", "Uploaded", "Cleared", "Camera Bag", "Personal"]
    let jobBoxStatuses = ["Packed", "Picked Up", "Left Job", "Turned In"]
    
    // Access to shared services
    @ObservedObject private var userManager = UserManager.shared
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Offline indicator
                if !offlineManager.isOnline {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.white)
                        
                        Text("Offline Mode")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        
                        if offlineManager.syncPending {
                            Text("• Sync Pending")
                                .font(.subheadline.bold())
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.8))
                    )
                    .padding(.top, 8)
                }
                
                Spacer()
                
                // Main scan button
                VStack(spacing: 24) {
                    if let cardNumber = nfcReader.scannedCardNumber {
                        Text("Tag #\(cardNumber)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    
                    Button(action: {
                        nfcReader.beginScanning()
                    }) {
                        VStack(spacing: 16) {
                            Image(systemName: "wave.3.right.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.white)
                            
                            Text("Scan Tag")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                        }
                        .frame(width: 200, height: 200)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.orange,
                                            Color.orange.opacity(0.8)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    }
                    .accessibilityLabel("Scan Tag")
                    .accessibilityHint("Tap to scan an NFC tag")
                    
                    if let error = nfcReader.errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(UIColor.systemGray6))
                            )
                            .padding(.horizontal, 20)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Job Box Notification
                    if !leftJobBoxes.isEmpty {
                        JobBoxNotification(jobBoxes: leftJobBoxes)
                            .padding(.top, 20)
                    }
                }
                
                Spacer()
            }
        }
        // When the scanned tag number changes, determine if it's a job box or SD card
        .onReceive(nfcReader.$scannedCardNumber) { newValue in
            guard let number = newValue else { return }
            isLoading = true
            
            // Check if the number is in the job box range (3001+)
            if let intNumber = Int(number), intNumber >= 3001 {
                loadingMessage = "Fetching job box history..."
                fetchLastJobBoxRecord(for: number)
            } else {
                loadingMessage = "Fetching card history..."
                fetchLastRecord(for: number)
            }
        }
        // Load cached school data and check for job boxes onAppear
        .onAppear {
            print("DEBUG: ScanView appeared")
            if let data = UserDefaults.standard.data(forKey: "dropdownRecords"),
               let cachedDropdowns = try? JSONDecoder().decode([DropdownRecord].self, from: data) {
                if !cachedDropdowns.isEmpty, school.isEmpty {
                    // Default to the first school alphabetically if not already set
                    self.school = cachedDropdowns.sorted { $0.value < $1.value }.first?.value ?? ""
                }
            }
            
            // Initial check for job boxes in "Left Job" status
            checkForLeftJobBoxes()
            
            // Set up real-time listener for job box changes
            setupJobBoxListener()
        }
        .onDisappear {
            // Remove the Firestore listener when view disappears
            jobBoxListener?.remove()
            jobBoxListener = nil
            nfcReader.errorMessage = nil
        }
        .sheet(isPresented: $showingForm, onDismiss: {
            // Reset state when form is dismissed
            nfcReader.scannedCardNumber = nil
            school = ""
            schoolId = nil
            status = "Job Box"
        }) {
            if let cardNumber = nfcReader.scannedCardNumber {
                FormView(
                    cardNumber: cardNumber,
                    selectedSchool: $school,
                    selectedStatus: $status,
                    localStatuses: localStatuses,
                    lastRecord: lastRecord,
                    onSubmit: { cardNum, chosenPhotographer, jasonVal, andyVal, completion in
                        isLoading = true
                        loadingMessage = "Saving card data..."
                        
                        // Validate required fields
                        guard validateFields(
                            cardNumber: cardNum,
                            photographer: chosenPhotographer,
                            school: school,
                            status: status
                        ) else {
                            isLoading = false
                            completion(false)
                            return
                        }
                        
                        submitSDCardData(
                            cardNumber: cardNum,
                            photographer: chosenPhotographer,
                            jasonValue: jasonVal,
                            andyValue: andyVal,
                            completion: completion
                        )
                    },
                    onCancel: {
                        nfcReader.scannedCardNumber = nil
                        showingForm = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingJobBoxForm, onDismiss: {
            // Reset state when form is dismissed
            nfcReader.scannedCardNumber = nil
            school = ""
            schoolId = nil
            status = "Job Box"
        }) {
            Group {
                if let boxNumber = nfcReader.scannedCardNumber {
                    JobBoxFormView(
                        boxNumber: boxNumber,
                        selectedSchool: $school,
                        selectedStatus: $status,
                        lastRecord: lastJobBoxRecord,
                        onSubmit: { chosenPhotographer, schoolId, shiftUid, completion in
                            isLoading = true
                            loadingMessage = "Saving job box data..."
                            
                            // Validate required fields
                            guard validateFields(
                                cardNumber: boxNumber,
                                photographer: chosenPhotographer,
                                school: school,
                                status: status
                            ) else {
                                isLoading = false
                                completion(false)
                                return
                            }
                            
                            submitJobBoxData(
                                boxNumber: boxNumber,
                                photographer: chosenPhotographer,
                                schoolId: schoolId,
                                shiftUid: shiftUid,
                                completion: completion
                            )
                        },
                        onCancel: {
                            nfcReader.scannedCardNumber = nil
                            showingJobBoxForm = false
                        }
                    )
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Info"),
                  message: Text(alertMessage),
                  dismissButton: .default(Text("OK")))
        }
        .loadingOverlay(isPresented: $isLoading, message: loadingMessage)
        .toast(isPresented: $showToast, message: toastMessage, isSuccess: isSuccessToast)
        .onChange(of: nfcReader.errorMessage) { newValue in
            // Clear any error message after 10 seconds
            if newValue != nil {
                // Show as toast
                toastMessage = newValue!
                isSuccessToast = false
                showToast = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    if nfcReader.errorMessage == newValue {
                        nfcReader.errorMessage = nil
                    }
                }
            }
        }
        .navigationBarTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // Set up an efficient real-time listener for job box changes
    func setupJobBoxListener() {
        guard jobBoxListener == nil else { return }
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            return
        }
        
        print("DEBUG: Setting up real-time job box listener for org \(orgID)")
        
        // Get Firestore reference
        let db = Firestore.firestore()
        
        // Listen for ALL job box updates in this organization
        // This is more efficient than querying everything repeatedly
        jobBoxListener = db.collection("jobBoxes")
            .whereField("organizationID", isEqualTo: orgID)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("DEBUG: Error in job box listener: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else {
                    print("DEBUG: Empty snapshot in job box listener")
                    return
                }
                
                print("DEBUG: Job box listener triggered - detected changes")
                
                // Instead of refreshing completely, we'll process the changes
                // to determine if we need to update our left job box notifications
                self.processJobBoxChanges(snapshot: snapshot)
            }
    }
    
    // Process snapshots to efficiently update left job box notifications
    func processJobBoxChanges(snapshot: QuerySnapshot) {
        let currentUserName = storedUserFirstName
        guard !currentUserName.isEmpty else {
            return
        }
        
        // Look for document changes that might affect our left job box list
        var needFullRefresh = false
        var boxNumbers = Set<String>()
        
        // Extract box numbers from changed documents
        for change in snapshot.documentChanges {
            // Access the data directly without trying to decode it
            let data = change.document.data()
            
            // Extract the box number directly from the document data
            if let boxNumber = data["boxNumber"] as? String {
                boxNumbers.insert(boxNumber)
                
                // If this is for the current user, we'll check more carefully
                if let photographer = data["photographer"] as? String,
                   photographer.lowercased() == currentUserName.lowercased() {
                    
                    if change.type == .added || change.type == .modified {
                        // If a box entered or left "Left Job" status, we need a refresh
                        if let status = data["status"] as? String,
                           status.lowercased() == "left job" || change.type == .modified {
                            needFullRefresh = true
                        }
                    } else if change.type == .removed {
                        // If a document was deleted, we need a full refresh
                        needFullRefresh = true
                    }
                }
            }
        }
        
        // If box numbers from our notification list were affected by changes,
        // or if we determined we need a full refresh, do it now
        let affectedNotificationBox = leftJobBoxes.contains { record, _ in
            return boxNumbers.contains(record.boxNumber)
        }
        
        if needFullRefresh || affectedNotificationBox {
            print("DEBUG: Changes affect our notifications - refreshing left job boxes")
            checkForLeftJobBoxes()
        }
    }
    
    // Function to check for job boxes in "Left Job" status
    func checkForLeftJobBoxes() {
        // Make sure we have the necessary user info
        let orgID = userManager.currentUserOrganizationID
        let currentUserName = storedUserFirstName
        guard !orgID.isEmpty && !currentUserName.isEmpty else {
            print("DEBUG: Missing user info - can't check for job boxes")
            return
        }
        
        print("DEBUG: Checking for left job boxes for \(currentUserName) in org \(orgID)")
        
        // Reset the "loaded" flag to ensure we always recheck
        jobBoxesLoaded = false
        let currentTime = Date()
        
        // First, we need to find all box numbers
        FirestoreManager.shared.fetchJobBoxRecords(field: "all", value: "", organizationID: orgID) { result in
            switch result {
            case .success(let allRecords):
                print("DEBUG: Found \(allRecords.count) total job box records")
                
                // Group by box number to find the most recent status for each box
                let boxGroups = Dictionary(grouping: allRecords, by: { $0.boxNumber })
                
                // Find boxes that are still in "Left Job" status
                var leftJobBoxRecords: [JobBox] = []
                
                for (boxNumber, records) in boxGroups {
                    // Get the most recent record for this box number
                    if let mostRecent = records.sorted(by: { $0.timestamp > $1.timestamp }).first {
                        if mostRecent.status == .leftJob {
                            // Check if this box belongs to the current user
                            if mostRecent.scannedBy.lowercased() == currentUserName.lowercased() {
                                leftJobBoxRecords.append(mostRecent)
                                print("DEBUG: Box #\(boxNumber) is currently in 'Left Job' status (most recent)")
                            }
                        } else {
                            print("DEBUG: Box #\(boxNumber) is NOT in 'Left Job' status, current status: \(mostRecent.status.rawValue)")
                        }
                    }
                }
                
                // If no boxes are currently in "Left Job" status, clear the notifications
                if leftJobBoxRecords.isEmpty {
                    print("DEBUG: No boxes are currently in 'Left Job' status")
                    DispatchQueue.main.async {
                        self.leftJobBoxes = []
                        self.jobBoxesLoaded = true
                    }
                    return
                }
                
                // Process the boxes that are still in "Left Job" status
                let processedRecords = leftJobBoxRecords.map { record -> (JobBox, TimeInterval) in
                    let timeDifference = currentTime.timeIntervalSince(record.timestamp)
                    let hoursInLeftJob = timeDifference / 3600.0
                    
                    print("DEBUG: Box #\(record.boxNumber) by \(record.scannedBy) has been in 'Left Job' for \(hoursInLeftJob) hours")
                    
                    return (record, timeDifference)
                }
                
                // Filter to show boxes that have been in "Left Job" for >12 hours
                // Use a threshold of just 5 minutes (300 seconds) in debug mode
                let threshold = self.debugMode ? 300.0 : 43200.0 // 5 minutes or 12 hours
                let filteredBoxes = processedRecords.filter { _, timeDiff in
                    let oldEnough = timeDiff > threshold
                    return oldEnough
                }
                
                print("DEBUG: After filtering, found \(filteredBoxes.count) boxes for \(currentUserName) older than threshold")
                
                DispatchQueue.main.async {
                    self.leftJobBoxes = filteredBoxes.sorted(by: { $0.1 > $1.1 })
                    self.jobBoxesLoaded = true
                    print("DEBUG: Updated leftJobBoxes array with \(self.leftJobBoxes.count) items")
                }
                
            case .failure(let error):
                print("DEBUG: Failed to fetch job boxes: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.jobBoxesLoaded = true
                }
            }
        }
    }
    
    // Validate that required fields are not empty
    func validateFields(cardNumber: String, photographer: String, school: String, status: String) -> Bool {
        var isValid = true
        var errorMessages: [String] = []
        
        if cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessages.append("Card/Box number cannot be empty")
            isValid = false
        }
        
        if photographer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessages.append("Photographer cannot be empty")
            isValid = false
        }
        
        if school.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessages.append("School cannot be empty")
            isValid = false
        }
        
        if status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessages.append("Status cannot be empty")
            isValid = false
        }
        
        if !isValid {
            alertMessage = errorMessages.joined(separator: "\n")
            showAlert = true
        }
        
        return isValid
    }
    
    func submitSDCardData(
        cardNumber: String,
        photographer: String,
        jasonValue: String,
        andyValue: String,
        completion: @escaping (Bool) -> Void
    ) {
        let timestamp = Date()
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            isLoading = false
            toastMessage = "User organization not found."
            isSuccessToast = false
            showToast = true
            completion(false)
            return
        }
        
        FirestoreManager.shared.saveRecord(
            timestamp: timestamp,
            photographer: photographer,
            cardNumber: cardNumber,
            school: school,
            status: status,
            uploadedFromJasonsHouse: jasonValue,
            uploadedFromAndysHouse: andyValue,
            organizationID: orgID,
            userId: UserManager.shared.getCurrentUserID() ?? ""
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let message):
                    self.toastMessage = message
                    self.isSuccessToast = true
                    self.showToast = true
                    
                    // Close form and reset state
                    self.showingForm = false
                    self.nfcReader.scannedCardNumber = nil
                    
                    // Then notify completion
                    completion(true)
                    
                case .failure(let error):
                    self.toastMessage = "Failed to save record: \(error.localizedDescription)"
                    self.isSuccessToast = false
                    self.showToast = true
                    completion(false)
                }
            }
        }
    }
    
    func submitJobBoxData(
        boxNumber: String,
        photographer: String,
        schoolId: String? = nil,
        shiftUid: String? = nil, // Updated to include shiftUid
        completion: @escaping (Bool) -> Void
    ) {
        let timestamp = Date()
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            isLoading = false
            toastMessage = "User organization not found."
            isSuccessToast = false
            showToast = true
            completion(false)
            return
        }
        
        // Check if the job box was previously in "Left Job" status
        let wasInLeftJobStatus = lastJobBoxRecord?.status == .leftJob
        let wasNotificationBox = leftJobBoxes.contains { record, _ in
            return record.boxNumber == boxNumber
        }
        
        // Get the shiftUid from lastJobBoxRecord if not provided and it's not a "Packed" status
        // This ensures we maintain the shiftUid even when transitioning from one status to another
        let effectiveShiftUid = shiftUid ?? (status.lowercased() != "packed" ? lastJobBoxRecord?.shiftUid : nil)
        
        FirestoreManager.shared.saveJobBoxRecord(
            timestamp: timestamp,
            photographer: photographer,
            boxNumber: boxNumber,
            school: school,
            schoolId: schoolId,
            status: status,
            organizationID: orgID,
            userId: UserManager.shared.getCurrentUserID() ?? "",
            shiftUid: effectiveShiftUid // Pass the effective shiftUid (either from parameter or last record)
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let message):
                    self.toastMessage = message
                    self.isSuccessToast = true
                    self.showToast = true
                    
                    // For immediate UI update if a notification box is being updated
                    if wasInLeftJobStatus || wasNotificationBox {
                        // Filter out this specific box from the notifications
                        self.leftJobBoxes = self.leftJobBoxes.filter { record, _ in
                            return record.boxNumber != boxNumber
                        }
                    }
                    
                    // Close form and reset state
                    self.showingJobBoxForm = false
                    self.nfcReader.scannedCardNumber = nil
                    
                    // No need to manually refresh since the Firestore listener
                    // will automatically pick up changes for cross-device updates
                    
                    // Then notify completion
                    completion(true)
                    
                case .failure(let error):
                    self.toastMessage = "Failed to save job box record: \(error.localizedDescription)"
                    self.isSuccessToast = false
                    self.showToast = true
                    completion(false)
                }
            }
        }
    }
    
    func fetchLastRecord(for cardNumber: String) {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            isLoading = false
            return
        }
        
        FirestoreManager.shared.fetchRecords(field: "cardNumber", value: cardNumber, organizationID: orgID) { result in
            isLoading = false
            
            switch result {
            case .success(let records):
                let sortedRecords = records.sorted { $0.timestamp > $1.timestamp }
                self.lastRecord = sortedRecords.first
                
                if let last = self.lastRecord {
                    // If last record was "cleared", default school to "Iconik"
                    if last.status.lowercased() == "cleared" {
                        self.school = "Iconik"
                    } else {
                        self.school = last.school
                    }
                    
                    // Advance the status in the default status cycle
                    let defaultStatuses = localStatuses.filter {
                        let s = $0.lowercased()
                        return s != "camera bag" && s != "personal"
                    }
                    if let index = defaultStatuses.firstIndex(where: { $0.lowercased() == last.status.lowercased() }) {
                        let nextIndex = (index + 1) % defaultStatuses.count
                        self.status = defaultStatuses[nextIndex]
                    } else {
                        self.status = defaultStatuses.first ?? ""
                    }
                } else {
                    // If no last record is found, attempt to use the locally cached school list
                    if let data = UserDefaults.standard.data(forKey: "dropdownRecords"),
                       let cachedDropdowns = try? JSONDecoder().decode([DropdownRecord].self, from: data) {
                        if !cachedDropdowns.isEmpty {
                            self.school = cachedDropdowns.sorted { $0.value < $1.value }.first?.value ?? ""
                        }
                    }
                }
                self.showingForm = true
                
            case .failure(let error):
                print("DEBUG: Error fetching last record: \(error.localizedDescription)")
                self.lastRecord = nil
                
                // Still show the form even if we couldn't fetch history
                self.toastMessage = "Could not fetch card history. Starting fresh."
                self.isSuccessToast = false
                self.showToast = true
                self.showingForm = true
            }
        }
    }
    
    func fetchLastJobBoxRecord(for boxNumber: String) {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            isLoading = false
            return
        }
        
        FirestoreManager.shared.fetchJobBoxRecords(field: "boxNumber", value: boxNumber, organizationID: orgID) { result in
            isLoading = false
            
            switch result {
            case .success(let records):
                let sortedRecords = records.sorted { $0.timestamp > $1.timestamp }
                self.lastJobBoxRecord = sortedRecords.first
                
                if let last = self.lastJobBoxRecord {
                    self.school = last.school
                    self.schoolId = last.schoolId
                    
                    // Advance the status in the job box status cycle
                    let currentStatusString = last.status.rawValue
                    if let index = jobBoxStatuses.firstIndex(where: { $0.lowercased() == currentStatusString.lowercased() }) {
                        let nextIndex = (index + 1) % jobBoxStatuses.count
                        self.status = jobBoxStatuses[nextIndex]
                    } else {
                        self.status = jobBoxStatuses.first ?? ""
                    }
                } else {
                    // For new job boxes, don't pre-select values - let them be chosen via session
                    self.school = ""
                    self.schoolId = nil
                    self.status = "" // Will be set when session is selected
                }
                
                // Always refresh sessions for job boxes
                // Sessions will be loaded in JobBoxFormView
                
                self.showingJobBoxForm = true
                
            case .failure(let error):
                print("DEBUG: Error fetching last job box record: \(error.localizedDescription)")
                self.lastJobBoxRecord = nil
                
                // Still show the form even if we couldn't fetch history
                self.toastMessage = "Could not fetch job box history. Starting fresh."
                self.isSuccessToast = false
                self.showToast = true
                
                // For new job boxes, don't pre-select values
                self.school = ""
                self.schoolId = nil
                self.status = ""
                
                // Always refresh sessions
                // Sessions will be loaded in JobBoxFormView
                
                self.showingJobBoxForm = true
            }
        }
    }
}

struct ScanView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScanView()
        }
    }
}