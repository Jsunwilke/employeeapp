import SwiftUI

struct MessageReactionsView: View {
    let messageId: String
    @State private var reactions: [String: Int] = [:]
    @State private var showReactionPicker = false
    @StateObject private var chatManager = ChatManager.shared
    
    // Common quick reactions
    let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🔥"]
    
    var body: some View {
        HStack(spacing: 4) {
            // Show existing reactions
            ForEach(Array(reactions.keys.sorted()), id: \.self) { emoji in
                reactionBubble(emoji: emoji, count: reactions[emoji] ?? 0)
            }
            
            // Add reaction button
            Button(action: {
                showReactionPicker = true
            }) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .padding(4)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
        }
        .popover(isPresented: $showReactionPicker) {
            reactionPickerView
        }
    }
    
    private func reactionBubble(emoji: String, count: Int) -> some View {
        HStack(spacing: 2) {
            Text(emoji)
                .font(.system(size: 14))
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onTapGesture {
            // Toggle reaction
            toggleReaction(emoji)
        }
    }
    
    private var reactionPickerView: some View {
        VStack(spacing: 8) {
            Text("React")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                ForEach(quickReactions, id: \.self) { emoji in
                    Button(action: {
                        toggleReaction(emoji)
                        showReactionPicker = false
                    }) {
                        Text(emoji)
                            .font(.system(size: 24))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
    
    private func toggleReaction(_ emoji: String) {
        // In a real implementation, this would update through Stream Chat
        // For now, we'll just update locally
        if let count = reactions[emoji] {
            if count == 1 {
                reactions.removeValue(forKey: emoji)
            } else {
                reactions[emoji] = count - 1
            }
        } else {
            reactions[emoji] = 1
        }
    }
}

// MARK: - Enhanced Message Bubble with Reactions
struct EnhancedMessageBubbleView: View {
    let message: ChatMessage
    let isOwnMessage: Bool
    let showSenderName: Bool
    @State private var showActions = false
    
    var body: some View {
        VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 2) {
            if message.type == .system {
                // System message layout
                systemMessageView
            } else {
                // Regular message layout
                VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                    if showSenderName && !isOwnMessage, let senderName = message.senderName {
                        Text(senderName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Message content with gesture handling
                    ChatMessageContent(message: message, isOwnMessage: isOwnMessage)
                        .onLongPressGesture {
                            showActions = true
                        }
                        .contextMenu {
                            messageContextMenu
                        }
                    
                    // Reactions
                    if !message.id.hasSuffix("_temp") {
                        MessageReactionsView(messageId: message.id)
                    }
                    
                    Text(message.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var systemMessageView: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Text(systemMessageText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                
                Text(message.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var systemMessageText: String {
        switch message.systemAction {
        case "participants_added":
            if let addedByName = message.addedByName,
               let addedParticipants = message.addedParticipants {
                let names = addedParticipants.joined(separator: ", ")
                return "\(addedByName) added \(names) to the group"
            }
        case "participant_removed":
            if let removedByName = message.removedByName,
               let removedParticipantName = message.removedParticipantName {
                return "\(removedByName) removed \(removedParticipantName) from the group"
            }
        case "participant_left":
            if let leftUserName = message.leftUserName {
                return "\(leftUserName) left the group"
            }
        default:
            break
        }
        return "System message"
    }
    
    @ViewBuilder
    private var messageContextMenu: some View {
        Button(action: {
            UIPasteboard.general.string = message.text
        }) {
            Label("Copy", systemImage: "doc.on.doc")
        }
        
        if isOwnMessage && !message.id.hasSuffix("_temp") {
            Button(action: {
                // Implement edit functionality
            }) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: {
                // Implement delete functionality
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
        
        Button(action: {
            // Implement reply functionality
        }) {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }
    }
}