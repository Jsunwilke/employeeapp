import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Chat Service Protocol
protocol ChatServiceProtocol {
    // Conversation Management
    func createConversation(participants: [String], type: Conversation.ConversationType, customName: String?) async throws -> String
    func getUserConversations(userId: String) async throws -> [Conversation]
    func updateConversationName(conversationId: String, newName: String) async throws
    
    // Messaging
    func sendMessage(conversationId: String, senderId: String, text: String, type: ChatMessage.MessageType, fileUrl: String?, senderName: String) async throws -> String
    func getConversationMessages(conversationId: String, limit: Int, lastDocument: DocumentSnapshot?) async throws -> (messages: [ChatMessage], lastDoc: DocumentSnapshot?, hasMore: Bool)
    func markMessagesAsRead(conversationId: String, userId: String) async throws
    
    // Real-time Listeners
    func subscribeToUserConversations(userId: String, completion: @escaping ([Conversation]) -> Void) -> ListenerRegistration
    func subscribeToConversationMessages(conversationId: String, completion: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration
    func subscribeToNewMessages(conversationId: String, afterTimestamp: Timestamp?, completion: @escaping ([ChatMessage], Bool) -> Void) -> ListenerRegistration
    
    // User Management
    func getOrganizationUsers(organizationId: String) async throws -> [ChatUser]
    func updateUserPresence(userId: String, isOnline: Bool, conversationId: String?) async throws
}

// MARK: - Chat Service Implementation
class ChatService: ChatServiceProtocol {
    private let db = Firestore.firestore()
    private let conversationsCollection = "conversations"
    private let messagesCollection = "messages"
    private let usersCollection = "users"
    private let userPresenceCollection = "userPresence"
    
    static let shared = ChatService()
    
    private init() {}
    
    // MARK: - Conversation Management
    
    func createConversation(participants: [String], type: Conversation.ConversationType, customName: String?) async throws -> String {
        // Check if direct conversation already exists
        if type == .direct && participants.count == 2 {
            let existingConversation = try await findExistingDirectConversation(participants: participants)
            if let existingId = existingConversation {
                return existingId
            }
        }
        
        // Generate default name
        let defaultName = try await generateConversationName(participants: participants, type: type)
        
        // Create conversation document
        let conversationRef = db.collection(conversationsCollection).document()
        let conversationData: [String: Any] = [
            "participants": participants,
            "type": type.rawValue,
            "name": customName ?? NSNull(),
            "defaultName": defaultName,
            "createdAt": FieldValue.serverTimestamp(),
            "lastActivity": FieldValue.serverTimestamp(),
            "unreadCounts": participants.reduce(into: [String: Int]()) { $0[$1] = 0 }
        ]
        
        try await conversationRef.setData(conversationData)
        return conversationRef.documentID
    }
    
    func getUserConversations(userId: String) async throws -> [Conversation] {
        let snapshot = try await db.collection(conversationsCollection)
            .whereField("participants", arrayContains: userId)
            .order(by: "lastActivity", descending: true)
            .getDocuments()
        
        return try snapshot.documents.compactMap { document in
            var data = document.data()
            data["id"] = document.documentID
            
            // Convert Firestore types to JSON-compatible types
            if let createdAt = data["createdAt"] as? Timestamp {
                data["createdAt"] = ["seconds": createdAt.seconds, "nanoseconds": createdAt.nanoseconds]
            }
            if let lastActivity = data["lastActivity"] as? Timestamp {
                data["lastActivity"] = ["seconds": lastActivity.seconds, "nanoseconds": lastActivity.nanoseconds]
            }
            if let lastMessage = data["lastMessage"] as? [String: Any],
               let timestamp = lastMessage["timestamp"] as? Timestamp {
                var updatedLastMessage = lastMessage
                updatedLastMessage["timestamp"] = ["seconds": timestamp.seconds, "nanoseconds": timestamp.nanoseconds]
                data["lastMessage"] = updatedLastMessage
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(Conversation.self, from: jsonData)
        }
    }
    
    func updateConversationName(conversationId: String, newName: String) async throws {
        try await db.collection(conversationsCollection)
            .document(conversationId)
            .updateData(["name": newName])
    }
    
    // MARK: - Messaging
    
    func sendMessage(conversationId: String, senderId: String, text: String, type: ChatMessage.MessageType, fileUrl: String?, senderName: String) async throws -> String {
        // Create message document
        let messageRef = db.collection(messagesCollection)
            .document(conversationId)
            .collection("messages")
            .document()
        
        let messageData: [String: Any] = [
            "senderId": senderId,
            "senderName": senderName,
            "text": text,
            "type": type.rawValue,
            "fileUrl": fileUrl ?? NSNull(),
            "timestamp": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // Use batch write for atomicity
        let batch = db.batch()
        
        // Add message
        batch.setData(messageData, forDocument: messageRef)
        
        // Update conversation last activity and last message
        let conversationRef = db.collection(conversationsCollection).document(conversationId)
        let lastMessageData: [String: Any] = [
            "text": text,
            "senderId": senderId,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        batch.updateData([
            "lastActivity": FieldValue.serverTimestamp(),
            "lastMessage": lastMessageData
        ], forDocument: conversationRef)
        
        // Increment unread counts for all participants except sender
        let conversation = try await conversationRef.getDocument()
        if let participants = conversation.data()?["participants"] as? [String] {
            for participantId in participants where participantId != senderId {
                batch.updateData([
                    "unreadCounts.\(participantId)": FieldValue.increment(Int64(1))
                ], forDocument: conversationRef)
            }
        }
        
        try await batch.commit()
        return messageRef.documentID
    }
    
    func getConversationMessages(conversationId: String, limit: Int = 50, lastDocument: DocumentSnapshot? = nil) async throws -> (messages: [ChatMessage], lastDoc: DocumentSnapshot?, hasMore: Bool) {
        var query = db.collection(messagesCollection)
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let messages = try snapshot.documents.compactMap { document -> ChatMessage? in
            var data = document.data()
            data["id"] = document.documentID
            
            // Convert Firestore types to JSON-compatible types
            if let timestamp = data["timestamp"] as? Timestamp {
                data["timestamp"] = ["seconds": timestamp.seconds, "nanoseconds": timestamp.nanoseconds]
            }
            if let createdAt = data["createdAt"] as? Timestamp {
                data["createdAt"] = ["seconds": createdAt.seconds, "nanoseconds": createdAt.nanoseconds]
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(ChatMessage.self, from: jsonData)
        }.reversed() // Reverse to show chronologically
        
        let lastDoc = snapshot.documents.last
        let hasMore = snapshot.documents.count == limit
        
        return (Array(messages), lastDoc, hasMore)
    }
    
    func markMessagesAsRead(conversationId: String, userId: String) async throws {
        let conversationRef = db.collection(conversationsCollection).document(conversationId)
        try await conversationRef.updateData([
            "unreadCounts.\(userId)": 0
        ])
    }
    
    // MARK: - Real-time Listeners
    
    func subscribeToUserConversations(userId: String, completion: @escaping ([Conversation]) -> Void) -> ListenerRegistration {
        return db.collection(conversationsCollection)
            .whereField("participants", arrayContains: userId)
            .order(by: "lastActivity", descending: true)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching conversations: \(error?.localizedDescription ?? "Unknown error")")
                    completion([])
                    return
                }
                
                let conversations = documents.compactMap { document -> Conversation? in
                    do {
                        var data = document.data()
                        data["id"] = document.documentID
                        
                        // Convert Firestore types to JSON-compatible types
                        if let createdAt = data["createdAt"] as? Timestamp {
                            data["createdAt"] = ["seconds": createdAt.seconds, "nanoseconds": createdAt.nanoseconds]
                        }
                        if let lastActivity = data["lastActivity"] as? Timestamp {
                            data["lastActivity"] = ["seconds": lastActivity.seconds, "nanoseconds": lastActivity.nanoseconds]
                        }
                        if let lastMessage = data["lastMessage"] as? [String: Any],
                           let timestamp = lastMessage["timestamp"] as? Timestamp {
                            var updatedLastMessage = lastMessage
                            updatedLastMessage["timestamp"] = ["seconds": timestamp.seconds, "nanoseconds": timestamp.nanoseconds]
                            data["lastMessage"] = updatedLastMessage
                        }
                        
                        let jsonData = try JSONSerialization.data(withJSONObject: data)
                        return try JSONDecoder().decode(Conversation.self, from: jsonData)
                    } catch {
                        print("Error decoding conversation: \(error)")
                        return nil
                    }
                }
                
                completion(conversations)
            }
    }
    
    func subscribeToConversationMessages(conversationId: String, completion: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration {
        return db.collection(messagesCollection)
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching messages: \(error?.localizedDescription ?? "Unknown error")")
                    completion([])
                    return
                }
                
                let messages = documents.compactMap { document -> ChatMessage? in
                    do {
                        var data = document.data()
                        data["id"] = document.documentID
                        
                        // Convert Firestore types to JSON-compatible types
                        if let timestamp = data["timestamp"] as? Timestamp {
                            data["timestamp"] = ["seconds": timestamp.seconds, "nanoseconds": timestamp.nanoseconds]
                        }
                        if let createdAt = data["createdAt"] as? Timestamp {
                            data["createdAt"] = ["seconds": createdAt.seconds, "nanoseconds": createdAt.nanoseconds]
                        }
                        
                        let jsonData = try JSONSerialization.data(withJSONObject: data)
                        return try JSONDecoder().decode(ChatMessage.self, from: jsonData)
                    } catch {
                        print("Error decoding message: \(error)")
                        return nil
                    }
                }
                
                completion(messages)
            }
    }
    
    func subscribeToNewMessages(conversationId: String, afterTimestamp: Timestamp?, completion: @escaping ([ChatMessage], Bool) -> Void) -> ListenerRegistration {
        let messagesRef = db.collection(messagesCollection)
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
            
            let messages = documents.compactMap { document -> ChatMessage? in
                do {
                    var data = document.data()
                    data["id"] = document.documentID
                    
                    // Convert Firestore types to JSON-compatible types
                    if let timestamp = data["timestamp"] as? Timestamp {
                        data["timestamp"] = ["seconds": timestamp.seconds, "nanoseconds": timestamp.nanoseconds]
                    }
                    if let createdAt = data["createdAt"] as? Timestamp {
                        data["createdAt"] = ["seconds": createdAt.seconds, "nanoseconds": createdAt.nanoseconds]
                    }
                    
                    let jsonData = try JSONSerialization.data(withJSONObject: data)
                    return try JSONDecoder().decode(ChatMessage.self, from: jsonData)
                } catch {
                    print("Error decoding message: \(error)")
                    return nil
                }
            }.reversed() // Reverse to show chronologically
            
            // Only call completion if there are new messages
            if !messages.isEmpty {
                completion(Array(messages), afterTimestamp != nil)
            }
        }
    }
    
    // MARK: - User Management
    
    func getOrganizationUsers(organizationId: String) async throws -> [ChatUser] {
        let snapshot = try await db.collection(usersCollection)
            .whereField("organizationID", isEqualTo: organizationId)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { document in
            let data = document.data()
            
            // Extract fields directly without JSON serialization to avoid Timestamp issues
            guard let organizationID = data["organizationID"] as? String,
                  let firstName = data["firstName"] as? String,
                  let lastName = data["lastName"] as? String,
                  let email = data["email"] as? String else {
                return nil
            }
            
            return ChatUser(
                id: document.documentID,
                organizationID: organizationID,
                firstName: firstName,
                lastName: lastName,
                email: email,
                displayName: data["displayName"] as? String,
                photoURL: data["photoURL"] as? String,
                isActive: data["isActive"] as? Bool ?? true
            )
        }
    }
    
    func updateUserPresence(userId: String, isOnline: Bool, conversationId: String?) async throws {
        let presenceData: [String: Any] = [
            "isOnline": isOnline,
            "lastSeen": FieldValue.serverTimestamp(),
            "conversationId": conversationId ?? NSNull()
        ]
        
        try await db.collection(userPresenceCollection)
            .document(userId)
            .setData(presenceData, merge: true)
    }
    
    // MARK: - Helper Methods
    
    private func findExistingDirectConversation(participants: [String]) async throws -> String? {
        let sortedParticipants = participants.sorted()
        
        let snapshot = try await db.collection(conversationsCollection)
            .whereField("type", isEqualTo: "direct")
            .whereField("participants", isEqualTo: sortedParticipants)
            .limit(to: 1)
            .getDocuments()
        
        return snapshot.documents.first?.documentID
    }
    
    private func generateConversationName(participants: [String], type: Conversation.ConversationType) async throws -> String {
        if type == .direct && participants.count == 2 {
            // For direct chats, get the other user's name
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                return "Direct Chat"
            }
            
            let otherUserId = participants.first(where: { $0 != currentUserId }) ?? participants[0]
            
            if let userDoc = try? await db.collection(usersCollection).document(otherUserId).getDocument(),
               let userData = userDoc.data() {
                let firstName = userData["firstName"] as? String ?? ""
                let lastName = userData["lastName"] as? String ?? ""
                let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? userData["email"] as? String ?? "Unknown User" : name
            }
        }
        
        // For group chats, list participant names
        var names: [String] = []
        for participantId in participants.prefix(3) {
            if let userDoc = try? await db.collection(usersCollection).document(participantId).getDocument(),
               let userData = userDoc.data() {
                let firstName = userData["firstName"] as? String ?? ""
                names.append(firstName)
            }
        }
        
        if participants.count > 3 {
            names.append("and \(participants.count - 3) others")
        }
        
        return names.joined(separator: ", ")
    }
}