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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            TimeClockRangePicker(selection: $range)

            switch phase {
            case .loading:
                AmbientLoadingRow(message: "Loading your hours…")

            case .failed(let message):
                AmbientFailureCard(message: message) { load() }

            case .loaded:
                TimeClockTotalsCard(totalSeconds: totalSeconds,
                                    entryCount: entries.count,
                                    rangeLabel: range.rawValue,
                                    isTruncated: entries.count >= fetchCeiling)

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
        .task(id: range) { await loadAsync() }
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

    private func loadAsync() async {
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
