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
/// RE-CUT IN AMB.2 (operator approved 2026-07-25) so that all 27 features are
/// distinct. The previous map had 27 features sharing 11 colours — five of them
/// blue — which was survivable while this only tinted a tile, and is not
/// survivable now: under D11 a feature's colour becomes the WASH behind its
/// whole screen, so two features sharing a colour are two screens you cannot
/// tell apart.
///
/// Arranged as ten families: hues adjacent inside a family so a group reads as
/// a group, families far apart so a wash is unmistakable. Manager tools are
/// deliberately desaturated — they are not daily photographer work, and the
/// palette can say so without a label.
///
/// The schedule keeps its own data-driven wash (the colour of the job in front
/// of you) — the schedule entry here still tints its TILE and its bottom-bar
/// item, which is what this map is for.
enum FeatureTheme {
    static func color(for id: String) -> Color {
        switch id {
        // Planning
        case "schedule": return Color(hex: "#E5484D")
        case "flagUser": return Color(hex: "#C62A2F")
        // On the road
        case "routePlanner": return Color(hex: "#F76B15")
        case "mileageReports": return Color(hex: "#E8830C")
        // Shoot day
        case "capture": return Color(hex: "#F5B70A")
        case "sportsShoot": return Color(hex: "#C9A227")
        case "focalPointSports": return Color(hex: "#A3B818")
        // Groups & delivery
        case "classGroups": return Color(hex: "#46A758")
        case "yearbookChecklists": return Color(hex: "#2E9B4F")
        case "galleryCreator": return Color(hex: "#3DB88B")
        // Time & pay
        case "timeTracking": return Color(hex: "#12A594")
        case "timeOffRequests": return Color(hex: "#0D9B8A")
        case "timeOffApprovals": return Color(hex: "#0C8577")
        // Gear
        case "equipment": return Color(hex: "#00A2C7")
        case "jobBoxTracker": return Color(hex: "#0B8BA8")
        case "scan": return Color(hex: "#2AA7D8")
        // Paperwork
        case "dailyJobReport": return Color(hex: "#3E63DD")
        case "customDailyReports": return Color(hex: "#5471E0")
        case "myDailyJobReports": return Color(hex: "#7189E8")
        // Notes & photos
        case "photoshootNotes": return Color(hex: "#6E56CF")
        case "locationPhotos": return Color(hex: "#8E4EC6")
        // People
        case "chat": return Color(hex: "#D6409F")
        case "tasks": return Color(hex: "#E93D82")
        case "training": return Color(hex: "#C43B6D")
        // Manager tools — deliberately desaturated
        case "stats": return Color(hex: "#7A7FA6")
        case "unflagUser": return Color(hex: "#5F8A6E")
        case "managerMileage": return Color(hex: "#8A7A5F")
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

    // MARK: display formatters

    /// These are for text a person reads, so unlike the fixed-format formatters
    /// above they deliberately use the DEVICE locale and calendar — a 24-hour
    /// device shows 24-hour times. Never parse with these; never persist their
    /// output. Moved here from ScheduleStyle in AMB.2, which had grown a second
    /// formatter cache beside this one.

    /// Time of day, e.g. "9:41 AM".
    static let shortTime: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    /// "Mon"
    static let weekdayShort: DateFormatter = display("EEE")
    /// "M"
    static let weekdayNarrow: DateFormatter = display("EEEEE")
    /// "Monday"
    static let weekdayFull: DateFormatter = display("EEEE")
    /// "7"
    static let dayNumber: DateFormatter = display("d")
    /// "Jul 25"
    static let monthDay: DateFormatter = display("MMM d")
    /// "July 2026"
    static let monthYear: DateFormatter = display("MMMM yyyy")
    /// "Saturday, July 25, 2026"
    static let longDate: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none; return f
    }()

    /// "Today" / "Tomorrow" / "Yesterday", else the weekday name.
    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return weekdayFull.string(from: date)
    }

    /// "6h 30m" / "45m" / "3h".
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds.rounded() / 60)
        let hours = totalMinutes / 60, minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    // MARK: private

    private static var zonedISODate: [String: DateFormatter] = [:]

    /// Fixed-format: pins `en_US_POSIX` so parsing is calendar-independent.
    private static func fixed(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    /// Display-format: device locale and time zone, no POSIX pin. Carried over
    /// verbatim from ScheduleStyle in AMB.2 — a restyle phase does not get to
    /// change what a date says, so these keep the plain `dateFormat` assignment
    /// the schedule shipped with rather than switching to a localized template.
    private static func display(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        return f
    }
}

// The card container used to live here as `cardStyle()`. It was deleted in AMB.2
// along with its `CardStyle` modifier: it had ZERO call sites in the entire app
// after being introduced in the audit roadmap's Phase 3, while 115 hand-rolled
// cards went on being written around it. Its replacement is `.ambientCard(...)`
// in DesignSystem/AmbientCard.swift, which ships with an enforcement gate
// precisely because this one proved that an unenforced card modifier is
// decoration. See AMBIENT_ROLLOUT_PLAN.md.
