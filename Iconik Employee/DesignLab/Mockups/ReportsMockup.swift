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
}

// MARK: - The standard daily job report

private struct DailyJobReportMockup: View {
    @State private var expanded: Set<String> = Set(DesignLabSampleData.reportSections.map(\.title))
    @State private var vehicle: String = ""
    @State private var showVehicleConfirm = false

    private var sections: [(title: String, symbol: String, tint: Color, required: Bool, done: Bool)] {
        DesignLabSampleData.reportSections
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: ReportsMockup.featureTint, intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    draftStrip
                    requirementLead
                    ForEach(sections, id: \.title) { section in
                        sectionCard(section)
                    }
                    submitNote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Daily Job Report")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Confirm Vehicle", isPresented: $showVehicleConfirm, titleVisibility: .visible) {
            Button("Personal") { vehicle = "personal" }
            Button("Company") { vehicle = "company" }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select the vehicle again to confirm — this sets your mileage reimbursement and can't be changed by an accidental tap.")
        }
    }

    /// PROPOSED. There is NO draft and no autosave in this form today: every
    /// field is plain view state, and leaving the screen — including the jump to
    /// Home the app performs after a successful submit — discards everything
    /// typed. The only thing that persists a keystroke is the photoshoot note
    /// editor, which writes to shared storage on every character.
    private var draftStrip: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
            Text("Draft saved 2 minutes ago")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Text("PROPOSED")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .ambientCard(density: .compact, border: .dashed(Color.secondary.opacity(0.35)), fillWidth: true)
    }

    /// The redesign's central move on this screen: separate the ONE requirement
    /// from the seven suggestions, instead of averaging them into a progress bar
    /// that can read 7/7 on a form the app will refuse.
    private var requirementLead: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: vehicle.isEmpty ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(vehicle.isEmpty ? .orange : .green)
                Text(vehicle.isEmpty ? "One thing is required" : "Ready to submit")
                    .font(.headline)
                Spacer(minLength: 0)
            }

            Text(vehicle.isEmpty
                 ? "Everything else on this form is optional. Only the vehicle has to be answered — it sets your mileage reimbursement."
                 : "The rest of the form is optional. You can submit whenever you're ready.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // The two-step confirmation, kept exactly. The segment does NOT
            // commit the value — it raises the dialog.
            HStack(spacing: 8) {
                vehicleButton("Personal", "car.fill")
                vehicleButton("Company", "bus.fill")
            }

            if vehicle.isEmpty {
                Text("Tap a vehicle, then confirm the selection.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .ambientCard(density: .hero, state: .highlighted,
                     glow: vehicle.isEmpty ? .orange : .green, fillWidth: true)
    }

    private func vehicleButton(_ title: String, _ icon: String) -> some View {
        let selected = vehicle == title.lowercased()
        return Button {
            showVehicleConfirm = true
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                // ambient-allow: a segmented control, not a container.
                .background(Capsule().fill(selected
                                           ? AnyShapeStyle(ReportsMockup.featureTint)
                                           : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.1)))
        }
        .buttonStyle(.plain)
    }

    /// The eight sections, all always present, all starting expanded — as today.
    /// What changes is that a section says whether it is REQUIRED rather than
    /// wearing a checkmark that means nothing.
    private func sectionCard(_ section: (title: String, symbol: String, tint: Color, required: Bool, done: Bool)) -> some View {
        let isOpen = expanded.contains(section.title)
        return VStack(alignment: .leading, spacing: isOpen ? 10 : 0) {
            Button {
                withAnimation(AmbientMotion.snappy) {
                    if isOpen { expanded.remove(section.title) } else { expanded.insert(section.title) }
                }
                AmbientHaptics.impact(.light)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: section.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(section.tint)
                        .frame(width: 24)
                    Text(section.title).font(AmbientDensity.roomy.titleFont)
                    if section.required {
                        AmbientBadge(text: "Required", tint: .orange)
                    }
                    Spacer(minLength: 0)
                    if section.done && !section.required {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                    }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                sectionBody(section.title)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    @ViewBuilder
    private func sectionBody(_ title: String) -> some View {
        switch title {
        case "Basic Information":
            VStack(spacing: 0) {
                row("Report Date", Formatters.monthDay.string(from: Date()))
                Divider()
                row("Your Name", "Maria Alvarez")
                Divider()
                row("Session", "Riverside Middle — 3:30 PM (Fall Sports)")
            }
        case "Photoshoot Note":
            // Three real states: none available, exactly one (auto-selected,
            // with NO way to deselect), or several behind a picker.
            VStack(alignment: .leading, spacing: 6) {
                Text("Using note from \(Formatters.shortTime.string(from: DesignLabSampleData.at(11, 20)))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Lincoln High School").font(.subheadline.weight(.semibold))
                Text("Auto-selected because it is the only note. There is no way to deselect it once this happens — kept, but worth seeing.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case "Schools & Mileage":
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "building.2").font(.caption).foregroundStyle(.secondary)
                    Text("Riverside Middle School").font(.subheadline)
                    Spacer(minLength: 0)
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary)
                }
                Text("Derived from the session and locked. With no session chosen this becomes a multi-school picker with Add School.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack {
                    Text("Total Mileage").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("18.2").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("miles").font(.caption).foregroundStyle(.secondary)
                }
            }
        case "Job Description":
            checkboxGrid(DesignLabSampleData.jobDescriptionOptions, preselected: ["Fall Sports"])
        case "Extra Items":
            checkboxGrid(DesignLabSampleData.extraItemOptions, preselected: [])
        case "Scan Status":
            VStack(alignment: .leading, spacing: 10) {
                radioGroup("Cards Scanned", ["Yes", "No"], selected: "Yes")
                radioGroup("Job Box and Camera Cards Turned In", ["Yes", "No", "NA"], selected: nil)
                radioGroup("Sports Background Shot", ["Yes", "No", "NA"], selected: nil)
                Text("None of these can be cleared once answered, and none of them blocks submission.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        case "Notes":
            VStack(alignment: .leading, spacing: 6) {
                Text("Additional Notes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("Backdrop stand from Kit A is bent — used the loaner.")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            }
        case "Photos":
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 68, height: 68)
                            .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                    }
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: 68, height: 68)
                        .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                }
                Text("3 photos selected. One image per pick, photo library only — there is no camera on this screen.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        default:
            EmptyView()
        }
    }

    private func checkboxGrid(_ options: [String], preselected: Set<String>) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)], spacing: 7) {
            ForEach(options, id: \.self) { option in
                HStack(spacing: 6) {
                    Image(systemName: preselected.contains(option) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundStyle(preselected.contains(option) ? ReportsMockup.featureTint : .secondary)
                    Text(option)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func radioGroup(_ title: String, _ options: [String], selected: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    Text(option)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected == option ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        // ambient-allow: a radio control, not a container.
                        .background(Capsule().fill(selected == option
                                                   ? AnyShapeStyle(ReportsMockup.featureTint)
                                                   : AnyShapeStyle(.ultraThinMaterial)))
                }
            }
        }
    }

    private var submitNote: some View {
        Text("Submit lives in the navigation bar, as today — there is no button at the bottom of this form.")
            .font(.caption2).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Template picker

private struct TemplatePickerMockup: View {
    @State private var search = ""
    @State private var decoded = true

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

/// The dynamic form, drawn against EVERY field type it can render rather than a
/// convenient three. Four of these types are broken today in ways that stop the
/// form being submittable at all; they are drawn in their broken state and
/// labelled, because a design approved against a form that cannot submit is not
/// an approval of anything.
private struct TemplateFormMockup: View {
    @State private var showBroken = false

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Color(hex: "#5471E0"), intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    header
                    fieldSections
                    submitBlock
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Sports Day")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · field defects", trailing: "not a design element")
            Toggle("Mark the four broken field types", isOn: $showBroken)
                .font(.caption)
        }
    }

    /// The live screen fakes a nav bar with a blue gradient because it is a sheet
    /// with no navigation container. Here it is a real pushed screen with a real
    /// bar, which is one fewer bespoke thing to maintain.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("14 fields · 4 automatic").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("v3").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            Text("Every field must pass before this form will submit — including the automatic ones you cannot edit.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// Sections are auto-derived from field types and rendered ALPHABETICALLY —
    /// which is why "Basic Information" precedes "Report Details" by accident
    /// rather than by design. Kept as-is so the operator can see it and decide.
    private var fieldSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Basic Information", ["user_name", "date_auto", "time_auto"])
            section("Calculated Fields", ["school_name", "mileage", "photo_count", "weather_conditions"])
            section("Media & Location", ["file"])
            section("Report Details", ["text", "email", "phone", "number", "currency",
                                       "select", "multiselect", "radio", "toggle", "date", "time", "textarea"])
        }
    }

    private func section(_ title: String, _ types: [String]) -> some View {
        let fields = DesignLabSampleData.templateFieldTypes.filter { types.contains($0.type) }
        return VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle(title, trailing: "\(fields.count)")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(fields, id: \.type) { field in
                    fieldRow(field)
                }
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    private func fieldRow(_ field: (type: String, label: String, required: Bool, readOnly: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(field.label).font(.subheadline.weight(.medium))
                if field.required {
                    Text("*").font(.subheadline.weight(.bold)).foregroundStyle(.red)
                }
                if field.readOnly {
                    AmbientBadge(text: "Auto", tint: .blue)
                }
                Spacer(minLength: 0)
                Text(field.type)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            control(for: field)

            if showBroken, let note = defect(field.type) {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9, weight: .bold))
                    Text(note).font(.caption2).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func control(for field: (type: String, label: String, required: Bool, readOnly: Bool)) -> some View {
        switch field.type {
        case "user_name", "date_auto", "time_auto", "school_name", "mileage", "photo_count", "weather_conditions":
            Text(autoValue(field.type))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                // ambient-allow: a read-only input well, not a card.
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1)))
        case "textarea":
            Text("Placeholder text is ignored for this type.")
                .font(.caption).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                .padding(10)
                // ambient-allow: an input well, not a card.
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1)))
        case "select":
            inputWell("Select sport", chevron: true)
        case "multiselect":
            VStack(alignment: .leading, spacing: 5) {
                ForEach(["Basic", "Deluxe", "Team photo"], id: \.self) { option in
                    HStack(spacing: 6) {
                        Image(systemName: "square").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(option).font(.caption)
                        Spacer(minLength: 0)
                    }
                }
            }
        case "radio":
            HStack(spacing: 6) {
                ForEach(["Yes", "No", "NA"], id: \.self) { option in
                    Text(option)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        // ambient-allow: a radio control.
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
        case "toggle":
            Toggle("", isOn: .constant(false)).labelsHidden()
        case "file":
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                Text("Photos are shared across every file field on the template — they are not stored per field.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case "date", "time":
            inputWell(field.type == "date" ? Formatters.monthDay.string(from: Date()) : "5:30 PM", chevron: false)
        default:
            inputWell("Enter \(field.label.lowercased())", chevron: false)
        }
    }

    private func inputWell(_ placeholder: String, chevron: Bool) -> some View {
        HStack {
            Text(placeholder).font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
            if chevron { Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        // ambient-allow: an input well, not a card.
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.1)))
    }

    private func autoValue(_ type: String) -> String {
        switch type {
        case "user_name": return "Maria Alvarez"
        case "date_auto": return Formatters.shortDate.string(from: Date())
        case "time_auto": return Formatters.shortTime.string(from: Date())
        case "school_name": return "No schools selected"
        case "mileage": return "0.0"
        case "photo_count": return "0"
        case "weather_conditions": return "Weather loading..."
        default: return ""
        }
    }

    private func defect(_ type: String) -> String? {
        switch type {
        case "number":
            return "An untouched number field fails validation even when it is optional, so Submit stays disabled forever. Finding R15."
        case "file":
            return "A required file field can never be satisfied — photos are never written to the field's own key. Finding R14."
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

    private var submitBlock: some View {
        VStack(spacing: 6) {
            Button {} label: {
                Text("Submit Report")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    // ambient-allow: a control.
                    .background(Capsule().fill(Color(hex: "#5471E0")))
            }
            .buttonStyle(.plain)
            Text("Leaving this screen discards everything typed — there is no draft and swipe-to-dismiss is not blocked.")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }
}

// MARK: - Photoshoot notes

private struct PhotoshootNotesMockup: View {
    let notesOnlyOrg: Bool
    @State private var selected: String = "n1"

    private var notes: [LabPhotoshootNote] { DesignLabSampleData.photoshootNotes.filter { !$0.submitted } }
    private var submitted: [LabPhotoshootNote] { DesignLabSampleData.photoshootNotes.filter(\.submitted) }
    private var current: LabPhotoshootNote? { notes.first { $0.id == selected } }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Color(hex: "#6E56CF"), intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    actionRow
                    noteStrip
                    if let note = current {
                        editor(note)
                        photos(note)
                        syncRow(note)
                        if notesOnlyOrg { submitButton(note) }
                    } else {
                        AmbientEmptyState(title: "No note selected",
                                          message: "Pick a note above, or start a new one.",
                                          systemImage: "note.text")
                    }
                    if notesOnlyOrg { submittedSection }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Photoshoot Notes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {} label: {
                Label("New", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    // ambient-allow: a control.
                    .background(Capsule().fill(Color(hex: "#6E56CF")))
            }
            .buttonStyle(.plain)

            Button {} label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    // ambient-allow: a control.
                    .background(Capsule().fill(Color.red.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .opacity(current == nil ? 0.4 : 1)

            Spacer(minLength: 0)

            Text("2 sessions today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 10).padding(.vertical, 6)
                // ambient-allow: a status pill.
                .background(Capsule().fill(Color.green.opacity(0.16)))
        }
    }

    /// A horizontal strip, as today — but NEWEST FIRST. The full screen currently
    /// shows insertion order (oldest first) while the iPad widget shows newest
    /// first and caps at five. Two orders for one list is a bug in the design,
    /// not a preference, and the note you want is nearly always the recent one.
    private var noteStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(notes.reversed()) { note in
                    Button {
                        withAnimation(AmbientMotion.snappy) { selected = note.id }
                        AmbientHaptics.selection()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Formatters.shortTime.string(from: note.timestamp))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(note.school.isEmpty ? "No school yet" : note.school)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(note.school.isEmpty ? .orange : .primary)
                                .lineLimit(1)
                            Text(note.text.isEmpty ? "(No content)" : note.text)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
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

    private func editor(_ note: LabPhotoshootNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("School")
            HStack {
                Text(note.school.isEmpty ? "Choose a school" : note.school)
                    .font(.subheadline)
                    .foregroundStyle(note.school.isEmpty ? .tertiary : .primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
            }
            .ambientCard(density: .compact, fillWidth: true)

            if note.school.isEmpty {
                // The real behaviour: with more than one session today, a
                // confirmation dialog asks which school — and it can appear
                // UNPROMPTED, because the schedule listener also triggers it.
                AmbientNoteCard(
                    title: "Which shoot is this?",
                    text: "You have two photoshoots today. The app will ask which school this note belongs to — and it can ask on its own when the schedule finishes loading, not only when you tap.",
                    accent: .orange,
                    density: .compact)
            }

            AmbientSectionTitle("Note", trailing: "\(note.text.count) characters")
            Text(note.text.isEmpty ? "Type what happened on this shoot." : note.text)
                .font(.subheadline)
                .foregroundStyle(note.text.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                .ambientCard(density: .compact, fillWidth: true)

            Text("Saves on every keystroke. There is no Save button.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func photos(_ note: LabPhotoshootNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Photos", trailing: note.photoCount == 0 ? nil : "\(note.photoCount)")
            HStack(spacing: 8) {
                Button {} label: {
                    Label("Camera", systemImage: "camera")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        // ambient-allow: a control.
                        .background(Capsule().fill(Color.blue))
                }
                .buttonStyle(.plain)
                Button {} label: {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        // ambient-allow: a control.
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)
            }
            Text("The only screen in this family that offers the camera.")
                .font(.caption2).foregroundStyle(.tertiary)

            if note.photoCount > 0 {
                HStack(spacing: 8) {
                    ForEach(0..<note.photoCount, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 76, height: 76)
                            .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                    }
                }
            } else {
                Text("No photos added").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func syncRow(_ note: LabPhotoshootNote) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(note.syncedToServer ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(note.syncedToServer ? "Synced to server" : "Local only (not synced)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private func submitButton(_ note: LabPhotoshootNote) -> some View {
        let ready = !note.school.isEmpty && !note.text.isEmpty
        return VStack(spacing: 6) {
            Button {} label: {
                Label("Submit Note", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    // ambient-allow: a control.
                    .background(Capsule().fill(ready ? Color.green : Color.gray))
            }
            .buttonStyle(.plain)
            .disabled(!ready)

            Text("PROPOSED — today submitting DELETES the local copy immediately, and the query that would fetch it back cannot succeed. Findings R1, R2 and R8.")
                .font(.caption2).foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var submittedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Submitted notes", trailing: "last 30 days")
            ForEach(submitted) { note in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(note.school).font(.subheadline.weight(.semibold))
                        Spacer()
                        AmbientBadge(text: "Submitted", systemImage: "checkmark", tint: .green)
                    }
                    Text(note.text).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .ambientCard(density: .compact,
                             border: .hairline(Color.green.opacity(0.35)),
                             fillWidth: true)
            }
            Text("In the live app this list is always empty — the fetch sends a malformed filter, and any row that did come back would be dropped on a date it cannot parse.")
                .font(.caption2).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Location photos

private struct LocationPhotosMockup: View {
    @State private var school: String? = nil
    @State private var staged = 3

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Color(hex: "#8E4EC6"), intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    locationSection
                    if school == nil { emptyState } else { grid }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Location Photos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Location")
            HStack(spacing: 8) {
                Button {
                    withAnimation(AmbientMotion.gentle) { school = "Lincoln High School" }
                } label: {
                    HStack {
                        Text(school ?? "Select a school")
                            .font(.subheadline)
                            .foregroundStyle(school == nil ? .tertiary : .primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .ambientCard(density: .compact, fillWidth: true)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(AmbientMotion.gentle) { school = "Lincoln High School" }
                } label: {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: "#8E4EC6"))
                }
                .buttonStyle(.plain)
            }

            if school != nil {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.caption2)
                    Text("You are at Lincoln High School").font(.caption)
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
            actionTitle: "Detect Current School",
            actionIcon: "location.circle.fill",
            action: { withAnimation(AmbientMotion.gentle) { school = "Lincoln High School" } },
            actionTint: Color(hex: "#8E4EC6"))
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Photos", trailing: "\(staged) staged")

            // The one adaptive grid in the family — kept, because a location
            // photo is being looked AT rather than counted, so it earns the size.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], spacing: 12) {
                ForEach(0..<staged, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 130)
                            .overlay(Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, .black.opacity(0.5))
                                    .padding(6)
                            }
                        HStack(spacing: 4) {
                            Image(systemName: index == 0 ? "camera.fill" : "photo.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(hex: "#8E4EC6"))
                            Text(index == 0 ? "Camera" : "Library")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Enter label")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            // ambient-allow: an input well, not a card.
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.1)))
                    }
                }
            }

            Button {} label: {
                Text("Upload Photos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    // ambient-allow: a control.
                    .background(Capsule().fill(Color(hex: "#8E4EC6")))
            }
            .buttonStyle(.plain)

            Text("These photos exist only in memory until Upload is pressed — leaving the screen loses them. Deleting an already-uploaded photo happens in Settings, not here.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
