import Foundation

// MARK: - Conversation Model
struct Conversation: Codable, Identifiable {
    let id: String
    let participants: [String]
    let type: ConversationType
    let name: String?
    let default_name: String?
    let created_at: Date
    let last_activity: Date
    let last_message: LastMessage?
    var unread_counts: [String: Int]
    var pinned_by: [String]?

    // Resolved display name (populated by ChatManager)
    var resolvedDisplayName: String?

    enum ConversationType: String, Codable {
        case direct = "direct"
        case group = "group"
    }

    // Backward compatibility computed properties
    var defaultName: String? { default_name }
    var createdAt: Date { created_at }
    var lastActivity: Date { last_activity }
    var lastMessage: LastMessage? { last_message }
    var unreadCounts: [String: Int] {
        get { unread_counts }
        set { unread_counts = newValue }
    }
    var pinnedBy: [String]? {
        get { pinned_by }
        set { pinned_by = newValue }
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
        if let defaultName = default_name, !defaultName.isEmpty {
            return defaultName
        }
        return type == .direct ? "Direct Message" : "Group Chat"
    }

    // Get unread count for specific user
    func unreadCount(for userId: String) -> Int {
        return unread_counts[userId] ?? 0
    }

    // Check if conversation is pinned by user
    func isPinned(by userId: String) -> Bool {
        return pinned_by?.contains(userId) ?? false
    }

    // Custom decoding to handle database field names
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        participants = try container.decode([String].self, forKey: .participants)

        let typeString = try container.decode(String.self, forKey: .type)
        type = ConversationType(rawValue: typeString) ?? .direct

        name = try container.decodeIfPresent(String.self, forKey: .name)
        default_name = try container.decodeIfPresent(String.self, forKey: .default_name)
        created_at = try container.decode(Date.self, forKey: .created_at)
        last_activity = try container.decode(Date.self, forKey: .last_activity)
        last_message = try container.decodeIfPresent(LastMessage.self, forKey: .last_message)
        unread_counts = try container.decodeIfPresent([String: Int].self, forKey: .unread_counts) ?? [:]
        pinned_by = try container.decodeIfPresent([String].self, forKey: .pinned_by)
        resolvedDisplayName = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, participants, type, name
        case default_name
        case created_at
        case last_activity
        case last_message
        case unread_counts
        case pinned_by
    }

    // Custom encoding to exclude resolvedDisplayName
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(participants, forKey: .participants)
        try container.encode(type.rawValue, forKey: .type)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(default_name, forKey: .default_name)
        try container.encode(created_at, forKey: .created_at)
        try container.encode(last_activity, forKey: .last_activity)
        try container.encodeIfPresent(last_message, forKey: .last_message)
        try container.encode(unread_counts, forKey: .unread_counts)
        try container.encodeIfPresent(pinned_by, forKey: .pinned_by)
    }
}

// MARK: - Last Message Model
struct LastMessage: Codable {
    let text: String
    let sender_id: String
    let timestamp: Date

    // Backward compatibility
    var senderId: String { sender_id }

    // Format timestamp for display
    var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Chat Message Model
struct ChatMessage: Codable, Identifiable {
    let id: String
    let sender_id: String?  // Optional for system messages
    let sender_name: String?  // Optional for system messages
    let text: String
    let type: MessageType
    let file_url: String?
    let timestamp: Date
    let created_at: Date

    // System message fields
    let system_action: String?
    let added_by: String?
    let added_by_name: String?
    let added_participants: [String]?
    let removed_by: String?
    let removed_by_name: String?
    let removed_participant: String?
    let removed_participant_name: String?
    let left_user_id: String?
    let left_user_name: String?

    // Backward compatibility computed properties
    var senderId: String? { sender_id }
    var senderName: String? { sender_name }
    var fileUrl: String? { file_url }
    var createdAt: Date { created_at }
    var systemAction: String? { system_action }
    var addedBy: String? { added_by }
    var addedByName: String? { added_by_name }
    var addedParticipants: [String]? { added_participants }
    var removedBy: String? { removed_by }
    var removedByName: String? { removed_by_name }
    var removedParticipant: String? { removed_participant }
    var removedParticipantName: String? { removed_participant_name }
    var leftUserId: String? { left_user_id }
    var leftUserName: String? { left_user_name }

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

        switch system_action {
        case "participants_added":
            let names = added_participants?.joined(separator: ", ") ?? "participants"
            return "\(added_by_name ?? "Someone") added \(names) to the group"
        case "participant_removed":
            return "\(removed_by_name ?? "Someone") removed \(removed_participant_name ?? "a participant") from the group"
        case "participant_left":
            return "\(left_user_name ?? "Someone") left the group"
        default:
            return text
        }
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - User Presence Model
struct UserPresence: Codable {
    let is_online: Bool
    let last_seen: Date
    let conversation_id: String?
    let is_typing: Bool?

    // Backward compatibility
    var isOnline: Bool { is_online }
    var lastSeen: Date { last_seen }
    var conversationId: String? { conversation_id }
    var isTyping: Bool? { is_typing }

    init(isOnline: Bool, lastSeen: Date, conversationId: String? = nil, isTyping: Bool? = nil) {
        self.is_online = isOnline
        self.last_seen = lastSeen
        self.conversation_id = conversationId
        self.is_typing = isTyping
    }
}

// MARK: - Chat User Model (extends base User model for chat-specific needs)
struct ChatUser: Codable, Identifiable, Hashable {
    let id: String
    let organization_id: String
    let first_name: String
    let last_name: String
    let email: String
    let display_name: String?
    let photo_url: String?
    let is_active: Bool?

    // Backward compatibility computed properties
    var organizationID: String { organization_id }
    var firstName: String { first_name }
    var lastName: String { last_name }
    var displayName: String? { display_name }
    var photoURL: String? { photo_url }
    var isActive: Bool? { is_active }

    // Computed display name
    var fullName: String {
        if let displayName = display_name, !displayName.isEmpty {
            return displayName
        }
        let name = "\(first_name) \(last_name)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? email : name
    }

    // Get initials for avatar
    var initials: String {
        let firstInitial = first_name.first?.uppercased() ?? ""
        let lastInitial = last_name.first?.uppercased() ?? ""
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
    let latestMessageTimestamp: Date?
}

struct UserCacheData: Codable {
    let version: String
    let timestamp: Date
    let data: [ChatUser]
}
