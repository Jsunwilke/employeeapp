import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ConversationSettingsView: View {
    let conversation: Conversation
    @StateObject private var chatManager = ChatManager.shared
    @State private var isEditingName = false
    @State private var newName = ""
    @State private var showAddParticipants = false
    @State private var showDeleteConfirmation = false
    @State private var participantToRemove: ChatUser?
    @State private var showRemoveConfirmation = false
    @State private var showLeaveConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    private let currentUserId = Auth.auth().currentUser?.uid ?? ""
    
    // Get participant users from organization users
    private var participantUsers: [ChatUser] {
        conversation.participants.compactMap { participantId in
            chatManager.organizationUsers.first { $0.id == participantId }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // Group Name Section (only for groups)
                if conversation.type == .group {
                    groupNameSection
                }
                
                // Participants Section
                participantsSection
                
                // Conversation Info
                conversationInfoSection
                
                // Leave Group (only for groups with 3+ participants)
                if conversation.type == .group && conversation.participants.count > 2 {
                    Section {
                        Button(action: {
                            showLeaveConfirmation = true
                        }) {
                            Label("Leave Group", systemImage: "arrow.right.square")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Danger Zone
                if conversation.type == .group {
                    dangerZoneSection
                }
            }
            .navigationTitle("Conversation Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddParticipants) {
                EmployeeSelectorView { selectedUsers in
                    Task {
                        await addSelectedParticipants(selectedUsers)
                    }
                }
            }
            .confirmationDialog(
                "Remove Participant",
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible,
                presenting: participantToRemove
            ) { participant in
                Button("Remove \(participant.firstName)", role: .destructive) {
                    Task {
                        await removeParticipant(participant)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { participant in
                Text("Are you sure you want to remove \(participant.fullName) from this conversation?")
            }
            .confirmationDialog(
                "Delete Conversation",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Conversation", role: .destructive) {
                    Task {
                        await deleteConversation()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this conversation? This action cannot be undone.")
            }
            .confirmationDialog(
                "Leave Group",
                isPresented: $showLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Leave Group", role: .destructive) {
                    Task {
                        await leaveConversation()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to leave this group? You will need to be re-added to rejoin.")
            }
        }
    }
    
    // MARK: - Sections
    
    private var groupNameSection: some View {
        Section("Group Name") {
            if isEditingName {
                HStack {
                    TextField("Group name", text: $newName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Save") {
                        Task {
                            await saveGroupName()
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button("Cancel") {
                        isEditingName = false
                        newName = conversation.displayName
                    }
                    .foregroundColor(.red)
                }
            } else {
                HStack {
                    Text(conversation.displayName)
                    Spacer()
                    Button(action: {
                        isEditingName = true
                        newName = conversation.displayName
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }
    
    private var participantsSection: some View {
        Section("Participants (\(conversation.participants.count))") {
            // Add participants button (groups only)
            if conversation.type == .group {
                Button(action: { showAddParticipants = true }) {
                    Label("Add Participants", systemImage: "person.badge.plus")
                        .foregroundColor(.blue)
                }
            }
            
            // List participants
            ForEach(participantUsers, id: \.id) { user in
                HStack {
                    // Avatar
                    UserAvatar(user: user, size: 40)
                    
                    // User info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(user.fullName)
                                .font(.headline)
                            
                            if user.id == currentUserId {
                                Text("(You)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text(user.email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Remove button (only for groups with 3+ participants, not for self)
                    if conversation.type == .group &&
                       conversation.participants.count > 2 &&
                       user.id != currentUserId {
                        Button(action: {
                            participantToRemove = user
                            showRemoveConfirmation = true
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var conversationInfoSection: some View {
        Section("Information") {
            HStack {
                Text("Type")
                Spacer()
                Text(conversation.type == .group ? "Group Chat" : "Direct Message")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Created")
                Spacer()
                Text(conversation.createdAt.dateValue(), style: .date)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var dangerZoneSection: some View {
        Section {
            Button(action: {
                showDeleteConfirmation = true
            }) {
                Label("Delete Conversation", systemImage: "trash")
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Methods
    
    private func saveGroupName() async {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        await chatManager.updateConversationName(conversation, newName: trimmedName)
        isEditingName = false
    }
    
    private func addSelectedParticipants(_ users: [ChatUser]) async {
        let userIds = users.map { $0.id }
        await chatManager.addParticipants(userIds, to: conversation)
    }
    
    private func removeParticipant(_ user: ChatUser) async {
        await chatManager.removeParticipant(user.id, from: conversation, participantName: user.fullName)
    }
    
    private func deleteConversation() async {
        await chatManager.deleteConversation(conversation)
        dismiss()
    }
    
    private func leaveConversation() async {
        let success = await chatManager.leaveConversation(conversation)
        if success {
            dismiss()
        }
    }
}

// MARK: - User Avatar View
struct UserAvatar: View {
    let user: ChatUser
    let size: CGFloat
    
    var body: some View {
        ZStack {
            if let photoURL = user.photoURL, !photoURL.isEmpty, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    case .failure(_), .empty:
                        avatarPlaceholder
                    @unknown default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
    }
    
    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
                .frame(width: size, height: size)
            
            Text(user.initials)
                .foregroundColor(.white)
                .font(.system(size: size * 0.4, weight: .medium))
        }
    }
    
    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red]
        let index = abs(user.id.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Preview
struct ConversationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview disabled due to Conversation's custom Codable implementation
        Text("ConversationSettingsView Preview")
    }
}