//  ChatMockup.swift
//  Iconik Employee — AMB.6's mockup
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  THE HARDEST TEST OF COMPACT, and the plan names it as one of the two
//  surfaces that gets variants rather than a single proposal.
//
//  WHAT MAKES A SCROLLBACK DENSE OR NOT — three levers, all of them live here:
//
//      1. THE PER-MESSAGE TIMESTAMP. Every single message in the app carries a
//         .caption2 line under it. Nothing else in the thread costs as much
//         height for as little. The switch offers the alternative: a timestamp
//         only when the conversation actually paused.
//      2. GROUPING. The app has none — consecutive messages from the same
//         person repeat the sender name and get the full gap, so a run of four
//         reads as four separate arrivals.
//      3. THE BODY FONT. The message body has no font modifier at all, so it
//         rides on the default .body at 17pt while its own timestamp is 11pt.
//
//      Grouping and date separators are PRESENTATION — nothing about the data
//      changes — so they are inside a restyle. Read receipts, typing indicators
//      and thread avatars are all genuinely absent from the feature and are NOT
//      proposed here; adding them would be new work wearing a restyle's clothes.
//
//  MY BUBBLE'S COLOUR IS AN OPEN QUESTION, so it is a switch rather than a
//  decision. Chat's feature colour is #D6409F, and under D11 that is also the
//  wash behind the whole thread — a pink bubble on a pink wash may read as mush.
//  The alternative is the company blue, which says "you" without competing with
//  the screen's own colour. Flip it on the device; that is the only way to know.
//
//  THE CARD PRIMITIVE CANNOT DRAW A BUBBLE YET, and that is expected: the lab's
//  job is to prototype a treatment the primitive cannot express, and `ambientCard`
//  fills with a material, never a solid tint. If bubbles survive review, a tinted
//  fill gets promoted INTO AmbientCard before AMB.6 converts a single real screen
//  — it does not get hand-rolled in Chat/. The conversation LIST rows below go
//  through `.ambientCard` normally, because those are ordinary cards.

import SwiftUI

struct ChatMockup: View {

    @State private var wash: Double = 1
    @State private var pushed: LabConversation?
    @State private var query = ""

    private var feature: Color { FeatureTheme.color(for: "chat") }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: wash)

            VStack(spacing: 10) {
                searchField.padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                        labStrip.padding(.bottom, 4)

                        if visible.isEmpty {
                            AmbientEmptyState(
                                title: "No conversations",
                                message: "Nothing matches “\(query)”.",
                                systemImage: "bubble.left.and.bubble.right")
                        } else {
                            ForEach(visible) { conversation in
                                Button { pushed = conversation } label: {
                                    LabConversationRow(conversation: conversation)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
            }
            .padding(.top, 8)
        }
        .ambientPush(item: $pushed) { conversation in
            ChatThreadMockup(conversation: conversation, feature: feature, wash: wash)
        }
    }

    /// Pinned first, which is what the real list does.
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
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $wash, in: 0...1).tint(feature)
            Text("Open the pinned group at the top — that is the thread the density question is decided on, and the switches that matter are inside it. The wash you set here carries through.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, border: .dashed(Color.primary.opacity(0.25)), fillWidth: true)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search conversations", text: $query)
                .font(.subheadline)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

// MARK: - Conversation row

/// The list row at compact. Everything the real row carries: the hashed-colour
/// avatar, the name in bold when unread, a two-line preview with the "You: "
/// prefix and emoji-typed media previews, a relative timestamp, an unread pill,
/// and the pinned treatment.
///
/// Two changes from today, both deliberate:
///   - the avatar is 44 rather than 50, which is where the row's height goes;
///   - pinned is an orange hairline and a pin glyph rather than a 10% orange
///     wash across the whole row, because under D11 the page already carries a
///     colour and a second full-row tint on top of it reads as a rendering bug.
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
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
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
                    Text(conversation.previewText)
                        .font(density.subtitleFont)
                        .foregroundStyle(unread ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

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
                     state: .normal,
                     border: .hairline(conversation.pinned
                                       ? Color.orange.opacity(0.45)
                                       : Color.primary.opacity(0.08)))
    }

    private var avatar: some View {
        Group {
            if conversation.isGroup {
                ZStack {
                    Circle().fill(AmbientStyle.avatarColor(conversation.id).gradient)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
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

    /// Lever 1. `everyMessage` is what ships today.
    private enum Stamps: String, CaseIterable {
        case everyMessage = "Every message"
        case whenItPauses = "When it pauses"
    }

    /// Lever 3 — whose colour "mine" is. A genuinely open question, so it is a
    /// switch rather than a decision made on the operator's behalf.
    private enum MineTint: String, CaseIterable {
        case brand = "Company blue"
        case feature = "Chat pink"
    }

    @State private var stamps: Stamps = .whenItPauses
    @State private var grouped = true
    @State private var mineTint: MineTint = .brand
    @State private var draft = ""
    @State private var showControls = true

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

                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            if let separator = daySeparator(at: index) {
                                dayDivider(separator)
                            }
                            bubble(message, at: index)
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
                Button {
                    withAnimation(AmbientMotion.snappy) { showControls.toggle() }
                } label: {
                    Image(systemName: showControls ? "slider.horizontal.3" : "slider.horizontal.below.rectangle")
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
                Text("“Every message” is what ships today — a caption line under all fifteen of these.")
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

            Text("Hide this strip with the button top-right to judge the scrollback clean.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact, border: .dashed(Color.primary.opacity(0.25)), fillWidth: true)
    }

    // MARK: - Grouping rules

    /// True when this message continues a run: same sender, same day, and close
    /// enough in time that it reads as one turn rather than two.
    private func continuesRun(at index: Int) -> Bool {
        guard grouped, index > 0 else { return false }
        let previous = messages[index - 1]
        let current = messages[index]
        guard previous.sender == current.sender else { return false }
        guard Calendar.current.isDate(previous.sentAt, inSameDayAs: current.sentAt) else { return false }
        return current.sentAt.timeIntervalSince(previous.sentAt) < 5 * 60
    }

    /// The last message of a run — the one that carries the timestamp when
    /// stamps are set to "when it pauses".
    private func endsRun(at index: Int) -> Bool {
        guard index + 1 < messages.count else { return true }
        return !continuesRun(at: index + 1)
    }

    private func showsSender(at index: Int) -> Bool {
        // 1:1 threads never name the sender; the app names them in groups only.
        guard conversation.isGroup, !messages[index].mine else { return false }
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
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
        .padding(.vertical, 14)
    }

    // MARK: - Bubbles

    private func bubble(_ message: LabMessage, at index: Int) -> some View {
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
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }

            if !message.mine { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private func content(_ message: LabMessage) -> some View {
        switch message.kind {
        case .text, .link, .file:
            LabChatBubble(mine: message.mine, tint: bubbleTint) {
                Text(message.text ?? "")
                    // 15pt, not the default 17pt the app rides on. This is the
                    // third lever, and the cheapest of the three.
                    .font(.system(size: 15))
                    .foregroundStyle(message.mine ? AnyShapeStyle(.white) : AnyShapeStyle(Color.primary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .gif:
            media(label: "GIF", systemImage: "photo.stack.fill", width: 200, height: 140)
        case .image:
            media(label: "Photo", systemImage: "photo.fill", width: 220, height: 165)
        }
    }

    /// A placeholder, not a real asset. Sized to a sensible aspect rather than
    /// the fixed 250×250 every GIF gets today regardless of its real shape —
    /// worth seeing, because that squaring is visible in the app.
    private func media(label: String, systemImage: String,
                       width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(label).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(feature)

            HStack(spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))

            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(draft.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(bubbleTint))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
    }
}

// MARK: - The one thing the card primitive cannot draw yet

/// A message bubble.
///
/// `ambientCard` fills with a material and takes its radius from a density —
/// a bubble needs a SOLID tint for "mine" and a 16pt radius on both. That is a
/// gap in the primitive, not a licence to hand-roll: if bubbles survive review,
/// a tinted fill is promoted INTO AmbientCard and Chat's conversion calls it,
/// exactly as the lab's charter says. This type exists so the gap is visible
/// and named rather than discovered halfway through AMB.6.
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
