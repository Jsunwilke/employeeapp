//  ChatMockup.swift
//  Iconik Employee — AMB.6's mockup
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  A REDESIGN under D12, with the parity list in AMB_BATCH1_PARITY.md.
//
//  THE THREE LEVERS ON SCROLLBACK HEIGHT, all live in the thread:
//      1. THE PER-MESSAGE TIMESTAMP. Every message in the app carries a
//         .caption2 line under it. Nothing else costs as much height for as
//         little. The alternative: a timestamp only when the conversation
//         actually paused.
//      2. GROUPING. The app has none, so a run of four messages from one person
//         repeats their name and takes the full gap four times.
//      3. THE BODY FONT. A message has NO font modifier at all, so it rides on
//         the 17pt default while its own timestamp is 11pt.
//
//      Grouping and date separators are presentation — the data does not change
//      — so they are inside D12 comfortably. Read receipts, typing indicators
//      and thread avatars are genuinely absent from the feature and are NOT
//      proposed: that would be new work wearing a redesign's clothes.
//
//  WHOSE COLOUR "MINE" IS stayed a question rather than a decision, so it is a
//  switch. Chat's feature colour is #D6409F and under D11 that is also the wash
//  behind the thread, so a pink bubble on a pink wash may be mush. The company
//  blue says "you" without competing with the screen's own colour.
//
//  WHAT THE PARITY PASS CAUGHT IN THE FIRST CUT OF THIS MOCKUP:
//      SYSTEM MESSAGES were missing entirely. The app renders three of them —
//      "X added Y to the group", "X removed Y from the group", "X left the
//      group" — centred in a capsule with their own timestamp. There is one in
//      the thread below now. Also missing: the "No messages yet" row, and the
//      fact that swipe-to-delete exists for GROUPS ONLY.
//
//  THE CARD PRIMITIVE CANNOT DRAW A BUBBLE, and that is expected — the lab's
//  charter is to prototype treatments the primitive cannot express yet.
//  `ambientCard` fills with a material, never a solid tint. If bubbles survive
//  review, a tinted fill gets promoted INTO AmbientCard before AMB.6 converts a
//  single real screen; it does not get hand-rolled in Chat/.

import SwiftUI

struct ChatMockup: View {

    @State private var wash: Double = 1
    @State private var pushed: LabConversation?
    @State private var query = ""

    private var feature: Color { FeatureTheme.color(for: "chat") }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AmbientBackdrop(tint: feature, intensity: wash)

            VStack(spacing: 10) {
                searchField.padding(.horizontal, 16)

                // A LIST, not a LazyVStack — and that is load-bearing, not a
                // style preference. `.swipeActions` is a List-only modifier: on
                // a row inside a LazyVStack it compiles, renders, and silently
                // does nothing. Pin and delete are real capabilities here, so
                // building this out of a stack would have shipped the operator a
                // mockup whose swipes were dead — the same class of bug as
                // AMB.1's dead tap, which is the reason the lab exists at all.
                //
                // The cost is having to strip List's own chrome so the ambient
                // wash shows through: hidden scroll background, clear row
                // backgrounds, no separators, and the insets set by hand.
                List {
                    labStrip.modifier(LabChatListRow())

                    if visible.isEmpty {
                        AmbientEmptyState(
                            title: query.isEmpty ? "No conversations" : "Nothing found",
                            message: query.isEmpty
                                ? "Start a conversation with your team members."
                                : "Nothing matches “\(query)”.",
                            systemImage: "bubble.left.and.bubble.right")
                            .modifier(LabChatListRow())
                    } else {
                        ForEach(visible) { conversation in
                            LabConversationRow(conversation: conversation)
                                .contentShape(Rectangle())
                                .onTapGesture { pushed = conversation }
                                .modifier(LabChatListRow())
                        }
                    }

                    Color.clear
                        .frame(height: 80)
                        .modifier(LabChatListRow())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
            }
            .padding(.top, 8)

            newConversationButton
        }
        .ambientPush(item: $pushed) { conversation in
            ChatThreadMockup(conversation: conversation, feature: feature, wash: wash)
        }
    }

    /// Pinned first — the app's ordering.
    private var visible: [LabConversation] {
        let matching = DesignLabSampleData.conversations.filter { conversation in
            guard !query.isEmpty else { return true }
            let needle = query.lowercased()
            return conversation.name.lowercased().contains(needle)
                || conversation.preview.lowercased().contains(needle)
        }
        return matching.filter(\.pinned) + matching.filter { !$0.pinned }
    }

    private var labStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(feature).frame(width: 12, height: 12)
                Text("Chat wash").font(.footnote.weight(.semibold))
                Spacer()
                Text(wash == 0 ? "off" : "\(Int(wash * 100))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $wash, in: 0...1).tint(feature)
            Text("Open the pinned group at the top — that is the thread the density question is decided on, and the switches that matter are inside it. Swipe a row for pin; swipe a GROUP for delete (a direct message cannot be swiped away, which is deliberate).")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, border: .dashed(Color.primary.opacity(0.25)), fillWidth: true)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Search conversations", text: $query)
                .font(.subheadline).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    /// The app puts this in the nav bar as square.and.pencil. Kept as an
    /// explicit affordance here because the lab's mockups have no nav bar of
    /// their own to hang it in.
    private var newConversationButton: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(Circle().fill(feature))
            .shadow(color: feature.opacity(0.45), radius: 10, y: 5)
            .padding(.trailing, 20)
            .padding(.bottom, 92)
    }
}

/// Strips a List row back to nothing so the ambient wash shows through and the
/// cards supply all the spacing — while keeping the row a real List row, which
/// is what makes `.swipeActions` work.
private struct LabChatListRow: ViewModifier {
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

/// Everything ConversationRow carries: hashed-colour avatar, name bold when
/// unread, a two-line preview with the "You: " prefix and emoji-typed media
/// previews, a relative time, an unread pill and the pinned treatment.
///
/// Two deliberate changes:
///   - the avatar is 44 rather than 50, which is where the row's height goes
///   - pinned is an orange hairline rather than a 10% orange wash over the whole
///     row: under D11 the page already carries a colour, and a second full-row
///     tint on top of it reads as a rendering fault rather than as emphasis
struct LabConversationRow: View {
    let conversation: LabConversation
    var density: AmbientDensity = .compact

    private var unread: Bool { conversation.unread > 0 }

    var body: some View {
        HStack(spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: density.contentSpacing) {
                HStack(spacing: 5) {
                    if conversation.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9)).foregroundStyle(.orange)
                    }
                    Text(conversation.name)
                        .font(unread ? density.titleFont.weight(.bold) : density.titleFont)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(conversation.time)
                        .font(.caption2)
                        .foregroundStyle(unread ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.tertiary))
                }

                HStack(alignment: .top, spacing: 8) {
                    if conversation.hasMessages {
                        Text(conversation.previewText)
                            .font(density.subtitleFont)
                            .foregroundStyle(unread ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        // The app's own wording and its italic.
                        Text("No messages yet")
                            .font(density.subtitleFont)
                            .foregroundStyle(.secondary)
                            .italic()
                    }

                    Spacer(minLength: 0)

                    if unread {
                        Text("\(conversation.unread)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 19, minHeight: 19)
                            .background(Capsule().fill(AmbientStyle.brand))
                    }
                }
            }
        }
        .ambientCard(density: density,
                     border: .hairline(conversation.pinned
                                       ? Color.orange.opacity(0.45)
                                       : Color.primary.opacity(0.08)))
        // Pin on the leading edge; delete on the trailing edge for GROUPS ONLY.
        // A direct message cannot be swiped away in the app and that asymmetry
        // is kept.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { } label: {
                Label(conversation.pinned ? "Unpin" : "Pin",
                      systemImage: conversation.pinned ? "pin.slash" : "pin")
            }
            .tint(conversation.pinned ? .gray : .orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if conversation.isGroup {
                Button(role: .destructive) { } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var avatar: some View {
        Group {
            if conversation.isGroup {
                ZStack {
                    // Seeded from the conversation id, as the app does — but
                    // through AmbientStyle.stableHash rather than hashValue,
                    // which is seeded per process and gives a person a
                    // different colour after every relaunch.
                    Circle().fill(AmbientStyle.avatarColor(conversation.id).gradient)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 15)).foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            } else {
                AmbientAvatar(name: conversation.name, size: 44)
            }
        }
    }
}

// MARK: - The thread

struct ChatThreadMockup: View {
    let conversation: LabConversation
    let feature: Color
    let wash: Double

    private enum Stamps: String, CaseIterable {
        case everyMessage = "Every message"
        case whenItPauses = "When it pauses"
    }

    private enum MineTint: String, CaseIterable {
        case brand = "Company blue"
        case feature = "Chat pink"
    }

    @State private var stamps: Stamps = .whenItPauses
    @State private var grouped = true
    @State private var mineTint: MineTint = .brand
    @State private var draft = ""
    @State private var showControls = true
    @State private var showAttachments = false

    private var bubbleTint: Color {
        mineTint == .brand ? AmbientStyle.brand : feature
    }

    private var messages: [LabMessage] { DesignLabSampleData.thread }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: wash)

            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if showControls { controls.padding(.bottom, 12) }

                        loadEarlier

                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            if let separator = daySeparator(at: index) {
                                dayDivider(separator)
                            }
                            row(message, at: index)
                                .padding(.top, topGap(at: index))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }

                composer
            }
        }
        .navigationTitle(conversation.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        withAnimation(AmbientMotion.snappy) { showControls.toggle() }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    // The app's overflow: Conversation Settings, View Profile
                    // (direct conversations only, and a TODO), Refresh Messages.
                    Menu {
                        Button { } label: { Label("Conversation settings", systemImage: "gear") }
                        if !conversation.isGroup {
                            Button { } label: { Label("View profile", systemImage: "person.circle") }
                        }
                        Button { } label: { Label("Refresh messages", systemImage: "arrow.clockwise") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - Lab chrome

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The three levers on scrollback height")
                .font(.footnote.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Timestamps").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                Picker("Timestamps", selection: $stamps) {
                    ForEach(Stamps.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("“Every message” is what ships today — a caption line under all sixteen of these.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("My bubble").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                Picker("My bubble", selection: $mineTint) {
                    ForEach(MineTint.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Chat's own colour is already the wash behind this thread. Pink on pink may be mush — turn the wash up and check.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $grouped.animation(AmbientMotion.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Group a run from one person").font(.footnote.weight(.semibold))
                    Text("Off is today: the name repeats and every message gets the full gap.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(feature)

            Text("Hide this strip with the slider button top-right to judge the scrollback clean.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact, border: .dashed(Color.primary.opacity(0.25)), fillWidth: true)
    }

    /// Kept: the app pages older messages behind this button, with a spinner.
    private var loadEarlier: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.circle").font(.caption)
            Text("Load earlier messages").font(.caption)
        }
        .foregroundStyle(feature)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // MARK: - Grouping rules

    private func continuesRun(at index: Int) -> Bool {
        guard grouped, index > 0 else { return false }
        let previous = messages[index - 1]
        let current = messages[index]
        // A system message never joins a run in either direction.
        guard previous.kind != .system, current.kind != .system else { return false }
        guard previous.sender == current.sender else { return false }
        guard Calendar.current.isDate(previous.sentAt, inSameDayAs: current.sentAt) else { return false }
        return current.sentAt.timeIntervalSince(previous.sentAt) < 5 * 60
    }

    private func endsRun(at index: Int) -> Bool {
        guard index + 1 < messages.count else { return true }
        return !continuesRun(at: index + 1)
    }

    private func showsSender(at index: Int) -> Bool {
        let message = messages[index]
        guard message.kind != .system else { return false }
        // Named in groups only, and never for your own — the app's rule.
        guard conversation.isGroup, !message.mine else { return false }
        return !continuesRun(at: index)
    }

    private func showsStamp(at index: Int) -> Bool {
        switch stamps {
        case .everyMessage: return true
        case .whenItPauses: return endsRun(at: index)
        }
    }

    private func topGap(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        if daySeparator(at: index) != nil { return 0 }
        if messages[index].kind == .system || messages[index - 1].kind == .system { return 12 }
        return continuesRun(at: index) ? 2 : 8
    }

    private func daySeparator(at index: Int) -> String? {
        let current = messages[index].sentAt
        guard index > 0 else { return Formatters.relativeDay(current) }
        let previous = messages[index - 1].sentAt
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
    private func row(_ message: LabMessage, at index: Int) -> some View {
        if message.kind == .system {
            systemRow(message, at: index)
        } else {
            bubbleRow(message, at: index)
        }
    }

    /// Centred, in a capsule, never in a bubble and never with a sender name.
    /// "X added Y to the group", "X removed Y", "X left the group".
    private func systemRow(_ message: LabMessage, at index: Int) -> some View {
        VStack(spacing: 3) {
            Text(message.text ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
            if showsStamp(at: index) {
                Text(Formatters.shortTime.string(from: message.sentAt))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bubbleRow(_ message: LabMessage, at index: Int) -> some View {
        HStack {
            if message.mine { Spacer(minLength: 60) }

            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if showsSender(at: index) {
                    Text(message.sender)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AmbientStyle.avatarColor(message.sender))
                        .padding(.leading, 4)
                }

                content(message)

                if showsStamp(at: index) {
                    Text(Formatters.shortTime.string(from: message.sentAt))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }

            if !message.mine { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private func content(_ message: LabMessage) -> some View {
        switch message.kind {
        case .text, .link, .system:
            LabChatBubble(mine: message.mine, tint: bubbleTint) {
                Text(message.text ?? "")
                    // 15pt, against the 17pt default the app rides on. The
                    // cheapest of the three levers.
                    .font(.system(size: 15))
                    .foregroundStyle(message.mine ? AnyShapeStyle(.white) : AnyShapeStyle(Color.primary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .gif:
            media(label: "GIF", systemImage: "photo.stack.fill", width: 200, height: 140)
        case .image:
            media(label: "Photo", systemImage: "photo.fill", width: 220, height: 165)
        case .file:
            // The app shows the literal word "File" plus an Open button that is
            // a TODO. Kept, because pretending it opens would be a lie.
            LabChatBubble(mine: message.mine, tint: bubbleTint) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill").font(.footnote)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("File").font(.caption.weight(.medium))
                        Text(message.text ?? "").font(.caption2).lineLimit(1)
                    }
                }
                .foregroundStyle(message.mine ? AnyShapeStyle(.white) : AnyShapeStyle(Color.primary))
            }
        }
    }

    /// A placeholder, not a real asset. Sized to a sensible aspect rather than
    /// the fixed 250×250 every GIF gets today regardless of its real shape.
    /// Tapping opens full screen in the app — that viewer is live, not dead code.
    private func media(label: String, systemImage: String,
                       width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                    Text(label).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            if showAttachments {
                HStack(spacing: 18) {
                    attachmentButton("Photo", "photo.on.rectangle.angled")
                    attachmentButton("GIF", "photo.stack.fill")
                    attachmentButton("File", "paperclip")
                    attachmentButton("Emoji", "face.smiling")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(AmbientMotion.snappy) { showAttachments.toggle() }
                } label: {
                    Image(systemName: showAttachments ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 26)).foregroundStyle(feature)
                }
                .buttonStyle(.plain)

                TextField("Message", text: $draft, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))

                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(draft.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(bubbleTint))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
    }

    private func attachmentButton(_ label: String, _ symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(feature)
                .frame(width: 42, height: 42)
                .background(Circle().fill(feature.opacity(0.12)))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - The one thing the card primitive cannot draw yet

/// A message bubble.
///
/// `ambientCard` fills with a material and takes its radius from a density — a
/// bubble needs a SOLID tint for "mine" and 16pt on both. That is a gap in the
/// primitive, not a licence to hand-roll: if bubbles survive review, the tinted
/// fill is promoted INTO AmbientCard and Chat's conversion calls it. This type
/// exists so the gap is visible and named rather than discovered halfway
/// through AMB.6.
///
/// ambient-allow: a bubble is not a card; it is the treatment AMB.6 must promote
/// into AmbientCard before any real Chat screen is converted.
struct LabChatBubble<Content: View>: View {
    let mine: Bool
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if mine {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                }
            }
            .overlay {
                if !mine {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
            }
    }
}
