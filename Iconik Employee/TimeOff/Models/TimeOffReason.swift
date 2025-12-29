import Foundation

enum TimeOffReason: String, CaseIterable, Codable {
    case vacation = "vacation"
    case sick = "sick"
    case personal = "personal"
    case emergency = "emergency"
    case bereavement = "bereavement"
    case other = "other"

    // Display string for UI
    var displayName: String {
        switch self {
        case .vacation:
            return "Vacation"
        case .sick:
            return "Sick Leave"
        case .personal:
            return "Personal Day"
        case .emergency:
            return "Family Emergency"
        case .bereavement:
            return "Bereavement"
        case .other:
            return "Other"
        }
    }
    
    // Icon for UI representation
    var systemImageName: String {
        switch self {
        case .vacation:
            return "sun.max.fill"
        case .sick:
            return "cross.fill"
        case .personal:
            return "person.fill"
        case .emergency:
            return "exclamationmark.triangle.fill"
        case .bereavement:
            return "heart.fill"
        case .other:
            return "ellipsis.circle.fill"
        }
    }

    // Color for UI representation
    var colorName: String {
        switch self {
        case .vacation:
            return "blue"
        case .sick:
            return "red"
        case .personal:
            return "green"
        case .emergency:
            return "orange"
        case .bereavement:
            return "purple"
        case .other:
            return "gray"
        }
    }
    
    // Helper to get all reasons for picker
    static var allReasons: [TimeOffReason] {
        return TimeOffReason.allCases
    }
}