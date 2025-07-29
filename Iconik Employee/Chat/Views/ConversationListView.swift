import SwiftUI
import FirebaseAuth

struct ConversationListView: View {
    @StateObject private var chatManager = ChatManager.shared
    @State private var showNewConversation = false
    @State private var searchText = ""
    @State private var selectedConversation: Conversation?
    @State private var showErrorAlert = false
    
    // Filtered conversations based on search
    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return chatManager.conversations
        }
        return chatManager.conversations.filter { conversation in
            conversation.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if chatManager.isLoading && chatManager.conversations.isEmpty {
                    ProgressView("Loading conversations...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if chatManager.conversations.isEmpty && !chatManager.isLoading {
                    emptyStateView
                } else {
                    conversationsList
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showNewConversation = true }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search conversations")
            .refreshable {
                await chatManager.loadConversations()
            }
            .onAppear {
                Task {
                    await chatManager.initialize()
                }
            }
            .sheet(isPresented: $showNewConversation) {
                EmployeeSelectorView { selectedUsers in
                    Task {
                        await createNewConversation(with: selectedUsers)
                    }
                }
            }
            .alert("Error", isPresented: $showErrorAlert, actions: {
                Button("OK", role: .cancel) { }
            }, message: {
                Text(chatManager.errorMessage ?? "An error occurred")
            })
            .onChange(of: chatManager.errorMessage) { error in
                showErrorAlert = error != nil
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Views
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Conversations")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start a conversation with your team members")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { showNewConversation = true }) {
                Label("New Conversation", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top, 10)
        }
    }
    
    private var conversationsList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                ConversationRow(
                    conversation: conversation,
                    currentUserId: Auth.auth().currentUser?.uid ?? ""
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedConversation = conversation
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        // TODO: Implement archive/delete functionality
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .background(
            NavigationLink(
                destination: MessageThreadView(conversation: selectedConversation),
                isActive: Binding(
                    get: { selectedConversation != nil },
                    set: { if !$0 { selectedConversation = nil } }
                )
            ) {
                EmptyView()
            }
        )
    }
    
    // MARK: - Methods
    
    private func createNewConversation(with users: [ChatUser]) async {
        guard !users.isEmpty else { return }
        
        do {
            let participantIds = users.map { $0.id }
            let conversationType: Conversation.ConversationType = users.count == 1 ? .direct : .group
            
            let conversationId = try await chatManager.createConversation(
                with: participantIds,
                type: conversationType
            )
            
            // Find the newly created conversation and navigate to it
            await chatManager.loadConversations()
            if let newConversation = chatManager.conversations.first(where: { $0.id == conversationId }) {
                selectedConversation = newConversation
            }
        } catch {
            chatManager.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Conversation Row
struct ConversationRow: View {
    let conversation: Conversation
    let currentUserId: String
    
    private var unreadCount: Int {
        conversation.unreadCount(for: currentUserId)
    }
    
    private var hasUnreadMessages: Bool {
        unreadCount > 0
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            conversationAvatar
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.displayName)
                        .font(.headline)
                        .fontWeight(hasUnreadMessages ? .bold : .medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage.formattedTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    if let lastMessage = conversation.lastMessage {
                        Text(messagePreview(lastMessage))
                            .font(.subheadline)
                            .foregroundColor(hasUnreadMessages ? .primary : .secondary)
                            .fontWeight(hasUnreadMessages ? .medium : .regular)
                            .lineLimit(2)
                    } else {
                        Text("No messages yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    Spacer()
                    
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var conversationAvatar: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
                .frame(width: 50, height: 50)
            
            if conversation.type == .group {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20))
            } else {
                Text(avatarInitials)
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .medium))
            }
        }
    }
    
    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red]
        let index = abs(conversation.id.hashValue) % colors.count
        return colors[index]
    }
    
    private var avatarInitials: String {
        let name = conversation.displayName
        let components = name.components(separatedBy: " ")
        
        if components.count >= 2 {
            let first = components[0].first?.uppercased() ?? ""
            let last = components[1].first?.uppercased() ?? ""
            return "\(first)\(last)"
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
    
    private func messagePreview(_ lastMessage: LastMessage) -> String {
        if lastMessage.senderId == currentUserId {
            return "You: \(lastMessage.text)"
        }
        return lastMessage.text
    }
}

// MARK: - Preview
struct ConversationListView_Previews: PreviewProvider {
    static var previews: some View {
        ConversationListView()
    }
}