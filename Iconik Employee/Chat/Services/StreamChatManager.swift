import Foundation
import StreamChat
import FirebaseAuth
import FirebaseFunctions

@MainActor
class StreamChatManager: ObservableObject {
    static let shared = StreamChatManager()
    
    // Stream Chat client
    private var chatClient: ChatClient?
    
    // Published properties
    @Published var isConnected = false
    @Published var connectionError: String?
    
    // API Configuration
    private let apiKey = "fgxkbmk4kp9f"
    
    private init() {}
    
    // MARK: - Connection Management
    
    func connect() async throws {
        guard let firebaseUser = Auth.auth().currentUser else {
            throw StreamChatError.notAuthenticated
        }
        
        // Get Stream token from Firebase Function
        let token = try await getStreamToken(for: firebaseUser.uid)
        
        // Configure Stream Chat
        var config = ChatClientConfig(apiKey: .init(apiKey))
        config.isLocalStorageEnabled = true
        config.shouldConnectAutomatically = true
        config.staysConnectedInBackground = true
        
        // Create client
        chatClient = ChatClient(config: config)
        
        // Get organization ID from UserManager
        let organizationId = UserManager.shared.getCachedOrganizationID()
        
        // Create user info for Stream
        let streamUser = UserInfo(
            id: firebaseUser.uid,
            name: firebaseUser.displayName ?? "User",
            imageURL: firebaseUser.photoURL,
            extraData: [
                "email": .string(firebaseUser.email ?? ""),
                "organizationID": .string(organizationId),
                "role": .string("user")
            ]
        )
        
        // Connecting user: \(streamUser.id)
        
        // Connect to Stream using completion handler
        return try await withCheckedThrowingContinuation { continuation in
            chatClient?.connectUser(
                userInfo: streamUser,
                token: Token(stringLiteral: token)
            ) { error in
                if let error = error {
                    print("[StreamChat] Connection failed: \(error)")
                    continuation.resume(throwing: error)
                } else {
                    // Connection successful
                    self.isConnected = true
                    self.connectionError = nil
                    continuation.resume()
                }
            }
        }
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
        let generateToken = functions.httpsCallable("generateStreamChatToken")
        
        let result = try await generateToken.call(["userId": userId])
        
        guard let data = result.data as? [String: Any],
              let success = data["success"] as? Bool,
              success == true,
              let token = data["token"] as? String else {
            throw StreamChatError.tokenGenerationFailed
        }
        
        return token
    }
    
    // MARK: - Client Access
    
    var client: ChatClient? {
        return chatClient
    }
    
    // MARK: - Channel Management
    
    func getOrCreateDirectMessageChannel(with otherUserId: String, otherUserName: String? = nil) async throws -> ChatChannel {
        guard let client = chatClient,
              let currentUserId = client.currentUserId else {
            throw StreamChatError.notConnected
        }
        
        // Create sorted channel ID for consistency
        let members = [currentUserId, otherUserId].sorted()
        let channelId = "dm-\(members.joined(separator: "-"))"
        
        // Get or create the channel using the correct API
        let channelController = try client.channelController(
            createDirectMessageChannelWith: Set([otherUserId]),
            type: .messaging,
            isCurrentUserMember: true,
            name: nil,
            imageURL: nil,
            extraData: [
                "organizationID": .string(UserManager.shared.getCachedOrganizationID()),
                "channelId": .string(channelId)
            ]
        )
        
        try await channelController.synchronize()
        
        guard let channel = channelController.channel else {
            throw StreamChatError.channelCreationFailed
        }
        
        return channel
    }
    
    func createGroupChannel(name: String, memberIds: [String]) async throws -> ChatChannel {
        guard let client = chatClient,
              let currentUserId = client.currentUserId else {
            throw StreamChatError.notConnected
        }
        
        // Ensure current user is included
        var allMembers = Set(memberIds)
        allMembers.insert(currentUserId)
        
        let channelId = UUID().uuidString
        let cid = ChannelId(type: .team, id: channelId)
        
        let channelController = try client.channelController(
            createChannelWithId: cid,
            name: name,
            imageURL: nil,
            team: nil,
            members: allMembers,
            isCurrentUserMember: true,
            extraData: [
                "organizationID": .string(UserManager.shared.getCachedOrganizationID())
            ]
        )
        
        try await channelController.synchronize()
        
        guard let channel = channelController.channel else {
            throw StreamChatError.channelCreationFailed
        }
        
        return channel
    }
    
    // MARK: - Channel List
    
    func createChannelListController() -> ChatChannelListController? {
        guard let client = chatClient,
              let currentUserId = client.currentUserId else {
            return nil
        }
        
        let organizationId = UserManager.shared.getCachedOrganizationID()
        
        // Create filter for user's channels
        // Note: Custom fields filtering requires backend configuration
        // For now, filter by membership only
        let filter: Filter<ChannelListFilterScope> = .containMembers(userIds: [currentUserId])
        
        let query = ChannelListQuery(
            filter: filter,
            sort: [.init(key: .lastMessageAt, isAscending: false)],
            pageSize: 30
        )
        
        let controller = client.channelListController(query: query)
        // Created channel list controller for user: \(currentUserId)
        return controller
    }
    
    // MARK: - Message Sending
    
    func sendMessage(text: String, to channelId: ChannelId) async throws {
        guard let client = chatClient else {
            throw StreamChatError.notConnected
        }
        
        let channelController = client.channelController(for: channelId)
        
        // Use completion handler version
        return try await withCheckedThrowingContinuation { continuation in
            channelController.createNewMessage(text: text) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Error Types

enum StreamChatError: LocalizedError {
    case notAuthenticated
    case notConnected
    case tokenGenerationFailed
    case connectionFailed
    case channelCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .notConnected:
            return "Not connected to Stream Chat"
        case .tokenGenerationFailed:
            return "Failed to generate Stream Chat token"
        case .connectionFailed:
            return "Failed to connect to Stream Chat"
        case .channelCreationFailed:
            return "Failed to create channel"
        }
    }
}