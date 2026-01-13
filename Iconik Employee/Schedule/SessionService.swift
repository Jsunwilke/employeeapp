import Foundation
import Network
import SwiftUI
import Combine
import Supabase

@MainActor
class SessionService: ObservableObject {
    // Singleton instance
    static let shared = SessionService()

    private let supabase = SupabaseManager.shared.client
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")

    // MARK: - Decoder Error Helper
    private func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing field '\(key.stringValue)' at: \(path.isEmpty ? "root" : path)"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch for \(type) at: \(path.isEmpty ? "root" : path) - \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Null value for \(type) at: \(path.isEmpty ? "root" : path)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Corrupted data at: \(path.isEmpty ? "root" : path) - \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    @Published var isConnected: Bool = true
    @Published var lastError: String?
    @Published var isRetrying: Bool = false

    // Cache for sessions
    private var sessionsCache: [Session] = []
    private var lastCacheUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    // Track active Supabase realtime channels - keyed by subscription ID for per-caller tracking
    private var activeChannels: [UUID: RealtimeChannelV2] = [:]

    // Pagination support
    private let pageSize = 50
    private var currentPage = 0
    private var hasMorePages = true

    private init() {
        setupNetworkMonitoring()
    }

    // MARK: - Session Retrieval (Async/Await Pattern)

    /// Fetch sessions for the current user's organization
    func fetchSessions(includeUnpublished: Bool = false) async throws -> [Session] {
        let cachedOrgID = UserManager.shared.getCachedOrganizationID()

        guard !cachedOrgID.isEmpty else {
            throw SessionError.permissionDenied
        }

        return try await fetchSessions(organizationID: cachedOrgID, includeUnpublished: includeUnpublished)
    }

    /// Fetch sessions for a specific organization
    /// - Parameter forceRefresh: If true, bypasses cache and fetches fresh data (used by real-time handlers)
    func fetchSessions(organizationID: String, includeUnpublished: Bool = false, forceRefresh: Bool = false) async throws -> [Session] {
        // Check cache first (skip if forceRefresh)
        if !forceRefresh,
           let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheValidityDuration,
           !sessionsCache.isEmpty {
            print("📅 SessionService: Returning \(sessionsCache.count) cached sessions")
            return sessionsCache
        }

        var query = supabase
            .from("sessions")
            .select()
            .eq("organization_id", value: organizationID)

        // Filter by published status if needed
        if !includeUnpublished {
            query = query.eq("is_published", value: true)
        }

        do {
            let sessions: [Session] = try await query.execute().value
            print("📅 SessionService: Fetched \(sessions.count) sessions for org \(organizationID)")

            // Update cache
            sessionsCache = sessions
            lastCacheUpdate = Date()

            return sessions
        } catch {
            print("❌ SessionService decode error: \(describeDecodingError(error))")
            throw error
        }
    }

    /// Start listening to sessions with Supabase Realtime
    /// Each caller should provide a unique subscriptionId to maintain their own subscription
    func startListeningToSessions(subscriptionId: UUID, organizationID: String, includeUnpublished: Bool = false, onChange: @escaping ([Session]) -> Void) {
        Task {
            await startListeningToSessionsAsync(subscriptionId: subscriptionId, organizationID: organizationID, includeUnpublished: includeUnpublished, onChange: onChange)
        }
    }

    /// Async implementation matching RosterEntryService pattern exactly
    private func startListeningToSessionsAsync(subscriptionId: UUID, organizationID: String, includeUnpublished: Bool, onChange: @escaping ([Session]) -> Void) async {
        // Unsubscribe from any existing channel with this subscription ID first
        await stopListeningToSessionsAsync(subscriptionId: subscriptionId)

        // Create unique channel name per subscription to avoid conflicts
        let channelKey = "sessions-\(organizationID)-\(subscriptionId.uuidString)"

        // Use realtimeV2 API (same as RosterEntryService which works)
        let channel = supabase.realtimeV2.channel(channelKey)

        print("📡 SessionService: Setting up postgres change listener for org: \(organizationID)")

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "sessions",
            filter: "organization_id=eq.\(organizationID)"
        )

        print("📡 SessionService: Subscribing to channel \(channelKey)...")
        await channel.subscribe()

        // Store this subscription
        activeChannels[subscriptionId] = channel
        print("📡 SessionService: Channel status after subscribe: \(channel.status)")
        print("📅 SessionService: Channel \(subscriptionId) subscribed, starting initial fetch...")

        // Initial fetch - always force refresh to get latest data when starting a new subscription
        do {
            let sessions = try await fetchSessions(organizationID: organizationID, includeUnpublished: includeUnpublished, forceRefresh: true)
            print("📅 SessionService: Calling onChange callback with \(sessions.count) sessions")
            onChange(sessions)
        } catch {
            print("❌ Error on initial sessions fetch: \(describeDecodingError(error))")
            onChange([])
        }

        // Listen for changes in a separate task (matching RosterEntryService exactly)
        Task {
            for await change in changes {
                print("📡 SessionService: Received realtime event! Change: \(change)")
                do {
                    let sessions = try await self.fetchSessions(organizationID: organizationID, includeUnpublished: includeUnpublished, forceRefresh: true)
                    print("📡 SessionService: Fetched \(sessions.count) sessions after realtime update")
                    await MainActor.run {
                        onChange(sessions)
                    }
                } catch {
                    print("❌ Error fetching sessions after realtime update: \(error)")
                }
            }
            print("📡 SessionService: Changes stream ended for \(subscriptionId)")
        }
    }

    private func stopListeningToSessionsAsync(subscriptionId: UUID) async {
        if let channel = activeChannels[subscriptionId] {
            await channel.unsubscribe()
            activeChannels.removeValue(forKey: subscriptionId)
            print("📅 SessionService: Unsubscribed channel \(subscriptionId)")
        }
    }

    /// Stop listening to sessions for a specific subscription
    func stopListeningToSessions(subscriptionId: UUID) {
        if let channel = activeChannels[subscriptionId] {
            Task {
                await channel.unsubscribe()
                activeChannels.removeValue(forKey: subscriptionId)
                print("📅 SessionService: Unsubscribed channel \(subscriptionId)")
            }
        }
    }

    /// Stop all session listeners (for cleanup)
    func stopAllListeners() {
        for (_, channel) in activeChannels {
            Task {
                await channel.unsubscribe()
            }
        }
        activeChannels.removeAll()
        print("📅 SessionService: Unsubscribed all channels")
    }

    /// Fetch a single session by ID
    func fetchSession(sessionId: String) async throws -> Session? {
        let sessions: [Session] = try await supabase
            .from("sessions")
            .select()
            .eq("id", value: sessionId)
            .limit(1)
            .execute()
            .value

        return sessions.first
    }

    /// Fetch sessions within a date range
    func fetchSessions(from startDate: Date, to endDate: Date, organizationID: String, includeUnpublished: Bool = false) async throws -> [Session] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let startDateStr = dateFormatter.string(from: startDate)
        let endDateStr = dateFormatter.string(from: endDate)

        var query = supabase
            .from("sessions")
            .select()
            .eq("organization_id", value: organizationID)
            .gte("date", value: startDateStr)
            .lte("date", value: endDateStr)

        if !includeUnpublished {
            query = query.eq("is_published", value: true)
        }

        let sessions: [Session] = try await query.execute().value
        return sessions
    }

    /// Fetch sessions for a specific week
    func getSessionsForWeek(startOfWeek: Date, organizationID: String) async throws -> [Session] {
        let endOfWeek = Calendar.current.date(byAdding: .day, value: 7, to: startOfWeek) ?? startOfWeek

        return try await fetchSessions(from: startOfWeek, to: endOfWeek, organizationID: organizationID, includeUnpublished: false)
    }

    /// Fetch sessions for a specific employee
    func fetchSessions(forEmployeeName employeeName: String, organizationID: String) async throws -> [Session] {
        // Fetch all sessions and filter client-side (Supabase doesn't support JSONB array filtering easily)
        let allSessions = try await fetchSessions(organizationID: organizationID, includeUnpublished: false)

        return allSessions.filter { session in
            session.photographers.contains { $0.name == employeeName }
        }
    }

    // MARK: - Session Validation

    func validateSessionInput(formData: SessionFormData) -> [String: String] {
        var errors: [String: String] = [:]

        // Validate school
        if formData.schoolId.isEmpty {
            errors["school"] = "Please select a school"
        }

        // Validate date
        if formData.date.isEmpty {
            errors["date"] = "Please select a date"
        }

        // Validate times
        if formData.startTime.isEmpty {
            errors["startTime"] = "Please select a start time"
        }

        if formData.endTime.isEmpty {
            errors["endTime"] = "Please select an end time"
        }

        // Validate start time is before end time
        if !formData.startTime.isEmpty && !formData.endTime.isEmpty {
            if formData.startTime >= formData.endTime {
                errors["time"] = "Start time must be before end time"
            }
        }

        // Validate session types
        if formData.sessionTypes.isEmpty {
            errors["sessionTypes"] = "Please select at least one session type"
        }

        // If "other" is selected, require custom session type
        if formData.sessionTypes.contains("other") && formData.customSessionType.isEmpty {
            errors["customSessionType"] = "Please specify a custom session type"
        }

        // Validate photographers
        if formData.photographerIds.isEmpty && !formData.isTimeOff {
            errors["photographers"] = "Please select at least one photographer"
        }

        return errors
    }

    // MARK: - Color Calculation

    func calculateSessionColor(organizationID: String, date: String, startTime: String, isTimeOff: Bool = false) async throws -> String {
        // Time-off sessions always get gray
        if isTimeOff {
            return "#666"
        }

        // Fetch organization to get color order settings
        let organizations: [Organization] = try await supabase
            .from("organizations")
            .select()
            .eq("id", value: organizationID)
            .limit(1)
            .execute()
            .value
        let organization = organizations.first

        let colorOrder = organization?.session_order_colors ?? [
            "#3b82f6", // blue
            "#10b981", // green
            "#8b5cf6", // purple
            "#f59e0b", // amber
            "#ef4444", // red
            "#06b6d4", // cyan
            "#8b5a3c", // brown
            "#6b7280"  // gray
        ]

        // Get existing sessions for this date (excluding time-off)
        let existingSessions: [Session] = try await supabase
            .from("sessions")
            .select()
            .eq("organization_id", value: organizationID)
            .eq("date", value: date)
            .execute()
            .value

        // Filter out time-off sessions and sort
        let regularSessions = existingSessions
            .filter { !($0.is_time_off ?? false) }
            .sorted { lhs, rhs in
                if lhs.start_time != rhs.start_time {
                    return lhs.start_time < rhs.start_time
                }
                return lhs.school_id < rhs.school_id
            }

        // Calculate color index for new session
        let colorIndex = regularSessions.count % colorOrder.count
        return colorOrder[colorIndex]
    }

    // MARK: - Create Session

    func createSession(
        organizationID: String,
        formData: SessionFormData,
        currentUserID: String,
        currentUserName: String,
        currentUserEmail: String,
        teamMembers: [TeamMember],
        schools: [School]
    ) async throws -> String {
        // Validate input
        let errors = validateSessionInput(formData: formData)
        guard errors.isEmpty else {
            throw SessionError.invalidInput(field: errors.keys.first ?? "unknown", message: errors.values.first ?? "Invalid input")
        }

        // Get school name
        guard let school = schools.first(where: { $0.id == formData.schoolId }) else {
            throw SessionError.invalidInput(field: "school", message: "School not found")
        }

        // Calculate session color
        let sessionColor = try await calculateSessionColor(
            organizationID: organizationID,
            date: formData.date,
            startTime: formData.startTime,
            isTimeOff: formData.isTimeOff
        )

        // Build photographers array
        let photographers = formData.photographerIds.compactMap { photographerId -> SessionPhotographer? in
            guard let member = teamMembers.first(where: { $0.id == photographerId }) else {
                return nil
            }

            let notes = formData.photographerNotes[photographerId] ?? ""

            return SessionPhotographer(
                id: member.id,
                name: member.fullName,
                email: member.email,
                notes: notes
            )
        }

        // Create the session
        let newSession = Session(
            id: UUID().uuidString,
            organization_id: organizationID,
            school_id: formData.schoolId,
            school_name: school.value,
            date: formData.date,
            start_time: formData.startTime,
            end_time: formData.endTime,
            session_types: formData.sessionTypes,
            custom_session_type: formData.sessionTypes.contains("other") ? formData.customSessionType : nil,
            photographers: photographers,
            notes: formData.notes.isEmpty ? nil : formData.notes,
            status: formData.status,
            session_color: sessionColor,
            is_published: true,
            is_time_off: formData.isTimeOff ? true : nil,
            created_at: Date(),
            created_by: SessionCreatedBy(
                id: currentUserID,
                name: currentUserName,
                email: currentUserEmail
            )
        )

        // Insert into Supabase
        try await supabase
            .from("sessions")
            .insert(newSession)
            .execute()

        // Recalculate colors for the date
        try await recalculateSessionColorsForDate(organizationID: organizationID, date: formData.date)

        print("✅ Created session: \(newSession.id)")
        return newSession.id
    }

    // MARK: - Update Session

    func updateSession(
        sessionId: String,
        formData: SessionFormData,
        teamMembers: [TeamMember],
        schools: [School]
    ) async throws {
        // Validate input
        let errors = validateSessionInput(formData: formData)
        guard errors.isEmpty else {
            throw SessionError.invalidInput(field: errors.keys.first ?? "unknown", message: errors.values.first ?? "Invalid input")
        }

        // Get existing session to check if date changed
        guard let existingSession = try await fetchSession(sessionId: sessionId) else {
            throw SessionError.notFound
        }

        // Get school name
        guard let school = schools.first(where: { $0.id == formData.schoolId }) else {
            throw SessionError.invalidInput(field: "school", message: "School not found")
        }

        // Build photographers array
        let photographers = formData.photographerIds.compactMap { photographerId -> SessionPhotographer? in
            guard let member = teamMembers.first(where: { $0.id == photographerId }) else {
                return nil
            }

            let notes = formData.photographerNotes[photographerId] ?? ""

            return SessionPhotographer(
                id: member.id,
                name: member.fullName,
                email: member.email,
                notes: notes
            )
        }

        // Prepare update data
        var updateData: [String: AnyJSON] = [
            "school_id": .string(formData.schoolId),
            "school_name": .string(school.value),
            "date": .string(formData.date),
            "start_time": .string(formData.startTime),
            "end_time": .string(formData.endTime),
            "session_types": .array(formData.sessionTypes.map { .string($0) }),
            "status": .string(formData.status),
            "updated_at": .string(Date().ISO8601Format())
        ]

        // Handle photographers
        let photographersData = try JSONEncoder().encode(photographers)
        let photographersJSON = try JSONDecoder().decode(AnyJSON.self, from: photographersData)
        updateData["photographers"] = photographersJSON

        // Handle custom session type (set to null if not "other")
        if formData.sessionTypes.contains("other") {
            updateData["custom_session_type"] = .string(formData.customSessionType)
        } else {
            updateData["custom_session_type"] = .null
        }

        // Handle notes
        if formData.notes.isEmpty {
            updateData["notes"] = .null
        } else {
            updateData["notes"] = .string(formData.notes)
        }

        // Update in Supabase
        try await supabase
            .from("sessions")
            .update(updateData)
            .eq("id", value: sessionId)
            .execute()

        // Recalculate colors if date changed
        if existingSession.date != formData.date {
            try await recalculateSessionColorsForDate(organizationID: existingSession.organization_id, date: existingSession.date)
            try await recalculateSessionColorsForDate(organizationID: existingSession.organization_id, date: formData.date)
        } else {
            try await recalculateSessionColorsForDate(organizationID: existingSession.organization_id, date: formData.date)
        }

        print("✅ Updated session: \(sessionId)")
    }

    // MARK: - Color Recalculation

    private func recalculateSessionColorsForDate(organizationID: String, date: String, organization: Organization? = nil) async throws {
        // Fetch organization if not provided
        let org: Organization?
        if let providedOrg = organization {
            org = providedOrg
        } else {
            let orgs: [Organization] = try await supabase
                .from("organizations")
                .select()
                .eq("id", value: organizationID)
                .limit(1)
                .execute()
                .value
            org = orgs.first
        }

        let colorOrder = org?.session_order_colors ?? [
            "#3b82f6", "#10b981", "#8b5cf6", "#f59e0b",
            "#ef4444", "#06b6d4", "#8b5a3c", "#6b7280"
        ]

        // Get all sessions for this date
        let sessions: [Session] = try await supabase
            .from("sessions")
            .select()
            .eq("organization_id", value: organizationID)
            .eq("date", value: date)
            .execute()
            .value

        // Separate time-off and regular sessions
        let timeOffSessions = sessions.filter { $0.is_time_off ?? false }
        let regularSessions = sessions
            .filter { !($0.is_time_off ?? false) }
            .sorted { lhs, rhs in
                if lhs.start_time != rhs.start_time {
                    return lhs.start_time < rhs.start_time
                }
                return lhs.school_id < rhs.school_id
            }

        // Update regular sessions with colors
        for (index, session) in regularSessions.enumerated() {
            let colorIndex = index % colorOrder.count
            let newColor = colorOrder[colorIndex]

            if session.session_color != newColor {
                try await supabase
                    .from("sessions")
                    .update(["session_color": AnyJSON.string(newColor)])
                    .eq("id", value: session.id)
                    .execute()
            }
        }

        // Update time-off sessions to gray
        for session in timeOffSessions {
            if session.session_color != "#666" {
                try await supabase
                    .from("sessions")
                    .update(["session_color": AnyJSON.string("#666")])
                    .eq("id", value: session.id)
                    .execute()
            }
        }

        print("✅ Recalculated colors for \(sessions.count) sessions on \(date)")
    }

    // MARK: - Delete Session

    func deleteSession(id: String) async throws {
        // Get session to know which date to recalculate
        guard let session = try await fetchSession(sessionId: id) else {
            throw SessionError.notFound
        }

        // Delete from Supabase
        try await supabase
            .from("sessions")
            .delete()
            .eq("id", value: id)
            .execute()

        // Recalculate colors for the date
        try await recalculateSessionColorsForDate(organizationID: session.organization_id, date: session.date)

        print("✅ Deleted session: \(id)")
    }

    // MARK: - Publishing

    func publishSession(sessionId: String) async throws {
        try await supabase
            .from("sessions")
            .update([
                "is_published": AnyJSON.bool(true),
                "updated_at": AnyJSON.string(Date().ISO8601Format())
            ])
            .eq("id", value: sessionId)
            .execute()

        print("✅ Published session: \(sessionId)")
    }

    func publishSessionsForDate(organizationID: String, date: String) async throws {
        try await supabase
            .from("sessions")
            .update([
                "is_published": AnyJSON.bool(true),
                "updated_at": AnyJSON.string(Date().ISO8601Format())
            ])
            .eq("organization_id", value: organizationID)
            .eq("date", value: date)
            .execute()

        print("✅ Published all sessions for date: \(date)")
    }

    func hasUnpublishedSessionsForDate(organizationID: String, date: String) async throws -> Bool {
        let sessions: [Session] = try await supabase
            .from("sessions")
            .select()
            .eq("organization_id", value: organizationID)
            .eq("date", value: date)
            .eq("is_published", value: false)
            .limit(1)
            .execute()
            .value

        return !sessions.isEmpty
    }

    // MARK: - Utility Methods

    func clearCache() {
        sessionsCache = []
        lastCacheUpdate = nil
    }

    func userCanManageSessions() -> Bool {
        let userRole = UserDefaults.standard.string(forKey: "userRole") ?? "employee"
        return userRole == "admin" || userRole == "manager"
    }

    func getConnectionStatus() -> (isConnected: Bool, lastError: String?, isRetrying: Bool) {
        return (isConnected, lastError, isRetrying)
    }

    func filterSessions(_ sessions: [Session], forEmployee employeeName: String) -> [Session] {
        return sessions.filter { session in
            session.photographers.contains { $0.name == employeeName }
        }
    }

    func sortSessionsByDate(_ sessions: [Session]) -> [Session] {
        return sessions.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.start_time < rhs.start_time
        }
    }

    func getSessionsForDay(_ sessions: [Session], date: Date) -> [Session] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)

        return sessions.filter { $0.date == dateStr }
    }

    func hasSessions(_ sessions: [Session], on date: Date) -> Bool {
        return !getSessionsForDay(sessions, date: date).isEmpty
    }

    func getSessionDisplayName(for session: Session) -> String {
        return session.getSessionTypeDisplayName()
    }

    // MARK: - Pagination

    func loadSessionsPage(organizationID: String) async throws -> ([Session], Bool) {
        let offset = currentPage * pageSize

        let sessions: [Session] = try await supabase
            .from("sessions")
            .select()
            .eq("organization_id", value: organizationID)
            .order("date", ascending: false)
            .order("start_time", ascending: false)
            .range(from: offset, to: offset + pageSize - 1)
            .execute()
            .value

        hasMorePages = sessions.count == pageSize
        currentPage += 1

        return (sessions, hasMorePages)
    }

    func resetPagination() {
        currentPage = 0
        hasMorePages = true
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func handleError(_ error: Error, operation: String) {
        print("❌ SessionService error during \(operation): \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.lastError = error.localizedDescription
        }
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - Session Errors
enum SessionError: LocalizedError {
    case notFound
    case invalidInput(field: String, message: String)
    case permissionDenied
    case networkError

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Session not found"
        case .invalidInput(let field, let message):
            return "\(field): \(message)"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .networkError:
            return "Network error. Please check your connection"
        }
    }
}
