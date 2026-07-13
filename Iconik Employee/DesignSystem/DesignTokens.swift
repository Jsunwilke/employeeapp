//  DesignTokens.swift
//  Shared design tokens — one source of truth for feature colors, cached date
//  formatters, and the card container style. Introduced in Phase 3 of the audit
//  roadmap to replace three diverging feature-color maps, 200+ ad-hoc
//  `DateFormatter()` allocations, and dozens of copy-pasted card modifiers.

import SwiftUI
import UIKit

// MARK: - Feature colors

/// The single source of truth for the accent color of each feature tile/row.
///
/// Previously this switch was copy-pasted (and had drifted) in three places:
/// `MainEmployeeView`, `AllFeaturesView`, and `BottomTabBar` — e.g. the daily
/// job report was blue in two and green in the third. Those call sites now all
/// delegate here so a feature has exactly one color app-wide.
enum FeatureTheme {
    static func color(for id: String) -> Color {
        switch id {
        case "timeTracking": return .cyan
        case "photoshootNotes": return .purple
        case "dailyJobReport": return .blue
        case "customDailyReports": return .mint
        case "myDailyJobReports": return .green
        case "mileageReports": return .orange
        case "schedule": return .red
        case "locationPhotos": return .pink
        case "capture": return .blue
        case "sportsShoot": return .indigo
        case "focalPointSports": return .mint
        case "yearbookChecklists": return .purple
        case "classGroups": return .teal
        case "training": return .yellow
        case "chat": return .blue
        case "scan": return .orange
        case "flagUser": return .red
        case "unflagUser": return .green
        case "managerMileage": return .blue
        case "stats": return .indigo
        case "galleryCreator": return .green
        case "jobBoxTracker": return .teal
        case "equipment": return .cyan
        case "tasks": return .blue
        case "routePlanner": return .green
        case "timeOffRequests": return .teal
        case "timeOffApprovals": return .teal
        default: return .gray
        }
    }
}

// MARK: - Cached date formatters

/// Cached, correctly-configured `DateFormatter`s.
///
/// `DateFormatter()` is expensive to allocate and the app was creating 200+ of
/// them inline, many without a fixed locale — which makes fixed-format parsing
/// ("yyyy-MM-dd") break under non-Gregorian device calendars. All fixed-format
/// formatters here pin `en_US_POSIX`. Formatters are not thread-safe to mutate,
/// but reading a fully-configured one from multiple threads is safe, so these
/// are created once and shared.
enum Formatters {
    /// "yyyy-MM-dd" — the app's canonical day key (session/report dates). POSIX
    /// locale so it's calendar-independent. Uses the device time zone; pass a
    /// specific zone with `isoDate(in:)` when an org-timezone day boundary matters.
    static let isoDate: DateFormatter = fixed("yyyy-MM-dd")

    /// "yyyy-MM-dd'T'HH:mm:ss" local wall-clock timestamp (no zone designator).
    static let isoDateTime: DateFormatter = fixed("yyyy-MM-dd'T'HH:mm:ss")

    /// "HH:mm" 24-hour time-of-day (session start/end).
    static let time24: DateFormatter = fixed("HH:mm")

    /// Medium user-facing date (e.g. "Jul 12, 2026"), device locale/zone.
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// A POSIX "yyyy-MM-dd" formatter bound to a specific time zone. Cached per
    /// zone identifier so org-timezone day-boundary conversions don't re-allocate.
    static func isoDate(in timeZone: TimeZone) -> DateFormatter {
        if let cached = zonedISODate[timeZone.identifier] { return cached }
        let f = fixed("yyyy-MM-dd")
        f.timeZone = timeZone
        zonedISODate[timeZone.identifier] = f
        return f
    }

    // MARK: private

    private static var zonedISODate: [String: DateFormatter] = [:]

    private static func fixed(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}

// MARK: - Card container style

/// The app's standard card container: padded, rounded, subtly shadowed on the
/// system background. Replaces dozens of hand-rolled
/// `.padding().background(RoundedRectangle(cornerRadius: 12)).shadow(...)` stacks.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

extension View {
    /// Wrap content in the standard app card container. See `CardStyle`.
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = 12) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}
