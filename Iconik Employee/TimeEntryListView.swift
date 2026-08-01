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
//    - The pay-period arithmetic moved to `TimeClockRules`, where it is compiled
//      and tested, instead of being an 45-line private function with three
//      `print`-and-fallback branches on a payroll date range.
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
                                    rangeLabel: range.rawValue,
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
        let period = range.period()
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
}

#Preview {
    ScrollView {
        TimeEntryListView(timeTrackingService: TimeTrackingService())
            .padding()
    }
}
