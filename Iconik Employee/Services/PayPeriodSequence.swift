//  PayPeriodSequence.swift
//  Iconik Employee — pay periods, as compiled types shared by every surface
//
//  PROMOTED OUT OF `Misc Features/MileageRules.swift` for the time clock, which is
//  the second surface to need them. The arc's rule when a second surface needs a
//  primitive is to promote it rather than fork it — `AmbientFormSection`,
//  `AmbientCardFill.surface` and `AmbientControls` all arrived that way — and a
//  second copy of "what is a pay period" is the last thing this app should carry.
//
//  IT WAS ALREADY THE SECOND COPY. The time clock computed its own 14-day grid
//  from a hardcoded "2/25/2024" literal inside a view file, while mileage asked
//  `PayPeriodService`, which honours the organisation's real
//  `pay_period_settings` — weekly, bi-weekly or monthly. Those two agree TODAY
//  only by luck: Iconik Studio's configured start date, 2024-12-29, happens to sit
//  exactly 22 fourteen-day periods after that literal. Change the org's start date
//  by a day, or switch it to weekly, and the clock's "Pay Period" total would have
//  silently described a different span from mileage, from the manager's report and
//  from payroll. The clock now asks the same resolver.
//
//  NO SwiftUI IMPORT. Deliberate and load-bearing: `swiftc` compiles this
//  standalone for BOTH `scripts/test_mileage_rules.sh` and
//  `scripts/test_timeclock_rules.sh`. Anything needing a Color or a View belongs
//  in a Kit.

import Foundation

/// THE DEFECT THIS EXISTS TO KILL: the carousel used to step its labels back by a
/// HARDCODED 14 days (`MileageReportsView.swift`, before AMB.9) while the DATA came from
/// `PayPeriodService`, which honours `PayPeriodSettings.type` — weekly, bi-weekly
/// or monthly. For a weekly org the chips said one thing and the totals under them
/// described another span entirely, and nothing on the screen said which.
///
/// The mapping mirrors `PayPeriodService.getPayPeriod` exactly, INCLUDING its
/// fallbacks, so the caption cannot describe a cycle the boundaries are not on:
/// an unknown type and inactive-or-missing settings both fall to bi-weekly there,
/// and both fall to bi-weekly here.
enum PayPeriodCycle: String, Equatable, CaseIterable {
    case weekly
    case biweekly
    case monthly

    static func from(type: String?, isActive: Bool) -> PayPeriodCycle {
        // Inactive or missing settings mean PayPeriodService uses its default
        // 2/25/2024-anchored 14-day period, which IS a bi-weekly cycle.
        guard isActive,
              let raw = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return .biweekly }
        switch raw {
        case "weekly":              return .weekly
        case "bi-weekly", "biweekly": return .biweekly
        case "monthly":             return .monthly
        // Same branch PayPeriodService takes for an unrecognised type.
        default:                    return .biweekly
        }
    }

    /// The caption under the carousel. It ships as a statement of fact rather than
    /// the mockup's PROPOSED note, because the boundaries above it are now the
    /// org's real ones.
    var caption: String {
        switch self {
        case .weekly:   return "Weekly pay periods"
        case .biweekly: return "Bi-weekly pay periods"
        case .monthly:  return "Monthly pay periods"
        }
    }
}

// MARK: - One pay period

/// A pay period, identified by how far back it is rather than by its start date.
///
/// THE INDEX IS THE IDENTITY, and that is the fix for a real defect: the old screen
/// held the selection as a `Date` seeded in `init` from a value the pay-period
/// service had not answered for yet, so on first render the selected date matched
/// NONE of the six cards. An index cannot be seeded wrong — it is resolved against
/// whatever list the service produces.
struct PayPeriod: Equatable, Identifiable {
    /// 0 is the current period; 1 is the one before it, and so on.
    let index: Int
    let start: Date
    let end: Date

    var id: Int { index }
    var isCurrent: Bool { index == 0 }

    /// "Jul 20 – Aug 2". The formatter is injected so this file stays SwiftUI-free
    /// and the test can pin a POSIX one.
    func rangeLabel(monthDay: (Date) -> String) -> String {
        "\(monthDay(start)) – \(monthDay(end))"
    }

    /// THE HEADER CANNOT LIE, because it is derived from the selection rather than
    /// typed above it. The old card was titled "Current Period" permanently while
    /// its values were replaced with the selected period's.
    func headerLabel(monthDay: (Date) -> String) -> String {
        isCurrent
            ? "This pay period · \(rangeLabel(monthDay: monthDay))"
            : rangeLabel(monthDay: monthDay)
    }

    func contains(_ date: Date) -> Bool { date >= start && date <= end }
}

/// The six chips, newest first.
///
/// Built by WALKING BACKWARDS THROUGH THE REAL RESOLVER — one day before a
/// period's start is, by definition, inside the previous period — so a monthly org
/// gets calendar months of unequal length and a weekly org gets seven-day steps,
/// with no period-length arithmetic in this type at all. That is what makes it
/// correct for all three cycles instead of for one.
///
/// THE WALK STOPS RATHER THAN GUESSES. A resolver that answers with a period which
/// overlaps, repeats or does not abut the one already collected is describing a
/// cycle this walk cannot represent, and the two guards below end the sequence
/// there. Fewer honest chips; never a wrong one.
///
/// THE RESOLVER THAT PROVOKES THIS, and whose repair is NOT in AMB.9's scope:
/// `PayPeriodService.getMonthlyPayPeriod` (PayPeriodService.swift:166) assigns
/// `components.day = startDay` and lets Foundation roll an out-of-range day
/// forward, so a monthly org anchored on the 29th or the 31st gets periods that
/// jump (a day-31 anchor answers "Jul 1 – Jul 31" for July and then
/// "May 31 – Jun 29", skipping Jun 30) and a day-29 anchor leaves Feb 28 in no
/// period at all. That is a PRE-EXISTING defect in the payroll rule, owned by
/// `PayPeriodService` and shared with every other screen that reads it — and no
/// live organisation is on a monthly cycle (all three are bi-weekly, verified
/// 2026-07-29), so this phase guards against the shape instead of rewriting the
/// rule that produces it.
enum PayPeriodSequence {
    static let chipCount = 6

    /// `resolve` is `PayPeriodService.getPayPeriod(for:)` in production and a
    /// hand-written cycle in the test.
    static func build(count: Int = chipCount,
                      now: Date = Date(),
                      calendar: Calendar = .current,
                      resolve: (Date) -> (start: Date, end: Date)?) -> [PayPeriod] {
        var periods: [PayPeriod] = []
        var probe = now

        for index in 0..<max(0, count) {
            guard let answer = resolve(probe) else { break }
            if let previous = periods.last {
                // NON-DECREASING: a resolver that keeps answering with the same
                // period — a misconfigured start date, a monthly cycle whose
                // day-of-month arithmetic sticks — would otherwise produce six
                // identical chips that all select the same range. Six copies of one
                // period is worse than fewer honest chips.
                if previous.start <= answer.start { break }
                // CONTIGUOUS: the previous chip's start is the day after this one
                // ends, because that is the day this walk probed with. When it is
                // not, the resolver has skipped days (mileage filed in them would
                // belong to no chip) or overlapped the chip already drawn (the same
                // trip counted twice). Either way the boundaries stop being the
                // org's, so the sequence ends here — see the day-29/31
                // `getMonthlyPayPeriod` shapes in this type's doc comment.
                guard let expectedEnd = calendar.date(byAdding: .day,
                                                     value: -1,
                                                     to: calendar.startOfDay(for: previous.start)),
                      calendar.startOfDay(for: answer.end) == expectedEnd else { break }
            }
            periods.append(PayPeriod(index: index, start: answer.start, end: answer.end))
            guard let dayBefore = calendar.date(byAdding: .day,
                                                value: -1,
                                                to: calendar.startOfDay(for: answer.start)) else { break }
            probe = dayBefore
        }

        return periods
    }
}
