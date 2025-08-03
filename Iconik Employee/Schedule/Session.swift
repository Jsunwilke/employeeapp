import Foundation
import FirebaseFirestore

struct Session: Identifiable, Equatable, Hashable {
    let id: String
    let employeeName: String
    let position: String
    let schoolName: String
    let startDate: Date?
    let endDate: Date?
    let description: String?
    let location: String?
    let organizationID: String
    let createdAt: Date
    let updatedAt: Date
    let isPublished: Bool
    
    // Raw fields from Firestore
    let date: String?
    let startTime: String?
    let endTime: String?
    let sessionType: [String]?
    let status: String?
    let schoolId: String?
    let sessionColor: String?  // Hex color string
    let photographers: [[String: Any]]
    
    init(id: String, data: [String: Any]) {
        self.id = id
        
        // Debug: Log all fields in the data
        print("📦 Session '\(id)' data fields: \(data.keys.sorted())")
        
        // Parse raw Firestore fields
        self.date = data["date"] as? String
        self.startTime = data["startTime"] as? String
        self.endTime = data["endTime"] as? String
        self.sessionType = data["sessionTypes"] as? [String]
        print("🏷️ Session '\(self.id)' sessionTypes: \(self.sessionType ?? [])")
        self.status = data["status"] as? String
        self.schoolId = data["schoolId"] as? String
        self.sessionColor = data["sessionColor"] as? String
        self.schoolName = data["schoolName"] as? String ?? ""
        self.photographers = data["photographers"] as? [[String: Any]] ?? []
        self.organizationID = data["organizationID"] as? String ?? ""
        self.isPublished = data["isPublished"] as? Bool ?? true // Default to true for backward compatibility
        
        // Extract employeeName from photographers array (use first photographer)
        if let firstPhotographer = self.photographers.first,
           let name = firstPhotographer["name"] as? String {
            self.employeeName = name
        } else {
            self.employeeName = ""
        }
        
        // Set position based on first sessionType or default
        self.position = self.sessionType?.first ?? "Photographer"
        
        // Description from session-level notes field, or fallback to sessionType
        if let sessionNotes = data["notes"] as? String, !sessionNotes.isEmpty {
            self.description = sessionNotes
        } else if let sessionDescription = data["description"] as? String, !sessionDescription.isEmpty {
            self.description = sessionDescription
        } else {
            self.description = self.sessionType?.first
        }
        
        // Location - might need to fetch from schoolId later
        self.location = nil
        
        // Convert date + time strings to Date objects
        self.startDate = Self.parseDateTime(date: self.date, time: self.startTime)
        self.endDate = Self.parseDateTime(date: self.date, time: self.endTime)
        
        if let createdTimestamp = data["createdAt"] as? Timestamp {
            self.createdAt = createdTimestamp.dateValue()
        } else {
            self.createdAt = Date()
        }
        
        if let updatedTimestamp = data["updatedAt"] as? Timestamp {
            self.updatedAt = updatedTimestamp.dateValue()
        } else {
            self.updatedAt = Date()
        }
    }
    
    init(id: String = UUID().uuidString,
         employeeName: String,
         position: String,
         schoolName: String,
         startDate: Date?,
         endDate: Date?,
         description: String? = nil,
         location: String? = nil,
         organizationID: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         isPublished: Bool = true) {
        self.id = id
        self.employeeName = employeeName
        self.position = position
        self.schoolName = schoolName
        self.startDate = startDate
        self.endDate = endDate
        self.description = description
        self.location = location
        self.organizationID = organizationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPublished = isPublished
        
        // Set default values for raw Firestore fields
        self.date = nil
        self.startTime = nil
        self.endTime = nil
        self.sessionType = [position]
        self.status = "scheduled"
        self.schoolId = nil
        self.sessionColor = nil
        self.photographers = []
    }
    
    // Helper method to parse date + time strings into Date objects
    static func parseDateTime(date: String?, time: String?) -> Date? {
        print("🕐 parseDateTime called with date: '\(date ?? "nil")', time: '\(time ?? "nil")'")
        
        guard let dateStr = date, let timeStr = time else { 
            print("🕐 parseDateTime: missing date or time - returning nil")
            return nil 
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone.current
        
        // Combine date and time strings
        let dateTimeString = "\(dateStr) \(timeStr)"
        print("🕐 parseDateTime: trying to parse '\(dateTimeString)'")
        
        let result = dateFormatter.date(from: dateTimeString)
        print("🕐 parseDateTime: result = \(result?.description ?? "nil")")
        
        return result
    }
    
    // MARK: - Helper Methods
    
    /// Check if a user ID is assigned as a photographer for this session
    func isUserAssigned(userID: String) -> Bool {
        print("🔍 Checking if user \(userID) is assigned to session \(schoolName)")
        print("🔍 Photographers array: \(photographers)")
        
        for (index, photographer) in photographers.enumerated() {
            let photographerID = photographer["id"] as? String
            print("🔍 Photographer \(index): id = '\(photographerID ?? "nil")', type = \(type(of: photographer["id"]))")
            
            if photographerID == userID {
                print("✅ Found match for user \(userID)")
                return true
            }
        }
        
        print("❌ No match found for user \(userID)")
        return false
    }
    
    /// Get all photographer IDs for this session
    func getPhotographerIDs() -> [String] {
        return photographers.compactMap { photographer in
            photographer["id"] as? String
        }
    }
    
    /// Get all photographer names for this session
    func getPhotographerNames() -> [String] {
        return photographers.compactMap { photographer in
            photographer["name"] as? String
        }
    }
    
    /// Get photographer info (name and notes) for a specific user ID
    func getPhotographerInfo(for userID: String) -> (name: String, notes: String)? {
        guard let photographer = photographers.first(where: { ($0["id"] as? String) == userID }) else {
            return nil
        }
        
        let name = photographer["name"] as? String ?? ""
        let notes = photographer["notes"] as? String ?? ""
        return (name: name, notes: notes)
    }
    
    var toDictionary: [String: Any] {
        var dict: [String: Any] = [
            "employeeName": employeeName,
            "position": position,
            "schoolName": schoolName,
            "organizationID": organizationID,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        if let startDate = startDate {
            dict["startDate"] = Timestamp(date: startDate)
        }
        
        if let endDate = endDate {
            dict["endDate"] = Timestamp(date: endDate)
        }
        
        if let description = description {
            dict["description"] = description
        }
        
        if let location = location {
            dict["location"] = location
        }
        
        return dict
    }
    
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id &&
        lhs.employeeName == rhs.employeeName &&
        lhs.position == rhs.position &&
        lhs.schoolName == rhs.schoolName &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate == rhs.endDate &&
        lhs.description == rhs.description &&
        lhs.location == rhs.location &&
        lhs.organizationID == rhs.organizationID &&
        lhs.date == rhs.date &&
        lhs.startTime == rhs.startTime &&
        lhs.endTime == rhs.endTime &&
        lhs.isPublished == rhs.isPublished
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(employeeName)
        hasher.combine(position)
        hasher.combine(schoolName)
        hasher.combine(startDate)
        hasher.combine(endDate)
        hasher.combine(description)
        hasher.combine(location)
        hasher.combine(organizationID)
        hasher.combine(date)
        hasher.combine(startTime)
        hasher.combine(endTime)
        hasher.combine(isPublished)
    }
}