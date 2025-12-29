import Foundation
import Supabase

@MainActor
class TimeTrackingService: ObservableObject {
    private let supabase = SupabaseManager.shared.client

    @Published var currentTimeEntry: TimeEntry?
    @Published var isClockIn = false
    @Published var elapsedTime: TimeInterval = 0

    private var timer: Timer?
    private var currentUserId: String?
    private var currentOrgId: String?

    init() {
        setupUser()
        Task {
            await checkCurrentStatus()
        }
    }

    deinit {
        stopTimer()
    }

    func setupUser() {
        print("🔧 TimeTrackingService.setupUser called")

        // Get user ID from Supabase auth
        if let session = try? supabase.auth.session, let user = session.user {
            self.currentUserId = user.id.uuidString
            print("✅ TimeTrackingService.setupUser: userId set to \(user.id)")
        } else {
            print("❌ TimeTrackingService.setupUser: No authenticated user")
            return
        }

        // Get organization ID from UserManager
        if let orgIdString = UserDefaults.standard.string(forKey: "userOrganizationID") {
            self.currentOrgId = orgIdString
            print("✅ TimeTrackingService.setupUser: orgId set to \(orgIdString)")
        } else {
            print("⚠️ TimeTrackingService.setupUser: No organization ID found")
        }
    }

    func refreshUserAndStatus() async {
        setupUser()
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
            if let session = try await SessionService.shared.fetchSession(sessionId: UUID(uuidString: sessionId) ?? UUID()) {
                sessionName = SessionService.shared.getSessionDisplayName(for: session)
            }
        }

        // Create time entry
        struct InsertData: Encodable {
            let user_id: String
            let organization_id: String
            let start_time: Date
            let date: String
            let status: String
            let session_id: String?
            let session_name: String?
            let notes: String?
        }

        let insertData = InsertData(
            user_id: userId,
            organization_id: orgId,
            start_time: Date(),
            date: currentDate,
            status: "active",
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
    }

    func clockOut(notes: String? = nil) async throws {
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

        // Update time entry
        struct UpdateData: Encodable {
            let clock_out_time: Date
            let status: String
            let notes: String?
        }

        let updateData = UpdateData(
            clock_out_time: Date(),
            status: "clocked-out",
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        try await supabase
            .from("time_entries")
            .update(updateData)
            .eq("id", value: activeEntry.id)
            .execute()

        await checkCurrentStatus()
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

        guard let clockInTime = activeEntry.clock_in_time else {
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

        // Check if crosses midnight
        let clockInDateString = clockInTime.toYYYYMMDD()
        let clockOutDateString = clockOutDateTime.toYYYYMMDD()
        let crossMidnight = clockInDateString != clockOutDateString

        // Update time entry
        struct UpdateData: Encodable {
            let clock_out_time: Date
            let status: String
            let cross_midnight: Bool?
            let notes: String?
        }

        let updateData = UpdateData(
            clock_out_time: clockOutDateTime,
            status: "clocked-out",
            cross_midnight: crossMidnight ? true : nil,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        try await supabase
            .from("time_entries")
            .update(updateData)
            .eq("id", value: activeEntry.id)
            .execute()

        await checkCurrentStatus()
    }

    // MARK: - Status Management

    func checkCurrentStatus() async {
        guard let userId = currentUserId,
              let orgId = currentOrgId else { return }

        do {
            let activeEntry = try await getCurrentTimeEntry(userId: userId, organizationID: orgId)
            self.currentTimeEntry = activeEntry
            self.isClockIn = (activeEntry != nil)

            if activeEntry != nil {
                startTimer()
            } else {
                stopTimer()
            }
        } catch {
            print("Error checking current status: \(error)")
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
              let clockInTime = currentEntry.clock_in_time else {
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

    private func getCurrentTimeEntry(userId: UUID, organizationID: UUID) async throws -> TimeEntry? {
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

        let entries: [TimeEntry] = try await supabase
            .from("time_entries")
            .select()
            .eq("user_id", value: userId)
            .eq("organization_id", value: orgId)
            .gte("date", value: startDate)
            .lte("date", value: endDate)
            .order("date", ascending: false)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value

        return entries
    }

    func getTodayAssignedSessions() async throws -> [Session] {
        guard let userId = currentUserId,
              let orgId = currentOrgId else {
            return []
        }

        let today = Date().toYYYYMMDD()

        let allSessions = try await SessionService.shared.fetchSessions(
            organizationID: orgId,
            includeUnpublished: false
        )

        return allSessions.filter { session in
            session.date == today && session.isUserAssigned(userID: userId)
        }
    }

    // MARK: - Manual Time Entry Operations

    func createManualTimeEntry(
        date: Date,
        startTime: Date,
        endTime: Date,
        sessionId: UUID? = nil,
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

        // Create the manual time entry
        struct InsertData: Encodable {
            let user_id: UUID
            let organization_id: UUID
            let clock_in_time: Date
            let clock_out_time: Date
            let date: String
            let status: String
            let session_id: UUID?
            let session_name: String?
            let notes: String?
        }

        let insertData = InsertData(
            user_id: userId,
            organization_id: orgId,
            clock_in_time: startTime,
            clock_out_time: endTime,
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
        entryId: UUID,
        startTime: Date,
        endTime: Date,
        sessionId: UUID? = nil,
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
                let clock_in_time: Date
                let notes: String?
            }

            let updateData = UpdateData(
                clock_in_time: startTime,
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
        let dateString = timeEntry.date
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

        // Update the time entry
        struct UpdateData: Encodable {
            let clock_in_time: Date
            let clock_out_time: Date
            let session_id: UUID?
            let notes: String?
        }

        let updateData = UpdateData(
            clock_in_time: startTime,
            clock_out_time: endTime,
            session_id: sessionId,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        try await supabase
            .from("time_entries")
            .update(updateData)
            .eq("id", value: entryId)
            .execute()
    }

    func deleteTimeEntry(entryId: UUID) async throws {
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
        excludeEntryId: UUID? = nil
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
            guard let entryStart = entry.clock_in_time,
                  let entryEnd = entry.clock_out_time else {
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
