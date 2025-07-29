import Foundation

enum TimeOffStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case underReview = "under_review"
    case approved = "approved"
    case denied = "denied"
    case cancelled = "cancelled"
    
    // Display string for UI
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .underReview:
            return "In Review"
        case .approved:
            return "Approved"
        case .denied:
            return "Denied"
        case .cancelled:
            return "Cancelled"
        }
    }
    
    // Icon for UI representation
    var systemImageName: String {
        switch self {
        case .pending:
            return "clock.fill"
        case .underReview:
            return "magnifyingglass.circle.fill"
        case .approved:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .cancelled:
            return "minus.circle.fill"
        }
    }
    
    // Color for UI representation
    var colorName: String {
        switch self {
        case .pending:
            return "orange"
        case .underReview:
            return "blue"
        case .approved:
            return "green"
        case .denied:
            return "red"
        case .cancelled:
            return "gray"
        }
    }
    
    // Check if status allows editing
    var isEditable: Bool {
        return self == .pending || self == .underReview
    }
    
    // Check if status allows cancellation
    var isCancellable: Bool {
        return self == .pending || self == .underReview
    }
    
    // Sort order for UI display
    var sortOrder: Int {
        switch self {
        case .pending:
            return 0
        case .underReview:
            return 1
        case .approved:
            return 2
        case .denied:
            return 3
        case .cancelled:
            return 4
        }
    }
    
    // Filter options for UI
    static var filterOptions: [TimeOffStatus] {
        return [.pending, .underReview, .approved, .denied, .cancelled]
    }
}