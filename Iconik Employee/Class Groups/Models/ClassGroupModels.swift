import Foundation

// MARK: - Class Group Job Model
struct ClassGroupJob: Identifiable, Codable, Hashable {
    var id: String
    var session_id: String
    var session_date: Date
    var school_id: String
    var school_name: String
    var organization_id: String
    var job_type: String // "classGroups" or "classCandids"
    var class_groups: [ClassGroup]
    var created_at: Date
    var updated_at: Date
    var created_by: String
    var last_modified_by: String

    // Backward compatibility computed properties
    var sessionId: String { session_id }
    var sessionDate: Date { session_date }
    var schoolId: String { school_id }
    var schoolName: String { school_name }
    var organizationId: String { organization_id }
    var jobType: String { job_type }
    var classGroups: [ClassGroup] {
        get { class_groups }
        set { class_groups = newValue }
    }
    var createdAt: Date { created_at }
    var updatedAt: Date { updated_at }
    var createdBy: String { created_by }
    var lastModifiedBy: String { last_modified_by }

    // MARK: - Initialization
    init(
        id: String = UUID().uuidString,
        sessionId: String = "",
        sessionDate: Date = Date(),
        schoolId: String = "",
        schoolName: String = "",
        organizationId: String = "",
        jobType: String = "classGroups",
        classGroups: [ClassGroup] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        createdBy: String = "",
        lastModifiedBy: String = ""
    ) {
        self.id = id
        self.session_id = sessionId
        self.session_date = sessionDate
        self.school_id = schoolId
        self.school_name = schoolName
        self.organization_id = organizationId
        self.job_type = jobType
        self.class_groups = classGroups
        self.created_at = createdAt
        self.updated_at = updatedAt
        self.created_by = createdBy
        self.last_modified_by = lastModifiedBy
    }

    // MARK: - Computed Properties
    var classGroupCount: Int {
        return class_groups.count
    }

    var totalImageCount: Int {
        return class_groups.reduce(0) { $0 + $1.imageCount }
    }

    var hasClassGroups: Bool {
        return !class_groups.isEmpty
    }
}

// MARK: - Class Group Model (Simplified)
struct ClassGroup: Identifiable, Codable, Hashable {
    var id: String
    var grade: String
    var teacher: String
    var image_numbers: String
    var notes: String

    // Backward compatibility
    var imageNumbers: String {
        get { image_numbers }
        set { image_numbers = newValue }
    }

    init(
        id: String = UUID().uuidString,
        grade: String = "",
        teacher: String = "",
        imageNumbers: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.grade = grade
        self.teacher = teacher
        self.image_numbers = imageNumbers
        self.notes = notes
    }

    // MARK: - Computed Properties
    var displayName: String {
        return "\(grade) - \(teacher)"
    }

    var hasImages: Bool {
        return !image_numbers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var imageCount: Int {
        let trimmed = image_numbers.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return trimmed.split(separator: ",").count
    }

    var imageNumbersArray: [String] {
        let trimmed = image_numbers.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        return trimmed.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

// MARK: - Common Grade Options
extension ClassGroup {
    static let commonGrades = [
        "Pre-K",
        "Kindergarten",
        "1st Grade",
        "2nd Grade",
        "3rd Grade",
        "4th Grade",
        "5th Grade",
        "6th Grade",
        "7th Grade",
        "8th Grade",
        "9th Grade",
        "10th Grade",
        "11th Grade",
        "12th Grade"
    ]

    static let shortGrades = [
        "Pre-K",
        "K",
        "1st",
        "2nd",
        "3rd",
        "4th",
        "5th",
        "6th",
        "7th",
        "8th",
        "9th",
        "10th",
        "11th",
        "12th"
    ]
}
