import SwiftUI
import FirebaseAuth

struct EmployeeSelectorView: View {
    @StateObject private var chatManager = ChatManager.shared
    @State private var searchText = ""
    @State private var selectedUsers = Set<ChatUser>()
    @Environment(\.dismiss) private var dismiss
    
    let onSelection: ([ChatUser]) -> Void
    
    private let currentUserId = Auth.auth().currentUser?.uid ?? ""
    
    // Filtered users based on search
    private var filteredUsers: [ChatUser] {
        let users = chatManager.organizationUsers.filter { $0.id != currentUserId }
        
        if searchText.isEmpty {
            return users
        }
        
        return users.filter { user in
            user.fullName.localizedCaseInsensitiveContains(searchText) ||
            user.email.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Selected users chips
                if !selectedUsers.isEmpty {
                    selectedUsersView
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    
                    Divider()
                }
                
                // Users list
                if chatManager.organizationUsers.isEmpty {
                    emptyStateView
                } else {
                    usersList
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Start") {
                        onSelection(Array(selectedUsers))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedUsers.isEmpty)
                }
            }
            .searchable(text: $searchText, prompt: "Search by name or email")
            .onAppear {
                if chatManager.organizationUsers.isEmpty {
                    Task {
                        await chatManager.loadOrganizationUsers()
                    }
                }
            }
        }
    }
    
    // MARK: - Views
    
    private var selectedUsersView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedUsers)) { user in
                    HStack(spacing: 4) {
                        Text(user.fullName)
                            .font(.caption)
                            .lineLimit(1)
                        
                        Button(action: {
                            selectedUsers.remove(user)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .cornerRadius(15)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Team Members Found")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("No other active users in your organization")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var usersList: some View {
        List {
            ForEach(filteredUsers, id: \.id) { user in
                UserRow(
                    user: user,
                    isSelected: selectedUsers.contains(user),
                    onTap: {
                        toggleUserSelection(user)
                    }
                )
            }
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Methods
    
    private func toggleUserSelection(_ user: ChatUser) {
        if selectedUsers.contains(user) {
            selectedUsers.remove(user)
        } else {
            selectedUsers.insert(user)
        }
    }
}

// MARK: - User Row
struct UserRow: View {
    let user: ChatUser
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                userAvatar
                
                // User info
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.fullName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(user.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title3)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var userAvatar: some View {
        ZStack {
            if let photoURL = user.photoURL, !photoURL.isEmpty, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
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
                .frame(width: 40, height: 40)
            
            Text(user.initials)
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .medium))
        }
    }
    
    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red]
        let index = abs(user.id.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Preview
struct EmployeeSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        EmployeeSelectorView { _ in }
    }
}