import Foundation
import SwiftUI
import Combine
import Supabase

// MARK: - Chat Manager
@MainActor
class ChatManager: ObservableObject {
    // Published properties for UI
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?
    @Published var messages: [ChatMessage] = []
    @Published var organizationUsers: [ChatUser] = []
    @Published var isLoading = true
    @Published var isSendingMessage = false
    @Published var messagesLoading = false
    @Published var hasMoreMessages = false
    @Published var errorMessage: String?
    @Published var totalUnreadCount: Int = 0

    // Services
    private let supabaseChatService: SupabaseChatService
    private let cacheService: ChatCacheServiceProtocol
    private let readCounter: ReadCounterProtocol

    // Supabase realtime channels
    private var conversationsChannel: RealtimeChannelV2?
    private var messagesChannel: RealtimeChannelV2?
    private var currentMessageOffset = 0

    // Debouncing
    private var messageUpdateDebouncer = Debouncer(delay: 0.1)

    // Current user info
    var currentUserId: String? {
        UserManager.shared.getCurrentUserIDUnified()
    }

    var currentUserOrganizationId: String? {
        UserManager.shared.getCachedOrganizationID()
    }

    // Singleton instance
    static let shared = ChatManager()

    private init() {
        self.supabaseChatService = SupabaseChatService.shared
        self.cacheService = ChatCacheService.shared
        self.readCounter = ReadCounterService.shared
    }

    // MARK: - Initialization

    func initialize() async {
        // Load users first so we can resolve conversation names
        await loadOrganizationUsers()
        await loadConversations()
    }

    // MARK: - Conversation Management

    func sortConversations(_ conversations: [Conversation]) -> [Conversation] {
        guard let userId = currentUserId else { return conversations }

        return conversations.sorted { conv1, conv2 in
            let isPinned1 = conv1.isPinned(by: userId)
            let isPinned2 = conv2.isPinned(by: userId)

            // If one is pinned and the other isn't, pinned comes first
            if isPinned1 && !isPinned2 { return true }
            if !isPinned1 && isPinned2 { return false }

            // Otherwise sort by lastActivity
            return conv1.lastActivity > conv2.lastActivity
        }
    }

    func openChannel(cid: String) async {
        // Find and select the conversation with the given channel CID
        if let conversation = conversations.first(where: { $0.id == cid }) {
            await selectConversation(conversation)
        } else {
            // If not found, try to load conversations first
            await loadConversations()
            if let conversation = conversations.first(where: { $0.id == cid }) {
                await selectConversation(conversation)
            }
        }
    }

    func loadConversations() async {
        guard let userId = currentUserId else {
            errorMessage = "Not authenticated"
            isLoading = false
            return
        }

        // 1. Load from cache first
        if let cachedConversations = cacheService.getCachedConversations() {
            let resolvedConversations = resolveConversationNames(cachedConversations)
            self.conversations = sortConversations(resolvedConversations)
            self.isLoading = false
            updateTotalUnreadCount()
            readCounter.recordCacheHit(collection: "conversations", component: "ChatManager", savedReads: cachedConversations.count)
        } else {
            readCounter.recordCacheMiss(collection: "conversations", component: "ChatManager")
        }

        // 2. Set up real-time listener using Supabase
        conversationsChannel = supabaseChatService.subscribeToUserConversations(userId: userId) { [weak self] updatedConversations in
            guard let self = self else { return }

            // Resolve names and sort conversations
            let resolvedConversations = self.resolveConversationNames(updatedConversations)
            self.conversations = self.sortConversations(resolvedConversations)
            self.isLoading = false
            self.updateTotalUnreadCount()

            // Cache the updated data (without resolved names to keep cache clean)
            self.cacheService.setCachedConversations(updatedConversations)

            // Record reads
            self.readCounter.recordRead(
                operation: "subscribeToUserConversations",
                collection: "conversations",
                component: "ChatManager",
                count: updatedConversations.count
            )
        }
    }

    func createConversation(with participants: [String], type: Conversation.ConversationType = .direct, customName: String? = nil) async throws -> String {
        guard let userId = currentUserId else {
            throw ChatError.notAuthenticated
        }

        // Ensure current user is in participants
        var allParticipants = participants
        if !allParticipants.contains(userId) {
            allParticipants.append(userId)
        }

        let conversationId = try await supabaseChatService.createConversation(
            participants: allParticipants,
            type: type,
            customName: customName
        )

        readCounter.recordRead(
            operation: "createConversation",
            collection: "conversations",
            component: "ChatManager",
            count: 1
        )

        return conversationId
    }

    func selectConversation(_ conversation: Conversation, markAsRead: Bool = true) async {
        self.activeConversation = conversation
        await loadMessages(for: conversation)

        // Mark messages as read only if requested (i.e., user is actively viewing the conversation)
        if markAsRead, let userId = currentUserId {
            Task {
                try? await supabaseChatService.markMessagesAsRead(conversationId: conversation.id, userId: userId)
            }
        }
    }

    // MARK: - Message Management

    func loadMessages(for conversation: Conversation) async {
        self.activeConversation = conversation
        self.messagesLoading = true
        self.currentMessageOffset = 0
        self.hasMoreMessages = true

        // 1. Load from cache first for immediate display
        let cachedMessages = cacheService.getCachedMessages(conversationId: conversation.id)

        if let cachedMessages = cachedMessages, !cachedMessages.isEmpty {
            self.messages = cachedMessages
            self.messagesLoading = false
            readCounter.recordCacheHit(collection: "messages", component: "ChatManager", savedReads: cachedMessages.count)
        } else {
            readCounter.recordCacheMiss(collection: "messages", component: "ChatManager")
        }

        // 2. Set up real-time listener for all messages
        messagesChannel = supabaseChatService.subscribeToConversationMessages(conversationId: conversation.id) { [weak self] updatedMessages in
            guard let self = self else { return }

            // Remove any temporary messages
            self.messages.removeAll { $0.id.hasSuffix("_temp") }

            self.messages = updatedMessages
            self.messagesLoading = false

            // Cache the updated messages
            self.cacheService.setCachedMessages(conversationId: conversation.id, messages: updatedMessages)

            self.readCounter.recordRead(
                operation: "subscribeToConversationMessages",
                collection: "messages",
                component: "ChatManager",
                count: updatedMessages.count
            )
        }
    }

    func loadMoreMessages() async {
        guard let conversation = activeConversation, hasMoreMessages else { return }

        do {
            currentMessageOffset += 30
            let result = try await supabaseChatService.getConversationMessages(
                conversationId: conversation.id,
                limit: 30,
                offset: currentMessageOffset
            )

            // Prepend older messages
            let allMessages = result.messages + messages
            messages = allMessages
            hasMoreMessages = result.hasMore

            // Update cache
            cacheService.setCachedMessages(conversationId: conversation.id, messages: allMessages)

            readCounter.recordRead(
                operation: "loadMoreMessages",
                collection: "messages",
                component: "ChatManager",
                count: result.messages.count
            )
        } catch {
            errorMessage = "Failed to load more messages"
        }
    }

    func sendMessage(text: String, type: ChatMessage.MessageType = .text, fileUrl: String? = nil) async {
        guard let conversation = activeConversation,
              let currentUserId = UserManager.shared.getCurrentUserIDUnified(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSendingMessage = true
        errorMessage = nil

        do {
            // Get current user info from cache or fetch
            let senderName = await getSenderName()

            // Create optimistic message for immediate display
            let optimisticMessage = ChatMessage(
                id: UUID().uuidString + "_temp",
                sender_id: currentUserId,
                sender_name: senderName,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                file_url: fileUrl,
                file_data: nil,
                status: nil,
                read_by: nil,
                timestamp: Date(),
                created_at: Date(),
                system_action: nil,
                added_by: nil,
                added_by_name: nil,
                added_participants: nil,
                removed_by: nil,
                removed_by_name: nil,
                removed_participant: nil,
                removed_participant_name: nil,
                left_user_id: nil,
                left_user_name: nil
            )

            // Add optimistic message immediately
            messages.append(optimisticMessage)

            _ = try await supabaseChatService.sendMessage(
                conversationId: conversation.id,
                senderId: currentUserId,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                fileUrl: fileUrl,
                senderName: senderName
            )

            // Note: Real-time listener will update with the actual message
            readCounter.recordRead(
                operation: "sendMessage",
                collection: "messages",
                component: "ChatManager",
                count: 1
            )
        } catch {
            // Remove optimistic message on error
            messages.removeAll { $0.id.hasSuffix("_temp") }
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }

        isSendingMessage = false
    }

    // MARK: - User Management

    func loadOrganizationUsers() async {
        guard let orgId = currentUserOrganizationId else { return }

        // Load from cache first
        if let cachedUsers = cacheService.getCachedUsers() {
            self.organizationUsers = cachedUsers
            readCounter.recordCacheHit(collection: "users", component: "ChatManager", savedReads: cachedUsers.count)
            // Re-resolve conversation names if we have conversations loaded
            if !conversations.isEmpty {
                conversations = resolveConversationNames(conversations)
            }
            return
        }

        readCounter.recordCacheMiss(collection: "users", component: "ChatManager")

        do {
            let users = try await supabaseChatService.getOrganizationUsers(organizationId: orgId)

            self.organizationUsers = users
            cacheService.setCachedUsers(users)

            // Re-resolve conversation names now that we have users
            if !conversations.isEmpty {
                conversations = resolveConversationNames(conversations)
            }

            readCounter.recordRead(
                operation: "getOrganizationUsers",
                collection: "users",
                component: "ChatManager",
                count: users.count
            )
        } catch {
            errorMessage = "Failed to load users"
        }
    }

    // MARK: - Group Management

    func togglePinConversation(_ conversation: Conversation) async {
        guard let userId = currentUserId else { return }

        let isPinned = conversation.isPinned(by: userId)

        do {
            try await supabaseChatService.togglePinConversation(
                conversationId: conversation.id,
                userId: userId,
                isPinned: !isPinned
            )

            // Update local state immediately for better UX
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                var updatedConversation = conversations[index]
                if isPinned {
                    updatedConversation.pinnedBy?.removeAll { $0 == userId }
                } else {
                    if updatedConversation.pinnedBy == nil {
                        updatedConversation.pinnedBy = [userId]
                    } else {
                        updatedConversation.pinnedBy?.append(userId)
                    }
                }
                conversations[index] = updatedConversation
                conversations = sortConversations(conversations)
            }
        } catch {
            errorMessage = "Failed to update pin status"
        }
    }

    func updateConversationName(_ conversation: Conversation, newName: String) async {
        do {
            try await supabaseChatService.updateConversationName(
                conversationId: conversation.id,
                newName: newName
            )
        } catch {
            errorMessage = "Failed to update conversation name"
        }
    }

    func addParticipants(_ userIds: [String], to conversation: Conversation) async {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified() else { return }

        do {
            let addedByName = await getSenderName()
            try await supabaseChatService.addParticipantsToConversation(
                conversationId: conversation.id,
                newParticipantIds: userIds,
                addedBy: (id: currentUserId, name: addedByName)
            )
        } catch {
            errorMessage = "Failed to add participants"
        }
    }

    func removeParticipant(_ participantId: String, from conversation: Conversation, participantName: String) async {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified() else { return }

        do {
            let removedByName = await getSenderName()
            try await supabaseChatService.removeParticipantFromConversation(
                conversationId: conversation.id,
                participantId: participantId,
                removedBy: (id: currentUserId, name: removedByName),
                removedUserName: participantName
            )
        } catch {
            errorMessage = "Failed to remove participant"
        }
    }

    func deleteConversation(_ conversation: Conversation) async {
        do {
            try await supabaseChatService.deleteConversation(conversationId: conversation.id)

            // Remove from local list
            conversations.removeAll { $0.id == conversation.id }
        } catch {
            errorMessage = "Failed to delete conversation"
        }
    }

    func leaveConversation(_ conversation: Conversation) async -> Bool {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified() else {
            errorMessage = "Not authenticated"
            return false
        }

        do {
            let userName = await getSenderName()
            try await supabaseChatService.leaveConversation(
                conversationId: conversation.id,
                userId: currentUserId,
                userName: userName
            )

            // Remove from local list
            conversations.removeAll { $0.id == conversation.id }

            // Clear active conversation if it's the one we're leaving
            if activeConversation?.id == conversation.id {
                activeConversation = nil
                messages = []
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Helper Methods

    func resolveConversationName(_ conversation: Conversation) -> Conversation {
        guard let currentUserId = self.currentUserId else { return conversation }

        var updatedConversation = conversation

        if conversation.type == .direct {
            // For direct conversations, find the other participant
            let otherUserId = conversation.participants.first(where: { $0 != currentUserId }) ?? conversation.participants.first ?? ""

            // Look up the user in our cached organization users
            if let otherUser = organizationUsers.first(where: { $0.id == otherUserId }) {
                updatedConversation.resolvedDisplayName = otherUser.fullName
            }
        } else {
            // For group conversations, create a list of participant names
            let participantNames = conversation.participants.compactMap { participantId in
                organizationUsers.first(where: { $0.id == participantId })?.firstName
            }.prefix(3)

            if !participantNames.isEmpty {
                var groupName = participantNames.joined(separator: ", ")
                if conversation.participants.count > 3 {
                    groupName += " and \(conversation.participants.count - 3) others"
                }
                updatedConversation.resolvedDisplayName = groupName
            }
        }

        return updatedConversation
    }

    func resolveConversationNames(_ conversations: [Conversation]) -> [Conversation] {
        return conversations.map { resolveConversationName($0) }
    }

    func updateTotalUnreadCount() {
        guard let userId = currentUserId else { return }
        totalUnreadCount = conversations.reduce(0) { $0 + $1.unreadCount(for: userId) }
    }

    private func getSenderName() async -> String {
        guard let userId = currentUserId else { return "Unknown" }

        // Check cached users first
        if let user = organizationUsers.first(where: { $0.id == userId }) {
            return user.fullName
        }

        // Fallback to AppStorage values
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let email = UserDefaults.standard.string(forKey: "userEmail") ?? ""

        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? email : fullName
    }

    // MARK: - Cleanup

    func cleanup() {
        Task {
            await conversationsChannel?.unsubscribe()
            await messagesChannel?.unsubscribe()
        }
        conversationsChannel = nil
        messagesChannel = nil

        // Prune old cache
        cacheService.pruneOldCache()
    }

    func cleanupMessageListener() {
        Task {
            await messagesChannel?.unsubscribe()
        }
        messagesChannel = nil
    }

    func clearMessagesCache(for conversationId: String) {
        cacheService.clearMessagesCache(conversationId: conversationId)
    }

    func refreshMessages() async {
        guard let conversation = activeConversation else { return }

        // Clear cache for this conversation
        cacheService.clearMessagesCache(conversationId: conversation.id)

        // Reset pagination
        currentMessageOffset = 0
        hasMoreMessages = true

        // Reload messages
        await loadMessages(for: conversation)
    }

    // MARK: - File Upload Methods

    func uploadImage(data: Data) async -> String? {
        // Image upload not yet implemented for Supabase Chat
        errorMessage = "Image upload not yet implemented"
        return nil
    }

    func uploadFile(data: Data, fileName: String) async -> String? {
        // File upload not yet implemented for Supabase Chat
        errorMessage = "File upload not yet implemented"
        return nil
    }

    deinit {
        Task {
            await conversationsChannel?.unsubscribe()
            await messagesChannel?.unsubscribe()
        }
    }
}

// MARK: - Chat Errors
enum ChatError: LocalizedError {
    case notAuthenticated
    case noOrganization
    case conversationNotFound
    case messageSendFailed
    case permissionDenied
    case notAParticipant
    case cannotLeaveDirect
    case cannotLeaveLastTwo

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to use chat"
        case .noOrganization:
            return "No organization found"
        case .conversationNotFound:
            return "Conversation not found"
        case .messageSendFailed:
            return "Failed to send message"
        case .permissionDenied:
            return "You don't have permission to access this conversation"
        case .notAParticipant:
            return "You are not a participant in this conversation"
        case .cannotLeaveDirect:
            return "Cannot leave direct conversations"
        case .cannotLeaveLastTwo:
            return "Cannot leave group - at least 2 participants must remain"
        }
    }
}

// MARK: - Debouncer
class Debouncer {
    private var workItem: DispatchWorkItem?
    private let delay: TimeInterval
    private let queue: DispatchQueue

    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        let newWorkItem = DispatchWorkItem(block: action)
        workItem = newWorkItem
        queue.asyncAfter(deadline: .now() + delay, execute: newWorkItem)
    }

    func cancel() {
        workItem?.cancel()
    }
}
