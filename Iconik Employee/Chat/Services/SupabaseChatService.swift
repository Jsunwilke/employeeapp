import Foundation
import Supabase

// MARK: - Supabase Chat Service Protocol

protocol SupabaseChatServiceProtocol {
    // Conversation Management
    func createConversation(participants: [String], type: Conversation.ConversationType, customName: String?) async throws -> String
    func getUserConversations(userId: String) async throws -> [Conversation]
    func updateConversationName(conversationId: String, newName: String) async throws

    // Messaging
    func sendMessage(conversationId: String, senderId: String, text: String, type: ChatMessage.MessageType, fileUrl: String?, senderName: String) async throws -> String
    func getConversationMessages(conversationId: String, limit: Int, offset: Int) async throws -> (messages: [ChatMessage], hasMore: Bool)
    func markMessagesAsRead(conversationId: String, userId: String) async throws

    // Real-time Listeners
    func subscribeToUserConversations(userId: String, completion: @escaping ([Conversation]) -> Void) -> RealtimeChannelV2
    func subscribeToConversationMessages(conversationId: String, completion: @escaping ([ChatMessage]) -> Void) -> RealtimeChannelV2

    // User Management
    func getOrganizationUsers(organizationId: String) async throws -> [ChatUser]
    func updateUserPresence(userId: String, isOnline: Bool, conversationId: String?) async throws

    // Group Management
    func togglePinConversation(conversationId: String, userId: String, isPinned: Bool) async throws
    func addParticipantsToConversation(conversationId: String, newParticipantIds: [String], addedBy: (id: String, name: String)) async throws
    func removeParticipantFromConversation(conversationId: String, participantId: String, removedBy: (id: String, name: String), removedUserName: String) async throws
    func deleteConversation(conversationId: String) async throws
    func leaveConversation(conversationId: String, userId: String, userName: String) async throws
}

// MARK: - Supabase Chat Service Implementation

@MainActor
class SupabaseChatService: SupabaseChatServiceProtocol {
    private let supabase = SupabaseManager.shared.client

    static let shared = SupabaseChatService()

    private init() {}

    // MARK: - Conversation Management

    func createConversation(participants: [String], type: Conversation.ConversationType, customName: String?) async throws -> String {
        // Check if direct conversation already exists
        if type == .direct && participants.count == 2 {
            let existingConversation = try await findExistingDirectConversation(participants: participants)
            if let existingId = existingConversation {
                return existingId
            }
        }

        // Generate default name
        let defaultName = try await generateConversationName(participants: participants, type: type)

        // Generate UUID for conversation
        let conversationId = UUID().uuidString

        // Initialize unread counts
        var unreadCounts: [String: Int] = [:]
        for participantId in participants {
            unreadCounts[participantId] = 0
        }

        // Create conversation data
        struct ConversationInsert: Encodable {
            let id: String
            let participants: [String]
            let type: String
            let name: String?
            let default_name: String
            let unread_counts: [String: Int]
        }

        let conversationData = ConversationInsert(
            id: conversationId,
            participants: participants,
            type: type.rawValue,
            name: customName,
            default_name: defaultName,
            unread_counts: unreadCounts
        )

        try await supabase
            .from("conversations")
            .insert(conversationData)
            .execute()

        return conversationId
    }

    func getUserConversations(userId: String) async throws -> [Conversation] {
        // Query conversations where user is a participant
        // Note: Supabase doesn't have array-contains, so we use a PostgreSQL function or filter client-side
        let response: [Conversation] = try await supabase
            .from("conversations")
            .select()
            .contains("participants", value: [userId])
            .order("last_activity", ascending: false)
            .execute()
            .value

        return response
    }

    func updateConversationName(conversationId: String, newName: String) async throws {
        struct NameUpdate: Encodable {
            let name: String
        }

        try await supabase
            .from("conversations")
            .update(NameUpdate(name: newName))
            .eq("id", value: conversationId)
            .execute()
    }

    // MARK: - Messaging

    func sendMessage(conversationId: String, senderId: String, text: String, type: ChatMessage.MessageType, fileUrl: String?, senderName: String) async throws -> String {
        let messageId = UUID().uuidString

        struct MessageInsert: Encodable {
            let id: String
            let conversation_id: String
            let sender_id: String
            let sender_name: String
            let text: String
            let type: String
            let file_url: String?
            let status: String
        }

        let messageData = MessageInsert(
            id: messageId,
            conversation_id: conversationId,
            sender_id: senderId,
            sender_name: senderName,
            text: text,
            type: type.rawValue,
            file_url: fileUrl,
            status: "sent"
        )

        // Insert message
        try await supabase
            .from("messages")
            .insert(messageData)
            .execute()

        // Update conversation last activity and last message
        struct ConversationUpdate: Encodable {
            let last_activity: String
            let last_message: String
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let update = ConversationUpdate(
            last_activity: now,
            last_message: text
        )

        try await supabase
            .from("conversations")
            .update(update)
            .eq("id", value: conversationId)
            .execute()

        // Increment unread counts for other participants
        // Note: This requires a PostgreSQL function or RPC call
        // For now, we'll handle this on the client side when marking as read

        return messageId
    }

    func getConversationMessages(conversationId: String, limit: Int = 50, offset: Int = 0) async throws -> (messages: [ChatMessage], hasMore: Bool) {
        let messages: [ChatMessage] = try await supabase
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationId)
            .order("timestamp", ascending: true)
            .limit(limit + 1) // Fetch one extra to check if there are more
            .range(from: offset, to: offset + limit)
            .execute()
            .value

        let hasMore = messages.count > limit
        let resultMessages = hasMore ? Array(messages.prefix(limit)) : messages

        return (resultMessages, hasMore)
    }

    func markMessagesAsRead(conversationId: String, userId: String) async throws {
        // Update unread count for this user in the conversation
        // This requires a PostgreSQL function to update the JSONB field
        // For now, we'll use RPC
        struct MarkReadParams: Encodable {
            let conversation_id: String
            let user_id: String
        }

        let params = MarkReadParams(
            conversation_id: conversationId,
            user_id: userId
        )
        try await supabase.rpc("mark_conversation_read", params: params).execute()
    }

    // MARK: - Real-time Listeners

    func subscribeToUserConversations(userId: String, completion: @escaping ([Conversation]) -> Void) -> RealtimeChannelV2 {
        let channelKey = "conversations-user-\(userId)"
        let channel = supabase.channel(channelKey)

        _ = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "conversations",
            filter: "participants=cs.{\(userId)}" // Contains filter
        ) { [weak self] _ in
            Task { @MainActor in
                do {
                    let conversations = try await self?.getUserConversations(userId: userId) ?? []
                    completion(conversations)
                } catch {
                    print("❌ Error fetching conversations after realtime update: \(error)")
                    completion([])
                }
            }
        }

        Task {
            await channel.subscribe()

            // Initial fetch
            do {
                let conversations = try await getUserConversations(userId: userId)
                completion(conversations)
            } catch {
                print("❌ Error on initial conversations fetch: \(error)")
                completion([])
            }
        }

        return channel
    }

    func subscribeToConversationMessages(conversationId: String, completion: @escaping ([ChatMessage]) -> Void) -> RealtimeChannelV2 {
        let channelKey = "messages-\(conversationId)"
        let channel = supabase.channel(channelKey)

        _ = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "messages",
            filter: "conversation_id=eq.\(conversationId)"
        ) { [weak self] _ in
            Task { @MainActor in
                do {
                    let (messages, _) = try await self?.getConversationMessages(conversationId: conversationId, limit: 100, offset: 0) ?? ([], false)
                    completion(messages)
                } catch {
                    print("❌ Error fetching messages after realtime update: \(error)")
                    completion([])
                }
            }
        }

        Task {
            await channel.subscribe()

            // Initial fetch
            do {
                let (messages, _) = try await getConversationMessages(conversationId: conversationId, limit: 100, offset: 0)
                completion(messages)
            } catch {
                print("❌ Error on initial messages fetch: \(error)")
                completion([])
            }
        }

        return channel
    }

    // MARK: - User Management

    func getOrganizationUsers(organizationId: String) async throws -> [ChatUser] {
        let users: [ChatUser] = try await supabase
            .from("users")
            .select()
            .eq("organization_id", value: organizationId)
            .eq("is_active", value: true)
            .execute()
            .value

        return users
    }

    func updateUserPresence(userId: String, isOnline: Bool, conversationId: String?) async throws {
        struct PresenceUpdate: Encodable {
            let user_id: String
            let is_online: Bool
            let conversation_id: String?
            let last_seen: String
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let update = PresenceUpdate(
            user_id: userId,
            is_online: isOnline,
            conversation_id: conversationId,
            last_seen: now
        )

        try await supabase
            .from("user_presence")
            .upsert(update)
            .execute()
    }

    // MARK: - Group Management

    func togglePinConversation(conversationId: String, userId: String, isPinned: Bool) async throws {
        // Use RPC to toggle pin status in the pinnedBy array
        struct TogglePinParams: Encodable {
            let conversation_id: String
            let user_id: String
            let is_pinned: Bool
        }

        let params = TogglePinParams(
            conversation_id: conversationId,
            user_id: userId,
            is_pinned: isPinned
        )
        try await supabase.rpc("toggle_pin_conversation", params: params).execute()
    }

    func addParticipantsToConversation(conversationId: String, newParticipantIds: [String], addedBy: (id: String, name: String)) async throws {
        // Use RPC to add participants (handles both participants array and unread_counts)
        struct AddParticipantsParams: Encodable {
            let conversation_id: String
            let new_participant_ids: [String]
            let added_by_id: String
            let added_by_name: String
        }

        let params = AddParticipantsParams(
            conversation_id: conversationId,
            new_participant_ids: newParticipantIds,
            added_by_id: addedBy.id,
            added_by_name: addedBy.name
        )
        try await supabase.rpc("add_conversation_participants", params: params).execute()
    }

    func removeParticipantFromConversation(conversationId: String, participantId: String, removedBy: (id: String, name: String), removedUserName: String) async throws {
        // Use RPC to remove participant
        struct RemoveParticipantParams: Encodable {
            let conversation_id: String
            let participant_id: String
            let removed_by_id: String
            let removed_by_name: String
            let removed_participant_name: String
        }

        let params = RemoveParticipantParams(
            conversation_id: conversationId,
            participant_id: participantId,
            removed_by_id: removedBy.id,
            removed_by_name: removedBy.name,
            removed_participant_name: removedUserName
        )
        try await supabase.rpc("remove_conversation_participant", params: params).execute()
    }

    func deleteConversation(conversationId: String) async throws {
        // Delete conversation (messages will be cascade deleted if FK is set up correctly)
        try await supabase
            .from("conversations")
            .delete()
            .eq("id", value: conversationId)
            .execute()
    }

    func leaveConversation(conversationId: String, userId: String, userName: String) async throws {
        // Use RPC to handle leaving conversation with validation
        struct LeaveConversationParams: Encodable {
            let conversation_id: String
            let user_id: String
            let user_name: String
        }

        let params = LeaveConversationParams(
            conversation_id: conversationId,
            user_id: userId,
            user_name: userName
        )
        try await supabase.rpc("leave_conversation", params: params).execute()
    }

    // MARK: - Helper Methods

    private func findExistingDirectConversation(participants: [String]) async throws -> String? {
        let sortedParticipants = participants.sorted()

        // Query for direct conversations with exactly these participants
        let conversations: [Conversation] = try await supabase
            .from("conversations")
            .select()
            .eq("type", value: "direct")
            .eq("participants", value: sortedParticipants)
            .limit(1)
            .execute()
            .value

        return conversations.first?.id
    }

    private func generateConversationName(participants: [String], type: Conversation.ConversationType) async throws -> String {
        if type == .direct && participants.count == 2 {
            // For direct chats, get the other user's name
            guard let currentUserId = UserManager.shared.getCurrentUserIDUnified() else {
                return "Direct Chat"
            }

            let otherUserId = participants.first(where: { $0 != currentUserId }) ?? participants[0]

            do {
                struct UserName: Decodable {
                    let first_name: String
                    let last_name: String
                    let email: String
                }

                let users: [UserName] = try await supabase
                    .from("users")
                    .select("first_name,last_name,email")
                    .eq("id", value: otherUserId)
                    .limit(1)
                    .execute()
                    .value

                if let user = users.first {
                    let name = "\(user.first_name) \(user.last_name)".trimmingCharacters(in: .whitespaces)
                    return name.isEmpty ? user.email : name
                }
            } catch {
                print("Error fetching user name: \(error)")
            }
        }

        // For group chats, list participant names
        var names: [String] = []
        for participantId in participants.prefix(3) {
            do {
                struct UserFirstName: Decodable {
                    let first_name: String
                }

                let users: [UserFirstName] = try await supabase
                    .from("users")
                    .select("first_name")
                    .eq("id", value: participantId)
                    .limit(1)
                    .execute()
                    .value

                if let user = users.first {
                    names.append(user.first_name)
                }
            } catch {
                print("Error fetching participant name: \(error)")
            }
        }

        if participants.count > 3 {
            names.append("and \(participants.count - 3) others")
        }

        return names.isEmpty ? "Group Chat" : names.joined(separator: ", ")
    }
}
