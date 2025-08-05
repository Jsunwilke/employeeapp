import Foundation
import FirebaseFirestore

// MARK: - Class Group Job Model
struct ClassGroupJob: Identifiable, Codable, Hashable {
    var id: String
    var sessionId: String
    var sessionDate: Date
    var schoolId: String
    var schoolName: String
    var organizationId: String
    var jobType: String // "classGroups" or "classCandids"
    var classGroups: [ClassGroup]
    var createdAt: Date
    var updatedAt: Date
    var createdBy: String
    var lastModifiedBy: String
    
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
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.schoolId = schoolId
        self.schoolName = schoolName
        self.organizationId = organizationId
        self.jobType = jobType
        self.classGroups = classGroups
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.lastModifiedBy = lastModifiedBy
    }
    
    // MARK: - Firestore Conversion
    init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        self.id = document.documentID
        self.sessionId = data["sessionId"] as? String ?? ""
        self.sessionDate = (data["sessionDate"] as? Timestamp)?.dateValue() ?? Date()
        self.schoolId = data["schoolId"] as? String ?? ""
        self.schoolName = data["schoolName"] as? String ?? ""
        self.organizationId = data["organizationId"] as? String ?? ""
        self.jobType = data["jobType"] as? String ?? "classGroups"
        
        // Parse class groups array
        if let groupsData = data["classGroups"] as? [[String: Any]] {
            self.classGroups = groupsData.compactMap { ClassGroup(from: $0) }
        } else {
            self.classGroups = []
        }
        
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        self.createdBy = data["createdBy"] as? String ?? ""
        self.lastModifiedBy = data["lastModifiedBy"] as? String ?? ""
    }
    
    func toFirestoreData() -> [String: Any] {
        return [
            "sessionId": sessionId,
            "sessionDate": Timestamp(date: sessionDate),
            "schoolId": schoolId,
            "schoolName": schoolName,
            "organizationId": organizationId,
            "jobType": jobType,
            "classGroups": classGroups.map { $0.toFirestoreData() },
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "createdBy": createdBy,
            "lastModifiedBy": lastModifiedBy
        ]
    }
    
    // MARK: - Computed Properties
    var classGroupCount: Int {
        return classGroups.count
    }
    
    var totalImageCount: Int {
        return classGroups.reduce(0) { $0 + $1.imageCount }
    }
    
    var hasClassGroups: Bool {
        return !classGroups.isEmpty
    }
}

// MARK: - Class Group Model (Simplified)
struct ClassGroup: Identifiable, Codable, Hashable {
    var id: String
    var grade: String
    var teacher: String
    var imageNumbers: String
    var notes: String
    
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
        self.imageNumbers = imageNumbers
        self.notes = notes
    }
    
    // MARK: - Firestore Conversion
    init?(from dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String else { return nil }
        
        self.id = id
        self.grade = dictionary["grade"] as? String ?? ""
        self.teacher = dictionary["teacher"] as? String ?? ""
        self.imageNumbers = dictionary["imageNumbers"] as? String ?? ""
        self.notes = dictionary["notes"] as? String ?? ""
    }
    
    func toFirestoreData() -> [String: Any] {
        return [
            "id": id,
            "grade": grade,
            "teacher": teacher,
            "imageNumbers": imageNumbers,
            "notes": notes
        ]
    }
    
    // MARK: - Computed Properties
    var displayName: String {
        return "\(grade) - \(teacher)"
    }
    
    var hasImages: Bool {
        return !imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var imageCount: Int {
        let trimmed = imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return trimmed.split(separator: ",").count
    }
    
    var imageNumbersArray: [String] {
        let trimmed = imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines)
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