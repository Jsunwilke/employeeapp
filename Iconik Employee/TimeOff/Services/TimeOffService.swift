import Foundation
import Supabase

@MainActor
class TimeOffService: ObservableObject {
    static let shared = TimeOffService()
    private let supabase = SupabaseManager.shared.client

    @Published var timeOffRequests: [TimeOffRequest] = []
    @Published var myRequests: [TimeOffRequest] = []
    @Published var pendingRequests: [TimeOffRequest] = []
    @Published var isLoading = false
    /// TRUE ONLY WHILE THE LIST IS BEING FETCHED, and deliberately separate from
    /// `isLoading`.
    ///
    /// `isLoading` is a single flag written by SEVEN operations — the fetch plus
    /// create, update, cancel, approve, deny and put-in-review. Routing the fetch
    /// through it too means a completing fetch clears the flag out from under an
    /// in-flight approve, and an approve's own clear ends a fetch's spinner. That
    /// is benign for today's readers only because both gate on the list being
    /// empty, which is luck rather than design — and shared mutable state that
    /// happens not to bite yet is precisely the shape this feature has been bitten
    /// by twice already.
    @Published var isFetchingList = false
    @Published var errorMessage = ""

    private var requestsChannel: RealtimeChannelV2?
    private var currentUserId: String?
    private var currentOrgId: String?

    // Cache management
    private var lastCacheUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    // Track if we have an active listener to prevent duplicates
    private var hasActiveListener = false

    private init() {
        Task {
            await setupUser()
        }
    }

    deinit {
        Task { [weak requestsChannel] in
            await requestsChannel?.unsubscribe()
        }
    }

    private func setupUser() async {
        do {
            let session = try await supabase.auth.session
            self.currentUserId = session.user.id.uuidString.lowercased()
            self.currentOrgId = UserDefaults.standard.string(forKey: "userOrganizationID")
        } catch {
            print("⚠️ TimeOffService: No active session")
        }
    }

    // MARK: - Identity Resolution

    /// The singleton may be created before sign-in completes (e.g. the app backgrounds
    /// during signup), leaving the init-time snapshot nil for the rest of the app run.
    /// Always re-check the live session instead of trusting the cached value.
    private func resolveUserId() async throws -> String {
        if currentUserId == nil {
            currentUserId = (try? await supabase.auth.session)?.user.id.uuidString.lowercased()
        }
        guard let userId = currentUserId else {
            throw NSError(domain: "TimeOffService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        return userId
    }

    private func resolveIdentity() async throws -> (userId: String, orgId: String) {
        let userId = try await resolveUserId()
        if currentOrgId == nil || currentOrgId?.isEmpty == true {
            currentOrgId = UserDefaults.standard.string(forKey: "userOrganizationID")
        }
        guard let orgId = currentOrgId, !orgId.isEmpty else {
            throw NSError(domain: "TimeOffService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Organization not found — please sign out and back in"])
        }
        return (userId, orgId)
    }

    // MARK: - Real-time Listeners

    func startListeningToRequests() async {
        // Refresh the user ID in case the singleton was created before sign-in,
        // otherwise updateFilteredLists() leaves myRequests empty
        // SET BEFORE THE FIRST AWAIT. Placed after `resolveUserId()` it left the
        // empty state showing for the whole of a cold-start session lookup, which
        // is the exact lie the flag exists to prevent.
        isFetchingList = true
        defer { isFetchingList = false }

        _ = try? await resolveUserId()

        // Try currentOrgId first, fall back to UserDefaults if not set yet
        let orgId: String
        if let cachedOrgId = currentOrgId, !cachedOrgId.isEmpty {
            orgId = cachedOrgId
        } else if let storedOrgId = UserDefaults.standard.string(forKey: "userOrganizationID"), !storedOrgId.isEmpty {
            orgId = storedOrgId
            self.currentOrgId = storedOrgId
        } else {
            errorMessage = "Organization ID not found"
            return
        }

        // AMB.8: the fetch below never touched `isLoading`, so every screen's
        // "loading" branch was unreachable and the EMPTY state rendered during the
        // initial network load — "You haven't submitted any time off requests yet"
        // with a Create CTA, and "All Caught Up!" on a manager's queue, both while
        // the request was still in flight. Same family as the failure-that-looks-
        // like-emptiness this phase exists to remove.
        // Check if we already have an active listener
        if hasActiveListener {
            print("📅 TimeOffService: Reusing existing listener")
            // If we have cached data and it's still valid, use it
            if let lastUpdate = lastCacheUpdate,
               Date().timeIntervalSince(lastUpdate) < cacheValidityDuration,
               !timeOffRequests.isEmpty {
                errorMessage = ""
                updateFilteredLists()
                return
            }
            // Cache is empty or stale - fetch fresh data even with active listener
            do {
                let response: [TimeOffRequest] = try await supabase.database
                    .from("time_off_requests")
                    .select()
                    .eq("organization_id", value: orgId)
                    .order("created_at", ascending: false)
                    .execute()
                    .value

                self.timeOffRequests = response
                self.lastCacheUpdate = Date()
                // AMB.8: errorMessage was only ever SET, never cleared — nothing
                // in this file assigned "" anywhere. That was invisible while no
                // view read it. Now that the screens DISPLAY it, a single failure
                // would pin an orange banner for the rest of the app session and
                // suppress the empty state behind it, which is the same class of
                // defect the conversion exists to remove. Cleared on success.
                errorMessage = ""
                updateFilteredLists()
            } catch {
                print("❌ TimeOffService refresh error: \(error)")
                errorMessage = "Error loading requests: \(error.localizedDescription)"
            }
            return
        }

        // Clean up any existing channel
        await requestsChannel?.unsubscribe()
        hasActiveListener = true

        // Set up real-time channel using realtimeV2
        let channelKey = "timeoff-\(orgId)"
        let channel = supabase.realtimeV2.channel(channelKey)

        // Set up postgres change listener
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "time_off_requests",
            filter: "organization_id=eq.\(orgId)"
        )

        // Subscribe to the channel
        await channel.subscribe()
        self.requestsChannel = channel

        // Initial fetch
        do {
            let response: [TimeOffRequest] = try await supabase.database
                .from("time_off_requests")
                .select()
                .eq("organization_id", value: orgId)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.timeOffRequests = response
            self.lastCacheUpdate = Date()
            errorMessage = ""
            updateFilteredLists()

        } catch {
            errorMessage = "Error loading requests: \(error.localizedDescription)"
            print("❌ TimeOffService: \(error)")
        }

        // Listen for changes using async sequence
        Task { [weak self] in
            for await _ in changes {
                guard let self = self else { return }
                await self.handleRealtimeChange()
            }
        }
    }

    private func handleRealtimeChange() async {
        do {
            // Re-fetch all requests to ensure data consistency
            guard let orgId = currentOrgId else { return }

            let response: [TimeOffRequest] = try await supabase.database
                .from("time_off_requests")
                .select()
                .eq("organization_id", value: orgId)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.timeOffRequests = response
            self.lastCacheUpdate = Date()
            // THE FOURTH SUCCESS PATH, and the one that runs most often. The fix
            // round cleared the other three and left this one, so a colleague's
            // approval could refresh the list successfully while the stale failure
            // banner stayed over fresh data.
            errorMessage = ""
            updateFilteredLists()

        } catch {
            print("❌ TimeOffService realtime update error: \(error)")
        }
    }

    private func updateFilteredLists() {
        guard let userId = currentUserId else { return }

        // Filter my requests
        myRequests = timeOffRequests.filter { $0.photographer_id == userId }

        // Filter pending requests for managers
        pendingRequests = timeOffRequests.filter { $0.status == "pending" }
    }

    func stopListening() async {
        await requestsChannel?.unsubscribe()
        requestsChannel = nil
        hasActiveListener = false
    }

    // MARK: - Create Request

    func createTimeOffRequest(
        startDate: Date,
        endDate: Date,
        reason: TimeOffReason,
        notes: String,
        isPartialDay: Bool,
        startTime: String? = nil,
        endTime: String? = nil,
        isPaidTimeOff: Bool = false,
        ptoHoursRequested: Double? = nil,
        projectedPTOBalance: Double? = nil
    ) async throws {
        let (userId, orgId) = try await resolveIdentity()

        // Get user info
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let email = UserDefaults.standard.string(forKey: "userEmail") ?? ""

        let photographerName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)

        // Prepare insert data matching database schema
        struct InsertData: Encodable {
            let id: String
            let organization_id: String
            let photographer_id: String
            let photographer_name: String
            let photographer_email: String
            let start_date: Date
            let end_date: Date
            let reason: String
            let type: String?
            let notes: String
            let status: String
            let is_partial_day: Bool?
            let start_time: String?
            let end_time: String?
            let is_paid_time_off: Bool?
            let pto_hours_requested: Double?
            let projected_pto_balance: Double?
        }

        let insertData = InsertData(
            id: UUID().uuidString,
            organization_id: orgId,
            photographer_id: userId,
            photographer_name: photographerName,
            photographer_email: email,
            start_date: startDate,
            end_date: endDate,
            reason: reason.rawValue,
            type: nil, // Database has this field, but not using it yet
            notes: notes,
            status: "pending",
            is_partial_day: isPartialDay ? true : nil,
            start_time: isPartialDay ? startTime : nil,
            end_time: isPartialDay ? endTime : nil,
            is_paid_time_off: isPaidTimeOff ? true : nil,
            pto_hours_requested: isPaidTimeOff ? ptoHoursRequested : nil,
            projected_pto_balance: isPaidTimeOff ? projectedPTOBalance : nil
        )

        isLoading = true

        do {
            // Insert the request
            try await supabase.database
                .from("time_off_requests")
                .insert(insertData)
                .execute()

            // If using PTO, reserve the hours
            if isPaidTimeOff, let ptoHours = ptoHoursRequested {
                do {
                    try await PTOService.shared.reservePTOHours(
                        userId: userId,
                        organizationID: orgId,
                        hours: ptoHours
                    )
                } catch {
                    print("⚠️ Warning: Failed to reserve PTO hours: \(error.localizedDescription)")
                }
            }

            isLoading = false

        } catch {
            isLoading = false
            throw NSError(domain: "TimeOffService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error creating request: \(error.localizedDescription)"])
        }
    }

    // MARK: - Update Request

    func updateTimeOffRequest(
        requestId: String,
        startDate: Date,
        endDate: Date,
        reason: TimeOffReason,
        notes: String,
        isPartialDay: Bool,
        startTime: String? = nil,
        endTime: String? = nil,
        isPaidTimeOff: Bool = false,
        ptoHoursRequested: Double? = nil,
        projectedPTOBalance: Double? = nil
    ) async throws {
        let userId = try await resolveUserId()

        // Find the existing request
        guard let existingRequest = timeOffRequests.first(where: { $0.id == requestId }) else {
            throw NSError(domain: "TimeOffService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Request not found"])
        }

        // Check permissions
        if existingRequest.photographer_id != userId {
            throw NSError(domain: "TimeOffService", code: 403, userInfo: [NSLocalizedDescriptionKey: "You can only edit your own requests"])
        }

        if existingRequest.status != "pending" && existingRequest.status != "underReview" {
            throw NSError(domain: "TimeOffService", code: 403, userInfo: [NSLocalizedDescriptionKey: "You can only edit pending or under review requests"])
        }

        isLoading = true

        // Prepare update data matching database schema
        struct UpdateData: Encodable {
            let start_date: Date
            let end_date: Date
            let reason: String
            let notes: String
            let is_partial_day: Bool?
            let start_time: String?
            let end_time: String?
            let is_paid_time_off: Bool?
            let pto_hours_requested: Double?
            let projected_pto_balance: Double?
            let updated_at: Date
        }

        let updateData = UpdateData(
            start_date: startDate,
            end_date: endDate,
            reason: reason.rawValue,
            notes: notes,
            is_partial_day: isPartialDay ? true : nil,
            start_time: isPartialDay ? startTime : nil,
            end_time: isPartialDay ? endTime : nil,
            is_paid_time_off: isPaidTimeOff ? true : nil,
            pto_hours_requested: isPaidTimeOff ? ptoHoursRequested : nil,
            projected_pto_balance: isPaidTimeOff ? projectedPTOBalance : nil,
            updated_at: Date()
        )

        do {
            try await supabase.database
                .from("time_off_requests")
                .update(updateData)
                .eq("id", value: requestId)
                .execute()

            isLoading = false

        } catch {
            isLoading = false
            throw NSError(domain: "TimeOffService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error updating request: \(error.localizedDescription)"])
        }
    }

    // MARK: - Cancel Request

    func cancelTimeOffRequest(requestId: String) async throws {
        let (userId, orgId) = try await resolveIdentity()

        // Find the existing request
        guard let existingRequest = timeOffRequests.first(where: { $0.id == requestId }) else {
            throw NSError(domain: "TimeOffService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Request not found"])
        }

        // Check permissions
        if existingRequest.photographer_id != userId {
            throw NSError(domain: "TimeOffService", code: 403, userInfo: [NSLocalizedDescriptionKey: "You can only cancel your own requests"])
        }

        if existingRequest.status != "pending" && existingRequest.status != "underReview" {
            throw NSError(domain: "TimeOffService", code: 403, userInfo: [NSLocalizedDescriptionKey: "You can only cancel pending or under review requests"])
        }

        isLoading = true

        struct UpdateData: Encodable {
            let status: String
            let updated_at: Date
        }

        let updateData = UpdateData(
            status: "cancelled",
            updated_at: Date()
        )

        do {
            try await supabase.database
                .from("time_off_requests")
                .update(updateData)
                .eq("id", value: requestId)
                .execute()

            // If request was using PTO, release the reserved hours
            if existingRequest.is_paid_time_off == true, let ptoHours = existingRequest.pto_hours_requested {
                do {
                    try await PTOService.shared.releasePTOHours(
                        userId: userId,
                        organizationID: orgId,
                        hours: ptoHours
                    )
                } catch {
                    print("⚠️ Warning: Failed to release PTO hours: \(error.localizedDescription)")
                }
            }

            isLoading = false

        } catch {
            isLoading = false
            throw NSError(domain: "TimeOffService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error cancelling request: \(error.localizedDescription)"])
        }
    }

    // MARK: - Manager Actions

    func approveTimeOffRequest(requestId: String) async throws {
        let userId = try await resolveUserId()

        // Find the request to check if it uses PTO
        guard let request = timeOffRequests.first(where: { $0.id == requestId }) else {
            throw NSError(domain: "TimeOffService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Request not found"])
        }

        // Get manager info
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let approverName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)

        isLoading = true

        struct UpdateData: Encodable {
            let status: String
            let approved_by: String
            let approver_name: String
            let approved_at: Date
            let updated_at: Date
        }

        let updateData = UpdateData(
            status: "approved",
            approved_by: userId,
            approver_name: approverName,
            approved_at: Date(),
            updated_at: Date()
        )

        do {
            try await supabase.database
                .from("time_off_requests")
                .update(updateData)
                .eq("id", value: requestId)
                .execute()

            // If request uses PTO, deduct the hours
            if request.is_paid_time_off == true, let ptoHours = request.pto_hours_requested {
                do {
                    try await PTOService.shared.usePTOHours(
                        userId: request.photographer_id,
                        organizationID: request.organization_id,
                        hours: ptoHours
                    )
                } catch {
                    print("⚠️ Warning: Failed to deduct PTO hours: \(error.localizedDescription)")
                }
            }

            isLoading = false

        } catch {
            isLoading = false
            throw NSError(domain: "TimeOffService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error approving request: \(error.localizedDescription)"])
        }
    }

    func denyTimeOffRequest(requestId: String, denialReason: String) async throws {
        let userId = try await resolveUserId()

        if denialReason.trimmingCharacters(in: .whitespaces).isEmpty {
            throw NSError(domain: "TimeOffService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Denial reason is required"])
        }

        // Find the request to check if it uses PTO
        guard let request = timeOffRequests.first(where: { $0.id == requestId }) else {
            throw NSError(domain: "TimeOffService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Request not found"])
        }

        // Get manager info
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let denierName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)

        isLoading = true

        struct UpdateData: Encodable {
            let status: String
            let denied_by: String
            let denier_name: String
            let denied_at: Date
            let denial_reason: String
            let updated_at: Date
        }

        let updateData = UpdateData(
            status: "denied",
            denied_by: userId,
            denier_name: denierName,
            denied_at: Date(),
            denial_reason: denialReason,
            updated_at: Date()
        )

        do {
            try await supabase.database
                .from("time_off_requests")
                .update(updateData)
                .eq("id", value: requestId)
                .execute()

            // If request was using PTO, release the reserved hours
            if request.is_paid_time_off == true, let ptoHours = request.pto_hours_requested {
                do {
                    try await PTOService.shared.releasePTOHours(
                        userId: request.photographer_id,
                        organizationID: request.organization_id,
                        hours: ptoHours
                    )
                } catch {
                    print("⚠️ Warning: Failed to release PTO hours: \(error.localizedDescription)")
                }
            }

            isLoading = false

        } catch {
            isLoading = false
            throw NSError(domain: "TimeOffService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error denying request: \(error.localizedDescription)"])
        }
    }

    func putTimeOffRequestInReview(requestId: String) async throws {
        let userId = try await resolveUserId()

        // Find the request
        guard let request = timeOffRequests.first(where: { $0.id == requestId }) else {
            throw NSError(domain: "TimeOffService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Request not found"])
        }

        // Only pending requests can be put in review
        if request.status != "pending" {
            throw NSError(domain: "TimeOffService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Only pending requests can be put in review"])
        }

        // Get reviewer info
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let reviewerName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)

        isLoading = true

        struct UpdateData: Encodable {
            let status: String
            let reviewed_by: String
            let reviewer_name: String
            let reviewed_at: Date
            let updated_at: Date
        }

        let updateData = UpdateData(
            status: "underReview",
            reviewed_by: userId,
            reviewer_name: reviewerName,
            reviewed_at: Date(),
            updated_at: Date()
        )

        do {
            try await supabase.database
                .from("time_off_requests")
                .update(updateData)
                .eq("id", value: requestId)
                .execute()

            isLoading = false

        } catch {
            isLoading = false
            throw NSError(domain: "TimeOffService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Error putting request in review: \(error.localizedDescription)"])
        }
    }

    // MARK: - Conflict Detection

    func checkForConflicts(
        startDate: Date,
        endDate: Date,
        isPartialDay: Bool,
        startTime: String? = nil,
        endTime: String? = nil,
        excludeRequestId: String? = nil
    ) async -> [String] {
        guard let userId = currentUserId,
              let _ = currentOrgId else {
            return []
        }

        // Check against sessions first
        // For full day requests, check entire days
        if !isPartialDay {
            // Check each day in the range
            let conflicts: [String] = []
            let calendar = Calendar.current
            var currentDate = startDate

            while currentDate <= endDate {
                // Check if user has sessions on this date
                // This would need integration with your session checking logic
                // For now, we'll just note it as a placeholder

                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
                if currentDate > endDate { break }
            }

            return conflicts
        } else {
            // For partial day requests, check time overlaps
            // This would need more complex logic to check session times
            // For now, we'll return empty array
            return []
        }
    }

    // MARK: - Helper Methods

    func getMyRequests(status: TimeOffStatus? = nil) -> [TimeOffRequest] {
        if let status = status {
            let statusString = status.rawValue
            return myRequests.filter { $0.status == statusString }
        }
        return myRequests
    }

    func getPendingRequestsCount() -> Int {
        return pendingRequests.count
    }

    /// Forces a NETWORK fetch. The banner's Retry used to route through
    /// `startListeningToRequests`, which returns early from cache when
    /// `lastCacheUpdate` is fresh — and a realtime change refreshes that stamp. So
    /// a manager tapping Retry got `errorMessage = ""` and a return, with no
    /// request made: the banner vanished and read as a successful retry. Anything
    /// that means "the user asked for fresh data" must invalidate first.
    func refreshRequests() async {
        lastCacheUpdate = nil
        await startListeningToRequests()
    }

    // MARK: - Permission Checks

    @MainActor
    func canManageRequests() -> Bool {
        // Phase 7 RBAC — managers + admins + owners have edit on time-off approvals
        return Permissions.has("timeOffApprovals", level: .edit)
    }

    func canEditRequest(_ request: TimeOffRequest) -> Bool {
        guard let userId = currentUserId else { return false }
        return request.photographer_id == userId && (request.status == "pending" || request.status == "underReview")
    }

    func canCancelRequest(_ request: TimeOffRequest) -> Bool {
        guard let userId = currentUserId else { return false }
        return request.photographer_id == userId && (request.status == "pending" || request.status == "underReview")
    }

    // MARK: - Calendar Integration

    func getTimeOffForCalendar(dateRange: (start: Date, end: Date)) async -> [TimeOffCalendarEntry] {
        // Try currentOrgId first, fall back to UserDefaults if not set yet
        let orgId: String
        if let cachedOrgId = currentOrgId, !cachedOrgId.isEmpty {
            orgId = cachedOrgId
        } else if let storedOrgId = UserDefaults.standard.string(forKey: "userOrganizationID"), !storedOrgId.isEmpty {
            orgId = storedOrgId
            // Also update the cached value for future calls
            self.currentOrgId = storedOrgId
        } else {
            print("📅 TimeOffService: No org ID for calendar query")
            return []
        }

        // Format dates as ISO8601 for Supabase query
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let startDateStr = formatter.string(from: dateRange.start)
        let endDateStr = formatter.string(from: dateRange.end)

        print("📅 TimeOffService: Fetching time off for \(startDateStr) to \(endDateStr), org: \(orgId)")

        do {
            // Query for time off requests that overlap with the visible date range
            // Include both pending and approved requests for calendar display
            let response: [TimeOffRequest] = try await supabase.database
                .from("time_off_requests")
                .select()
                .eq("organization_id", value: orgId)
                .in("status", values: ["pending", "underReview", "approved"])
                .lte("start_date", value: endDateStr)
                .gte("end_date", value: startDateStr)
                .execute()
                .value

            print("📅 TimeOffService: Found \(response.count) time off requests for calendar")

            // Convert to calendar entries
            return convertToCalendarEntries(requests: response)

        } catch {
            print("❌ Error fetching time off for calendar: \(error)")
            return []
        }
    }

    func startListeningToCalendarTimeOff(dateRange: (start: Date, end: Date)) async -> RealtimeChannel? {
        guard let orgId = currentOrgId else {
            return nil
        }

        // If we already have an active listener, filter from the main timeOffRequests
        if hasActiveListener && !timeOffRequests.isEmpty {
            let filteredRequests = timeOffRequests.filter { request in
                (request.status == "pending" || request.status == "underReview" || request.status == "approved") &&
                request.start_date <= dateRange.end &&
                request.end_date >= dateRange.start
            }

            // Return nil since we're reusing the main listener
            return nil
        }

        // Real-time is handled by the main listener in startListeningToRequests()
        // Calendar views should call startListeningToRequests() instead
        return nil
    }

    private func convertToCalendarEntries(requests: [TimeOffRequest]) -> [TimeOffCalendarEntry] {
        var entries: [TimeOffCalendarEntry] = []
        let calendar = Calendar.current

        for request in requests {
            var currentDate = request.start_date
            let endDate = request.end_date

            // Create entries for each day in the range
            while currentDate <= endDate {
                let isPartialDay = request.is_partial_day ?? false
                let title = isPartialDay
                    ? "Time Off: \(request.reasonEnum.displayName) (\(formatTime(request.start_time)) - \(formatTime(request.end_time)))"
                    : "Time Off: \(request.reasonEnum.displayName)"

                let entry = TimeOffCalendarEntry(
                    id: "\(request.id)-\(currentDate.timeIntervalSince1970)",
                    requestId: request.id,
                    title: title,
                    date: currentDate,
                    startTime: isPartialDay ? (request.start_time ?? "09:00") : "09:00",
                    endTime: isPartialDay ? (request.end_time ?? "17:00") : "17:00",
                    photographerId: request.photographer_id,
                    photographerName: request.photographer_name ?? "",
                    status: request.statusEnum,
                    isPartialDay: isPartialDay,
                    reason: request.reasonEnum,
                    notes: request.notes ?? ""
                )

                entries.append(entry)

                // Move to next day
                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
                currentDate = nextDate

                if currentDate > endDate { break }
            }
        }

        return entries.sorted { $0.date < $1.date }
    }

    private func formatTime(_ timeString: String?) -> String {
        guard let timeString = timeString else { return "" }

        // Convert "HH:mm" to display format
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        if let date = formatter.date(from: timeString) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        return timeString
    }
}
