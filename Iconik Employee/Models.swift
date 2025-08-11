import Foundation
import FirebaseFirestore

struct SchoolItem: Identifiable, Hashable, Codable, Equatable {
    let id: String
    let name: String
    let address: String
    let coordinates: String? // Format: "lat,lng"
}

// MARK: - Template Models

struct ReportTemplate: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let shootType: String
    let organizationID: String
    let fields: [TemplateField]
    let isDefault: Bool
    let isActive: Bool
    let version: Int
    let createdAt: Timestamp?
    let updatedAt: Timestamp?
    let createdBy: String
    
    init(id: String = UUID().uuidString, name: String, description: String? = nil, shootType: String, organizationID: String, fields: [TemplateField], isDefault: Bool = false, isActive: Bool = true, version: Int = 1, createdAt: Timestamp? = Timestamp(), updatedAt: Timestamp? = Timestamp(), createdBy: String) {
        self.id = id
        self.name = name
        self.description = description
        self.shootType = shootType
        self.organizationID = organizationID
        self.fields = fields
        self.isDefault = isDefault
        self.isActive = isActive
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
    }
    
    // Custom decoding to handle flexibility with web app data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        shootType = try container.decodeIfPresent(String.self, forKey: .shootType) ?? "general"
        organizationID = try container.decode(String.self, forKey: .organizationID)
        fields = try container.decodeIfPresent([TemplateField].self, forKey: .fields) ?? []
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy) ?? ""
        
        // Handle timestamps flexibly - they might be missing or different types
        createdAt = try? container.decodeIfPresent(Timestamp.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(Timestamp.self, forKey: .updatedAt)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, description, shootType, organizationID, fields
        case isDefault, isActive, version, createdAt, updatedAt, createdBy
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

struct DailyJobReport: Codable, Identifiable {
    let id: String
    let organizationID: String
    let userId: String
    let date: String
    let photographer: String
    let templateId: String?
    let templateName: String?
    let templateVersion: Int?
    let reportType: String
    let smartFieldsUsed: [String]?
    let formData: [String: AnyCodable]
    let createdAt: Timestamp
    let updatedAt: Timestamp
    
    init(id: String = UUID().uuidString, organizationID: String, userId: String, date: String, photographer: String, templateId: String? = nil, templateName: String? = nil, templateVersion: Int? = nil, reportType: String = "template", smartFieldsUsed: [String]? = nil, formData: [String: AnyCodable] = [:], createdAt: Timestamp = Timestamp(), updatedAt: Timestamp = Timestamp()) {
        self.id = id
        self.organizationID = organizationID
        self.userId = userId
        self.date = date
        self.photographer = photographer
        self.templateId = templateId
        self.templateName = templateName
        self.templateVersion = templateVersion
        self.reportType = reportType
        self.smartFieldsUsed = smartFieldsUsed
        self.formData = formData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    let userId: String
    let organizationID: String
    let clockInTime: Date?
    let clockOutTime: Date?
    let date: String
    let status: String
    let sessionId: String?
    let sessionName: String?
    let notes: String?
    let createdAt: Date?
    let updatedAt: Date?
    
    // Direct initializer for creating TimeEntry instances
    init(id: String, userId: String, organizationID: String, clockInTime: Date? = nil, clockOutTime: Date? = nil, date: String, status: String, sessionId: String? = nil, sessionName: String? = nil, notes: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.organizationID = organizationID
        self.clockInTime = clockInTime
        self.clockOutTime = clockOutTime
        self.date = date
        self.status = status
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    init(document: QueryDocumentSnapshot) {
        self.id = document.documentID
        let data = document.data()
        
        self.userId = data["userId"] as? String ?? ""
        self.organizationID = data["organizationID"] as? String ?? ""
        self.date = data["date"] as? String ?? ""
        self.status = data["status"] as? String ?? ""
        self.sessionId = data["sessionId"] as? String
        self.sessionName = data["sessionName"] as? String
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
    
    init(document: DocumentSnapshot) {
        self.id = document.documentID
        let data = document.data() ?? [:]
        
        self.userId = data["userId"] as? String ?? ""
        self.organizationID = data["organizationID"] as? String ?? ""
        self.date = data["date"] as? String ?? ""
        self.status = data["status"] as? String ?? ""
        self.sessionId = data["sessionId"] as? String
        self.sessionName = data["sessionName"] as? String
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
        guard let createdAt = entry.createdAt else { return false }
        
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

// MARK: - NFC SD Tracker Models

import FirebaseFirestoreSwift

struct FirestoreRecord: Codable, Identifiable {
    @DocumentID var id: String?
    let timestamp: Date
    let photographer: String
    let cardNumber: String
    let school: String
    let status: String
    let uploadedFromJasonsHouse: String?
    let uploadedFromAndysHouse: String?
    let organizationID: String
    let userId: String // User ID for Firebase Auth
    
    // Manual initializer for Firestore data
    init(id: String, data: [String: Any]) {
        self.id = id
        
        // Handle timestamp conversion
        if let timestamp = data["timestamp"] as? Timestamp {
            self.timestamp = timestamp.dateValue()
        } else {
            self.timestamp = Date()
        }
        
        self.photographer = data["photographer"] as? String ?? ""
        self.cardNumber = data["cardNumber"] as? String ?? ""
        self.school = data["school"] as? String ?? ""
        self.status = data["status"] as? String ?? ""
        self.uploadedFromJasonsHouse = data["uploadedFromJasonsHouse"] as? String
        self.uploadedFromAndysHouse = data["uploadedFromAndysHouse"] as? String
        self.organizationID = data["organizationID"] as? String ?? ""
        self.userId = data["userId"] as? String ?? ""
    }
    
    // Member-wise initializer for creating new records
    init(id: String? = nil,
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
        self.cardNumber = cardNumber
        self.school = school
        self.status = status
        self.uploadedFromJasonsHouse = uploadedFromJasonsHouse
        self.uploadedFromAndysHouse = uploadedFromAndysHouse
        self.organizationID = organizationID
        self.userId = userId
    }
}

// JobBoxRecord removed - using existing JobBox struct from Manager Features/JobBoxStatus.swift

struct DropdownRecord: Codable, Identifiable {
    @DocumentID var id: String?
    let type: String?
    let value: String
    let organizationID: String?
}

// MARK: - Photo Critique Models

struct Critique: Codable, Identifiable {
    @DocumentID var id: String?
    let organizationId: String
    
    // Submission info
    let submitterId: String
    let submitterName: String
    let submitterEmail: String
    
    // Target photographer
    let targetPhotographerId: String
    let targetPhotographerName: String
    
    // Images
    let imageUrls: [String]
    let thumbnailUrls: [String]
    let imageUrl: String  // Backward compatibility
    let thumbnailUrl: String
    let imageCount: Int
    
    // Content
    let managerNotes: String
    let exampleType: String  // "example" or "improvement"
    let status: String
    
    // Timestamps
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
    
    // Computed property for display
    var isGoodExample: Bool {
        exampleType == "example"
    }
    
    // Computed property for formatted date
    var formattedDate: String {
        guard let createdAt = createdAt else { return "" }
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
