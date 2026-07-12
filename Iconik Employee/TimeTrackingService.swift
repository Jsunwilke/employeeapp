import Foundation
import Supabase
import Network

@MainActor
class TimeTrackingService: ObservableObject {
    private let supabase = SupabaseManager.shared.client

    @Published var currentTimeEntry: TimeEntry?
    @Published var isClockIn = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var isUsingOfflineData = false
    @Published var lastSyncTime: Date?
    @Published var isConnected = true

    private var timer: Timer?
    private var isClockingOut = false

    // Computed from the live session/UserDefaults rather than captured at init,
    // so a sign-in that completes after this service is created is still picked up
    private var currentUserId: String? {
        supabase.auth.currentUser?.id.uuidString.lowercased()
    }
    private var currentOrgId: String? {
        UserDefaults.standard.string(forKey: "userOrganizationID")
    }

    // Persistent cache and network monitoring
    private let persistentCache = TimeEntryCacheManager.shared
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "TimeTrackingNetworkMonitor")

    init() {
        setupNetworkMonitoring()
        Task {
            // Load cached current entry immediately for instant display
            await loadCachedCurrentEntry()
            // Then check actual status from network
            await checkCurrentStatus()
        }
    }

    deinit {
        timer?.invalidate()
        timer = nil
        networkMonitor.cancel()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = self?.isConnected == false
                self?.isConnected = path.status == .satisfied

                // When coming back online, refresh status
                if wasOffline && path.status == .satisfied {
                    self?.isUsingOfflineData = false
                    await self?.checkCurrentStatus()
                    print("📡 TimeTrackingService: Network restored - refreshing status")
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Cache Operations

    /// Load cached current entry for instant display
    private func loadCachedCurrentEntry() async {
        if let cached = await persistentCache.loadCurrentEntry() {
            // Only use if still clocked in
            if cached.status == "clocked-in" {
                self.currentTimeEntry = cached
                self.isClockIn = true
                self.isUsingOfflineData = true
                startTimer()
                print("📱 TimeTrackingService: Loaded cached active entry for instant display")
            }
        }
    }

    /// Save current entry to cache
    private func cacheCurrentEntry() async {
        await persistentCache.saveCurrentEntry(currentTimeEntry)
    }

    func refreshUserAndStatus() async {
        await checkCurrentStatus()
    }

    // MARK: - Main Clock In/Out Functions

    func clockIn(sessionId: String? = nil, notes: String? = nil) async throws {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            throw TimeTrackingError.userNotAuthenticated
        }

        // Validate notes
        let (isValid, error) = TimeEntryValidator.validateNotes(notes)
        if !isValid {
            throw TimeTrackingError.validationFailed(error ?? "Invalid notes")
        }

        // Check for active entry
        if let activeEntry = try await getCurrentTimeEntry(userId: userId, organizationID: orgId) {
            throw TimeTrackingError.alreadyClockedIn
        }

        let currentDate = Date().toYYYYMMDD()

        // Get session name if session ID provided
        var sessionName: String?
        if let sessionId = sessionId {
            if let session = try await SessionService.shared.fetchSession(sessionId: sessionId) {
                sessionName = SessionService.shared.getSessionDisplayName(for: session)
            }
        }

        // Create time entry
        struct InsertData: Encodable {
            let id: String
            let user_id: String
            let organization_id: String
            let start_time: Date // Database column name
            let date: String
            let status: String
            let session_id: String?
            let session_name: String?
            let notes: String?
        }

        let insertData = InsertData(
            id: UUID().uuidString,
            user_id: userId,
            organization_id: orgId,
            start_time: Date(),
            date: currentDate,
            status: "clocked-in",
            session_id: sessionId,
            session_name: sessionName,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let _: TimeEntry = try await supabase
            .from("time_entries")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        await checkCurrentStatus()
        await cacheCurrentEntry()
    }

    func clockOut(notes: String? = nil) async throws {
        guard !isClockingOut else { return }
        isClockingOut = true
        defer { isClockingOut = false }

        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            throw TimeTrackingError.userNotAuthenticated
        }

        // Validate notes
        let (isValid, error) = TimeEntryValidator.validateNotes(notes)
        if !isValid {
            throw TimeTrackingError.validationFailed(error ?? "Invalid notes")
        }

        guard let activeEntry = try await getCurrentTimeEntry(userId: userId, organizationID: orgId) else {
            throw TimeTrackingError.noActiveEntry
        }

        // Calculate total hours
        guard let startTime = activeEntry.start_time else {
            throw TimeTrackingError.invalidEntry
        }
        let endTime = Date()
        let totalHours = endTime.timeIntervalSince(startTime) / 3600.0

        // Update time entry
        struct UpdateData: Encodable {
            let end_time: Date // Database column name
            let total_hours: Double
            let status: String
            let notes: String?
        }

        let updateData = UpdateData(
            end_time: endTime,
            total_hours: totalHours,
            status: "clocked-out",
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        try await supabase
            .from("time_entries")
            .update(updateData)
            .eq("id", value: activeEntry.id)
            .execute()

        await checkCurrentStatus()
        await cacheCurrentEntry()
    }

    func clockOutManual(clockOutDateTime: Date, notes: String? = nil) async throws {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            throw TimeTrackingError.userNotAuthenticated
        }

        // Validate notes
        let (isValid, error) = TimeEntryValidator.validateNotes(notes)
        if !isValid {
            throw TimeTrackingError.validationFailed(error ?? "Invalid notes")
        }

        // Validate clock out time
        if clockOutDateTime > Date() {
            throw TimeTrackingError.validationFailed("Clock out time cannot be in the future")
        }

        guard let activeEntry = try await getCurrentTimeEntry(userId: userId, organizationID: orgId) else {
            throw TimeTrackingError.noActiveEntry
        }

        guard let clockInTime = activeEntry.clockInTime else {
            throw TimeTrackingError.invalidEntry
        }

        if clockOutDateTime <= clockInTime {
            throw TimeTrackingError.validationFailed("Clock out time must be after clock in time")
        }

        // Validate not longer than 24 hours
        let duration = clockOutDateTime.timeIntervalSince(clockInTime)
        if duration > 24 * 60 * 60 {
            throw TimeTrackingError.validationFailed("Shift duration cannot exceed 24 hours")
        }

        let totalHours = duration / 3600.0

        // Update time entry
        struct UpdateData: Encodable {
            let end_time: Date
            let total_hours: Double
            let status: String
            let notes: String?
        }

        let updateData = UpdateData(
            end_time: clockOutDateTime,
            total_hours: totalHours,
            status: "clocked-out",
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        try await supabase
            .from("time_entries")
            .update(updateData)
            .eq("id", value: activeEntry.id)
            .execute()

        await checkCurrentStatus()
        await cacheCurrentEntry()
    }

    func updateActiveClockInTime(newClockInTime: Date) async throws {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            throw TimeTrackingError.userNotAuthenticated
        }

        // Get the current active entry
        guard let activeEntry = try await getCurrentTimeEntry(userId: userId, organizationID: orgId),
              activeEntry.status == "clocked-in" else {
            throw TimeTrackingError.noActiveEntry
        }

        // Validate the new clock-in time
        let validation = TimeEntryValidator.canEditActiveClockIn(activeEntry, newClockInTime: newClockInTime)
        if !validation.isValid {
            throw TimeTrackingError.validationFailed(validation.error ?? "Invalid clock-in time")
        }

        // Update the entry in Supabase
        struct UpdateData: Encodable {
            let start_time: Date
            let updated_at: Date
        }

        let updateData = UpdateData(
            start_time: newClockInTime,
            updated_at: Date()
        )

        try await supabase
            .from("time_entries")
            .update(updateData)
            .eq("id", value: activeEntry.id)
            .execute()

        // Refresh current status to update local state
        await checkCurrentStatus()
    }

    // MARK: - Status Management

    func checkCurrentStatus() async {
        guard let userId = currentUserId,
              let orgId = currentOrgId else { return }

        // If offline, use cached data
        if !isConnected {
            if currentTimeEntry == nil {
                await loadCachedCurrentEntry()
            }
            return
        }

        do {
            let activeEntry = try await getCurrentTimeEntry(userId: userId, organizationID: orgId)
            self.currentTimeEntry = activeEntry
            self.isClockIn = (activeEntry != nil)
            self.isUsingOfflineData = false
            self.lastSyncTime = Date()

            // Cache the current entry for offline use
            await cacheCurrentEntry()

            if activeEntry != nil {
                startTimer()
            } else {
                stopTimer()
            }
        } catch {
            // On network error, fall back to cache
            if currentTimeEntry == nil {
                await loadCachedCurrentEntry()
            }
        }
    }

    private func startTimer() {
        stopTimer() // Stop any existing timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
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

    private func getCurrentTimeEntry(userId: String, organizationID: String) async throws -> TimeEntry? {
        let entries: [TimeEntry] = try await supabase
            .from("time_entries")
            .select()
            .eq("user_id", value: userId)
            .eq("organization_id", value: organizationID)
            .eq("status", value: "clocked-in")
            .limit(1)
            .execute()
            .value

        return entries.first
    }

    func getTimeEntries(startDate: String, endDate: String) async throws -> [TimeEntry] {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            return []
        }

        // If offline, try to load from cache
        if !isConnected {
            if let cached = await persistentCache.loadTimeEntries(userId: userId, organizationId: orgId) {
                isUsingOfflineData = true
                lastSyncTime = cached.lastSync
                return cached.entries
            }
            return []
        }

        // Get device's current timezone offset (e.g., "-06:00" for Central)
        let offsetSeconds = TimeZone.current.secondsFromGMT()
        let hours = abs(offsetSeconds) / 3600
        let minutes = (abs(offsetSeconds) % 3600) / 60
        let sign = offsetSeconds >= 0 ? "+" : "-"
        let tzOffset = String(format: "%@%02d:%02d", sign, hours, minutes)

        do {
            let entries: [TimeEntry] = try await supabase
                .from("time_entries")
                .select()
                .eq("user_id", value: userId)
                .eq("organization_id", value: orgId)
                .gte("start_time", value: "\(startDate)T00:00:00\(tzOffset)")
                .lte("start_time", value: "\(endDate)T23:59:59\(tzOffset)")
                .order("start_time", ascending: false)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value

            // Cache the entries for offline use
            await persistentCache.saveTimeEntries(entries, userId: userId, organizationId: orgId, periodStart: startDate, periodEnd: endDate)
            isUsingOfflineData = false
            lastSyncTime = Date()

            return entries
        } catch {
            // On error, try to load from cache
            if let cached = await persistentCache.loadTimeEntries(userId: userId, organizationId: orgId) {
                isUsingOfflineData = true
                lastSyncTime = cached.lastSync
                return cached.entries
            }
            throw error
        }
    }

    /// Debug function to diagnose time entry issues (prints removed for production)
    func debugTimeEntryQuery() async {
        // Debug function - outputs removed for cleaner console
    }

    func getTodayAssignedSessions() async throws -> [Session] {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            return []
        }

        // Get current user email for fallback matching
        let currentUserEmail = UserDefaults.standard.string(forKey: "userEmail")

        let today = Date().toYYYYMMDD()

        let allSessions = try await SessionService.shared.fetchSessions(
            organizationID: orgId,
            includeUnpublished: false
        )

        // A session's days live in session_days; include any session with a day on
        // today (not just first-day), rendered as that day's occurrence.
        return allSessions.compactMap { session -> Session? in
            guard session.isUserAssigned(userID: userId, userEmail: currentUserEmail),
                  let todayDay = session.day(onDate: today) else { return nil }
            return session.with(day: todayDay)
        }
    }

    func getAvailableSessionsForJobBox() async throws -> [Session] {
        guard let orgId = currentOrgId else {
            return []
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoWeeksFromNow = calendar.date(byAdding: .day, value: 14, to: today)!

        // Format dates for comparison
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)
        let twoWeeksString = dateFormatter.string(from: twoWeeksFromNow)

        // Fetch sessions using SessionService
        let allSessions = try await SessionService.shared.fetchSessions(
            organizationID: orgId,
            includeUnpublished: false
        )

        // Filter sessions for next 2 weeks with scheduled status
        let filteredSessions = allSessions.filter { session in
            session.status == "scheduled" &&
            session.date >= todayString &&
            session.date <= twoWeeksString
        }

        // Sort by date and time
        return filteredSessions.sorted { (session1, session2) in
            if session1.date != session2.date {
                return session1.date < session2.date
            }
            return session1.start_time < session2.start_time
        }
    }

    // MARK: - Manual Time Entry Operations

    func createManualTimeEntry(
        date: Date,
        startTime: Date,
        endTime: Date,
        sessionId: String? = nil,
        notes: String? = nil
    ) async throws {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            throw TimeTrackingError.userNotAuthenticated
        }

        // Validate the manual entry
        let dateString = date.toYYYYMMDD()
        let (isValid, validationError) = TimeEntryValidator.validateManualEntry(
            date: dateString,
            startTime: startTime,
            endTime: endTime
        )
        if !isValid {
            throw TimeTrackingError.validationFailed(validationError ?? "Invalid entry")
        }

        // Validate notes
        let (notesValid, notesError) = TimeEntryValidator.validateNotes(notes)
        if !notesValid {
            throw TimeTrackingError.validationFailed(notesError ?? "Invalid notes")
        }

        // Check for overlaps
        let (hasOverlap, overlapCount) = try await checkTimeOverlap(
            startTime: startTime,
            endTime: endTime
        )
        if hasOverlap {
            throw TimeTrackingError.overlappingEntry(count: overlapCount)
        }

        // Get session name if needed
        var sessionName: String?
        if let sessionId = sessionId {
            if let session = try await SessionService.shared.fetchSession(sessionId: sessionId) {
                sessionName = SessionService.shared.getSessionDisplayName(for: session)
            }
        }

        // Calculate total hours
        let totalHours = endTime.timeIntervalSince(startTime) / 3600.0

        // Create the manual time entry
        struct InsertData: Encodable {
            let id: String
            let user_id: String
            let organization_id: String
            let start_time: Date
            let end_time: Date
            let total_hours: Double
            let date: String
            let status: String
            let session_id: String?
            let session_name: String?
            let notes: String?
        }

        let insertData = InsertData(
            id: UUID().uuidString,
            user_id: userId,
            organization_id: orgId,
            start_time: startTime,
            end_time: endTime,
            total_hours: totalHours,
            date: dateString,
            status: "clocked-out",
            session_id: sessionId,
            session_name: sessionName,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let _: TimeEntry = try await supabase
            .from("time_entries")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value
    }

    func updateTimeEntry(
        entryId: String,
        startTime: Date,
        endTime: Date,
        sessionId: String? = nil,
        notes: String? = nil
    ) async throws {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            throw TimeTrackingError.userNotAuthenticated
        }

        // Get existing entry
        let entries: [TimeEntry] = try await supabase
            .from("time_entries")
            .select()
            .eq("id", value: entryId)
            .limit(1)
            .execute()
            .value

        guard let timeEntry = entries.first else {
            throw TimeTrackingError.entryNotFound
        }

        // Check permissions
        if !TimeEntryValidator.canEditEntry(timeEntry) {
            throw TimeTrackingError.editWindowExpired
        }

        if timeEntry.user_id != userId || timeEntry.organization_id != orgId {
            throw TimeTrackingError.permissionDenied
        }

        // Handle active entries differently
        if timeEntry.status == "clocked-in" {
            let validation = TimeEntryValidator.canEditActiveClockIn(timeEntry, newClockInTime: startTime)
            if !validation.isValid {
                throw TimeTrackingError.validationFailed(validation.error ?? "Invalid clock-in time")
            }

            struct UpdateData: Encodable {
                let start_time: Date
                let notes: String?
            }

            let updateData = UpdateData(
                start_time: startTime,
                notes: notes
            )

            try await supabase
                .from("time_entries")
                .update(updateData)
                .eq("id", value: entryId)
                .execute()

            // Update local copy
            if let currentEntry = currentTimeEntry, currentEntry.id == entryId {
                await checkCurrentStatus()
            }
            return
        }

        // For completed entries
        guard let dateString = timeEntry.date else {
            throw TimeTrackingError.invalidEntry
        }

        let (isValid, validationError) = TimeEntryValidator.validateManualEntry(
            date: dateString,
            startTime: startTime,
            endTime: endTime
        )
        if !isValid {
            throw TimeTrackingError.validationFailed(validationError ?? "Invalid entry")
        }

        // Validate notes
        let (notesValid, notesError) = TimeEntryValidator.validateNotes(notes)
        if !notesValid {
            throw TimeTrackingError.validationFailed(notesError ?? "Invalid notes")
        }

        // Check for overlaps (excluding current entry)
        let (hasOverlap, overlapCount) = try await checkTimeOverlap(
            startTime: startTime,
            endTime: endTime,
            excludeEntryId: entryId
        )
        if hasOverlap {
            throw TimeTrackingError.overlappingEntry(count: overlapCount)
        }

        // Calculate total hours
        let totalHours = endTime.timeIntervalSince(startTime) / 3600.0

        // Update the time entry
        struct UpdateData: Encodable {
            let start_time: Date
            let end_time: Date
            let total_hours: Double
            let session_id: String?
            let notes: String?
        }

        let updateData = UpdateData(
            start_time: startTime,
            end_time: endTime,
            total_hours: totalHours,
            session_id: sessionId,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        try await supabase
            .from("time_entries")
            .update(updateData)
            .eq("id", value: entryId)
            .execute()
    }

    func deleteTimeEntry(entryId: String) async throws {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            throw TimeTrackingError.userNotAuthenticated
        }

        // Get existing entry
        let entries: [TimeEntry] = try await supabase
            .from("time_entries")
            .select()
            .eq("id", value: entryId)
            .limit(1)
            .execute()
            .value

        guard let timeEntry = entries.first else {
            throw TimeTrackingError.entryNotFound
        }

        // Check permissions
        if !TimeEntryValidator.canEditEntry(timeEntry) {
            throw TimeTrackingError.editWindowExpired
        }

        if timeEntry.user_id != userId || timeEntry.organization_id != orgId {
            throw TimeTrackingError.permissionDenied
        }

        // Delete the entry
        try await supabase
            .from("time_entries")
            .delete()
            .eq("id", value: entryId)
            .execute()
    }

    func getSessionsForDate(_ date: Date) async throws -> [Session] {
        guard let orgId = currentOrgId else {
            return []
        }

        let dateString = date.toYYYYMMDD()

        let allSessions = try await SessionService.shared.fetchSessions(
            organizationID: orgId,
            includeUnpublished: false
        )

        return allSessions.filter { session in
            session.date == dateString
        }
    }

    // MARK: - Overlap Detection

    func checkTimeOverlap(
        startTime: Date,
        endTime: Date,
        excludeEntryId: String? = nil
    ) async throws -> (hasOverlap: Bool, count: Int) {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            return (false, 0)
        }

        let dateString = startTime.toYYYYMMDD()

        let entries: [TimeEntry] = try await supabase
            .from("time_entries")
            .select()
            .eq("user_id", value: userId)
            .eq("organization_id", value: orgId)
            .eq("date", value: dateString)
            .execute()
            .value

        var overlapCount = 0
        for entry in entries {
            // Skip the entry being edited
            if let excludeId = excludeEntryId, entry.id == excludeId {
                continue
            }

            // Skip entries without proper times
            guard let entryStart = entry.start_time,
                  let entryEnd = entry.end_time else {
                continue
            }

            // Check for overlap
            if startTime < entryEnd && endTime > entryStart {
                overlapCount += 1
            }
        }

        return (overlapCount > 0, overlapCount)
    }
}

// MARK: - TimeTrackingError

enum TimeTrackingError: LocalizedError {
    case userNotAuthenticated
    case alreadyClockedIn
    case noActiveEntry
    case invalidEntry
    case entryNotFound
    case editWindowExpired
    case permissionDenied
    case validationFailed(String)
    case overlappingEntry(count: Int)

    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "User not authenticated"
        case .alreadyClockedIn:
            return "You already have an active time entry. Please clock out first."
        case .noActiveEntry:
            return "No active time entry found. Please clock in first."
        case .invalidEntry:
            return "Invalid time entry data"
        case .entryNotFound:
            return "Time entry not found"
        case .editWindowExpired:
            return "This time entry cannot be edited (outside the 30-day edit window)"
        case .permissionDenied:
            return "You don't have permission to modify this time entry"
        case .validationFailed(let message):
            return message
        case .overlappingEntry(let count):
            return "This time entry overlaps with \(count) existing entries. Please choose different times."
        }
    }
}
