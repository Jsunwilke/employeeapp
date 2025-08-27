import SwiftUI
import FirebaseAuth
import WebKit  // For WKWebView in AnimatedGifView
import PhotosUI
import UniformTypeIdentifiers

struct MessageThreadView: View {
    let conversation: Conversation?
    @StateObject private var chatManager = ChatManager.shared
    @State private var messageText = ""
    @State private var scrollToBottom = false
    @State private var showConversationSettings = false
    @State private var showEmojiPicker = false
    @State private var showGifPicker = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingMedia = false
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
                        showConversationSettings = true
                    }) {
                        Label("Conversation Settings", systemImage: "gear")
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
                    // Only mark as read when the view actually appears (user is viewing it)
                    await chatManager.selectConversation(conversation, markAsRead: true)
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
        .sheet(isPresented: $showConversationSettings) {
            if let conversation = conversation {
                ConversationSettingsView(conversation: conversation)
            }
        }
        .sheet(isPresented: $showGifPicker) {
            GifPickerView(
                isPresented: $showGifPicker,
                onGifSelected: { gifUrl in
                    // Send GIF as a message
                    Task {
                        await chatManager.sendMessage(
                            text: gifUrl,
                            type: .file,
                            fileUrl: gifUrl
                        )
                    }
                }
            )
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { item in
            if let item = item {
                Task {
                    await handlePhotoSelection(item)
                }
            }
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.pdf, .text, .plainText, .data],
            onCompletion: handleFileSelection
        )
        .overlay(
            Group {
                if isUploadingMedia {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay(
                            VStack {
                                ProgressView()
                                Text("Uploading...")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                        )
                }
            }
        )
        .animation(.easeInOut(duration: 0.2), value: showEmojiPicker)
    }
    
    // MARK: - Message Input View
    
    private var messageInputView: some View {
        VStack(spacing: 0) {
            // Emoji picker overlay
            if showEmojiPicker {
                EmojiPickerView(
                    onEmojiSelected: { emoji in
                        messageText += emoji
                    },
                    isPresented: $showEmojiPicker
                )
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Divider()
            
            HStack(alignment: .bottom, spacing: 8) {
                // Input accessory buttons with sliding menu
                MessageInputAccessoryView(
                    showEmojiPicker: $showEmojiPicker,
                    showGifPicker: $showGifPicker,
                    showPhotoPicker: $showPhotoPicker,
                    onAttachmentTap: {
                        showDocumentPicker = true
                    }
                )
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
                        .onChange(of: isMessageFieldFocused) { focused in
                            if focused {
                                showEmojiPicker = false
                            }
                        }
                }
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .frame(maxWidth: .infinity)
                
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
        // Don't show sender name for system messages
        if message.type == .system {
            return false
        }
        
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
    
    // MARK: - Photo Selection Handler
    
    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        isUploadingMedia = true
        selectedPhotoItem = nil
        
        do {
            // Load the image data
            guard let data = try await item.loadTransferable(type: Data.self) else {
                isUploadingMedia = false
                return
            }
            
            // Convert to UIImage to verify it's valid
            guard let image = UIImage(data: data) else {
                isUploadingMedia = false
                return
            }
            
            // Compress the image for upload
            guard let compressedData = image.jpegData(compressionQuality: 0.8) else {
                isUploadingMedia = false
                return
            }
            
            // Send image through Stream Chat (handles upload internally)
            _ = await chatManager.uploadImage(data: compressedData)
            
            isUploadingMedia = false
        } catch {
            print("Error handling photo selection: \(error)")
            isUploadingMedia = false
        }
    }
    
    // MARK: - File Selection Handler
    
    private func handleFileSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                isUploadingMedia = true
                
                // Start accessing the security-scoped resource
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                do {
                    // Read file data
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    
                    // Send file through Stream Chat (handles upload internally)
                    _ = await chatManager.uploadFile(data: data, fileName: fileName)
                    
                    isUploadingMedia = false
                } catch {
                    print("Error reading file: \(error)")
                    isUploadingMedia = false
                }
            }
        case .failure(let error):
            print("File selection error: \(error)")
        }
    }
}

// MARK: - Message Bubble View
struct MessageBubbleView: View {
    let message: ChatMessage
    let isOwnMessage: Bool
    let showSenderName: Bool
    
    var body: some View {
        if message.type == .system {
            // System message layout
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
        } else {
            // Regular message layout
            HStack(alignment: .bottom, spacing: 8) {
                if isOwnMessage { Spacer(minLength: 60) }
                
                VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                    if showSenderName && !isOwnMessage, let senderName = message.senderName {
                        Text(senderName)
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
}

// MARK: - Message Content
struct ChatMessageContent: View {
    let message: ChatMessage
    let isOwnMessage: Bool
    
    init(message: ChatMessage, isOwnMessage: Bool) {
        self.message = message
        self.isOwnMessage = isOwnMessage
        print("[ChatMessageContent] Rendering message: type=\(message.type.rawValue), text='\(message.text)', fileUrl=\(message.fileUrl ?? "nil")")
    }
    
    var body: some View {
        Group {
            switch message.type {
            case .text:
                // Check if it's a media URL
                if isGifURL(message.text) {
                    let _ = print("[ChatMessageContent] Detected GIF URL in text: \(message.text)")
                    EnhancedGifMessageView(url: message.text, isOwnMessage: isOwnMessage)
                } else if isImageURL(message.text) {
                    let _ = print("[ChatMessageContent] Detected image URL in text: \(message.text)")
                    ChatImageView(url: message.text, isOwnMessage: isOwnMessage)
                } else {
                    Text(message.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isOwnMessage ? Color.blue : Color(.systemGray5))
                        .foregroundColor(isOwnMessage ? .white : .primary)
                        .cornerRadius(16)
                }
            case .file:
                if let fileUrl = message.fileUrl {
                    let _ = print("[ChatMessageContent] File message with URL: \(fileUrl)")
                    if isGifURL(fileUrl) {
                        let _ = print("[ChatMessageContent] Detected GIF URL in fileUrl: \(fileUrl)")
                        EnhancedGifMessageView(url: fileUrl, isOwnMessage: isOwnMessage)
                    } else if isImageURL(fileUrl) {
                        let _ = print("[ChatMessageContent] Detected image URL in fileUrl: \(fileUrl)")
                        ChatImageView(url: fileUrl, isOwnMessage: isOwnMessage)
                    } else {
                        FileMessageView(message: message, isOwnMessage: isOwnMessage)
                    }
                } else {
                    // Fallback to text display if no file URL
                    Text(message.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isOwnMessage ? Color.blue : Color(.systemGray5))
                        .foregroundColor(isOwnMessage ? .white : .primary)
                        .cornerRadius(16)
                }
            case .system:
                Text(message.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func isGifURL(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        let isGif = lowercased.contains(".gif") ||
                   lowercased.contains("giphy.com") ||
                   lowercased.contains("tenor.com") ||
                   lowercased.contains("gfycat.com") ||
                   lowercased.hasPrefix("https://media") && lowercased.contains("gif")
        
        if isGif {
            print("[ChatMessageContent] isGifURL('\(url)') = true")
        }
        return isGif
    }
    
    private func isImageURL(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        return lowercased.contains(".jpg") ||
               lowercased.contains(".jpeg") ||
               lowercased.contains(".png") ||
               lowercased.contains(".webp") ||
               lowercased.contains("imgur.com")
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