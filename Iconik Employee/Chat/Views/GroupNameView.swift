import SwiftUI

struct GroupNameView: View {
    let selectedUsers: [ChatUser]
    let onComplete: (String) -> Void
    
    @State private var groupName = ""
    @FocusState private var isNameFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Group icon
                Image(systemName: "person.3.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 40)
                
                // Title
                Text("Name your group")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter group name", text: $groupName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isNameFieldFocused)
                        .onSubmit {
                            if !groupName.isEmpty {
                                createGroup()
                            }
                        }
                }
                .padding(.horizontal)
                
                // Participants preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Participants (\(selectedUsers.count + 1))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            // Current user (You)
                            ParticipantChip(name: "You", isCurrentUser: true)
                            
                            // Selected users
                            ForEach(selectedUsers) { user in
                                ParticipantChip(name: user.firstName)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Create button
                Button(action: createGroup) {
                    Text("Create Group")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(groupName.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(10)
                }
                .disabled(groupName.isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isNameFieldFocused = true
            }
        }
    }
    
    private func createGroup() {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        onComplete(trimmedName)
        dismiss()
    }
}

// MARK: - Participant Chip
struct ParticipantChip: View {
    let name: String
    var isCurrentUser: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.caption)
            
            Text(name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isCurrentUser ? Color.blue.opacity(0.2) : Color(.systemGray5))
        .foregroundColor(isCurrentUser ? .blue : .primary)
        .cornerRadius(15)
    }
}

// MARK: - Preview
struct GroupNameView_Previews: PreviewProvider {
    static var previews: some View {
        GroupNameView(
            selectedUsers: [
                ChatUser(
                    id: "1",
                    organizationID: "org1",
                    firstName: "John",
                    lastName: "Doe",
                    email: "john@example.com",
                    displayName: nil,
                    photoURL: nil,
                    isActive: true
                )
            ],
            onComplete: { _ in }
        )
    }
}