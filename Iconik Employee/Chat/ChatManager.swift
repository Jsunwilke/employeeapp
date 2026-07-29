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

    /// True once the user has paged back into history, after which the newest-page
    /// fetch stops being allowed to answer `hasMoreMessages`.
    private var hasPagedBack = false
    /// One "Load earlier" in flight at a time; two concurrent taps would both
    /// compute the same offset and fetch the same page.
    ///
    /// PUBLISHED, because the button needs to show a spinner. It was private,
    /// and the button read `messagesLoading` instead — which `loadMoreMessages`
    /// never sets, so tapping "Load earlier" gave no feedback at all while the
    /// initial load spun the button at the one moment it should not.
    @Published var isLoadingMoreMessages = false
    /// Ids of optimistic messages that the server has not confirmed yet. They are
    /// excluded from the paging offset, and a failed send removes exactly its own
    /// id — the previous code removed EVERY unconfirmed message on any failure,
    /// so one failed send erased other sends still in flight.
    private var pendingMessageIds: Set<String> = []

    /// The conversation whose thread is ACTUALLY ON SCREEN.
    ///
    /// Deliberately not `activeConversation`, which is never cleared when the user
    /// leaves a thread — keying "mark this read" off that would keep zeroing a
    /// conversation the user walked away from, hiding genuinely unread messages.
    /// Set and cleared by MessageThreadView's appear/disappear.
    private var viewingConversationId: String?

    /// Read-only view of the on-screen thread for PushNotificationManager.willPresent
    /// (PSH.2 review round): a chat push for the conversation the person is READING must
    /// not banner-and-buzz over it — the realtime stream already renders the message in
    /// place. Same signal, same lifecycle, as the mark-read logic above.
    var visibleConversationId: String? { viewingConversationId }

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

        // 2. Set up real-time listener using Supabase.
        // Unsubscribe any previous channel first to avoid leaking it on reload.
        await conversationsChannel?.unsubscribe()
        conversationsChannel = supabaseChatService.subscribeToUserConversations(userId: userId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let updatedConversations):
                // Resolve names and sort conversations
                let resolvedConversations = self.resolveConversationNames(updatedConversations)
                self.conversations = self.sortConversations(resolvedConversations)
                self.isLoading = false
                self.errorMessage = nil
                self.updateTotalUnreadCount()

                // THIS is where the badge had to be cleared, and hooking the
                // messages callback instead is why the previous attempt failed.
                // A send is three writes: insert the message, update the
                // conversation, then raise the unread counts. The MESSAGES event
                // fires from the first, two round trips BEFORE the count exists —
                // so marking there always saw 0 and returned. The count only
                // appears here, on the conversations event, and nothing re-marked.
                self.markViewedConversationRead()

                // Cache the updated data (without resolved names to keep cache clean)
                self.cacheService.setCachedConversations(updatedConversations)

                // Record reads
                self.readCounter.recordRead(
                    operation: "subscribeToUserConversations",
                    collection: "conversations",
                    component: "ChatManager",
                    count: updatedConversations.count
                )

            case .failure(let error):
                // Keep whatever is already on screen — a failed fetch is not the
                // same as having no conversations, and treating it as such is how
                // this list used to blank itself silently. Still clear isLoading,
                // or the spinner runs forever.
                self.isLoading = false
                self.errorMessage = "Couldn't load conversations: \(error.localizedDescription)"
            }
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
        await loadMessages(for: conversation)

        // Mark messages as read only if requested (i.e., user is actively viewing
        // the conversation). Registering here as well as in the view's onAppear
        // covers `openChannel(cid:)`, which selects a conversation without the
        // thread having appeared yet.
        if markAsRead {
            viewingConversationId = conversation.id
            markViewedConversationRead()
        }
    }

    /// Called by the thread as it appears and disappears, so the manager knows
    /// whether anything is actually being read.
    func beginViewing(_ conversationId: String) {
        viewingConversationId = conversationId
    }

    func endViewing(_ conversationId: String) {
        // Only clear if it is still OURS. During a push transition the incoming
        // screen's onAppear can run before the outgoing screen's onDisappear, and
        // an unconditional clear would wipe the new thread's registration.
        if viewingConversationId == conversationId {
            viewingConversationId = nil
        }
    }

    /// Zero the on-screen conversation's unread count, locally and on the server.
    ///
    /// The local half matters: the server call only reached the UI via a realtime
    /// round trip, so opening a conversation left its unread pill and the tab bar
    /// badge sitting there until the echo arrived.
    private func markViewedConversationRead() {
        guard let conversationId = viewingConversationId, let userId = currentUserId else { return }

        // Nothing to do, and worth checking so a busy thread is not firing an
        // RPC per incoming message.
        // `guard let`, not `if let`. With `if let` a conversation missing from the
        // list fell through to the RPC on EVERY incoming message — and each RPC
        // updates conversations, which fires the conversations channel, which
        // refetches: two extra round trips per message, indefinitely.
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        // The `> 0` test is ALSO what stops this recursing. Marking writes to
        // `conversations`, which fires the conversations channel, which calls this
        // again — but by then the server value is 0, so it returns here. One hop,
        // always. When a genuinely new message raises the count again the cycle
        // repeats, which is correct: that is a real message being read.
        guard conversations[index].unreadCount(for: userId) > 0 else { return }

        conversations[index].unread_counts[userId] = 0
        updateTotalUnreadCount()

        Task {
            do {
                try await supabaseChatService.markMessagesAsRead(conversationId: conversationId, userId: userId)
            } catch {
                print("⚠️ mark-as-read failed for \(conversationId): \(error)")
            }
        }
    }

    // MARK: - Message Management

    func loadMessages(for conversation: Conversation) async {
        let isSameConversation = activeConversation?.id == conversation.id

        self.activeConversation = conversation
        self.messagesLoading = true
        self.hasPagedBack = false

        // Opening a DIFFERENT conversation clears the thread first. This array is
        // shared across every chat screen, and it used to survive the switch — so
        // the new conversation opened showing the PREVIOUS one's messages until
        // its own fetch landed. Harmless-looking until a redesign draws a count
        // from it, at which point the number is simply wrong.
        if !isSameConversation {
            self.messages = []
        }

        // 1. Load from cache first for immediate display
        let cachedMessages = cacheService.getCachedMessages(conversationId: conversation.id)

        if let cachedMessages = cachedMessages, !cachedMessages.isEmpty {
            self.messages = cachedMessages
            self.messagesLoading = false
            readCounter.recordCacheHit(collection: "messages", component: "ChatManager", savedReads: cachedMessages.count)
        } else {
            readCounter.recordCacheMiss(collection: "messages", component: "ChatManager")
        }

        // 2. Set up real-time listener for all messages.
        // Unsubscribe the previous conversation's channel first — otherwise
        // switching conversations leaks a channel each time and stale
        // callbacks keep firing.
        await messagesChannel?.unsubscribe()
        messagesChannel = supabaseChatService.subscribeToConversationMessages(conversationId: conversation.id) { [weak self] result in
            guard let self = self else { return }

            // A late callback from a conversation the user has already left must
            // not write into the thread they are now looking at.
            guard self.activeConversation?.id == conversation.id else { return }

            switch result {
            case .success(let page):
                // MERGE rather than replace. Replacing threw away everything
                // "Load earlier" had paged in, on every single realtime event.
                self.messages = self.merge(page.messages, into: self.messages)
                self.messagesLoading = false

                // Only the first page may answer "is there older history?". Once
                // the user has paged back, `loadMoreMessages` owns that answer —
                // otherwise reaching the very beginning of a thread and then
                // receiving any message would re-offer "Load earlier" forever.
                if !self.hasPagedBack {
                    self.hasMoreMessages = page.hasMore
                }

                // Cache the updated messages
                self.cacheService.setCachedMessages(conversationId: conversation.id, messages: self.messages)

                // You are LOOKING at this thread, so anything that just arrived
                // is already read. Kept as well as the conversations-callback hook
                // because it covers the case where the count was ALREADY non-zero
                // when the page arrived; the conversations hook covers the count
                // being raised while the thread is open. Both are guarded by the
                // same `> 0` test, so neither loops.
                self.markViewedConversationRead()

                self.readCounter.recordRead(
                    operation: "subscribeToConversationMessages",
                    collection: "messages",
                    component: "ChatManager",
                    count: page.messages.count
                )

            case .failure(let error):
                self.messagesLoading = false
                self.errorMessage = "Couldn't load messages: \(error.localizedDescription)"
            }
        }
    }

    func loadMoreMessages() async {
        guard let conversation = activeConversation, hasMoreMessages, !isLoadingMoreMessages else { return }

        isLoadingMoreMessages = true
        defer { isLoadingMoreMessages = false }

        do {
            // The offset is the number of CONFIRMED messages already loaded, not a
            // page counter. Optimistic sends are excluded because they do not
            // exist server-side and would shift every subsequent page by one.
            let loadedCount = messages.filter { !pendingMessageIds.contains($0.id) }.count

            let result = try await supabaseChatService.getConversationMessages(
                conversationId: conversation.id,
                limit: SupabaseChatService.messagePageSize,
                offset: loadedCount
            )

            hasPagedBack = true
            messages = merge(result.messages, into: messages)
            hasMoreMessages = result.hasMore

            // Update cache
            cacheService.setCachedMessages(conversationId: conversation.id, messages: messages)

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

    /// Union by id, ordered oldest to newest. The server's copy of a message wins
    /// over a local optimistic one, which is what retires an optimistic send now
    /// that both carry the SAME id.
    private func merge(_ incoming: [ChatMessage], into existing: [ChatMessage]) -> [ChatMessage] {
        var byId: [String: ChatMessage] = [:]
        for message in existing { byId[message.id] = message }
        for message in incoming { byId[message.id] = message }

        return byId.values.sorted {
            if $0.timestamp == $1.timestamp { return $0.id < $1.id }
            return $0.timestamp < $1.timestamp
        }
    }

    /// Returns whether the message reached the server, so the composer can keep
    /// the user's text on failure instead of throwing it away.
    /// `into` pins the destination. Callers that do slow work before sending
    /// (an attachment upload) MUST pass the conversation they started with,
    /// because `activeConversation` can change underneath them.
    @discardableResult
    func sendMessage(text: String, type: ChatMessage.MessageType = .text, fileUrl: String? = nil,
                     into destination: Conversation? = nil) async -> Bool {
        guard let conversation = destination ?? activeConversation,
              let currentUserId = UserManager.shared.getCurrentUserIDUnified(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        isSendingMessage = true
        errorMessage = nil

        // The id is minted HERE and handed to the insert, so the optimistic
        // message and the row the server stores are the same message. The merge
        // then retires the optimistic copy by id instead of the old approach of
        // deleting everything whose id ended in "_temp".
        let messageId = UUID().uuidString.lowercased()

        // Hoisted out of the `do` so the failure path can read it: whether this
        // send's destination is the thread currently on screen. It decides both
        // where the optimistic bubble goes and whose cache may be rewritten.
        let showsOnScreen = activeConversation?.id == conversation.id

        do {
            // Get current user info from cache or fetch
            let senderName = await getSenderName()

            // Create optimistic message for immediate display
            let optimisticMessage = ChatMessage(
                id: messageId,
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

            // Add optimistic message immediately — but ONLY if it belongs to the
            // thread currently on screen. An attachment send that finished after
            // the user moved on would otherwise drop a bubble into whatever
            // conversation they are now looking at.
            if showsOnScreen {
                pendingMessageIds.insert(messageId)
                messages = merge([optimisticMessage], into: messages)
            }

            try await supabaseChatService.sendMessage(
                messageId: messageId,
                conversationId: conversation.id,
                senderId: currentUserId,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                fileUrl: fileUrl,
                senderName: senderName
            )

            pendingMessageIds.remove(messageId)

            // Note: Real-time listener will update with the actual message
            readCounter.recordRead(
                operation: "sendMessage",
                collection: "messages",
                component: "ChatManager",
                count: 1
            )

            isSendingMessage = false
            return true
        } catch {
            // Remove ONLY this message. Other sends may still be in flight.
            pendingMessageIds.remove(messageId)
            messages.removeAll { $0.id == messageId }
            // The optimistic copy is dropped from the CACHE too, so a realtime
            // event landing between the merge and this failure cannot persist a
            // message that never existed.
            //
            // ONLY when this send's conversation is the one on screen. `messages`
            // holds the ACTIVE thread, and `conversation` is the send's
            // DESTINATION — which can differ for an attachment the user walked
            // away from. Writing one into the other's cache poisoned the
            // destination with a different conversation's messages, and the
            // union-only merge meant they never evicted.
            // RE-READ, not the snapshot taken before the await. The previous
            // attempt at this fix hoisted `showsOnScreen` from before the network
            // round trip and tested it here, which left the whole bug intact and
            // merely moved the window: leave the thread WHILE the send is in
            // flight and the stale `true` wrote the NEW thread's messages into
            // the OLD thread's cache. Fixing the instance is not fixing the class.
            if activeConversation?.id == conversation.id {
                cacheService.setCachedMessages(conversationId: conversation.id, messages: messages)
            }
            errorMessage = "Failed to send message: \(error.localizedDescription)"

            isSendingMessage = false
            return false
        }
    }

    // MARK: - User Management

    func loadOrganizationUsers() async {
        // The TWIN of the dead guard fixed in sendAttachment: same cause, same
        // file. `getCachedOrganizationID()` returns a NON-optional String and
        // yields "", so `guard let` never fired and this queried users with
        // organization_id = '', got nothing, cached nothing — and every direct
        // conversation then fell back to its default_name because there were no
        // users to resolve names against. Reachable at launch, before the org id
        // is cached.
        let orgId = currentUserOrganizationId ?? ""
        guard !orgId.isEmpty else { return }

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

    /// NEITHER OF THESE USED TO UNSUBSCRIBE ANYTHING, and de1eed5 is what made
    /// that matter: this type is `@MainActor` and both functions are
    /// synchronous, so the `Task` body could not begin until the function had
    /// already returned — by which point the properties were nil and
    /// `await channel?.unsubscribe()` was a no-op on nil. Deterministically.
    ///
    /// It went unnoticed because `cleanup()` had never once been called (its
    /// call site compared a value against itself). Fixing that call site turned
    /// a dormant no-op into a live leak: the SDK caches channels by topic and
    /// re-registering `postgresChange` on an already-subscribed channel is
    /// refused, so every re-opened conversation kept an orphaned fetch loop.
    ///
    /// The channels are captured into locals BEFORE the properties are cleared,
    /// so the detached task holds real references.
    func cleanup() {
        let conversations = conversationsChannel
        let messages = messagesChannel
        conversationsChannel = nil
        messagesChannel = nil

        Task {
            await conversations?.unsubscribe()
            await messages?.unsubscribe()
        }

        // Prune old cache
        cacheService.pruneOldCache()
    }

    func cleanupMessageListener() {
        let channel = messagesChannel
        messagesChannel = nil

        Task { await channel?.unsubscribe() }
    }

    func clearMessagesCache(for conversationId: String) {
        cacheService.clearMessagesCache(conversationId: conversationId)
    }

    func refreshMessages() async {
        guard let conversation = activeConversation else { return }

        // Clear cache for this conversation
        cacheService.clearMessagesCache(conversationId: conversation.id)

        // Drop the loaded history so the refresh genuinely starts from the newest
        // page. `hasMoreMessages` is deliberately NOT forced true here — the
        // reload's own first page answers that now.
        messages = []
        pendingMessageIds.removeAll()
        hasPagedBack = false

        // Reload messages
        await loadMessages(for: conversation)
    }

    // MARK: - Attachments

    /// Upload an image and post it as a message.
    ///
    /// This replaces `uploadImage`, which set "Image upload not yet implemented"
    /// and returned nil. Note the caller ALSO threw the result away, so even a
    /// working upload would not have posted anything — the two halves were
    /// broken independently.
    @discardableResult
    func sendImageMessage(data: Data) async -> Bool {
        await sendAttachment(data: data, fileExtension: "jpg", contentType: "image/jpeg", caption: "📷 Photo")
    }

    /// Upload a file and post it as a message.
    @discardableResult
    func sendFileMessage(data: Data, fileName: String) async -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return await sendAttachment(
            data: data,
            fileExtension: ext.isEmpty ? "dat" : ext,
            contentType: Self.contentType(forExtension: ext),
            caption: fileName
        )
    }

    /// The conversation is pinned for the WHOLE operation.
    ///
    /// This used to capture `activeConversation` for the upload and then call
    /// `sendMessage`, which re-read `activeConversation` afterwards — with a
    /// multi-second upload in between. Leaving the thread mid-upload therefore
    /// filed the message against a DIFFERENT conversation than the one the file
    /// was uploaded into, and since the storage policy scopes reads per
    /// conversation, nobody in the destination could open it.
    private func sendAttachment(data: Data, fileExtension: String, contentType: String, caption: String) async -> Bool {
        guard let conversation = activeConversation else { return false }
        // `getCachedOrganizationID()` returns a NON-optional String and yields ""
        // when it does not know, so `guard let` never fired. The empty value then
        // became the first path segment, which the bucket's WITH CHECK rejects
        // with an opaque storage error instead of this sentence.
        let organizationId = currentUserOrganizationId ?? ""
        guard !organizationId.isEmpty else {
            errorMessage = "No organization found — can't attach files."
            return false
        }

        errorMessage = nil

        do {
            let path = try await supabaseChatService.uploadAttachment(
                organizationId: organizationId,
                conversationId: conversation.id,
                data: data,
                fileExtension: fileExtension,
                contentType: contentType
            )

            // The STORAGE PATH goes in file_url, not a signed URL — a signed URL
            // stored in the row expires and leaves the message pointing at
            // nothing. ChatAttachment signs it at render time instead.
            return await sendMessage(text: caption, type: .file, fileUrl: path, into: conversation)
        } catch {
            errorMessage = "Couldn't upload attachment: \(error.localizedDescription)"
            return false
        }
    }

    private static func contentType(forExtension ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    // No deinit. This is a `static let shared` singleton, so deinit is
    // unreachable — the one that used to be here captured self in a Task that
    // outlives deinit (a Swift 6 error) to do teardown that could never run.
    // Teardown happens in `cleanup()`, which now actually fires: see the
    // previousTab comparison in MainEmployeeView's tab-change handler.
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
