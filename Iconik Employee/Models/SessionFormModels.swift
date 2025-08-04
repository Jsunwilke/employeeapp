import Foundation
import FirebaseAuth

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

// MARK: - School Model
struct School: Identifiable, Codable {
    let id: String
    let organizationID: String
    let value: String // School name (legacy field name)
    let isActive: Bool
    let createdAt: Date?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case organizationID
        case value
        case isActive
        case createdAt
        case updatedAt
    }
}

// MARK: - Team Member Model
struct TeamMember: Identifiable, Codable {
    let id: String
    let organizationID: String
    let email: String
    let firstName: String
    let lastName: String
    let photoURL: String?
    let isActive: Bool
    let role: String
    let displayName: String?
    let createdAt: Date?
    let updatedAt: Date?
    
    var fullName: String {
        displayName ?? "\(firstName) \(lastName)"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case organizationID
        case email
        case firstName
        case lastName
        case photoURL
        case isActive
        case role
        case displayName
        case createdAt
        case updatedAt
    }
}

// MARK: - Session Type Model
struct SessionType: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let color: String
    var order: Int
    
    static func == (lhs: SessionType, rhs: SessionType) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Session Photographer Model
struct SessionPhotographer: Codable {
    let id: String
    let name: String
    let email: String
    let notes: String
}

// MARK: - Session Creation Data
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

// MARK: - User Model Extension
extension FirebaseAuth.User {
    var firstName: String? {
        // Try to extract first name from display name
        displayName?.components(separatedBy: " ").first
    }
    
    var lastName: String? {
        // Try to extract last name from display name
        let components = displayName?.components(separatedBy: " ") ?? []
        return components.count > 1 ? components.dropFirst().joined(separator: " ") : nil
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