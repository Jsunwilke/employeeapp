import Foundation

struct SchoolItem: Identifiable, Hashable, Codable, Equatable {
    let id: String
    let name: String
    let address: String
    let coordinates: String? // Format: "lat,lng"
}

// MARK: - Template Models (Supabase)

/// Report template for Supabase - uses snake_case for database fields
struct ReportTemplate: Codable, Identifiable {
    let id: String
    let organization_id: String
    let name: String
    var description: String?
    let shoot_type: String
    var fields: [TemplateField]
    var is_default: Bool
    var is_active: Bool
    var version: Int
    let created_by: String
    let created_at: Date?
    let updated_at: Date?

    // Computed properties for backward compatibility
    var organizationID: String { organization_id }
    var shootType: String { shoot_type }
    var isDefault: Bool { is_default }
    var isActive: Bool { is_active }
    var createdBy: String { created_by }
    var createdAt: Date? { created_at }
    var updatedAt: Date? { updated_at }

    enum CodingKeys: String, CodingKey {
        case id, name, description, fields, version
        case organization_id, shoot_type, is_default, is_active
        case created_by, created_at, updated_at
    }

    init(
        id: String = UUID().uuidString,
        organizationID: String,
        name: String,
        description: String? = nil,
        shootType: String,
        fields: [TemplateField] = [],
        isDefault: Bool = false,
        isActive: Bool = true,
        version: Int = 1,
        createdBy: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.organization_id = organizationID
        self.name = name
        self.description = description
        self.shoot_type = shootType
        self.fields = fields
        self.is_default = isDefault
        self.is_active = isActive
        self.version = version
        self.created_by = createdBy
        self.created_at = createdAt
        self.updated_at = updatedAt
    }
}

struct TemplateField: Codable, Identifiable {
    let id: String
    let type: String
    let label: String
    let required: Bool
    let options: [String]?
    let placeholder: String?
    let defaultValue: String?
    let smartConfig: SmartFieldConfig?
    let readOnly: Bool?
    
    init(id: String = UUID().uuidString, type: String, label: String, required: Bool = false, options: [String]? = nil, placeholder: String? = nil, defaultValue: String? = nil, smartConfig: SmartFieldConfig? = nil, readOnly: Bool? = nil) {
        self.id = id
        self.type = type
        self.label = label
        self.required = required
        self.options = options
        self.placeholder = placeholder
        self.defaultValue = defaultValue
        self.smartConfig = smartConfig
        self.readOnly = readOnly
    }
    
    // Custom decoding to handle flexibility with web app data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try container.decode(String.self, forKey: .type)
        label = try container.decode(String.self, forKey: .label)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        options = try container.decodeIfPresent([String].self, forKey: .options)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        smartConfig = try? container.decodeIfPresent(SmartFieldConfig.self, forKey: .smartConfig)
        readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, type, label, required, options, placeholder, defaultValue, smartConfig, readOnly
    }
}

struct SmartFieldConfig: Codable {
    let calculationType: String
    let fallbackValue: String?
    let autoUpdate: Bool
    let format: String? // For date/time/location formatting
    
    init(calculationType: String, fallbackValue: String? = nil, autoUpdate: Bool = true, format: String? = nil) {
        self.calculationType = calculationType
        self.fallbackValue = fallbackValue
        self.autoUpdate = autoUpdate
        self.format = format
    }
}

/// Daily Job Report for Supabase - uses snake_case for database fields
struct DailyJobReport: Codable, Identifiable {
    let id: String
    let organization_id: String
    let user_id: String

    // Report date and metadata
    let date: Date
    let your_name: String

    // School/Location
    var school_or_destination: String?

    // Mileage
    var total_mileage: Double

    // Job details (stored as JSONB arrays in Supabase)
    var job_descriptions: [String]?
    var extra_items: [String]?

    // Yes/No/NA selections
    var cards_scanned_choice: String?
    var job_box_and_camera_cards: String?
    var sports_background_shot: String?

    // Notes
    var job_description_text: String?

    // Photoshoot note reference
    var photoshoot_note_id: String?
    var photoshoot_note_text: String?

    // Photos (stored as JSONB array in Supabase)
    var photo_urls: [String]?

    // Template reference (for template-based reports)
    var template_id: String?
    var template_name: String?
    var template_version: Int?
    var report_type: String?
    var smart_fields_used: [String]?
    var form_data: [String: AnyCodable]?

    // Timestamps
    let created_at: Date?
    let updated_at: Date?

    // MARK: - Computed properties for backward compatibility

    var organizationID: String { organization_id }
    var userId: String { user_id }
    var yourName: String { your_name }
    var schoolOrDestination: String? { school_or_destination }
    var totalMileage: Double { total_mileage }
    var jobDescriptions: [String] { job_descriptions ?? [] }
    var extraItems: [String] { extra_items ?? [] }
    var cardsScannedChoice: String? { cards_scanned_choice }
    var jobBoxAndCameraCards: String? { job_box_and_camera_cards }
    var sportsBackgroundShot: String? { sports_background_shot }
    var jobDescriptionText: String? { job_description_text }
    var photoshootNoteID: String? { photoshoot_note_id }
    var photoshootNoteText: String? { photoshoot_note_text }
    var photoURLs: [String] { photo_urls ?? [] }
    var templateId: String? { template_id }
    var templateName: String? { template_name }
    var templateVersion: Int? { template_version }
    var reportType: String { report_type ?? "standard" }
    var smartFieldsUsed: [String] { smart_fields_used ?? [] }
    var formData: [String: AnyCodable] { form_data ?? [:] }
    var createdAt: Date? { created_at }
    var updatedAt: Date? { updated_at }

    // Legacy photographer field (maps to your_name)
    var photographer: String { your_name }

    enum CodingKeys: String, CodingKey {
        case id, date
        case organization_id, user_id, your_name
        case school_or_destination, total_mileage
        case job_descriptions, extra_items
        case cards_scanned_choice, job_box_and_camera_cards, sports_background_shot
        case job_description_text
        case photoshoot_note_id, photoshoot_note_text
        case photo_urls
        case template_id, template_name, template_version
        case report_type, smart_fields_used, form_data
        case created_at, updated_at
    }

    // Custom decoder to handle Supabase date format ("2025-12-28" string instead of Date)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields
        id = try container.decode(String.self, forKey: .id)
        organization_id = try container.decode(String.self, forKey: .organization_id)
        user_id = try container.decode(String.self, forKey: .user_id)
        your_name = try container.decode(String.self, forKey: .your_name)

        // Handle date from Supabase - can be either:
        // 1. Simple date format: "2025-12-28"
        // 2. Full timestamp format: "2025-12-18T18:05:00+00:00"
        let dateString = try container.decode(String.self, forKey: .date)
        var parsedDate: Date?

        // Try simple date format first (yyyy-MM-dd)
        let simpleDateFormatter = DateFormatter()
        simpleDateFormatter.dateFormat = "yyyy-MM-dd"
        simpleDateFormatter.timeZone = TimeZone.current
        parsedDate = simpleDateFormatter.date(from: dateString)

        // If that fails, try ISO8601 timestamp format
        if parsedDate == nil {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            parsedDate = isoFormatter.date(from: dateString)

            // Try without fractional seconds
            if parsedDate == nil {
                isoFormatter.formatOptions = [.withInternetDateTime]
                parsedDate = isoFormatter.date(from: dateString)
            }
        }

        guard let finalDate = parsedDate else {
            throw DecodingError.dataCorruptedError(
                forKey: .date,
                in: container,
                debugDescription: "Invalid date format: \(dateString). Expected yyyy-MM-dd or ISO8601"
            )
        }
        date = finalDate

        // Optional fields
        school_or_destination = try container.decodeIfPresent(String.self, forKey: .school_or_destination)
        total_mileage = try container.decodeIfPresent(Double.self, forKey: .total_mileage) ?? 0.0
        job_descriptions = try container.decodeIfPresent([String].self, forKey: .job_descriptions)
        extra_items = try container.decodeIfPresent([String].self, forKey: .extra_items)
        cards_scanned_choice = try container.decodeIfPresent(String.self, forKey: .cards_scanned_choice)
        job_box_and_camera_cards = try container.decodeIfPresent(String.self, forKey: .job_box_and_camera_cards)
        sports_background_shot = try container.decodeIfPresent(String.self, forKey: .sports_background_shot)
        job_description_text = try container.decodeIfPresent(String.self, forKey: .job_description_text)
        photoshoot_note_id = try container.decodeIfPresent(String.self, forKey: .photoshoot_note_id)
        photoshoot_note_text = try container.decodeIfPresent(String.self, forKey: .photoshoot_note_text)
        photo_urls = try container.decodeIfPresent([String].self, forKey: .photo_urls)
        template_id = try container.decodeIfPresent(String.self, forKey: .template_id)
        template_name = try container.decodeIfPresent(String.self, forKey: .template_name)
        template_version = try container.decodeIfPresent(Int.self, forKey: .template_version)
        report_type = try container.decodeIfPresent(String.self, forKey: .report_type)
        smart_fields_used = try container.decodeIfPresent([String].self, forKey: .smart_fields_used)
        form_data = try container.decodeIfPresent([String: AnyCodable].self, forKey: .form_data)

        // Handle timestamps (ISO8601 with time from Supabase)
        if let createdAtString = try container.decodeIfPresent(String.self, forKey: .created_at) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var parsedCreatedAt = isoFormatter.date(from: createdAtString)
            // Try without fractional seconds if that fails
            if parsedCreatedAt == nil {
                isoFormatter.formatOptions = [.withInternetDateTime]
                parsedCreatedAt = isoFormatter.date(from: createdAtString)
            }
            created_at = parsedCreatedAt
        } else {
            created_at = nil
        }

        if let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updated_at) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var parsedUpdatedAt = isoFormatter.date(from: updatedAtString)
            // Try without fractional seconds if that fails
            if parsedUpdatedAt == nil {
                isoFormatter.formatOptions = [.withInternetDateTime]
                parsedUpdatedAt = isoFormatter.date(from: updatedAtString)
            }
            updated_at = parsedUpdatedAt
        } else {
            updated_at = nil
        }
    }

    init(
        id: String = UUID().uuidString,
        organizationID: String,
        userId: String,
        date: Date,
        yourName: String,
        schoolOrDestination: String? = nil,
        totalMileage: Double = 0.0,
        jobDescriptions: [String]? = nil,
        extraItems: [String]? = nil,
        cardsScannedChoice: String? = nil,
        jobBoxAndCameraCards: String? = nil,
        sportsBackgroundShot: String? = nil,
        jobDescriptionText: String? = nil,
        photoshootNoteID: String? = nil,
        photoshootNoteText: String? = nil,
        photoURLs: [String]? = nil,
        templateId: String? = nil,
        templateName: String? = nil,
        templateVersion: Int? = nil,
        reportType: String = "standard",
        smartFieldsUsed: [String]? = nil,
        formData: [String: AnyCodable]? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.organization_id = organizationID
        self.user_id = userId
        self.date = date
        self.your_name = yourName
        self.school_or_destination = schoolOrDestination
        self.total_mileage = totalMileage
        self.job_descriptions = jobDescriptions
        self.extra_items = extraItems
        self.cards_scanned_choice = cardsScannedChoice
        self.job_box_and_camera_cards = jobBoxAndCameraCards
        self.sports_background_shot = sportsBackgroundShot
        self.job_description_text = jobDescriptionText
        self.photoshoot_note_id = photoshootNoteID
        self.photoshoot_note_text = photoshootNoteText
        self.photo_urls = photoURLs
        self.template_id = templateId
        self.template_name = templateName
        self.template_version = templateVersion
        self.report_type = reportType
        self.smart_fields_used = smartFieldsUsed
        self.form_data = formData
        self.created_at = createdAt
        self.updated_at = updatedAt
    }
}

// Helper for storing Any values in Codable structs
// MARK: - Weather Models

struct WeatherResponse: Codable {
    let latitude: Double
    let longitude: Double
    let current_weather: CurrentWeather
}

struct CurrentWeather: Codable {
    let temperature: Double
    let weathercode: Int
    let windspeed: Double?
    let winddirection: Int?
}

struct AnyCodable: Codable {
    let value: Any
    
    init<T>(_ value: T?) {
        self.value = value ?? ()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = ()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            let encodableArray = arrayValue.map { AnyCodable($0) }
            try container.encode(encodableArray)
        case let dictValue as [String: Any]:
            let encodableDict = dictValue.mapValues { AnyCodable($0) }
            try container.encode(encodableDict)
        default:
            try container.encodeNil()
        }
    }
}

enum TemplateError: Error, LocalizedError {
    case noOrganization
    case noTemplatesFound
    case networkError(Error)
    case permissionDenied
    case invalidTemplate
    case calculationFailed
    
    var errorDescription: String? {
        switch self {
        case .noOrganization:
            return "No organization ID found"
        case .noTemplatesFound:
            return "No templates available"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .permissionDenied:
            return "Permission denied"
        case .invalidTemplate:
            return "Invalid template format"
        case .calculationFailed:
            return "Smart field calculation failed"
        }
    }
}

struct PhotoshootNote: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var timestamp: Date
    var school: String  // The school name selected via dropdown.
    var noteText: String
    var photoURLs: [String] // URLs of photos taken for this note
    
    // For backward compatibility when decoding existing notes
    enum CodingKeys: String, CodingKey {
        case id, timestamp, school, noteText, photoURLs
    }
    
    init(id: UUID, timestamp: Date, school: String, noteText: String, photoURLs: [String] = []) {
        self.id = id
        self.timestamp = timestamp
        self.school = school
        self.noteText = noteText
        self.photoURLs = photoURLs
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        school = try container.decode(String.self, forKey: .school)
        noteText = try container.decode(String.self, forKey: .noteText)
        // Try to decode photoURLs, but use an empty array if the key doesn't exist
        photoURLs = (try? container.decode([String].self, forKey: .photoURLs)) ?? []
    }
}

// MARK: - Time Tracking Models

struct TimeEntry: Identifiable, Codable {
    let id: String

    // Supabase snake_case properties (matching actual database columns)
    let user_id: String
    let organization_id: String
    let start_time: Date? // Database column name
    let end_time: Date?   // Database column name
    let total_hours: Double?
    let date: String? // YYYY-MM-DD format (optional, added by migration)
    let status: String // "clocked-in" or "clocked-out"
    let session_id: String?
    let session_name: String? // Optional, added by migration
    let notes: String? // Optional, added by migration
    let created_at: Date
    let updated_at: Date

    // Backward compatibility computed properties (camelCase for iOS code)
    var userId: String { user_id }
    var organizationID: String { organization_id }
    var clockInTime: Date? { start_time } // iOS uses clockInTime
    var clockOutTime: Date? { end_time }  // iOS uses clockOutTime
    var sessionId: String? { session_id }
    var sessionName: String? { session_name }
    var createdAt: Date { created_at }
    var updatedAt: Date { updated_at }

    // Coding keys for Supabase (must match database column names exactly)
    enum CodingKeys: String, CodingKey {
        case id
        case user_id
        case organization_id
        case start_time      // DB column, not clock_in_time
        case end_time        // DB column, not clock_out_time
        case total_hours
        case date
        case status
        case session_id
        case session_name
        case notes
        case created_at
        case updated_at
    }

    // Custom initializer for backward compatibility with camelCase parameters
    init(
        id: String,
        userId: String,
        organizationID: String,
        clockInTime: Date?,
        clockOutTime: Date?,
        date: String? = nil,
        status: String,
        sessionId: String? = nil,
        sessionName: String? = nil,
        notes: String? = nil,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.user_id = userId
        self.organization_id = organizationID
        self.start_time = clockInTime
        self.end_time = clockOutTime
        self.total_hours = nil // Will be calculated if needed
        self.date = date
        self.status = status
        self.session_id = sessionId
        self.session_name = sessionName
        self.notes = notes
        self.created_at = createdAt ?? Date()
        self.updated_at = updatedAt ?? Date()
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

// MARK: - Time Entry Validation

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
    static func canEditEntry(_ entry: TimeEntry, clockInOnly: Bool = false) -> Bool {
        let createdAt = entry.createdAt

        // Allow editing for active entries (clock-in time can be edited)
        if entry.status == "clocked-in" {
            return true // Allow editing active entries
        }

        // 30-day edit window for completed entries
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return createdAt >= thirtyDaysAgo
    }
    
    // Validate clock-in time for active entries
    static func canEditActiveClockIn(_ entry: TimeEntry, newClockInTime: Date) -> (isValid: Bool, error: String?) {
        // Must be an active entry
        guard entry.status == "clocked-in" else {
            return (false, "Entry is not currently active")
        }
        
        // Cannot be in the future
        if newClockInTime > Date() {
            return (false, "Clock-in time cannot be in the future")
        }
        
        // Must be within the last 48 hours (reasonable limit)
        let fortyEightHoursAgo = Calendar.current.date(byAdding: .hour, value: -48, to: Date()) ?? Date()
        if newClockInTime < fortyEightHoursAgo {
            return (false, "Clock-in time must be within the last 48 hours")
        }
        
        return (true, nil)
    }
}

// MARK: - Date and TimeInterval Extensions

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

// MARK: - NFC SD Tracker Models (Supabase)

/// Record for NFC SD card tracking stored in Supabase
struct NFCRecord: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let photographer: String
    let card_number: String
    let school: String
    let status: String
    let uploaded_from_jasons_house: String?
    let uploaded_from_andys_house: String?
    let organization_id: String
    let user_id: String

    // Backward compatibility computed properties
    var cardNumber: String { card_number }
    var uploadedFromJasonsHouse: String? { uploaded_from_jasons_house }
    var uploadedFromAndysHouse: String? { uploaded_from_andys_house }
    var organizationID: String { organization_id }
    var userId: String { user_id }

    // Member-wise initializer for creating new records
    init(id: String = UUID().uuidString,
         timestamp: Date,
         photographer: String,
         cardNumber: String,
         school: String,
         status: String,
         uploadedFromJasonsHouse: String? = nil,
         uploadedFromAndysHouse: String? = nil,
         organizationID: String,
         userId: String) {
        self.id = id
        self.timestamp = timestamp
        self.photographer = photographer
        self.card_number = cardNumber
        self.school = school
        self.status = status
        self.uploaded_from_jasons_house = uploadedFromJasonsHouse
        self.uploaded_from_andys_house = uploadedFromAndysHouse
        self.organization_id = organizationID
        self.user_id = userId
    }
}

// JobBoxRecord removed - using existing JobBox struct from Manager Features/JobBoxStatus.swift

struct DropdownRecord: Codable, Identifiable {
    let id: String
    let type: String?
    let value: String
    let organization_id: String?

    var organizationID: String? { organization_id }
}

// MARK: - Photo Critique Models

struct Critique: Codable, Identifiable {
    let id: String
    let organization_id: String

    // Submission info
    let submitter_id: String
    let submitter_name: String
    let submitter_email: String

    // Target photographer
    let target_photographer_id: String
    let target_photographer_name: String

    // Images
    let image_urls: [String]?
    let thumbnail_urls: [String]?
    let image_url: String?  // Backward compatibility
    let thumbnail_url: String?
    let image_count: Int?

    // Content
    let manager_notes: String
    let example_type: String  // "example" or "improvement"
    let status: String

    // Timestamps
    let created_at: Date?
    let updated_at: Date?

    // Computed property for display
    var isGoodExample: Bool {
        example_type == "example"
    }

    // Backward compatibility computed properties
    var organizationId: String { organization_id }
    var submitterId: String { submitter_id }
    var submitterName: String { submitter_name }
    var submitterEmail: String { submitter_email }
    var targetPhotographerId: String { target_photographer_id }
    var targetPhotographerName: String { target_photographer_name }
    var imageUrls: [String] { image_urls ?? [] }
    var thumbnailUrls: [String] { thumbnail_urls ?? [] }
    var imageUrl: String { image_url ?? "" }
    var thumbnailUrl: String { thumbnail_url ?? "" }
    var imageCount: Int { image_count ?? 0 }
    var managerNotes: String { manager_notes }
    var exampleType: String { example_type }
    var createdAt: Date? { created_at }
    var updatedAt: Date? { updated_at }

    // Computed property for formatted date
    var formattedDate: String {
        guard let createdAt = created_at else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

struct CritiqueStats {
    let total: Int
    let goodExamples: Int
    let needsImprovement: Int
}
