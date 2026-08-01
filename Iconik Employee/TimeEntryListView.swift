//  TimeEntryListView.swift
//  Iconik Employee — your recorded hours, converted to Ambient in AMB.13
//
//  The old presentation and its 200-line hand-rolled `TimeEntryRow` are GONE
//  from this file. The row now lives in `TimeClock/TimeClockKit.swift`, which the
//  design lab's mockup also draws with, so the two cannot diverge.
//
//  THE ONE THAT MATTERS: A FAILED LOAD IS NO LONGER DRAWN AS ZERO HOURS.
//  The catch block used to set `isLoading = false` and nothing else, so a
//  request that timed out produced "No time entries for pay period" above a
//  total of 0h. That is payroll appearing to be zero because the wifi dropped.
//  Failure is now its own state with its own words and a Retry, using
//  `AmbientFailureCard` — which AMB.12 added to the design system naming THIS
//  screen as one of the two reasons it was needed.
//
//  ALSO CHANGED:
//    - The 100-row fetch ceiling is SAID rather than hidden. `getTimeEntries`
//      caps at 100 with no pagination, and the total under it is then not the
//      range's total. Raising the cap is a data change (AMB13_CLOCK_PARITY §7);
//      admitting to it is presentation.
//    - No scrolling view inside a scrolling view. This was a `ScrollView` nested
//      in its parent's `VStack` with a `Spacer()` fighting it.
//    - THE PAY PERIOD IS THE ORGANISATION'S, AND YOU CAN WALK BACK THROUGH THEM.
//      This screen used to compute its own 14-day grid from a hardcoded
//      "2/25/2024" literal in a 45-line private function with three
//      `print`-and-fallback branches — and it could only ever show the CURRENT
//      period, so an entry in the one before it was unreachable. It now asks
//      `PayPeriodService` through the shared `PayPeriodSequence`, the same
//      resolver mileage and the manager's report use, and carries the same
//      six-chip carousel.
//    - The half-second `DispatchQueue.main.asyncAfter` that the first load was
//      gated on — a race papered over with a delay — is gone; the load runs in
//      a `.task`, which also cancels when the view goes away.
//    - Debug `print`s on a payroll path are gone, and with them the call to
//      `debugTimeEntryQuery()`, a function with an empty body that was awaited
//      on every empty result.

import SwiftUI

struct TimeEntryListView: View {
    @ObservedObject var timeTrackingService: TimeTrackingService

    @State private var entries: [TimeEntry] = []
    @State private var range: TimeClockRange = .payPeriod
    @State private var phase: LoadPhase = .loading
    @State private var showingManualEntry = false
    @State private var entryBeingEdited: TimeEntry?

    /// The org's real pay periods, most recent first, and which one is showing.
    ///
    /// THE INDEX IS THE IDENTITY, not a date — the reason is written down on
    /// `PayPeriod` itself: a date seeded before the service has answered matches
    /// none of the periods it later produces.
    @State private var periods: [PayPeriod] = []
    @State private var selectedPeriodIndex = 0
    @State private var cycle: PayPeriodCycle = .biweekly
    private let payPeriodService = PayPeriodService.shared

    /// Loading, loaded and FAILED are three states, not two. Conflating the last
    /// two is the defect this screen is named for.
    private enum LoadPhase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// The service's hard `.limit(100)` (`TimeTrackingService.swift:591`). When
    /// the fetch comes back exactly full we cannot tell "100 entries" from "the
    /// first 100 of more", so the total is flagged as possibly short rather than
    /// presented as fact.
    private let fetchCeiling = 100

    private var totalSeconds: TimeInterval {
        entries.reduce(0) { $0 + $1.payrollSeconds }
    }

    private var isLoading: Bool { phase == .loading }

    /// The span currently on screen. Today and This Week are calendar facts the
    /// rules file can answer; a pay period is the ORGANISATION's and comes from
    /// the carousel's selection.
    private var activePeriod: TimeClockPeriod? {
        if let fixed = range.fixedPeriod() { return fixed }
        guard periods.indices.contains(selectedPeriodIndex) else { return nil }
        let period = periods[selectedPeriodIndex]
        return TimeClockPeriod(start: period.start, end: period.end)
    }

    /// What the totals card is titled. For a pay period it names WHICH one, so a
    /// figure can never sit under a header that does not describe it — the defect
    /// `PayPeriod.headerLabel` exists to prevent on the mileage screen.
    ///
    /// `rangeLabel`, NOT `headerLabel`: mileage's header carries the words "This
    /// pay period" because its carousel can be scrolled off screen, and here the
    /// chips sit directly above the card with the current one marked "Now". The
    /// longer form wrapped onto two lines and pushed the entry count out of
    /// alignment for the period people look at most.
    private var activeRangeLabel: String {
        guard range == .payPeriod else { return range.rawValue }
        guard periods.indices.contains(selectedPeriodIndex) else { return range.rawValue }
        return periods[selectedPeriodIndex]
            .rangeLabel(monthDay: { Formatters.monthDay.string(from: $0) })
    }

    /// True only before the FIRST successful load of this range. Once there are
    /// rows, they stay on screen through a refresh and through a refresh that
    /// fails — a total that blinks to nothing and back is its own small lie
    /// about payroll.
    private var hasNothingToShow: Bool {
        if case .loaded = phase { return false }
        return entries.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            TimeClockRangePicker(selection: $range)

            if range == .payPeriod { periodCarousel }

            // A FAILURE IS SHOWN ABOVE WHAT WE ALREADY HAD, never instead of it.
            // The first cut of this swapped the whole list for the failure card,
            // which is a quieter version of the same lie the screen exists to
            // remove: a refresh that fails should not make the hours you were
            // already looking at disappear.
            if case .failed(let message) = phase {
                AmbientFailureCard(message: message) { load() }
            }

            if hasNothingToShow {
                // Nothing loaded and nothing to fall back on. Either it is still
                // arriving, or the card above already explains why it is not.
                if isLoading {
                    AmbientLoadingRow(message: "Loading your hours…")
                }
            } else {
                TimeClockTotalsCard(totalSeconds: totalSeconds,
                                    entryCount: entries.count,
                                    rangeLabel: activeRangeLabel,
                                    isTruncated: entries.count >= fetchCeiling,
                                    lastSyncedAt: timeTrackingService.isUsingOfflineData
                                        ? (timeTrackingService.lastSyncTime ?? Date())
                                        : nil)

                if entries.isEmpty {
                    AmbientEmptyState(
                        title: "No hours yet",
                        message: "Nothing recorded for this \(range.rawValue.lowercased()). Clock in, or add an entry by hand.",
                        systemImage: "clock.badge.questionmark",
                        actionTitle: "Add entry",
                        actionIcon: "plus",
                        action: { showingManualEntry = true },
                        actionTint: TimeClockStyle.accent
                    )
                } else {
                    LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                        ForEach(entries) { entry in
                            TimeClockEntryRow(entry: entry.clockDisplay()) {
                                entryBeingEdited = entry
                            }
                            .ambientScrollFade()
                        }
                    }
                }
            }
        }
        .task(id: range) { await loadAsync(resettingRows: true) }
        // A different pay period is a different query, and its rows must not be
        // shown under the new period's header while it arrives.
        .task(id: selectedPeriodIndex) {
            guard range == .payPeriod else { return }
            await loadAsync(resettingRows: true)
        }
        .sheet(isPresented: $showingManualEntry, onDismiss: load) {
            ManualTimeEntryView(timeTrackingService: timeTrackingService)
        }
        .sheet(item: $entryBeingEdited, onDismiss: load) { entry in
            EditTimeEntryView(timeEntry: entry, timeTrackingService: timeTrackingService)
        }
        // A clock-in or clock-out anywhere else in the app changes what belongs
        // in this list. The shipped screen only reloaded on its own sheets.
        .onChange(of: timeTrackingService.isClockIn) { _ in load() }
    }

    /// Six pay periods, walked backwards from today, so you can see the ones you
    /// have already been paid for.
    ///
    /// THE SAME CAROUSEL THE MILEAGE SCREEN SHIPS, from the same types: the chip
    /// is `AmbientPeriodChip` and the walk is `PayPeriodSequence`, both promoted
    /// out of the mileage feature when this screen became the second to need
    /// them. Copying it would have meant a second answer to "when did that pay
    /// period start", which is the one thing this change exists to stop.
    private var periodCarousel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(periods) { period in
                        AmbientPeriodChip(
                            label: period.rangeLabel(monthDay: { Formatters.monthDay.string(from: $0) }),
                            isCurrent: period.isCurrent,
                            isSelected: period.index == selectedPeriodIndex,
                            tint: TimeClockStyle.accent
                        ) {
                            guard period.index != selectedPeriodIndex else { return }
                            selectedPeriodIndex = period.index
                        }
                    }
                }
                .ambientScrollTargets()
            }
            .ambientCarousel(margin: 16)
            .padding(.horizontal, -16)

            Text(cycle.caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var header: some View {
        HStack {
            AmbientSectionTitle("Your hours")
            Spacer(minLength: 8)
            AmbientActionButton(title: "Add entry",
                                systemImage: "plus",
                                role: .secondary,
                                size: .small,
                                fillWidth: false) {
                showingManualEntry = true
            }
        }
    }

    // MARK: - Loading

    private func load() {
        Task { await loadAsync() }
    }

    /// `resettingRows` is true only when the RANGE changed. Keeping the old rows
    /// there would show a pay period's entries under a total labelled "Today"
    /// until the fetch landed. A plain refresh keeps them, which is the point of
    /// `hasNothingToShow`.
    private func loadAsync(resettingRows: Bool = false) async {
        if resettingRows { entries = [] }
        phase = .loading

        // The org's periods have to exist before a pay-period query can be
        // built. Resolved once and reused; a failure here leaves any periods a
        // previous read produced alone, because they came from a read that
        // succeeded.
        if range == .payPeriod, periods.isEmpty { await loadPeriods() }

        guard let period = activePeriod else {
            phase = .failed("Couldn't work out your organization's pay periods. Try again when you're back online.")
            return
        }

        do {
            let loaded = try await timeTrackingService.getTimeEntries(
                startDate: Formatters.isoDate.string(from: period.start),
                endDate: Formatters.isoDate.string(from: period.end)
            )
            guard !Task.isCancelled else { return }
            entries = loaded
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            // The entries already on screen are left alone deliberately: wiping
            // them to zero on a failed refresh is the same lie in a smaller form.
            phase = .failed("Couldn't load your hours. \(error.userFacingMessage)")
        }
    }

    /// Resolve the organisation's pay periods, then walk six of them back.
    ///
    /// `PayPeriodService` is completion-based and caches per organisation, so the
    /// continuation is the bridge rather than a second cache. Its resolver
    /// honours weekly, bi-weekly and monthly settings and falls back to a default
    /// bi-weekly grid when an org carries none — the same answer mileage gets,
    /// which is the entire point of asking it rather than computing here.
    private func loadPeriods() async {
        await withCheckedContinuation { continuation in
            payPeriodService.loadPayPeriodSettings { _ in continuation.resume() }
        }
        guard !Task.isCancelled else { return }

        let service = payPeriodService
        let built = PayPeriodSequence.build(now: Date()) { service.getPayPeriod(for: $0) }
        guard !built.isEmpty else { return }

        periods = built
        cycle = PayPeriodCycle.from(type: service.payPeriodSettings?.type,
                                    isActive: service.payPeriodSettings?.isActive ?? false)
        if !periods.indices.contains(selectedPeriodIndex) { selectedPeriodIndex = 0 }
    }
}

#Preview {
    ScrollView {
        TimeEntryListView(timeTrackingService: TimeTrackingService())
            .padding()
    }
}
