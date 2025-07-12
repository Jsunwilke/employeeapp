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
