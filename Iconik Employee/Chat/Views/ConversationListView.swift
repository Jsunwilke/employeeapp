//  ConversationListView.swift
//  Iconik Employee — Chat, converted to the Ambient design language in AMB.6.
//
//  Ported from the mockup the operator approved on device (iPhone + iPad,
//  2026-07-25) as part of batch 1. The capability inventory it is checked
//  against is AMB6_CHAT_PARITY.md, read out of the previous version of this
//  file rather than from the mockup — three phases running, that walk has found
//  features an approved design had silently dropped.
//
//  THIS IS A `List`, AND THAT IS LOAD-BEARING RATHER THAN A STYLE CHOICE.
//  `.swipeActions` is a List-only modifier: on a row inside a LazyVStack it
//  compiles, renders, and silently does nothing. Pin and delete are real
//  capabilities here, so the cost of keeping them is stripping List's own
//  chrome — hidden scroll background, clear row backgrounds, no separators,
//  insets set by hand — so the ambient wash shows through.

import SwiftUI

struct ConversationListView: View {
    @StateObject private var chatManager = ChatManager.shared
    // Plain let, NOT @ObservedObject (review round): this view consumes exactly one of
    // the manager's publishers via onReceive; observing the whole object re-evaluated
    // this body on every keyboard show/hide, tab switch, and overlay toggle.
    private let tabBarManager = TabBarManager.shared
    @State private var showNewConversation = false
    @State private var showGroupNaming = false
    @State private var selectedUsersForGroup: [ChatUser] = []
    @State private var searchText = ""
    @State private var pushedConversation: Conversation?

    /// Chat's own accent colour under D11. Not the background — since D14 every
    /// screen takes the one app wash.
    private var feature: Color { FeatureTheme.color(for: "chat") }

    private var currentUserId: String {
        UserManager.shared.getCurrentUserIDUnified() ?? ""
    }

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return chatManager.conversations }
        return chatManager.conversations.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            content
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showNewConversation = true } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search conversations")
        .refreshable { await chatManager.loadConversations() }
        .onAppear {
            Task { await chatManager.initialize() }
            consumePending(tabBarManager.pendingConversation, in: chatManager.conversations)
        }
        // PSH.2: a tapped chat push parks a PendingDeepLink and lands here; the list may
        // still be loading at that moment, so re-check whenever either side changes. The
        // consume rules (emitted value, async mutation hop, expiry) live in ONE place —
        // TabBarManager.consumePendingDeepLink.
        .onReceive(tabBarManager.$pendingConversation) { pending in
            consumePending(pending, in: chatManager.conversations)
        }
        .onReceive(chatManager.$conversations) { list in
            consumePending(tabBarManager.pendingConversation, in: list)
        }
        .sheet(isPresented: $showNewConversation) {
            EmployeeSelectorView { selectedUsers in
                if selectedUsers.count > 1 {
                    selectedUsersForGroup = selectedUsers
                    showGroupNaming = true
                } else {
                    Task { await createNewConversation(with: selectedUsers, groupName: nil) }
                }
            }
        }
        .sheet(isPresented: $showGroupNaming) {
            GroupNameView(selectedUsers: selectedUsersForGroup) { groupName in
                Task { await createNewConversation(with: selectedUsersForGroup, groupName: groupName) }
            }
        }
        // ONE push target on this view. Two stacked NavigationLink(isActive:) is
        // the shape of AMB.1's dead tap; the rule since AMB.3 is one
        // `.ambientPush` per view, with an enum destination if a screen needs
        // more. This screen needs exactly one.
        .ambientPush(item: $pushedConversation) { conversation in
            MessageThreadView(conversation: conversation)
        }
    }

    private func consumePending(_ pending: PendingDeepLink?, in conversations: [Conversation]) {
        tabBarManager.consumePendingDeepLink(\.pendingConversation, emitted: pending,
                                             in: conversations, id: { $0.id }) { match in
            pushedConversation = match
        }
    }

    @ViewBuilder
    private var content: some View {
        if chatManager.isLoading && chatManager.conversations.isEmpty {
            ProgressView("Loading conversations…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            // The failure banner. `errorMessage` is published and, before AMB.6,
            // was surfaced only as an alert that fired on CHANGE — so two
            // identical consecutive failures raised it once and a failure that
            // arrived while the alert was dismissed was lost entirely. A banner
            // is honest about a state that persists.
            if let error = chatManager.errorMessage {
                failureBanner(error).modifier(ChatListRow())
            }

            if filteredConversations.isEmpty {
                AmbientEmptyState(
                    title: searchText.isEmpty ? "No conversations" : "Nothing found",
                    message: searchText.isEmpty
                        ? "Start a conversation with your team members."
                        : "Nothing matches “\(searchText)”.",
                    systemImage: "bubble.left.and.bubble.right",
                    // RESTORED. The old empty state carried this button and the
                    // conversion dropped it, because the shared component had no
                    // action slot. Only when nothing is being searched for —
                    // "no search results" is not the moment to offer a new group.
                    actionTitle: searchText.isEmpty ? "New Conversation" : nil,
                    actionIcon: "plus.circle.fill",
                    action: searchText.isEmpty ? { showNewConversation = true } : nil,
                    actionTint: feature
                )
                .modifier(ChatListRow())
            } else {
                ForEach(filteredConversations) { conversation in
                    ConversationRow(conversation: conversation, currentUserId: currentUserId)
                        .contentShape(Rectangle())
                        .onTapGesture { pushedConversation = conversation }
                        .modifier(ChatListRow())
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                Task { await chatManager.togglePinConversation(conversation) }
                            } label: {
                                let isPinned = conversation.isPinned(by: currentUserId)
                                Label(isPinned ? "Unpin" : "Pin",
                                      systemImage: isPinned ? "pin.slash" : "pin")
                            }
                            .tint(conversation.isPinned(by: currentUserId) ? .gray : .orange)
                        }
                        // GROUPS ONLY. A direct message cannot be swiped away,
                        // and that asymmetry is deliberate — it is in the parity
                        // inventory twice because it is easy to read as "delete
                        // exists" rather than "delete is conditional".
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if conversation.type == .group {
                                Button(role: .destructive) {
                                    Task { await chatManager.deleteConversation(conversation) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func failureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Something went wrong")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                chatManager.errorMessage = nil
                Task { await chatManager.loadConversations() }
            } label: {
                Text("Retry").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(feature)
        }
        .ambientCard(density: .compact,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
    }

    private func createNewConversation(with users: [ChatUser], groupName: String?) async {
        guard !users.isEmpty else { return }

        do {
            let participantIds = users.map { $0.id }
            let conversationType: Conversation.ConversationType = users.count == 1 ? .direct : .group

            let conversationId = try await chatManager.createConversation(
                with: participantIds,
                type: conversationType,
                customName: groupName
            )

            await chatManager.loadConversations()
            if let newConversation = chatManager.conversations.first(where: { $0.id == conversationId }) {
                pushedConversation = newConversation
            }
        } catch {
            chatManager.errorMessage = error.localizedDescription
        }
    }
}

/// Strips a List row back to nothing so the ambient wash shows through and the
/// cards supply all the spacing — while keeping the row a real List row, which
/// is what keeps `.swipeActions` alive.
private struct ChatListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: AmbientDensity.compact.stackSpacing / 2,
                                      leading: 16,
                                      bottom: AmbientDensity.compact.stackSpacing / 2,
                                      trailing: 16))
    }
}

// MARK: - Conversation row

struct ConversationRow: View {
    let conversation: Conversation
    let currentUserId: String
    var density: AmbientDensity = .compact

    private var unreadCount: Int { conversation.unreadCount(for: currentUserId) }
    private var unread: Bool { unreadCount > 0 }
    private var isPinned: Bool { conversation.isPinned(by: currentUserId) }

    var body: some View {
        HStack(spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: density.contentSpacing) {
                HStack(spacing: 5) {
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }

                    Text(conversation.displayName)
                        .font(unread ? density.titleFont.weight(.bold) : density.titleFont)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage.formattedTime)
                            .font(.caption2)
                            .foregroundStyle(unread ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.tertiary))
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    if let lastMessage = conversation.lastMessage {
                        Text(messagePreview(lastMessage))
                            .font(density.subtitleFont)
                            .foregroundStyle(unread ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("No messages yet")
                            .font(density.subtitleFont)
                            .foregroundStyle(.secondary)
                            .italic()
                    }

                    Spacer(minLength: 0)

                    if unread {
                        Text("\(unreadCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 19, minHeight: 19)
                            .background(Capsule().fill(AmbientStyle.brand))
                    }
                }
            }
        }
        // Pinned is an orange HAIRLINE, not the old 10% orange wash over the
        // whole row: under D11 the page already carries a colour, and a second
        // full-row tint on top of it reads as a rendering fault, not emphasis.
        .ambientCard(density: density,
                     border: .hairline(isPinned
                                       ? Color.orange.opacity(0.45)
                                       : Color.primary.opacity(0.08)))
    }

    private var avatar: some View {
        Group {
            if conversation.type == .group {
                ZStack {
                    // Seeded from the conversation id as before, but through
                    // AmbientStyle.stableHash rather than `hashValue`, which is
                    // seeded per process — the same conversation used to change
                    // colour after every relaunch.
                    Circle().fill(AmbientStyle.avatarColor(conversation.id).gradient)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            } else {
                AmbientAvatar(name: conversation.displayName, size: 44)
            }
        }
    }

    /// The app's media sniffing, unchanged: Photo / File / GIF / Link, plus the
    /// "You: " prefix.
    ///
    /// ONE CHANGE, forced by the decode repair. `last_message` is a text column
    /// and this app writes bare text into it, so a row written by this app
    /// carries no sender id at all. Rather than guess — and be wrong half the
    /// time — an unknown sender simply gets no prefix. Rows written by the web
    /// app carry the object and still say "You:".
    private func messagePreview(_ lastMessage: LastMessage) -> String {
        let text = lastMessage.text
        let senderIsMe = !lastMessage.senderId.isEmpty
            && lastMessage.senderId.lowercased() == currentUserId.lowercased()

        func prefixed(_ body: String) -> String {
            senderIsMe ? "You: \(body)" : body
        }

        if text == "📷 Photo" || text == "📎 File" || text == "🎬 GIF" {
            return prefixed(text)
        }

        let lowered = text.lowercased()

        if lowered.contains("giphy.com") || lowered.contains(".gif") || lowered.contains("tenor.com") {
            return prefixed("🎬 GIF")
        }

        if lowered.contains(".jpg") || lowered.contains(".jpeg")
            || lowered.contains(".png") || lowered.contains(".webp") {
            return prefixed("📷 Photo")
        }

        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return prefixed("🔗 Link")
        }

        return prefixed(text)
    }
}
