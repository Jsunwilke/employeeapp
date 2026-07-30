//  MileageReportsView.swift
//  Iconik Employee — Mileage Reports, converted to Ambient in AMB.9
//
//  The old screen and its `SummaryCardView` — two hand-rolled cards, a
//  `NumberFormatter` allocated per render, and the "Current Period" title that
//  stayed put while its values were replaced — are GONE from this file, not left
//  beside the new one. Every piece of the design now lives in
//  `Misc Features/MileageKit.swift`, which the design lab's mockup also draws with,
//  so the mockup and this screen cannot diverge.
//
//  WHAT THIS SCREEN GAINED, and why each is in scope:
//    · THE MONEY LEADS. The selected period's reimbursement is the big number.
//    · THE SPLIT IS ALWAYS VISIBLE, including at zero company miles.
//    · THE HEADER IS DERIVED FROM THE SELECTION, so it cannot say "Current Period"
//      over a past period's totals.
//    · REAL PAY-PERIOD BOUNDARIES. Six chips walked back through
//      `PayPeriodService`, so a weekly or monthly org gets its own cycle — and the
//      caption states which one it is reading.
//    · LOADING, EMPTY, FAILURE AND STALE STATES. The screen had none of the four,
//      and both fetch paths swallowed their failure, so a failed load read
//      "0.0 miles / $0.00".
//
//  CLEARANCE: this is a SHELL-WRAPPED feature — `MainEmployeeView.featureContainer`
//  applies `tabBarClearance` inside its own `NavigationView`, so this root must not
//  apply it again. The DETAIL is pushed and insets itself; see MileageDetailView.
//
//  DELIBERATELY NOT DRAWN: an "add trip" button. Mileage is one of 28 columns of a
//  daily job report and there is no add flow anywhere in the app; an empty state
//  that invites you to create something you cannot create is worse than one that
//  explains where the numbers come from.

import SwiftUI

struct MileageReportsView: View {
    @StateObject var viewModel: MileageReportsViewModel

    /// One `@State` destination, one `.ambientPush` — the AMB.3 rule.
    @State private var selectedRecord: MileageReportsViewModel.MileageRecordWrapper?

    private var tint: Color { MileageStyle.tint }

    init(userName: String) {
        _viewModel = StateObject(wrappedValue: MileageReportsViewModel(userName: userName))
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: tint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch viewModel.state {
                    case .loading:
                        hero
                        periodCarousel
                        monthAndYear
                        MileageTripsLoading()
                    case .loaded:
                        hero
                        periodCarousel
                        // A CHIP FETCH THAT FAILED, said inline. The figures above
                        // are current for the period now selected — the selection
                        // reverted — so this is not the stale banner's claim that
                        // everything on screen is older than now.
                        if let notice = viewModel.periodNotice {
                            MileageInlineNotice(message: notice, systemImage: "arrow.clockwise")
                        }
                        monthAndYear
                        if viewModel.records.isEmpty {
                            MileageEmptyTripsState()
                        } else {
                            tripsSection
                        }
                    case .stale(let message):
                        MileageStaleFiguresBanner(retry: { viewModel.retry() }, tint: tint)
                        hero
                        periodCarousel
                        monthAndYear
                        // The trips list is NOT drawn empty here: "no trips this
                        // period" would be a claim, and the banner has just said
                        // the screen could not reach the server. The figures are
                        // last-synced; the list is simply unknown.
                        if !viewModel.records.isEmpty {
                            tripsSection
                        } else {
                            MileageInlineNotice(message: message, systemImage: "wifi.slash")
                        }
                    case .failed(let message):
                        MileageFailureCard(message: message, tint: tint) { viewModel.retry() }
                        // The carousel stays: picking another period is a legitimate
                        // way to retry, and removing it would strand the screen.
                        periodCarousel
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .navigationBarTitle("Mileage Reports", displayMode: .inline)
        .ambientPush(item: $selectedRecord) { record in
            MileageDetailView(record: record,
                              personalRate: viewModel.personalRate,
                              companyRate: viewModel.companyRate)
        }
        // ONE call. The old screen called both loaders here while the first already
        // chained the second, so every appearance fetched the year twice.
        .onAppear { viewModel.load() }
    }

    // MARK: - 1. The money

    private var hero: some View {
        MileageHeroCard(header: headerLabel,
                        figures: viewModel.currentPeriodFigures,
                        tint: tint,
                        // The header moves on the tap; the money arrives later. For
                        // that gap the figures are redacted rather than left
                        // standing under a header that already changed.
                        isRefreshing: viewModel.isFetchingPeriod)
    }

    /// "This pay period · Jul 20 – Aug 2" when the current period is selected, the
    /// bare range when it is not. Derived, never typed.
    private var headerLabel: String {
        guard let period = viewModel.selectedPeriod else {
            // Before the pay-period service answers there is no range to state, and
            // inventing one is what put a selection on a period that did not exist.
            return "This pay period"
        }
        return period.headerLabel(monthDay: { Formatters.monthDay.string(from: $0) })
    }

    // MARK: - 2. The period carousel

    private var periodCarousel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.periods) { period in
                        MileagePeriodChip(
                            label: period.rangeLabel(monthDay: { Formatters.monthDay.string(from: $0) }),
                            isCurrent: period.isCurrent,
                            isSelected: period.index == viewModel.selectedPeriodIndex,
                            tint: tint) {
                                viewModel.selectPeriod(index: period.index)
                            }
                    }
                }
                .ambientScrollTargets()
            }
            .ambientCarousel(margin: 16)
            .padding(.horizontal, -16)

            // The org's REAL cycle, read from its pay-period settings. The mockup
            // marked this PROPOSED because the labels stepped a hardcoded 14 days;
            // both the labels and this caption now come from the same resolver.
            Text(viewModel.cycle.caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 3. Month and year

    /// THESE TWO TILES ARE GATED ON THEIR OWN FETCH, not on the screen's state. The
    /// period query and the year query succeed and fail independently, so a `.loaded`
    /// screen can carry month and year figures nobody ever fetched — and they would
    /// render as `0.0 miles · $0.00`, a real-looking total. Until the year query
    /// lands, each tile says so itself rather than leaning on an inline notice that
    /// the next chip tap clears.
    private var monthAndYear: some View {
        HStack(spacing: 10) {
            MileageFigureTile(title: "This month",
                              caption: Formatters.monthYear.string(from: Date()),
                              figures: viewModel.monthFigures,
                              systemImage: "calendar",
                              tint: tint,
                              isLoaded: viewModel.monthYearLoaded,
                              retry: monthYearRetry)
            MileageFigureTile(title: "This year",
                              caption: String(Calendar.current.component(.year, from: Date())),
                              figures: viewModel.yearFigures,
                              systemImage: "calendar.badge.clock",
                              tint: tint,
                              isLoaded: viewModel.monthYearLoaded,
                              retry: monthYearRetry)
        }
    }

    /// No retry offered while the first load is still running: the tiles are unloaded
    /// because nothing has answered YET, and a control that re-runs what is already
    /// running reads as a failure that has not happened.
    private var monthYearRetry: (() -> Void)? {
        if case .loading = viewModel.state { return nil }
        return { viewModel.retry() }
    }

    // MARK: - 4. The trips

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Trips", trailing: "\(viewModel.records.count)")
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                // Already newest-first: the view model sorts once, where the trips
                // land, rather than per body evaluation here.
                ForEach(viewModel.records) { record in
                    Button { selectedRecord = record } label: {
                        MileageTripRow(date: record.date,
                                       school: record.schoolName,
                                       miles: record.totalMileage,
                                       amount: viewModel.amount(for: record),
                                       isCompany: record.vehicle == .company,
                                       tint: tint)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }
            MileageSourceNote()
        }
    }
}
