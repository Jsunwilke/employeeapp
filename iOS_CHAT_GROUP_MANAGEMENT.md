# iOS Chat Group Management Features

This document provides implementation details for adding group management features to the iOS chat functionality.

## Overview

The web app now supports:
1. **Pinning conversations** (user-specific)
2. **Renaming group conversations**
3. **Adding participants to groups**
4. **Removing participants from groups**
5. **System messages** for participant changes

## 1. Pinning Conversations

### Data Structure
Conversations now have a `pinnedBy` field:
```swift
struct Conversation {
    // ... existing fields ...
    var pinnedBy: [String]? // Array of userIds who pinned this conversation
}
```

### Implementation

#### Check if Conversation is Pinned
```swift
func isConversationPinned(conversation: Conversation, userId: String) -> Bool {
    return conversation.pinnedBy?.contains(userId) ?? false
}
```

#### Toggle Pin Status
```swift
func togglePinConversation(conversationId: String, userId: String, isPinned: Bool) async throws {
    let conversationRef = Firestore.firestore()
        .collection("conversations")
        .document(conversationId)
    
    if isPinned {
        // Add user to pinnedBy array
        try await conversationRef.updateData([
            "pinnedBy": FieldValue.arrayUnion([userId])
        ])
    } else {
        // Remove user from pinnedBy array
        try await conversationRef.updateData([
            "pinnedBy": FieldValue.arrayRemove([userId])
        ])
    }
}
```

#### Sort Conversations (Pinned First)
```swift
func sortConversations(_ conversations: [Conversation], userId: String) -> [Conversation] {
    return conversations.sorted { conv1, conv2 in
        let isPinned1 = isConversationPinned(conversation: conv1, userId: userId)
        let isPinned2 = isConversationPinned(conversation: conv2, userId: userId)
        
        // If one is pinned and the other isn't, pinned comes first
        if isPinned1 && !isPinned2 { return true }
        if !isPinned1 && isPinned2 { return false }
        
        // Otherwise sort by lastActivity
        return conv1.lastActivity > conv2.lastActivity
    }
}
```

### UI Implementation
- Add a pin icon to each conversation cell
- Show pinned conversations with a different background color (e.g., light yellow)
- Display filled pin icon for pinned conversations

## 2. Renaming Group Conversations

### Implementation

#### Update Conversation Name
```swift
func updateConversationName(conversationId: String, newName: String) async throws {
    let conversationRef = Firestore.firestore()
        .collection("conversations")
        .document(conversationId)
    
    try await conversationRef.updateData([
        "name": newName
    ])
}
```

### UI Implementation
- Only show rename option for group conversations (`type == "group"`)
- Add edit button in conversation settings/details screen
- Show text input with current name
- Validate name (max length, not empty)

## 3. Adding Participants to Groups

### Implementation

#### Add Participants
```swift
func addParticipantsToConversation(
    conversationId: String,
    newParticipantIds: [String],
    addedByUserId: String,
    addedByUserName: String
) async throws {
    let db = Firestore.firestore()
    let conversationRef = db.collection("conversations").document(conversationId)
    
    // Get current conversation data
    let conversation = try await conversationRef.getDocument()
    guard let data = conversation.data(),
          var unreadCounts = data["unreadCounts"] as? [String: Int] else {
        throw ChatError.conversationNotFound
    }
    
    // Initialize unread counts for new participants
    for participantId in newParticipantIds {
        unreadCounts[participantId] = 0
    }
    
    // Update conversation
    try await conversationRef.updateData([
        "participants": FieldValue.arrayUnion(newParticipantIds),
        "unreadCounts": unreadCounts
    ])
    
    // Add system message
    let messageData: [String: Any] = [
        "type": "system",
        "systemAction": "participants_added",
        "addedBy": addedByUserId,
        "addedByName": addedByUserName,
        "addedParticipants": newParticipantIds,
        "timestamp": FieldValue.serverTimestamp(),
        "createdAt": FieldValue.serverTimestamp()
    ]
    
    try await db.collection("messages")
        .document(conversationId)
        .collection("messages")
        .addDocument(data: messageData)
}
```

### UI Implementation
- Add "Add Participants" button in group settings
- Show employee selector excluding current participants
- Allow multiple selection
- Update participant count after adding

## 4. Removing Participants from Groups

### Implementation

#### Remove Participant
```swift
func removeParticipantFromConversation(
    conversationId: String,
    participantId: String,
    removedByUserId: String,
    removedByUserName: String,
    removedUserName: String
) async throws {
    let db = Firestore.firestore()
    let conversationRef = db.collection("conversations").document(conversationId)
    
    // Get current conversation data
    let conversation = try await conversationRef.getDocument()
    guard var data = conversation.data(),
          var unreadCounts = data["unreadCounts"] as? [String: Int] else {
        throw ChatError.conversationNotFound
    }
    
    // Remove unread count for the participant
    unreadCounts.removeValue(forKey: participantId)
    
    // Update conversation
    try await conversationRef.updateData([
        "participants": FieldValue.arrayRemove([participantId]),
        "unreadCounts": unreadCounts
    ])
    
    // Add system message
    let messageData: [String: Any] = [
        "type": "system",
        "systemAction": "participant_removed",
        "removedBy": removedByUserId,
        "removedByName": removedByUserName,
        "removedParticipant": participantId,
        "removedParticipantName": removedUserName,
        "timestamp": FieldValue.serverTimestamp(),
        "createdAt": FieldValue.serverTimestamp()
    ]
    
    try await db.collection("messages")
        .document(conversationId)
        .collection("messages")
        .addDocument(data: messageData)
}
```

### UI Implementation
- Show remove button next to each participant (except self)
- Only allow removal if more than 2 participants remain
- Show confirmation dialog before removing
- Update participant list after removal

## 5. Leaving Conversations

### Implementation

#### Leave Group Conversation
```swift
func leaveConversation(conversationId: String, userId: String, userName: String) async throws {
    let db = Firestore.firestore()
    let conversationRef = db.collection("conversations").document(conversationId)
    
    // Get conversation to validate
    let conversation = try await conversationRef.getDocument()
    guard let data = conversation.data() else {
        throw ChatError.conversationNotFound
    }
    
    // Check if user is a participant
    guard let participants = data["participants"] as? [String],
          participants.contains(userId) else {
        throw ChatError.notAParticipant
    }
    
    // Validate conversation type and participant count
    if data["type"] as? String == "direct" {
        throw ChatError.cannotLeaveDirect
    }
    
    if participants.count <= 2 {
        throw ChatError.cannotLeaveLastTwo
    }
    
    // Remove user from participants and unread counts
    var unreadCounts = data["unreadCounts"] as? [String: Int] ?? [:]
    unreadCounts.removeValue(forKey: userId)
    
    try await conversationRef.updateData([
        "participants": FieldValue.arrayRemove([userId]),
        "unreadCounts": unreadCounts
    ])
    
    // Add system message
    let messageData: [String: Any] = [
        "type": "system",
        "systemAction": "participant_left",
        "leftUserId": userId,
        "leftUserName": userName,
        "timestamp": FieldValue.serverTimestamp(),
        "createdAt": FieldValue.serverTimestamp()
    ]
    
    try await db.collection("messages")
        .document(conversationId)
        .collection("messages")
        .addDocument(data: messageData)
}
```

### UI Implementation
- Add "Leave Group" button in conversation settings
- Only show for group conversations with 3+ participants
- Show confirmation dialog before leaving
- Remove conversation from local list after leaving
- Navigate back to conversation list

### Error Handling
```swift
enum ChatError: Error {
    // ... existing cases ...
    case notAParticipant
    case cannotLeaveDirect
    case cannotLeaveLastTwo
    
    var localizedDescription: String {
        switch self {
        // ... existing cases ...
        case .notAParticipant:
            return "You are not a participant in this conversation"
        case .cannotLeaveDirect:
            return "Cannot leave direct conversations"
        case .cannotLeaveLastTwo:
            return "Cannot leave group - at least 2 participants must remain"
        }
    }
}
```

## 6. System Messages

### Message Type
```swift
enum MessageType: String {
    case text = "text"
    case file = "file"
    case system = "system"
}

struct Message {
    // ... existing fields ...
    var type: MessageType
    var systemAction: String? // "participants_added", "participant_removed", or "participant_left"
    var addedBy: String?
    var addedByName: String?
    var addedParticipants: [String]?
    var removedBy: String?
    var removedByName: String?
    var removedParticipant: String?
    var removedParticipantName: String?
    var leftUserId: String?
    var leftUserName: String?
}
```

### Rendering System Messages
```swift
func renderSystemMessage(_ message: Message) -> String {
    guard message.type == .system else { return "" }
    
    switch message.systemAction {
    case "participants_added":
        let addedNames = message.addedParticipants?
            .compactMap { getUserName(for: $0) }
            .joined(separator: ", ") ?? ""
        return "\(message.addedByName ?? "Someone") added \(addedNames) to the group"
        
    case "participant_removed":
        return "\(message.removedByName ?? "Someone") removed \(message.removedParticipantName ?? "a participant") from the group"
        
    case "participant_left":
        return "\(message.leftUserName ?? "Someone") left the group"
        
    default:
        return "System message"
    }
}
```

### UI Implementation
- Display system messages centered with gray background
- Use smaller font size than regular messages
- Don't show sender avatar or name
- Include timestamp

## 7. Conversation Settings Screen

Create a settings/details screen that shows:

```swift
struct ConversationSettingsView: View {
    let conversation: Conversation
    @State private var isEditingName = false
    @State private var newName = ""
    @State private var showAddParticipants = false
    @State private var showLeaveConfirmation = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            // Group Name Section (only for groups)
            if conversation.type == "group" {
                Section("Group Name") {
                    if isEditingName {
                        HStack {
                            TextField("Group name", text: $newName)
                            Button("Save") {
                                saveGroupName()
                            }
                            Button("Cancel") {
                                isEditingName = false
                                newName = conversation.name ?? ""
                            }
                        }
                    } else {
                        HStack {
                            Text(conversation.name ?? "Unnamed Group")
                            Spacer()
                            Button(action: { 
                                isEditingName = true
                                newName = conversation.name ?? ""
                            }) {
                                Image(systemName: "pencil")
                            }
                        }
                    }
                }
            }
            
            // Participants Section
            Section("Participants (\(conversation.participants.count))") {
                // Add participants button (groups only)
                if conversation.type == "group" {
                    Button(action: { showAddParticipants = true }) {
                        Label("Add Participants", systemImage: "person.badge.plus")
                    }
                }
                
                // List participants
                ForEach(conversation.participants, id: \.self) { participantId in
                    ParticipantRow(
                        participantId: participantId,
                        canRemove: conversation.type == "group" && 
                                  conversation.participants.count > 2 &&
                                  participantId != currentUserId
                    )
                }
            }
            
            // Conversation Type
            Section("Conversation Type") {
                HStack {
                    Text(conversation.type == "group" ? "👥 Group Chat" : "👤 Direct Message")
                    Spacer()
                }
            }
            
            // Leave Group Section (only for groups with 3+ participants)
            if conversation.type == "group" && conversation.participants.count > 2 {
                Section {
                    Button(action: { showLeaveConfirmation = true }) {
                        Label("Leave Group", systemImage: "arrow.right.square")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .confirmationDialog(
            "Leave Group",
            isPresented: $showLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave Group", role: .destructive) {
                Task {
                    do {
                        try await leaveConversation(
                            conversationId: conversation.id,
                            userId: currentUserId,
                            userName: currentUserName
                        )
                        dismiss()
                    } catch {
                        // Show error
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to leave this group? You will need to be re-added to rejoin.")
        }
    }
}
```

## 7. Error Handling

```swift
enum ChatError: Error {
    case conversationNotFound
    case insufficientPermissions
    case invalidOperation
    case networkError
    
    var localizedDescription: String {
        switch self {
        case .conversationNotFound:
            return "Conversation not found"
        case .insufficientPermissions:
            return "You don't have permission to perform this action"
        case .invalidOperation:
            return "This operation is not allowed"
        case .networkError:
            return "Network error. Please try again"
        }
    }
}
```

## 8. Best Practices

1. **Cache Management**
   - Update local cache when pinning/unpinning
   - Update participant lists in cached conversations
   - Clear/update cache when participants change

2. **Real-time Updates**
   - Listen for changes to conversation document
   - Update UI when `pinnedBy`, `participants`, or `name` changes
   - Handle system messages in real-time

3. **Permissions**
   - Check if user is participant before allowing actions
   - Validate group type before showing group-only features
   - Handle permission errors gracefully

4. **Performance**
   - Batch operations when possible
   - Use transactions for multi-step operations
   - Implement optimistic UI updates

## 10. Testing Checklist

- [ ] Pin/unpin conversations persists across app restarts
- [ ] Pinned conversations appear at top of list
- [ ] Group names can be changed and sync across devices
- [ ] Can add multiple participants at once
- [ ] Can't remove last 2 participants from group
- [ ] Can leave group conversations with 3+ participants
- [ ] Cannot leave direct conversations
- [ ] Cannot leave group if only 2 participants remain
- [ ] System messages appear when participants change (added/removed/left)
- [ ] Conversation is removed from list after leaving
- [ ] All changes sync in real-time across devices
- [ ] Error handling works for network failures
- [ ] UI updates optimistically before server confirmation

## 10. Firebase Security Rules

The web app has updated Firebase security rules to allow these operations. The key changes:
- `participants` array can be updated by any current participant
- `pinnedBy` array can be updated by authenticated users
- `name` field can be updated by participants
- System messages can be created by participants

These rules are already deployed and active.