import Foundation
import SwiftUI
import StreamChat
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - ChatManager Stream Integration
extension ChatManager {
    
    // MARK: - Stream Integration Properties
    private var streamManager: StreamChatManager {
        StreamChatManager.shared
    }
    
    // MARK: - Initialize with Stream
    
    func initializeWithStream() async {
        // First connect to Stream
        do {
            try await streamManager.connect()
            
            // Load users for name resolution
            await loadOrganizationUsers()
            
            // Set up channel list controller
            await setupStreamChannels()
            
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
    
    // MARK: - Stream Channel Management
    
    private func setupStreamChannels() async {
        guard let controller = streamManager.createChannelListController() else {
            self.errorMessage = "Failed to create channel list"
            self.isLoading = false
            return
        }
        
        // Set self as delegate
        controller.delegate = self
        
        // Store controller
        self.channelListController = controller
        
        // Initial synchronization
        controller.synchronize { error in
            if let error = error {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }
    
    // MARK: - Create Conversation with Stream
    
    func createStreamConversation(with participants: [String], type: Conversation.ConversationType = .direct, customName: String? = nil) async throws -> String {
        guard Auth.auth().currentUser?.uid != nil else {
            throw ChatError.notAuthenticated
        }
        
        // Get participant users for names
        let participantUsers = organizationUsers.filter { participants.contains($0.id) }
        
        if type == .direct && participants.count == 1 {
            // Create direct message channel
            let otherUserId = participants[0]
            let otherUserName = participantUsers.first?.fullName
            
            let channel = try await streamManager.getOrCreateDirectMessageChannel(
                with: otherUserId,
                otherUserName: otherUserName
            )
            
            return channel.cid.id
        } else {
            // Create group channel
            let channel = try await streamManager.createGroupChannel(
                name: customName ?? "Group Chat",
                memberIds: participants
            )
            
            return channel.cid.id
        }
    }
    
    // MARK: - Select Conversation with Stream
    
    func selectStreamConversation(_ conversation: Conversation) async {
        self.activeConversation = conversation
        self.hasLoadedInitialMessages = false
        
        guard let client = streamManager.client else { return }
        
        // Create channel controller
        let cid = ChannelId(type: conversation.type == .direct ? .messaging : .team, id: conversation.id)
        let controller = client.channelController(for: cid)
        
        // Store controller first
        self.channelController = controller
        
        // Set as delegate (after storing to ensure we don't miss events)
        controller.delegate = self
        
        // Setting up channel controller for conversation: \(conversation.id)
        
        // Synchronize and load messages
        controller.synchronize { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            
            // Load initial messages after synchronization
            let initialMessages = controller.messages
            // After synchronize, loaded \(initialMessages.count) messages
            
            // Convert and set initial messages
            if !initialMessages.isEmpty {
                let sortedMessages = initialMessages.sorted { $0.createdAt < $1.createdAt }
                self.messages = sortedMessages.map { StreamChatAdapter.convertToChatMessage($0) }
                self.hasLoadedInitialMessages = true
                // Set initial messages: \(self.messages.count)
            } else {
                // Channel is empty, no need to load previous messages
                // Channel is empty (no messages to load)
                self.messages = []
                self.hasLoadedInitialMessages = true
                
                // Don't try to load previous messages if the channel is new/empty
                // This avoids the ChannelEmptyMessages error
            }
            
            // Mark as read using completion handler
            if let currentUserId = self.currentUserId {
                controller.markRead { _ in
                    // Update local unread count
                    if var conv = self.conversations.first(where: { $0.id == conversation.id }) {
                        conv.unreadCounts[currentUserId] = 0
                        if let index = self.conversations.firstIndex(where: { $0.id == conversation.id }) {
                            self.conversations[index] = conv
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Send Message with Image
    
    func sendStreamMessageWithImage(data: Data) async -> String? {
        guard let controller = channelController else {
            print("No channel controller available for sending image")
            return nil
        }
        
        guard currentUserId != nil else {
            print("No current user ID")
            return nil
        }
        
        isSendingMessage = true
        defer {
            isSendingMessage = false
        }
        
        do {
            // Create a temporary file for the image
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "\(UUID().uuidString).jpg"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            // Write image data to temporary file
            try data.write(to: fileURL)
            
            // Upload the image using Stream's attachment system
            let uploadedAttachment = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UploadedAttachment, Error>) in
                controller.uploadAttachment(
                    localFileURL: fileURL,
                    type: .image,
                    progress: nil
                ) { result in
                    continuation.resume(with: result)
                }
            }
            
            // Create and send message with the uploaded attachment
            // Use empty text since the image itself is the content
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                controller.createNewMessage(
                    text: "",
                    attachments: [
                        .init(payload: ImageAttachmentPayload(
                            title: nil,
                            imageRemoteURL: uploadedAttachment.remoteURL
                        ))
                    ]
                ) { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: fileURL)
            
            return "stream-image-sent"
        } catch {
            print("Image send error: \(error)")
            self.errorMessage = error.localizedDescription
            return nil
        }
    }
    
    // MARK: - Send Message with File
    
    func sendStreamMessageWithFile(data: Data, fileName: String) async -> String? {
        guard let controller = channelController else {
            print("No channel controller available for sending file")
            return nil
        }
        
        guard currentUserId != nil else {
            print("No current user ID")
            return nil
        }
        
        isSendingMessage = true
        defer {
            isSendingMessage = false
        }
        
        do {
            // Create a temporary file for the document
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            // Write data to temporary file
            try data.write(to: fileURL)
            
            // Upload the file using Stream's attachment system
            let uploadedAttachment = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UploadedAttachment, Error>) in
                controller.uploadAttachment(
                    localFileURL: fileURL,
                    type: .file,
                    progress: nil
                ) { result in
                    continuation.resume(with: result)
                }
            }
            
            // Create and send message with the uploaded file attachment
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                controller.createNewMessage(
                    text: "📎 \(fileName)",
                    attachments: [
                        .init(payload: FileAttachmentPayload(
                            title: fileName,
                            assetRemoteURL: uploadedAttachment.remoteURL,
                            file: .init(type: .generic, size: Int64(data.count), mimeType: nil),
                            extraData: nil
                        ))
                    ]
                ) { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: fileURL)
            
            return "stream-file-sent"
        } catch {
            print("File send error: \(error)")
            self.errorMessage = error.localizedDescription
            return nil
        }
    }
    
    // MARK: - Send Message with Stream
    
    func sendStreamMessage(text: String) async {
        guard let controller = channelController else {
            // No channel controller available for sending message
            return
        }
        
        guard let currentUserId = currentUserId else { 
            // No current user ID
            return 
        }
        
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sending message: '\(cleanText)'
        
        isSendingMessage = true
        defer { 
            isSendingMessage = false 
            // Send message operation complete
        }
        
        // Add optimistic message for immediate UI update
        let tempId = UUID().uuidString + "_temp"
        let optimisticMessage = ChatMessage(
            id: tempId,
            senderId: currentUserId,
            senderName: await getSenderName(),
            text: cleanText,
            type: .text,
            fileUrl: nil,
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
        // Added optimistic message with temp ID: \(tempId), total messages: \(messages.count)
        
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                controller.createNewMessage(text: cleanText) { result in
                    switch result {
                    case .success:
                        // Message sent successfully
                        // The real message will come through the delegate's didUpdateMessages
                        // The delegate will remove the temp message when it processes the insert
                        continuation.resume()
                    case .failure(let error):
                        print("[StreamChat] Failed to send message: \(error)")
                        // Remove optimistic message on error
                        Task { @MainActor in
                            // Removing failed optimistic message
                            self.messages.removeAll { $0.id == tempId }
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
            // Message send completed successfully
        } catch {
            print("[StreamChat] Message send error: \(error)")
            self.errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Load More Messages with Stream
    
    func loadMoreStreamMessages() async {
        guard let controller = channelController else { return }
        
        // Don't try to load more if channel is empty
        guard !controller.messages.isEmpty else {
            hasMoreMessages = false
            return
        }
        
        // Don't try to load if we've already loaded all messages
        guard !controller.hasLoadedAllPreviousMessages else {
            hasMoreMessages = false
            return
        }
        
        messagesLoading = true
        defer { messagesLoading = false }
        
        do {
            // Load previous page of messages
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                controller.loadPreviousMessages(limit: 25) { error in
                    if let error = error {
                        // Ignore the expected empty channel error
                        let errorString = "\(error)"
                        if errorString.contains("ChannelEmptyMessages") {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: error)
                        }
                    } else {
                        continuation.resume()
                    }
                }
            }
            
            // Update hasMoreMessages based on whether there are more to load
            hasMoreMessages = controller.hasLoadedAllPreviousMessages == false
        } catch {
            // Only show error if it's not the expected empty channel error
            let errorString = "\(error)"
            if !errorString.contains("ChannelEmptyMessages") {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Update Conversation from Stream Channel
    
    private func updateConversationsFromStreamChannels(_ channels: [ChatChannel]) {
        guard let currentUserId = currentUserId else { return }
        
        // Convert Stream channels to our Conversation model
        let updatedConversations = channels.map { channel in
            StreamChatAdapter.convertToConversation(channel, currentUserId: currentUserId)
        }
        
        // Resolve names and sort
        let resolvedConversations = resolveConversationNames(updatedConversations)
        self.conversations = sortConversations(resolvedConversations)
        
        // Update total unread count
        updateTotalUnreadCount()
    }
    
    // MARK: - Helper Methods
    
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
    
}

// MARK: - ChatChannelListControllerDelegate

extension ChatManager: ChatChannelListControllerDelegate {
    
    nonisolated func controller(_ controller: ChatChannelListController, didChangeChannels changes: [ListChange<StreamChat.ChatChannel>]) {
        Task { @MainActor in
            // Channel list updated with \(changes.count) changes
            self.updateConversationsFromStreamChannels(Array(controller.channels))
        }
    }
}

// MARK: - ChatChannelControllerDelegate

extension ChatManager: ChatChannelControllerDelegate {
    
    nonisolated func channelController(_ channelController: ChatChannelController, didUpdateMessages changes: [ListChange<StreamChatMessage>]) {
        Task { @MainActor in
            // Delegate: didUpdateMessages called with \(changes.count) changes
            
            // Skip if we haven't loaded initial messages yet
            guard self.hasLoadedInitialMessages else {
                // Skipping update - initial messages not loaded yet
                return
            }
            
            // Prevent concurrent updates
            guard !self.isProcessingStreamUpdate else {
                // Skipping update - already processing
                return
            }
            
            self.isProcessingStreamUpdate = true
            defer { self.isProcessingStreamUpdate = false }
            
            // Process each change individually
            var needsFullReload = false
            
            for change in changes {
                switch change {
                case .insert(let message, _):
                    // New message inserted at \(index): \(message.text)
                    
                    // Remove any temporary message with matching text
                    self.messages.removeAll { $0.id.hasSuffix("_temp") && $0.text == message.text }
                    
                    // Convert and insert the new message
                    let newMessage = StreamChatAdapter.convertToChatMessage(message)
                    
                    // Insert at correct position (messages should be oldest-first)
                    let insertIndex = self.messages.firstIndex { $0.timestamp.dateValue() > newMessage.timestamp.dateValue() } ?? self.messages.count
                    self.messages.insert(newMessage, at: insertIndex)
                    
                case .update(let message, _):
                    // Message updated
                    let updatedMessage = StreamChatAdapter.convertToChatMessage(message)
                    
                    // Find and update the message
                    if let existingIndex = self.messages.firstIndex(where: { $0.id == updatedMessage.id }) {
                        self.messages[existingIndex] = updatedMessage
                    }
                    
                case .remove(let message, _):
                    // Message removed
                    self.messages.removeAll { $0.id == message.id }
                    
                case .move:
                    // Message moved
                    needsFullReload = true
                }
            }
            
            // If we need a full reload (e.g., due to moves), reload all messages
            if needsFullReload {
                // Performing full reload of messages
                let allMessages = channelController.messages
                let sortedMessages = allMessages.sorted { $0.createdAt < $1.createdAt }
                self.messages = sortedMessages.map { StreamChatAdapter.convertToChatMessage($0) }
            }
            
            // After processing changes, total messages: \(self.messages.count)
            
            // Messages updated successfully
        }
    }
    
    nonisolated func channelController(_ channelController: ChatChannelController, didChangeTypingUsers typingUsers: Set<StreamChat.ChatUser>) {
        Task { @MainActor in
            // Handle typing indicators if needed
            // You can add a @Published property to show typing status
        }
    }
    
    nonisolated func channelController(_ channelController: ChatChannelController, didUpdateChannel channel: EntityChange<StreamChat.ChatChannel>) {
        Task { @MainActor in
            guard let currentUserId = Auth.auth().currentUser?.uid else { return }
            
            // Update the conversation in our list
            if case .update(let updatedChannel) = channel {
                let updatedConversation = StreamChatAdapter.convertToConversation(updatedChannel, currentUserId: currentUserId)
                
                if let index = self.conversations.firstIndex(where: { $0.id == updatedConversation.id }) {
                    self.conversations[index] = self.resolveConversationName(updatedConversation)
                    self.conversations = self.sortConversations(self.conversations)
                }
            }
        }
    }
}