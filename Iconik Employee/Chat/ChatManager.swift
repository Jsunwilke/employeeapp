import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

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
    private let chatService: ChatServiceProtocol
    private let cacheService: ChatCacheServiceProtocol
    private let readCounter: ReadCounterProtocol
    
    // Firestore listeners
    private var conversationsListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    private var lastMessageDoc: DocumentSnapshot?
    
    // Debouncing
    private var messageUpdateDebouncer = Debouncer(delay: 0.1)
    
    // Current user info
    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    private var currentUserOrganizationId: String? {
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
        await loadConversations()
    }
    
    // MARK: - Conversation Management
    
    func loadConversations() async {
        guard let userId = currentUserId else {
            errorMessage = "Not authenticated"
            isLoading = false
            return
        }
        
        // 1. Load from cache first
        if let cachedConversations = cacheService.getCachedConversations() {
            self.conversations = resolveConversationNames(cachedConversations)
            self.isLoading = false
            updateTotalUnreadCount()
            readCounter.recordCacheHit(collection: "conversations", component: "ChatManager", savedReads: cachedConversations.count)
        } else {
            readCounter.recordCacheMiss(collection: "conversations", component: "ChatManager")
        }
        
        // 2. Set up real-time listener
        conversationsListener = chatService.subscribeToUserConversations(userId: userId) { [weak self] updatedConversations in
            guard let self = self else { return }
            
            // Resolve names before setting conversations
            self.conversations = self.resolveConversationNames(updatedConversations)
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
    
    func selectConversation(_ conversation: Conversation) async {
        self.activeConversation = conversation
        await loadMessages(for: conversation)
        
        // Mark messages as read
        if let userId = currentUserId {
            Task {
                try? await chatService.markMessagesAsRead(conversationId: conversation.id, userId: userId)
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
        
        // Mark as read
        Task {
            if let userId = self.currentUserId {
                try? await self.chatService.markMessagesAsRead(
                    conversationId: conversation.id,
                    userId: userId
                )
            }
        }
    }
    
    func loadMoreMessages() async {
        guard let conversation = activeConversation, hasMoreMessages else { return }
        
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
                createdAt: Timestamp(date: Date())
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
    
    // MARK: - Helper Methods
    
    private func resolveConversationNames(_ conversations: [Conversation]) -> [Conversation] {
        guard let currentUserId = self.currentUserId else { return conversations }
        
        return conversations.map { conversation in
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
    }
    
    private func updateTotalUnreadCount() {
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
        
        // Clear cache for this conversation
        cacheService.clearMessagesCache(conversationId: conversation.id)
        
        // Reset pagination
        lastMessageDoc = nil
        hasMoreMessages = true
        
        // Reload messages
        await loadMessages(for: conversation)
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