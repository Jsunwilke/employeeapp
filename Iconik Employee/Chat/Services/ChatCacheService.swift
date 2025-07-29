import Foundation
import FirebaseFirestore

// MARK: - Chat Cache Service Protocol
protocol ChatCacheServiceProtocol {
    // Conversations
    func setCachedConversations(_ conversations: [Conversation])
    func getCachedConversations() -> [Conversation]?
    func clearConversationsCache()
    
    // Messages
    func setCachedMessages(conversationId: String, messages: [ChatMessage])
    func getCachedMessages(conversationId: String) -> [ChatMessage]?
    func appendNewMessages(conversationId: String, newMessages: [ChatMessage]) -> [ChatMessage]
    func getLatestCachedMessageTimestamp(conversationId: String) -> Timestamp?
    func clearMessagesCache(conversationId: String)
    func clearAllMessagesCache()
    
    // Users
    func setCachedUsers(_ users: [ChatUser])
    func getCachedUsers() -> [ChatUser]?
    func clearUsersCache()
    
    // Cache management
    func clearAllCache()
    func getCacheSize() -> Int
    func pruneOldCache()
}

// MARK: - Chat Cache Service Implementation
class ChatCacheService: ChatCacheServiceProtocol {
    private let cachePrefix = "focal_chat_"
    private let conversationsKey: String
    private let usersKey: String
    private let cacheVersion = "1.0"
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private let maxMessagesPerConversation = 500
    
    private let userDefaults = UserDefaults.standard
    
    static let shared = ChatCacheService()
    
    private init() {
        self.conversationsKey = "\(cachePrefix)conversations"
        self.usersKey = "\(cachePrefix)users"
    }
    
    // MARK: - Conversations Cache
    
    func setCachedConversations(_ conversations: [Conversation]) {
        let cacheData = ConversationCacheData(
            version: cacheVersion,
            timestamp: Date(),
            data: conversations
        )
        
        if let encoded = try? JSONEncoder().encode(cacheData) {
            userDefaults.set(encoded, forKey: conversationsKey)
        }
    }
    
    func getCachedConversations() -> [Conversation]? {
        guard let data = userDefaults.data(forKey: conversationsKey),
              let cacheData = try? JSONDecoder().decode(ConversationCacheData.self, from: data) else {
            return nil
        }
        
        // Check cache validity
        if cacheData.version != cacheVersion || 
           Date().timeIntervalSince(cacheData.timestamp) > maxCacheAge {
            clearConversationsCache()
            return nil
        }
        
        return cacheData.data
    }
    
    func clearConversationsCache() {
        userDefaults.removeObject(forKey: conversationsKey)
    }
    
    // MARK: - Messages Cache
    
    func setCachedMessages(conversationId: String, messages: [ChatMessage]) {
        // Limit cache size
        let limitedMessages = Array(messages.suffix(maxMessagesPerConversation))
        
        let latestTimestamp = limitedMessages.last?.timestamp
        
        let cacheData = MessageCacheData(
            version: cacheVersion,
            timestamp: Date(),
            conversationId: conversationId,
            data: limitedMessages,
            latestMessageTimestamp: latestTimestamp
        )
        
        let key = getMessagesKey(conversationId: conversationId)
        if let encoded = try? JSONEncoder().encode(cacheData) {
            userDefaults.set(encoded, forKey: key)
        }
    }
    
    func getCachedMessages(conversationId: String) -> [ChatMessage]? {
        let key = getMessagesKey(conversationId: conversationId)
        guard let data = userDefaults.data(forKey: key),
              let cacheData = try? JSONDecoder().decode(MessageCacheData.self, from: data) else {
            return nil
        }
        
        // Check cache validity
        if cacheData.version != cacheVersion || 
           Date().timeIntervalSince(cacheData.timestamp) > maxCacheAge {
            clearMessagesCache(conversationId: conversationId)
            return nil
        }
        
        return cacheData.data
    }
    
    func appendNewMessages(conversationId: String, newMessages: [ChatMessage]) -> [ChatMessage] {
        var existingMessages = getCachedMessages(conversationId: conversationId) ?? []
        
        // Filter out duplicates
        let existingIds = Set(existingMessages.map { $0.id })
        let uniqueNewMessages = newMessages.filter { !existingIds.contains($0.id) }
        
        // Append new messages
        existingMessages.append(contentsOf: uniqueNewMessages)
        
        // Sort by timestamp
        existingMessages.sort { $0.timestamp.dateValue() < $1.timestamp.dateValue() }
        
        // Limit to max messages
        if existingMessages.count > maxMessagesPerConversation {
            existingMessages = Array(existingMessages.suffix(maxMessagesPerConversation))
        }
        
        // Save updated cache
        setCachedMessages(conversationId: conversationId, messages: existingMessages)
        
        return existingMessages
    }
    
    func getLatestCachedMessageTimestamp(conversationId: String) -> Timestamp? {
        let key = getMessagesKey(conversationId: conversationId)
        guard let data = userDefaults.data(forKey: key),
              let cacheData = try? JSONDecoder().decode(MessageCacheData.self, from: data) else {
            return nil
        }
        
        // Check cache validity
        if cacheData.version != cacheVersion || 
           Date().timeIntervalSince(cacheData.timestamp) > maxCacheAge {
            return nil
        }
        
        return cacheData.latestMessageTimestamp
    }
    
    func clearMessagesCache(conversationId: String) {
        let key = getMessagesKey(conversationId: conversationId)
        userDefaults.removeObject(forKey: key)
    }
    
    func clearAllMessagesCache() {
        // Get all keys that start with message prefix
        let messagePrefix = "\(cachePrefix)messages_"
        let allKeys = userDefaults.dictionaryRepresentation().keys
        
        for key in allKeys where key.hasPrefix(messagePrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }
    
    // MARK: - Users Cache
    
    func setCachedUsers(_ users: [ChatUser]) {
        let cacheData = [
            "version": cacheVersion,
            "timestamp": Date().timeIntervalSince1970,
            "users": users.compactMap { user -> [String: Any]? in
                guard let data = try? JSONEncoder().encode(user),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                return dict
            }
        ] as [String: Any]
        
        userDefaults.set(cacheData, forKey: usersKey)
    }
    
    func getCachedUsers() -> [ChatUser]? {
        guard let cacheData = userDefaults.dictionary(forKey: usersKey),
              let version = cacheData["version"] as? String,
              let timestamp = cacheData["timestamp"] as? TimeInterval,
              let usersData = cacheData["users"] as? [[String: Any]] else {
            return nil
        }
        
        // Check cache validity
        if version != cacheVersion || 
           Date().timeIntervalSince1970 - timestamp > maxCacheAge {
            clearUsersCache()
            return nil
        }
        
        return usersData.compactMap { dict -> ChatUser? in
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let user = try? JSONDecoder().decode(ChatUser.self, from: data) else {
                return nil
            }
            return user
        }
    }
    
    func clearUsersCache() {
        userDefaults.removeObject(forKey: usersKey)
    }
    
    // MARK: - Cache Management
    
    func clearAllCache() {
        clearConversationsCache()
        clearAllMessagesCache()
        clearUsersCache()
        
        // Clear any other chat-related cache
        let allKeys = userDefaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(cachePrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }
    
    func getCacheSize() -> Int {
        var totalSize = 0
        let allKeys = userDefaults.dictionaryRepresentation().keys
        
        for key in allKeys where key.hasPrefix(cachePrefix) {
            if let data = userDefaults.data(forKey: key) {
                totalSize += data.count
            }
        }
        
        return totalSize
    }
    
    func pruneOldCache() {
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let messagePrefix = "\(cachePrefix)messages_"
        
        for key in allKeys where key.hasPrefix(messagePrefix) {
            if let data = userDefaults.data(forKey: key),
               let cacheData = try? JSONDecoder().decode(MessageCacheData.self, from: data) {
                // Remove cache older than max age
                if Date().timeIntervalSince(cacheData.timestamp) > maxCacheAge {
                    userDefaults.removeObject(forKey: key)
                }
            }
        }
        
        // Also prune conversations and users cache if old
        if let conversationData = userDefaults.data(forKey: conversationsKey),
           let cacheData = try? JSONDecoder().decode(ConversationCacheData.self, from: conversationData),
           Date().timeIntervalSince(cacheData.timestamp) > maxCacheAge {
            clearConversationsCache()
        }
        
        if let usersData = userDefaults.dictionary(forKey: usersKey),
           let timestamp = usersData["timestamp"] as? TimeInterval,
           Date().timeIntervalSince1970 - timestamp > maxCacheAge {
            clearUsersCache()
        }
    }
    
    // MARK: - Helper Methods
    
    private func getMessagesKey(conversationId: String) -> String {
        return "\(cachePrefix)messages_\(conversationId)"
    }
}

// MARK: - Cache Statistics
extension ChatCacheService {
    struct CacheStats {
        let conversationsCached: Int
        let messagesCached: Int
        let usersCached: Int
        let totalSizeBytes: Int
        let oldestCacheDate: Date?
        
        var formattedSize: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            return formatter.string(fromByteCount: Int64(totalSizeBytes))
        }
    }
    
    func getCacheStatistics() -> CacheStats {
        let conversations = getCachedConversations()?.count ?? 0
        let users = getCachedUsers()?.count ?? 0
        
        var messagesCount = 0
        var oldestDate: Date?
        
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let messagePrefix = "\(cachePrefix)messages_"
        
        for key in allKeys where key.hasPrefix(messagePrefix) {
            if let data = userDefaults.data(forKey: key),
               let cacheData = try? JSONDecoder().decode(MessageCacheData.self, from: data) {
                messagesCount += cacheData.data.count
                
                if oldestDate == nil || cacheData.timestamp < oldestDate! {
                    oldestDate = cacheData.timestamp
                }
            }
        }
        
        return CacheStats(
            conversationsCached: conversations,
            messagesCached: messagesCount,
            usersCached: users,
            totalSizeBytes: getCacheSize(),
            oldestCacheDate: oldestDate
        )
    }
}