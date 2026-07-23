import Foundation

// MARK: - Job Type Labels
// The three job types tracked by the Groups feature. The raw values are stored in
// class_group_jobs.job_type (shared with the web app — do not change existing ids).
// Rows always use the { grade, teacher, image_numbers, notes } keys; only the
// user-facing labels differ per type (clubs relabel grade→Club Name, teacher→Advisor).
enum ClassGroupJobType {
    static let classGroups = "classGroups"
    static let classCandids = "classCandids"
    static let clubs = "clubs"

    static let defaultType = classGroups
    static let all = [classGroups, classCandids, clubs]

    /// Rows written before job_type existed (and any unknown value) bucket into class groups.
    static func normalize(_ rawType: String?) -> String {
        guard let rawType, all.contains(rawType) else { return defaultType }
        return rawType
    }

    /// "Class Groups" / "Class Candids" / "Clubs"
    static func displayName(_ jobType: String?) -> String {
        switch normalize(jobType) {
        case classCandids: return "Class Candids"
        case clubs: return "Clubs"
        default: return "Class Groups"
        }
    }

    /// "Class Group" / "Class Candid" / "Club" — singular, title case
    static func singularTitle(_ jobType: String?) -> String {
        switch normalize(jobType) {
        case classCandids: return "Class Candid"
        case clubs: return "Club"
        default: return "Class Group"
        }
    }

    /// "class group" / "class candid" / "club" — singular, lowercase
    static func rowNoun(_ jobType: String?) -> String {
        singularTitle(jobType).lowercased()
    }

    /// "class groups" / "class candids" / "clubs" — plural, lowercase
    static func rowNounPlural(_ jobType: String?) -> String {
        displayName(jobType).lowercased()
    }

    /// Row-count noun, matching the web job card: "group" / "group" / "club"
    static func countNoun(_ jobType: String?) -> String {
        normalize(jobType) == clubs ? "club" : "group"
    }

    /// "groups" / "groups" / "clubs"
    static func countNounPlural(_ jobType: String?) -> String {
        countNoun(jobType) + "s"
    }

    /// Dashboard badge: "Groups" / "Candids" / "Clubs"
    static func badgeLabel(_ jobType: String?) -> String {
        switch normalize(jobType) {
        case classCandids: return "Candids"
        case clubs: return "Clubs"
        default: return "Groups"
        }
    }

    /// Form section noun: "Class" / "Candid" / "Club" (used as "<noun> Information")
    static func formNoun(_ jobType: String?) -> String {
        switch normalize(jobType) {
        case classCandids: return "Candid"
        case clubs: return "Club"
        default: return "Class"
        }
    }

    /// Label for the row's `grade` field: "Grade" / "Grade" / "Club Name"
    static func primaryFieldLabel(_ jobType: String?) -> String {
        normalize(jobType) == clubs ? "Club Name" : "Grade"
    }

    /// Label for the row's `teacher` field: "Teacher Name" / "Teacher Name" / "Advisor Name"
    static func secondaryFieldLabel(_ jobType: String?) -> String {
        normalize(jobType) == clubs ? "Advisor Name" : "Teacher Name"
    }

    /// The grade suggestions menu only makes sense for grade-based types.
    static func showsGradeSuggestions(_ jobType: String?) -> Bool {
        normalize(jobType) != clubs
    }

    /// Jobs-list empty-state icon
    static func listEmptyIcon(_ jobType: String?) -> String {
        switch normalize(jobType) {
        case classCandids: return "camera"
        case clubs: return "person.2"
        default: return "person.3"
        }
    }

    /// Job-detail empty-state icon
    static func detailEmptyIcon(_ jobType: String?) -> String {
        switch normalize(jobType) {
        case classGroups: return "camera.viewfinder"
        default: return "camera"
        }
    }
}

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
    var notes: String?  // Job-level notes
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
        notes: String? = nil,
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
        self.notes = notes
        self.created_at = createdAt
        self.updated_at = updatedAt
        self.created_by = createdBy
        self.last_modified_by = lastModifiedBy
    }

    // MARK: - Decoding
    // Tolerant decode for the cross-app fields: every list read decodes the whole
    // array at once, so one row with a NULL session_id (or an unknown writer's
    // missing job_type) must not blank the entire feature. "" is the established
    // no-session convention both apps write; unknown job_type buckets to the default.
    enum CodingKeys: String, CodingKey {
        case id, session_id, session_date, school_id, school_name, organization_id
        case job_type, class_groups, notes, created_at, updated_at, created_by, last_modified_by
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        session_id = try container.decodeIfPresent(String.self, forKey: .session_id) ?? ""
        session_date = try container.decode(Date.self, forKey: .session_date)
        school_id = try container.decodeIfPresent(String.self, forKey: .school_id) ?? ""
        school_name = try container.decodeIfPresent(String.self, forKey: .school_name) ?? ""
        organization_id = try container.decode(String.self, forKey: .organization_id)
        job_type = try container.decodeIfPresent(String.self, forKey: .job_type) ?? ClassGroupJobType.defaultType
        class_groups = try container.decodeIfPresent([ClassGroup].self, forKey: .class_groups) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        created_at = try container.decode(Date.self, forKey: .created_at)
        updated_at = try container.decode(Date.self, forKey: .updated_at)
        created_by = try container.decodeIfPresent(String.self, forKey: .created_by) ?? ""
        last_modified_by = try container.decodeIfPresent(String.self, forKey: .last_modified_by) ?? ""
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

    // Tolerant decode for the value fields, same contract as ClassGroupJob:
    // list reads decode whole arrays, so one malformed row must not blank the
    // feature. Identity (`id`) stays strict — a row without it can't be edited
    // or deleted, and both apps always write it.
    enum CodingKeys: String, CodingKey {
        case id, grade, teacher, image_numbers, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        grade = try container.decodeIfPresent(String.self, forKey: .grade) ?? ""
        teacher = try container.decodeIfPresent(String.self, forKey: .teacher) ?? ""
        image_numbers = try container.decodeIfPresent(String.self, forKey: .image_numbers) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
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
