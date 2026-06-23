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
    @Published var isUsingOfflineData: Bool = false
    @Published var lastSyncTime: Date?

    // In-memory cache for sessions
    private var sessionsCache: [Session] = []
    private var lastCacheUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    // Persistent cache manager for offline support
    private let persistentCache = ScheduleCacheManager.shared

    // Track active Supabase realtime channels - keyed by subscription ID for per-caller tracking
    private var activeChannels: [UUID: RealtimeChannelV2] = [:]

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
        // Check in-memory cache first (skip if forceRefresh)
        if !forceRefresh,
           let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheValidityDuration,
           !sessionsCache.isEmpty {
            print("📅 SessionService: Returning \(sessionsCache.count) in-memory cached sessions")
            return sessionsCache
        }

        // If offline, try to load from persistent cache
        if !isConnected {
            return try await loadFromOfflineCache(organizationID: organizationID)
        }

        var query = supabase
            .from("sessions")
            .select("*, session_days(*)")
            .eq("organization_id", value: organizationID)

        // Filter by published status if needed
        if !includeUnpublished {
            query = query.eq("is_published", value: true)
        }

        do {
            let sessions: [Session] = try await query.execute().value
            print("📅 SessionService: Fetched \(sessions.count) sessions for org \(organizationID)")

            // Update in-memory cache
            sessionsCache = sessions
            lastCacheUpdate = Date()

            // Save to persistent cache for offline use
            await persistentCache.saveSessions(sessions, organizationId: organizationID)

            // Update sync status
            isUsingOfflineData = false
            lastSyncTime = Date()

            return sessions
        } catch {
            print("❌ SessionService fetch error: \(describeDecodingError(error))")

            // On network error, try to load from persistent cache
            if let cached = await loadFromOfflineCacheIfAvailable(organizationID: organizationID) {
                return cached
            }

            throw error
        }
    }

    /// Load sessions from offline cache
    private func loadFromOfflineCache(organizationID: String) async throws -> [Session] {
        if let cached = await persistentCache.loadSessions(organizationId: organizationID) {
            print("📱 SessionService: Using offline cache (\(cached.sessions.count) sessions)")
            sessionsCache = cached.sessions
            lastCacheUpdate = cached.lastSync
            isUsingOfflineData = true
            lastSyncTime = cached.lastSync
            return cached.sessions
        }

        throw SessionError.networkError
    }

    /// Try to load from offline cache without throwing
    private func loadFromOfflineCacheIfAvailable(organizationID: String) async -> [Session]? {
        if let cached = await persistentCache.loadSessions(organizationId: organizationID) {
            print("📱 SessionService: Falling back to offline cache after network error")
            sessionsCache = cached.sessions
            lastCacheUpdate = cached.lastSync
            isUsingOfflineData = true
            lastSyncTime = cached.lastSync
            return cached.sessions
        }
        return nil
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

        // OPTIMIZATION: Show cached data immediately, then sync fresh data in background
        // This eliminates the loading spinner for users who have cached data
        if let cached = await persistentCache.loadSessions(organizationId: organizationID) {
            print("📅 SessionService: Showing \(cached.sessions.count) cached sessions immediately")
            sessionsCache = cached.sessions
            lastCacheUpdate = cached.lastSync
            isUsingOfflineData = !isConnected  // Only mark as offline if actually offline
            lastSyncTime = cached.lastSync
            onChange(cached.sessions)
        }

        // Now fetch fresh data from network (if online)
        if isConnected {
            do {
                let sessions = try await fetchSessions(organizationID: organizationID, includeUnpublished: includeUnpublished, forceRefresh: true)
                print("📅 SessionService: Updated with \(sessions.count) fresh sessions from network")
                onChange(sessions)
            } catch {
                print("❌ Error on initial sessions fetch: \(describeDecodingError(error))")
                // Already showed cached data, so don't call onChange([]) here
                if sessionsCache.isEmpty {
                    onChange([])
                }
            }
        } else if sessionsCache.isEmpty {
            // Offline with no cache - show empty state
            print("📅 SessionService: Offline with no cached data")
            onChange([])
        }

        // Listen for changes in a separate task (matching RosterEntryService exactly)
        Task {
            for await change in changes {
                print("📡 SessionService: Received realtime event! Change: \(change)")
                do {
                    let sessions = try await self.fetchSessions(organizationID: organizationID, includeUnpublished: includeUnpublished, forceRefresh: true)
                    print("📡 SessionService: Fetched \(sessions.count) sessions after realtime update")

                    // Save to persistent cache on realtime updates
                    await self.persistentCache.saveSessions(sessions, organizationId: organizationID)

                    await MainActor.run {
                        self.isUsingOfflineData = false
                        self.lastSyncTime = Date()
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

    /// Fetch a single session by ID (with its embedded day rows)
    func fetchSession(sessionId: String) async throws -> Session? {
        let sessions: [Session] = try await supabase
            .from("sessions")
            .select("*, session_days(*)")
            .eq("id", value: sessionId)
            .limit(1)
            .execute()
            .value

        return sessions.first
    }

    /// Fetch sessions within a date range.
    /// A session's date now lives in `session_days`, so we resolve the session ids
    /// that have a day in range, then fetch those sessions with their full day rows.
    func fetchSessions(from startDate: Date, to endDate: Date, organizationID: String, includeUnpublished: Bool = false) async throws -> [Session] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let startDateStr = dateFormatter.string(from: startDate)
        let endDateStr = dateFormatter.string(from: endDate)

        let ids = try await sessionIds(from: startDateStr, to: endDateStr)
        return try await fetchSessions(ids: ids, organizationID: organizationID, includeUnpublished: includeUnpublished)
    }

    // MARK: - session_days resolution helpers
    // Wherever we used to filter the `sessions` table by its `date` column, we now
    // resolve the matching session ids from the `session_days` child table (RLS-scoped
    // to the user's org via the parent session) and fetch those sessions with their
    // embedded day rows. This keeps the app working after the legacy
    // sessions.date/start_time/end_time columns are dropped.

    private struct SessionDayIdRow: Decodable { let session_id: String }
    private struct SessionIdRow: Decodable { let id: String }

    /// Session ids that have a day on a specific date.
    private func sessionIds(onDate date: String) async throws -> [String] {
        let rows: [SessionDayIdRow] = try await supabase
            .from("session_days")
            .select("session_id")
            .eq("date", value: date)
            .execute()
            .value
        return Array(Set(rows.map { $0.session_id }))
    }

    /// Session ids that have a day within a date range (inclusive).
    private func sessionIds(from startDate: String, to endDate: String) async throws -> [String] {
        let rows: [SessionDayIdRow] = try await supabase
            .from("session_days")
            .select("session_id")
            .gte("date", value: startDate)
            .lte("date", value: endDate)
            .execute()
            .value
        return Array(Set(rows.map { $0.session_id }))
    }

    /// Fetch sessions by id, with their embedded day rows.
    private func fetchSessions(ids: [String], organizationID: String, includeUnpublished: Bool = false) async throws -> [Session] {
        guard !ids.isEmpty else { return [] }
        var query = supabase
            .from("sessions")
            .select("*, session_days(*)")
            .eq("organization_id", value: organizationID)
            .in("id", values: ids)
        if !includeUnpublished {
            query = query.eq("is_published", value: true)
        }
        return try await query.execute().value
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

        // Get existing sessions for this date (excluding time-off). The date lives in
        // session_days, so resolve ids on that date then fetch those sessions.
        let idsOnDate = try await sessionIds(onDate: date)
        let existingSessions = try await fetchSessions(ids: idsOnDate, organizationID: organizationID, includeUnpublished: true)

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

        // Create the session row. A session's date/time live in the `session_days`
        // child table (inserted below) — the legacy date/start_time/end_time columns
        // have been dropped, so the sessions row carries only shared job data.
        let sessionId = UUID().uuidString
        let nowISO = Date().ISO8601Format()
        let sessionInsert = SessionInsert(
            id: sessionId,
            organization_id: organizationID,
            school_id: formData.schoolId,
            school_name: school.value,
            session_types: formData.sessionTypes,
            custom_session_type: formData.sessionTypes.contains("other") ? formData.customSessionType : nil,
            photographers: photographers,
            notes: formData.notes.isEmpty ? nil : formData.notes,
            status: formData.status,
            session_color: sessionColor,
            is_published: true,
            is_time_off: formData.isTimeOff ? true : nil,
            photographers_needed: 1,
            posers_needed: 0,
            helpers_needed: 0,
            created_at: nowISO,
            created_by: SessionCreatedBy(
                id: currentUserID,
                name: currentUserName,
                email: currentUserEmail
            )
        )

        // Insert the session row
        try await supabase
            .from("sessions")
            .insert(sessionInsert)
            .execute()

        // Insert the single day row (the source of truth for when it happens)
        let dayInsert = SessionDayInsert(
            id: UUID().uuidString,
            session_id: sessionId,
            date: formData.date,
            start_time: formData.startTime,
            end_time: formData.endTime,
            sort_order: 0
        )
        try await supabase
            .from("session_days")
            .insert(dayInsert)
            .execute()

        // Recalculate colors for the date
        try await recalculateSessionColorsForDate(organizationID: organizationID, date: formData.date)

        print("✅ Created session: \(sessionId)")
        return sessionId
    }

    // MARK: - Update Session

    func updateSession(
        sessionId: String,
        dayId: String? = nil,
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

        // Prepare update data. date/start_time/end_time live in session_days (synced
        // below), not on the sessions row — those legacy columns are dropped.
        var updateData: [String: AnyJSON] = [
            "school_id": .string(formData.schoolId),
            "school_name": .string(school.value),
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

        // Update the sessions row (shared job data only). The date/time are
        // reconciled into session_days below.
        try await supabase
            .from("sessions")
            .update(updateData)
            .eq("id", value: sessionId)
            .execute()

        // Keep the session_days source of truth in sync. iOS edits ONE day of the
        // session — the day the user opened (`dayId`). Update THAT row, not blindly the
        // first day, which would overwrite day 1 of a multi-day session. Fall back to the
        // earliest day, and self-heal by inserting one if a legacy session has no rows.
        let targetDayId = dayId ?? existingSession.firstDay?.id
        if let targetDayId = targetDayId {
            let dayUpdate: [String: AnyJSON] = [
                "date": .string(formData.date),
                "start_time": .string(formData.startTime),
                "end_time": .string(formData.endTime),
                "updated_at": .string(Date().ISO8601Format())
            ]
            try await supabase
                .from("session_days")
                .update(dayUpdate)
                .eq("id", value: targetDayId)
                .execute()
        } else {
            let dayInsert = SessionDayInsert(
                id: UUID().uuidString,
                session_id: sessionId,
                date: formData.date,
                start_time: formData.startTime,
                end_time: formData.endTime,
                sort_order: 0
            )
            try await supabase
                .from("session_days")
                .insert(dayInsert)
                .execute()
        }

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

        // Get all sessions for this date (date lives in session_days)
        let idsOnDate = try await sessionIds(onDate: date)
        let sessions = try await fetchSessions(ids: idsOnDate, organizationID: organizationID, includeUnpublished: true)

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
        // Sessions on a date are resolved via session_days now.
        let ids = try await sessionIds(onDate: date)
        guard !ids.isEmpty else { return }
        try await supabase
            .from("sessions")
            .update([
                "is_published": AnyJSON.bool(true),
                "updated_at": AnyJSON.string(Date().ISO8601Format())
            ])
            .eq("organization_id", value: organizationID)
            .in("id", values: ids)
            .execute()

        print("✅ Published all sessions for date: \(date)")
    }

    func hasUnpublishedSessionsForDate(organizationID: String, date: String) async throws -> Bool {
        let ids = try await sessionIds(onDate: date)
        guard !ids.isEmpty else { return false }
        let rows: [SessionIdRow] = try await supabase
            .from("sessions")
            .select("id")
            .eq("organization_id", value: organizationID)
            .in("id", values: ids)
            .eq("is_published", value: false)
            .limit(1)
            .execute()
            .value

        return !rows.isEmpty
    }

    // MARK: - Utility Methods

    func clearCache() {
        sessionsCache = []
        lastCacheUpdate = nil
    }

    /// Clear both in-memory and persistent cache
    func clearAllCaches() async {
        sessionsCache = []
        lastCacheUpdate = nil
        await persistentCache.clearCache()
        isUsingOfflineData = false
        lastSyncTime = nil
    }

    /// Get formatted last sync time for display
    func getLastSyncDisplay() async -> String {
        let organizationID = UserManager.shared.getCachedOrganizationID()
        guard !organizationID.isEmpty else { return "Not synced" }
        return await persistentCache.getLastSyncDisplay(organizationId: organizationID)
    }

    /// Check if we have offline data available
    func hasOfflineData() async -> Bool {
        let organizationID = UserManager.shared.getCachedOrganizationID()
        guard !organizationID.isEmpty else { return false }
        return await persistentCache.hasCachedData(organizationId: organizationID)
    }

    @MainActor
    func userCanManageSessions() -> Bool {
        // Phase 7 RBAC — managers + admins have schedule edit
        Permissions.has("schedule", level: .edit)
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

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOffline = self?.isConnected == false
                self?.isConnected = path.status == .satisfied

                // When coming back online, clear offline flag
                // The realtime subscription will automatically sync fresh data
                if wasOffline && path.status == .satisfied {
                    self?.isUsingOfflineData = false
                    print("📡 SessionService: Network restored - realtime will sync fresh data")
                }
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

// MARK: - Insert DTOs
// Typed payloads for inserting into Supabase. Kept separate from the `Session`
// model (which carries an embedded `days` array that must NOT be sent to the
// sessions table) so encoding maps cleanly to real columns.

/// Payload for inserting a row into the `sessions` table. Shared job data only —
/// a session's date/time live in the `session_days` child table.
private struct SessionInsert: Encodable {
    let id: String
    let organization_id: String
    let school_id: String
    let school_name: String
    let session_types: [String]
    let custom_session_type: String?
    let photographers: [SessionPhotographer]
    let notes: String?
    let status: String
    let session_color: String
    let is_published: Bool
    let is_time_off: Bool?
    let photographers_needed: Int
    let posers_needed: Int
    let helpers_needed: Int
    let created_at: String
    let created_by: SessionCreatedBy
}

/// Payload for inserting a row into the `session_days` table.
private struct SessionDayInsert: Encodable {
    let id: String
    let session_id: String
    let date: String
    let start_time: String
    let end_time: String
    let sort_order: Int
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
