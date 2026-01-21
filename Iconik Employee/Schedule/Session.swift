import Foundation

// MARK: - Session Photographer Model
struct SessionPhotographer: Codable, Hashable {
    let id: String
    let name: String
    let email: String?  // Can be NULL in database
    let notes: String?  // Can be NULL in database
}

// MARK: - Created By Info Model
struct SessionCreatedBy: Codable, Hashable {
    let id: String
    let name: String
    let email: String
}

// MARK: - Session Model (Supabase)
struct Session: Identifiable, Codable, Equatable, Hashable {
    // MARK: - Snake_case Properties (from Supabase database)
    let id: String
    let organization_id: String
    let school_id: String
    let school_name: String
    let date: String  // Format: YYYY-MM-DD
    let start_time: String  // Format: HH:MM
    let end_time: String  // Format: HH:MM
    let session_types: [String]  // JSONB array
    let custom_session_type: String?
    let photographers: [SessionPhotographer]  // JSONB array
    let notes: String?
    let status: String
    let session_color: String?  // Hex color string - can be NULL in database
    let is_published: Bool
    let is_time_off: Bool?
    let has_class_group_job: Bool?
    let has_class_candids: Bool?
    let has_sports_job: Bool?
    let photographers_needed: Int
    let posers_needed: Int
    let helpers_needed: Int
    let created_at: Date
    let updated_at: Date?
    let created_by: SessionCreatedBy?

    // MARK: - Backward Compatibility Computed Properties (camelCase)
    var organizationID: String { organization_id }
    var schoolId: String { school_id }
    var schoolName: String { school_name }
    var startTime: String { start_time }
    var endTime: String { end_time }
    var sessionType: [String] { session_types }
    var customSessionType: String? { custom_session_type }
    var sessionColor: String { session_color ?? "#3b82f6" }  // Default blue if NULL
    var isPublished: Bool { is_published }
    var isTimeOff: Bool { is_time_off ?? false }
    var hasClassGroupJob: Bool { has_class_group_job ?? false }
    var hasClassCandids: Bool { has_class_candids ?? false }
    var hasSportsJob: Bool { has_sports_job ?? false }
    var photographersNeeded: Int { photographers_needed }
    var posersNeeded: Int { posers_needed }
    var helpersNeeded: Int { helpers_needed }
    var createdAt: Date { created_at }
    var updatedAt: Date? { updated_at }
    var createdBy: SessionCreatedBy? { created_by }

    // MARK: - Computed Display Properties
    var employeeName: String {
        photographers.first?.name ?? ""
    }

    var position: String {
        // If it's an "other" type with custom session type, use that
        if session_types.contains("other"), let custom = custom_session_type, !custom.isEmpty {
            return custom
        }
        // Otherwise use first session type or default to "Photographer"
        return session_types.first ?? "Photographer"
    }

    var description: String? {
        // Use notes if available, otherwise fall back to position
        if let notes = notes, !notes.isEmpty {
            return notes
        }
        return position
    }

    var location: String? {
        // Location might be fetched from school data - returning nil for now
        return nil
    }

    var startDate: Date? {
        Self.parseDateTime(date: date, time: start_time)
    }

    var endDate: Date? {
        Self.parseDateTime(date: date, time: end_time)
    }

    // MARK: - Initializers

    // Default Codable initializer works automatically for Supabase

    /// Manual initializer for creating new sessions
    init(
        id: String = UUID().uuidString,
        organization_id: String,
        school_id: String,
        school_name: String,
        date: String,
        start_time: String,
        end_time: String,
        session_types: [String],
        custom_session_type: String? = nil,
        photographers: [SessionPhotographer],
        notes: String? = nil,
        status: String = "scheduled",
        session_color: String? = "#3b82f6",
        is_published: Bool = true,
        is_time_off: Bool? = nil,
        has_class_group_job: Bool? = nil,
        has_class_candids: Bool? = nil,
        has_sports_job: Bool? = nil,
        photographers_needed: Int = 1,
        posers_needed: Int = 0,
        helpers_needed: Int = 0,
        created_at: Date = Date(),
        updated_at: Date? = nil,
        created_by: SessionCreatedBy? = nil
    ) {
        self.id = id
        self.organization_id = organization_id
        self.school_id = school_id
        self.school_name = school_name
        self.date = date
        self.start_time = start_time
        self.end_time = end_time
        self.session_types = session_types
        self.custom_session_type = custom_session_type
        self.photographers = photographers
        self.notes = notes
        self.status = status
        self.session_color = session_color
        self.is_published = is_published
        self.is_time_off = is_time_off
        self.has_class_group_job = has_class_group_job
        self.has_class_candids = has_class_candids
        self.has_sports_job = has_sports_job
        self.photographers_needed = photographers_needed
        self.posers_needed = posers_needed
        self.helpers_needed = helpers_needed
        self.created_at = created_at
        self.updated_at = updated_at
        self.created_by = created_by
    }

    // MARK: - Helper Methods

    /// Parse date + time strings into Date object
    static func parseDateTime(date: String, time: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone.current

        let dateTimeString = "\(date) \(time)"
        return dateFormatter.date(from: dateTimeString)
    }

    /// Get the display name for the session type (handles "other" with custom type)
    func getSessionTypeDisplayName() -> String {
        if session_types.contains("other"), let custom = custom_session_type, !custom.isEmpty {
            return custom
        }
        return position
    }

    /// Check if a user ID is assigned as a photographer for this session
    func isUserAssigned(userID: String, userEmail: String? = nil) -> Bool {
        // Primary: Match by Supabase UUID (case-insensitive since UUIDs can vary in case)
        let userIDLower = userID.lowercased()
        if photographers.contains(where: { $0.id.lowercased() == userIDLower }) {
            return true
        }

        // Fallback: Match by email (for legacy data or transition period)
        if let email = userEmail {
            return photographers.contains {
                $0.email?.lowercased() == email.lowercased()
            }
        }

        return false
    }

    /// Get all photographer IDs for this session
    func getPhotographerIDs() -> [String] {
        photographers.map { $0.id }
    }

    /// Get all photographer names for this session
    func getPhotographerNames() -> [String] {
        photographers.map { $0.name }
    }

    /// Get photographer info (name and notes) for a specific user ID
    func getPhotographerInfo(for userID: String) -> (name: String, notes: String?)? {
        guard let photographer = photographers.first(where: { $0.id == userID }) else {
            return nil
        }
        return (name: photographer.name, notes: photographer.notes)
    }

    // MARK: - Equatable
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id &&
        lhs.organization_id == rhs.organization_id &&
        lhs.school_id == rhs.school_id &&
        lhs.school_name == rhs.school_name &&
        lhs.date == rhs.date &&
        lhs.start_time == rhs.start_time &&
        lhs.end_time == rhs.end_time &&
        lhs.is_published == rhs.is_published &&
        lhs.session_color == rhs.session_color
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(organization_id)
        hasher.combine(school_id)
        hasher.combine(school_name)
        hasher.combine(date)
        hasher.combine(start_time)
        hasher.combine(end_time)
        hasher.combine(is_published)
        hasher.combine(session_color)
    }
}

// MARK: - Custom Codable Extension for Date Handling
extension Session {
    enum CodingKeys: String, CodingKey {
        case id, organization_id, school_id, school_name, date, start_time, end_time
        case session_types, custom_session_type, photographers, notes, status
        case session_color, is_published, is_time_off
        case has_class_group_job, has_class_candids, has_sports_job
        case photographers_needed, posers_needed, helpers_needed
        case created_at, updated_at, created_by
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        organization_id = try container.decode(String.self, forKey: .organization_id)
        school_id = try container.decode(String.self, forKey: .school_id)
        school_name = try container.decode(String.self, forKey: .school_name)
        date = try container.decode(String.self, forKey: .date)
        start_time = try container.decode(String.self, forKey: .start_time)
        end_time = try container.decode(String.self, forKey: .end_time)
        session_types = try container.decode([String].self, forKey: .session_types)
        custom_session_type = try container.decodeIfPresent(String.self, forKey: .custom_session_type)
        photographers = try container.decode([SessionPhotographer].self, forKey: .photographers)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        status = try container.decode(String.self, forKey: .status)
        session_color = try container.decodeIfPresent(String.self, forKey: .session_color)
        is_published = try container.decode(Bool.self, forKey: .is_published)
        is_time_off = try container.decodeIfPresent(Bool.self, forKey: .is_time_off)
        has_class_group_job = try container.decodeIfPresent(Bool.self, forKey: .has_class_group_job)
        has_class_candids = try container.decodeIfPresent(Bool.self, forKey: .has_class_candids)
        has_sports_job = try container.decodeIfPresent(Bool.self, forKey: .has_sports_job)

        // Staffing fields with defaults (photographers_needed defaults to 1, others to 0)
        photographers_needed = try container.decodeIfPresent(Int.self, forKey: .photographers_needed) ?? 1
        posers_needed = try container.decodeIfPresent(Int.self, forKey: .posers_needed) ?? 0
        helpers_needed = try container.decodeIfPresent(Int.self, forKey: .helpers_needed) ?? 0

        // Handle created_at - try Date first, then ISO8601 string
        if let dateValue = try? container.decode(Date.self, forKey: .created_at) {
            created_at = dateValue
        } else if let dateString = try? container.decode(String.self, forKey: .created_at) {
            // Parse ISO8601 string
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = isoFormatter.date(from: dateString) {
                created_at = parsed
            } else {
                isoFormatter.formatOptions = [.withInternetDateTime]
                created_at = isoFormatter.date(from: dateString) ?? Date()
            }
        } else {
            created_at = Date()  // Fallback if NULL or missing
        }

        // Handle updated_at - same pattern but optional
        if let dateValue = try? container.decodeIfPresent(Date.self, forKey: .updated_at) {
            updated_at = dateValue
        } else if let dateString = try? container.decodeIfPresent(String.self, forKey: .updated_at) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = isoFormatter.date(from: dateString) {
                updated_at = parsed
            } else {
                isoFormatter.formatOptions = [.withInternetDateTime]
                updated_at = isoFormatter.date(from: dateString)
            }
        } else {
            updated_at = nil
        }

        created_by = try container.decodeIfPresent(SessionCreatedBy.self, forKey: .created_by)
    }
}
