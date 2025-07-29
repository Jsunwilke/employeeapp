import SwiftUI
import FirebaseAuth

struct MessageThreadView: View {
    let conversation: Conversation?
    @StateObject private var chatManager = ChatManager.shared
    @State private var messageText = ""
    @State private var scrollToBottom = false
    @FocusState private var isMessageFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    private let currentUserId = Auth.auth().currentUser?.uid ?? ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Load more button
                        if chatManager.hasMoreMessages {
                            Button(action: {
                                Task {
                                    await chatManager.loadMoreMessages()
                                }
                            }) {
                                HStack {
                                    if chatManager.messagesLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.up.circle")
                                    }
                                    Text("Load earlier messages")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                                .padding(.vertical, 8)
                            }
                        }
                        
                        // Messages
                        ForEach(chatManager.messages) { message in
                            MessageBubbleView(
                                message: message,
                                isOwnMessage: message.senderId == currentUserId,
                                showSenderName: shouldShowSenderName(for: message)
                            )
                            .id(message.id)
                        }
                        
                        // Invisible anchor for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .refreshable {
                    await chatManager.refreshMessages()
                }
                .onChange(of: chatManager.messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: scrollToBottom) { shouldScroll in
                    if shouldScroll {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        scrollToBottom = false
                    }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            
            // Message input
            messageInputView
        }
        .navigationTitle(conversation?.displayName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        // TODO: Show conversation info
                    }) {
                        Label("Conversation Info", systemImage: "info.circle")
                    }
                    
                    if conversation?.type == .direct {
                        Button(action: {
                            // TODO: View profile
                        }) {
                            Label("View Profile", systemImage: "person.circle")
                        }
                    }
                    
                    Button(action: {
                        Task {
                            await chatManager.refreshMessages()
                        }
                    }) {
                        Label("Refresh Messages", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if let conversation = conversation {
                Task {
                    await chatManager.selectConversation(conversation)
                }
            }
        }
        .onDisappear {
            // Only clean up the message listener for this conversation
            chatManager.cleanupMessageListener()
        }
        .onTapGesture {
            isMessageFieldFocused = false
        }
    }
    
    // MARK: - Message Input View
    
    private var messageInputView: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(alignment: .bottom, spacing: 12) {
                // Attachment button
                Button(action: {
                    // TODO: Implement file attachment
                }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
                .disabled(chatManager.isSendingMessage)
                
                // Message field
                HStack(alignment: .bottom) {
                    TextField("Type a message", text: $messageText, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .lineLimit(1...5)
                        .focused($isMessageFieldFocused)
                        .onSubmit {
                            if !messageText.isEmpty {
                                sendMessage()
                            }
                        }
                }
                .background(Color(.systemGray6))
                .cornerRadius(20)
                
                // Send button
                Button(action: sendMessage) {
                    if chatManager.isSendingMessage {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(messageText.isEmpty ? .gray : .blue)
                    }
                }
                .disabled(messageText.isEmpty || chatManager.isSendingMessage)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Helper Methods
    
    private func shouldShowSenderName(for message: ChatMessage) -> Bool {
        // Show sender name in group conversations
        guard conversation?.type == .group else { return false }
        
        // Show sender name if it's not the current user's message
        return message.senderId != currentUserId
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Clear input immediately for better UX
        messageText = ""
        
        Task {
            await chatManager.sendMessage(text: text)
            scrollToBottom = true
        }
    }
}

// MARK: - Message Bubble View
struct MessageBubbleView: View {
    let message: ChatMessage
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
                
                ChatMessageContent(message: message, isOwnMessage: isOwnMessage)
                
                Text(message.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !isOwnMessage { Spacer(minLength: 60) }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Message Content
struct ChatMessageContent: View {
    let message: ChatMessage
    let isOwnMessage: Bool
    
    var body: some View {
        Group {
            switch message.type {
            case .text:
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isOwnMessage ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isOwnMessage ? .white : .primary)
                    .cornerRadius(16)
            case .file:
                FileMessageView(message: message, isOwnMessage: isOwnMessage)
            }
        }
    }
}

// MARK: - File Message View
struct FileMessageView: View {
    let message: ChatMessage
    let isOwnMessage: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.fill")
                    .font(.title3)
                
                VStack(alignment: .leading) {
                    Text("File")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            if let fileUrl = message.fileUrl {
                Button(action: {
                    // TODO: Open file
                }) {
                    Text("Open")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(isOwnMessage ? Color.blue : Color(.systemGray5))
        .foregroundColor(isOwnMessage ? .white : .primary)
        .cornerRadius(16)
    }
}

// MARK: - Preview
struct MessageThreadView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MessageThreadView(conversation: nil)
        }
    }
}