//  TimeClockAdapters.swift
//  Iconik Employee — turning the app's models into what TimeClockKit draws
//
//  `TimeClockKit` deliberately knows nothing about `TimeEntry` or `Session` — it
//  takes plain values, which is what let the design lab feed it samples and lets
//  production feed it a service without either owning the other. This file is
//  the one place that crosses between them.
//
//  It is small on purpose. Anything here that starts making a DECISION rather
//  than a translation belongs in `TimeClockRules.swift`, where it can be
//  compiled and run by the test harness.

import SwiftUI

// MARK: - What kind of entry this is

extension TimeClockEntryKind {
    /// THE OLD TEST WAS WRONG AND THIS ONE IS DELIBERATELY WEAKER.
    ///
    /// `TimeEntryRow` and `TimeEntryDetailView` both asked
    /// `clockInTime != nil && clockOutTime != nil && status != "clocked-in"` and
    /// called the answer "manual" — a condition true of EVERY completed shift.
    /// `time_entries` has no column recording how a row was created, so that
    /// distinction was never available; see the enum's own comment.
    init(_ entry: TimeEntry) {
        if entry.status == "clocked-in" {
            self = .running
        } else if entry.clockInTime != nil && entry.clockOutTime != nil {
            self = .recorded
        } else {
            self = .incomplete
        }
    }
}

// MARK: - An entry

extension TimeEntry {

    var clockKind: TimeClockEntryKind { TimeClockEntryKind(self) }

    /// Seconds this entry contributes to a range total.
    ///
    /// A REAL PAYROLL BUG LIVED IN THE DIFFERENCE BETWEEN THIS AND
    /// `durationInHours`. That property substitutes `Date()` for a missing end
    /// time (`Models.swift:653`) — correct for a shift in progress, and wrong
    /// for an entry that is NOT running and has no end time, which the service
    /// can genuinely produce: a queued offline clock-out whose row has gone is
    /// logged and dropped on purpose (`TimeTrackingService.swift:212-218`).
    /// Summed by the list, such a row grew by an hour every hour and inflated
    /// the pay-period total forever.
    ///
    /// A running shift still counts up to now — that is intended, and it is what
    /// the home dashboard's "Active" figure has always shown.
    var payrollSeconds: TimeInterval {
        guard let start = clockInTime else { return 0 }
        if let end = clockOutTime { return max(end.timeIntervalSince(start), 0) }
        guard status == "clocked-in" else { return 0 }
        return max(Date().timeIntervalSince(start), 0)
    }

    /// Everything a row draws.
    func clockDisplay(now: Date = Date(), calendar: Calendar = .current) -> TimeClockEntryDisplay {
        let kind = clockKind
        return TimeClockEntryDisplay(
            id: id,
            dayLabel: Self.dayLabel(for: date, now: now, calendar: calendar),
            timeRange: timeRangeText,
            durationText: kind == .incomplete ? "—" : TimeClockFormat.hoursAndMinutes(payrollSeconds),
            kind: kind,
            sessionName: sessionDisplayName,
            notes: notes,
            editDaysRemaining: TimeClockRules.editWindowDaysRemaining(
                createdAt: createdAt,
                isRunning: kind == .running,
                now: now,
                calendar: calendar
            )
        )
    }

    /// "9:00 AM – 5:30 PM", "9:00 AM – Present", or — the case the shipped row
    /// could not say — "9:00 AM – no clock-out".
    private var timeRangeText: String {
        guard let start = clockInTime else { return "No start time" }
        let from = Formatters.shortTime.string(from: start)
        if let end = clockOutTime {
            return "\(from) – \(Formatters.shortTime.string(from: end))"
        }
        return status == "clocked-in" ? "\(from) – Present" : "\(from) – no clock-out"
    }

    /// The shipped rule: show the session's name, or the literal "Session" when
    /// only an id survived the denormalisation.
    private var sessionDisplayName: String? {
        guard let sessionId, !sessionId.isEmpty else { return nil }
        if let name = sessionName, !name.isEmpty, name != sessionId { return name }
        return "Session"
    }

    /// "Today" / "Yesterday" / "Mar 4", from the entry's `yyyy-MM-dd` day key.
    ///
    /// Uses the shared `Formatters` cache rather than building two
    /// `DateFormatter`s per row per body pass, which is what every screen on
    /// this surface was doing.
    static func dayLabel(for dateString: String?, now: Date, calendar: Calendar) -> String {
        guard let dateString, let day = Formatters.isoDate.date(from: dateString) else {
            return dateString ?? "—"
        }
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return Formatters.dayAndMonth.string(from: day)
    }
}

// MARK: - A session

extension TimeClockSessionDisplay {
    init(_ session: Session) {
        var range: String?
        if let start = session.startDate, let end = session.endDate {
            range = "\(Formatters.shortTime.string(from: start)) – \(Formatters.shortTime.string(from: end))"
        }
        self.init(id: session.id,
                  schoolName: session.schoolName,
                  position: session.position,
                  timeRange: range,
                  location: session.location,
                  dayLabel: session.multiDayLabel)
    }
}

// MARK: - One more shared formatter

extension Formatters {
    /// "Mar 4" — the entry list's relative-date fallback. Added here rather than
    /// in `DesignTokens.swift` so it travels with the surface that needs it; if a
    /// second surface wants it, it gets promoted like everything else on this arc.
    static let dayAndMonth: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()
}
