import Foundation

enum TimeOffReason: String, CaseIterable, Codable {
    case vacation = "Vacation"
    case sickLeave = "Sick Leave"
    case personalDay = "Personal Day"
    case familyEmergency = "Family Emergency"
    case medicalAppointment = "Medical Appointment"
    case other = "Other"
    
    // Display string for UI
    var displayName: String {
        return rawValue
    }
    
    // Icon for UI representation
    var systemImageName: String {
        switch self {
        case .vacation:
            return "sun.max.fill"
        case .sickLeave:
            return "cross.fill"
        case .personalDay:
            return "person.fill"
        case .familyEmergency:
            return "house.fill"
        case .medicalAppointment:
            return "stethoscope"
        case .other:
            return "ellipsis.circle.fill"
        }
    }
    
    // Color for UI representation
    var colorName: String {
        switch self {
        case .vacation:
            return "blue"
        case .sickLeave:
            return "red"
        case .personalDay:
            return "green"
        case .familyEmergency:
            return "orange"
        case .medicalAppointment:
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