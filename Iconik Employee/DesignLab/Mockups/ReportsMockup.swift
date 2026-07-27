//  ReportsMockup.swift
//  Iconik Employee — AMB.7's mockup, built in batch 2
//
//  ARC SCAFFOLDING. Deleted at AMB.7's close, with the rest of the lab going at
//  AMB.12.
//
//  THE THING TO UNDERSTAND BEFORE JUDGING THIS DESIGN
//      "Reports" is not one feature. It is TWO PARALLEL REPORT SYSTEMS plus two
//      note-taking surfaces, and a single organisation flag switches between the
//      first two:
//
//        usePhotoshootNotesOnly TRUE   hides the daily job report, custom reports
//                                      and my-reports features ENTIRELY, and is
//                                      also the flag that turns ON submitting in
//                                      Photoshoot Notes.
//        usePhotoshootNotesOnly FALSE  the three report features are visible, and
//                                      Photoshoot Notes is a LOCAL scratchpad
//                                      whose notes only reach the server by being
//                                      attached to a daily job report.
//
//      One boolean therefore selects which of two entire workflows an org uses.
//      A design that draws only one of them strands the other, so the lab control
//      at the top of the root screen flips it and the whole surface changes.
//      This was found by reading the source, not by looking at the screens.
//
//  WHAT THE DESIGN IS ARGUING
//
//      1. THE LIST THAT IS REACHABLE IS THE POOR ONE.
//         MyJobReportsView — the only reports list a user can actually open —
//         has no search, no filter, no grouping and NO EMPTY STATE AT ALL. A
//         second list, TemplateReportListView, has all of it: search, a date
//         filter, grouping by template, badges, counts, a real empty state and an
//         error state with a retry. It is 558 lines, it is compiled and shipped,
//         and it is ORPHANED — verified: the only instantiation anywhere in the
//         repo is its own preview instantiating itself. The redesign takes the
//         capabilities from the dead screen and puts them in the live one.
//
//      2. THE FORM SHOULD SAY WHAT IT ACTUALLY REQUIRES.
//         The standard report draws a progress bar over EIGHT sections with a
//         denominator of SEVEN, ticks sections by rules that gate nothing, and
//         then blocks submission on exactly ONE field: the vehicle. So a form
//         reading "6/7 complete" can be submittable and a form reading "7/7" can
//         be refused. The redesign separates the one requirement from the seven
//         suggestions instead of averaging them into a number.
//
//      3. THE VEHICLE TWO-STEP IS KEPT AND MADE OBVIOUS.
//         Tapping a vehicle segment deliberately DISCARDS the value and raises a
//         confirmation, because that field sets mileage reimbursement. That is a
//         payroll safeguard, not friction, and it is the one place this family
//         gets something right. Note the edit screen has NO such guard on the
//         same field — recorded in the parity doc, not silently harmonised here.
//
//      4. THE MISSING STATES ARE DRAWN.
//         No draft, no autosave, no offline anything: leaving the standard form
//         discards everything typed. Drawn here as a PROPOSED draft strip, marked
//         as such, because adding real draft persistence is a data-layer change
//         and D12 puts that out of scope for this arc.
//
//  WHAT IS NOT BEING PROPOSED
//      No data layer, service, loader, business rule or permission changes (D12).
//      Thirty-six non-style defects were found while inventorying this family and
//      are recorded in AMB_BATCH2_PARITY.md. Several are severe — a submitted
//      photoshoot note deletes its only copy and the query that would fetch it
//      back cannot succeed. NONE of them is fixed by this phase. Where the mockup
//      draws a state that would need one of those fixes, it says PROPOSED.

import SwiftUI

// MARK: - Destinations

/// One enum, one `.ambientPush` — the AMB.3 rule.
private enum ReportsDestination: String, Identifiable {
    case standardForm
    case templatePicker
    case templateForm
    case notes
    case locationPhotos

    var id: String { rawValue }
}

// MARK: - Root

struct ReportsMockup: View {
    /// The paperwork family's colour (D11). Three adjacent blues for the three
    /// report features, so they read as one family.
    static let featureTint = Color(hex: "#3E63DD")

    /// The org flag that selects between two whole workflows.
    @State private var notesOnlyOrg = false
    @State private var search = ""
    @State private var window: ReportWindow = .all
    @State private var groupByTemplate = false
    @State private var destination: ReportsDestination?
    @State private var showEmpty = false

    private enum ReportWindow: String, CaseIterable, Identifiable {
        case all = "All"
        case week = "This Week"
        case month = "This Month"
        case thirty = "Last 30 Days"
        var id: String { rawValue }

        func contains(_ date: Date) -> Bool {
            let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
            switch self {
            case .all: return true
            case .week: return days <= 7
            case .month: return days <= 31
            case .thirty: return days <= 30
            }
        }
    }

    private var filtered: [LabJobReport] {
        DesignLabSampleData.jobReports.filter { report in
            guard window.contains(report.date) else { return false }
            guard !search.isEmpty else { return true }
            let haystack = [report.school, report.templateName ?? "", report.sessionName ?? ""]
                .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    todayLead
                    if !notesOnlyOrg {
                        searchField
                        filterRow
                        listSection
                    }
                    otherSurfaces
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .standardForm: DailyJobReportMockup()
            case .templatePicker: TemplatePickerMockup()
            case .templateForm: TemplateFormMockup()
            case .notes: PhotoshootNotesMockup(notesOnlyOrg: notesOnlyOrg)
            case .locationPhotos: LocationPhotosMockup()
            }
        }
    }

    // MARK: lab chrome

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · org workflow", trailing: "not a design element")
            Picker("Workflow", selection: $notesOnlyOrg) {
                Text("Reports org").tag(false)
                Text("Notes-only org").tag(true)
            }
            .pickerStyle(.segmented)
            Text(notesOnlyOrg
                 ? "usePhotoshootNotesOnly = true. The three report features are HIDDEN and Photoshoot Notes gains a submit button and a Submitted list."
                 : "usePhotoshootNotesOnly = false. Reports are visible and Photoshoot Notes is a local scratchpad that can only reach the server by being attached to a report.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Show empty state", isOn: $showEmpty)
                .font(.caption)
        }
    }

    // MARK: 1 — what today needs

    /// The claim: the first question this surface should answer is "have I filed
    /// today's report yet", and today nothing answers it. Auto-select already
    /// computes exactly this — it walks today's sessions and picks the first one
    /// you have NOT reported — but it does that silently inside a form you have
    /// to open first.
    private var todayLead: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Self.featureTint)
                Text("Today").font(.headline)
                Spacer(minLength: 0)
                Text(Formatters.monthDay.string(from: Date()))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }

            Text("2 sessions scheduled · 1 report filed")
                .font(.subheadline).foregroundStyle(.secondary)

            // The outstanding one, named. Not "file a report" — file THIS report.
            Button {
                destination = notesOnlyOrg ? .notes : .standardForm
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notesOnlyOrg ? "Riverside Middle — write the note" : "Riverside Middle — 3:30 PM")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(notesOnlyOrg ? "Fall Sports · not yet submitted" : "Fall Sports · not yet reported")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                // ambient-allow: a filled primary action is a control, not a card.
                .background(Capsule().fill(Self.featureTint))
            }
            .buttonStyle(.plain)

            if !notesOnlyOrg {
                Button { destination = .templatePicker } label: {
                    Label("Use a template instead", systemImage: "doc.text.below.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Self.featureTint)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .hero, state: .highlighted, glow: Self.featureTint, fillWidth: true)
    }

    // MARK: 2 — search, which exists only in the orphaned screen today

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search reports", text: $search)
                .font(.subheadline)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReportWindow.allCases) { option in
                        Button {
                            withAnimation(AmbientMotion.snappy) { window = option }
                            AmbientHaptics.selection()
                        } label: {
                            Text(option.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(window == option ? .white : .primary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                // ambient-allow: a selection chip is a control.
                                .background(Capsule().fill(window == option
                                                           ? AnyShapeStyle(Self.featureTint)
                                                           : AnyShapeStyle(.ultraThinMaterial)))
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(window == option ? 0 : 0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)

            Toggle(isOn: $groupByTemplate) {
                Text("Group by template").font(.caption)
            }
            .toggleStyle(.switch)
            .tint(Self.featureTint)
        }
    }

    // MARK: 3 — the list

    @ViewBuilder
    private var listSection: some View {
        if showEmpty {
            // The state MyJobReportsView does not have at all: today an empty
            // list and a failed query are the same blank screen.
            AmbientEmptyState(
                title: "No Reports Yet",
                message: "Reports you file will be listed here. Start with today's session.",
                systemImage: "doc.text",
                actionTitle: "File Today's Report",
                actionIcon: "plus.circle.fill",
                action: { destination = .standardForm },
                actionTint: Self.featureTint)
        } else if filtered.isEmpty {
            // A search that matches nothing is a DIFFERENT state, and the
            // orphaned screen gets this wrong too — it branches on the raw fetch
            // rather than the filtered set, so a non-matching search renders a
            // blank scroll view with no message.
            AmbientEmptyState(
                title: "No matching reports",
                message: "Nothing matches \"\(search)\" in this window.",
                systemImage: "magnifyingglass")
        } else if groupByTemplate {
            grouped
        } else {
            flat
        }
    }

    private var flat: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Filed reports", trailing: "\(filtered.count)")
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(filtered) { report in
                    ReportRow(report: report)
                        .ambientScrollFade()
                }
            }
        }
    }

    /// Grouping by template, with "Standard reports" for everything that has no
    /// template — the orphaned screen calls that group "Legacy Reports", which is
    /// a word for the developer rather than the photographer.
    private var grouped: some View {
        let groups = Dictionary(grouping: filtered) { $0.templateName ?? "Standard reports" }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(groups.keys.sorted(), id: \.self) { key in
                VStack(alignment: .leading, spacing: 8) {
                    AmbientSectionTitle(key, trailing: "\(groups[key]?.count ?? 0)")
                    LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                        ForEach(groups[key] ?? []) { report in
                            ReportRow(report: report)
                        }
                    }
                }
            }
        }
    }

    // MARK: 4 — the rest of the family

    private var otherSurfaces: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("The rest of batch 2")
            VStack(spacing: AmbientDensity.compact.stackSpacing) {
                surfaceRow("Photoshoot Notes", "note.text", Color(hex: "#6E56CF"),
                           notesOnlyOrg ? "Submits to the server in this org" : "Local scratchpad in this org") {
                    destination = .notes
                }
                surfaceRow("Location Photos", "photo.on.rectangle.angled", Color(hex: "#8E4EC6"),
                           "Add-only — deleting lives in Settings") {
                    destination = .locationPhotos
                }
                if !notesOnlyOrg {
                    surfaceRow("Template form", "list.bullet.rectangle", Color(hex: "#5471E0"),
                               "Every field type the dynamic form can render") {
                        destination = .templateForm
                    }
                }
            }
        }
    }

    private func surfaceRow(_ title: String, _ icon: String, _ tint: Color,
                            _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AmbientDensity.compact.titleFont)
                    Text(detail).font(AmbientDensity.compact.subtitleFont).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - A report row

/// The live row today is: date, school (always drawn even when the column is
/// null), "Mileage: N", and a photo pill. It cannot tell a template report from a
/// standard one — that distinction exists only in the orphaned list.
private struct ReportRow: View {
    let report: LabJobReport
    private var density: AmbientDensity { .compact }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Text(Formatters.dayNumber.string(from: report.date))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(Formatters.weekdayShort.string(from: report.date).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                // The sparse case is real: a report can carry no school at all,
                // and the row still has to read.
                Text(report.school.isEmpty ? "No school recorded" : report.school)
                    .font(density.titleFont)
                    .foregroundStyle(report.school.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                if let session = report.sessionName {
                    Text(session)
                        .font(density.subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    // Off-schedule is a real and common case, and saying so is
                    // more useful than leaving the line blank.
                    Text("Off-schedule")
                        .font(density.subtitleFont)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 6) {
                    if report.mileage > 0 {
                        metric(String(format: "%.1f mi", report.mileage), "car.fill")
                    }
                    if report.photoCount > 0 {
                        metric("\(report.photoCount)", "photo.fill")
                    }
                    if report.vehicle == "company" {
                        AmbientBadge(text: "Company", tint: .teal)
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 0)

            if report.isTemplate {
                VStack(alignment: .trailing, spacing: 3) {
                    AmbientBadge(text: "Template", systemImage: "doc.text.below.ecg", tint: ReportsMockup.featureTint)
                    if report.smartFieldCount > 0 {
                        Text("\(report.smartFieldCount) auto")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .ambientCard(density: density, fillWidth: true)
    }

    private func metric(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.secondary)
    }
}// MARK: - The standard daily job report

/// THE ONE THAT HAS TO BE FILLED IN. Every control here is live.
///
/// TWO CORRECTIONS FROM THE OPERATOR, both recorded so the next person does not
/// re-make them:
///
///   1. The first cut was a SPECIMEN — eight sections with their values already
///      in place and nothing you could touch. Wrong thing to judge. This is the
///      surface a photographer completes at the end of every shoot, so the only
///      question worth asking is what COMPLETING it feels like.
///
///   2. The second cut folded the date, name, session, school and mileage into
///      one "we filled this in" card, on the theory that the app already knows
///      them. The operator's answer was that this is not how their reports work.
///      That theory came from reading what the form CAN do, not from how a day
///      actually goes — which is exactly the assumption the arc keeps being
///      burned by. THE FOLD IS GONE. School and mileage are first-class,
///      visible, and filled with sample data like everything else.
///
/// SO THE SCHOOL PICKER IS THE CENTRE OF THIS SCREEN, NOT A DERIVED FIELD.
/// A report can carry SEVERAL schools — the live form supports that through an
/// "Add School" button, which the previous cut had hidden behind the
/// no-session branch. Here it is always available, stops can be removed, and
/// the mileage RESPONDS: add a school and the number moves, because "does the
/// mileage update when I add a stop" is a real question about this screen.
///
/// STILL OPEN, and the operator is the only one who can settle it: whether a
/// scheduled session is usually there to attach to, whether a normal day is one
/// school or several, and how much of the mileage is typed by hand. The design
/// below assumes NOTHING is pre-filled from the schedule — session is an
/// optional link you may set, not the thing the report is built from.
///
/// WHAT IS KEPT EXACTLY
///     All 22 job descriptions and all 12 extra items, verbatim, in the shipped
///     order. The three scan radios with their real options and real defaults.
///     The two-step vehicle confirmation and its exact wording. The fact that
///     the vehicle is the ONLY thing that blocks submission. Submit in the nav
///     bar. Multiple schools per report.
private struct DailyJobReportMockup: View {

    @State private var reportDate = Date()
    @State private var photographer = "Maria Alvarez"
    @State private var sessionLabel: String?

    /// Several stops per report is normal, so this is an array, not a value.
    @State private var stops: [LabSchool] = [DesignLabSampleData.schools[1]]
    @State private var showSchoolPicker = false

    /// Typed mileage must WIN. In the live app a recalculation silently
    /// overwrites what you typed, and clears it entirely if you have no home
    /// address set. Here an override sticks and says so.
    @State private var mileageOverride: String?

    @State private var jobDescriptions: Set<String> = []
    @State private var extraItems: Set<String> = []
    @State private var cardsScanned: String?
    @State private var jobBox: String? = "NA"
    @State private var sportsBackground: String? = "NA"
    @State private var notes = ""
    @State private var photos: [Color] = []
    @State private var showAllDescriptions = false
    @State private var showAllExtras = false

    @State private var vehicle = ""
    @State private var showVehicleConfirm = false

    @State private var submitted = false
    @State private var lastEdit = Date()

    private var computedMiles: Double { DesignLabSampleData.routeMiles(stops) }
    private var mileageText: String {
        mileageOverride ?? String(format: "%.1f", computedMiles)
    }
    private var canSubmit: Bool { !vehicle.isEmpty }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: ReportsMockup.featureTint, intensity: 0.7)
            if submitted { successState } else { form }
        }
        .navigationTitle("Daily Job Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Submit") {
                    withAnimation(AmbientMotion.gentle) { submitted = true }
                    AmbientHaptics.impact(.medium)
                }
                .font(.body.weight(.semibold))
                .disabled(!canSubmit)
            }
        }
        .sheet(isPresented: $showSchoolPicker) { schoolPicker }
        .confirmationDialog("Confirm Vehicle", isPresented: $showVehicleConfirm, titleVisibility: .visible) {
            Button("Personal") { commitVehicle("personal") }
            Button("Company") { commitVehicle("company") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select the vehicle again to confirm — this sets your mileage reimbursement and can't be changed by an accidental tap.")
        }
    }

    private func commitVehicle(_ value: String) {
        withAnimation(AmbientMotion.snappy) { vehicle = value }
        lastEdit = Date()
        AmbientHaptics.impact(.medium)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                draftStrip
                basicsSection
                schoolsSection
                mileageSection
                questionsHeader
                shotSection
                extrasSection
                scanSection
                notesSection
                photosSection
                vehicleSection
                submitFooter
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
    }

    // MARK: draft

    /// PROPOSED. There is no draft and no autosave in the live form — every
    /// field is plain view state, so leaving the screen (including the jump to
    /// Home the app performs after submitting) discards everything typed.
    private var draftStrip: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.caption.weight(.semibold))
            Text("Draft saved ").font(.caption.weight(.semibold))
                + Text(lastEdit, style: .relative).font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Text("PROPOSED").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .ambientCard(density: .compact, border: .dashed(Color.secondary.opacity(0.35)), fillWidth: true)
    }

    // MARK: 1 — the basics

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("The basics")
            VStack(spacing: 0) {
                HStack {
                    Label("Date", systemImage: "calendar")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: $reportDate, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.vertical, 6)

                Divider()

                HStack {
                    Label("Your name", systemImage: "person")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $photographer) {
                        ForEach(DesignLabSampleData.crew.map(\.name), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .padding(.vertical, 6)

                Divider()

                // An OPTIONAL link, not the thing the report is built from.
                // Whether a session is usually there is the operator's question
                // to answer — the design does not depend on it either way.
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Session", systemImage: "clock")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $sessionLabel) {
                            Text("Not linked").tag(String?.none)
                            Text("Riverside Middle — 3:30 PM")
                                .tag(String?.some("Riverside Middle — 3:30 PM (Fall Sports)"))
                            Text("Lincoln High — 7:45 AM")
                                .tag(String?.some("Lincoln High — 7:45 AM (Fall Original)"))
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    Text("Optional. Linking a session is how the report gets tied to the schedule — it does not lock anything below.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    // MARK: 2 — schools, as many as the day had

    private var schoolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Schools", trailing: stops.isEmpty ? nil : "\(stops.count)")

            VStack(alignment: .leading, spacing: 8) {
                if stops.isEmpty {
                    Text("No schools yet. A report can cover as many as the day had.")
                        .font(.subheadline).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, school in
                        stopRow(school, index: index)
                        if index < stops.count - 1 { Divider() }
                    }
                }

                Button { showSchoolPicker = true } label: {
                    Label("Add School", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ReportsMockup.featureTint)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    private func stopRow(_ school: LabSchool, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Stop order matters — it is what the route is computed along.
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(ReportsMockup.featureTint))

            VStack(alignment: .leading, spacing: 2) {
                Text(school.name)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(school.address).font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(AmbientMotion.snappy) {
                    stops.removeAll { $0.id == school.id }
                }
                lastEdit = Date()
                AmbientHaptics.impact(.light)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    /// A searchable sheet, matching the picker the rest of the app already uses
    /// rather than the plain menu Photoshoot Notes grew its own version of.
    private var schoolPicker: some View {
        SchoolPickerSheet(
            chosen: stops.map(\.id),
            onPick: { school in
                withAnimation(AmbientMotion.snappy) { stops.append(school) }
                lastEdit = Date()
                showSchoolPicker = false
            },
            onCancel: { showSchoolPicker = false })
    }

    // MARK: 3 — mileage

    private var mileageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Mileage")
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Total").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    TextField("0.0", text: Binding(
                        get: { mileageText },
                        set: { mileageOverride = $0; lastEdit = Date() }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(width: 92)
                    Text("miles").font(.subheadline).foregroundStyle(.secondary)
                }

                Divider()

                if let override = mileageOverride, !override.isEmpty {
                    // The behaviour the live app gets wrong: a typed value is
                    // silently replaced the next time anything recalculates.
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "hand.raised.fill").font(.caption2.weight(.bold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You typed this. It will not be overwritten.")
                                .font(.caption.weight(.semibold))
                            Text("The route works out to \(computedMiles, specifier: "%.1f") miles.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(AmbientMotion.snappy) { mileageOverride = nil }
                        } label: {
                            Text("Use route").font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.orange)
                } else if stops.isEmpty {
                    Text("Add a school and the route is calculated from home and back.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Calculated from your route").font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(routeDescription)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    private var routeDescription: String {
        (["Home"] + stops.map(\.name) + ["Home"]).joined(separator: " → ")
    }

    // MARK: 4 — the questions

    private var questionsHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("The rest of the report").font(.headline)
            Text("None of this is required — the vehicle at the bottom is the only thing that is.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var shotSection: some View {
        questionCard(number: 1, title: "What did you shoot?", tint: .orange,
                     count: jobDescriptions.count) {
            VStack(alignment: .leading, spacing: 10) {
                optionGrid(DesignLabSampleData.jobDescriptionOptions,
                           selection: $jobDescriptions, expanded: $showAllDescriptions,
                           collapsedCount: 8, tint: .orange)
                noneWarning(jobDescriptions)
            }
        }
    }

    private var extrasSection: some View {
        questionCard(number: 2, title: "Anything extra, not on the schedule?", tint: .pink,
                     count: extraItems.count) {
            VStack(alignment: .leading, spacing: 10) {
                optionGrid(DesignLabSampleData.extraItemOptions,
                           selection: $extraItems, expanded: $showAllExtras,
                           collapsedCount: 6, tint: .pink)
                noneWarning(extraItems)
            }
        }
    }

    private var scanSection: some View {
        questionCard(number: 3, title: "Cards and job box", tint: .teal,
                     count: [cardsScanned, jobBox, sportsBackground].compactMap { $0 }.count,
                     countSuffix: " of 3") {
            VStack(alignment: .leading, spacing: 12) {
                radioRow("Cards scanned", ["Yes", "No"], $cardsScanned)
                radioRow("Job box and camera cards turned in", ["Yes", "No", "NA"], $jobBox)
                radioRow("Sports background shot", ["Yes", "No", "NA"], $sportsBackground)
                Text("Two of these arrive answered as NA, and none can be cleared once tapped — both are the live form's behaviour, kept.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notesSection: some View {
        questionCard(number: 4, title: "Anything worth writing down?", tint: .indigo,
                     count: notes.isEmpty ? 0 : 1,
                     countSuffix: notes.isEmpty ? "" : " note") {
            TextEditor(text: $notes)
                .frame(minHeight: 90)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .padding(8)
                // ambient-allow: an input well, not a card.
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.1)))
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Bent stand, a student missed the session, anything the lab or the next photographer needs.")
                            .font(.subheadline).foregroundStyle(.tertiary)
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var photosSection: some View {
        questionCard(number: 5, title: "Photos", tint: .red, count: photos.count) {
            VStack(alignment: .leading, spacing: 8) {
                if photos.isEmpty {
                    Button { addPhoto() } label: {
                        Label("Add Photos", systemImage: "photo.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            // ambient-allow: a control, not a card.
                            .background(Capsule().fill(Color.red))
                    }
                    .buttonStyle(.plain)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, colour in
                            photoTile(colour, index: index)
                        }
                        Button { addPhoto() } label: {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.4),
                                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .frame(height: 92)
                                .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(.secondary))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") selected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("One image per pick, photo library only — there is no camera on this screen.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func photoTile(_ colour: Color, index: Int) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(colour.opacity(0.35))
            .frame(height: 92)
            .overlay(Image(systemName: "photo").font(.title3).foregroundStyle(colour))
            .overlay(alignment: .topTrailing) {
                Button {
                    // `remove(at:)` returns the element, which would make this
                    // closure non-Void and the animation's result unused.
                    withAnimation(AmbientMotion.snappy) { _ = photos.remove(at: index) }
                    AmbientHaptics.impact(.light)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(5)
                }
                .buttonStyle(.plain)
            }
    }

    private func addPhoto() {
        let palette: [Color] = [.blue, .green, .orange, .purple, .teal, .pink]
        withAnimation(AmbientMotion.snappy) { photos.append(palette[photos.count % palette.count]) }
        lastEdit = Date()
        AmbientHaptics.impact(.light)
    }

    // MARK: 5 — the one requirement

    private var vehicleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: vehicle.isEmpty ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(vehicle.isEmpty ? .orange : .green)
                Text("Vehicle").font(.headline)
                AmbientBadge(text: "Required", tint: .orange)
                Spacer(minLength: 0)
            }
            Text(vehicle.isEmpty
                 ? "The only thing on this form that has to be answered. It sets your mileage reimbursement."
                 : "Set to \(vehicle.capitalized). Tap again to change it — it will ask you to confirm.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                vehicleButton("Personal", "car.fill")
                vehicleButton("Company", "bus.fill")
            }
            if vehicle.isEmpty {
                Text("Tap a vehicle, then confirm the selection. The first tap deliberately does not commit it.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ambientCard(density: .hero, state: .highlighted,
                     glow: vehicle.isEmpty ? .orange : .green, fillWidth: true)
    }

    private func vehicleButton(_ title: String, _ icon: String) -> some View {
        let selected = vehicle == title.lowercased()
        return Button {
            showVehicleConfirm = true
            AmbientHaptics.impact(.light)
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                // ambient-allow: a segmented control, not a container.
                .background(Capsule().fill(selected
                                           ? AnyShapeStyle(ReportsMockup.featureTint)
                                           : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 6 — submit

    private var submitFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: canSubmit ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(canSubmit ? .green : .secondary)
                Text(canSubmit ? "Ready to submit" : "Pick a vehicle to submit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(canSubmit ? .green : .secondary)
                Spacer(minLength: 0)
            }
            Text("Submit is in the navigation bar, top right — as it is today. Nothing else blocks it: no school, no mileage, no job descriptions, no scan answers.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, fillWidth: true)
        .padding(.bottom, 8)
    }

    // MARK: success

    private var successState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52)).foregroundStyle(.green)
                Text("Report submitted").font(.title3.weight(.semibold))
                Text(Formatters.mediumDate.string(from: reportDate))
                    .font(.subheadline).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 5) {
                    summaryLine("Schools", stops.isEmpty ? "None" : stops.map(\.name).joined(separator: ", "))
                    summaryLine("Mileage", "\(mileageText) mi · \(vehicle.capitalized)")
                    summaryLine("Shot", jobDescriptions.isEmpty ? "Nothing ticked" : jobDescriptions.sorted().joined(separator: ", "))
                    if !extraItems.isEmpty {
                        summaryLine("Extra", extraItems.sorted().joined(separator: ", "))
                    }
                    summaryLine("Photos", photos.isEmpty ? "None" : "\(photos.count)")
                }
                .ambientCard(density: .roomy, fillWidth: true)
                .padding(.top, 4)

                Button {
                    withAnimation(AmbientMotion.gentle) { submitted = false }
                } label: {
                    Text("Fill in another")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        // ambient-allow: a control.
                        .background(Capsule().fill(ReportsMockup.featureTint))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
    }

    private func summaryLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Text(value).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: shared question chrome

    private func questionCard<Content: View>(
        number: Int, title: String, tint: Color, count: Int,
        countSuffix: String = "", @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(tint))
                Text(title).font(AmbientDensity.roomy.titleFont)
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)\(countSuffix)")
                        .font(.caption.weight(.bold)).foregroundStyle(tint)
                        .contentTransition(.numericText())
                }
            }
            content()
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// Every option is still here and still reachable — the fold is a default,
    /// not a filter — and anything already ticked is always shown regardless of
    /// where it sits, so a fold can never hide your own answer.
    private func optionGrid(_ options: [String], selection: Binding<Set<String>>,
                            expanded: Binding<Bool>, collapsedCount: Int, tint: Color) -> some View {
        let visible: [String] = expanded.wrappedValue
            ? options
            : options.enumerated()
                .filter { $0.offset < collapsedCount || selection.wrappedValue.contains($0.element) }
                .map(\.element)

        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)], spacing: 9) {
                ForEach(visible, id: \.self) { option in
                    checkbox(option, selection: selection, tint: tint)
                }
            }
            if options.count > visible.count || expanded.wrappedValue {
                Button {
                    withAnimation(AmbientMotion.snappy) { expanded.wrappedValue.toggle() }
                } label: {
                    Text(expanded.wrappedValue ? "Show fewer" : "Show all \(options.count)")
                        .font(.caption.weight(.semibold)).foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func checkbox(_ option: String, selection: Binding<Set<String>>, tint: Color) -> some View {
        let on = selection.wrappedValue.contains(option)
        return Button {
            withAnimation(AmbientMotion.snappy) {
                if on { selection.wrappedValue.remove(option) }
                else { selection.wrappedValue.insert(option) }
            }
            lastEdit = Date()
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(on ? tint : .secondary)
                Text(option)
                    .font(.caption).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            // The whole row is the target. In the live edit screen the tap
            // gesture is on the ICON only — a 20pt target in a two-column grid.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "NONE" is an ordinary option in both lists with no exclusivity logic, so
    /// it can be ticked alongside six other things and the report is stored
    /// saying both. This does not change that — exclusivity is a data rule and
    /// out of scope (D12) — it stops the screen being silent about it.
    @ViewBuilder
    private func noneWarning(_ selection: Set<String>) -> some View {
        if selection.contains("NONE") && selection.count > 1 {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2.weight(.bold))
                Text("\"NONE\" is ticked along with \(selection.count - 1) other item\(selection.count == 2 ? "" : "s"). The report will be saved saying both.")
                    .font(.caption2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.orange)
        }
    }

    private func radioRow(_ title: String, _ options: [String], _ selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    Button {
                        withAnimation(AmbientMotion.snappy) { selection.wrappedValue = option }
                        lastEdit = Date()
                        AmbientHaptics.selection()
                    } label: {
                        Text(option)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selection.wrappedValue == option ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            // ambient-allow: a radio control, not a container.
                            .background(Capsule().fill(selection.wrappedValue == option
                                                       ? AnyShapeStyle(Color.teal)
                                                       : AnyShapeStyle(.ultraThinMaterial)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(
                                selection.wrappedValue == option ? 0 : 0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - School picker

/// Searchable, matching the picker the report form already uses today rather
/// than the plain menu Photoshoot Notes grew its own version of. Schools already
/// on the report are shown as chosen and cannot be added twice.
private struct SchoolPickerSheet: View {
    let chosen: [String]
    let onPick: (LabSchool) -> Void
    let onCancel: () -> Void

    @State private var search = ""

    private var results: [LabSchool] {
        let all = DesignLabSampleData.schools.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.address.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if results.isEmpty {
                    AmbientEmptyState(
                        title: "No schools found",
                        message: "Nothing matches \"\(search)\".",
                        systemImage: "magnifyingglass")
                } else {
                    List(results) { school in
                        Button { onPick(school) } label: { row(school) }
                            .buttonStyle(.plain)
                            .disabled(chosen.contains(school.id))
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $search, prompt: "Search schools")
            .navigationTitle("Add School")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func row(_ school: LabSchool) -> some View {
        let already = chosen.contains(school.id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(school.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(already ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(school.address).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if already {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.green)
            } else {
                Text("\(school.milesFromHome, specifier: "%.1f") mi")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Template picker

private struct TemplatePickerMockup: View {
    @State private var search = ""
    @State private var decoded = true
    /// One enum-free push is fine here: there is exactly ONE destination, and
    /// the item itself carries which template was chosen.
    @State private var opening: LabReportTemplate?

    /// The live app never decodes six of a template's properties, so every card
    /// shows "No description available", every version reads v1, no DEFAULT badge
    /// can ever appear, and every template falls into ONE category with a BLANK
    /// header. This toggle shows both, because the design has to be judged on
    /// what it looks like TODAY as well as after that is fixed.
    private var templates: [LabReportTemplate] {
        DesignLabSampleData.reportTemplates.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Color(hex: "#5471E0"), intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    searchField
                    if decoded { groupedByType } else { flatUndecoded }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Custom Daily Reports")
        .navigationBarTitleDisplayMode(.inline)
        .ambientPush(item: $opening) { template in
            TemplateFormMockup(template: template)
        }
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · template fields", trailing: "not a design element")
            Picker("Decoded", selection: $decoded) {
                Text("As designed").tag(true)
                Text("As it ships today").tag(false)
            }
            .pickerStyle(.segmented)
            Text(decoded
                 ? "Description, shoot type, default flag and version all decoded."
                 : "Six model properties sit outside CodingKeys, so none of them is ever decoded. This is what every org sees. See AMB_BATCH2_PARITY.md finding R13.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Search templates", text: $search).font(.subheadline).textFieldStyle(.plain)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var groupedByType: some View {
        let groups = Dictionary(grouping: templates) { $0.shootType.capitalized }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(groups.keys.sorted(), id: \.self) { key in
                VStack(alignment: .leading, spacing: 8) {
                    AmbientSectionTitle(key, trailing: "\(groups[key]?.count ?? 0)")
                    VStack(spacing: AmbientDensity.compact.stackSpacing) {
                        ForEach(groups[key] ?? []) { template in
                            templateRow(template, showDetail: true)
                        }
                    }
                }
            }
        }
    }

    private var flatUndecoded: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The blank category header the live app draws — an empty string
            // capitalized is still an empty string, so this is a gap with a
            // count pill floating beside it.
            AmbientSectionTitle(" ", trailing: "\(templates.count)")
            VStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(templates) { template in
                    templateRow(template, showDetail: false)
                }
            }
        }
    }

    /// A ROW, not a 160pt card in a two-column grid.
    ///
    /// The live screen uses a fixed-height two-column grid on iPhone AND iPad
    /// alike, which forces the title to two lines with a scale factor and leaves
    /// most of each card empty. Templates are a list you pick one item from, and
    /// a list row reads faster and survives a long name.
    private func templateRow(_ template: LabReportTemplate, showDetail: Bool) -> some View {
        Button { opening = template } label: { templateRowLabel(template, showDetail: showDetail) }
            .buttonStyle(.plain)
    }

    private func templateRowLabel(_ template: LabReportTemplate, showDetail: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#5471E0"))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(template.name).font(AmbientDensity.compact.titleFont)
                    if showDetail && template.isDefault {
                        AmbientBadge(text: "Default", tint: .green)
                    }
                }
                if showDetail, let detail = template.detail {
                    Text(detail)
                        .font(AmbientDensity.compact.subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("No description available")
                        .font(AmbientDensity.compact.subtitleFont)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
                HStack(spacing: 8) {
                    Text("\(template.fieldCount) fields")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    if template.smartFieldCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold))
                            Text("\(template.smartFieldCount) auto")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Color(hex: "#5471E0"))
                    }
                    Spacer(minLength: 0)
                    Text("v\(showDetail ? template.version : 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact,
                     border: showDetail && template.isDefault ? .hairline(Color.green.opacity(0.4)) : .none,
                     fillWidth: true)
    }
}
// MARK: - Template form

/// THE SECOND REPORT TYPE, and fillable for the same reason the first one is:
/// an operator cannot tell whether a form works by looking at a picture of it.
///
/// Drawn against EVERY field type the template engine can render rather than a
/// convenient three, because a template is authored in the web app and this
/// screen has to survive whatever comes back. Fourteen render types plus the
/// unknown-type fallback are all here and all live.
///
/// THE ONE THING THIS DESIGN ADDS: WHY SUBMIT IS DISABLED.
///     The live form disables Submit whenever any field fails validation and
///     says NOTHING — no per-field error, no message, just a greyed button at
///     60% opacity. With required fields scattered across four auto-generated
///     sections, a photographer can be left tapping a dead button with no way to
///     find out which field is the problem. The strip above the button lists
///     them and scrolls you to them.
///
/// Field types marked with the lab toggle are the four that are BROKEN in the
/// live app in ways that make the form permanently unsubmittable. This mockup
/// implements them CORRECTLY — an optional number left blank does not block
/// submission here — so the design can be judged on what it should be, while
/// the toggle still shows where the real defects are.
private struct TemplateFormMockup: View {
    var template: LabReportTemplate?

    @State private var text: [String: String] = [:]
    @State private var multi: [String: Set<String>] = [:]
    @State private var flags: [String: Bool] = [:]
    @State private var dates: [String: Date] = [:]
    @State private var photos: [Color] = []
    @State private var showBroken = false
    @State private var submitted = false

    private var fields: [(type: String, label: String, required: Bool, readOnly: Bool)] {
        DesignLabSampleData.templateFieldTypes
    }

    private var title: String { template?.name ?? "Sports Day" }
    private var version: Int { template?.version ?? 3 }

    /// The real rule, kept: a template report requires EVERY field to validate,
    /// unlike the standard report which requires only the vehicle.
    private var unfinished: [(type: String, label: String, required: Bool, readOnly: Bool)] {
        fields.filter { !isValid($0) }
    }

    private func isValid(_ field: (type: String, label: String, required: Bool, readOnly: Bool)) -> Bool {
        guard field.required, !field.readOnly else { return true }
        switch field.type {
        case "multiselect":
            return !(multi[field.type] ?? []).isEmpty
        case "toggle":
            return true
        case "file":
            return !photos.isEmpty
        case "date", "time":
            return dates[field.type] != nil
        case "email":
            let value = text[field.type] ?? ""
            return value.contains("@") && value.contains(".")
        default:
            return !(text[field.type] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Color(hex: "#5471E0"), intensity: 0.7)
            if submitted { successState } else { form }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Submit") {
                    withAnimation(AmbientMotion.gentle) { submitted = true }
                    AmbientHaptics.impact(.medium)
                }
                .font(.body.weight(.semibold))
                .disabled(!unfinished.isEmpty)
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                labControl
                header
                blockingStrip
                section("Basic Information", ["user_name", "date_auto", "time_auto"])
                section("Calculated Fields", ["school_name", "mileage", "photo_count", "weather_conditions"])
                section("Media & Location", ["file"])
                section("Report Details", ["text", "email", "phone", "number", "currency",
                                          "select", "multiselect", "radio", "toggle",
                                          "date", "time", "textarea"])
                footerNote
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · field defects", trailing: "not a design element")
            Toggle("Mark the field types that are broken today", isOn: $showBroken)
                .font(.caption)
        }
    }

    /// The live screen fakes a nav bar with a blue gradient because it is a
    /// sheet with no navigation container. Here it is a real pushed screen with
    /// a real bar — one fewer bespoke thing to maintain, and Submit sits where
    /// it sits on the standard report.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(fields.count) fields · \(fields.filter(\.readOnly).count) automatic")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("v\(version)").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            Text("Every field must pass before this form will submit — including the automatic ones you cannot edit. That is the live rule, and it is why the strip below exists.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// The state that should exist and does not.
    @ViewBuilder
    private var blockingStrip: some View {
        if unfinished.isEmpty {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Ready to submit").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                Spacer(minLength: 0)
            }
            .ambientCard(density: .compact, fillWidth: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("\(unfinished.count) field\(unfinished.count == 1 ? "" : "s") still needed")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.orange)
                AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(unfinished, id: \.type) { field in
                        AmbientBadge(text: field.label, tint: .orange)
                    }
                }
                Text("Today the button simply greys out and says nothing, with the failing field possibly in a section you have not scrolled to.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ambientCard(density: .compact,
                         border: .hairline(Color.orange.opacity(0.4)), fillWidth: true)
        }
    }

    /// Sections are auto-derived from field TYPES and rendered ALPHABETICALLY —
    /// which is why Basic Information precedes Report Details by accident rather
    /// than design. Kept as-is so the operator can see it and decide.
    private func section(_ name: String, _ types: [String]) -> some View {
        let list = fields.filter { types.contains($0.type) }
        return VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle(name, trailing: "\(list.count)")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(list, id: \.type) { field in
                    fieldRow(field)
                }
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    private func fieldRow(_ field: (type: String, label: String, required: Bool, readOnly: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(field.label).font(.subheadline.weight(.medium))
                if field.required {
                    Text("*").font(.subheadline.weight(.bold)).foregroundStyle(.red)
                }
                if field.readOnly { AmbientBadge(text: "Auto", tint: .blue) }
                Spacer(minLength: 0)
                Text(field.type)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            control(field)

            if showBroken, let note = defect(field.type) {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9, weight: .bold))
                    Text(note).font(.caption2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func control(_ field: (type: String, label: String, required: Bool, readOnly: Bool)) -> some View {
        switch field.type {
        case "user_name", "date_auto", "time_auto", "school_name", "mileage",
             "photo_count", "weather_conditions":
            readOnlyWell(autoValue(field.type))

        case "textarea":
            TextEditor(text: binding(field.type))
                .frame(minHeight: 74)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .padding(8)
                // ambient-allow: an input well, not a card.
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1)))

        case "number", "currency":
            TextField(field.type == "currency" ? "0.00" : "0", text: binding(field.type))
                .keyboardType(.decimalPad)
                .font(.subheadline)
                .padding(.horizontal, 10).padding(.vertical, 9)
                // ambient-allow: an input well, not a card.
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1)))

        case "select":
            Picker("", selection: binding(field.type)) {
                Text("Select \(field.label.lowercased())").tag("")
                ForEach(["Football", "Volleyball", "Cross country", "Cheer"], id: \.self) {
                    Text($0).tag($0)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

        case "multiselect":
            VStack(alignment: .leading, spacing: 6) {
                ForEach(["Basic", "Deluxe", "Team photo", "Digital download"], id: \.self) { option in
                    multiRow(option, key: field.type)
                }
            }

        case "radio":
            HStack(spacing: 6) {
                ForEach(["Yes", "No", "NA"], id: \.self) { option in
                    let on = text[field.type] == option
                    Button {
                        withAnimation(AmbientMotion.snappy) { text[field.type] = option }
                        AmbientHaptics.selection()
                    } label: {
                        Text(option)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(on ? .white : .primary)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            // ambient-allow: a radio control, not a container.
                            .background(Capsule().fill(on
                                                       ? AnyShapeStyle(Color(hex: "#5471E0"))
                                                       : AnyShapeStyle(.ultraThinMaterial)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }

        case "toggle":
            Toggle("", isOn: Binding(
                get: { flags[field.type] ?? false },
                set: { flags[field.type] = $0 }))
                .labelsHidden()
                .tint(Color(hex: "#5471E0"))

        case "date", "time":
            DatePicker("", selection: Binding(
                get: { dates[field.type] ?? Date() },
                set: { dates[field.type] = $0 }),
                displayedComponents: field.type == "date" ? .date : .hourAndMinute)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

        case "file":
            filePicker

        default:
            TextField("Enter \(field.label.lowercased())", text: binding(field.type))
                .font(.subheadline)
                .padding(.horizontal, 10).padding(.vertical, 9)
                // ambient-allow: an input well, not a card.
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1)))
        }
    }

    private var filePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if photos.isEmpty {
                Button { addPhoto() } label: {
                    Label("Add Photos", systemImage: "photo.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: "#5471E0"))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        // ambient-allow: a control, not a card.
                        .background(Capsule().fill(Color(hex: "#5471E0").opacity(0.13)))
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, colour in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(colour.opacity(0.35))
                            .frame(height: 78)
                            .overlay(Image(systemName: "photo").foregroundStyle(colour))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    withAnimation(AmbientMotion.snappy) { _ = photos.remove(at: index) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                            }
                    }
                    Button { addPhoto() } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.4),
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(height: 78)
                            .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Photos are shared across every file field on a template — they are not stored per field.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addPhoto() {
        let palette: [Color] = [.blue, .green, .orange, .purple, .teal, .pink]
        withAnimation(AmbientMotion.snappy) { photos.append(palette[photos.count % palette.count]) }
        AmbientHaptics.impact(.light)
    }

    private func multiRow(_ option: String, key: String) -> some View {
        let on = (multi[key] ?? []).contains(option)
        return Button {
            withAnimation(AmbientMotion.snappy) {
                var set = multi[key] ?? []
                if on { set.remove(option) } else { set.insert(option) }
                multi[key] = set
            }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(on ? Color(hex: "#5471E0") : .secondary)
                Text(option).font(.caption)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { text[key] ?? "" }, set: { text[key] = $0 })
    }

    private func readOnlyWell(_ value: String) -> some View {
        Text(value)
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 9)
            // ambient-allow: a read-only input well, not a card.
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1)))
    }

    /// Note that photo_count is LIVE — add a photo above and this moves, which
    /// is the one smart field the live form does keep up to date.
    private func autoValue(_ type: String) -> String {
        switch type {
        case "user_name": return "Maria Alvarez"
        case "date_auto": return Formatters.shortDate.string(from: Date())
        case "time_auto": return Formatters.shortTime.string(from: Date())
        case "school_name": return "No schools selected"
        case "mileage": return "0.0"
        case "photo_count": return "\(photos.count)"
        case "weather_conditions": return "Weather loading..."
        default: return ""
        }
    }

    private func defect(_ type: String) -> String? {
        switch type {
        case "number":
            return "An untouched number field fails validation even when optional, so Submit stays disabled forever. Implemented correctly here. Finding R15."
        case "file":
            return "A required file field can never be satisfied — photos are never written to the field's own key. Implemented correctly here. Finding R14."
        case "school_name", "mileage":
            return "This form has no school picker at all, so this always renders the fallback. Finding R17."
        case "weather_conditions":
            return "Never actually calculated. This placeholder string is what gets SAVED into the report. Finding R16."
        case "date":
            return "The picker snaps back to today after every selection — written as a full date, read with a formatter that cannot parse one. Finding R33."
        default:
            return nil
        }
    }

    private var footerNote: some View {
        Text("Leaving this screen discards everything typed — there is no draft, and in the live app swipe-to-dismiss is not blocked either.")
            .font(.caption2).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
    }

    private var successState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green)
            Text("Report submitted").font(.title3.weight(.semibold))
            Text("\(title) · v\(version)").font(.subheadline).foregroundStyle(.secondary)
            Button {
                withAnimation(AmbientMotion.gentle) { submitted = false }
            } label: {
                Text("Fill in another")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    // ambient-allow: a control.
                    .background(Capsule().fill(Color(hex: "#5471E0")))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Photoshoot notes

/// Live: write a note, set its school, add photos, submit it, start another.
///
/// The model underneath is thinner than the screen makes it look — a note is a
/// timestamp, ONE school NAME (not an id), a body, and photo URLs. There are no
/// categories, no tags, no note types, and nothing binds a note to a session.
private struct PhotoshootNotesMockup: View {
    let notesOnlyOrg: Bool

    @State private var notes: [LabPhotoshootNote] = DesignLabSampleData.photoshootNotes
    @State private var selected: String? = "n1"
    @State private var askingSchool = false
    @State private var banner: String?

    private var drafts: [LabPhotoshootNote] { notes.filter { !$0.submitted } }
    private var submittedNotes: [LabPhotoshootNote] { notes.filter(\.submitted) }
    private var index: Int? { notes.firstIndex { $0.id == selected } }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Color(hex: "#6E56CF"), intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    actionRow
                    noteStrip
                    if let index, !notes[index].submitted {
                        editor(index)
                        photos(index)
                        syncRow(index)
                        if notesOnlyOrg { submitButton(index) }
                    } else {
                        AmbientEmptyState(
                            title: "No note selected",
                            message: "Pick a note above, or start a new one.",
                            systemImage: "note.text",
                            actionTitle: "New Note",
                            actionIcon: "plus.circle.fill",
                            action: newNote,
                            actionTint: Color(hex: "#6E56CF"))
                    }
                    if notesOnlyOrg { submittedSection }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Photoshoot Notes")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { bannerView }
        .confirmationDialog("Select School for Note", isPresented: $askingSchool, titleVisibility: .visible) {
            ForEach(["Riverside Middle School", "Lincoln High School"], id: \.self) { name in
                Button(name) { setSchool(name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have multiple photoshoots today. Which school would you like to use for this note?")
        }
    }

    // MARK: actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: newNote) {
                Label("New", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    // ambient-allow: a control.
                    .background(Capsule().fill(Color(hex: "#6E56CF")))
            }
            .buttonStyle(.plain)

            Button(action: deleteNote) {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    // ambient-allow: a control.
                    .background(Capsule().fill(Color.red.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(index == nil)
            .opacity(index == nil ? 0.4 : 1)

            Spacer(minLength: 0)

            Text("2 sessions today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 10).padding(.vertical, 6)
                // ambient-allow: a status pill.
                .background(Capsule().fill(Color.green.opacity(0.16)))
        }
    }

    private func newNote() {
        let note = LabPhotoshootNote(
            id: "n\(notes.count + 1)-\(drafts.count)",
            timestamp: Date(), school: "", text: "", photoCount: 0)
        withAnimation(AmbientMotion.snappy) {
            notes.append(note)
            selected = note.id
        }
        AmbientHaptics.impact(.light)
        // The real behaviour: a new note immediately tries to set its school
        // from the schedule, and with more than one session today it ASKS.
        askingSchool = true
    }

    private func deleteNote() {
        guard let index else { return }
        withAnimation(AmbientMotion.snappy) {
            notes.remove(at: index)
            selected = drafts.first?.id
        }
        show("Note deleted")
    }

    private func setSchool(_ name: String) {
        guard let index else { return }
        withAnimation(AmbientMotion.snappy) { notes[index].school = name }
        show("Selected \(name) for this note")
    }

    private func show(_ message: String) {
        withAnimation(AmbientMotion.gentle) { banner = message }
    }

    // MARK: strip

    /// NEWEST FIRST. The full screen currently shows insertion order (oldest
    /// first) while the iPad widget shows newest first and caps at five. Two
    /// orders for one list is a defect in the design, not a preference.
    private var noteStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(drafts.reversed()) { note in
                    Button {
                        withAnimation(AmbientMotion.snappy) { selected = note.id }
                        AmbientHaptics.selection()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Formatters.shortTime.string(from: note.timestamp))
                                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            Text(note.school.isEmpty ? "No school yet" : note.school)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(note.school.isEmpty ? .orange : .primary)
                                .lineLimit(1)
                            Text(note.text.isEmpty ? "(No content)" : note.text)
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .frame(width: 168, alignment: .leading)
                        .ambientCard(density: .compact,
                                     state: selected == note.id ? .highlighted : .normal,
                                     border: selected == note.id
                                        ? .strong(Color(hex: "#6E56CF"))
                                        : .hairline(Color.primary.opacity(0.08)),
                                     fillWidth: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    // MARK: editor

    private func editor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("School")

            Menu {
                ForEach(DesignLabSampleData.schools) { school in
                    Button(school.name) { setSchool(school.name) }
                }
            } label: {
                HStack {
                    Text(notes[index].school.isEmpty ? "Choose a school" : notes[index].school)
                        .font(.subheadline)
                        .foregroundStyle(notes[index].school.isEmpty ? .tertiary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
                }
                .ambientCard(density: .compact, fillWidth: true)
            }

            if notes[index].school.isEmpty {
                AmbientNoteCard(
                    title: "Which shoot is this?",
                    text: "You have two photoshoots today. The app asks which school this note belongs to — and it can ask on its own when the schedule finishes loading, not only when you tap.",
                    accent: .orange, density: .compact)
            }

            AmbientSectionTitle("Note", trailing: "\(notes[index].text.count) characters")
            TextEditor(text: Binding(
                get: { notes[index].text },
                set: { notes[index].text = $0 }))
                .frame(minHeight: 120)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .ambientCard(density: .compact, fillWidth: true)
                .overlay(alignment: .topLeading) {
                    if notes[index].text.isEmpty {
                        Text("What happened on this shoot.")
                            .font(.subheadline).foregroundStyle(.tertiary)
                            .padding(.horizontal, 17).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            Text("Saves on every keystroke. There is no Save button.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func photos(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Photos",
                                trailing: notes[index].photoCount == 0 ? nil : "\(notes[index].photoCount)")
            HStack(spacing: 8) {
                Button { addPhoto(index) } label: {
                    Label("Camera", systemImage: "camera")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        // ambient-allow: a control.
                        .background(Capsule().fill(Color.blue))
                }
                .buttonStyle(.plain)
                Button { addPhoto(index) } label: {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        // ambient-allow: a control.
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)
            }
            Text("The only screen in this family that offers the camera.")
                .font(.caption2).foregroundStyle(.tertiary)

            if notes[index].photoCount > 0 {
                HStack(spacing: 8) {
                    ForEach(0..<notes[index].photoCount, id: \.self) { slot in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.purple.opacity(0.25))
                            .frame(width: 76, height: 76)
                            .overlay(Image(systemName: "photo").foregroundStyle(.purple))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    withAnimation(AmbientMotion.snappy) {
                                        notes[index].photoCount -= 1
                                    }
                                    show("Photo removed")
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                                .id(slot)
                            }
                    }
                }
            } else {
                Text("No photos added").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func addPhoto(_ index: Int) {
        withAnimation(AmbientMotion.snappy) { notes[index].photoCount += 1 }
        show("Photo added successfully")
        AmbientHaptics.impact(.light)
    }

    private func syncRow(_ index: Int) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(notes[index].syncedToServer ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(notes[index].syncedToServer ? "Synced to server" : "Local only (not synced)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private func submitButton(_ index: Int) -> some View {
        let ready = !notes[index].school.isEmpty && !notes[index].text.isEmpty
        return VStack(spacing: 6) {
            Button {
                withAnimation(AmbientMotion.gentle) {
                    notes[index].submitted = true
                    notes[index].submittedAt = Date()
                    notes[index].syncedToServer = true
                    selected = drafts.first?.id
                }
                show("Note submitted successfully!")
                AmbientHaptics.impact(.medium)
            } label: {
                Label("Submit Note", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    // ambient-allow: a control.
                    .background(Capsule().fill(ready ? Color.green : Color.gray))
            }
            .buttonStyle(.plain)
            .disabled(!ready)

            if !ready {
                Text(notes[index].school.isEmpty
                     ? "Please select a school before submitting"
                     : "Please add some notes before submitting")
                    .font(.caption).foregroundStyle(.orange)
            }

            Text("PROPOSED — today submitting DELETES the local copy immediately, and the query that would fetch it back cannot succeed. Findings R1, R2 and R8.")
                .font(.caption2).foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var submittedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Submitted notes", trailing: "last 30 days")
            if submittedNotes.isEmpty {
                Text("No submitted notes found").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(submittedNotes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(note.school.isEmpty ? "No school" : note.school)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            AmbientBadge(text: "Submitted", systemImage: "checkmark", tint: .green)
                        }
                        Text(note.text).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .ambientCard(density: .compact,
                                 border: .hairline(Color.green.opacity(0.35)), fillWidth: true)
                }
            }
            Text("In the live app this list is always empty — the fetch sends a malformed filter, and any row that did come back would be dropped on a date it cannot parse.")
                .font(.caption2).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            Text(banner)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                // ambient-allow: a transient banner, not a card.
                .background(Capsule().fill(Color.green.opacity(0.9)))
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: banner) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation(AmbientMotion.gentle) { self.banner = nil }
                }
        }
    }
}

// MARK: - Location photos

/// Live: detect or pick a school, stage photos, label them, upload.
///
/// The thing to notice while using it: the staged photos exist only in memory
/// until Upload is pressed, so leaving loses them — unlike Photoshoot Notes,
/// which saves on every keystroke. Two sibling screens, opposite promises.
private struct LocationPhotosMockup: View {
    private struct Staged: Identifiable {
        let id = UUID()
        var label: String
        let fromCamera: Bool
        let colour: Color
    }

    @State private var school: LabSchool?
    @State private var staged: [Staged] = []
    @State private var showPicker = false
    @State private var showSource = false
    @State private var uploading = false
    @State private var uploaded = false
    @State private var detectMessage: String?

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Color(hex: "#8E4EC6"), intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    locationSection
                    if staged.isEmpty { emptyState } else { grid }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }

            if uploading { uploadingOverlay }
            if uploaded { uploadedOverlay }
        }
        .navigationTitle("Location Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSource = true } label: { Image(systemName: "plus") }
                    .disabled(school == nil)
            }
        }
        .sheet(isPresented: $showPicker) {
            SchoolPickerSheet(
                chosen: [],
                onPick: { picked in
                    withAnimation(AmbientMotion.gentle) { school = picked }
                    showPicker = false
                },
                onCancel: { showPicker = false })
        }
        .confirmationDialog("Add Photo", isPresented: $showSource, titleVisibility: .visible) {
            Button("Take Photo") { add(camera: true) }
            Button("Photo Library") { add(camera: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a source")
        }
    }

    private func add(camera: Bool) {
        let palette: [Color] = [.purple, .blue, .teal, .orange, .green]
        withAnimation(AmbientMotion.snappy) {
            staged.append(Staged(label: "", fromCamera: camera,
                                 colour: palette[staged.count % palette.count]))
        }
        AmbientHaptics.impact(.light)
    }

    private func detect() {
        withAnimation(AmbientMotion.gentle) {
            school = DesignLabSampleData.schools[0]
            detectMessage = "You are at \(DesignLabSampleData.schools[0].name)"
        }
        AmbientHaptics.impact(.medium)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Location")
            HStack(spacing: 8) {
                Button { showPicker = true } label: {
                    HStack {
                        Text(school?.name ?? "Select a school")
                            .font(.subheadline)
                            .foregroundStyle(school == nil ? .tertiary : .primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .ambientCard(density: .compact, fillWidth: true)
                }
                .buttonStyle(.plain)

                Button(action: detect) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(hex: "#8E4EC6"))
                }
                .buttonStyle(.plain)
            }

            if let detectMessage {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.caption2)
                    Text(detectMessage).font(.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        AmbientEmptyState(
            title: "No Photos Added",
            message: "Add photos to help others identify this location.",
            systemImage: "photo.on.rectangle.angled",
            actionTitle: school == nil ? "Detect Current School" : "Add Photo",
            actionIcon: school == nil ? "location.circle.fill" : "plus.circle.fill",
            action: { if school == nil { detect() } else { showSource = true } },
            actionTint: Color(hex: "#8E4EC6"))
    }

    /// The one adaptive grid in the family — kept, because a location photo is
    /// being looked AT rather than counted, so it earns the size.
    private var grid: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Photos", trailing: "\(staged.count) staged")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], spacing: 12) {
                ForEach($staged) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.colour.opacity(0.3))
                            .frame(height: 130)
                            .overlay(Image(systemName: "photo").font(.title2).foregroundStyle(item.colour))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    withAnimation(AmbientMotion.snappy) {
                                        staged.removeAll { $0.id == item.id }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                            }

                        HStack(spacing: 4) {
                            Image(systemName: item.fromCamera ? "camera.fill" : "photo.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(hex: "#8E4EC6"))
                            Text(item.fromCamera ? "Camera" : "Library")
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        TextField("Enter label", text: $item.label)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 7)
                            // ambient-allow: an input well, not a card.
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.1)))
                    }
                }
            }

            Button {
                uploading = true
                Task {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    withAnimation(AmbientMotion.gentle) {
                        uploading = false
                        uploaded = true
                    }
                }
            } label: {
                Text("Upload Photos")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    // ambient-allow: a control.
                    .background(Capsule().fill(school == nil ? Color.gray : Color(hex: "#8E4EC6")))
            }
            .buttonStyle(.plain)
            .disabled(school == nil)

            Text("An unlabelled photo is stored as \"Location Photo\". These exist only in memory until Upload is pressed — leaving the screen loses them. Deleting an already-uploaded photo happens in Settings, not here.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text("Uploading Photos...").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
        }
    }

    private var uploadedOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(.green)
                Text("Photos Uploaded!").font(.title3.weight(.bold))
                Text("Your photos have been successfully uploaded to \(school?.name ?? "the location").")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .ambientCard(density: .hero, state: .highlighted, contentAlignment: .center)
            .padding(.horizontal, 32)
        }
        .task(id: uploaded) {
            guard uploaded else { return }
            // Auto-dismisses after 2 seconds and CLEARS the staged photos —
            // the live screen's only reset.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(AmbientMotion.gentle) {
                uploaded = false
                staged.removeAll()
            }
        }
    }
}
