import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine
import StreamChat

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
    
    // Stream Chat Mode
    private let useStreamChat = true  // Toggle this to switch between Firestore and Stream
    
    // Services
    private let chatService: ChatServiceProtocol
    private let cacheService: ChatCacheServiceProtocol
    private let readCounter: ReadCounterProtocol
    
    // Firestore listeners
    private var conversationsListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    private var lastMessageDoc: DocumentSnapshot?
    
    // Stream controllers (defined in extension)
    var channelListController: ChatChannelListController?
    var channelController: ChatChannelController?
    
    // State management for Stream updates
    var isProcessingStreamUpdate = false
    var hasLoadedInitialMessages = false
    
    // Debouncing
    private var messageUpdateDebouncer = Debouncer(delay: 0.1)
    
    // Current user info
    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    var currentUserOrganizationId: String? {
        UserManager.shared.getCachedOrganizationID()
    }
    
    // Singleton instance
    static let shared = ChatManager()
    
    private init() {
        self.chatService = ChatService.shared
        self.cacheService = ChatCacheService.shared
        self.readCounter = ReadCounterService.shared
    }
    
    // MARK: - Initialization
    
    func initialize() async {
        // Load users first so we can resolve conversation names
        await loadOrganizationUsers()
        
        if useStreamChat {
            await initializeWithStream()
        } else {
            await loadConversations()
        }
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
            return conv1.lastActivity.dateValue() > conv2.lastActivity.dateValue()
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
        
        // 2. Set up real-time listener
        conversationsListener = chatService.subscribeToUserConversations(userId: userId) { [weak self] updatedConversations in
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
        
        if useStreamChat {
            return try await createStreamConversation(with: participants, type: type, customName: customName)
        } else {
            // Ensure current user is in participants
            var allParticipants = participants
            if !allParticipants.contains(userId) {
                allParticipants.append(userId)
            }
            
            let conversationId = try await chatService.createConversation(
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
    }
    
    func selectConversation(_ conversation: Conversation, markAsRead: Bool = true) async {
        if useStreamChat {
            await selectStreamConversation(conversation)
        } else {
            self.activeConversation = conversation
            await loadMessages(for: conversation)
            
            // Mark messages as read only if requested (i.e., user is actively viewing the conversation)
            if markAsRead, let userId = currentUserId {
                Task {
                    try? await chatService.markMessagesAsRead(conversationId: conversation.id, userId: userId)
                }
            }
        }
    }
    
    // MARK: - Message Management
    
    func loadMessages(for conversation: Conversation) async {
        self.activeConversation = conversation
        self.messagesLoading = true
        self.lastMessageDoc = nil
        self.hasMoreMessages = true
        
        // 1. Load from cache first for immediate display
        let cachedMessages = cacheService.getCachedMessages(conversationId: conversation.id)
        
        if let cachedMessages = cachedMessages, !cachedMessages.isEmpty {
            self.messages = cachedMessages
            self.messagesLoading = false
            readCounter.recordCacheHit(collection: "messages", component: "ChatManager", savedReads: cachedMessages.count)
            
            // Get the latest timestamp from cache
            let latestTimestamp = cachedMessages.last?.timestamp
            
            // Set up listener for only new messages
            messagesListener = chatService.subscribeToNewMessages(
                conversationId: conversation.id,
                afterTimestamp: latestTimestamp
            ) { [weak self] newMessages, isIncremental in
                guard let self = self else { return }
                
                if !newMessages.isEmpty {
                    // Remove any temporary messages
                    self.messages.removeAll { $0.id.hasSuffix("_temp") }
                    
                    // Append new messages and update cache
                    let updatedMessages = self.cacheService.appendNewMessages(
                        conversationId: conversation.id,
                        newMessages: newMessages
                    )
                    self.messages = updatedMessages
                    
                    self.readCounter.recordRead(
                        operation: "subscribeToNewMessages",
                        collection: "messages",
                        component: "ChatManager",
                        count: newMessages.count
                    )
                }
            }
        } else {
            // No cache, load recent messages
            readCounter.recordCacheMiss(collection: "messages", component: "ChatManager")
            
            do {
                // Load only recent messages (last 30)
                let result = try await chatService.getConversationMessages(
                    conversationId: conversation.id,
                    limit: 30,
                    lastDocument: nil
                )
                
                self.messages = result.messages
                self.lastMessageDoc = result.lastDoc
                self.hasMoreMessages = result.hasMore
                self.messagesLoading = false
                
                // Cache the initial messages
                cacheService.setCachedMessages(conversationId: conversation.id, messages: result.messages)
                
                readCounter.recordRead(
                    operation: "getConversationMessages",
                    collection: "messages",
                    component: "ChatManager",
                    count: result.messages.count
                )
                
                // Set up listener for new messages only
                let latestTimestamp = result.messages.last?.timestamp
                messagesListener = chatService.subscribeToNewMessages(
                    conversationId: conversation.id,
                    afterTimestamp: latestTimestamp
                ) { [weak self] newMessages, isIncremental in
                    guard let self = self else { return }
                    
                    if !newMessages.isEmpty {
                        // Remove any temporary messages
                        self.messages.removeAll { $0.id.hasSuffix("_temp") }
                        
                        // Append new messages and update cache
                        let updatedMessages = self.cacheService.appendNewMessages(
                            conversationId: conversation.id,
                            newMessages: newMessages
                        )
                        self.messages = updatedMessages
                        
                        self.readCounter.recordRead(
                            operation: "subscribeToNewMessages",
                            collection: "messages",
                            component: "ChatManager",
                            count: newMessages.count
                        )
                    }
                }
            } catch {
                self.messagesLoading = false
                self.errorMessage = "Failed to load messages"
            }
        }
    }
    
    func loadMoreMessages() async {
        guard let conversation = activeConversation, hasMoreMessages else { return }
        
        if useStreamChat {
            await loadMoreStreamMessages()
            return
        }
        
        do {
            let result = try await chatService.getConversationMessages(
                conversationId: conversation.id,
                limit: 30,
                lastDocument: lastMessageDoc
            )
            
            // Prepend older messages
            let allMessages = result.messages + messages
            messages = allMessages
            lastMessageDoc = result.lastDoc
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
              let currentUser = Auth.auth().currentUser,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        if useStreamChat {
            await sendStreamMessage(text: text)
            return
        }
        
        isSendingMessage = true
        errorMessage = nil
        
        do {
            // Get current user info from cache or fetch
            let senderName = await getSenderName()
            
            // Create optimistic message for immediate display
            let optimisticMessage = ChatMessage(
                id: UUID().uuidString + "_temp",
                senderId: currentUser.uid,
                senderName: senderName,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                fileUrl: fileUrl,
                timestamp: Timestamp(date: Date()),
                createdAt: Timestamp(date: Date()),
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
            
            // Add optimistic message immediately
            messages.append(optimisticMessage)
            
            _ = try await chatService.sendMessage(
                conversationId: conversation.id,
                senderId: currentUser.uid,
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
            let users = try await chatService.getOrganizationUsers(organizationId: orgId)
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
            try await chatService.togglePinConversation(
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
            try await chatService.updateConversationName(
                conversationId: conversation.id,
                newName: newName
            )
        } catch {
            errorMessage = "Failed to update conversation name"
        }
    }
    
    func addParticipants(_ userIds: [String], to conversation: Conversation) async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            let addedByName = await getSenderName()
            try await chatService.addParticipantsToConversation(
                conversationId: conversation.id,
                newParticipantIds: userIds,
                addedBy: (id: currentUser.uid, name: addedByName)
            )
        } catch {
            errorMessage = "Failed to add participants"
        }
    }
    
    func removeParticipant(_ participantId: String, from conversation: Conversation, participantName: String) async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            let removedByName = await getSenderName()
            try await chatService.removeParticipantFromConversation(
                conversationId: conversation.id,
                participantId: participantId,
                removedBy: (id: currentUser.uid, name: removedByName),
                removedUserName: participantName
            )
        } catch {
            errorMessage = "Failed to remove participant"
        }
    }
    
    func deleteConversation(_ conversation: Conversation) async {
        do {
            try await chatService.deleteConversation(conversationId: conversation.id)
            
            // Remove from local list
            conversations.removeAll { $0.id == conversation.id }
        } catch {
            errorMessage = "Failed to delete conversation"
        }
    }
    
    func leaveConversation(_ conversation: Conversation) async -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Not authenticated"
            return false
        }
        
        do {
            let userName = await getSenderName()
            try await chatService.leaveConversation(
                conversationId: conversation.id,
                userId: currentUser.uid,
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
    
    func updateMessagesFromStreamMessages(_ streamMessages: [StreamChat.ChatMessage]) {
        // This is called from the extension and from refreshMessages
        // Convert Stream messages to our ChatMessage model
        // Stream Chat returns messages in newest-first order, but our UI expects oldest-first
        let sortedMessages = streamMessages.sorted { $0.createdAt < $1.createdAt }
        
        // Remove any temporary messages before updating
        let hasTemp = messages.contains { $0.id.hasSuffix("_temp") }
        if hasTemp {
            print("[StreamChat] Removing temporary messages")
        }
        
        self.messages = sortedMessages.map { StreamChatAdapter.convertToChatMessage($0) }
        print("[StreamChat] Updated messages array with \(self.messages.count) messages (sorted oldest-first)")
    }
    
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
        let email = Auth.auth().currentUser?.email ?? ""
        
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? email : fullName
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        conversationsListener?.remove()
        messagesListener?.remove()
        conversationsListener = nil
        messagesListener = nil
        
        // Prune old cache
        cacheService.pruneOldCache()
    }
    
    func cleanupMessageListener() {
        messagesListener?.remove()
        messagesListener = nil
    }
    
    func clearMessagesCache(for conversationId: String) {
        cacheService.clearMessagesCache(conversationId: conversationId)
    }
    
    func refreshMessages() async {
        guard let conversation = activeConversation else { return }
        
        if useStreamChat {
            // For Stream, re-synchronize the channel and reload messages
            if let controller = channelController {
                do {
                    try await controller.synchronize()
                    
                    // Force reload messages
                    let messages = controller.messages
                    updateMessagesFromStreamMessages(Array(messages))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            // Clear cache for this conversation
            cacheService.clearMessagesCache(conversationId: conversation.id)
            
            // Reset pagination
            lastMessageDoc = nil
            hasMoreMessages = true
            
            // Reload messages
            await loadMessages(for: conversation)
        }
    }
    
    // MARK: - File Upload Methods
    
    func uploadImage(data: Data) async -> String? {
        // Use Stream Chat for uploads when enabled
        if useStreamChat {
            return await sendStreamMessageWithImage(data: data)
        }
        
        // Fallback to Firebase for non-Stream mode (if needed in future)
        // For now, return nil since we're using Stream
        errorMessage = "Image upload only supported with Stream Chat"
        return nil
    }
    
    func uploadFile(data: Data, fileName: String) async -> String? {
        // Use Stream Chat for uploads when enabled
        if useStreamChat {
            return await sendStreamMessageWithFile(data: data, fileName: fileName)
        }
        
        // Fallback to Firebase for non-Stream mode (if needed in future)
        // For now, return nil since we're using Stream
        errorMessage = "File upload only supported with Stream Chat"
        return nil
    }
    
    deinit {
        conversationsListener?.remove()
        messagesListener?.remove()
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