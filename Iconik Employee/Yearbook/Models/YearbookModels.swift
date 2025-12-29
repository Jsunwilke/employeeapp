import Foundation

// MARK: - Yearbook Shoot List Model (Supabase)
struct YearbookShootList: Identifiable, Codable {
    let id: String
    let organization_id: String
    let school_id: String
    let school_name: String
    let school_year: String
    let start_date: Date
    let end_date: Date
    let is_active: Bool
    let copied_from_id: String?
    var completed_count: Int
    let total_count: Int
    var items: [YearbookItem]
    let created_at: Date
    var updated_at: Date

    // Backward compatibility computed properties
    var organizationId: String { organization_id }
    var schoolId: String { school_id }
    var schoolName: String { school_name }
    var schoolYear: String { school_year }
    var startDate: Date { start_date }
    var endDate: Date { end_date }
    var isActive: Bool { is_active }
    var copiedFromId: String? { copied_from_id }
    var completedCount: Int {
        get { completed_count }
        set { completed_count = newValue }
    }
    var totalCount: Int { total_count }
    var createdAt: Date { created_at }
    var updatedAt: Date {
        get { updated_at }
        set { updated_at = newValue }
    }

    // Computed properties
    var completionPercentage: Double {
        guard total_count > 0 else { return 0 }
        return Double(completed_count) / Double(total_count) * 100
    }

    var isCompleted: Bool {
        return completed_count == total_count && total_count > 0
    }

    // Initializer with camelCase parameters for backward compatibility
    init(
        id: String = UUID().uuidString,
        organizationId: String,
        schoolId: String,
        schoolName: String,
        schoolYear: String,
        startDate: Date,
        endDate: Date,
        isActive: Bool,
        copiedFromId: String? = nil,
        completedCount: Int,
        totalCount: Int,
        items: [YearbookItem],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.organization_id = organizationId
        self.school_id = schoolId
        self.school_name = schoolName
        self.school_year = schoolYear
        self.start_date = startDate
        self.end_date = endDate
        self.is_active = isActive
        self.copied_from_id = copiedFromId
        self.completed_count = completedCount
        self.total_count = totalCount
        self.items = items
        self.created_at = createdAt
        self.updated_at = updatedAt
    }

    // Initializer with snake_case parameters for database operations
    init(
        id: String = UUID().uuidString,
        organization_id: String,
        school_id: String,
        school_name: String,
        school_year: String,
        start_date: Date,
        end_date: Date,
        is_active: Bool,
        copied_from_id: String? = nil,
        completed_count: Int,
        total_count: Int,
        items: [YearbookItem],
        created_at: Date,
        updated_at: Date
    ) {
        self.id = id
        self.organization_id = organization_id
        self.school_id = school_id
        self.school_name = school_name
        self.school_year = school_year
        self.start_date = start_date
        self.end_date = end_date
        self.is_active = is_active
        self.copied_from_id = copied_from_id
        self.completed_count = completed_count
        self.total_count = total_count
        self.items = items
        self.created_at = created_at
        self.updated_at = updated_at
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
    var completed_date: Date?
    var completed_by_session: String?
    var photographer_id: String?
    var photographer_name: String?
    var image_numbers: [String]?
    var notes: String?
    let order: Int

    // Backward compatibility
    var completedDate: Date? {
        get { completed_date }
        set { completed_date = newValue }
    }
    var completedBySession: String? {
        get { completed_by_session }
        set { completed_by_session = newValue }
    }
    var photographerId: String? {
        get { photographer_id }
        set { photographer_id = newValue }
    }
    var photographerName: String? {
        get { photographer_name }
        set { photographer_name = newValue }
    }
    var imageNumbers: [String]? {
        get { image_numbers }
        set { image_numbers = newValue }
    }

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
        self.completed_date = completedDate
        self.completed_by_session = completedBySession
        self.photographer_id = photographerId
        self.photographer_name = photographerName
        self.image_numbers = imageNumbers
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
