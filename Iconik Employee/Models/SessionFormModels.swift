import Foundation

// MARK: - Session Form Data
struct SessionFormData {
    var schoolId: String = ""
    var date: String = ""
    var startTime: String = ""
    var endTime: String = ""
    var sessionTypes: [String] = []
    var customSessionType: String = ""
    var photographerIds: Set<String> = []
    var photographerNotes: [String: String] = [:] // photographerId -> notes
    var notes: String = ""
    var status: String = "scheduled"
    var isTimeOff: Bool = false
}

// MARK: - School Model (snake_case for Supabase)
struct School: Identifiable, Hashable {
    // Core fields
    let id: String
    let organization_id: String
    let name: String
    let is_active: Bool

    // Address fields
    let address: String?
    let street: String?
    let city: String?
    let state: String?
    let zip: String?
    let coordinates: String?  // Can be "lat,lng" string OR converted from {lat, lng} object

    // Contact fields
    let contact_name: String?
    let contact_email: String?
    let contact_phone: String?

    // District relationship
    let district_id: String?
    let district_name: String?

    // Other
    let notes: String?
    let location_photos: String?  // JSONB stored as string - array of {url, label} objects

    // Timestamps
    let created_at: Date?
    let updated_at: Date?

    // Computed properties for backward compatibility
    var value: String { name }  // Legacy accessor (old code used .value for name)
    var organizationID: String { organization_id }
    var isActive: Bool { is_active }
    var createdAt: Date? { created_at }
    var updatedAt: Date? { updated_at }
    var contactName: String? { contact_name }
    var contactEmail: String? { contact_email }
    var contactPhone: String? { contact_phone }
    var districtId: String? { district_id }
    var districtName: String? { district_name }

    /// Parse coordinates string "lat,lng" into tuple
    var parsedCoordinates: (lat: Double, lng: Double)? {
        guard let coords = coordinates else { return nil }
        // Remove any surrounding quotes from the string
        let cleaned = coords.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let parts = cleaned.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lng = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return (lat, lng)
    }

    /// Parse location_photos JSONB string into array of LocationPhoto objects
    var parsedLocationPhotos: [LocationPhoto] {
        guard let photosString = location_photos,
              let data = photosString.data(using: .utf8) else {
            return []
        }
        do {
            let photoDicts = try JSONDecoder().decode([[String: String]].self, from: data)
            return photoDicts.compactMap { dict in
                guard let url = dict["url"], let label = dict["label"] else { return nil }
                return LocationPhoto(url: url, label: label)
            }
        } catch {
            return []
        }
    }
}

// MARK: - School Codable Extension (handles coordinates as String OR Object)
extension School: Codable {
    enum CodingKeys: String, CodingKey {
        case id, organization_id, name, is_active
        case address, street, city, state, zip, coordinates
        case contact_name, contact_email, contact_phone
        case district_id, district_name
        case notes, location_photos
        case created_at, updated_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        organization_id = try container.decode(String.self, forKey: .organization_id)
        name = try container.decode(String.self, forKey: .name)
        is_active = try container.decodeIfPresent(Bool.self, forKey: .is_active) ?? true

        address = try container.decodeIfPresent(String.self, forKey: .address)
        street = try container.decodeIfPresent(String.self, forKey: .street)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        zip = try container.decodeIfPresent(String.self, forKey: .zip)

        // Handle coordinates - can be String "lat,lng" OR Object {lat: x, lng: y}
        if let coordString = try? container.decodeIfPresent(String.self, forKey: .coordinates) {
            coordinates = coordString
        } else if let coordDict = try? container.decodeIfPresent([String: Double].self, forKey: .coordinates) {
            // Convert {lat: x, lng: y} object to "lat,lng" string
            if let lat = coordDict["lat"], let lng = coordDict["lng"] {
                coordinates = "\(lat),\(lng)"
            } else {
                coordinates = nil
            }
        } else {
            coordinates = nil
        }

        contact_name = try container.decodeIfPresent(String.self, forKey: .contact_name)
        contact_email = try container.decodeIfPresent(String.self, forKey: .contact_email)
        contact_phone = try container.decodeIfPresent(String.self, forKey: .contact_phone)

        district_id = try container.decodeIfPresent(String.self, forKey: .district_id)
        district_name = try container.decodeIfPresent(String.self, forKey: .district_name)

        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        location_photos = try container.decodeIfPresent(String.self, forKey: .location_photos)

        created_at = try container.decodeIfPresent(Date.self, forKey: .created_at)
        updated_at = try container.decodeIfPresent(Date.self, forKey: .updated_at)
    }
}

// MARK: - Team Member Model (snake_case for Supabase)
struct TeamMember: Identifiable, Codable {
    let id: String
    let organization_id: String
    let email: String?  // Made optional - database may have NULL values
    let first_name: String
    let last_name: String?  // Made optional - database may have NULL values
    let photo_url: String?
    let is_active: Bool
    let role: String?  // Made optional - database may have NULL values
    let display_name: String?
    let created_at: Date?
    let updated_at: Date?

    // Flag-related fields
    let is_flagged: Bool?
    let flag_note: String?
    let flagged_by: String?

    // Computed properties for backward compatibility with camelCase
    var organizationID: String { organization_id }
    var firstName: String { first_name }
    var lastName: String? { last_name }
    var photoURL: String? { photo_url }
    var isActive: Bool { is_active }
    var displayName: String? { display_name }
    var createdAt: Date? { created_at }
    var updatedAt: Date? { updated_at }
    var isFlagged: Bool { is_flagged ?? false }
    var flagNote: String? { flag_note }
    var flaggedBy: String? { flagged_by }

    var fullName: String {
        if let displayName = display_name, !displayName.isEmpty {
            return displayName
        }
        if let lastName = last_name, !lastName.isEmpty {
            return "\(first_name) \(lastName)"
        }
        return first_name
    }
}

// MARK: - Session Type Model
struct SessionType: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let color: String
    var order: Int?  // Made optional - some session types may not have order set

    static func == (lhs: SessionType, rhs: SessionType) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Session Creation Data
// Note: SessionPhotographer is now defined in Session.swift
struct SessionCreationData {
    let organizationID: String
    let schoolId: String
    let schoolName: String
    let date: String
    let startTime: String
    let endTime: String
    let sessionTypes: [String]
    let customSessionType: String?
    let photographers: [SessionPhotographer]
    let notes: String
    let status: String
    let sessionColor: String
    let isTimeOff: Bool
    let createdBy: CreatedByInfo
    let published: Bool?
}

// MARK: - Created By Info
struct CreatedByInfo: Codable {
    let id: String
    let name: String
    let email: String
}

