import Foundation
import FirebaseFirestore

// MARK: - Yearbook Shoot List Model
struct YearbookShootList: Identifiable, Codable {
    @DocumentID var id: String?
    let organizationId: String
    let schoolId: String
    let schoolName: String
    let schoolYear: String
    let startDate: Date
    let endDate: Date
    let isActive: Bool
    let copiedFromId: String?
    var completedCount: Int
    let totalCount: Int
    var items: [YearbookItem]
    let createdAt: Date
    var updatedAt: Date
    
    // Computed properties
    var completionPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount) * 100
    }
    
    var isCompleted: Bool {
        return completedCount == totalCount && totalCount > 0
    }
}

// MARK: - Yearbook Item Model
struct YearbookItem: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let category: String
    let required: Bool
    var completed: Bool
    var completedDate: Date?
    var completedBySession: String?
    var photographerId: String?
    var photographerName: String?
    var imageNumbers: [String]?
    var notes: String?
    let order: Int
    
    // Default initializer for creating new items
    init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        category: String,
        required: Bool = true,
        completed: Bool = false,
        completedDate: Date? = nil,
        completedBySession: String? = nil,
        photographerId: String? = nil,
        photographerName: String? = nil,
        imageNumbers: [String]? = nil,
        notes: String? = nil,
        order: Int
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.required = required
        self.completed = completed
        self.completedDate = completedDate
        self.completedBySession = completedBySession
        self.photographerId = photographerId
        self.photographerName = photographerName
        self.imageNumbers = imageNumbers
        self.notes = notes
        self.order = order
    }
}

// MARK: - Session Context for Integration
struct YearbookSessionContext {
    let sessionId: String
    let photographerId: String
    let photographerName: String
    let sessionDate: Date
}

// MARK: - Helper Functions
extension YearbookShootList {
    /// Calculate the current school year based on a given date
    static func getCurrentSchoolYear(date: Date = Date()) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        
        // School year starts in August (month 8)
        if month >= 8 {
            // August-December: return current year - next year
            return "\(year)-\(year + 1)"
        } else {
            // January-July: return previous year - current year
            return "\(year - 1)-\(year)"
        }
    }
    
    /// Get the start and end dates for a school year
    static func getSchoolYearDates(schoolYear: String) -> (start: Date, end: Date)? {
        let components = schoolYear.split(separator: "-")
        guard components.count == 2,
              let startYear = Int(components[0]),
              let endYear = Int(components[1]) else {
            return nil
        }
        
        let calendar = Calendar.current
        var startComponents = DateComponents()
        startComponents.year = startYear
        startComponents.month = 8  // August
        startComponents.day = 1
        
        var endComponents = DateComponents()
        endComponents.year = endYear
        endComponents.month = 7  // July
        endComponents.day = 31
        
        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(from: endComponents) else {
            return nil
        }
        
        return (startDate, endDate)
    }
    
    /// Group items by category
    func itemsByCategory() -> [(category: String, items: [YearbookItem])] {
        let grouped = Dictionary(grouping: items) { $0.category }
        return grouped.sorted { $0.key < $1.key }
            .map { (category: $0.key, items: $0.value.sorted { $0.order < $1.order }) }
    }
    
    /// Get items filtered by completion status
    func items(completed: Bool) -> [YearbookItem] {
        return items.filter { $0.completed == completed }
    }
    
    /// Get required items only
    var requiredItems: [YearbookItem] {
        return items.filter { $0.required }
    }
    
    /// Get completion stats by category
    func completionStatsByCategory() -> [(category: String, completed: Int, total: Int)] {
        let grouped = itemsByCategory()
        return grouped.map { category, items in
            let completed = items.filter { $0.completed }.count
            return (category: category, completed: completed, total: items.count)
        }
    }
}

// MARK: - Firestore Extensions
extension YearbookShootList {
    /// Convert to Firestore data
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "organizationId": organizationId,
            "schoolId": schoolId,
            "schoolName": schoolName,
            "schoolYear": schoolYear,
            "startDate": Timestamp(date: startDate),
            "endDate": Timestamp(date: endDate),
            "isActive": isActive,
            "completedCount": completedCount,
            "totalCount": totalCount,
            "items": items.map { $0.toFirestoreData() },
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        if let copiedFromId = copiedFromId {
            data["copiedFromId"] = copiedFromId
        }
        
        return data
    }
}

extension YearbookItem {
    /// Convert to Firestore data
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "name": name,
            "category": category,
            "required": required,
            "completed": completed,
            "order": order
        ]
        
        // Optional fields
        if let description = description {
            data["description"] = description
        }
        if let completedDate = completedDate {
            data["completedDate"] = Timestamp(date: completedDate)
        }
        if let completedBySession = completedBySession {
            data["completedBySession"] = completedBySession
        }
        if let photographerId = photographerId {
            data["photographerId"] = photographerId
        }
        if let photographerName = photographerName {
            data["photographerName"] = photographerName
        }
        if let imageNumbers = imageNumbers, !imageNumbers.isEmpty {
            data["imageNumbers"] = imageNumbers
        }
        if let notes = notes {
            data["notes"] = notes
        }
        
        return data
    }
}

// MARK: - Error Types
enum YearbookError: LocalizedError {
    case listNotFound
    case itemNotFound
    case invalidSchoolYear
    case permissionDenied
    case networkError
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .listNotFound:
            return "Yearbook shoot list not found"
        case .itemNotFound:
            return "Item not found in the list"
        case .invalidSchoolYear:
            return "Invalid school year format"
        case .permissionDenied:
            return "You don't have permission to access this list"
        case .networkError:
            return "Network connection error"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}