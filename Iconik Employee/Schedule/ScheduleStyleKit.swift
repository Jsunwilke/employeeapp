//  ScheduleStyleKit.swift
//  Iconik Employee — what is genuinely about a shift
//
//  This file used to hold the whole Ambient vocabulary. In AMB.2 (2026-07-25)
//  everything that was not about shifts moved to DesignSystem/ — the card
//  container, badges, avatars, the flow layout, the wash, motion, haptics, the
//  deterministic identity colours and the iOS 16.6 wrappers — so that Equipment,
//  Tasks and Chat build from the same primitives instead of copying them.
//
//  What remains here is the part only the schedule can know: what colour a
//  session is, which icon a session type gets, how a shift's times read, and
//  where a shift sits relative to now.

import SwiftUI

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
        let hue = Double(AmbientStyle.stableHash(id) % 360) / 360
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

    // MARK: shift times

    static func timeRange(_ session: Session) -> String {
        guard let start = session.startDate else { return "Time TBD" }
        guard let end = session.endDate else { return Formatters.shortTime.string(from: start) }
        return "\(Formatters.shortTime.string(from: start)) – \(Formatters.shortTime.string(from: end))"
    }

    static func duration(_ session: Session) -> String? {
        guard let start = session.startDate, let end = session.endDate, end > start else { return nil }
        return Formatters.duration(end.timeIntervalSince(start))
    }

    // MARK: adapters

    /// Crew as design-system avatar subjects.
    static func avatarSubjects(_ crew: [SessionPhotographer]) -> [AmbientAvatarSubject] {
        crew.map { AmbientAvatarSubject(id: $0.id, name: $0.name) }
    }

    /// A session's types (plus its draft / multi-day markers) as pills.
    @MainActor
    static func pills(for session: Session, includeState: Bool = true) -> [AmbientPill] {
        var pills = session.sessionType.map { type in
            AmbientPill(id: type,
                        text: typeName(type, in: session),
                        systemImage: typeSymbol(type, in: session),
                        tint: typeColor(type))
        }
        guard includeState else { return pills }
        if let label = session.multiDayLabel {
            pills.append(AmbientPill(id: "multiDay", text: label,
                                     systemImage: "square.stack.3d.up.fill",
                                     tint: accent(for: session)))
        }
        if !session.isPublished {
            pills.append(AmbientPill(id: "draft", text: "Draft", systemImage: "pencil", tint: .orange))
        }
        return pills
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

    /// How a card carrying this shift should read.
    var cardState: AmbientCardState {
        switch self {
        case .past: return .receded
        case .live: return .highlighted
        case .upcoming: return .normal
        }
    }
}

// MARK: - Session-shaped components

/// Every session type on a job, plus its state markers, wrapped.
struct ScheduleTypePills: View {
    let session: Session
    var showState = true
    var density: AmbientDensity = .roomy

    var body: some View {
        AmbientPillRow(pills: ScheduleStyle.pills(for: session, includeState: showState),
                       density: density)
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
