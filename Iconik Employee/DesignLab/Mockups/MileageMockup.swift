//  MileageMockup.swift
//  Iconik Employee — AMB.9's Mileage mockup, built in batch 3
//
//  ARC SCAFFOLDING. Deleted at AMB.9's close, once the operator has confirmed the
//  converted screens on a device — the rule AMB.7's and AMB.11's mockups went by.
//
//  WHAT THE DESIGN IS ARGUING, in four claims the operator can accept or reject
//
//      1. THE MONEY LEADS.
//         Today the screen opens with a period carousel and then three cards of
//         EQUAL weight — "Current Period", "Miles in July", "Miles this Year" —
//         each of which puts miles in the big number and the money underneath in
//         a caption. But nobody opens a mileage screen to learn how far they
//         drove; they open it to find out what they are owed. So the selected
//         period's REIMBURSEMENT is the big number, the miles sit under it, and
//         the month/year figures step down to two tiles. Nothing is deleted:
//         both figures — miles AND money — survive on every card, because a past
//         phase of this arc lost a money figure by dropping a label.
//
//      2. THE SPLIT IS ALWAYS VISIBLE.
//         "Personal 132.4 mi · Company 18.0 mi" renders today ONLY when company
//         miles are greater than zero (parity §1, `MileageReportsView.swift:244`).
//         That is a payroll line: the two halves are reimbursed at different
//         rates, and "no company miles this period" is a fact worth stating, not
//         an absence worth hiding. It is drawn unconditionally here.
//
//      3. A CARD IS TITLED BY WHAT IT SHOWS.
//         Select a past period today and the values are replaced with that
//         period's while the title stays "Current Period" (parity §1). So the
//         header line reads "This pay period · Jul 20 – Aug 2" when the current
//         one is selected and simply "Jul 6 – Jul 19" when it is not. The title
//         cannot lie because it is derived from the selection.
//
//      4. THE MISSING STATES ARE DRAWN.
//         Mileage Reports has NO loading, empty, error or offline state at all,
//         and both fetch paths swallow their failure to a `print` — so a failed
//         load renders "0.0 miles / $0.00", indistinguishable from a genuinely
//         empty period (parity §1, "States — all four absent"). Those states are
//         drawn here and marked PROPOSED.
//
//  WHAT IS NOT BEING PROPOSED
//      No data layer, service, loader, rate rule or permission change (D12). Two
//      money defects found in the inventory — the hardcoded 14-day carousel step
//      contradicting `PayPeriodSettings.type`, and compensation computed as
//      Σ(miles) × TODAY's rate rather than Σ(miles × rate) — are recorded in
//      AMB_BATCH3_PARITY.md §1 and are NOT fixed by this phase. Where this mockup
//      draws a caption those fixes would need, it says PROPOSED, so an approval
//      here is not mistaken for an approval of the fix.
//
//      Deliberately NOT drawn: an "add trip" button. Mileage is one of 28 columns
//      of a daily job report and there is no add flow anywhere in the app; an
//      empty state that invites you to create something you cannot create is
//      worse than one that explains where the numbers come from.

import SwiftUI

// MARK: - Destinations

/// One enum, one `.ambientPush` — the AMB.3 rule.
private enum MileageDestination: String, Identifiable {
    case detail

    var id: String { rawValue }
}

/// A lab control, not a design element — it exists so the operator can see the
/// empty, error and offline states without having to arrange for them.
private enum MileageLabState: String, CaseIterable, Identifiable {
    case populated = "Populated"
    case empty = "Empty"
    case error = "Error"
    case offline = "Offline"

    var id: String { rawValue }
}

// MARK: - Root: Mileage

struct MileageMockup: View {
    /// The feature's own colour (D11) — `FeatureTheme.color(for: "mileageReports")`,
    /// the "On the road" family it shares with the Route Planner.
    static let featureTint = Color(hex: "#E8830C")

    @State private var state: MileageLabState = .populated
    @State private var selectedPeriod: Int = 0
    @State private var destination: MileageDestination?

    private var period: LabPayPeriod { MileageSample.periods[selectedPeriod] }
    private var trips: [LabMileageTrip] { MileageSample.trips(for: selectedPeriod) }

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
                    case .empty:
                        hero
                        periodCarousel
                        monthAndYear
                        emptyState
                    case .error:
                        errorState
                        periodCarousel
                    case .offline:
                        offlineBanner
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

    /// Claim 1 and claim 3 in one card. Every figure is computed from the period's
    /// trips rather than typed in, so the hero cannot disagree with the list under
    /// it — the same arithmetic-honesty rule the Stats mockup is built on.
    private var hero: some View {
        let totals = MileageSample.totals(for: state == .empty ? -1 : selectedPeriod)
        return VStack(alignment: .leading, spacing: 10) {
            Text(period.isCurrent
                 ? "This pay period · \(period.label)"
                 : period.label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(MileageSample.money(totals.reimbursement))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("reimbursement")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text("\(totals.miles, specifier: "%.1f") miles")
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            // Claim 2: ALWAYS drawn, including at zero company miles. The two
            // halves are paid at different rates; the split is payroll, not trim.
            HStack(spacing: 6) {
                Image(systemName: "car.fill").font(.caption2.weight(.semibold))
                Text("Personal \(totals.personalMiles, specifier: "%.1f") mi · Company \(totals.companyMiles, specifier: "%.1f") mi")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
        }
        .ambientCard(density: .hero, state: .highlighted, glow: Self.featureTint, fillWidth: true)
    }

    // MARK: 2 — the period carousel

    private var periodCarousel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MileageSample.periods) { option in
                        periodChip(option)
                    }
                }
                .ambientScrollTargets()
            }
            .ambientCarousel(margin: 16)
            .padding(.horizontal, -16)

            // PROPOSED — the carousel's labels step by a HARDCODED 14 days
            // (`MileageReportsView.swift:11-24`) while the DATA comes from the
            // org's real `PayPeriodService` range. For a weekly or monthly org
            // the labels and the numbers describe different spans of time. The
            // design says which cycle it is drawing; making that true is a
            // settings read this phase has not been authorised to add.
            Text("Bi-weekly pay periods · PROPOSED — today the labels always step 14 days even for weekly and monthly orgs.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func periodChip(_ option: LabPayPeriod) -> some View {
        let selected = option.id == selectedPeriod
        return Button {
            withAnimation(AmbientMotion.snappy) { selectedPeriod = option.id }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 5) {
                if option.isCurrent {
                    Circle()
                        .fill(selected ? Color.white : Self.featureTint)
                        .frame(width: 5, height: 5)
                }
                Text(option.label).font(.caption.weight(.semibold))
                if option.isCurrent {
                    Text("Now")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? .white : .secondary)
                }
            }
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // ambient-allow: a selection chip is a control, not a container.
            .background(Capsule().fill(selected
                                       ? AnyShapeStyle(Self.featureTint)
                                       : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 3 — month and year

    /// The old "Miles in <Month>" and "Miles this Year" cards, kept whole: BOTH
    /// figures survive on both tiles. The month card's clock icon is corrected to
    /// a calendar — a clock on a card counting miles in July was reading as
    /// elapsed time.
    private var monthAndYear: some View {
        HStack(spacing: 10) {
            figureTile(title: "This month",
                       caption: MileageSample.monthName,
                       miles: MileageSample.monthMiles,
                       systemImage: "calendar")
            figureTile(title: "This year",
                       caption: MileageSample.yearName,
                       miles: MileageSample.yearMiles,
                       systemImage: "calendar.badge.clock")
        }
    }

    private func figureTile(title: String, caption: String, miles: Double, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Self.featureTint)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text("\(miles, specifier: "%.1f")")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("miles · \(MileageSample.money(miles * MileageSample.personalRate))")
                .font(.caption).foregroundStyle(.secondary)
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    // MARK: 4 — the trips

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Trips", trailing: "\(trips.count)")
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(trips) { trip in
                    Button { destination = .detail } label: { tripRow(trip) }
                        .buttonStyle(.plain)
                        .ambientScrollFade()
                }
            }
            Text("Mileage is one of 28 columns of a daily job report. These rows are those reports, seen from the money side.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tripRow(_ trip: LabMileageTrip) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(Formatters.weekdayShort.string(from: trip.date).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(Formatters.dayNumber.string(from: trip.date))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(trip.school)
                    .font(AmbientDensity.compact.titleFont)
                    .lineLimit(1)
                if trip.isCompanyVehicle {
                    AmbientBadge(text: "Company", systemImage: "car.2.fill", tint: Self.featureTint)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(trip.miles, specifier: "%.1f") mi")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(MileageSample.money(trip.amount))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    // MARK: the three states the screen does not have today

    /// No action button, deliberately. There is genuinely no add flow — mileage
    /// arrives with a filed daily job report — so the empty state explains the
    /// route instead of offering one that does not exist.
    private var emptyState: some View {
        AmbientEmptyState(
            title: "No trips this period",
            message: "Mileage comes from your daily job reports — file one with mileage and it lands here.",
            systemImage: "car")
    }

    /// PROPOSED — today a failed load is swallowed to a `print` and the cards
    /// render $0.00, which reads as a real zero-mileage period. Money that
    /// silently reads zero is the worst failure mode on this screen.
    private var errorState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Couldn't load mileage").font(.headline)
            Text("The server didn't answer. Your trips and your reimbursement are safe — this screen just can't show them right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                withAnimation(AmbientMotion.gentle) { state = .populated }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    // ambient-allow: a control, not a card.
                    .background(Capsule().fill(Self.featureTint))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Text("PROPOSED — today both fetch paths swallow the failure and the cards read $0.00. See AMB_BATCH3_PARITY.md §1.")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    /// PROPOSED — likewise absent. The distinction that matters is that this is
    /// NOT an error: the figures are real, they are just older than now.
    private var offlineBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash").font(.footnote.weight(.semibold))
                Text("Offline — showing the last figures that synced")
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
            }
            Text("PROPOSED — the screen has no offline state today, though the home dashboard's mileage widget already caches to UserDefaults.")
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.orange)
        .ambientCard(density: .compact, border: .dashed(Color.orange.opacity(0.5)), fillWidth: true)
    }
}

// MARK: - Detail

/// One trip, and the edit that today lives in inline Save/Cancel buttons halfway
/// down the content (`MileageDetailView.swift:136-178`). Here Edit, Save and
/// Cancel are TOOLBAR items: an edit that changes a payroll figure should be a
/// mode you enter, not a pair of buttons sitting between two cards.
private struct MileageDetailMockup: View {
    private let trip = MileageSample.detailTrip

    @State private var editing = false
    @State private var saving = false
    @State private var school: String = MileageSample.detailTrip.school
    @State private var vehicle: String? = MileageSample.detailTrip.isCompanyVehicle ? "Company" : "Personal"
    @State private var milesText: String = String(format: "%.1f", MileageSample.detailTrip.miles)
    @State private var picking = false
    @State private var validation: String?

    private var isCompany: Bool { vehicle == "Company" }
    private var rate: Double { isCompany ? MileageSample.companyRate : MileageSample.personalRate }
    private var miles: Double? { Double(milesText) }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: MileageMockup.featureTint, intensity: 0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    if editing { editSection } else { readSection }
                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $picking) {
            SchoolPickerSheet(selection: $school)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if editing {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    school = trip.school
                    vehicle = trip.isCompanyVehicle ? "Company" : "Personal"
                    milesText = String(format: "%.1f", trip.miles)
                    validation = nil
                    withAnimation(AmbientMotion.snappy) { editing = false }
                }
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

    private func save() {
        guard !school.trimmingCharacters(in: .whitespaces).isEmpty else {
            validation = "Please select a school."
            return
        }
        guard let value = miles, value >= 0 else {
            validation = "Please enter a number for the miles driven."
            return
        }
        validation = nil
        milesText = String(format: "%.1f", value)
        saving = true
        // Save is disabled in flight — today's screen leaves it live and a second
        // press fires a second UPDATE (parity §2).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            saving = false
            withAnimation(AmbientMotion.snappy) { editing = false }
            AmbientHaptics.impact(.medium)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(school).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                // Personal is BADGED too. Today a personal trip shows nothing at
                // all and absence is the only signal (parity §2).
                AmbientBadge(text: isCompany ? "Company" : "Personal",
                             systemImage: isCompany ? "car.2.fill" : "car.fill",
                             tint: isCompany ? MileageMockup.featureTint : .secondary)
            }
            Text(Formatters.longDate.string(from: trip.date))
                .font(.subheadline).foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(miles ?? 0, specifier: "%.1f")")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("miles").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(MileageSample.money((miles ?? 0) * rate))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
            }
            Text("at \(MileageSample.money(rate)) per mile")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .hero, state: .highlighted, glow: MileageMockup.featureTint, fillWidth: true)
    }

    private var readSection: some View {
        VStack(spacing: 0) {
            row("School", school)
            Divider()
            row("Vehicle", isCompany ? "Company car" : "Personal car")
            Divider()
            row("Miles", String(format: "%.1f", miles ?? 0))
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private var editSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientFormSection(title: "Trip",
                               status: "\(String(format: "%.1f", miles ?? 0)) mi · \(isCompany ? "Company" : "Personal")",
                               statusTint: MileageMockup.featureTint,
                               density: .roomy) {
                VStack(alignment: .leading, spacing: 12) {
                    Button { picking = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("School").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(school.isEmpty ? "Select a school" : school)
                                    .font(.subheadline)
                                    .foregroundStyle(school.isEmpty ? .secondary : .primary)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Divider()

                    AmbientChoiceRow(title: "Vehicle",
                                     options: ["Personal", "Company"],
                                     selection: $vehicle,
                                     tint: MileageMockup.featureTint)

                    Divider()

                    VStack(spacing: 4) {
                        Text("Miles driven").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("0.0", text: $milesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let validation {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").font(.caption.weight(.semibold))
                    Text(validation).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.orange)
            }
        }
    }

    /// "Open full report" is deliberately NOT drawn: there is no route to the
    /// report from here in the data layer today, and a mockup does not get to
    /// invent navigation. What the screen CAN honestly say is what the edit does.
    private var footnote: some View {
        Text("Edits change the mileage on the filed report.")
            .font(.caption2).foregroundStyle(.tertiary)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).font(.subheadline).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - School picker

/// Hand-rolled search field, not `.searchable` — iOS 16.6 floor, and the app's
/// own school picker is hand-rolled too.
private struct SchoolPickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return MileageSample.schools }
        return MileageSample.schools.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: MileageMockup.featureTint, intensity: 0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        searchField
                        if matches.isEmpty {
                            AmbientEmptyState(title: "No schools match",
                                              message: "Try fewer words.",
                                              systemImage: "magnifyingglass")
                        } else {
                            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                                ForEach(matches, id: \.self) { school in
                                    Button {
                                        selection = school
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: school == selection
                                                  ? "checkmark.circle.fill" : "circle")
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(school == selection
                                                                 ? MileageMockup.featureTint : .secondary)
                                            Text(school).font(.subheadline)
                                            Spacer(minLength: 0)
                                        }
                                        .ambientCard(density: .compact, fillWidth: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Select School")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.footnote).foregroundStyle(.secondary)
            TextField("Search schools", text: $query)
                .font(.subheadline)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.footnote).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
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

    var amount: Double { miles * rate }
}

private struct LabPayPeriod: Identifiable {
    let id: Int
    let start: Date
    let end: Date

    var isCurrent: Bool { id == 0 }

    var label: String {
        "\(Formatters.monthDay.string(from: start)) – \(Formatters.monthDay.string(from: end))"
    }
}

private struct LabMileageTotals {
    let miles: Double
    let personalMiles: Double
    let companyMiles: Double
    let reimbursement: Double
}

/// All of it computed from a FIXED anchor date rather than `Date()`, so the
/// mockup shows the same six periods on any day the operator opens it.
private enum MileageSample {
    static let personalRate: Double = 0.67
    static let companyRate: Double = 0.10

    /// Monday 20 July 2026 — the current pay period's first day.
    static let anchor: Date =
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 20))
        ?? Date(timeIntervalSince1970: 1_784_505_600)

    static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }

    static let periods: [LabPayPeriod] = (0..<6).map { index in
        LabPayPeriod(id: index, start: day(-14 * index), end: day(-14 * index + 13))
    }

    static let monthName = "July 2026"
    static let yearName = "2026"
    static let monthMiles: Double = 262.6
    static let yearMiles: Double = 1574.2

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

    /// Period 0 carries the argument-causing cases: both vehicle types, a long
    /// school name that must truncate, and a trip with miles but a ZERO rate —
    /// which is the shape a real "$0.00" takes and which today's screen cannot be
    /// told apart from a failed load.
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

    /// A company-only period — the case the current screen hides, because it
    /// renders the split line only when company miles are non-zero and therefore
    /// never states that PERSONAL miles are the zero half.
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
    static func totals(for period: Int) -> LabMileageTotals {
        let rows = trips(for: period)
        let personal = rows.filter { !$0.isCompanyVehicle }.reduce(0) { $0 + $1.miles }
        let company = rows.filter { $0.isCompanyVehicle }.reduce(0) { $0 + $1.miles }
        return LabMileageTotals(miles: personal + company,
                                personalMiles: personal,
                                companyMiles: company,
                                reimbursement: rows.reduce(0) { $0 + $1.amount })
    }

    static let detailTrip = period0[1]

    /// "$1,234.50" — grouped, two decimals, never truncated to whole dollars the
    /// way the Stats screen's `$<Int>` bars are.
    static func money(_ value: Double) -> String {
        let formatter = currencyFormatter
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
