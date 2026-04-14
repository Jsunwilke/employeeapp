import Foundation
import Supabase

// Helper function to parse date strings from Supabase
// Handles multiple formats: ISO8601, timestamps with space separator, and plain dates
private func parseISO8601Date(_ dateString: String?) -> Date? {
    guard let dateString = dateString else { return nil }

    // Try ISO8601 with fractional seconds (2025-12-29T22:47:23.045+00:00)
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFormatter.date(from: dateString) {
        return date
    }

    // Try ISO8601 without fractional seconds (2025-12-29T22:47:23+00:00)
    isoFormatter.formatOptions = [.withInternetDateTime]
    if let date = isoFormatter.date(from: dateString) {
        return date
    }

    // Try Supabase timestamp format with space separator (2025-12-29 22:47:23.045+00)
    let timestampFormatter = DateFormatter()
    timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
    timestampFormatter.timeZone = TimeZone(identifier: "UTC")

    // With fractional seconds and timezone
    timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXX"
    if let date = timestampFormatter.date(from: dateString) {
        return date
    }

    // With fractional seconds and short timezone (+00)
    timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXX"
    if let date = timestampFormatter.date(from: dateString) {
        return date
    }

    // Without fractional seconds
    timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ssXXX"
    if let date = timestampFormatter.date(from: dateString) {
        return date
    }

    timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ssXX"
    if let date = timestampFormatter.date(from: dateString) {
        return date
    }

    // Plain date only (2025-12-29) — shoot_date is a calendar date, not a UTC moment.
    // Use local timezone so "2026-02-25" doesn't roll back to the 24th for western timezones.
    let dateOnlyFormatter = DateFormatter()
    dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateOnlyFormatter.timeZone = TimeZone.current
    dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
    if let date = dateOnlyFormatter.date(from: dateString) {
        return date
    }

    return nil
}

// MARK: - Roster Entry Model (matches roster_entries table)
struct RosterEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var sportsJobId: UUID
    var organizationId: String    // Required for PowerSync sync rules
    var lastName: String          // Maps to "Name" in Captura
    var firstName: String         // Maps to "Subject ID" in Captura
    var teacher: String           // Maps to "Special" in Captura
    var groupName: String         // Maps to "Sport/Team" in Captura
    var email: String
    var phone: String
    var imageNumbers: String
    var notes: String
    var sortOrder: Int

    // Sync & conflict resolution
    var version: Int
    var updatedAt: Date
    var updatedBy: UUID?

    // Soft locking
    var lockedBy: UUID?
    var lockedByName: String?
    var lockedAt: Date?

    var createdAt: Date
    var isFilledBlank: Bool?  // Indicates if this is a filled blank entry
    var subjectId: String?   // FK to Production subjects (iPad sync)
    var rosterId: String     // Dedicated roster/jersey ID (replaces firstName hack)

    // CodingKeys to map snake_case database fields to camelCase Swift properties
    enum CodingKeys: String, CodingKey {
        case id, email, phone, notes, teacher, version
        case sportsJobId = "sports_job_id"
        case organizationId = "organization_id"
        case lastName = "last_name"
        case firstName = "first_name"
        case groupName = "group_name"
        case imageNumbers = "image_numbers"
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
        case lockedBy = "locked_by"
        case lockedByName = "locked_by_name"
        case lockedAt = "locked_at"
        case createdAt = "created_at"
        case isFilledBlank = "is_filled_blank"
        case subjectId = "subject_id"
        case rosterId = "roster_id"
    }

    // Custom decoder to handle missing fields with defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sportsJobId = try container.decode(UUID.self, forKey: .sportsJobId)
        organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        teacher = try container.decodeIfPresent(String.self, forKey: .teacher) ?? ""
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        imageNumbers = try container.decodeIfPresent(String.self, forKey: .imageNumbers) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        updatedAt = parseISO8601Date(try container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? Date()
        updatedBy = try container.decodeIfPresent(UUID.self, forKey: .updatedBy)
        lockedBy = try container.decodeIfPresent(UUID.self, forKey: .lockedBy)
        lockedByName = try container.decodeIfPresent(String.self, forKey: .lockedByName)
        lockedAt = parseISO8601Date(try container.decodeIfPresent(String.self, forKey: .lockedAt))
        createdAt = parseISO8601Date(try container.decodeIfPresent(String.self, forKey: .createdAt)) ?? Date()
        isFilledBlank = try container.decodeIfPresent(Bool.self, forKey: .isFilledBlank)
        subjectId = try container.decodeIfPresent(String.self, forKey: .subjectId)
        rosterId = try container.decodeIfPresent(String.self, forKey: .rosterId) ?? ""
    }

    init(id: UUID = UUID(),
         sportsJobId: UUID,
         organizationId: String = "",
         lastName: String = "",
         firstName: String = "",
         teacher: String = "",
         groupName: String = "",
         email: String = "",
         phone: String = "",
         imageNumbers: String = "",
         notes: String = "",
         sortOrder: Int = 0,
         version: Int = 1,
         updatedAt: Date = Date(),
         updatedBy: UUID? = nil,
         lockedBy: UUID? = nil,
         lockedByName: String? = nil,
         lockedAt: Date? = nil,
         createdAt: Date = Date(),
         isFilledBlank: Bool? = nil,
         subjectId: String? = nil,
         rosterId: String = "") {
        self.id = id
        self.sportsJobId = sportsJobId
        self.organizationId = organizationId
        self.lastName = lastName
        self.firstName = firstName
        self.teacher = teacher
        self.groupName = groupName
        self.email = email
        self.phone = phone
        self.imageNumbers = imageNumbers
        self.notes = notes
        self.sortOrder = sortOrder
        self.version = version
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.lockedBy = lockedBy
        self.lockedByName = lockedByName
        self.lockedAt = lockedAt
        self.createdAt = createdAt
        self.isFilledBlank = isFilledBlank
        self.subjectId = subjectId
        self.rosterId = rosterId
    }

    // Check if entry is currently locked by someone else
    var isLocked: Bool {
        guard let lockedAt = lockedAt else { return false }
        // Lock expires after 2 minutes
        return Date().timeIntervalSince(lockedAt) < 120
    }

    // Check if locked by a specific user
    func isLockedBy(userId: UUID) -> Bool {
        return lockedBy == userId && isLocked
    }

    /// Check if locked by a different device (uses lockedByName with device session ID)
    /// Falls back to UUID comparison if lockedByName is nil (legacy data)
    func isLockedByOtherDevice(editorIdentifier: String, userId: UUID?) -> Bool {
        guard isLocked else { return false }
        if let name = lockedByName {
            return name != editorIdentifier
        }
        // Fallback for entries locked before lockedByName was populated
        guard let lockedBy = lockedBy, let userId = userId else { return false }
        return lockedBy != userId
    }
}

// MARK: - Group Image Model (matches group_images table)
struct GroupImage: Identifiable, Codable, Hashable {
    var id: UUID
    var sportsJobId: UUID
    var organizationId: String
    var description: String
    var imageNumbers: String
    var notes: String
    var sport: String
    var gender: String
    var teamLevel: String
    var sortOrder: Int

    // Sync & conflict resolution
    var version: Int
    var updatedAt: Date
    var updatedBy: UUID?

    // Soft locking
    var lockedBy: UUID?
    var lockedByName: String?
    var lockedAt: Date?

    var createdAt: Date

    // Photographer who shot this group photo
    var photographerId: String?

    // CodingKeys to map snake_case database fields to camelCase Swift properties
    enum CodingKeys: String, CodingKey {
        case id, description, notes, sport, gender, version
        case sportsJobId = "sports_job_id"
        case organizationId = "organization_id"
        case imageNumbers = "image_numbers"
        case teamLevel = "team_level"
        case sortOrder = "sort_order"
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
        case lockedBy = "locked_by"
        case lockedByName = "locked_by_name"
        case lockedAt = "locked_at"
        case createdAt = "created_at"
        case photographerId = "photographer_id"
    }

    // Custom decoder to handle missing fields with defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sportsJobId = try container.decode(UUID.self, forKey: .sportsJobId)
        organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        imageNumbers = try container.decodeIfPresent(String.self, forKey: .imageNumbers) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        sport = try container.decodeIfPresent(String.self, forKey: .sport) ?? ""
        gender = try container.decodeIfPresent(String.self, forKey: .gender) ?? ""
        teamLevel = try container.decodeIfPresent(String.self, forKey: .teamLevel) ?? ""
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        updatedAt = parseISO8601Date(try container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? Date()
        updatedBy = try container.decodeIfPresent(UUID.self, forKey: .updatedBy)
        lockedBy = try container.decodeIfPresent(UUID.self, forKey: .lockedBy)
        lockedByName = try container.decodeIfPresent(String.self, forKey: .lockedByName)
        lockedAt = parseISO8601Date(try container.decodeIfPresent(String.self, forKey: .lockedAt))
        createdAt = parseISO8601Date(try container.decodeIfPresent(String.self, forKey: .createdAt)) ?? Date()
        photographerId = try container.decodeIfPresent(String.self, forKey: .photographerId)
    }

    init(id: UUID = UUID(),
         sportsJobId: UUID,
         organizationId: String = "",
         description: String = "",
         imageNumbers: String = "",
         notes: String = "",
         sport: String = "",
         gender: String = "",
         teamLevel: String = "",
         sortOrder: Int = 0,
         version: Int = 1,
         updatedAt: Date = Date(),
         updatedBy: UUID? = nil,
         lockedBy: UUID? = nil,
         lockedByName: String? = nil,
         lockedAt: Date? = nil,
         createdAt: Date = Date(),
         photographerId: String? = nil) {
        self.id = id
        self.sportsJobId = sportsJobId
        self.organizationId = organizationId
        self.description = description
        self.imageNumbers = imageNumbers
        self.notes = notes
        self.sport = sport
        self.gender = gender
        self.teamLevel = teamLevel
        self.sortOrder = sortOrder
        self.version = version
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.lockedBy = lockedBy
        self.lockedByName = lockedByName
        self.lockedAt = lockedAt
        self.createdAt = createdAt
        self.photographerId = photographerId
    }

    // Check if entry is currently locked by someone else
    var isLocked: Bool {
        guard let lockedAt = lockedAt else { return false }
        // Lock expires after 2 minutes
        return Date().timeIntervalSince(lockedAt) < 120
    }

    // Check if locked by a specific user
    func isLockedBy(userId: UUID) -> Bool {
        return lockedBy == userId && isLocked
    }

    /// Check if locked by a different device (uses lockedByName with device session ID)
    /// Falls back to UUID comparison if lockedByName is nil (legacy data)
    func isLockedByOtherDevice(editorIdentifier: String, userId: UUID?) -> Bool {
        guard isLocked else { return false }
        if let name = lockedByName {
            return name != editorIdentifier
        }
        // Fallback for entries locked before lockedByName was populated
        guard let lockedBy = lockedBy, let userId = userId else { return false }
        return lockedBy != userId
    }
}

// MARK: - Sports Shoot Model (matches sports_jobs table)
// Note: roster and groupImages are now in separate tables and fetched via RosterEntryService/GroupImageService
struct SportsShoot: Identifiable, Codable {
    var id: UUID
    var organizationId: String
    var schoolName: String
    var schoolId: String?
    var sportName: String
    var seasonType: String
    var shootDate: Date
    var location: String
    var photographer: String
    var additionalNotes: String
    var sessionId: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var galleryId: String?       // FK to Production galleries (iPad sync)
    var shootType: String?       // Gallery shoot_type (sports, springPortraits, underclassFall, etc.)
    var displayConfig: String?   // JSON: configurable sidebar card layout from gallery settings

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case schoolName = "school_name"
        case schoolId = "school_id"
        case sportName = "sport_name"
        case seasonType = "season_type"
        case shootDate = "shoot_date"
        case location, photographer
        case additionalNotes = "additional_notes"
        case sessionId = "session_id"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case galleryId = "gallery_id"
        case shootType = "shoot_type"
        case displayConfig = "display_config"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId) ?? ""
        schoolName = try container.decodeIfPresent(String.self, forKey: .schoolName) ?? ""
        schoolId = try container.decodeIfPresent(String.self, forKey: .schoolId)
        sportName = try container.decodeIfPresent(String.self, forKey: .sportName) ?? ""
        seasonType = try container.decodeIfPresent(String.self, forKey: .seasonType) ?? ""
        shootDate = parseISO8601Date(try container.decodeIfPresent(String.self, forKey: .shootDate)) ?? Date()
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        photographer = try container.decodeIfPresent(String.self, forKey: .photographer) ?? ""
        additionalNotes = try container.decodeIfPresent(String.self, forKey: .additionalNotes) ?? ""
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = parseISO8601Date(try container.decodeIfPresent(String.self, forKey: .createdAt)) ?? Date()
        updatedAt = parseISO8601Date(try container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? Date()
        galleryId = try container.decodeIfPresent(String.self, forKey: .galleryId)
        shootType = try container.decodeIfPresent(String.self, forKey: .shootType)
        displayConfig = try container.decodeIfPresent(String.self, forKey: .displayConfig)
    }

    init(id: UUID = UUID(),
         organizationId: String = "",
         schoolName: String = "",
         schoolId: String? = nil,
         sportName: String = "",
         seasonType: String = "",
         shootDate: Date = Date(),
         location: String = "",
         photographer: String = "",
         additionalNotes: String = "",
         sessionId: String? = nil,
         isArchived: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         galleryId: String? = nil,
         displayConfig: String? = nil) {
        self.id = id
        self.organizationId = organizationId
        self.schoolName = schoolName
        self.schoolId = schoolId
        self.sportName = sportName
        self.seasonType = seasonType
        self.shootDate = shootDate
        self.location = location
        self.photographer = photographer
        self.additionalNotes = additionalNotes
        self.sessionId = sessionId
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.galleryId = galleryId
        self.displayConfig = displayConfig
    }
}

// MARK: - Sports Shoot Service (manages sports_jobs table only)
// Roster entries and group images are now in separate tables - use RosterEntryService and GroupImageService
class SportsShootService {
    static let shared = SportsShootService()
    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private let tableName = "sports_jobs"

    private init() {}

    // MARK: - Fetch
    // NOTE: PowerSync handles offline caching for sports_jobs table automatically

    func fetchSportsShoot(id: UUID) async throws -> SportsShoot {
        // Fetch from network (Supabase)
        let shoot: SportsShoot = try await supabase
            .from(tableName)
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value

        return shoot
    }

    func fetchAllSportsShoots(forOrganization orgID: String) async throws -> [SportsShoot] {
        print("DEBUG: Fetching sports shoots for org: '\(orgID)'")

        // Fetch from network (Supabase)
        let shoots: [SportsShoot] = try await supabase
            .from(tableName)
            .select()
            .eq("organization_id", value: orgID)
            .order("shoot_date", ascending: false)
            .execute()
            .value
        print("DEBUG: Successfully decoded \(shoots.count) shoots")

        return shoots
    }

    // MARK: - Create

    func createSportsShoot(_ shoot: SportsShoot) async throws -> SportsShoot {
        let created: SportsShoot = try await supabase
            .from(tableName)
            .insert(shoot)
            .select()
            .single()
            .execute()
            .value
        return created
    }

    // MARK: - Update

    func updateSportsShoot(_ shoot: SportsShoot) async throws {
        try await supabase
            .from(tableName)
            .update(shoot)
            .eq("id", value: shoot.id)
            .execute()
    }

    // MARK: - Archive

    func archiveSportsShoot(id: UUID) async throws {
        try await supabase
            .from(tableName)
            .update(["is_archived": true])
            .eq("id", value: id)
            .execute()
    }

    func unarchiveSportsShoot(id: UUID) async throws {
        try await supabase
            .from(tableName)
            .update(["is_archived": false])
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Delete

    func deleteSportsShoot(id: UUID) async throws {
        try await supabase
            .from(tableName)
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Session Integration

    func fetchUpcomingSessions(forOrganization orgID: String) async throws -> [Session] {
        let now = Date()
        let twoWeeksFromNow = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: now) ?? now

        let sessions = try await SessionService.shared.fetchSessions(organizationID: orgID)

        return sessions.filter { session in
            guard let sessionDate = session.startDate else { return false }
            return sessionDate >= now && sessionDate <= twoWeeksFromNow && !session.hasSportsJob
        }.sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
    }
}
