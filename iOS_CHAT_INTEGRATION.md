# iOS Chat Integration Guide for Focal Point

This document provides comprehensive guidance for implementing the chat feature in the Focal Point iOS app, based on the existing web implementation.

## Table of Contents
1. [Overview](#overview)
2. [Firebase Data Structure](#firebase-data-structure)
3. [Authentication & Security](#authentication--security)
4. [Core Architecture](#core-architecture)
5. [iOS Implementation Guide](#ios-implementation-guide)
6. [Caching Strategy](#caching-strategy)
7. [Real-Time Updates](#real-time-updates)
8. [UI/UX Guidelines](#uiux-guidelines)
9. [Push Notifications](#push-notifications)
10. [Performance Optimization](#performance-optimization)
11. [Error Handling](#error-handling)
12. [Testing Strategy](#testing-strategy)

## Overview

The Focal Point chat system is a real-time messaging feature built on Firebase Firestore with the following key characteristics:

- **Multi-tenant Architecture**: Messages are scoped to organizations
- **Real-time Synchronization**: Uses Firestore listeners for instant updates
- **Cache-First Loading**: Implements aggressive caching to minimize Firebase reads
- **Optimized Performance**: Uses incremental loading to reduce costs
- **Direct & Group Chats**: Supports both one-on-one and group conversations

### Key Statistics
- Cache hit rate target: >80% for returning users
- Maximum messages cached per conversation: 500
- Cache expiration: 7 days
- Initial load time target: <2 seconds with cache

## Firebase Data Structure

### Collections Overview

```
firestore/
├── conversations/
│   └── {conversationId}/
│       ├── participants: string[]
│       ├── type: 'direct' | 'group'
│       ├── name: string | null
│       ├── defaultName: string
│       ├── createdAt: Timestamp
│       ├── lastActivity: Timestamp
│       ├── lastMessage: {
│       │   ├── text: string
│       │   ├── senderId: string
│       │   └── timestamp: Timestamp
│       │   }
│       └── unreadCounts: {
│           └── [userId]: number
│           }
├── messages/
│   └── {conversationId}/
│       └── messages/
│           └── {messageId}/
│               ├── senderId: string
│               ├── senderName: string
│               ├── text: string
│               ├── type: 'text' | 'file'
│               ├── fileUrl: string | null
│               ├── timestamp: Timestamp
│               └── createdAt: Timestamp
├── users/
│   └── {userId}/
│       ├── organizationID: string
│       ├── firstName: string
│       ├── lastName: string
│       └── email: string
└── userPresence/
    └── {userId}/
        ├── isOnline: boolean
        ├── lastSeen: Timestamp
        └── conversationId: string | null
```

### Data Models (Swift)

```swift
// MARK: - Conversation Model
struct Conversation: Codable {
    let id: String
    let participants: [String]
    let type: ConversationType
    let name: String?
    let defaultName: String
    let createdAt: Timestamp
    let lastActivity: Timestamp
    let lastMessage: LastMessage?
    let unreadCounts: [String: Int]
    
    enum ConversationType: String, Codable {
        case direct = "direct"
        case group = "group"
    }
}

struct LastMessage: Codable {
    let text: String
    let senderId: String
    let timestamp: Timestamp
}

// MARK: - Message Model
struct Message: Codable {
    let id: String
    let senderId: String
    let senderName: String
    let text: String
    let type: MessageType
    let fileUrl: String?
    let timestamp: Timestamp
    let createdAt: Timestamp
    
    enum MessageType: String, Codable {
        case text = "text"
        case file = "file"
    }
}

// MARK: - User Model
struct User: Codable {
    let id: String
    let organizationID: String
    let firstName: String
    let lastName: String
    let email: String
    let displayName: String?
}
```

## Authentication & Security

### Requirements
1. User must be authenticated via Firebase Auth
2. User must have a valid `organizationID` in their profile
3. Users can only access conversations where they are participants
4. Users can only see other users within their organization

### Firebase Security Rules
```javascript
// Conversations
match /conversations/{conversationId} {
  allow read: if request.auth != null && 
    request.auth.uid in resource.data.participants;
  allow create: if request.auth != null;
  allow update: if request.auth != null && 
    request.auth.uid in resource.data.participants;
}

// Messages
match /messages/{conversationId}/messages/{messageId} {
  allow read: if request.auth != null && 
    exists(/databases/$(database)/documents/conversations/$(conversationId)) &&
    request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participants;
  allow create: if request.auth != null &&
    request.auth.uid == request.resource.data.senderId;
}
```

## Core Architecture

### Service Layer Pattern

The web app uses a service layer pattern that should be replicated in iOS:

```swift
// MARK: - ChatService Protocol
protocol ChatServiceProtocol {
    // Conversation Management
    func createConversation(participants: [String], type: Conversation.ConversationType, customName: String?) async throws -> String
    func getUserConversations(userId: String) async throws -> [Conversation]
    func updateConversationName(conversationId: String, newName: String) async throws
    
    // Messaging
    func sendMessage(conversationId: String, senderId: String, text: String, type: Message.MessageType, fileUrl: String?, senderName: String) async throws -> String
    func getConversationMessages(conversationId: String, limit: Int, lastDocument: DocumentSnapshot?) async throws -> (messages: [Message], lastDoc: DocumentSnapshot?, hasMore: Bool)
    func markMessagesAsRead(conversationId: String, userId: String) async throws
    
    // Real-time Listeners
    func subscribeToUserConversations(userId: String, completion: @escaping ([Conversation]) -> Void) -> ListenerRegistration
    func subscribeToConversationMessages(conversationId: String, completion: @escaping ([Message]) -> Void) -> ListenerRegistration
    func subscribeToNewMessages(conversationId: String, afterTimestamp: Timestamp?, completion: @escaping ([Message], Bool) -> Void) -> ListenerRegistration
    
    // User Management
    func getOrganizationUsers(organizationId: String) async throws -> [User]
    func updateUserPresence(userId: String, isOnline: Bool, conversationId: String?) async throws
}
```

### Context/State Management

In iOS, use a combination of:
1. **ObservableObject** for reactive state management
2. **Combine** for data flow
3. **@EnvironmentObject** for dependency injection

```swift
// MARK: - ChatManager (Similar to ChatContext)
@MainActor
class ChatManager: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var organizationUsers: [User] = []
    @Published var isLoading = true
    @Published var isSendingMessage = false
    @Published var messagesLoading = false
    @Published var hasMoreMessages = false
    
    private let chatService: ChatServiceProtocol
    private let cacheService: ChatCacheServiceProtocol
    private let readCounter: ReadCounterProtocol
    private let authManager: AuthManager
    
    private var conversationsListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    private var lastMessageDoc: DocumentSnapshot?
    
    init(chatService: ChatServiceProtocol, 
         cacheService: ChatCacheServiceProtocol,
         readCounter: ReadCounterProtocol,
         authManager: AuthManager) {
        self.chatService = chatService
        self.cacheService = cacheService
        self.readCounter = readCounter
        self.authManager = authManager
    }
}
```

## iOS Implementation Guide

### 1. Firebase Setup

```swift
// AppDelegate or App struct
import Firebase
import FirebaseFirestore

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        
        // Enable offline persistence
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        Firestore.firestore().settings = settings
        
        return true
    }
}
```

### 2. Cache-First Loading Implementation

```swift
// MARK: - Load Conversations with Cache
func loadConversations() async {
    guard let userId = authManager.currentUser?.id else { return }
    
    // 1. Load from cache first
    if let cachedConversations = cacheService.getCachedConversations() {
        self.conversations = cachedConversations
        self.isLoading = false
        readCounter.recordCacheHit(collection: "conversations", component: "ChatManager", savedReads: cachedConversations.count)
    } else {
        readCounter.recordCacheMiss(collection: "conversations", component: "ChatManager")
    }
    
    // 2. Set up real-time listener
    conversationsListener = chatService.subscribeToUserConversations(userId: userId) { [weak self] updatedConversations in
        self?.conversations = updatedConversations
        self?.isLoading = false
        
        // Cache the updated data
        self?.cacheService.setCachedConversations(updatedConversations)
    }
}

// MARK: - Load Messages with Cache
func loadMessages(for conversation: Conversation) async {
    self.activeConversation = conversation
    
    // 1. Load from cache first
    let cachedMessages = cacheService.getCachedMessages(conversationId: conversation.id)
    let latestTimestamp = cacheService.getLatestCachedMessageTimestamp(conversationId: conversation.id)
    
    if let cachedMessages = cachedMessages, !cachedMessages.isEmpty {
        self.messages = cachedMessages
        self.messagesLoading = false
        readCounter.recordCacheHit(collection: "messages", component: "ChatManager", savedReads: cachedMessages.count)
    } else {
        readCounter.recordCacheMiss(collection: "messages", component: "ChatManager")
    }
    
    // 2. Set up optimized listener
    if let latestTimestamp = latestTimestamp {
        // Listen only for new messages
        messagesListener = chatService.subscribeToNewMessages(
            conversationId: conversation.id,
            afterTimestamp: latestTimestamp
        ) { [weak self] newMessages, isIncremental in
            guard let self = self else { return }
            
            if isIncremental {
                let updatedMessages = self.cacheService.appendNewMessages(
                    conversationId: conversation.id,
                    newMessages: newMessages
                )
                self.messages = updatedMessages
            } else {
                self.messages = newMessages
                self.cacheService.setCachedMessages(conversationId: conversation.id, messages: newMessages)
            }
            
            self.messagesLoading = false
            
            // Mark as read
            Task {
                try? await self.chatService.markMessagesAsRead(
                    conversationId: conversation.id,
                    userId: self.authManager.currentUser?.id ?? ""
                )
            }
        }
    } else {
        // No cache, use regular listener
        messagesListener = chatService.subscribeToConversationMessages(
            conversationId: conversation.id
        ) { [weak self] updatedMessages in
            self?.messages = updatedMessages
            self?.messagesLoading = false
            self?.cacheService.setCachedMessages(conversationId: conversation.id, messages: updatedMessages)
        }
    }
}
```

### 3. Sending Messages

```swift
func sendMessage(text: String, type: Message.MessageType = .text, fileUrl: String? = nil) async {
    guard let conversation = activeConversation,
          let currentUser = authManager.currentUser,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    
    isSendingMessage = true
    
    do {
        let senderName = currentUser.displayName ?? 
                        "\(currentUser.firstName) \(currentUser.lastName)".trimmingCharacters(in: .whitespaces) ?? 
                        currentUser.email
        
        _ = try await chatService.sendMessage(
            conversationId: conversation.id,
            senderId: currentUser.id,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            fileUrl: fileUrl,
            senderName: senderName
        )
        
        // Note: Real-time listener will update the cache when the message arrives
    } catch {
        // Handle error
        print("Failed to send message: \(error)")
    }
    
    isSendingMessage = false
}
```

## Caching Strategy

### Cache Service Implementation

```swift
// MARK: - ChatCacheService
class ChatCacheService: ChatCacheServiceProtocol {
    private let cachePrefix = "focal_chat_"
    private let conversationsKey: String
    private let cacheVersion = "1.0"
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private let maxMessagesPerConversation = 500
    
    init() {
        self.conversationsKey = "\(cachePrefix)conversations"
    }
    
    // MARK: - Conversations Cache
    func setCachedConversations(_ conversations: [Conversation]) {
        let cacheData = CacheData(
            version: cacheVersion,
            timestamp: Date(),
            data: conversations
        )
        
        if let encoded = try? JSONEncoder().encode(cacheData) {
            UserDefaults.standard.set(encoded, forKey: conversationsKey)
        }
    }
    
    func getCachedConversations() -> [Conversation]? {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let cacheData = try? JSONDecoder().decode(CacheData<[Conversation]>.self, from: data) else {
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
    
    // MARK: - Messages Cache
    func setCachedMessages(conversationId: String, messages: [Message]) {
        // Limit cache size
        let limitedMessages = Array(messages.suffix(maxMessagesPerConversation))
        
        let cacheData = MessageCacheData(
            version: cacheVersion,
            timestamp: Date(),
            conversationId: conversationId,
            data: limitedMessages
        )
        
        let key = getMessagesKey(conversationId: conversationId)
        if let encoded = try? JSONEncoder().encode(cacheData) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    func getCachedMessages(conversationId: String) -> [Message]? {
        let key = getMessagesKey(conversationId: conversationId)
        guard let data = UserDefaults.standard.data(forKey: key),
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
}
```

### Cache Data Models

```swift
struct CacheData<T: Codable>: Codable {
    let version: String
    let timestamp: Date
    let data: T
}

struct MessageCacheData: Codable {
    let version: String
    let timestamp: Date
    let conversationId: String
    let data: [Message]
}
```

## Real-Time Updates

### Optimized Listener Pattern

```swift
// MARK: - Optimized New Messages Listener
func subscribeToNewMessages(
    conversationId: String,
    afterTimestamp: Timestamp?,
    completion: @escaping ([Message], Bool) -> Void
) -> ListenerRegistration {
    
    let messagesRef = Firestore.firestore()
        .collection("messages")
        .document(conversationId)
        .collection("messages")
    
    var query = messagesRef.order(by: "timestamp", descending: true)
    
    // Only get messages newer than cached ones
    if let afterTimestamp = afterTimestamp {
        query = query.whereField("timestamp", isGreaterThan: afterTimestamp)
    } else {
        query = query.limit(to: 20)
    }
    
    return query.addSnapshotListener { snapshot, error in
        guard let documents = snapshot?.documents else {
            print("Error fetching messages: \(error?.localizedDescription ?? "Unknown error")")
            return
        }
        
        let messages = documents.compactMap { doc -> Message? in
            try? doc.data(as: Message.self)
        }.reversed() // Reverse to show chronologically
        
        // Only call completion if there are new messages
        if !messages.isEmpty {
            completion(messages, afterTimestamp != nil)
        }
    }
}
```

### Handling Real-Time Updates

```swift
// MARK: - Message Update Handler
private func handleMessageUpdates() {
    // Debounce rapid updates
    messageUpdateDebouncer.debounce(delay: 0.1) { [weak self] in
        self?.refreshMessageDisplay()
    }
}

// MARK: - Connection State Management
func handleNetworkStateChange(isConnected: Bool) {
    if isConnected {
        // Resume listeners
        Task {
            await loadConversations()
            if let activeConversation = activeConversation {
                await loadMessages(for: activeConversation)
            }
        }
    } else {
        // App continues to work with cached data
        // Firestore offline persistence handles queuing
    }
}
```

## UI/UX Guidelines

### iOS-Specific Considerations

1. **Navigation Structure**
   - Use `NavigationSplitView` for iPad
   - Use `NavigationStack` for iPhone
   - Implement proper state restoration

2. **Message Display**
   - Use `LazyVStack` for efficient scrolling
   - Implement proper keyboard avoidance
   - Add haptic feedback for actions

3. **Real-Time Indicators**
   - Show typing indicators
   - Display online/offline status
   - Implement read receipts

### SwiftUI Implementation Example

```swift
// MARK: - Message View
struct MessageView: View {
    let message: Message
    let isOwnMessage: Bool
    let showSenderName: Bool
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwnMessage { Spacer(minLength: 60) }
            
            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                if showSenderName && !isOwnMessage {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                MessageBubble(message: message, isOwnMessage: isOwnMessage)
                
                Text(message.timestamp.dateValue().formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !isOwnMessage { Spacer(minLength: 60) }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: Message
    let isOwnMessage: Bool
    
    var body: some View {
        Group {
            switch message.type {
            case .text:
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            case .file:
                FileMessageView(message: message)
            }
        }
        .background(isOwnMessage ? Color.blue : Color(.systemGray5))
        .foregroundColor(isOwnMessage ? .white : .primary)
        .cornerRadius(16)
    }
}
```

## Push Notifications

### Setup Requirements

1. **Firebase Cloud Messaging (FCM)**
   ```swift
   import FirebaseMessaging
   
   // In AppDelegate
   func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
       FirebaseApp.configure()
       
       // Configure push notifications
       UNUserNotificationCenter.current().delegate = self
       Messaging.messaging().delegate = self
       
       application.registerForRemoteNotifications()
       
       return true
   }
   ```

2. **Notification Payload Structure**
   ```json
   {
     "notification": {
       "title": "New message from {senderName}",
       "body": "{messageText}",
       "sound": "default"
     },
     "data": {
       "conversationId": "{conversationId}",
       "senderId": "{senderId}",
       "messageId": "{messageId}",
       "type": "chat_message"
     },
     "apns": {
       "payload": {
         "aps": {
           "category": "CHAT_MESSAGE",
           "thread-id": "{conversationId}",
           "mutable-content": 1
         }
       }
     }
   }
   ```

3. **Background Message Handling**
   ```swift
   func userNotificationCenter(
       _ center: UNUserNotificationCenter,
       didReceive response: UNNotificationResponse,
       withCompletionHandler completionHandler: @escaping () -> Void
   ) {
       let userInfo = response.notification.request.content.userInfo
       
       if let conversationId = userInfo["conversationId"] as? String {
           // Navigate to conversation
           navigateToConversation(id: conversationId)
       }
       
       completionHandler()
   }
   ```

## Performance Optimization

### 1. Read Counter Integration

```swift
// MARK: - ReadCounter Service
class ReadCounter: ReadCounterProtocol {
    private let userDefaults = UserDefaults.standard
    private let sessionKey = "focal_read_session_\(UUID().uuidString)"
    
    func recordRead(operation: String, collection: String, component: String, count: Int) {
        let read = ReadOperation(
            timestamp: Date(),
            operation: operation,
            collection: collection,
            component: component,
            count: count,
            cacheHit: false
        )
        
        // Store for analytics
        storeReadOperation(read)
        
        // Update daily counter
        updateDailyCounter(count: count)
    }
    
    func recordCacheHit(collection: String, component: String, savedReads: Int) {
        let read = ReadOperation(
            timestamp: Date(),
            operation: "cache_hit",
            collection: collection,
            component: component,
            count: 0,
            cacheHit: true,
            savedReads: savedReads
        )
        
        storeReadOperation(read)
    }
    
    func getSessionStats() -> ReadStats {
        // Calculate and return session statistics
        return calculateStats()
    }
}
```

### 2. Memory Management

```swift
// MARK: - Memory-Efficient Message Loading
class MessageLoader {
    private let batchSize = 20
    private var loadedMessages: [Message] = []
    private var visibleRange: Range<Int> = 0..<0
    
    func loadVisibleMessages(in scrollView: UIScrollView) {
        let visibleRect = CGRect(
            origin: scrollView.contentOffset,
            size: scrollView.bounds.size
        )
        
        // Calculate which messages should be in memory
        let newVisibleRange = calculateVisibleRange(for: visibleRect)
        
        // Unload messages outside visible range + buffer
        unloadMessagesOutsideRange(newVisibleRange.extended(by: 10))
        
        // Load messages in visible range
        loadMessagesInRange(newVisibleRange)
    }
}
```

### 3. Image Caching

```swift
// MARK: - Profile Image Cache
class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    
    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        
        // Check memory cache
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        // Check disk cache
        if let diskCached = loadFromDisk(key: key) {
            cache.setObject(diskCached, forKey: key)
            return diskCached
        }
        
        // Download and cache
        if let downloaded = await downloadImage(from: url) {
            cache.setObject(downloaded, forKey: key)
            saveToDisk(image: downloaded, key: key)
            return downloaded
        }
        
        return nil
    }
}
```

## Error Handling

### Network Error Recovery

```swift
enum ChatError: LocalizedError {
    case networkUnavailable
    case authenticationRequired
    case insufficientPermissions
    case messageFailedToSend
    case conversationNotFound
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "No internet connection. Messages will be sent when you're back online."
        case .authenticationRequired:
            return "Please sign in to continue."
        case .insufficientPermissions:
            return "You don't have permission to access this conversation."
        case .messageFailedToSend:
            return "Message failed to send. Please try again."
        case .conversationNotFound:
            return "This conversation no longer exists."
        }
    }
}

// MARK: - Error Handler
class ChatErrorHandler {
    func handle(_ error: Error, in viewController: UIViewController) {
        if let chatError = error as? ChatError {
            switch chatError {
            case .networkUnavailable:
                // Show offline banner
                showOfflineBanner()
            case .authenticationRequired:
                // Navigate to login
                navigateToLogin()
            default:
                // Show error alert
                showErrorAlert(message: chatError.localizedDescription)
            }
        } else {
            // Generic error handling
            showErrorAlert(message: "An unexpected error occurred.")
        }
    }
}
```

## Testing Strategy

### Unit Tests

```swift
// MARK: - Chat Service Tests
class ChatServiceTests: XCTestCase {
    var sut: ChatService!
    var mockFirestore: MockFirestore!
    
    override func setUp() {
        super.setUp()
        mockFirestore = MockFirestore()
        sut = ChatService(firestore: mockFirestore)
    }
    
    func testSendMessage_Success() async throws {
        // Given
        let conversationId = "test_conversation"
        let senderId = "test_user"
        let text = "Hello, World!"
        
        // When
        let messageId = try await sut.sendMessage(
            conversationId: conversationId,
            senderId: senderId,
            text: text,
            type: .text,
            fileUrl: nil,
            senderName: "Test User"
        )
        
        // Then
        XCTAssertNotNil(messageId)
        XCTAssertEqual(mockFirestore.writtenDocuments.count, 1)
    }
    
    func testCacheHitRate() async {
        // Test that cache hit rate exceeds 80% threshold
        let cacheService = ChatCacheService()
        
        // Simulate user session
        await simulateUserSession()
        
        let stats = readCounter.getSessionStats()
        let hitRate = Double(stats.cacheHits) / Double(stats.totalReads) * 100
        
        XCTAssertGreaterThan(hitRate, 80.0)
    }
}
```

### Integration Tests

```swift
// MARK: - Chat Flow Integration Tests
class ChatIntegrationTests: XCTestCase {
    func testCompleteMessageFlow() async throws {
        // 1. Create conversation
        let conversationId = try await createTestConversation()
        
        // 2. Send message
        let messageId = try await sendTestMessage(to: conversationId)
        
        // 3. Verify message received
        let messages = try await loadMessages(for: conversationId)
        XCTAssertTrue(messages.contains { $0.id == messageId })
        
        // 4. Verify cache updated
        let cachedMessages = cacheService.getCachedMessages(conversationId: conversationId)
        XCTAssertNotNil(cachedMessages)
        XCTAssertTrue(cachedMessages!.contains { $0.id == messageId })
    }
}
```

## Implementation Checklist

### Phase 1: Core Infrastructure
- [ ] Set up Firebase SDK and configuration
- [ ] Implement authentication flow
- [ ] Create data models
- [ ] Set up cache service with UserDefaults/CoreData
- [ ] Implement read counter service

### Phase 2: Chat Service
- [ ] Implement ChatService protocol
- [ ] Add conversation management methods
- [ ] Add message sending/receiving
- [ ] Set up real-time listeners
- [ ] Implement cache-first loading

### Phase 3: UI Implementation
- [ ] Create conversation list view
- [ ] Create message thread view
- [ ] Implement message input
- [ ] Add employee selector
- [ ] Implement pull-to-refresh

### Phase 4: Optimization
- [ ] Add message pagination
- [ ] Implement image caching
- [ ] Add typing indicators
- [ ] Optimize real-time listeners
- [ ] Add network state handling

### Phase 5: Polish
- [ ] Add push notifications
- [ ] Implement deep linking
- [ ] Add message search
- [ ] Add file sharing
- [ ] Implement message reactions (if needed)

## Important Notes

1. **Cost Optimization**: The web app experienced a 58 million read incident. Always implement cache-first loading and use the ReadCounter to monitor usage.

2. **Real-Time Optimization**: Use the `subscribeToNewMessages` pattern with timestamp filtering to avoid re-reading cached messages.

3. **Cache Management**: Implement proper cache expiration and size limits to prevent storage issues.

4. **Error Handling**: Always provide offline functionality using cached data.

5. **Security**: Never expose organization data to users outside their organization.

## Support Resources

- Firebase iOS SDK Documentation: https://firebase.google.com/docs/ios/setup
- Firestore Best Practices: https://firebase.google.com/docs/firestore/best-practices
- Web Implementation Reference: `/src/contexts/ChatContext.js` and `/src/services/chatService.js`
- Cache Implementation Reference: `/src/services/chatCacheService.js`

For questions about the web implementation, refer to the source files or contact the web development team.