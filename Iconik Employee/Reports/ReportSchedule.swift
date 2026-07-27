//  ReportSchedule.swift
//  Iconik Employee — the schedule side of a daily job report
//
//  ONE HOME FOR A QUESTION THAT WAS ASKED IN THREE PLACES.
//      "Which of this photographer's sessions are on this date, and which have
//      they already filed a report against?" was answered by its own copy of the
//      same code in DailyJobReportView, TemplateFormView and nowhere on the list
//      screen at all — which is why the list screen could not tell you whether
//      today's report was done.
//
//      This type holds one copy. It changes NOTHING about the queries: the same
//      SessionService listener, the same filter, the same sort, and the same
//      "already reported" lookup the standard form has always used. It is a
//      consolidation, not a data-layer change (AMB plan, D12).
//
//  A DEFECT THAT MOVES HERE RATHER THAN BEING FIXED HERE
//      The "already reported" lookup is keyed on the photographer's FIRST NAME
//      (AMB_BATCH2_PARITY.md, finding R25), so two photographers who share a
//      first name share that state. That is wrong, it is live today, and fixing
//      it is a data-layer change this phase does not own. What changes is that
//      it now has ONE home instead of two, so the fix is one edit rather than a
//      hunt. Recorded, not repaired.
//
//  WHAT THE SESSION LISTENER CANNOT TELL US
//      `SessionService.startListeningToSessions` has no failure callback — it
//      only ever delivers sessions. So a failed load and a genuinely empty day
//      are indistinguishable from out here, and this type does not pretend
//      otherwise: it publishes "loading" and then "these are the sessions",
//      never a fabricated error state. Giving that fetch a real failure path is
//      a SessionService change and belongs with the offline work (OFF.1).

import Foundation
import SwiftUI

@MainActor
final class ReportSchedule: ObservableObject {

    /// This photographer's sessions on the loaded date, EARLIEST FIRST with
    /// undated sessions last — the order the picker shows and the order
    /// auto-select walks.
    @Published private(set) var sessions: [Session] = []

    /// Session ids this photographer has already filed a report against on the
    /// loaded date. Legacy reports with no session link contribute nothing.
    @Published private(set) var reportedSessionIDs: Set<String> = []

    /// True from the moment a date is requested until its sessions arrive.
    @Published private(set) var isLoadingSessions = false

    /// True once the "already reported" question has been ASKED for the loaded
    /// date — including when it could not be asked at all, which the live form
    /// treated as "nothing reported" and this keeps identical.
    ///
    /// Auto-select must not run before this is true, or the first thing it does
    /// is offer a session the photographer has already filed a report against.
    @Published private(set) var hasCheckedReported = false

    /// The lookup was attempted and did NOT produce an answer.
    ///
    /// "Nobody has filed anything" and "we could not find out" are different,
    /// and a screen that draws a COUNT must not present the second as the first.
    /// This app lost a whole feature for a year to exactly that shape.
    @Published private(set) var reportedLookupFailed = false

    /// The date currently loaded, as the app's canonical day key.
    private(set) var dateKey: String = ""

    private let sessionService = SessionService.shared
    private let subscriptionID = UUID()
    private var loadedDate: Date?
    /// Which already-reported lookup is current. Two date changes in quick
    /// succession, or a photographer change mid-flight, could otherwise let the
    /// older answer land last — and `SessionAutoSelect` makes its one decision
    /// per date from whatever is there.
    private var reportedRun = 0

    // MARK: - Sessions

    /// Load (and keep listening to) this photographer's sessions for `date`.
    ///
    /// Safe to call repeatedly for the same date — the listener replaces its own
    /// subscription. `onChange` fires every time the set changes, which is what
    /// lets the caller re-run auto-select; `SessionAutoSelect` is what makes
    /// those repeats harmless.
    func start(for date: Date, onChange: @escaping () -> Void) {
        let key = Formatters.isoDate.string(from: date)
        let isNewDate = key != dateKey
        if isNewDate {
            // A different day's answers are not this day's. Clearing these is
            // what makes auto-select re-decide rather than trusting yesterday's.
            reportedSessionIDs = []
            hasCheckedReported = false
            reportedLookupFailed = false
            reportedRun += 1          // abandon anything already in flight
        }
        loadedDate = date
        dateKey = key

        guard let currentUserID = UserManager.shared.getCurrentUserID() else {
            isLoadingSessions = false
            sessions = []
            return
        }
        let organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        guard !organizationID.isEmpty else {
            isLoadingSessions = false
            sessions = []
            return
        }

        let currentUserEmail = UserDefaults.standard.string(forKey: "userEmail")
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        // Only blank the list when the DATE changed. This is called again on
        // every re-appear and every foreground, and clearing it unconditionally
        // made a screen that already had today's sessions flash back to
        // "Checking your schedule…" each time.
        if isNewDate { sessions = [] }
        isLoadingSessions = sessions.isEmpty

        sessionService.startListeningToSessions(
            subscriptionId: subscriptionID,
            organizationID: organizationID,
            includeUnpublished: false          // regular users see only published
        ) { [weak self] all in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // A late delivery for a date the caller has moved off must not
                // overwrite the current day's sessions.
                guard self.loadedDate.map({ calendar.isDate($0, inSameDayAs: date) }) == true else { return }

                let mine: [Session] = all.filter { session in
                    guard let start = session.startDate else { return false }
                    guard start >= startOfDay, start < endOfDay else { return false }
                    return session.isUserAssigned(userID: currentUserID, userEmail: currentUserEmail)
                }
                self.sessions = mine.sorted {
                    ($0.startDate ?? Date.distantFuture) < ($1.startDate ?? Date.distantFuture)
                }
                self.isLoadingSessions = false
                onChange()
            }
        }
    }

    func stop() {
        sessionService.stopListeningToSessions(subscriptionId: subscriptionID)
    }

    // MARK: - Already reported

    /// Refresh which of the loaded date's sessions already have a report.
    ///
    /// `photographerFirstName` is the key the live standard form uses — see the
    /// header. Passing an empty name leaves the set untouched rather than
    /// clearing it, because "we do not know yet" and "nothing is reported" are
    /// different answers and only one of them is safe to draw.
    func refreshReported(photographerFirstName: String, organizationID: String) async {
        guard let date = loadedDate else { return }
        guard !photographerFirstName.isEmpty, !organizationID.isEmpty else {
            // Invalidate anything already in flight: without this, an older
            // lookup could land AFTER this non-answer and quietly repopulate a
            // set that has just been declared unknown.
            reportedRun += 1
            // The live form's `checkExistingReports` answered `[]` when it could
            // not identify the photographer, so auto-select proceeded. Same
            // answer here rather than blocking auto-select forever — but it is
            // marked as a non-answer so nothing draws a count from it.
            hasCheckedReported = true
            reportedLookupFailed = true
            return
        }

        reportedRun += 1
        let run = reportedRun
        let key = dateKey
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay


        do {
            let reports = try await DailyJobReportService.shared.getReports(
                yourName: photographerFirstName,
                organizationID: organizationID,
                startDate: startOfDay,
                endDate: endOfDay
            )
            // A late answer for a date or a photographer the caller has moved
            // off must not land.
            guard run == reportedRun, key == dateKey else { return }
            reportedSessionIDs = Set(reports.compactMap { $0.session_id })
            hasCheckedReported = true
            reportedLookupFailed = false
        } catch {
            guard run == reportedRun, key == dateKey else { return }
            // Asked and failed still counts as ASKED — otherwise a network blip
            // would leave auto-select permanently disabled. But it is also
            // recorded as a FAILURE, so a screen showing "N reports filed" can
            // say it does not know instead of asserting zero. The live form
            // swallowed this into an empty array and silently re-offered a
            // session that had been reported (finding R4).
            hasCheckedReported = true
            reportedLookupFailed = true
            print("⚠️ ReportSchedule: already-reported lookup failed — \(error.localizedDescription)")
        }
    }

    /// The candidates `SessionAutoSelect` needs, in picker order.
    var autoSelectCandidates: [SessionAutoSelect.Candidate] {
        sessions.map { .init(id: $0.id, alreadyReported: reportedSessionIDs.contains($0.id)) }
    }

    /// How many of the loaded date's sessions still have no report.
    var outstandingSessions: [Session] {
        sessions.filter { !reportedSessionIDs.contains($0.id) }
    }
}
