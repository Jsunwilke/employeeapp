# iOS Time Tracking Implementation Manual

## Overview
This manual provides the complete implementation guide for adding time tracking/clock in functionality to the existing iOS app. Since authentication and session management are already integrated, this focuses purely on the time tracking features.

## Table of Contents
1. [Firestore Data Model](#firestore-data-model)
2. [Core Time Tracking Functions](#core-time-tracking-functions)
3. [Firebase Integration](#firebase-integration)
4. [Business Logic & Validation](#business-logic--validation)
5. [UI Implementation](#ui-implementation)
6. [Code Examples](#code-examples)

---

## Firestore Data Model

### timeEntries Collection

Each time entry document has the following structure:

```javascript
{
  id: string,                    // Auto-generated Firestore document ID
  userId: string,                // Firebase Auth UID of the user
  organizationID: string,        // Organization the user belongs to
  clockInTime: timestamp,        // Firebase server timestamp of clock in
  clockOutTime: timestamp,       // Firebase server timestamp of clock out (null if active)
  date: string,                  // Date in YYYY-MM-DD format (local timezone)
  status: string,                // "clocked-in" or "clocked-out"
  sessionId: string,             // Optional: ID of photography session
  notes: string,                 // Optional: User notes (max 500 characters)
  createdAt: timestamp,          // Document creation timestamp
  updatedAt: timestamp           // Last update timestamp
}
```

### Required Firestore Indexes

Create these composite indexes in the Firebase Console:

1. **Collection:** `timeEntries`
   - Fields: `organizationID` (Ascending), `userId` (Ascending), `date` (Descending)

2. **Collection:** `timeEntries`
   - Fields: `organizationID` (Ascending), `date` (Descending), `createdAt` (Descending)

3. **Collection:** `timeEntries`
   - Fields: `userId` (Ascending), `organizationID` (Ascending), `status` (Ascending)

---

## Core Time Tracking Functions

### 1. Check Current Time Entry Status

Before allowing clock in/out, always check if user has an active entry:

```swift
func getCurrentTimeEntry(userId: String, organizationID: String, completion: @escaping (TimeEntry?) -> Void) {
    let db = Firestore.firestore()
    
    db.collection("timeEntries")
        .whereField("userId", isEqualTo: userId)
        .whereField("organizationID", isEqualTo: organizationID)
        .whereField("status", isEqualTo: "clocked-in")
        .getDocuments { snapshot, error in
            if let error = error {
                print("Error getting current time entry: \(error)")
                completion(nil)
                return
            }
            
            if let document = snapshot?.documents.first {
                let timeEntry = TimeEntry(document: document)
                completion(timeEntry)
            } else {
                completion(nil)
            }
        }
}
```

### 2. Clock In Function

```swift
func clockIn(userId: String, organizationID: String, sessionId: String? = nil, notes: String? = nil, completion: @escaping (Bool, String?) -> Void) {
    let db = Firestore.firestore()
    
    // First check if user already has an active entry
    getCurrentTimeEntry(userId: userId, organizationID: organizationID) { activeEntry in
        if activeEntry != nil {
            completion(false, "You already have an active time entry. Please clock out first.")
            return
        }
        
        // Get current date in YYYY-MM-DD format (local timezone)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let currentDate = dateFormatter.string(from: Date())
        
        // Create time entry data
        var timeEntryData: [String: Any] = [
            "userId": userId,
            "organizationID": organizationID,
            "clockInTime": FieldValue.serverTimestamp(),
            "date": currentDate,
            "status": "clocked-in",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        // Add optional fields
        if let sessionId = sessionId {
            timeEntryData["sessionId"] = sessionId
        }
        if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            timeEntryData["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Create the document
        db.collection("timeEntries").addDocument(data: timeEntryData) { error in
            if let error = error {
                completion(false, "Failed to clock in: \(error.localizedDescription)")
            } else {
                completion(true, nil)
            }
        }
    }
}
```

### 3. Clock Out Function

```swift
func clockOut(userId: String, organizationID: String, notes: String? = nil, completion: @escaping (Bool, String?) -> Void) {
    let db = Firestore.firestore()
    
    // Get the current active entry
    getCurrentTimeEntry(userId: userId, organizationID: organizationID) { activeEntry in
        guard let activeEntry = activeEntry else {
            completion(false, "No active time entry found. Please clock in first.")
            return
        }
        
        // Prepare update data
        var updateData: [String: Any] = [
            "clockOutTime": FieldValue.serverTimestamp(),
            "status": "clocked-out",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        // Handle notes
        if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateData["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Update the document
        db.collection("timeEntries").document(activeEntry.id).updateData(updateData) { error in
            if let error = error {
                completion(false, "Failed to clock out: \(error.localizedDescription)")
            } else {
                completion(true, nil)
            }
        }
    }
}
```

### 4. Get Time Entries for Date Range

```swift
func getTimeEntries(userId: String, organizationID: String, startDate: String, endDate: String, completion: @escaping ([TimeEntry]) -> Void) {
    let db = Firestore.firestore()
    
    db.collection("timeEntries")
        .whereField("userId", isEqualTo: userId)
        .whereField("organizationID", isEqualTo: organizationID)
        .whereField("date", isGreaterThanOrEqualTo: startDate)
        .whereField("date", isLessThanOrEqualTo: endDate)
        .order(by: "date", descending: true)
        .order(by: "createdAt", descending: true)
        .getDocuments { snapshot, error in
            if let error = error {
                print("Error getting time entries: \(error)")
                completion([])
                return
            }
            
            let timeEntries = snapshot?.documents.compactMap { document in
                TimeEntry(document: document)
            } ?? []
            
            completion(timeEntries)
        }
}
```

---

## Firebase Integration

### TimeEntry Model

```swift
struct TimeEntry: Identifiable, Codable {
    let id: String
    let userId: String
    let organizationID: String
    let clockInTime: Date?
    let clockOutTime: Date?
    let date: String
    let status: String
    let sessionId: String?
    let notes: String?
    let createdAt: Date?
    let updatedAt: Date?
    
    init(document: QueryDocumentSnapshot) {
        self.id = document.documentID
        let data = document.data()
        
        self.userId = data["userId"] as? String ?? ""
        self.organizationID = data["organizationID"] as? String ?? ""
        self.date = data["date"] as? String ?? ""
        self.status = data["status"] as? String ?? ""
        self.sessionId = data["sessionId"] as? String
        self.notes = data["notes"] as? String
        
        // Convert Firestore timestamps to Date objects
        if let clockInTimestamp = data["clockInTime"] as? Timestamp {
            self.clockInTime = clockInTimestamp.dateValue()
        } else {
            self.clockInTime = nil
        }
        
        if let clockOutTimestamp = data["clockOutTime"] as? Timestamp {
            self.clockOutTime = clockOutTimestamp.dateValue()
        } else {
            self.clockOutTime = nil
        }
        
        if let createdAtTimestamp = data["createdAt"] as? Timestamp {
            self.createdAt = createdAtTimestamp.dateValue()
        } else {
            self.createdAt = nil
        }
        
        if let updatedAtTimestamp = data["updatedAt"] as? Timestamp {
            self.updatedAt = updatedAtTimestamp.dateValue()
        } else {
            self.updatedAt = nil
        }
    }
    
    // Calculate duration in seconds
    var durationInSeconds: TimeInterval? {
        guard let clockIn = clockInTime else { return nil }
        let clockOut = clockOutTime ?? Date() // Use current time if still clocked in
        return clockOut.timeIntervalSince(clockIn)
    }
    
    // Format duration as hours and minutes
    var formattedDuration: String {
        guard let duration = durationInSeconds else { return "0h 0m" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    // Get duration in decimal hours for calculations
    var durationInHours: Double {
        guard let duration = durationInSeconds else { return 0.0 }
        return duration / 3600.0
    }
}
```

### Real-Time Timer Implementation

```swift
class TimeTrackingViewModel: ObservableObject {
    @Published var currentTimeEntry: TimeEntry?
    @Published var elapsedTime: TimeInterval = 0
    @Published var isClockIn = false
    
    private var timer: Timer?
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateElapsedTime()
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateElapsedTime() {
        guard let currentEntry = currentTimeEntry,
              let clockInTime = currentEntry.clockInTime else {
            elapsedTime = 0
            return
        }
        
        elapsedTime = Date().timeIntervalSince(clockInTime)
    }
    
    func formatElapsedTime() -> String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
```

---

## Business Logic & Validation

### 1. Time Entry Validation Rules

```swift
struct TimeEntryValidator {
    
    // Validate notes field
    static func validateNotes(_ notes: String?) -> (isValid: Bool, error: String?) {
        guard let notes = notes, !notes.isEmpty else {
            return (true, nil) // Notes are optional
        }
        
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedNotes.count > 500 {
            return (false, "Notes cannot exceed 500 characters")
        }
        
        // Basic XSS prevention - remove/escape HTML-like content
        let sanitizedNotes = trimmedNotes.replacingOccurrences(of: "<", with: "&lt;")
                                        .replacingOccurrences(of: ">", with: "&gt;")
        
        return (true, nil)
    }
    
    // Validate manual time entry
    static func validateManualEntry(date: String, startTime: Date, endTime: Date) -> (isValid: Bool, error: String?) {
        // Cannot create future entries
        let today = Date()
        if endTime > today {
            return (false, "Cannot create time entries for future dates")
        }
        
        // End time must be after start time
        if endTime <= startTime {
            return (false, "End time must be after start time")
        }
        
        // Maximum duration check (16 hours)
        let duration = endTime.timeIntervalSince(startTime)
        if duration > 16 * 3600 { // 16 hours in seconds
            return (false, "Time entry cannot exceed 16 hours")
        }
        
        // Minimum duration check (1 minute)
        if duration < 60 {
            return (false, "Time entry must be at least 1 minute long")
        }
        
        return (true, nil)
    }
    
    // Check if user can edit entry (30-day rule)
    static func canEditEntry(_ entry: TimeEntry) -> Bool {
        guard let createdAt = entry.createdAt else { return false }
        
        // Cannot edit active entries
        if entry.status == "clocked-in" {
            return false
        }
        
        // 30-day edit window
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return createdAt >= thirtyDaysAgo
    }
}
```

### 2. Overlap Detection

```swift
func checkTimeOverlap(userId: String, organizationID: String, startTime: Date, endTime: Date, excludeEntryId: String? = nil, completion: @escaping (Bool, Int) -> Void) {
    let db = Firestore.firestore()
    
    // Get date string for the entry
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let dateString = dateFormatter.string(from: startTime)
    
    db.collection("timeEntries")
        .whereField("userId", isEqualTo: userId)
        .whereField("organizationID", isEqualTo: organizationID)
        .whereField("date", isEqualTo: dateString)
        .getDocuments { snapshot, error in
            if let error = error {
                print("Error checking overlap: \(error)")
                completion(false, 0)
                return
            }
            
            var overlapCount = 0
            let entries = snapshot?.documents.compactMap { document in
                TimeEntry(document: document)
            } ?? []
            
            for entry in entries {
                // Skip the entry being edited
                if let excludeId = excludeEntryId, entry.id == excludeId {
                    continue
                }
                
                // Skip entries without proper times
                guard let entryStart = entry.clockInTime,
                      let entryEnd = entry.clockOutTime else {
                    continue
                }
                
                // Check for overlap
                if startTime < entryEnd && endTime > entryStart {
                    overlapCount += 1
                }
            }
            
            completion(overlapCount > 0, overlapCount)
        }
}
```

### 3. Session Integration

Since sessions are already integrated, you can fetch today's assigned sessions like this:

```swift
func getTodayAssignedSessions(userId: String, organizationID: String, completion: @escaping ([Session]) -> Void) {
    let db = Firestore.firestore()
    
    // Get today's date in YYYY-MM-DD format
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let today = dateFormatter.string(from: Date())
    
    db.collection("sessions")
        .whereField("organizationID", isEqualTo: organizationID)
        .whereField("date", isEqualTo: today)
        .getDocuments { snapshot, error in
            if let error = error {
                print("Error getting sessions: \(error)")
                completion([])
                return
            }
            
            let allSessions = snapshot?.documents.compactMap { document in
                Session(document: document)
            } ?? []
            
            // Filter sessions assigned to the user
            let assignedSessions = allSessions.filter { session in
                // Check modern photographers array format
                if let photographers = session.photographers,
                   photographers.contains(where: { $0.id == userId }) {
                    return true
                }
                
                // Check legacy photographer format
                if let photographer = session.photographer,
                   photographer.id == userId {
                    return true
                }
                
                return false
            }
            
            completion(assignedSessions)
        }
}
```

---

## UI Implementation

### 1. Clock In/Out Button States

```swift
struct ClockInOutButton: View {
    @ObservedObject var viewModel: TimeTrackingViewModel
    @State private var showingSessionSelection = false
    @State private var showingNotesInput = false
    @State private var notes = ""
    @State private var selectedSession: Session?
    
    var body: some View {
        VStack {
            if viewModel.isClockIn {
                // Clocked In State
                VStack {
                    Text("Clocked In")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    
                    Text(viewModel.formatElapsedTime())
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Button("Clock Out") {
                        showingNotesInput = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                // Clocked Out State
                Button("Clock In") {
                    showingSessionSelection = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .sheet(isPresented: $showingSessionSelection) {
            SessionSelectionView(
                selectedSession: $selectedSession,
                notes: $notes,
                onClockIn: { session, notes in
                    viewModel.clockIn(sessionId: session?.id, notes: notes)
                }
            )
        }
        .sheet(isPresented: $showingNotesInput) {
            NotesInputView(
                notes: $notes,
                onClockOut: { notes in
                    viewModel.clockOut(notes: notes)
                }
            )
        }
    }
}
```

### 2. Session Selection Interface

```swift
struct SessionSelectionView: View {
    @Binding var selectedSession: Session?
    @Binding var notes: String
    @State private var availableSessions: [Session] = []
    let onClockIn: (Session?, String) -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                if availableSessions.isEmpty {
                    VStack {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No sessions assigned for today")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("You can still clock in without selecting a session")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                } else {
                    List(availableSessions, id: \.id) { session in
                        SessionRow(session: session, isSelected: selectedSession?.id == session.id)
                            .onTapGesture {
                                selectedSession = session
                            }
                    }
                }
                
                VStack {
                    TextField("Add notes (optional)", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                    
                    Button("Clock In") {
                        onClockIn(selectedSession, notes)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
            .navigationTitle("Clock In")
            .navigationBarItems(trailing: Button("Cancel") {
                // Dismiss
            })
        }
        .onAppear {
            loadTodaysSessions()
        }
    }
    
    private func loadTodaysSessions() {
        // Use your existing session loading logic
        getTodayAssignedSessions(userId: currentUserId, organizationID: currentOrgId) { sessions in
            self.availableSessions = sessions
        }
    }
}
```

### 3. Time Entry List View

```swift
struct TimeEntryListView: View {
    @State private var timeEntries: [TimeEntry] = []
    @State private var selectedDateRange = DateRange.today
    
    enum DateRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
    }
    
    var body: some View {
        VStack {
            Picker("Date Range", selection: $selectedDateRange) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            List(timeEntries) { entry in
                TimeEntryRow(entry: entry)
            }
        }
        .onAppear {
            loadTimeEntries()
        }
        .onChange(of: selectedDateRange) { _ in
            loadTimeEntries()
        }
    }
    
    private func loadTimeEntries() {
        let (startDate, endDate) = getDateRange(for: selectedDateRange)
        getTimeEntries(
            userId: currentUserId,
            organizationID: currentOrgId,
            startDate: startDate,
            endDate: endDate
        ) { entries in
            self.timeEntries = entries
        }
    }
}

struct TimeEntryRow: View {
    let entry: TimeEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formatDate(entry.date))
                    .font(.headline)
                Spacer()
                Text(entry.formattedDuration)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
            
            HStack {
                Image(systemName: entry.status == "clocked-in" ? "play.circle.fill" : "stop.circle.fill")
                    .foregroundColor(entry.status == "clocked-in" ? .green : .gray)
                
                Text(formatTimeRange())
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if entry.status == "clocked-in" {
                    Text("• ACTIVE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }
            
            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTimeRange() -> String {
        guard let clockIn = entry.clockInTime else { return "" }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        if let clockOut = entry.clockOutTime {
            return "\(formatter.string(from: clockIn)) - \(formatter.string(from: clockOut))"
        } else {
            return "\(formatter.string(from: clockIn)) - Present"
        }
    }
}
```

---

## Code Examples

### Complete TimeTrackingService Class

```swift
import Foundation
import FirebaseFirestore
import FirebaseAuth

class TimeTrackingService: ObservableObject {
    private let db = Firestore.firestore()
    
    @Published var currentTimeEntry: TimeEntry?
    @Published var isClockIn = false
    @Published var elapsedTime: TimeInterval = 0
    
    private var timer: Timer?
    private var currentUserId: String?
    private var currentOrgId: String?
    
    init() {
        setupUser()
        checkCurrentStatus()
    }
    
    private func setupUser() {
        guard let user = Auth.auth().currentUser else { return }
        self.currentUserId = user.uid
        
        // Get organization ID from user profile (assuming you have this)
        // self.currentOrgId = userProfile.organizationID
    }
    
    // MARK: - Main Clock In/Out Functions
    
    func clockIn(sessionId: String? = nil, notes: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion(false, "User not authenticated")
            return
        }
        
        // Validate notes
        let (isValid, error) = TimeEntryValidator.validateNotes(notes)
        if !isValid {
            completion(false, error)
            return
        }
        
        getCurrentTimeEntry(userId: userId, organizationID: orgId) { [weak self] activeEntry in
            if activeEntry != nil {
                completion(false, "You already have an active time entry. Please clock out first.")
                return
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current
            let currentDate = dateFormatter.string(from: Date())
            
            var timeEntryData: [String: Any] = [
                "userId": userId,
                "organizationID": orgId,
                "clockInTime": FieldValue.serverTimestamp(),
                "date": currentDate,
                "status": "clocked-in",
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            if let sessionId = sessionId {
                timeEntryData["sessionId"] = sessionId
            }
            if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                timeEntryData["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            self?.db.collection("timeEntries").addDocument(data: timeEntryData) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(false, "Failed to clock in: \(error.localizedDescription)")
                    } else {
                        self?.checkCurrentStatus()
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    func clockOut(notes: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            completion(false, "User not authenticated")
            return
        }
        
        // Validate notes
        let (isValid, error) = TimeEntryValidator.validateNotes(notes)
        if !isValid {
            completion(false, error)
            return
        }
        
        getCurrentTimeEntry(userId: userId, organizationID: orgId) { [weak self] activeEntry in
            guard let activeEntry = activeEntry else {
                completion(false, "No active time entry found. Please clock in first.")
                return
            }
            
            var updateData: [String: Any] = [
                "clockOutTime": FieldValue.serverTimestamp(),
                "status": "clocked-out",
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateData["notes"] = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            self?.db.collection("timeEntries").document(activeEntry.id).updateData(updateData) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(false, "Failed to clock out: \(error.localizedDescription)")
                    } else {
                        self?.checkCurrentStatus()
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    // MARK: - Status Management
    
    private func checkCurrentStatus() {
        guard let userId = currentUserId,
              let orgId = currentOrgId else { return }
        
        getCurrentTimeEntry(userId: userId, organizationID: orgId) { [weak self] activeEntry in
            DispatchQueue.main.async {
                self?.currentTimeEntry = activeEntry
                self?.isClockIn = (activeEntry != nil)
                
                if activeEntry != nil {
                    self?.startTimer()
                } else {
                    self?.stopTimer()
                }
            }
        }
    }
    
    private func startTimer() {
        stopTimer() // Stop any existing timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateElapsedTime()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsedTime = 0
    }
    
    private func updateElapsedTime() {
        guard let currentEntry = currentTimeEntry,
              let clockInTime = currentEntry.clockInTime else {
            elapsedTime = 0
            return
        }
        
        elapsedTime = Date().timeIntervalSince(clockInTime)
    }
    
    func formatElapsedTime() -> String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    // MARK: - Helper Functions
    
    private func getCurrentTimeEntry(userId: String, organizationID: String, completion: @escaping (TimeEntry?) -> Void) {
        db.collection("timeEntries")
            .whereField("userId", isEqualTo: userId)
            .whereField("organizationID", isEqualTo: organizationID)
            .whereField("status", isEqualTo: "clocked-in")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error getting current time entry: \(error)")
                    completion(nil)
                    return
                }
                
                if let document = snapshot?.documents.first {
                    let timeEntry = TimeEntry(document: document)
                    completion(timeEntry)
                } else {
                    completion(nil)
                }
            }
    }
}
```

### Utility Functions

```swift
extension Date {
    func toYYYYMMDD() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: self)
    }
}

extension TimeInterval {
    func formatAsHoursMinutes() -> String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    func formatAsHoursMinutesSeconds() -> String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
```

---

## Important Implementation Notes

### 1. Background App Considerations
- When the app goes to background while clocked in, the timer should continue
- Use background app refresh to update the timer when returning to foreground
- Consider local notifications to remind users if they've been clocked in for extended periods

### 2. Offline Handling
- Store clock in/out attempts locally when offline
- Sync with Firestore when connection is restored
- Show appropriate UI states for offline mode

### 3. Error Handling
- Always provide user-friendly error messages
- Log detailed errors for debugging
- Implement retry mechanisms for network failures

### 4. Performance Considerations
- Use Firestore listeners sparingly to avoid excessive reads
- Cache session data locally to reduce repeated queries
- Implement pagination for time entry lists if needed

### 5. Security
- All Firestore rules should validate user permissions
- Sanitize user input (especially notes field)
- Validate all dates and times on the server side

This manual provides everything needed to implement the time tracking functionality in your iOS app, maintaining feature parity with the web application.