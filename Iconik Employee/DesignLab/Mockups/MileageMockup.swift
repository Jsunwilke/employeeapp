//  MileageMockup.swift
//  Iconik Employee — AMB.9's Mileage mockup, built in batch 3
//
//  ARC SCAFFOLDING. Deleted at AMB.9's close, once the operator has confirmed the
//  converted screens on a device — the rule AMB.7's and AMB.11's mockups went by.
//
//  REPOINTED AT PRODUCTION CODE (2026-07-29, operator approved the design; D10
//  closed). Every component this file drew privately now lives in
//  `Misc Features/MileageKit.swift` and every number it computed privately is
//  computed by `Misc Features/MileageRules.swift`, which is compiled and RUN by
//  `scripts/test_mileage_rules.sh`. The real screens draw with exactly these types.
//  That is the mechanism, not a courtesy: there is no second copy of the design to
//  drift from, so "does the screen match the mockup" is not a question anyone has
//  to answer by eye.
//
//  WHAT IS STILL PRIVATE TO THIS FILE: the sample data, and the lab's state picker.
//  Nothing else.
//
//  THE FOUR CLAIMS THE OPERATOR ACCEPTED
//      1. THE MONEY LEADS — the selected period's REIMBURSEMENT is the big number,
//         the miles sit under it, and the month/year figures step down to two
//         tiles. Nothing is deleted: both figures — miles AND money — survive on
//         every card, because a past phase of this arc lost a money figure by
//         dropping a label.
//      2. THE SPLIT IS ALWAYS VISIBLE — "Personal 132.4 mi · Company 18.0 mi" is
//         drawn unconditionally, including at zero company miles. It is a payroll
//         line: the two halves are reimbursed at different rates.
//      3. A CARD IS TITLED BY WHAT IT SHOWS — the header reads "This pay period ·
//         Jul 20 – Aug 2" when the current period is selected and simply "Jul 6 –
//         Jul 19" when it is not. It cannot lie because it is derived from the
//         selection.
//      4. THE MISSING STATES ARE DRAWN — loading, empty, failure and stale. All
//         four ship: the view model publishes its failures now, and the three
//         headline totals are cached, so the "last figures that synced" banner has
//         real figures behind it. The PROPOSED captions this file used to carry are
//         gone because the things they were waiting on were built.
//
//  WHAT IS STILL NOT PROPOSED
//      An "add trip" button. Mileage is one of 28 columns of a daily job report and
//      there is no add flow anywhere in the app; an empty state that invites you to
//      create something you cannot create is worse than one that explains where the
//      numbers come from.

import SwiftUI

// MARK: - Destinations

/// One enum, one `.ambientPush` — the AMB.3 rule.
private enum MileageDestination: String, Identifiable {
    case detail

    var id: String { rawValue }
}

/// A lab control, not a design element — it exists so the operator can see the
/// empty, failure and stale states without having to arrange for them.
private enum MileageLabState: String, CaseIterable, Identifiable {
    case populated = "Populated"
    /// The in-flight state the real screen shows on a chip tap: the trips list is
    /// loading and the hero's figures are redacted, because until the fetch lands
    /// they belong to the period the header no longer names. Claim 4 says all four
    /// states are drawn, and this was the one the lab could not show.
    case loading = "Loading"
    case empty = "Empty"
    case error = "Error"
    case stale = "Stale"

    var id: String { rawValue }
}

// MARK: - Root: Mileage

struct MileageMockup: View {
    /// The feature's own colour (D11), read through the production style so the lab
    /// and the screen cannot disagree about it.
    static var featureTint: Color { MileageStyle.tint }

    @State private var state: MileageLabState = .populated
    @State private var selectedPeriod: Int = 0
    @State private var destination: MileageDestination?

    private var period: MileagePeriod { MileageSample.periods[selectedPeriod] }
    private var trips: [LabMileageTrip] { MileageSample.trips(for: selectedPeriod) }
    private var figures: MileageFigures {
        MileageSample.figures(for: state == .empty ? -1 : selectedPeriod)
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    switch state {
                    case .populated:
                        hero
                        periodCarousel
                        monthAndYear
                        tripsSection
                    case .loading:
                        hero
                        periodCarousel
                        monthAndYear
                        MileageTripsLoading()
                    case .empty:
                        hero
                        periodCarousel
                        monthAndYear
                        MileageEmptyTripsState()
                    case .error:
                        MileageFailureCard(message: MileageFailureCard.genericMessage,
                                           tint: Self.featureTint) {
                            withAnimation(AmbientMotion.gentle) { state = .populated }
                        }
                        periodCarousel
                    case .stale:
                        // The banner's copy names a Retry, so the banner draws one —
                        // the lab exercises the shipped control rather than a
                        // version of the card without it.
                        MileageStaleFiguresBanner(retry: {
                            withAnimation(AmbientMotion.gentle) { state = .populated }
                        }, tint: Self.featureTint)
                        hero
                        periodCarousel
                        monthAndYear
                        tripsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .detail: MileageDetailMockup()
            }
        }
    }

    // MARK: lab chrome

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · state", trailing: "not a design element")
            Picker("State", selection: $state) {
                ForEach(MileageLabState.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: 1 — the money

    /// Claims 1, 2 and 3 in one card. Every figure comes from `MileageSample.figures`,
    /// which accumulates the same trips the list under it draws through
    /// `VehicleRates.Split.add` — so the hero cannot disagree with the rows.
    private var hero: some View {
        MileageHeroCard(
            header: period.headerLabel(monthDay: { Formatters.monthDay.string(from: $0) }),
            figures: figures,
            tint: Self.featureTint,
            // The same in-flight presentation the real screen draws while a chip
            // fetch is running — the production component's own, not a lab copy.
            isRefreshing: state == .loading)
    }

    // MARK: 2 — the period carousel

    private var periodCarousel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MileageSample.periods) { option in
                        MileagePeriodChip(
                            label: option.rangeLabel(monthDay: { Formatters.monthDay.string(from: $0) }),
                            isCurrent: option.isCurrent,
                            isSelected: option.index == selectedPeriod,
                            tint: Self.featureTint) {
                                selectedPeriod = option.index
                            }
                    }
                }
                .ambientScrollTargets()
            }
            .ambientCarousel(margin: 16)
            .padding(.horizontal, -16)

            // The org's REAL cycle. This used to read PROPOSED because the labels
            // stepped a hardcoded 14 days while the data came from the org's pay
            // period; both now come from one resolver, and the real screen reads
            // this caption off `PayPeriodSettings.type`.
            Text(MileageSample.cycle.caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 3 — month and year

    /// The old "Miles in <Month>" and "Miles this Year" cards, kept whole: BOTH
    /// figures survive on both tiles. The month card's clock icon is corrected to a
    /// calendar — a clock on a card counting miles in July was reading as elapsed
    /// time.
    ///
    /// THE LOADING STATE DRAWS THEM UNLOADED, which is the production behaviour: the
    /// year query is a separate fetch from the period query, and until it lands these
    /// tiles have no figure to show — drawing 0.0 would be a total nobody fetched.
    private var monthAndYear: some View {
        HStack(spacing: 10) {
            MileageFigureTile(title: "This month",
                              caption: MileageSample.monthName,
                              figures: MileageSample.monthFigures,
                              systemImage: "calendar",
                              tint: Self.featureTint,
                              isLoaded: state != .loading)
            MileageFigureTile(title: "This year",
                              caption: MileageSample.yearName,
                              figures: MileageSample.yearFigures,
                              systemImage: "calendar.badge.clock",
                              tint: Self.featureTint,
                              isLoaded: state != .loading)
        }
    }

    // MARK: 4 — the trips

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Trips", trailing: "\(trips.count)")
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(trips) { trip in
                    Button { destination = .detail } label: {
                        MileageTripRow(date: trip.date,
                                       school: trip.school,
                                       miles: trip.miles,
                                       amount: trip.amount,
                                       isCompany: trip.isCompanyVehicle,
                                       tint: Self.featureTint)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }
            MileageSourceNote()
        }
    }
}

// MARK: - Detail

/// One trip, and the edit that used to live in inline Save/Cancel buttons halfway
/// down the content. Edit, Save and Cancel are TOOLBAR items: an edit that changes
/// a payroll figure should be a mode you enter, not a pair of buttons sitting
/// between two cards.
private struct MileageDetailMockup: View {
    private let trip = MileageSample.detailTrip

    @State private var editing = false
    @State private var saving = false
    @State private var school: String = MileageSample.detailTrip.school
    /// HELD AS THE TYPE, exactly as the real screen holds it (`MileageDetailView`):
    /// a label mapped back with `?? .personal` turns a renamed option into a company
    /// trip saved as personal, and the lab must not demonstrate the shape production
    /// no longer has.
    @State private var resolvedVehicle: MileageVehicle = MileageVehicle
        .from(storage: MileageSample.detailTrip.isCompanyVehicle ? "company" : "personal")
    @State private var milesText: String = MileageFigures.oneDecimal(MileageSample.detailTrip.miles)
    @State private var validation: String?

    /// The kit's choice row takes plain strings; an unrecognised one moves nothing.
    private var vehicleChoice: Binding<String?> {
        Binding(get: { resolvedVehicle.choiceLabel },
                set: { newValue in
                    guard let newValue, let picked = MileageVehicle.from(choiceLabel: newValue) else { return }
                    resolvedVehicle = picked
                })
    }
    private var rate: Double {
        resolvedVehicle == .company ? MileageSample.companyRate : MileageSample.personalRate
    }
    private var miles: Double { Double(milesText) ?? 0 }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: MileageMockup.featureTint, intensity: 0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MileageDetailHero(school: school,
                                      date: trip.date,
                                      miles: miles,
                                      vehicle: resolvedVehicle,
                                      rate: rate,
                                      tint: MileageMockup.featureTint)
                    if editing {
                        MileageEditForm(schoolName: $school,
                                        vehicleChoice: vehicleChoice,
                                        milesText: $milesText,
                                        schools: MileageSample.schoolItems,
                                        schoolsState: .ready,
                                        validationMessage: validation,
                                        tint: MileageMockup.featureTint)
                    } else {
                        MileageDetailReadRows(school: school,
                                              vehicle: resolvedVehicle,
                                              miles: miles)
                    }
                    MileageEditFootnote()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if editing {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    school = trip.school
                    resolvedVehicle = MileageVehicle
                        .from(storage: trip.isCompanyVehicle ? "company" : "personal")
                    milesText = MileageFigures.oneDecimal(trip.miles)
                    validation = nil
                    withAnimation(AmbientMotion.snappy) { editing = false }
                }
                .disabled(saving)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if saving {
                    ProgressView()
                } else {
                    Button("Save") { save() }
                        .font(.body.weight(.semibold))
                }
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    withAnimation(AmbientMotion.snappy) { editing = true }
                }
            }
        }
    }

    /// The same validation type the real screen runs, so the messages and their
    /// order are the design's rather than each screen's.
    private func save() {
        validation = nil
        let result = MileageEditValidation.evaluate(school: school,
                                                    vehicle: resolvedVehicle,
                                                    milesText: milesText)
        guard case .valid(_, _, let value) = result else {
            validation = result.message
            return
        }
        milesText = MileageFigures.oneDecimal(value)
        saving = true
        // Save is disabled in flight — the old screen left it live and a second
        // press fired a second UPDATE.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            saving = false
            withAnimation(AmbientMotion.snappy) { editing = false }
            AmbientHaptics.impact(.medium)
        }
    }
}

// MARK: - Sample data

private struct LabMileageTrip: Identifiable {
    let id: String
    let date: Date
    let school: String
    let miles: Double
    let isCompanyVehicle: Bool
    /// Per-trip, so the mockup can show the $0-rate edge — miles with no money —
    /// without the hero's arithmetic going wrong.
    let rate: Double

    var amount: Double {
        MileageMath.amount(miles: miles,
                           vehicleType: isCompanyVehicle ? "company" : "personal",
                           personalRate: rate,
                           companyCarRate: rate)
    }
}

/// All of it computed from a FIXED anchor date rather than `Date()`, so the mockup
/// shows the same six periods on any day the operator opens it.
private enum MileageSample {
    static let personalRate: Double = 0.67
    static let companyRate: Double = 0.10

    /// Monday 20 July 2026 — the current pay period's first day.
    static let anchor: Date =
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 20))
        ?? Date(timeIntervalSince1970: 1_784_505_600)

    /// A TRIP'S DATE AS THE DATABASE CARRIES ONE: `daily_job_reports.date` is a bare
    /// day, stored as midnight UTC. The trip row and the detail hero read it back in
    /// UTC (`Formatters.storedDay*`), so sample dates minted at LOCAL midnight would
    /// draw a day early in every zone east of UTC and the lab would be arguing with
    /// production about which day a row is. The chip anchor stays local — a pay-period
    /// boundary is a local wall-clock date, which is what `PayPeriodService` mints.
    static func day(_ offset: Int) -> Date {
        let calendar = MileageMath.storedDayCalendar
        let label = Calendar.current.dateComponents([.year, .month, .day], from: anchor)
        guard let storedAnchor = calendar.date(from: DateComponents(year: label.year,
                                                                   month: label.month,
                                                                   day: label.day)),
              let shifted = calendar.date(byAdding: .day, value: offset, to: storedAnchor)
        else { return anchor }
        return shifted
    }

    /// A bi-weekly cycle anchored on `anchor`, in the shape `PayPeriodService`
    /// answers in — so the six chips are built by the SAME walk-backwards the real
    /// screen uses (`MileagePeriodSequence`) rather than by a local 14-day loop.
    private static func resolve(_ date: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day ?? 0
        let elapsed = Int(floor(Double(days) / 14.0))
        guard let start = calendar.date(byAdding: .day, value: 14 * elapsed, to: anchor),
              let end = calendar.date(byAdding: .day, value: 13, to: start) else { return nil }
        return (start, end)
    }

    static let periods: [MileagePeriod] =
        MileagePeriodSequence.build(now: anchor, resolve: resolve)

    static let cycle: MileagePeriodCycle = .biweekly

    static let monthName = "July 2026"
    static let yearName = "2026"
    static let monthMiles: Double = 262.6
    static let yearMiles: Double = 1574.2

    /// The two tiles take a `MileageFigures` so their miles and their money come from
    /// ONE source, which is what production does — through the real accumulator here
    /// as well, rather than a `miles × rate` multiplication beside it.
    static let monthFigures = MileageFigures(split: MileageMath.split(personalMiles: monthMiles,
                                                                     companyMiles: 0,
                                                                     personalRate: personalRate,
                                                                     companyCarRate: companyRate))
    static let yearFigures = MileageFigures(split: MileageMath.split(personalMiles: yearMiles,
                                                                    companyMiles: 0,
                                                                    personalRate: personalRate,
                                                                    companyCarRate: companyRate))

    static let schools = [
        "Cedar Valley Day School",
        "Lakeshore Charter",
        "Northgate Elementary",
        "Oakmont Prep",
        "Pinehurst Elementary",
        "Riverbend Middle School",
        "St. Bartholomew Academy",
        "Westfield Consolidated High School"
    ]

    /// Fed into the app's own `SearchableMileageSchoolPicker`, which is the control
    /// the real edit form uses — so the lab is exercising the shipped picker rather
    /// than a lookalike sheet.
    static let schoolItems: [MileageSchoolItem] =
        schools.map { MileageSchoolItem(id: $0, name: $0) }

    /// Period 0 carries the argument-causing cases: both vehicle types, a long
    /// school name that must truncate, and a trip with miles but a ZERO rate —
    /// which is the shape a real "$0.00" takes, and which the screen can now be
    /// told apart from a failed load because a failed load has its own state.
    private static let period0: [LabMileageTrip] = [
        LabMileageTrip(id: "p0-1", date: day(0), school: "Northgate Elementary",
                       miles: 24.6, isCompanyVehicle: false, rate: personalRate),
        LabMileageTrip(id: "p0-2", date: day(1), school: "Westfield Consolidated High School",
                       miles: 38.2, isCompanyVehicle: false, rate: personalRate),
        LabMileageTrip(id: "p0-3", date: day(2), school: "St. Bartholomew Academy",
                       miles: 18.0, isCompanyVehicle: true, rate: companyRate),
        LabMileageTrip(id: "p0-4", date: day(3), school: "Riverbend Middle School",
                       miles: 41.0, isCompanyVehicle: false, rate: personalRate),
        LabMileageTrip(id: "p0-5", date: day(4), school: "Oakmont Prep",
                       miles: 28.6, isCompanyVehicle: false, rate: 0)
    ]

    /// A company-only period — the case the old screen hid, because it rendered the
    /// split line only when company miles were non-zero and therefore never stated
    /// that PERSONAL miles are the zero half.
    private static let period1: [LabMileageTrip] = [
        LabMileageTrip(id: "p1-1", date: day(-14), school: "Lakeshore Charter",
                       miles: 22.4, isCompanyVehicle: true, rate: companyRate),
        LabMileageTrip(id: "p1-2", date: day(-12), school: "Pinehurst Elementary",
                       miles: 16.8, isCompanyVehicle: true, rate: companyRate),
        LabMileageTrip(id: "p1-3", date: day(-9), school: "Cedar Valley Day School",
                       miles: 31.2, isCompanyVehicle: true, rate: companyRate)
    ]

    private static let period2: [LabMileageTrip] = [
        LabMileageTrip(id: "p2-1", date: day(-28), school: "Westfield Consolidated High School",
                       miles: 44.8, isCompanyVehicle: false, rate: personalRate),
        LabMileageTrip(id: "p2-2", date: day(-25), school: "Northgate Elementary",
                       miles: 27.6, isCompanyVehicle: false, rate: personalRate)
    ]

    private static let period3: [LabMileageTrip] = [
        LabMileageTrip(id: "p3-1", date: day(-42), school: "Oakmont Prep",
                       miles: 33.4, isCompanyVehicle: false, rate: personalRate),
        LabMileageTrip(id: "p3-2", date: day(-38), school: "Riverbend Middle School",
                       miles: 19.8, isCompanyVehicle: true, rate: companyRate)
    ]

    private static let period4: [LabMileageTrip] = [
        LabMileageTrip(id: "p4-1", date: day(-56), school: "St. Bartholomew Academy",
                       miles: 52.2, isCompanyVehicle: false, rate: personalRate)
    ]

    private static let period5: [LabMileageTrip] = [
        LabMileageTrip(id: "p5-1", date: day(-70), school: "Pinehurst Elementary",
                       miles: 12.4, isCompanyVehicle: false, rate: personalRate),
        LabMileageTrip(id: "p5-2", date: day(-66), school: "Lakeshore Charter",
                       miles: 29.0, isCompanyVehicle: false, rate: personalRate)
    ]

    static func trips(for period: Int) -> [LabMileageTrip] {
        switch period {
        case 0: return period0
        case 1: return period1
        case 2: return period2
        case 3: return period3
        case 4: return period4
        case 5: return period5
        default: return []
        }
    }

    /// Every hero figure comes through here, so the card and the list under it
    /// cannot disagree. A negative index means "the empty state" and totals zero.
    ///
    /// It accumulates through `VehicleRates.Split.add` — the production accumulator,
    /// one trip at a time — which is why a per-trip rate can be honoured without the
    /// split arithmetic being rewritten here.
    static func figures(for period: Int) -> MileageFigures {
        var split = VehicleRates.Split()
        for trip in trips(for: period) {
            split.add(miles: trip.miles,
                      vehicleType: trip.isCompanyVehicle ? "company" : "personal",
                      personalRate: trip.rate,
                      companyCarRate: trip.rate)
        }
        return MileageFigures(split: split)
    }

    static let detailTrip = period0[1]
}
