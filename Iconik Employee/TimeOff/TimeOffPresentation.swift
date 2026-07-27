//  TimeOffPresentation.swift
//  Iconik Employee — turning a stored row into what the card draws
//
//  The seam between the DATA (a `TimeOffRequest` decoded from the shared
//  Supabase table) and the DESIGN (`TimeOffKit`'s plain-value `TimeOffCardModel`).
//  It exists so the kit never imports a database model and the lab can therefore
//  draw the same card from sample data.
//
//  IT IS ALSO WHERE THE CROSS-CLIENT REPAIRS LIVE, and they are repairs to what
//  is DISPLAYED, not to what is stored. Nothing here writes anything. The shared
//  table is written by the web app too, and reading it correctly means reading
//  what that app actually puts there — which, in three places, is not what this
//  app assumed. Each is marked below with the evidence.

import Foundation

extension TimeOffRequest {

    /// What the card draws.
    var cardModel: TimeOffCardModel {
        TimeOffCardModel(
            id: id,
            photographer: displayPhotographerName,
            status: TimeOffStatusDisplay.from(raw: status),
            reason: TimeOffReasonDisplay.from(raw: reason),
            dateLabel: presentedDateLabel,
            timeLabel: presentedTimeLabel,
            durationLabel: presentedDurationLabel,
            isPartialDay: isPartialDay,
            dayCount: presentedSpan.dayCount,
            notes: notes,
            usesPTO: isPaidTimeOff,
            ptoHours: pto_hours_requested,
            attribution: presentedAttribution,
            denialReason: denial_reason,
            createdAt: created_at
        )
    }

    /// The span, built through the TESTED rule type rather than re-derived here.
    /// `TimeOffSpan.dayCount` is inclusive of both endpoints; getting that wrong
    /// is an off-by-eight-hours on somebody's PTO.
    var presentedSpan: TimeOffSpan {
        TimeOffSpan(startDay: start_date,
                    endDay: end_date,
                    isPartialDay: isPartialDay,
                    start: start_time.flatMap(TimeOfDay.init),
                    end: end_time.flatMap(TimeOfDay.init))
    }

    private var displayPhotographerName: String {
        var name = (photographer_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // The web app builds this as `${first_name} ${last_name}` with no guard,
        // so a row with neither arrives as the literal "undefined undefined".
        if name == "undefined undefined" || name == "null null" { name = "" }
        // Empty string is not nil. The web app writes "" into several text
        // columns, and `photographer_name ?? ""` would happily hand an empty
        // string to a label that then renders a blank gap where a person's name
        // should be.
        return name.isEmpty ? "Unknown" : name
    }

    private var presentedDateLabel: String {
        let span = presentedSpan
        if isPartialDay || span.dayCount == 1 {
            return TimeOffDateLabel.string(from: start_date)
        }
        return "\(TimeOffDateLabel.string(from: start_date)) – \(TimeOffDateLabel.string(from: end_date))"
    }

    private var presentedTimeLabel: String {
        guard isPartialDay else { return "Full day" }
        // A PARTIAL DAY WHOSE TIMES WILL NOT PARSE IS NOT A FULL DAY. Returning
        // "Full day" here made the card contradict itself — the headline said a
        // whole day while the duration beside it said "Time not set" — and the
        // headline was the confident wrong answer. Legacy rows written by an old
        // iOS build on an Arabic or Persian locale hold non-ASCII digits
        // ("٠٩:٠٠"), which is exactly the case that reaches this branch.
        guard let start = start_time.flatMap(TimeOfDay.init),
              let end = end_time.flatMap(TimeOfDay.init) else { return "Time not set" }
        return "\(start.displayString) – \(end.displayString)"
    }

    private var presentedDurationLabel: String {
        let span = presentedSpan
        if isPartialDay {
            // Nil rather than 0.0 when the times are unreadable — so the card says
            // it does not know instead of asserting a zero-hour request.
            guard let hours = span.partialHours else { return "Time not set" }
            if hours == 1 { return "1 hour" }
            if hours.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(hours)) hours" }
            return String(format: "%.1f hours", hours)
        }
        return span.dayCount == 1 ? "1 day" : "\(span.dayCount) days"
    }

    /// Who actioned it, and when — nil unless BOTH are present.
    ///
    /// THE DENIAL FALLBACK IS A CROSS-CLIENT FIX. The web app's deny path writes
    /// `status`, `approved_by`, `approver_name`, `denial_reason` and `approved_at`
    /// — it stamps the APPROVAL columns on a denial and leaves `denied_by`,
    /// `denier_name` and `denied_at` NULL. (Its own `TimeOffApprovalModal` carries
    /// a comment saying so.) The shipped iOS card required `denierName` AND
    /// `deniedAt`, so for every request denied on the web it drew a red "Denied"
    /// badge with no denier and — because the reason was nested inside that same
    /// block — no reason either.
    ///
    /// iOS-denied requests still resolve through the denial columns first, so
    /// nothing changes for them.
    private var presentedAttribution: TimeOffAttribution? {
        switch TimeOffRuleStatus.parse(status) {
        case .approved:
            return TimeOffAttribution(name: approver_name, date: approved_at, status: .approved)
        case .denied:
            return TimeOffAttribution(name: denier_name, date: denied_at, status: .denied)
                ?? TimeOffAttribution(name: approver_name, date: approved_at, status: .denied)
        case .underReview:
            return TimeOffAttribution(name: reviewer_name, date: reviewed_at, status: .underReview)
        case .pending, .cancelled, .none:
            return nil
        }
    }
}

/// "Jul 25" this year, "Jul 25, 2025" in any other.
///
/// `Formatters.monthDay` drops the year entirely, so on the History tab a request
/// approved in January 2025 and one approved in January 2026 both read "Jan 5".
/// The fix round corrected the small grey attribution line and left the card's
/// PRIMARY date on `monthDay` — the instance, not the class, and arguably the
/// wrong instance. A year is only shown when it is not the current one, so the
/// common case stays as short as the design drew it.
enum TimeOffDateLabel {
    static func string(from date: Date) -> String {
        let calendar = Calendar.current
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return Formatters.monthDay.string(from: date)
        }
        return Formatters.mediumDate.string(from: date)
    }
}

extension TimeOfDay {
    /// Locale-aware for DISPLAY — a 24-hour region sees 17:00, a 12-hour region
    /// sees 5:00 PM. Distinct from `storageString`, which is always "HH:mm"
    /// because that is what the column holds. Conflating the two is what the old
    /// code did, with an unpinned `DateFormatter` used for both.
    var displayString: String {
        let reference = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
        return reference.map { Formatters.shortTime.string(from: $0) } ?? storageString
    }
}
