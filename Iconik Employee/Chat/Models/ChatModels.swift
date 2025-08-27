import Foundation
import FirebaseFirestore

// MARK: - Conversation Model
struct Conversation: Codable, Identifiable {
    let id: String
    let participants: [String]
    let type: ConversationType
    let name: String?
    let defaultName: String?
    let createdAt: Timestamp
    let lastActivity: Timestamp
    let lastMessage: LastMessage?
    var unreadCounts: [String: Int]
    var pinnedBy: [String]?
    
    // Resolved display name (populated by ChatManager)
    var resolvedDisplayName: String?
    
    enum ConversationType: String, Codable {
        case direct = "direct"
        case group = "group"
    }
    
    // Computed property to get display name
    var displayName: String {
        // Priority: custom name > resolved name > default name > fallback
        if let name = name, !name.isEmpty {
            return name
        }
        if let resolvedName = resolvedDisplayName, !resolvedName.isEmpty {
            return resolvedName
        }
        if let defaultName = defaultName, !defaultName.isEmpty {
            return defaultName
        }
        return type == .direct ? "Direct Message" : "Group Chat"
    }
    
    // Get unread count for specific user
    func unreadCount(for userId: String) -> Int {
        return unreadCounts[userId] ?? 0
    }
    
    // Check if conversation is pinned by user
    func isPinned(by userId: String) -> Bool {
        return pinnedBy?.contains(userId) ?? false
    }
    
    // Custom decoding to handle web app compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        participants = try container.decode([String].self, forKey: .participants)
        
        let typeString = try container.decode(String.self, forKey: .type)
        type = ConversationType(rawValue: typeString) ?? .direct
        
        name = try container.decodeIfPresent(String.self, forKey: .name)
        defaultName = try container.decodeIfPresent(String.self, forKey: .defaultName)
        createdAt = try container.decode(Timestamp.self, forKey: .createdAt)
        lastActivity = try container.decode(Timestamp.self, forKey: .lastActivity)
        lastMessage = try container.decodeIfPresent(LastMessage.self, forKey: .lastMessage)
        unreadCounts = try container.decodeIfPresent([String: Int].self, forKey: .unreadCounts) ?? [:]
        pinnedBy = try container.decodeIfPresent([String].self, forKey: .pinnedBy)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, participants, type, name, defaultName, createdAt, lastActivity, lastMessage, unreadCounts, pinnedBy
    }
    
    // Custom encoding to exclude resolvedDisplayName
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(participants, forKey: .participants)
        try container.encode(type.rawValue, forKey: .type)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(defaultName, forKey: .defaultName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastActivity, forKey: .lastActivity)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encode(unreadCounts, forKey: .unreadCounts)
        try container.encodeIfPresent(pinnedBy, forKey: .pinnedBy)
    }
}

// MARK: - Last Message Model
struct LastMessage: Codable {
    let text: String
    let senderId: String
    let timestamp: Timestamp
    
    // Format timestamp for display
    var formattedTime: String {
        let date = timestamp.dateValue()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Chat Message Model
struct ChatMessage: Codable, Identifiable {
    let id: String
    let senderId: String?  // Optional for system messages
    let senderName: String?  // Optional for system messages
    let text: String
    let type: MessageType
    let fileUrl: String?
    let timestamp: Timestamp
    let createdAt: Timestamp
    
    // System message fields
    let systemAction: String?
    let addedBy: String?
    let addedByName: String?
    let addedParticipants: [String]?
    let removedBy: String?
    let removedByName: String?
    let removedParticipant: String?
    let removedParticipantName: String?
    let leftUserId: String?
    let leftUserName: String?
    
    enum MessageType: String, Codable {
        case text = "text"
        case file = "file"
        case system = "system"
    }
    
    // Computed properties for UI
    var isTextMessage: Bool {
        return type == .text
    }
    
    var isSystemMessage: Bool {
        return type == .system
    }
    
    // Generate display text for system messages
    var systemMessageText: String {
        guard type == .system else { return text }
        
        switch systemAction {
        case "participants_added":
            let names = addedParticipants?.joined(separator: ", ") ?? "participants"
            return "\(addedByName ?? "Someone") added \(names) to the group"
        case "participant_removed":
            return "\(removedByName ?? "Someone") removed \(removedParticipantName ?? "a participant") from the group"
        case "participant_left":
            return "\(leftUserName ?? "Someone") left the group"
        default:
            return text
        }
    }
    
    var formattedTime: String {
        let date = timestamp.dateValue()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var formattedDate: String {
        let date = timestamp.dateValue()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - User Presence Model
struct UserPresence: Codable {
    let isOnline: Bool
    let lastSeen: Timestamp
    let conversationId: String?
    let isTyping: Bool?
    
    init(isOnline: Bool, lastSeen: Timestamp, conversationId: String? = nil, isTyping: Bool? = nil) {
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.conversationId = conversationId
        self.isTyping = isTyping
    }
}

// MARK: - Chat User Model (extends base User model for chat-specific needs)
struct ChatUser: Codable, Identifiable, Hashable {
    let id: String
    let organizationID: String
    let firstName: String
    let lastName: String
    let email: String
    let displayName: String?
    let photoURL: String?
    let isActive: Bool?
    
    // Computed display name
    var fullName: String {
        if let displayName = displayName, !displayName.isEmpty {
            return displayName
        }
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? email : name
    }
    
    // Get initials for avatar
    var initials: String {
        let firstInitial = firstName.first?.uppercased() ?? ""
        let lastInitial = lastName.first?.uppercased() ?? ""
        return "\(firstInitial)\(lastInitial)"
    }
}

// MARK: - Typing Indicator Model
struct TypingIndicator: Identifiable {
    let id: String
    let userId: String
    let userName: String
    let conversationId: String
    let timestamp: Date
    
    var isExpired: Bool {
        // Consider typing expired after 5 seconds
        return Date().timeIntervalSince(timestamp) > 5
    }
}

// MARK: - Cache Models
struct ConversationCacheData: Codable {
    let version: String
    let timestamp: Date
    let data: [Conversation]
}

struct MessageCacheData: Codable {
    let version: String
    let timestamp: Date
    let conversationId: String
    let data: [ChatMessage]
    let latestMessageTimestamp: Timestamp?
}

struct UserCacheData: Codable {
    let version: String
    let timestamp: Date
    let data: [ChatUser]
}

// MARK: - Helper Extensions
extension Timestamp {
    func toDate() -> Date {
        return self.dateValue()
    }
}

extension Date {
    func toTimestamp() -> Timestamp {
        return Timestamp(date: self)
    }
}

