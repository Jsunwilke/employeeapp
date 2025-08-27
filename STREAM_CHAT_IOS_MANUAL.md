# Stream Chat iOS Integration Manual
## For Focal Point iOS Application

---

## Table of Contents
1. [Overview](#overview)
2. [Architecture & Flow](#architecture--flow)
3. [Configuration](#configuration)
4. [Authentication](#authentication)
5. [Channel Management](#channel-management)
6. [iOS Implementation Guide](#ios-implementation-guide)
7. [Code Examples](#code-examples)
8. [Testing & Debugging](#testing--debugging)

---

## Overview

The Focal Point web application has migrated from a custom Firebase-based chat to Stream Chat, a scalable chat infrastructure service. This manual provides comprehensive guidance for implementing Stream Chat in the iOS application to maintain feature parity with the web version.

### Key Benefits of Stream Chat
- Real-time messaging with WebSocket connections
- Built-in typing indicators, read receipts, and presence
- Rich media support (images, files, GIFs)
- Offline support with message synchronization
- Push notifications out of the box
- Thread/reply support
- Message reactions and custom attachments

### Current Web Implementation Stack
- **Stream Chat React SDK**: v10.x
- **Firebase Authentication**: For user management
- **Firebase Functions**: For secure token generation
- **LocalStorage**: For message caching
- **Organization-based**: Multi-tenant chat isolation

---

## Architecture & Flow

### System Architecture
```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   iOS App   │────▶│   Firebase   │────▶│ Stream Chat │
│             │     │     Auth     │     │   Server    │
└─────────────┘     └──────────────┘     └─────────────┘
       │                   │                      ▲
       │                   ▼                      │
       │            ┌──────────────┐             │
       └───────────▶│   Firebase   │─────────────┘
                    │   Function   │
                    │(Token Gen)   │
                    └──────────────┘
```

### Data Flow
1. User authenticates with Firebase
2. App requests Stream Chat token from Firebase Function
3. Firebase Function validates user and generates secure token
4. App connects to Stream Chat with token
5. User profile syncs between Firebase and Stream
6. Messages flow directly through Stream Chat

---

## Configuration

### Stream Chat Credentials (Production)
```
API Key: fgxkbmk4kp9f
API Secret: [NEVER USE IN CLIENT - Server Only]
```

### Firebase Function Endpoint
```
Function Name: generateStreamChatToken
Region: us-central1
URL: https://us-central1-focal-point-c452c.cloudfunctions.net/generateStreamChatToken
```

### Environment Setup for iOS

#### 1. Add Stream Chat iOS SDK

**Swift Package Manager (Recommended):**
```swift
dependencies: [
    .package(url: "https://github.com/GetStream/stream-chat-swift.git", from: "4.50.0")
]
```

**CocoaPods:**
```ruby
pod 'StreamChat', '~> 4.50.0'
pod 'StreamChatUI', '~> 4.50.0'  # Optional UI components
```

#### 2. Configure Info.plist
```xml
<!-- For photo/file uploads -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Upload photos to chat</string>
<key>NSCameraUsageDescription</key>
<string>Take photos for chat</string>

<!-- For push notifications -->
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

---

## Authentication

### Authentication Flow

#### Step 1: Firebase Authentication
The user must be authenticated with Firebase first. This is your existing authentication.

#### Step 2: Get Stream Chat Token
```swift
// Swift implementation
func getStreamChatToken(for userId: String) async throws -> String {
    // Get Firebase ID token
    guard let idToken = try await Auth.auth().currentUser?.getIDToken() else {
        throw AuthError.notAuthenticated
    }
    
    // Call Firebase Function
    let functions = Functions.functions()
    let generateToken = functions.httpsCallable("generateStreamChatToken")
    
    let result = try await generateToken.call(["userId": userId])
    
    guard let data = result.data as? [String: Any],
          let success = data["success"] as? Bool,
          success == true,
          let token = data["token"] as? String else {
        throw AuthError.tokenGenerationFailed
    }
    
    return token
}
```

#### Step 3: Connect to Stream Chat
```swift
import StreamChat

class StreamChatManager {
    static let shared = StreamChatManager()
    private var chatClient: ChatClient?
    
    func connectUser(userId: String, 
                     userInfo: UserInfo,
                     token: String) async throws {
        // Initialize Stream Chat client
        let config = ChatClientConfig(apiKey: .init("fgxkbmk4kp9f"))
        chatClient = ChatClient(config: config)
        
        // Prepare user object
        let streamUser = UserInfo(
            id: userId,
            name: userInfo.displayName ?? userInfo.email ?? "User",
            imageURL: userInfo.photoURL,
            extraData: [
                "email": .string(userInfo.email ?? ""),
                "role": .string(userInfo.role ?? "user"),
                "organizationID": .string(userInfo.organizationID)
            ]
        )
        
        // Connect with token
        try await chatClient?.connectUser(
            userInfo: streamUser,
            token: Token(stringLiteral: token)
        )
    }
}
```

### User Profile Structure
```swift
struct StreamUserProfile {
    let id: String           // Firebase UID
    let name: String         // Display name
    let email: String        // User email
    let imageURL: URL?       // Profile photo URL
    let role: String         // "admin", "photographer", etc.
    let organizationID: String  // Organization identifier
}
```

---

## Channel Management

### Channel Types

#### 1. Direct Messages (1-on-1)
- **Type**: `messaging`
- **ID Format**: `dm-{sortedUserIds}` (e.g., `dm-user1-user2`)
- **Creation**: Auto-created when first message sent

```swift
func getOrCreateDirectMessageChannel(with otherUserId: String) async throws -> Channel {
    let members = [currentUserId, otherUserId].sorted()
    let channelId = "dm-\(members.joined(separator: "-"))"
    
    let channelController = chatClient?.channelController(
        createDirectMessageChannelWith: [otherUserId],
        type: .messaging,
        id: channelId,
        extraData: [:]
    )
    
    try await channelController?.synchronize()
    return channelController!.channel!
}
```

#### 2. Group/Team Channels
- **Type**: `team`
- **ID Format**: Custom or auto-generated
- **Features**: Multiple members, admin roles, channel settings

```swift
func createGroupChannel(name: String, 
                        memberIds: [String],
                        isPrivate: Bool = false) async throws -> Channel {
    let channelController = try chatClient?.channelController(
        createChannelWith: memberIds,
        type: .team,
        id: ChannelId(type: .team, id: UUID().uuidString),
        name: name,
        imageURL: nil,
        extraData: [
            "isPrivate": .bool(isPrivate),
            "organizationID": .string(currentOrganizationId)
        ]
    )
    
    try await channelController?.synchronize()
    return channelController!.channel!
}
```

### Channel Filtering

Only show channels for the user's organization:

```swift
func loadOrganizationChannels() async throws -> [Channel] {
    let query = ChannelListQuery(
        filter: .and([
            .containMembers(userIds: [currentUserId]),
            .equal(.type, to: .messaging),
            .or([
                .equal(.type, to: .messaging),
                .equal(.type, to: .team)
            ])
        ]),
        sort: [.init(key: .lastMessageAt, isAscending: false)],
        pageSize: 30
    )
    
    let controller = chatClient?.channelListController(query: query)
    try await controller?.synchronize()
    return controller?.channels ?? []
}
```

---

## iOS Implementation Guide

### 1. Project Setup

#### AppDelegate Configuration
```swift
import StreamChat
import StreamChatUI

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Configure Stream Chat appearance
        Appearance.default.colorPalette.messageListBackground = .systemBackground
        Appearance.default.colorPalette.background = .systemBackground
        
        // Enable push notifications
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        application.registerForRemoteNotifications()
        
        return true
    }
}
```

### 2. Main Chat Interface

#### Using StreamUI Components (Recommended for Quick Implementation)
```swift
import StreamChatUI

class ChatViewController: ChatChannelListVC {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Customize appearance
        navigationItem.title = "Messages"
        
        // Add create channel button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(createNewChannel)
        )
    }
    
    override func channelListController(
        _ controller: ChatChannelListController,
        didSelectChannel channel: ChatChannel
    ) {
        let channelVC = ChatChannelVC()
        channelVC.channelController = controller.client.channelController(for: channel.cid)
        navigationController?.pushViewController(channelVC, animated: true)
    }
}
```

#### Custom Implementation
```swift
import StreamChat

class CustomChatViewController: UIViewController {
    private var channelListController: ChatChannelListController?
    private var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        loadChannels()
    }
    
    private func loadChannels() {
        let query = ChannelListQuery(
            filter: .containMembers(userIds: [currentUserId]),
            sort: [.init(key: .lastMessageAt)]
        )
        
        channelListController = ChatClient.shared.channelListController(query: query)
        channelListController?.delegate = self
        channelListController?.synchronize()
    }
}

extension CustomChatViewController: ChatChannelListControllerDelegate {
    func controller(_ controller: ChatChannelListController, 
                   didChangeChannels changes: [ListChange<ChatChannel>]) {
        tableView.reloadData()
    }
}
```

### 3. Message Handling

#### Sending Messages
```swift
func sendMessage(text: String, to channel: Channel) async throws {
    let messageController = chatClient?.messageController(
        cid: channel.cid,
        messageId: UUID().uuidString
    )
    
    try await messageController?.createNewMessage(
        text: text,
        attachments: [],
        extraData: [:]
    )
}
```

#### Receiving Messages
```swift
class MessageListener: ChatChannelControllerDelegate {
    func channelController(_ controller: ChatChannelController, 
                          didUpdateMessages changes: [ListChange<ChatMessage>]) {
        for change in changes {
            switch change {
            case .insert(let message, index: _):
                handleNewMessage(message)
            case .update(let message, index: _):
                handleUpdatedMessage(message)
            case .remove(let message, index: _):
                handleDeletedMessage(message)
            case .move:
                break
            }
        }
    }
}
```

### 4. Push Notifications

#### Setup Push Notifications
```swift
extension AppDelegate {
    func application(_ application: UIApplication, 
                    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        chatClient?.currentUserController().addDevice(.apn(token: deviceToken))
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap
        if let messageId = response.notification.request.content.userInfo["message_id"] as? String,
           let channelId = response.notification.request.content.userInfo["channel_id"] as? String {
            // Navigate to specific message/channel
            openChannel(channelId: channelId, messageId: messageId)
        }
        completionHandler()
    }
}
```

### 5. Offline Support

Stream Chat iOS SDK includes built-in offline support:

```swift
// Configure offline mode
var config = ChatClientConfig(apiKey: .init("fgxkbmk4kp9f"))
config.isLocalStorageEnabled = true  // Enable offline storage
config.shouldConnectAutomatically = true  // Auto-reconnect

let chatClient = ChatClient(config: config)
```

### 6. Typing Indicators

```swift
// Start typing
channelController?.sendStartTypingEvent()

// Stop typing
channelController?.sendStopTypingEvent()

// Listen for typing events
func channelController(_ controller: ChatChannelController, 
                      didChangeTypingUsers users: Set<ChatUser>) {
    if !users.isEmpty {
        let names = users.map { $0.name ?? "Someone" }.joined(separator: ", ")
        typingLabel.text = "\(names) is typing..."
    } else {
        typingLabel.text = nil
    }
}
```

### 7. Message Reactions

```swift
// Add reaction
func addReaction(emoji: String, to message: ChatMessage) async throws {
    let messageController = chatClient?.messageController(
        cid: message.cid,
        messageId: message.id
    )
    
    try await messageController?.addReaction(emoji)
}

// Remove reaction  
func removeReaction(emoji: String, from message: ChatMessage) async throws {
    let messageController = chatClient?.messageController(
        cid: message.cid,
        messageId: message.id
    )
    
    try await messageController?.deleteReaction(emoji)
}
```

### 8. File/Image Uploads

```swift
func sendImageMessage(image: UIImage, to channel: Channel) async throws {
    guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
    
    let attachment = AnyAttachmentPayload(
        type: .image,
        payload: ImageAttachmentPayload(
            imageData: imageData,
            imageName: "image.jpg"
        )
    )
    
    let messageController = chatClient?.messageController(
        cid: channel.cid,
        messageId: UUID().uuidString
    )
    
    try await messageController?.createNewMessage(
        text: "",
        attachments: [attachment],
        extraData: [:]
    )
}
```

---

## Code Examples

### Complete Integration Example

```swift
// StreamChatService.swift
import StreamChat
import Firebase

class StreamChatService: ObservableObject {
    static let shared = StreamChatService()
    
    private var chatClient: ChatClient?
    @Published var isConnected = false
    @Published var unreadCount = 0
    
    private init() {}
    
    // MARK: - Connection Management
    
    func connect() async throws {
        guard let firebaseUser = Auth.auth().currentUser else {
            throw ChatError.notAuthenticated
        }
        
        // Get Stream token from Firebase Function
        let token = try await getStreamToken(for: firebaseUser.uid)
        
        // Initialize Stream Chat
        var config = ChatClientConfig(apiKey: .init("fgxkbmk4kp9f"))
        config.isLocalStorageEnabled = true
        config.shouldConnectAutomatically = true
        
        chatClient = ChatClient(config: config)
        
        // Connect user
        let userInfo = UserInfo(
            id: firebaseUser.uid,
            name: firebaseUser.displayName ?? "User",
            imageURL: firebaseUser.photoURL
        )
        
        try await chatClient?.connectUser(
            userInfo: userInfo,
            token: Token(stringLiteral: token)
        )
        
        isConnected = true
        setupUnreadCountListener()
    }
    
    func disconnect() {
        Task {
            await chatClient?.disconnect()
            isConnected = false
        }
    }
    
    // MARK: - Token Generation
    
    private func getStreamToken(for userId: String) async throws -> String {
        let functions = Functions.functions()
        let callable = functions.httpsCallable("generateStreamChatToken")
        
        let result = try await callable.call(["userId": userId])
        
        guard let data = result.data as? [String: Any],
              let token = data["token"] as? String else {
            throw ChatError.tokenGenerationFailed
        }
        
        return token
    }
    
    // MARK: - Unread Count
    
    private func setupUnreadCountListener() {
        chatClient?.currentUserController().delegate = self
    }
    
    // MARK: - Channel Operations
    
    func createDirectMessage(with userId: String) async throws -> ChatChannel {
        let members = [chatClient!.currentUserId!, userId].sorted()
        let channelId = ChannelId(type: .messaging, id: "dm-\(members.joined(separator: "-"))")
        
        let controller = try chatClient!.channelController(
            createDirectMessageChannelWith: [userId],
            type: .messaging,
            id: channelId.id
        )
        
        try await controller.synchronize()
        return controller.channel!
    }
    
    func loadChannels() -> ChatChannelListController {
        let query = ChannelListQuery(
            filter: .containMembers(userIds: [chatClient!.currentUserId!]),
            sort: [.init(key: .lastMessageAt, isAscending: false)]
        )
        
        return chatClient!.channelListController(query: query)
    }
}

// MARK: - CurrentUserControllerDelegate

extension StreamChatService: CurrentChatUserControllerDelegate {
    func currentUserController(_ controller: CurrentChatUserController, 
                               didChangeUnreadCount unreadCount: UnreadCount) {
        self.unreadCount = unreadCount.messages
    }
}

// MARK: - Error Types

enum ChatError: Error {
    case notAuthenticated
    case tokenGenerationFailed
    case connectionFailed
    case channelCreationFailed
}
```

### SwiftUI Implementation

```swift
// ChatView.swift
import SwiftUI
import StreamChatSwiftUI

struct ChatView: View {
    @StateObject private var chatService = StreamChatService.shared
    @State private var selectedChannel: ChatChannel?
    
    var body: some View {
        NavigationView {
            if chatService.isConnected {
                ChatChannelListView(
                    viewFactory: CustomViewFactory(),
                    selectedChannel: $selectedChannel
                )
                .navigationTitle("Messages")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: createNewChat) {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            } else {
                ProgressView("Connecting...")
                    .task {
                        try? await chatService.connect()
                    }
            }
        }
    }
    
    private func createNewChat() {
        // Show user picker or create group modal
    }
}

// Custom View Factory for UI customization
class CustomViewFactory: ViewFactory {
    @Injected(\.chatClient) var chatClient
    
    func makeChannelHeaderViewModifier(for channel: ChatChannel) -> some ChannelHeaderViewModifier {
        CustomChannelHeaderModifier()
    }
}
```

---

## Testing & Debugging

### Test Credentials

For development/testing, you can use these test users:
1. Create test users in Firebase Auth
2. Ensure they have proper organizationID set
3. Generate tokens via Firebase Function

### Debug Mode

Enable Stream Chat logging:
```swift
var config = ChatClientConfig(apiKey: .init("fgxkbmk4kp9f"))
config.logLevel = .debug
```

### Common Issues & Solutions

#### 1. Token Generation Fails
- **Cause**: Firebase Function not deployed or misconfigured
- **Solution**: Ensure Firebase Function is deployed: `firebase deploy --only functions:generateStreamChatToken`

#### 2. User Not Found
- **Cause**: User not synced to Stream Chat
- **Solution**: Ensure user profile is created in Stream when they sign up

#### 3. Messages Not Appearing
- **Cause**: Channel filter incorrect or user not member
- **Solution**: Verify channel membership and filter criteria

#### 4. Push Notifications Not Working
- **Cause**: Device token not registered
- **Solution**: Call `addDevice` with APNs token after user connects

#### 5. Offline Messages Not Syncing
- **Cause**: Local storage disabled
- **Solution**: Enable `isLocalStorageEnabled` in config

### Performance Optimization

1. **Pagination**: Load messages in batches
```swift
channelController.loadNextMessages(limit: 25)
```

2. **Image Compression**: Compress images before upload
```swift
image.jpegData(compressionQuality: 0.7)
```

3. **Channel List Limit**: Limit initial channel load
```swift
ChannelListQuery(pageSize: 20)
```

4. **Lazy Loading**: Use lazy loading for user avatars and attachments

---

## Migration Checklist

- [ ] Add Stream Chat SDK to iOS project
- [ ] Configure Info.plist permissions
- [ ] Implement Firebase authentication flow
- [ ] Set up Stream token generation
- [ ] Create StreamChatService singleton
- [ ] Implement channel list UI
- [ ] Add message composition UI
- [ ] Configure push notifications
- [ ] Enable offline support
- [ ] Test direct messages
- [ ] Test group channels
- [ ] Verify typing indicators
- [ ] Test file/image uploads
- [ ] Implement message reactions
- [ ] Add error handling
- [ ] Test on various iOS versions
- [ ] Performance testing with large channels
- [ ] Submit for App Store review

---

## Support & Resources

### Documentation
- [Stream Chat iOS SDK Docs](https://getstream.io/chat/docs/ios/)
- [Stream Chat iOS Tutorial](https://getstream.io/chat/ios/tutorial/)
- [API Reference](https://getstream.io/chat/docs/ios/ios/)

### Firebase Functions
- Function logs: `firebase functions:log`
- Deploy function: `firebase deploy --only functions:generateStreamChatToken`

### Contact Information
- Stream Support: support@getstream.io
- Firebase Support: https://firebase.google.com/support

---

## Appendix: Web Implementation Reference

### Key Web Files for Reference
1. `/src/contexts/StreamChatContext.js` - Connection management
2. `/src/services/streamChatService.js` - Core Stream service
3. `/src/pages/ChatStreamPro.js` - Main chat UI
4. `/functions/index.js` - Token generation function
5. `/src/components/chat/` - UI components

### Web Features to Replicate
- Real-time message sync
- Typing indicators  
- Read receipts
- Message reactions
- File/image uploads
- Thread replies
- Channel search
- User presence
- Push notifications
- Offline support

---

*Document Version: 1.0*  
*Last Updated: December 2024*  
*For: Focal Point iOS Development Team*