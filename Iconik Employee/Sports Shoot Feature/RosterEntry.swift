import Foundation
import Firebase

// Model for roster entry (individual subject)
struct RosterEntry: Identifiable, Codable, Hashable, Equatable {
    var id: String
    var lastName: String     // Maps to "Name" in Captura
    var firstName: String    // Maps to "Subject ID" in Captura
    var teacher: String      // Maps to "Special" in Captura
    var group: String        // Maps to "Sport/Team" in Captura
    var email: String
    var phone: String
    var imageNumbers: String
    var notes: String
    
    init(id: String = UUID().uuidString,
         lastName: String = "",
         firstName: String = "",
         teacher: String = "",
         group: String = "",
         email: String = "",
         phone: String = "",
         imageNumbers: String = "",
         notes: String = "") {
        self.id = id
        self.lastName = lastName
        self.firstName = firstName
        self.teacher = teacher
        self.group = group
        self.email = email
        self.phone = phone
        self.imageNumbers = imageNumbers
        self.notes = notes
    }
    
    // Create from a dictionary - handle field mapping
    init?(from dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String else {
            return nil
        }
        
        self.id = id
        self.lastName = dictionary["lastName"] as? String ?? ""      // Maps to "Name" in Captura
        self.firstName = dictionary["firstName"] as? String ?? ""    // Maps to "Subject ID" in Captura
        self.teacher = dictionary["teacher"] as? String ?? ""        // Maps to "Special" in Captura
        self.group = dictionary["group"] as? String ?? ""            // Maps to "Sport/Team" in Captura
        self.email = dictionary["email"] as? String ?? ""
        self.phone = dictionary["phone"] as? String ?? ""
        self.imageNumbers = dictionary["imageNumbers"] as? String ?? ""
        self.notes = dictionary["notes"] as? String ?? ""
    }
    
    // Convert to dictionary for Firestore
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "lastName": lastName,          // Maps to "Name" in Captura
            "firstName": firstName,        // Maps to "Subject ID" in Captura
            "teacher": teacher,            // Maps to "Special" in Captura
            "group": group,                // Maps to "Sport/Team" in Captura
            "email": email,
            "phone": phone,
            "imageNumbers": imageNumbers,
            "notes": notes
        ]
    }
    
    // Check if entries are equal based on content
    static func == (lhs: RosterEntry, rhs: RosterEntry) -> Bool {
        return lhs.id == rhs.id &&
               lhs.lastName == rhs.lastName &&
               lhs.firstName == rhs.firstName &&
               lhs.teacher == rhs.teacher &&
               lhs.group == rhs.group &&
               lhs.email == rhs.email &&
               lhs.phone == rhs.phone &&
               lhs.imageNumbers == rhs.imageNumbers &&
               lhs.notes == rhs.notes
    }
    
    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(lastName)
        hasher.combine(firstName)
        hasher.combine(teacher)
        hasher.combine(group)
        hasher.combine(email)
        hasher.combine(phone)
        hasher.combine(imageNumbers)
        hasher.combine(notes)
    }
}