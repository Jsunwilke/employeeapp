import Foundation
import StreamChat
import FirebaseFirestore

// Type aliases to avoid naming conflicts
typealias StreamChatMessage = StreamChat.ChatMessage
typealias StreamChatUser = StreamChat.ChatUser
typealias StreamChatChannel = StreamChat.ChatChannel
typealias AppChatMessage = ChatMessage
typealias AppChatUser = ChatUser
typealias AppConversation = Conversation

// MARK: - Stream Chat Adapter
// This adapter converts between Stream Chat models and our existing app models

@MainActor
class StreamChatAdapter {
    
    // MARK: - Channel Conversion
    
    static func convertToConversation(_ channel: StreamChatChannel, currentUserId: String) -> AppConversation {
        // Get conversation type
        let type: Conversation.ConversationType = channel.type == .messaging ? .direct : .group
        
        // Get participant IDs
        let participants = channel.lastActiveMembers.map { $0.id }
        
        // Get display name
        var displayName: String? = nil
        var defaultName: String? = nil
        
        if let channelName = channel.name, !channelName.isEmpty {
            displayName = channelName
        } else if type == .direct {
            // For direct messages, use the other person's name
            if let otherMember = channel.lastActiveMembers.first(where: { $0.id != currentUserId }) {
                defaultName = otherMember.name ?? "User"
            }
        } else {
            // For groups without a name, create one from members
            let otherMembers = channel.lastActiveMembers.filter { $0.id != currentUserId }
            let names = otherMembers.prefix(3).compactMap { $0.name }
            defaultName = names.joined(separator: ", ")
        }
        
        // Convert last message
        var lastMessage: LastMessage? = nil
        if let message = channel.latestMessages.first {
            // Determine the text to display
            var displayText = message.text
            
            // If text is empty but has attachments, create a preview
            if displayText.isEmpty {
                if !message.imageAttachments.isEmpty {
                    displayText = "📷 Photo"
                } else if !message.fileAttachments.isEmpty {
                    displayText = "📎 File"
                } else if !message.giphyAttachments.isEmpty {
                    displayText = "🎬 GIF"
                }
            }
            
            lastMessage = LastMessage(
                text: displayText,
                senderId: message.author.id,
                timestamp: Timestamp(date: message.createdAt)
            )
        }
        
        // Calculate unread counts
        var unreadCounts: [String: Int] = [:]
        unreadCounts[currentUserId] = channel.unreadCount.messages
        
        // Check if pinned (Stream Chat doesn't have isPinned on membership)
        let pinnedBy: [String] = []  // We'll need to store pinning separately or in channel extra data
        
        // Create conversation struct directly (simpler approach)
        // We'll create a custom init in the Conversation struct to handle this
        // For now, let's use a workaround by creating the JSON structure that matches the decoder
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        // Create a temporary struct that matches the Conversation Codable format
        struct TempConversation: Codable {
            let id: String
            let participants: [String]
            let type: String
            let name: String?
            let defaultName: String?
            let createdAt: Timestamp
            let lastActivity: Timestamp
            let lastMessage: TempLastMessage?
            let unreadCounts: [String: Int]
            let pinnedBy: [String]?
            
            struct TempLastMessage: Codable {
                let text: String
                let senderId: String
                let timestamp: Timestamp
            }
        }
        
        let tempLastMessage = lastMessage.map { 
            TempConversation.TempLastMessage(text: $0.text, senderId: $0.senderId, timestamp: $0.timestamp)
        }
        
        let tempConv = TempConversation(
            id: channel.cid.id,
            participants: participants,
            type: type.rawValue,
            name: displayName,
            defaultName: defaultName,
            createdAt: Timestamp(date: channel.createdAt),
            lastActivity: Timestamp(date: channel.lastMessageAt ?? channel.createdAt),
            lastMessage: tempLastMessage,
            unreadCounts: unreadCounts,
            pinnedBy: pinnedBy.isEmpty ? nil : pinnedBy
        )
        
        // Encode and decode to get proper Conversation
        let jsonData = try! encoder.encode(tempConv)
        var conversation = try! decoder.decode(AppConversation.self, from: jsonData)
        
        // Set resolved display name
        conversation.resolvedDisplayName = defaultName
        
        return conversation
    }
    
    // MARK: - Message Conversion
    
    static func convertToChatMessage(_ streamMessage: StreamChatMessage) -> AppChatMessage {
        // Determine message type
        let messageType: AppChatMessage.MessageType
        if streamMessage.type == .system {
            messageType = .system
        } else if !streamMessage.imageAttachments.isEmpty || !streamMessage.fileAttachments.isEmpty {
            // If message has attachments, treat it as file type
            messageType = .file
        } else {
            messageType = .text
        }
        
        // Get sender name
        let senderName = streamMessage.author.name ?? streamMessage.author.id
        
        // Extract attachment URL if present
        let attachmentURL: String? = {
            if let imageURL = streamMessage.imageAttachments.first?.imageURL {
                return imageURL.absoluteString
            } else if let fileAttachment = streamMessage.fileAttachments.first {
                return fileAttachment.assetURL.absoluteString
            }
            return nil
        }()
        
        print("[StreamChatAdapter] Converting message: text='\(streamMessage.text)', type=\(messageType.rawValue), attachments: \(streamMessage.imageAttachments.count) images, \(streamMessage.fileAttachments.count) files, attachmentURL: \(attachmentURL ?? "nil")")
        
        // Create a temporary struct that matches the ChatMessage Codable format
        struct TempChatMessage: Codable {
            let id: String
            let senderId: String?
            let senderName: String?
            let text: String
            let type: String
            let fileUrl: String?
            let timestamp: Timestamp
            let createdAt: Timestamp
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
        }
        
        let tempMessage = TempChatMessage(
            id: streamMessage.id,
            senderId: streamMessage.author.id,
            senderName: senderName,
            text: streamMessage.text,
            type: messageType.rawValue,
            fileUrl: attachmentURL,
            timestamp: Timestamp(date: streamMessage.createdAt),
            createdAt: Timestamp(date: streamMessage.createdAt),
            systemAction: nil,
            addedBy: nil,
            addedByName: nil,
            addedParticipants: nil,
            removedBy: nil,
            removedByName: nil,
            removedParticipant: nil,
            removedParticipantName: nil,
            leftUserId: nil,
            leftUserName: nil
        )
        
        // Encode and decode to get proper ChatMessage
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let jsonData = try! encoder.encode(tempMessage)
        let message = try! decoder.decode(AppChatMessage.self, from: jsonData)
        
        return message
    }
    
    // MARK: - User Conversion
    
    static func convertToChatUser(_ streamUser: StreamChatUser) -> AppChatUser {
        // Extract name parts
        let fullName = streamUser.name ?? "User"
        let nameParts = fullName.split(separator: " ")
        let firstName = String(nameParts.first ?? "User")
        let lastName = nameParts.count > 1 ? String(nameParts.dropFirst().joined(separator: " ")) : ""
        
        // Create a temporary struct that matches the ChatUser Codable format
        struct TempChatUser: Codable {
            let id: String
            let organizationID: String
            let firstName: String
            let lastName: String
            let email: String
            let displayName: String?
            let photoURL: String?
            let isActive: Bool?
        }
        
        let tempUser = TempChatUser(
            id: streamUser.id,
            organizationID: streamUser.extraData["organizationID"]?.stringValue ?? "",
            firstName: firstName,
            lastName: lastName,
            email: streamUser.extraData["email"]?.stringValue ?? "",
            displayName: fullName,
            photoURL: streamUser.imageURL?.absoluteString,
            isActive: streamUser.isOnline
        )
        
        // Encode and decode to get proper ChatUser
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let jsonData = try! encoder.encode(tempUser)
        let user = try! decoder.decode(AppChatUser.self, from: jsonData)
        
        return user
    }
    
    // MARK: - Channel ID Helpers
    
    static func createDirectMessageChannelId(user1: String, user2: String) -> String {
        let sortedUsers = [user1, user2].sorted()
        return "dm-\(sortedUsers.joined(separator: "-"))"
    }
    
    static func parseDirectMessageChannelId(_ channelId: String) -> (String, String)? {
        guard channelId.hasPrefix("dm-") else { return nil }
        
        let usersString = String(channelId.dropFirst(3))
        let users = usersString.split(separator: "-").map(String.init)
        
        guard users.count == 2 else { return nil }
        return (users[0], users[1])
    }
    
    // MARK: - Typing Indicators
    
    static func formatTypingUsers(_ users: Set<StreamChatUser>) -> String? {
        guard !users.isEmpty else { return nil }
        
        let names = users.prefix(3).compactMap { $0.name ?? $0.id }
        
        if names.count == 1 {
            return "\(names[0]) is typing..."
        } else if names.count == 2 {
            return "\(names[0]) and \(names[1]) are typing..."
        } else {
            return "\(names[0]) and others are typing..."
        }
    }
}

