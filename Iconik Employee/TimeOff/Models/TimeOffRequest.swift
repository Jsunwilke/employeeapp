import Foundation

/// Time Off Request model for Supabase
struct TimeOffRequest: Identifiable, Codable {
    let id: String

    // Supabase snake_case properties (matching database)
    let organization_id: String
    let photographer_id: String
    let photographer_name: String? // Optional, added by migration
    let photographer_email: String? // Optional, added by migration
    let start_date: Date
    let end_date: Date
    let reason: String // Maps to TimeOffReason enum
    let type: String? // Database has 'type' field
    let notes: String? // Optional, added by migration
    let status: String // Maps to TimeOffStatus enum

    // Partial day support (all optional, added by migration)
    let is_partial_day: Bool?
    let start_time: String? // Format: "09:00"
    let end_time: String?   // Format: "17:00"

    // PTO fields (all optional, added by migration)
    let is_paid_time_off: Bool?
    let pto_hours_requested: Double?
    let projected_pto_balance: Double?

    // Approval fields (all optional, added by migration)
    let approved_by: String?
    let approver_name: String?
    let approved_at: Date?

    // Denial fields (all optional, added by migration)
    let denied_by: String?
    let denier_name: String?
    let denied_at: Date?
    let denial_reason: String?

    // Review fields (all optional, added by migration)
    let reviewed_by: String?
    let reviewer_name: String?
    let reviewed_at: Date?

    // Timestamps
    let created_at: Date
    let updated_at: Date

    // Backward compatibility computed properties (camelCase for iOS code)
    var organizationID: String { organization_id }
    var photographerId: String { photographer_id }
    var photographerName: String { photographer_name ?? "" }
    var photographerEmail: String { photographer_email ?? "" }
    var startDate: Date { start_date }
    var endDate: Date { end_date }
    var isPartialDay: Bool { is_partial_day ?? false }
    var startTime: String? { start_time }
    var endTime: String? { end_time }
    var isPaidTimeOff: Bool { is_paid_time_off ?? false }
    var ptoHoursRequested: Double? { pto_hours_requested }
    var projectedPTOBalance: Double? { projected_pto_balance }
    var approvedBy: String? { approved_by }
    var approverName: String? { approver_name }
    var approvedAt: Date? { approved_at }
    var deniedBy: String? { denied_by }
    var denierName: String? { denier_name }
    var deniedAt: Date? { denied_at }
    var denialReason: String? { denial_reason }
    var reviewedBy: String? { reviewed_by }
    var reviewerName: String? { reviewer_name }
    var reviewedAt: Date? { reviewed_at }
    var createdAt: Date { created_at }
    var updatedAt: Date { updated_at }

    // Parse reason string to enum
    var reasonEnum: TimeOffReason {
        TimeOffReason(rawValue: reason) ?? .other
    }

    // Parse status string to enum
    var statusEnum: TimeOffStatus {
        TimeOffStatus(rawValue: status) ?? .pending
    }

    // Coding keys for Supabase
    enum CodingKeys: String, CodingKey {
        case id
        case organization_id
        case photographer_id
        case photographer_name
        case photographer_email
        case start_date
        case end_date
        case reason
        case type
        case notes
        case status
        case is_partial_day
        case start_time
        case end_time
        case is_paid_time_off
        case pto_hours_requested
        case projected_pto_balance
        case approved_by
        case approver_name
        case approved_at
        case denied_by
        case denier_name
        case denied_at
        case denial_reason
        case reviewed_by
        case reviewer_name
        case reviewed_at
        case created_at
        case updated_at
    }
}

// MARK: - Computed Properties
extension TimeOffRequest {

    // Duration in days for full day requests
    var durationInDays: Int {
        guard is_partial_day != true else { return 0 }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: start_date, to: end_date).day ?? 0
        return days + 1 // Include both start and end dates
    }

    // Duration in hours for partial day requests
    var durationInHours: Double? {
        guard is_partial_day == true,
              let startTimeString = start_time,
              let endTimeString = end_time else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        guard let startTime = formatter.date(from: startTimeString),
              let endTime = formatter.date(from: endTimeString) else { return nil }

        let timeInterval = endTime.timeIntervalSince(startTime)
        return timeInterval / 3600 // Convert seconds to hours
    }

    // Formatted duration string for display
    var formattedDuration: String {
        if is_partial_day == true {
            if let hours = durationInHours {
                if hours == 1 {
                    return "1 hour"
                } else if hours.truncatingRemainder(dividingBy: 1) == 0 {
                    return "\(Int(hours)) hours"
                } else {
                    return String(format: "%.1f hours", hours)
                }
            } else {
                return "Invalid time range"
            }
        } else {
            let days = durationInDays
            return days == 1 ? "1 day" : "\(days) days"
        }
    }

    // Formatted date range for display
    var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        if is_partial_day == true {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short

            if let startTimeString = start_time,
               let endTimeString = end_time,
               let startTime = timeFromString(startTimeString),
               let endTime = timeFromString(endTimeString) {
                return "\(formatter.string(from: start_date)) (\(timeFormatter.string(from: startTime)) - \(timeFormatter.string(from: endTime)))"
            } else {
                return "\(formatter.string(from: start_date)) (Partial Day)"
            }
        } else {
            if Calendar.current.isDate(start_date, inSameDayAs: end_date) {
                return formatter.string(from: start_date)
            } else {
                return "\(formatter.string(from: start_date)) - \(formatter.string(from: end_date))"
            }
        }
    }

    // Helper to convert time string to Date for formatting
    private func timeFromString(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: timeString)
    }

    // Check if request can be edited
    var canBeEdited: Bool {
        return status == "pending" || status == "underReview"
    }

    // Check if request can be cancelled
    var canBeCancelled: Bool {
        return status == "pending" || status == "underReview"
    }

    // Status color for UI
    var statusColor: String {
        return statusEnum.colorName
    }
}

// MARK: - Validation
extension TimeOffRequest {

    // Validate the request data
    func validate() -> (isValid: Bool, error: String?) {
        // Check required fields
        if photographer_name?.isEmpty ?? true {
            return (false, "Photographer name is required")
        }

        // Date validation
        if is_partial_day == true {
            // Partial day must be same day
            if !Calendar.current.isDate(start_date, inSameDayAs: end_date) {
                return (false, "Partial day requests must be for the same day")
            }

            // Time validation
            guard let startTimeString = start_time,
                  let endTimeString = end_time else {
                return (false, "Start time and end time are required for partial day requests")
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"

            guard let startTime = formatter.date(from: startTimeString),
                  let endTime = formatter.date(from: endTimeString) else {
                return (false, "Invalid time format")
            }

            if endTime <= startTime {
                return (false, "End time must be after start time")
            }

            // Minimum duration check (30 minutes)
            let timeInterval = endTime.timeIntervalSince(startTime)
            if timeInterval < 1800 { // 30 minutes in seconds
                return (false, "Minimum duration is 30 minutes")
            }
        } else {
            // Full day validation
            if end_date < start_date {
                return (false, "End date must be after start date")
            }
        }

        // Start date cannot be in the past
        let calendar = Calendar.current
        if calendar.startOfDay(for: start_date) < calendar.startOfDay(for: Date()) {
            return (false, "Start date cannot be in the past")
        }

        return (true, nil)
    }
}

// MARK: - TimeOffCalendarEntry
struct TimeOffCalendarEntry: Identifiable, Codable {
    let id: String
    let requestId: String
    let title: String
    let date: Date
    let startTime: String
    let endTime: String
    let photographerId: String
    let photographerName: String
    let status: TimeOffStatus
    /// THE RAW STORED VALUE, carried alongside the collapsed enum.
    ///
    /// `status` is built from `statusEnum`, which is `TimeOffStatus(rawValue:) ??
    /// .pending` — so by the time a calendar entry exists, a web-written
    /// `partially_approved` has already become `.pending` and AMB.8's
    /// unknown-status repair cannot see it. The consequence was not cosmetic: the
    /// detail sheet offered a destructive **Cancel Request** on a request somebody
    /// had already decided. Defaults to the enum's raw value so every existing
    /// construction site is unchanged.
    var statusRaw: String = ""
    let isPartialDay: Bool
    let reason: TimeOffReason
    let notes: String

    init(
        id: String,
        requestId: String,
        title: String,
        date: Date,
        startTime: String,
        endTime: String,
        photographerId: String,
        photographerName: String,
        status: TimeOffStatus,
        statusRaw: String = "",
        isPartialDay: Bool,
        reason: TimeOffReason,
        notes: String
    ) {
        self.id = id
        self.requestId = requestId
        self.title = title
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.photographerId = photographerId
        self.photographerName = photographerName
        self.status = status
        self.statusRaw = statusRaw.isEmpty ? status.rawValue : statusRaw
        self.isPartialDay = isPartialDay
        self.reason = reason
        self.notes = notes
    }
}
