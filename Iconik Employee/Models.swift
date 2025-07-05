import Foundation

struct SchoolItem: Identifiable, Hashable, Codable, Equatable {
    let id: String
    let name: String
    let address: String
}

struct PhotoshootNote: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var timestamp: Date
    var school: String  // The school name selected via dropdown.
    var noteText: String
    var photoURLs: [String] // URLs of photos taken for this note
    
    // For backward compatibility when decoding existing notes
    enum CodingKeys: String, CodingKey {
        case id, timestamp, school, noteText, photoURLs
    }
    
    init(id: UUID, timestamp: Date, school: String, noteText: String, photoURLs: [String] = []) {
        self.id = id
        self.timestamp = timestamp
        self.school = school
        self.noteText = noteText
        self.photoURLs = photoURLs
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        school = try container.decode(String.self, forKey: .school)
        noteText = try container.decode(String.self, forKey: .noteText)
        // Try to decode photoURLs, but use an empty array if the key doesn't exist
        photoURLs = (try? container.decode([String].self, forKey: .photoURLs)) ?? []
    }
}
