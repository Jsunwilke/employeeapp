//  StatsView.swift
//  Iconik Employee — Statistics, rebuilt to the approved AMB.9 design
//
//  THE 1,005-LINE SCREEN THIS REPLACES NEVER RENDERED. Its queries named four
//  columns that do not exist, and `StatsView:23` replaced the entire tab area
//  with "Error Loading Data" whenever any one of five fetches failed — so the
//  screen was dead for every organisation, by construction. The repair is in
//  `StatsViewModel`; this file is the design the operator approved on 2026-07-29,
//  drawn with `Stats/StatsKit.swift` — the same views the lab mockup draws, so
//  there is nothing for the two to drift apart on.
//
//  WHAT THE DESIGN ARGUES, and what each claim replaces:
//
//    1. ONE SCROLL. The five-button tab strip is gone. Nothing here is secondary
//       (the operator's ruling on the report form), and switching tabs did not
//       even refetch — it hid four fifths of the answer.
//    2. CALENDAR PERIODS, HONESTLY LABELLED. Month/Quarter/Year silently meant
//       the trailing 31/92/365 days from that instant. The chips now name the
//       period they mean, because the window now is that period.
//    3. NO FABRICATED DATA. The hardcoded "Weather Impact on Jobs" table — five
//       literal rows and 930 invented jobs shown to every org — is deleted, and
//       so is "Average Job Time", which read a hardcoded 3.0 hours because the
//       timestamp columns it claimed to average do not exist.
//    4. DETERMINISTIC PER-PHOTOGRAPHER COLOUR via `AmbientStyle.avatarColor`. The
//       old trends chart answered only the literal names John, Sarah and Mike,
//       was hard-capped at three photographers, and drew everyone else as a grey
//       flat line at zero.
//    5. THREE HONEST STATES. Loading, an empty period that says so, and one error
//       card with Retry — one fetch, so one thing can fail.
//
//  WHAT IS DELIBERATELY NOT FIXED HERE, named rather than silently left:
//  Statistics is gated at the SECTION level in All Features
//  (`Permissions.has("users", .edit)`) and `featureView(for:)` re-checks nothing,
//  so any write of `selectedTab = "stats"` reaches this screen ungated. That is a
//  permission change, not a design one (D12), and it is recorded in
//  AMB_BATCH3_PARITY.md §4 rather than changed in a design phase.
//
//  SHELL-WRAPPED. `stats` is not in `isSelfNavFeature`, so MainEmployeeView
//  provides the NavigationView, the Home button and the tab-bar clearance. This
//  file adds none of those — a second inset reserves twice the room.

import SwiftUI

struct StatsView: View {
    @StateObject private var viewModel = StatsViewModel()
    @State private var period: StatsPeriod = .year
    /// Fixed when the screen opens, so the period boundaries and the chip labels
    /// cannot shift under the reader mid-session (and so a reload re-reads the
    /// same window rather than a new one).
    @State private var reference = Date()

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StatsPeriodChips(period: $period, reference: reference)
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .navigationTitle("Statistics")
        .onAppear {
            refreshReferenceIfDayChanged()
            load()
        }
        .onChange(of: period) { _ in load() }
    }

    /// THE REFERENCE IS STABLE WITHIN A DAY AND NEVER OLDER THAN ONE.
    ///
    /// It is fixed at `init` so the chip labels and the period boundaries cannot shift
    /// under the reader mid-session. But this screen lives inside a tab shell that
    /// keeps it alive for as long as the app is running, so past midnight — and past
    /// New Year — a stale reference had "July" over August's window and asked the
    /// server for the wrong month. Re-minted only when the stored day is no longer
    /// today, which leaves the within-session stability exactly as it was.
    private func refreshReferenceIfDayChanged() {
        let now = Date()
        guard !Calendar.current.isDate(reference, inSameDayAs: now) else { return }
        reference = now
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            StatsLoadingState(spanLabel: period.window(reference: reference).spanLabel)

        case .failed(let message):
            StatsErrorState(message: message) { load() }

        case .loaded(let aggregate):
            if aggregate.isEmpty {
                StatsEmptyPeriodState(periodLabel: aggregate.periodLabel)
            } else {
                StatsOverviewSection(aggregate: aggregate)
                StatsMileageSection(aggregate: aggregate)
                StatsLocationsSection(aggregate: aggregate)
                StatsPhotographersSection(aggregate: aggregate)
                StatsJobTypesSection(aggregate: aggregate)
            }
        }
    }

    private func load() {
        viewModel.load(period: period, reference: reference)
    }
}
