import Foundation
import Supabase

// MARK: - Supabase Chat Service Protocol

/// `@MainActor` because the only conformer is, and every completion it hands back
/// mutates `@Published` state on `ChatManager`. Without it the conformance
/// "crosses into main actor-isolated code", which is a warning today and an error
/// in Swift 6.
@MainActor
protocol SupabaseChatServiceProtocol {
    // Conversation Management
    func createConversation(participants: [String], type: Conversation.ConversationType, customName: String?) async throws -> String
    func getUserConversations(userId: String) async throws -> [Conversation]
    func updateConversationName(conversationId: String, newName: String) async throws

    // Messaging
    func sendMessage(messageId: String, conversationId: String, senderId: String, text: String, type: ChatMessage.MessageType, fileUrl: String?, senderName: String) async throws -> String
    func getConversationMessages(conversationId: String, limit: Int, offset: Int) async throws -> (messages: [ChatMessage], hasMore: Bool)
    func markMessagesAsRead(conversationId: String, userId: String) async throws

    // Real-time Listeners
    func subscribeToUserConversations(userId: String, completion: @escaping (Result<[Conversation], Error>) -> Void) -> RealtimeChannelV2
    func subscribeToConversationMessages(conversationId: String, completion: @escaping (Result<(messages: [ChatMessage], hasMore: Bool), Error>) -> Void) -> RealtimeChannelV2

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
        let conversationId = UUID().uuidString.lowercased()

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

    /// `messageId` is supplied by the caller so the optimistic message shown in
    /// the thread and the row stored here are the same message, and the merge can
    /// retire the optimistic copy by id.
    @discardableResult
    func sendMessage(messageId: String, conversationId: String, senderId: String, text: String, type: ChatMessage.MessageType, fileUrl: String?, senderName: String) async throws -> String {
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

        // Raise everyone else's unread count. Without this a message sent from
        // this app never moved anyone's badge — only web-sent messages did.
        //
        // It goes through an RPC rather than the web app's read-modify-write of
        // the whole jsonb blob, because that pattern loses an increment whenever
        // two people send at once (both read the same counts, both write back
        // their own +1, last writer wins). The RPC does it in one statement with
        // jsonb_set, matching the five chat RPCs already applied to this DB.
        //
        // A failure here must not fail the SEND — the message is already stored.
        do {
            struct IncrementParams: Encodable {
                let conversation_id: String
                let sender_id: String
            }
            try await supabase.rpc(
                "increment_conversation_unread",
                params: IncrementParams(conversation_id: conversationId, sender_id: senderId)
            ).execute()
        } catch {
            print("⚠️ Unread increment failed (message was still sent): \(error)")
        }

        return messageId
    }

    /// Page BACKWARD from the newest message.
    ///
    /// This used to order ascending and range forward, which meant `offset: 0`
    /// returned the hundred OLDEST messages in the conversation. In any thread
    /// longer than a page the recent messages were unreachable and a message you
    /// had just sent never appeared, because every refresh re-fetched the same
    /// ancient rows. "Load earlier" made it worse by advancing the offset, which
    /// under ascending order fetches NEWER messages, and then prepending them.
    ///
    /// A thread opens on the most recent messages and pages back into history, so
    /// the query is ordered DESCENDING and the offset counts backward from the
    /// newest row. The page is reversed before returning, because the view still
    /// renders oldest-to-newest.
    ///
    /// `offset` must be the number of messages already loaded — not a page
    /// counter — or pages overlap when the first page and later pages differ in
    /// size. `range` is inclusive at both ends, so asking for `limit` more rows
    /// than needed is the has-more probe; no separate `.limit` is used, because
    /// `range` overrides it.
    func getConversationMessages(conversationId: String, limit: Int = 50, offset: Int = 0) async throws -> (messages: [ChatMessage], hasMore: Bool) {
        let page: [ChatMessage] = try await supabase
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationId)
            .order("timestamp", ascending: false)
            // `id` is the tiebreaker, and it is required rather than tidy:
            // Postgres gives no stable row order for equal sort keys, so two
            // messages sharing a timestamp either side of a page boundary could
            // be returned twice or SKIPPED ENTIRELY between pages. The merge
            // dedupes a repeat; nothing recovers a skip.
            .order("id", ascending: false)
            .range(from: offset, to: offset + limit) // limit + 1 rows: the extra is the probe
            .execute()
            .value

        let hasMore = page.count > limit
        let window = hasMore ? Array(page.prefix(limit)) : page

        return (window.reversed(), hasMore)
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

    /// Reports FAILURE rather than an empty list. Publishing `[]` on a failed
    /// fetch is exactly how the conversation list went blank: one row whose
    /// `last_message` did not match the model threw, `Decodable` fails an array
    /// atomically, and the whole screen emptied with nothing but a console print.
    /// The decode is tolerant now (see `Conversation.decodeLastMessage`), but the
    /// reporting stays honest — a failure must never be presentable as "you have
    /// no conversations".
    func subscribeToUserConversations(userId: String, completion: @escaping (Result<[Conversation], Error>) -> Void) -> RealtimeChannelV2 {
        let channelKey = "conversations-user-\(userId)"
        let channel = supabase.realtimeV2.channel(channelKey)

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "conversations",
            filter: "participants=cs.{\(userId)}" // Contains filter
        )

        Task {
            await channel.subscribe()

            // Initial fetch — hop to the main actor like the change-stream
            // path below, since completion mutates @Published state on
            // ChatManager (@MainActor).
            await fetchConversations(userId: userId, completion: completion, context: "initial")

            // Listen for changes
            Task {
                for await _ in changes {
                    await self.fetchConversations(userId: userId, completion: completion, context: "realtime")
                }
            }
        }

        return channel
    }

    private func fetchConversations(
        userId: String,
        completion: @escaping (Result<[Conversation], Error>) -> Void,
        context: String
    ) async {
        do {
            let conversations = try await getUserConversations(userId: userId)
            await MainActor.run { completion(.success(conversations)) }
        } catch {
            print("❌ Error on \(context) conversations fetch: \(error)")
            await MainActor.run { completion(.failure(error)) }
        }
    }

    /// One page size for the whole feature. The initial load and "Load earlier"
    /// MUST agree on it: they used to be 100 and 30, so the first "Load earlier"
    /// asked for rows 30-60 of an already-loaded 100 and returned duplicates.
    static let messagePageSize = 50

    /// The completion carries `hasMore` as well, because `hasMoreMessages` used to
    /// be forced true on every load and only ever corrected by "Load earlier" —
    /// so a two-message conversation offered to load earlier ones.
    ///
    /// It reports FAILURE rather than an empty page. Publishing `[]` on a failed
    /// fetch is what made a decode error look like an empty conversation, and a
    /// caller that is never told cannot clear its loading flag — the permanent
    /// spinner AMB.4 shipped twice.
    func subscribeToConversationMessages(conversationId: String, completion: @escaping (Result<(messages: [ChatMessage], hasMore: Bool), Error>) -> Void) -> RealtimeChannelV2 {
        let channelKey = "messages-\(conversationId)"
        let channel = supabase.realtimeV2.channel(channelKey)

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "messages",
            filter: "conversation_id=eq.\(conversationId)"
        )

        Task {
            await channel.subscribe()

            // Initial fetch — hop to the main actor like the change-stream
            // path below (completion mutates @Published state on ChatManager).
            await fetchNewestPage(conversationId: conversationId, completion: completion, context: "initial")

            // Listen for changes
            Task {
                for await _ in changes {
                    await self.fetchNewestPage(conversationId: conversationId, completion: completion, context: "realtime")
                }
            }
        }

        return channel
    }

    /// Always the NEWEST page. The caller merges it into whatever history is
    /// already on screen rather than replacing — a realtime event used to
    /// overwrite the whole array, which threw away everything "Load earlier" had
    /// paged in.
    private func fetchNewestPage(
        conversationId: String,
        completion: @escaping (Result<(messages: [ChatMessage], hasMore: Bool), Error>) -> Void,
        context: String
    ) async {
        do {
            let page = try await getConversationMessages(
                conversationId: conversationId,
                limit: Self.messagePageSize,
                offset: 0
            )
            await MainActor.run { completion(.success(page)) }
        } catch {
            print("❌ Error on \(context) messages fetch: \(error)")
            await MainActor.run { completion(.failure(error)) }
        }
    }

    // MARK: - Attachments

    /// Bucket created by supabase/drafts/chat_attachments_bucket.sql.
    static let attachmentsBucket = "chat-attachments"

    /// Uploads an attachment and returns its STORAGE PATH.
    ///
    /// The path, not a URL — matching how Equipment stores photos, which is the
    /// newer of the two conventions in this app and the only one that survives a
    /// bucket staying private. (The older convention, used by the daily-report
    /// screens, bakes a one-year signed URL into the database row; when that year
    /// is up the row points at nothing.)
    ///
    /// The layout is {organization_id}/{conversation_id}/{uuid}.{ext} because the
    /// bucket's read policy checks BOTH segments — org membership and
    /// participation in that conversation. Changing this layout without changing
    /// that policy will make every upload fail the WITH CHECK.
    func uploadAttachment(
        organizationId: String,
        conversationId: String,
        data: Data,
        fileExtension: String,
        contentType: String
    ) async throws -> String {
        let fileName = "\(UUID().uuidString.lowercased()).\(fileExtension)"
        let path = "\(organizationId)/\(conversationId)/\(fileName)"

        try await supabase.storage
            .from(Self.attachmentsBucket)
            .upload(path, data: data, options: FileOptions(contentType: contentType))

        return path
    }

    /// Signs a stored attachment path for display. One hour, matching
    /// SupabaseImageView and the equipment photo path.
    func signedAttachmentURL(path: String) async throws -> URL {
        try await supabase.storage
            .from(Self.attachmentsBucket)
            .createSignedURL(path: path, expiresIn: 3600)
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

            guard let otherUserId = participants.first(where: { $0 != currentUserId }) ?? participants.first else {
                print("❌ No valid participant found for conversation")
                return "Direct Chat"
            }

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
