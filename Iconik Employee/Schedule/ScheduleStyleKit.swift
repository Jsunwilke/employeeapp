//  ScheduleStyleKit.swift
//  Iconik Employee — the schedule's visual vocabulary
//
//  Promoted out of the design lab when Ambient was chosen (2026-07-24). This is
//  the single definition of how a shift looks: its colour, its icons, its pills,
//  its crew, its cards. The week view and the shift detail both build from here,
//  so they cannot drift apart the way the three copy-pasted colour maps did
//  before Phase 3.
//
//  Everything is iOS 16.6-safe. Post-16 APIs go through the wrappers at the
//  bottom, which apply the modern treatment on iOS 17+ and no-op below.

import SwiftUI
import UIKit

// MARK: - Style

enum ScheduleStyle {

    // MARK: colour

    /// A session's colour: the one the scheduler picked, else its type's colour.
    @MainActor
    static func accent(for session: Session) -> Color {
        if let hex = session.session_color, !hex.isEmpty { return Color(hex: hex) }
        if let first = session.sessionType.first { return typeColor(first) }
        return .blue
    }

    @MainActor
    static func accent(for entry: TimeOffCalendarEntry) -> Color {
        switch entry.status {
        case .pending, .underReview: return .blue
        case .approved: return entry.isPartialDay ? .orange : .gray
        case .denied, .cancelled: return .secondary
        }
    }

    /// The colours of a session's types. Multi-discipline jobs blend these, so a
    /// job that is underclass AND sports looks like two things at a glance.
    @MainActor
    static func typeColors(for session: Session) -> [Color] {
        let colors = session.sessionType.map { typeColor($0) }
        return colors.count > 1 ? colors : [accent(for: session)]
    }

    @MainActor
    static func accentGradient(for session: Session, fadeTo opacity: Double = 0.05) -> LinearGradient {
        let colors = typeColors(for: session)
        if colors.count == 1 {
            return LinearGradient(colors: [colors[0].opacity(0.45), colors[0].opacity(opacity)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: colors.map { $0.opacity(0.75) },
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @MainActor
    static func typeColor(_ id: String) -> Color {
        if let definition = OrganizationService.shared.getSessionType(by: id) {
            return Color(hex: definition.color)
        }
        let hue = Double(ScheduleStyle.stableHash(id) % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }

    // MARK: naming

    @MainActor
    static func typeName(_ id: String, in session: Session? = nil) -> String {
        if id == "other", let custom = session?.customSessionType, !custom.isEmpty { return custom }
        if let definition = OrganizationService.shared.getSessionType(by: id) { return definition.name }
        return id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    // MARK: icons

    /// Headline icon — the first type only. Use `symbols(for:)` where there's room.
    @MainActor
    static func symbol(for session: Session) -> String {
        symbols(for: session).first ?? "camera.fill"
    }

    /// One icon per type, duplicates collapsed.
    @MainActor
    static func symbols(for session: Session, limit: Int = 3) -> [String] {
        var seen: [String] = []
        for type in session.sessionType {
            let icon = typeSymbol(type, in: session)
            if !seen.contains(icon) { seen.append(icon) }
            if seen.count == limit { break }
        }
        return seen.isEmpty ? ["camera.fill"] : seen
    }

    /// Icon for ONE type. Session types are user-defined rows in the database
    /// (name + colour, no icon column), so this is keyword-derived from the
    /// display name. Unrecognised types fall back to the camera.
    @MainActor
    static func typeSymbol(_ id: String, in session: Session? = nil) -> String {
        let name = typeName(id, in: session).lowercased()
        if name.contains("sport") || name.contains("team") || name.contains("athlet") { return "figure.basketball" }
        if name.contains("grad") || name.contains("commencement") { return "graduationcap.fill" }
        if name.contains("yearbook") { return "book.closed.fill" }
        if name.contains("senior") { return "person.crop.square.fill" }
        if name.contains("underclass") || name.contains("student") { return "studentdesk" }
        if name.contains("class") || name.contains("group") { return "person.3.fill" }
        if name.contains("candid") { return "camera.viewfinder" }
        if name.contains("retake") || name.contains("makeup") || name.contains("make-up") { return "arrow.triangle.2.circlepath" }
        if name.contains("prom") || name.contains("dance") || name.contains("homecoming") { return "music.note" }
        if name.contains("deliver") { return "shippingbox.fill" }
        if name.contains("event") { return "sparkles" }
        return "camera.fill"
    }

    // MARK: formatting

    static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    static let weekdayShort: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    static let weekdayNarrow: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEEE"; return f }()
    static let weekdayFull: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE"; return f }()
    static let dayNumber: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d"; return f }()
    static let monthDay: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()
    static let monthYear: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f }()
    static let longDate: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none; return f
    }()

    static func timeRange(_ session: Session) -> String {
        guard let start = session.startDate else { return "Time TBD" }
        guard let end = session.endDate else { return time.string(from: start) }
        return "\(time.string(from: start)) – \(time.string(from: end))"
    }

    static func duration(_ session: Session) -> String? {
        guard let start = session.startDate, let end = session.endDate, end > start else { return nil }
        return durationString(end.timeIntervalSince(start))
    }

    static func durationString(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds.rounded() / 60)
        let hours = totalMinutes / 60, minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    static func relativeDayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return weekdayFull.string(from: date)
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    /// Deterministic avatar tint, so a person is the same colour everywhere —
    /// including across launches and between two devices looking at the same
    /// crew. `String.hashValue` is seeded per process, so it could not deliver
    /// that; this is a plain FNV-1a over the bytes.
    static func avatarColor(_ seed: String) -> Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .teal, .green, .orange, .mint]
        return palette[Int(stableHash(seed) % UInt64(palette.count))]
    }

    /// FNV-1a. Stable across processes and devices, and never negative — so no
    /// `abs()` trap on Int.min either.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Where a shift sits relative to now. Drives every past/live/future cue, so the
/// day header and the rows under it can never disagree.
enum ShiftStanding {
    case past, live, upcoming

    static func of(_ session: Session, now: Date = Date()) -> ShiftStanding {
        guard let start = session.startDate else { return .upcoming }
        let end = session.endDate ?? start
        if now > end { return .past }
        if now >= start { return .live }
        return .upcoming
    }
}

// MARK: - Motion & feedback

enum ScheduleMotion {
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let gentle = Animation.spring(response: 0.45, dampingFraction: 0.85)
    static let pop = Animation.spring(response: 0.35, dampingFraction: 0.7)
}

enum ScheduleHaptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Layout

/// Wrapping row (iOS 16 `Layout`). Session types are user-defined and a job can
/// carry several, so pills wrap rather than truncating at an arbitrary count.
struct ScheduleFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing; x = 0; lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing; x = bounds.minX; lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Components

/// State marker: draft, multi-day, time-off status, session type.
struct ScheduleBadge: View {
    let text: String
    var systemImage: String?
    var tint: Color = .orange

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .textCase(.uppercase)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.16)))
        .foregroundStyle(tint)
    }
}

/// Every session type on a job, plus its state markers, wrapped.
struct ScheduleTypePills: View {
    let session: Session
    var showState = true
    var compact = false

    var body: some View {
        ScheduleFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(session.sessionType, id: \.self) { type in
                ScheduleBadge(text: ScheduleStyle.typeName(type, in: session),
                              systemImage: compact ? nil : ScheduleStyle.typeSymbol(type, in: session),
                              tint: ScheduleStyle.typeColor(type))
            }
            if showState {
                if let label = session.multiDayLabel {
                    ScheduleBadge(text: label, systemImage: "square.stack.3d.up.fill",
                                  tint: ScheduleStyle.accent(for: session))
                }
                if !session.isPublished {
                    ScheduleBadge(text: "Draft", systemImage: "pencil", tint: .orange)
                }
            }
        }
    }
}

/// The icons for every discipline on a job, overlapped into one mark.
struct ScheduleTypeIcons: View {
    let session: Session
    var size: CGFloat = 22

    var body: some View {
        let icons = ScheduleStyle.symbols(for: session)
        let colors = ScheduleStyle.typeColors(for: session)
        return HStack(spacing: -size * 0.28) {
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                Image(systemName: icon)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(colors[min(index, colors.count - 1)].gradient))
                    .overlay(Circle().strokeBorder(Color(.systemBackground).opacity(0.85), lineWidth: 1.2))
                    .zIndex(Double(icons.count - index))
            }
        }
    }
}

/// Initials bubble with an optional remote photo.
struct ScheduleAvatar: View {
    let name: String
    var photoURL: String?
    var size: CGFloat = 36
    var ringColor: Color?

    var body: some View {
        ZStack {
            Circle().fill(ScheduleStyle.avatarColor(name).gradient)
            if let photoURL, !photoURL.isEmpty {
                AsyncImage(url: URL(string: photoURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsText
                }
                .clipShape(Circle())
            } else {
                initialsText
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if let ringColor { Circle().strokeBorder(ringColor, lineWidth: 2.5) }
        }
    }

    private var initialsText: some View {
        Text(ScheduleStyle.initials(name))
            .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }
}

/// Overlapping crew stack with a "+N" overflow chip.
struct ScheduleCrewStack: View {
    let crew: [SessionPhotographer]
    var size: CGFloat = 28
    var maxVisible: Int = 4

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(Array(crew.prefix(maxVisible).enumerated()), id: \.element.id) { _, person in
                ScheduleAvatar(name: person.name, size: size)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
            }
            if crew.count > maxVisible {
                Text("+\(crew.count - maxVisible)")
                    .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
            }
        }
    }
}

struct ScheduleSectionTitle: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing).font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct ScheduleNoteCard: View {
    let title: String
    let text: String
    var accent: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScheduleSectionTitle(title)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(accent).frame(width: 3).padding(.vertical, 16).padding(.leading, 1)
        }
    }
}

struct ScheduleStatTile: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ScheduleEmptyState: View {
    var title: String = "Nothing scheduled"
    var message: String = "This day is clear."
    var systemImage: String = "sun.horizon.fill"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

/// The ambient wash: two soft blooms of the session's colour behind the page.
struct ScheduleBackdrop: View {
    let tint: Color

    var body: some View {
        ZStack {
            Color(.systemBackground)
            Circle().fill(tint.opacity(0.55)).frame(width: 420, height: 420)
                .blur(radius: 120).offset(x: -110, y: -260)
            Circle().fill(tint.opacity(0.28)).frame(width: 360, height: 360)
                .blur(radius: 140).offset(x: 140, y: 120)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: tint)
    }
}

/// Rounded on the top corners only — for bars anchored to the bottom edge.
struct TopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                              control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                              control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - iOS 16.6-safe wrappers

extension View {
    /// Fades and shrinks cells as they leave the viewport (iOS 17+).
    @ViewBuilder
    func scheduleScrollFade(minOpacity: Double = 0.4, minScale: CGFloat = 0.92) -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTransition(.interactive) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : minOpacity)
                    .scaleEffect(phase.isIdentity ? 1 : minScale)
            }
        } else { self }
    }

    /// Snap-to-cell horizontal carousel with inset content (iOS 17+).
    @ViewBuilder
    func scheduleCarousel(margin: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, margin, for: .scrollContent)
        } else {
            self.padding(.horizontal, margin)
        }
    }

    @ViewBuilder
    func scheduleScrollTargets() -> some View {
        if #available(iOS 17.0, *) { self.scrollTargetLayout() } else { self }
    }

    @ViewBuilder
    func scheduleNoBounceWhenShort() -> some View {
        if #available(iOS 16.4, *) { self.scrollBounceBehavior(.basedOnSize) } else { self }
    }

    /// Stretch on over-scroll (iOS 17+).
    @ViewBuilder
    func scheduleParallax(_ amount: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.visualEffect { content, proxy in
                let y = proxy.frame(in: .scrollView).minY
                return content.offset(y: y > 0 ? -y * amount : 0)
            }
        } else { self }
    }

    /// Push an optional item.
    ///
    /// Uses `NavigationLink(isActive:)` — deprecated in iOS 16, but the ONLY
    /// push API that works in both containers. The app shell hands most features
    /// a `NavigationView` (MainEmployeeView.featureContainer, per NAV.1's one bar
    /// per screen), and `navigationDestination` is a `NavigationStack`-only
    /// modifier: inside a `NavigationView` it is silently ignored, so the tap
    /// registers and nothing happens. That is exactly the bug this replaced.
    /// SlingWeeklyView used this same pattern, which is why it worked.
    func schedulePush<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        background(
            NavigationLink(
                isActive: Binding(
                    get: { item.wrappedValue != nil },
                    set: { if !$0 { item.wrappedValue = nil } }
                ),
                destination: {
                    if let value = item.wrappedValue { destination(value) }
                },
                label: { EmptyView() }
            )
            .hidden()
        )
    }
}
