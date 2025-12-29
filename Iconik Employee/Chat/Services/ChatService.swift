import Foundation

// DEPRECATED: This file is no longer used.
// The app now uses SupabaseChatService exclusively.
// This file is kept for reference only and will be removed in a future cleanup.

// Legacy protocol stub - kept for reference
protocol ChatServiceProtocol {
    // Conversation Management
    func createConversation(participants: [String], type: Conversation.ConversationType, customName: String?) async throws -> String
    func getUserConversations(userId: String) async throws -> [Conversation]
    func updateConversationName(conversationId: String, newName: String) async throws

    // Messaging
    func sendMessage(conversationId: String, senderId: String, text: String, type: ChatMessage.MessageType, fileUrl: String?, senderName: String) async throws -> String
    func markMessagesAsRead(conversationId: String, userId: String) async throws

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

// Note: ChatService class implementation has been removed.
// Use SupabaseChatService.shared instead.
