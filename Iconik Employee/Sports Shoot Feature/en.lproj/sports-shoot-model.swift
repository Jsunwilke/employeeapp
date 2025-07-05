import Foundation
import Firebase
import FirebaseFirestore

// Main sports shoot model
struct SportsShoot: Identifiable, Codable, Equatable {
    var id: String
    var schoolName: String
    var sportName: String
    var shootDate: Date
    var location: String
    var photographer: String
    var roster: [RosterEntry]
    var groupImages: [GroupImage]
    var additionalNotes: String
    var organizationID: String
    var createdAt: Date
    var updatedAt: Date
    
    init(id: String = UUID().uuidString,
         schoolName: String = "",
         sportName: String = "",
         shootDate: Date = Date(),
         location: String = "",
         photographer: String = "",
         roster: [RosterEntry] = [],
         groupImages: [GroupImage] = [],
         additionalNotes: String = "",
         organizationID: String = "",
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.schoolName = schoolName
        self.sportName = sportName
        self.shootDate = shootDate
        self.location = location
        self.photographer = photographer
        self.roster = roster
        self.groupImages = groupImages
        self.additionalNotes = additionalNotes
        self.organizationID = organizationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Adding a custom Codable implementation to handle optional fields and field mapping
    enum CodingKeys: String, CodingKey {
        case id, schoolName, sportName, shootDate, location, photographer
        case roster, groupImages, additionalNotes, organizationID
        case createdAt, updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        schoolName = try container.decodeIfPresent(String.self, forKey: .schoolName) ?? ""
        sportName = try container.decodeIfPresent(String.self, forKey: .sportName) ?? ""
        shootDate = try container.decodeIfPresent(Date.self, forKey: .shootDate) ?? Date()
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        photographer = try container.decodeIfPresent(String.self, forKey: .photographer) ?? ""
        roster = try container.decodeIfPresent([RosterEntry].self, forKey: .roster) ?? []
        groupImages = try container.decodeIfPresent([GroupImage].self, forKey: .groupImages) ?? []
        additionalNotes = try container.decodeIfPresent(String.self, forKey: .additionalNotes) ?? ""
        organizationID = try container.decodeIfPresent(String.self, forKey: .organizationID) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
    
    // Create from a Firestore document
    init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        self.id = document.documentID
        self.schoolName = data["schoolName"] as? String ?? "Unknown School"
        self.sportName = data["sportName"] as? String ?? "Unknown Sport"
        self.shootDate = (data["shootDate"] as? Timestamp)?.dateValue() ?? Date()
        self.location = data["location"] as? String ?? ""
        self.photographer = data["photographer"] as? String ?? ""
        self.additionalNotes = data["additionalNotes"] as? String ?? ""
        self.organizationID = data["organizationID"] as? String ?? ""
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        
        // Parse roster entries with field mapping
        self.roster = []
        if let rosterData = data["roster"] as? [[String: Any]] {
            for entryData in rosterData {
                if let entry = RosterEntry(from: entryData) {
                    self.roster.append(entry)
                }
            }
        }
        
        // Parse group images
        self.groupImages = []
        if let groupData = data["groupImages"] as? [[String: Any]] {
            for groupDict in groupData {
                if let group = GroupImage(from: groupDict) {
                    self.groupImages.append(group)
                }
            }
        }
    }
    
    // Convert to dictionary for Firestore
    func toDictionary() -> [String: Any] {
        let rosterDicts = roster.map { $0.toDictionary() }
        let groupDicts = groupImages.map { $0.toDictionary() }
        
        var result: [String: Any] = [
            "schoolName": schoolName,
            "sportName": sportName,
            "shootDate": Timestamp(date: shootDate),
            "location": location,
            "photographer": photographer,
            "roster": rosterDicts,
            "groupImages": groupDicts,
            "additionalNotes": additionalNotes,
            "organizationID": organizationID,
            "updatedAt": Timestamp(date: Date())
        ]
        
        // Set created date if it's a new document
        if createdAt != Date(timeIntervalSince1970: 0) {
            result["createdAt"] = Timestamp(date: createdAt)
        } else {
            result["createdAt"] = Timestamp(date: Date())
        }
        
        return result
    }
    
    // Helper method to check for equality
    static func == (lhs: SportsShoot, rhs: SportsShoot) -> Bool {
        return lhs.id == rhs.id &&
               lhs.schoolName == rhs.schoolName &&
               lhs.sportName == rhs.sportName &&
               lhs.location == rhs.location &&
               lhs.photographer == rhs.photographer &&
               lhs.additionalNotes == rhs.additionalNotes &&
               lhs.organizationID == rhs.organizationID &&
               Calendar.current.isDate(lhs.shootDate, inSameDayAs: rhs.shootDate) &&
               lhs.roster.count == rhs.roster.count &&
               lhs.groupImages.count == rhs.groupImages.count
    }
}
