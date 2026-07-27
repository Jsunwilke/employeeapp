//  ReportProposalMockup.swift
//  Iconik Employee — AMB.7, the daily job report, THIRD design
//
//  ARC SCAFFOLDING. Deleted at AMB.7's close.
//
//  TWO FAILED DESIGNS CAME BEFORE THIS ONE. Both verdicts are recorded, because
//  they are the entire reason this file looks the way it does.
//
//    v1  "You prettied up what I already had. You didn't really change it in any
//        meaningful way." — correct. It kept the eight-section wall and restyled
//        it.
//
//    v2  "Hate it, very hard to fill out." Then the diagnosis that mattered:
//        "too much is collapsed that I have to uncollapse to fill out. I have to
//        fill out what was shot and if anything extra was shot so I need to see
//        those." — also correct, and WORSE than v1, because I built an accordion
//        of nine rows after my own research had said accordions raise
//        interaction cost and should be avoided wherever people work with most
//        of the content. v2 is deleted rather than kept for comparison; a
//        prototype that did not work is not a reference.
//
//  WHAT BOTH VERSIONS GOT WRONG
//      I kept treating the 22 job descriptions and the 12 extra items as a WALL
//      to be hidden, folded, suggested away, or replaced by something cleverer.
//      They are not a wall — they are filled in on every single report.
//
//  AND THE CORRECTION AFTER THAT: "nothing is secondary. it is all important."
//      v3's first cut still ranked things. The two lists got headline titles and
//      full cards while the date, photographer, schools, mileage and vehicle
//      were compressed into one cramped block of small type — a layout saying
//      those matter less. They do not. A wrong school, a wrong vehicle or a
//      wrong mileage is a payroll error; a missing job description is a billing
//      error. Nothing here is background.
//
//      So EVERY part of the report is now a peer: the same heading, the same
//      card, the same spacing, and the same kind of status line on the right of
//      each heading. The only thing that varies is the control a field needs.
//
//  WHAT THIS DESIGN IS
//      One scrolling form. NOTHING COLLAPSES. NOTHING EXPANDS. Every field is on
//      screen and ready the moment you arrive.
//
//        1. A compact block of what the app already knows — date, photographer,
//           schools, mileage, vehicle — as LIVE CONTROLS, not summaries.
//           Prefilled, and directly editable without opening anything.
//        2. WHAT DID YOU SHOOT — all 22, visible, as tappable chips grouped into
//           seven named families so 22 options can be SCANNED rather than read.
//        3. ANYTHING EXTRA — all 12, same treatment.
//        4. Cards and job box, notes, photos.
//
//      Chips rather than a two-column checkbox grid because chips wrap to the
//      width of their words, so the whole vocabulary fits in roughly a third of
//      the height a grid needs — which is what makes "everything visible"
//      possible at all. A checkmark appears inside a selected chip so a chip row
//      never reads as single-select.
//
//  WHAT SURVIVED TWO REWRITES, AND WHY
//
//      NO WIZARD. NN/g: wizards "become annoying and overly controlling if they
//      have to be used over and over." The Ministry of Justice applied GOV.UK's
//      one-thing-per-page to daily professional users and called it "slow and
//      disorientating." The roadmap's own DJR.1 proposes a wizard; the evidence
//      says do not build one.
//
//      GROUPED, NEVER REORDERED. Grouping a long option list under subheadings
//      is the one thing every source agrees on. Re-sorting it by what you picked
//      recently is the one thing with measured evidence AGAINST it — adaptive
//      menus tested slower than static ones, because frequent users learn where
//      things are. These groups and their contents never move.
//
//      GROUPING LOSES NOTHING. Every one of the 22 and all 12 appear exactly
//      once, unchanged, and `DesignLabSampleData` keeps the flat lists beside the
//      grouped ones so the two can be diffed. Verified before this screen was
//      built, not after.
//
//      PREFILL IS MARKED, AND MILEAGE SHOWS ITS ROUTE. Prepopulated-tax-return
//      studies found people check a prefilled number when it costs them and let
//      it stand when it favours them. Mileage feeds reimbursement, so it is
//      never a bare figure: the route sits under it, a typed value is never
//      overwritten, and a figure out of line with this photographer's own
//      history at this school is flagged in place.
//
//      SOFT GATE. Submit is never disabled. The field apps that hard-block on
//      required fields are the ones whose reviews carry the lost-work stories.
//
//      EVERY PREFILLED VALUE IS EDITABLE — an operator requirement that v2 broke
//      by leaving date and photographer as unchangeable header text.

import SwiftUI

struct ReportProposalMockup: View {
    static let featureTint = Color(hex: "#3E63DD")

    // What the app can prefill.
    @State private var reportDate = Date()
    @State private var photographer = "Maria Alvarez"
    @State private var stops: [LabSchool] = [DesignLabSampleData.schools[1]]
    @State private var mileage = ""
    @State private var mileageEdited = false
    @State private var vehicle = DesignLabSampleData.History.usualVehicle

    // The work.
    @State private var shot: Set<String> = ["Fall Sports"]
    @State private var extras: Set<String> = []
    @State private var cardsScanned: String?
    @State private var jobBox: String? = "NA"
    @State private var sportsBackground: String? = "NA"
    @State private var notes = ""
    @State private var photos: [Color] = []

    @State private var showVehicleConfirm = false
    @State private var showSchoolPicker = false
    @State private var submitted = false

    private var computed: Double { DesignLabSampleData.routeMiles(stops) }
    private var miles: Double { Double(mileage) ?? computed }
    private var usual: Double? { stops.first.flatMap { DesignLabSampleData.History.usualMiles($0.name) } }
    private var mileageLooksOff: Bool {
        guard let usual, usual > 0, stops.count == 1 else { return false }
        return abs(miles - usual) / usual > 0.5
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.65)
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
            }
        }
        .sheet(isPresented: $showSchoolPicker) {
            SchoolPickerSheet(
                chosen: stops.map(\.id),
                onPick: { school in
                    withAnimation(AmbientMotion.snappy) { stops.append(school) }
                    showSchoolPicker = false
                },
                onCancel: { showSchoolPicker = false })
        }
        .confirmationDialog("Confirm Vehicle", isPresented: $showVehicleConfirm, titleVisibility: .visible) {
            Button("Personal") { commit("personal") }
            Button("Company") { commit("company") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You normally use your \(DesignLabSampleData.History.usualVehicle) vehicle. Confirm the change — this sets your mileage reimbursement.")
        }
    }

    private func commit(_ value: String) {
        withAnimation(AmbientMotion.snappy) { vehicle = value }
        AmbientHaptics.impact(.medium)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                whenSection
                schoolsSection
                mileageSection
                shotSection
                extrasSection
                scanSection
                notesSection
                photosSection
                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
    }

    // MARK: - Shared section chrome

    /// EVERY section on this screen goes through here. That is deliberate: the
    /// moment one part of the report gets its own heading treatment, the layout
    /// starts ranking things again, which is exactly the mistake this replaced.
    private func section<Content: View>(_ title: String, status: String,
                                        statusTint: Color? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer(minLength: 8)
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tertiary))
                    .contentTransition(.numericText())
                    .multilineTextAlignment(.trailing)
            }
            content()
                .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    // MARK: - The report, section by section, all equal

    private var whenSection: some View {
        section("Date and photographer",
                status: Formatters.relativeDay(reportDate)) {
            VStack(spacing: 0) {
                HStack {
                    Text("Date").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: $reportDate, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.vertical, 7)

                Divider()

                HStack {
                    Text("Photographer").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $photographer) {
                        ForEach(DesignLabSampleData.crew.map(\.name), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
                .padding(.vertical, 7)
            }
        }
    }

    private var schoolsSection: some View {
        section("Schools",
                status: stops.isEmpty ? "none yet" : "\(stops.count) selected",
                statusTint: stops.isEmpty ? nil : Self.featureTint) {
            schoolsBody
        }
    }

    private var schoolsBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stops.isEmpty {
                Text("No schools on this report yet — an off-schedule day still needs one.")
                    .font(.subheadline).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                AmbientFlowLayout(spacing: 7, lineSpacing: 7) {
                    ForEach(stops) { school in
                        HStack(spacing: 6) {
                            Text(school.name).font(.system(size: 13, weight: .semibold))
                            Button {
                                withAnimation(AmbientMotion.snappy) {
                                    stops.removeAll { $0.id == school.id }
                                }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(Self.featureTint)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        // ambient-allow: a token chip is a control, not a card.
                        .background(Capsule().fill(Self.featureTint.opacity(0.13)))
                    }
                }
            }

            Button { showSchoolPicker = true } label: {
                Label("Add a school", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Self.featureTint)
            }
            .buttonStyle(.plain)
        }
    }

    private var mileageSection: some View {
        section("Mileage and vehicle",
                status: String(format: "%.1f mi · %@", miles, vehicle.capitalized),
                statusTint: mileageLooksOff ? .orange : Self.featureTint) {
            mileageBody
        }
    }

    private var mileageBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Total").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                TextField(String(format: "%.1f", computed), text: $mileage)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(width: 84)
                    .onChange(of: mileage) { _ in mileageEdited = !mileage.isEmpty }
                Text("miles").font(.subheadline).foregroundStyle(.secondary)
            }

            Divider()

            // Vehicle lives with the mileage — one decision, per the operator.
            HStack(spacing: 8) {
                vehicleButton("Personal")
                vehicleButton("Company")
            }

            // The route, always. A bare number is what gets accepted unread.
            if !stops.isEmpty && !mileageEdited {
                Text((["Home"] + stops.map(\.name) + ["Home"]).joined(separator: " → "))
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if mileageEdited {
                HStack(spacing: 6) {
                    Text("You typed this — it won't be overwritten.")
                        .font(.caption).foregroundStyle(.orange)
                    Button {
                        withAnimation(AmbientMotion.snappy) { mileage = ""; mileageEdited = false }
                    } label: {
                        Text("Use \(String(format: "%.1f", computed))")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
            if mileageLooksOff, let usual {
                Label(String(format: "You usually claim %.1f at %@", usual, stops.first?.name ?? ""),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func vehicleButton(_ title: String) -> some View {
        let on = vehicle == title.lowercased()
        return Button {
            let value = title.lowercased()
            // Fires on a CHANGE away from the usual, not on every report — a
            // confirmation that appears every time stops being read.
            if value != DesignLabSampleData.History.usualVehicle && value != vehicle {
                showVehicleConfirm = true
            } else {
                commit(value)
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? .white : .primary)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                // ambient-allow: a segmented control, not a container.
                .background(Capsule().fill(on
                                           ? AnyShapeStyle(Self.featureTint)
                                           : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2 & 3. The work: both lists, entirely visible

    private var shotSection: some View {
        chipSection(title: "What did you shoot?",
                    groups: DesignLabSampleData.jobDescriptionGroups,
                    selection: $shot,
                    tint: .orange)
    }

    private var extrasSection: some View {
        chipSection(title: "Anything extra?",
                    groups: DesignLabSampleData.extraItemGroups,
                    selection: $extras,
                    tint: .pink)
    }

    /// Every option on screen, grouped, nothing behind a disclosure control.
    private func chipSection(title: String, groups: [(String, [String])],
                             selection: Binding<Set<String>>, tint: Color) -> some View {
        section(title,
                status: selection.wrappedValue.isEmpty
                    ? "select all that apply"
                    : "\(selection.wrappedValue.count) selected",
                statusTint: selection.wrappedValue.isEmpty ? nil : tint) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.0)
                            .font(.system(size: 10, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(.tertiary)
                        AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(group.1, id: \.self) { option in
                                chip(option, selection: selection, tint: tint)
                            }
                        }
                    }
                }

                if selection.wrappedValue.contains("NONE") && selection.wrappedValue.count > 1 {
                    Label("\"NONE\" is selected alongside \(selection.wrappedValue.count - 1) other item\(selection.wrappedValue.count == 2 ? "" : "s").",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func chip(_ option: String, selection: Binding<Set<String>>, tint: Color) -> some View {
        let on = selection.wrappedValue.contains(option)
        return Button {
            withAnimation(AmbientMotion.snappy) {
                if on { selection.wrappedValue.remove(option) }
                else { selection.wrappedValue.insert(option) }
            }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 5) {
                // The checkmark is what stops a chip row reading as single-select.
                if on {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                }
                Text(option)
                    .font(.system(size: 13, weight: on ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(on ? .white : .primary)
            .padding(.horizontal, 12).padding(.vertical, 9)
            // ambient-allow: a filter chip is a control, not a container.
            .background(Capsule().fill(on ? AnyShapeStyle(tint) : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. The rest

    private var scanSection: some View {
        let answered = [cardsScanned, jobBox, sportsBackground].compactMap { $0 }.count
        return section("Cards and job box",
                       status: "\(answered) of 3 answered",
                       statusTint: answered == 3 ? .teal : nil) {
            VStack(alignment: .leading, spacing: 14) {
                radio("Cards scanned", ["Yes", "No"], $cardsScanned)
                radio("Job box and camera cards turned in", ["Yes", "No", "NA"], $jobBox)
                radio("Sports background shot", ["Yes", "No", "NA"], $sportsBackground)
            }
        }
    }

    private func radio(_ title: String, _ options: [String], _ selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let on = selection.wrappedValue == option
                    Button {
                        withAnimation(AmbientMotion.snappy) { selection.wrappedValue = option }
                        AmbientHaptics.selection()
                    } label: {
                        Text(option)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(on ? .white : .primary)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            // ambient-allow: a radio control, not a container.
                            .background(Capsule().fill(on
                                                       ? AnyShapeStyle(Color.teal)
                                                       : AnyShapeStyle(.ultraThinMaterial)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notesSection: some View {
        section("Notes",
                status: notes.isEmpty ? "nothing written" : "\(notes.count) characters",
                statusTint: notes.isEmpty ? nil : Self.featureTint) {
            TextEditor(text: $notes)
                .frame(minHeight: 96)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Anything the lab or the next photographer needs to know.")
                            .font(.subheadline).foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var photosSection: some View {
        section("Photos",
                status: photos.isEmpty ? "none attached" : "\(photos.count) attached",
                statusTint: photos.isEmpty ? nil : Self.featureTint) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, colour in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(colour.opacity(0.3))
                        .frame(height: 76)
                        .overlay(Image(systemName: "photo").foregroundStyle(colour))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(AmbientMotion.snappy) { _ = photos.remove(at: index) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .padding(3)
                            }
                            .buttonStyle(.plain)
                        }
                }
                Button {
                    let palette: [Color] = [.blue, .green, .orange, .purple, .teal, .pink]
                    withAnimation(AmbientMotion.snappy) { photos.append(palette[photos.count % palette.count]) }
                    AmbientHaptics.impact(.light)
                } label: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(height: 76)
                        .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(.secondary))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.caption.weight(.semibold))
                Text("Draft saved").font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text("PROPOSED").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            Text("Submit is in the bar, top right, and is never blocked.")
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ambientCard(density: .compact, border: .dashed(Color.secondary.opacity(0.35)), fillWidth: true)
        .padding(.bottom, 8)
    }

    // MARK: - success

    private var successState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green)
                Text("Report submitted").font(.title3.weight(.semibold))
                Text(Formatters.mediumDate.string(from: reportDate))
                    .font(.subheadline).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    line("Schools", stops.isEmpty ? "None" : stops.map(\.name).joined(separator: ", "))
                    line("Mileage", String(format: "%.1f mi · %@", miles, vehicle.capitalized))
                    line("Shot", shot.isEmpty ? "Nothing selected" : shot.sorted().joined(separator: ", "))
                    if !extras.isEmpty { line("Extra", extras.sorted().joined(separator: ", ")) }
                    line("Cards", cardsScanned ?? "Not answered")
                    line("Photos", photos.isEmpty ? "None" : "\(photos.count)")
                }
                .ambientCard(density: .roomy, fillWidth: true)
                .padding(.top, 4)

                Button {
                    withAnimation(AmbientMotion.gentle) { submitted = false }
                } label: {
                    Text("Back to the report")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        // ambient-allow: a control.
                        .background(Capsule().fill(Self.featureTint))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Text(value).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
