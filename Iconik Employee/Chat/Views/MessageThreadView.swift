//  MessageThreadView.swift
//  Iconik Employee — Chat thread, converted to Ambient in AMB.6.
//
//  Ported from the mockup approved on device 2026-07-25. The switches that
//  mockup left live ship in the positions it opened in, which is what the
//  operator approved and what AMB6_CHAT_PARITY.md records:
//
//      timestamps   only when the conversation pauses
//      grouping     on
//      my bubble    the company blue, not chat's pink
//      body font    15pt, against the 17pt default the app rode on
//
//  The bubble colour has a recorded reason: chat's feature colour is #D6409F and
//  under D11 that is also the wash behind this screen, so a pink bubble on a
//  pink wash risks mush. The company blue says "you" without competing with the
//  screen's own colour.

import SwiftUI
import WebKit  // For WKWebView in AnimatedGifView
import PhotosUI
import UniformTypeIdentifiers

struct MessageThreadView: View {
    let conversation: Conversation?
    @StateObject private var chatManager = ChatManager.shared
    @State private var messageText = ""
    @State private var showConversationSettings = false
    @State private var showEmojiPicker = false
    @State private var showGifPicker = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingMedia = false
    /// A message whose send failed. Held here rather than pushed back into the
    /// composer so that typing during an in-flight send cannot destroy it, and it
    /// cannot be wiped by `errorMessage` being cleared by an unrelated success.
    @State private var failedMessage: String?
    @FocusState private var isMessageFieldFocused: Bool

    private var feature: Color { FeatureTheme.color(for: "chat") }
    private var bubbleTint: Color { AmbientStyle.brand }

    private var currentUserId: String {
        UserManager.shared.getCurrentUserIDUnified() ?? ""
    }

    private var messages: [ChatMessage] { chatManager.messages }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature)

            VStack(spacing: 0) {
                scrollback
                // A failure has to be visible ON THIS SCREEN. Four places here
                // write `errorMessage` and nothing read it — the banner lived
                // only on the conversation LIST, so a failed send or a failed
                // upload was completely silent while you watched the bubble
                // disappear. The parity inventory claims this as ADDED; this is
                // the half that did not land.
                // A failed message outranks a generic error: it carries the text
                // and can actually be retried. Only ONE banner shows.
                if let failed = failedMessage {
                    failedMessageBanner(failed)
                } else if let error = chatManager.errorMessage {
                    failureBanner(error)
                }
                composer
            }
        }
        // A PUSHED screen insets itself. The shell applies its clearance inside
        // its own NavigationView, to that container's root — and a safe-area
        // inset does not travel out of a container into what it pushes. Before
        // AMB.6 this screen had no clearance at all, so the composer sat under
        // the floating tab bar whenever the keyboard was down.
        .tabBarClearance()
        .navigationTitle(conversation?.displayName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showConversationSettings = true
                    } label: {
                        Label("Conversation Settings", systemImage: "gear")
                    }

                    // "View Profile" is DELETED rather than restyled. Its body
                    // was an empty TODO — a control that looked live and did
                    // nothing, the same class AMB.3 removed three of. There is
                    // no profile screen in the app for it to reach.

                    Button {
                        Task { await chatManager.refreshMessages() }
                    } label: {
                        Label("Refresh Messages", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            // `errorMessage` is one field on a shared singleton, so arriving here
            // with the conversation LIST's error still set rendered "Couldn't load
            // conversations…" above this composer, with a dismiss button and no
            // relevance. Cleared on entry.
            chatManager.errorMessage = nil
            if let conversation {
                // Registered BEFORE the async select, so a conversations event
                // arriving mid-load already knows this thread is being read.
                chatManager.beginViewing(conversation.id)
                Task { await chatManager.selectConversation(conversation, markAsRead: true) }
            }
        }
        .onDisappear {
            if let conversation {
                chatManager.endViewing(conversation.id)
            }
            chatManager.cleanupMessageListener()
        }
        .sheet(isPresented: $showConversationSettings) {
            if let conversation {
                ConversationSettingsView(conversation: conversation)
            }
        }
        .sheet(isPresented: $showGifPicker) {
            GifPickerView(isPresented: $showGifPicker) { gifUrl in
                Task { await chatManager.sendMessage(text: gifUrl, type: .file, fileUrl: gifUrl) }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { item in
            if let item { Task { await handlePhotoSelection(item) } }
        }
        .fileImporter(isPresented: $showDocumentPicker,
                      allowedContentTypes: [.pdf, .text, .plainText, .data],
                      onCompletion: handleFileSelection)
        .overlay {
            if isUploadingMedia { uploadingOverlay }
        }
    }

    // MARK: - Scrollback

    private var scrollback: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if chatManager.hasMoreMessages {
                        loadEarlierButton
                    }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if let day = daySeparator(at: index) {
                            dayDivider(day)
                        }

                        row(message, at: index)
                            .padding(.top, topGap(at: index))
                            .id(message.id)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .refreshable { await chatManager.refreshMessages() }
            // Keyed on the LAST message id, not on `count`. A realtime page can
            // replace the tail without changing the count, and the old
            // count-keyed watcher missed exactly that case.
            .onChange(of: messages.last?.id) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onTapGesture { isMessageFieldFocused = false }
        }
    }

    private var loadEarlierButton: some View {
        Button {
            Task { await chatManager.loadMoreMessages() }
        } label: {
            HStack(spacing: 6) {
                // Keyed on isLoadingMoreMessages, not messagesLoading. This
                // button read the INITIAL-load flag, which "Load earlier" never
                // sets — so tapping it showed nothing at all, while the initial
                // load spun it at the one moment it should have been still.
                if chatManager.isLoadingMoreMessages {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle").font(.caption)
                }
                Text("Load earlier messages").font(.caption)
            }
            .foregroundStyle(feature)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grouping rules (ported verbatim from the approved mockup)

    private func continuesRun(at index: Int) -> Bool {
        guard index > 0 else { return false }
        let previous = messages[index - 1]
        let current = messages[index]
        guard previous.type != .system, current.type != .system else { return false }
        guard previous.senderId == current.senderId else { return false }
        guard Calendar.current.isDate(previous.timestamp, inSameDayAs: current.timestamp) else { return false }
        return current.timestamp.timeIntervalSince(previous.timestamp) < 5 * 60
    }

    private func endsRun(at index: Int) -> Bool {
        guard index + 1 < messages.count else { return true }
        return !continuesRun(at: index + 1)
    }

    /// Named in groups only, and never for your own — the app's original rule.
    private func showsSender(at index: Int) -> Bool {
        let message = messages[index]
        guard message.type != .system else { return false }
        guard conversation?.type == .group else { return false }
        guard message.senderId != currentUserId else { return false }
        return !continuesRun(at: index)
    }

    /// A stamp only where the conversation actually paused.
    private func showsStamp(at index: Int) -> Bool { endsRun(at: index) }

    private func topGap(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        if daySeparator(at: index) != nil { return 0 }
        if messages[index].type == .system || messages[index - 1].type == .system { return 12 }
        return continuesRun(at: index) ? 2 : 8
    }

    private func daySeparator(at index: Int) -> String? {
        let current = messages[index].timestamp
        guard index > 0 else { return Formatters.relativeDay(current) }
        let previous = messages[index - 1].timestamp
        guard !Calendar.current.isDate(previous, inSameDayAs: current) else { return nil }
        return Formatters.relativeDay(current)
    }

    private func dayDivider(_ label: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
        .padding(.vertical, 14)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ message: ChatMessage, at index: Int) -> some View {
        if message.type == .system {
            systemRow(message, at: index)
        } else {
            bubbleRow(message, at: index)
        }
    }

    /// Centred, in a capsule, never in a bubble and never with a sender name.
    /// "X added Y to the group", "X removed Y", "X left the group".
    private func systemRow(_ message: ChatMessage, at index: Int) -> some View {
        VStack(spacing: 3) {
            Text(message.systemMessageText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                // ambient-allow: a system-message capsule is not a card — it is a
                // centred inline annotation, and AmbientCard is a rounded
                // rectangle by construction.
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))

            if showsStamp(at: index) {
                Text(Formatters.shortTime.string(from: message.timestamp))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bubbleRow(_ message: ChatMessage, at index: Int) -> some View {
        let mine = message.senderId == currentUserId

        return HStack {
            if mine { Spacer(minLength: 60) }

            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if showsSender(at: index), let senderName = message.senderName {
                    Text(senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AmbientStyle.avatarColor(senderName))
                        .padding(.leading, 4)
                }

                content(message, mine: mine)

                if showsStamp(at: index) {
                    Text(Formatters.shortTime.string(from: message.timestamp))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }

            if !mine { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private func content(_ message: ChatMessage, mine: Bool) -> some View {
        switch message.type {
        case .text:
            if isGifURL(message.text) {
                ChatAttachment(source: message.text) { url in
                    EnhancedGifMessageView(url: url, isOwnMessage: mine)
                }
            } else if isImageURL(message.text) {
                ChatAttachment(source: message.text) { url in
                    ChatImageView(url: url, isOwnMessage: mine)
                }
            } else {
                textBubble(message.text, mine: mine)
            }

        case .file:
            if let fileUrl = message.fileUrl {
                if isGifURL(fileUrl) {
                    ChatAttachment(source: fileUrl) { url in
                        EnhancedGifMessageView(url: url, isOwnMessage: mine)
                    }
                } else if isImageURL(fileUrl) {
                    ChatAttachment(source: fileUrl) { url in
                        ChatImageView(url: url, isOwnMessage: mine)
                    }
                } else {
                    fileBubble(message, mine: mine)
                }
            } else {
                textBubble(message.text, mine: mine)
            }

        case .system:
            Text(message.text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func textBubble(_ text: String, mine: Bool) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(mine ? AnyShapeStyle(.white) : AnyShapeStyle(Color.primary))
            .fixedSize(horizontal: false, vertical: true)
            .ambientCard(density: .bubble,
                         fill: mine ? .tint(bubbleTint) : .material,
                         border: mine ? .none : .hairline(Color.primary.opacity(0.08)))
    }

    private func fileBubble(_ message: ChatMessage, mine: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill").font(.footnote)
            VStack(alignment: .leading, spacing: 1) {
                Text("File").font(.caption.weight(.medium))
                if !message.text.isEmpty {
                    Text(message.text).font(.caption2).lineLimit(1)
                }
            }
        }
        .foregroundStyle(mine ? AnyShapeStyle(.white) : AnyShapeStyle(Color.primary))
        .ambientCard(density: .bubble,
                     fill: mine ? .tint(bubbleTint) : .material,
                     border: mine ? .none : .hairline(Color.primary.opacity(0.08)))
        // The old "Open" button is DELETED rather than restyled: its body was an
        // empty TODO. Drawing a button that does nothing is the dead control
        // AMB.3 spent a phase removing.
    }

    private func isGifURL(_ url: String) -> Bool {
        let lowered = url.lowercased()
        return lowered.contains(".gif")
            || lowered.contains("giphy.com")
            || lowered.contains("tenor.com")
            || lowered.contains("gfycat.com")
    }

    private func isImageURL(_ url: String) -> Bool {
        let lowered = url.lowercased()
        return lowered.contains(".jpg") || lowered.contains(".jpeg")
            || lowered.contains(".png") || lowered.contains(".webp")
            || lowered.contains("imgur.com")
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            if showEmojiPicker {
                EmojiPickerView(
                    onEmojiSelected: { messageText += $0 },
                    isPresented: $showEmojiPicker
                )
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                MessageInputAccessoryView(
                    showEmojiPicker: $showEmojiPicker,
                    showGifPicker: $showGifPicker,
                    showPhotoPicker: $showPhotoPicker,
                    onAttachmentTap: { showDocumentPicker = true }
                )
                .disabled(chatManager.isSendingMessage)

                TextField("Message", text: $messageText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
                    .focused($isMessageFieldFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    // ambient-allow: the composer field is a capsule input, not a card.
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                    // Gated like the send button. It was not, so the return key
                    // could start a second send while the first was in flight.
                    .onSubmit { if !chatManager.isSendingMessage { sendMessage() } }
                    .onChange(of: isMessageFieldFocused) { focused in
                        if focused { showEmojiPicker = false }
                    }

                Button(action: sendMessage) {
                    if chatManager.isSendingMessage {
                        ProgressView().scaleEffect(0.8).frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(messageText.isEmpty
                                             ? AnyShapeStyle(.tertiary)
                                             : AnyShapeStyle(bubbleTint))
                    }
                }
                .disabled(messageText.isEmpty || chatManager.isSendingMessage)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
        .animation(AmbientMotion.snappy, value: showEmojiPicker)
    }

    /// The message is IN this banner, so it cannot be lost. Retry re-sends it;
    /// the X discards it deliberately.
    private func failedMessageBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.arrow.circlepath")
                .font(.footnote)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not sent").font(.caption.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                failedMessage = nil
                chatManager.errorMessage = nil
                Task {
                    let sent = await chatManager.sendMessage(text: text)
                    if !sent { failedMessage = text }
                }
            } label: {
                Text("Retry").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(feature)

            Button { failedMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .ambientCard(density: .compact,
                     state: .highlighted,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    /// Dismissible, unlike the list's banner — here the user just watched their
    /// message vanish and needs to be told why, once.
    private func failureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                chatManager.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .ambientCard(density: .compact,
                     state: .highlighted,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 8) {
                ProgressView()
                Text("Uploading…").font(.caption).foregroundStyle(.secondary)
            }
            .ambientCard(density: .hero, state: .highlighted)
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isMessageFieldFocused = false

        // Cleared IMMEDIATELY so the next message can be typed while this one is in
        // flight, and a FAILED message is parked in its own state where nothing can
        // overwrite it.
        //
        // Three versions of this, and the first two both lost text. Clearing at
        // once let the failure path destroy the message. Clearing only on success
        // wiped anything typed during the flight. Restoring "only if the composer
        // is still empty" — the previous attempt — lost the message outright if the
        // user typed a single character or tapped one emoji while it was sending,
        // which is worse than where it started. The composer and the failed message
        // are now separate things, so neither can eat the other.
        messageText = ""

        Task {
            let sent = await chatManager.sendMessage(text: text)
            if !sent { failedMessage = text }
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        isUploadingMedia = true
        selectedPhotoItem = nil
        defer { isUploadingMedia = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let compressed = image.downsampledJPEGData(maxDimension: 2048, quality: 0.8) else {
                chatManager.errorMessage = "Couldn't read that photo."
                return
            }
            await chatManager.sendImageMessage(data: compressed)
        } catch {
            chatManager.errorMessage = "Couldn't read that photo: \(error.localizedDescription)"
        }
    }

    private func handleFileSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                isUploadingMedia = true
                defer { isUploadingMedia = false }

                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                do {
                    let data = try Data(contentsOf: url)
                    await chatManager.sendFileMessage(data: data, fileName: url.lastPathComponent)
                } catch {
                    chatManager.errorMessage = "Couldn't read that file: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            chatManager.errorMessage = "Couldn't pick that file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Attachment source resolution

/// Renders an attachment whose stored value may be EITHER an absolute URL or a
/// storage path.
///
/// Both exist by design. GIFs are posted as absolute Giphy URLs and always have
/// been; uploads added in AMB.6 store a PATH into a private bucket and are
/// signed at render time, so the row does not rot the way a baked one-year
/// signed URL does. This resolves whichever it is and hands a URL string down to
/// the existing image and GIF views.
struct ChatAttachment<Content: View>: View {
    let source: String
    @ViewBuilder let content: (String) -> Content

    @State private var resolved: String?
    @State private var failed = false

    var body: some View {
        Group {
            if let resolved {
                content(resolved)
            } else if failed {
                Label("Attachment unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .ambientCard(density: .bubble)
            } else {
                ProgressView()
                    .frame(width: 120, height: 90)
                    .task { await resolve() }
            }
        }
    }

    private func resolve() async {
        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            resolved = source
            return
        }

        do {
            let url = try await SupabaseChatService.shared.signedAttachmentURL(path: source)
            resolved = url.absoluteString
        } catch {
            print("❌ Could not sign chat attachment \(source): \(error)")
            failed = true
        }
    }
}
