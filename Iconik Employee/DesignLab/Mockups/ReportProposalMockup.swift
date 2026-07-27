//  ReportProposalMockup.swift
//  Iconik Employee — AMB.7, the SECOND daily-report design
//
//  ARC SCAFFOLDING. Deleted at AMB.7's close.
//
//  WHY A SECOND ONE
//      The operator's verdict on the first was correct: "you prettied up what I
//      already had. You didn't really change it in any meaningful way." It kept
//      the same information architecture — a long form of sections you fill in —
//      and restyled it. This one changes the architecture. Both are in the lab
//      so they can be compared on a device rather than argued about.
//
//  THE ONE IDEA
//      A daily job report is not a form. It is a CLAIM ABOUT A DAY THE APP
//      ALREADY KNOWS MOST OF — and it is filed by the same person, at the same
//      schools, doing the same kinds of shoot, roughly 200 times a year.
//
//      So the app writes the report and the photographer CORRECTS IT. The
//      default path is: open, glance, submit. The screen's real job is not
//      collecting answers — it is making the two or three things that are
//      UNUSUAL about today impossible to miss.
//
//  WHAT THE RESEARCH ACTUALLY SAID, and how each finding is spent here
//
//    1. DO NOT BUILD A WIZARD. The roadmap's own DJR.1 proposes one. NN/g is
//       explicit that wizards "become annoying and overly controlling if they
//       have to be used over and over," and that for repeat users you should
//       "consider offering another faster alternative." The Ministry of Justice
//       applied GOV.UK's one-thing-per-page to professional repeat users and
//       reported it "slow and disorientating." GOV.UK's own guidance carves out
//       services "where users need to repeat and switch between tasks quickly."
//       -> Everything stays on ONE screen. Editing happens in place.
//
//    2. PREFILL IS DANGEROUS IN ONE SPECIFIC DIRECTION. Controlled studies on
//       prepopulated tax returns found compliance HIGHEST with correct prefills
//       and LOWEST when the prefill understated what was owed — people check a
//       prefilled number when it costs them and let it stand when it favours
//       them. An accuracy-confirmation step only helped in the direction that
//       cost them. Mileage here feeds reimbursement, so a high number will not
//       get corrected.
//       -> Mileage is never presented as a bare figure to accept. The route it
//          came from is always shown, and a figure out of line with this
//          photographer's own history at this school is raised as an exception.
//
//    3. COPY THE CATEGORICAL, BLANK THE QUANTITATIVE. Every serious daily-log
//       product converged on copy-from-previous, and the valuable part is what
//       they REFUSE to copy. Procore excludes weather and photos because they
//       are point-in-time, offers a mode that copies the crew but ZEROES the
//       hours, and stamps a copied entry with the fact that it was copied.
//       Raken makes bringing the hours a separate opt-in.
//       -> School and job types are inherited. Mileage, notes, photos and the
//          three scan answers ALWAYS start empty. They are today's measurements.
//
//    4. CARRIED-FORWARD CONTENT PROPAGATES ERRORS SILENTLY. 66-90% of clinicians
//       routinely copy-paste; the documented mechanism is that one wrong value
//       rides along through every subsequent copy until somebody notices.
//       -> Every value on this screen carries its PROVENANCE. What the schedule
//          said, what was calculated, what came from your habits, and what you
//          typed are visually distinct. Procore's audit trail, made visible.
//
//    5. A CONFIRMATION THAT FIRES EVERY TIME STOPS BEING READ. Clinical alerts
//       are overridden 90-96% of the time. The vehicle two-step currently fires
//       on every single report.
//       -> The vehicle defaults to the one you almost always use, and the
//          confirmation fires when it CHANGES. The safeguard is kept and aimed.
//          THIS IS A PROPOSAL ABOUT A PAYROLL SAFEGUARD AND IS MARKED AS ONE.
//
//    6. DO NOT REORDER A LIST BY RECENCY. A controlled CHI study found adaptive
//       menus measurably SLOWER than a static order; frequent users build motor
//       memory for position.
//       -> The 22 job descriptions keep their shipped order, always. What the
//          session suggests is PINNED ABOVE the list, not sorted into it.
//
//    7. REVIEW BY EXCEPTION, NOT BY SUMMARY. SafetyCulture's completion flow
//       walks only the FLAGGED responses. A full "check your answers" screen on
//       day 200 is scrolled past unread — and the tax research showed a generic
//       confirmation step does not catch errors that favour the user.
//       -> The top of the screen is an exceptions strip, and nothing else.
//
//    8. SOFT GATE, ALWAYS. The products that hard-block on required fields are
//       the ones whose reviews carry the data-loss stories. Fulcrum offers
//       save-as-draft instead of blocking; Jobber offers "Complete visit anyway".
//       -> Submit is never disabled. Exceptions warn; they do not block.
//
//    9. KEEP POINT-TO-POINT MILEAGE, DO NOT ADD GPS TRIP DETECTION. Automatic
//       trip trackers split a journey at every stop of ~15 minutes and need a
//       manual merge to rebuild a day; a photographer hitting four schools is
//       the worst case for that model, and the top real complaint across those
//       products is SILENT NON-CAPTURE — the same failure class as AMB.6's chat.
//       -> What the app already does (route between named schools) is the
//          better architecture. It is kept, and the research is why.
//
//  WHAT IS STILL UNKNOWN, and only the operator can answer
//      Whether the org's session_types line up with the 22 hardcoded job
//      descriptions. The schedule stores session types as an ORG-CONFIGURED
//      vocabulary in the database; the report asks the same question again using
//      22 strings hardcoded in the iOS source. If those vocabularies match, the
//      biggest wall in the form is already answered and this design is nearly
//      free. If they do not, the suggestion strip below is weaker and the full
//      list does more of the work. The design degrades honestly either way — the
//      lab control at the top switches between them.

import SwiftUI

// MARK: - Provenance

/// Where a value on the report came from. The whole design rests on this being
/// visible: carried-forward content that looks identical to entered content is
/// exactly how a wrong value survives for weeks.
private enum Provenance {
    case schedule
    case calculated
    case habit
    case entered
    case empty

    var label: String? {
        switch self {
        case .schedule: return "from your schedule"
        case .calculated: return "calculated"
        case .habit: return "your usual"
        case .entered: return nil
        case .empty: return nil
        }
    }

    var tint: Color {
        switch self {
        case .schedule: return .blue
        case .calculated: return .teal
        case .habit: return .purple
        case .entered: return .primary
        case .empty: return .secondary
        }
    }

    var symbol: String? {
        switch self {
        case .schedule: return "calendar"
        case .calculated: return "function"
        case .habit: return "clock.arrow.circlepath"
        case .entered, .empty: return nil
        }
    }
}

/// Which day the lab is showing. Not a design element — it exists so the
/// operator can see the ordinary day AND the two that matter.
private enum LabDay: String, CaseIterable, Identifiable {
    case typical = "Ordinary day"
    case anomalous = "Something's off"
    case offSchedule = "Off-schedule"
    var id: String { rawValue }
}

// MARK: - Root

struct ReportProposalMockup: View {
    static let featureTint = Color(hex: "#3E63DD")

    @State private var day: LabDay = .typical
    @State private var typesMatch = true

    // The report itself.
    @State private var stops: [LabSchool] = [DesignLabSampleData.schools[1]]
    @State private var jobTypes: Set<String> = ["Fall Sports"]
    @State private var mileage: String = ""
    @State private var mileageEdited = false
    @State private var vehicle: String = DesignLabSampleData.History.usualVehicle
    @State private var cardsScanned: String?
    @State private var jobBox: String?
    @State private var notes = ""
    @State private var photos = 0

    // Which row is open for editing. Nil means the whole thing is a summary,
    // which is the state it should be in almost every day.
    @State private var editing: String?
    @State private var showVehicleConfirm = false
    @State private var pendingVehicle: String?
    @State private var submitted = false
    @State private var showAllTypes = false

    private var computed: Double { DesignLabSampleData.routeMiles(stops) }
    private var mileageValue: Double { Double(mileage) ?? computed }
    private var usual: Double? { stops.first.flatMap { DesignLabSampleData.History.usualMiles($0.name) } }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.7)
            if submitted { successState } else { content }
        }
        .navigationTitle("Today's Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Submit") {
                    withAnimation(AmbientMotion.gentle) { submitted = true }
                    AmbientHaptics.impact(.medium)
                }
                .font(.body.weight(.semibold))
                // NEVER disabled. Exceptions warn; they do not block.
            }
        }
        .confirmationDialog("Confirm Vehicle", isPresented: $showVehicleConfirm, titleVisibility: .visible) {
            Button("Personal") { commitVehicle("personal") }
            Button("Company") { commitVehicle("company") }
            Button("Cancel", role: .cancel) { pendingVehicle = nil }
        } message: {
            Text("You normally use your \(DesignLabSampleData.History.usualVehicle) vehicle. Confirm the change — this sets your mileage reimbursement.")
        }
        .onAppear(perform: applyDay)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                labControl
                header
                exceptionsStrip
                theDay
                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
    }

    // MARK: lab chrome

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Lab · the day", trailing: "not a design element")
            Picker("Day", selection: $day) {
                ForEach(LabDay.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: day) { _ in applyDay() }

            Toggle(isOn: $typesMatch) {
                Text("Session types match the 22 job descriptions")
                    .font(.caption)
            }
            Text(typesMatch
                 ? "The schedule's own vocabulary lines up, so what you shot is already answered and you are confirming it."
                 : "The schedule is coarser than the report, so it can only narrow the list — you still pick. The design has to survive both; only the operator knows which is true.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applyDay() {
        withAnimation(AmbientMotion.gentle) {
            editing = nil
            mileageEdited = false
            notes = ""
            photos = 0
            switch day {
            case .typical:
                stops = [DesignLabSampleData.schools[1]]
                jobTypes = ["Fall Sports"]
                mileage = ""
                vehicle = DesignLabSampleData.History.usualVehicle
                cardsScanned = nil
                jobBox = nil
            case .anomalous:
                // A four-school day: the mileage is genuinely much higher than
                // this photographer's usual at the first school, which is
                // exactly the case a bare prefilled number would sail through.
                stops = [DesignLabSampleData.schools[1], DesignLabSampleData.schools[7],
                         DesignLabSampleData.schools[2], DesignLabSampleData.schools[4]]
                jobTypes = ["Fall Sports", "Classroom Groups"]
                mileage = ""
                vehicle = "company"
                cardsScanned = nil
                jobBox = nil
            case .offSchedule:
                stops = []
                jobTypes = []
                mileage = ""
                vehicle = DesignLabSampleData.History.usualVehicle
                cardsScanned = nil
                jobBox = nil
            }
        }
    }

    // MARK: the header — what day this is

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Formatters.longDate.string(from: Date()))
                .font(.system(size: 20, weight: .bold))
            if day == .offSchedule {
                Text("Nothing on your schedule — this one is yours to write.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.caption2)
                    Text(stops.count == 1
                         ? "\(stops[0].name) · \(jobTypes.sorted().joined(separator: ", "))"
                         : "\(stops.count) schools · \(jobTypes.sorted().joined(separator: ", "))")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ambientCard(density: .roomy, fillWidth: true)
    }

    // MARK: exceptions — the only thing that should ever demand attention

    private var exceptions: [(text: String, detail: String, key: String)] {
        var found: [(String, String, String)] = []

        if let usual, stops.count == 1 || mileageEdited {
            let claimed = mileageValue
            if usual > 0, abs(claimed - usual) / usual > 0.5 {
                found.append((
                    String(format: "%.1f miles is well above your usual here", claimed),
                    String(format: "You have averaged %.1f at %@. Worth a look before this goes to payroll.",
                           usual, stops.first?.name ?? ""),
                    "mileage"))
            }
        } else if stops.count > 1 {
            found.append((
                String(format: "%.1f miles across %d schools", mileageValue, stops.count),
                "More stops than usual, so there is no past figure to compare against. Check the route below is the one you drove.",
                "mileage"))
        }

        if vehicle != DesignLabSampleData.History.usualVehicle {
            found.append((
                "You're claiming a \(vehicle) vehicle",
                "You normally use your \(DesignLabSampleData.History.usualVehicle) one. This changes the rate you're paid.",
                "vehicle"))
        }

        if cardsScanned == nil {
            found.append(("Cards scanned — not answered yet",
                          "The one thing here nobody else can tell us.", "scan"))
        }

        if stops.isEmpty {
            found.append(("No school on this report",
                          "Off-schedule days still need somewhere attached to them.", "schools"))
        }

        return found.map { (text: $0.0, detail: $0.1, key: $0.2) }
    }

    @ViewBuilder
    private var exceptionsStrip: some View {
        let items = exceptions
        if items.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nothing unusual about today").font(.subheadline.weight(.semibold))
                    Text("Everything below matches your schedule and your usual pattern.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .ambientCard(density: .roomy, state: .highlighted, glow: .green, fillWidth: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(items.count == 1 ? "One thing to check" : "\(items.count) things to check")
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                ForEach(items, id: \.key) { item in
                    Button {
                        withAnimation(AmbientMotion.snappy) { editing = item.key }
                        AmbientHaptics.impact(.light)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Color.orange).frame(width: 5, height: 5).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text).font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Text("These are the only things asking for you. Everything else is already right or already known.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ambientCard(density: .roomy, state: .highlighted,
                         border: .hairline(Color.orange.opacity(0.4)),
                         glow: .orange, fillWidth: true)
        }
    }

    // MARK: the day, as a readable document

    private var theDay: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("The day", trailing: "tap anything to change it")
            VStack(spacing: 0) {
                schoolsRow
                Divider()
                mileageRow
                Divider()
                vehicleRow
                Divider()
                shotRow
                Divider()
                scanRow
                Divider()
                notesRow
                Divider()
                photosRow
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
    }

    // MARK: rows

    private var schoolsRow: some View {
        row(key: "schools", icon: "building.2", title: "Schools",
            value: stops.isEmpty ? "None yet" : stops.map(\.name).joined(separator: ", "),
            provenance: stops.isEmpty ? .empty : (day == .offSchedule ? .entered : .schedule)) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(stops) { school in
                    HStack {
                        Text(school.name).font(.subheadline)
                        Spacer()
                        Button {
                            withAnimation(AmbientMotion.snappy) { stops.removeAll { $0.id == school.id } }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Menu {
                    ForEach(DesignLabSampleData.schools.filter { s in !stops.contains(where: { $0.id == s.id }) }) { school in
                        Button(school.name) {
                            withAnimation(AmbientMotion.snappy) { stops.append(school) }
                        }
                    }
                } label: {
                    Label("Add a school", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Self.featureTint)
                }
            }
        }
    }

    private var mileageRow: some View {
        row(key: "mileage", icon: "car", title: "Mileage",
            value: String(format: "%.1f miles", mileageValue),
            provenance: mileageEdited ? .entered : .calculated) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Total").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    TextField(String(format: "%.1f", computed), text: $mileage)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(width: 90)
                        .onChange(of: mileage) { _ in mileageEdited = !mileage.isEmpty }
                    Text("mi").font(.caption).foregroundStyle(.secondary)
                }

                // The route is ALWAYS shown. A bare number is what gets accepted
                // without looking; a route is something you can disagree with.
                if !stops.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("The route this came from")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text((["Home"] + stops.map(\.name) + ["Home"]).joined(separator: " → "))
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let usual {
                    Text(String(format: "You have averaged %.1f miles at %@.", usual, stops.first?.name ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }

                if mileageEdited {
                    Button {
                        withAnimation(AmbientMotion.snappy) { mileage = ""; mileageEdited = false }
                    } label: {
                        Text("Use the calculated \(String(format: "%.1f", computed))")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var vehicleRow: some View {
        row(key: "vehicle", icon: "key", title: "Vehicle",
            value: vehicle.capitalized,
            provenance: vehicle == DesignLabSampleData.History.usualVehicle ? .habit : .entered) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    vehicleButton("Personal")
                    vehicleButton("Company")
                }
                Text(vehicle == DesignLabSampleData.History.usualVehicle
                     ? "This is what you almost always use, so it is filled in. Changing it will ask you to confirm."
                     : "Changed from your usual \(DesignLabSampleData.History.usualVehicle) vehicle.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("PROPOSED — today this confirmation fires on EVERY report. Firing it only on a change is what keeps it from being tapped through automatically.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func vehicleButton(_ title: String) -> some View {
        let selected = vehicle == title.lowercased()
        return Button {
            let value = title.lowercased()
            // Confirm only when it differs from the habit. Otherwise commit.
            if value != DesignLabSampleData.History.usualVehicle {
                pendingVehicle = value
                showVehicleConfirm = true
            } else {
                commitVehicle(value)
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                // ambient-allow: a segmented control, not a container.
                .background(Capsule().fill(selected
                                           ? AnyShapeStyle(Self.featureTint)
                                           : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
    }

    private func commitVehicle(_ value: String) {
        withAnimation(AmbientMotion.snappy) { vehicle = value }
        pendingVehicle = nil
        AmbientHaptics.impact(.medium)
    }

    private var shotRow: some View {
        row(key: "shot", icon: "camera", title: "What you shot",
            value: jobTypes.isEmpty ? "Nothing yet" : jobTypes.sorted().joined(separator: ", "),
            provenance: jobTypes.isEmpty ? .empty : (typesMatch && day != .offSchedule ? .schedule : .entered)) {
            VStack(alignment: .leading, spacing: 10) {
                if typesMatch && day != .offSchedule {
                    Text("Your schedule already says what this shoot was, so it is filled in. Correct it if the day went differently.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if day != .offSchedule {
                    Text("Your schedule narrows it down but is not this specific — pick from the suggestions or the full list.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // PINNED above the list, never sorted INTO it — a list that
                // reorders itself is measurably slower for someone who has
                // learned where things are.
                if day != .offSchedule {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Suggested for this shoot")
                            .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                        AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(suggestedTypes, id: \.self) { option in
                                typeChip(option)
                            }
                        }
                    }
                }

                Button {
                    withAnimation(AmbientMotion.snappy) { showAllTypes.toggle() }
                } label: {
                    Text(showAllTypes ? "Hide the full list" : "All 22 job descriptions")
                        .font(.caption.weight(.semibold)).foregroundStyle(Self.featureTint)
                }
                .buttonStyle(.plain)

                if showAllTypes {
                    // Shipped order, always. No recency sorting.
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)], spacing: 9) {
                        ForEach(DesignLabSampleData.jobDescriptionOptions, id: \.self) { option in
                            checkbox(option)
                        }
                    }
                }
            }
        }
    }

    private var suggestedTypes: [String] {
        typesMatch
            ? ["Fall Sports", "Winter Sports", "Spring Sports"]
            : ["Fall Sports", "Winter Sports", "Spring Sports", "Sports League", "Classroom Groups"]
    }

    private func typeChip(_ option: String) -> some View {
        let on = jobTypes.contains(option)
        return Button {
            withAnimation(AmbientMotion.snappy) {
                if on { jobTypes.remove(option) } else { jobTypes.insert(option) }
            }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(option).font(.caption.weight(.semibold))
            }
            .foregroundStyle(on ? .white : .primary)
            .padding(.horizontal, 11).padding(.vertical, 7)
            // ambient-allow: a selection chip is a control.
            .background(Capsule().fill(on
                                       ? AnyShapeStyle(Self.featureTint)
                                       : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.1)))
        }
        .buttonStyle(.plain)
    }

    private func checkbox(_ option: String) -> some View {
        let on = jobTypes.contains(option)
        return Button {
            withAnimation(AmbientMotion.snappy) {
                if on { jobTypes.remove(option) } else { jobTypes.insert(option) }
            }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15)).foregroundStyle(on ? Self.featureTint : .secondary)
                Text(option).font(.caption).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scanRow: some View {
        let answered = [cardsScanned, jobBox].compactMap { $0 }.count
        return row(key: "scan", icon: "barcode.viewfinder", title: "Cards and job box",
                   value: answered == 0 ? "Not answered" : "\(answered) of 2 answered",
                   provenance: answered == 0 ? .empty : .entered) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Always starts empty. This is today's measurement, not something to inherit from yesterday.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                radioRow("Cards scanned", ["Yes", "No"], $cardsScanned)
                radioRow("Job box and camera cards turned in", ["Yes", "No", "NA"], $jobBox)
            }
        }
    }

    private func radioRow(_ title: String, _ options: [String], _ selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    Button {
                        withAnimation(AmbientMotion.snappy) { selection.wrappedValue = option }
                        AmbientHaptics.selection()
                    } label: {
                        Text(option)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selection.wrappedValue == option ? .white : .primary)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            // ambient-allow: a radio control, not a container.
                            .background(Capsule().fill(selection.wrappedValue == option
                                                       ? AnyShapeStyle(Color.teal)
                                                       : AnyShapeStyle(.ultraThinMaterial)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notesRow: some View {
        row(key: "notes", icon: "text.bubble", title: "Notes",
            value: notes.isEmpty ? "None" : notes,
            provenance: notes.isEmpty ? .empty : .entered) {
            TextEditor(text: $notes)
                .frame(minHeight: 90)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .padding(8)
                // ambient-allow: an input well, not a card.
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.1)))
        }
    }

    private var photosRow: some View {
        row(key: "photos", icon: "photo", title: "Photos",
            value: photos == 0 ? "None" : "\(photos)",
            provenance: photos == 0 ? .empty : .entered) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(0..<photos, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Self.featureTint.opacity(0.25))
                            .frame(width: 62, height: 62)
                            .overlay(Image(systemName: "photo").foregroundStyle(Self.featureTint))
                    }
                    Button {
                        withAnimation(AmbientMotion.snappy) { photos += 1 }
                    } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.4),
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(width: 62, height: 62)
                            .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                }
                if photos > 0 {
                    Button {
                        withAnimation(AmbientMotion.snappy) { photos = 0 }
                    } label: {
                        Text("Remove all").font(.caption.weight(.semibold)).foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: the row primitive

    /// A readable line that becomes an editor in place. Not a push, not a sheet,
    /// not a wizard step — everything stays on one screen, which is what the
    /// evidence supports for someone doing this 200 times a year.
    @ViewBuilder
    private func row<Editor: View>(key: String, icon: String, title: String,
                                   value: String, provenance: Provenance,
                                   @ViewBuilder editor: () -> Editor) -> some View {
        let open = editing == key
        VStack(alignment: .leading, spacing: open ? 10 : 0) {
            Button {
                withAnimation(AmbientMotion.snappy) { editing = open ? nil : key }
                AmbientHaptics.impact(.light)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(provenance == .empty ? .tertiary : .primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        // The provenance mark. This is the mitigation for
                        // carried-forward content looking identical to entered
                        // content — the failure mode that lets a wrong value
                        // ride along for weeks.
                        if let label = provenance.label {
                            HStack(spacing: 3) {
                                if let symbol = provenance.symbol {
                                    Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                                }
                                Text(label).font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(provenance.tint)
                        }
                    }

                    Spacer(minLength: 0)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            if open {
                editor()
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.caption.weight(.semibold))
                Text("Draft saved").font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text("PROPOSED").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)

            Text("Submit is never blocked. Anything still open is a warning, not a wall — a report filed from a car park with one bar has to survive, and the products that hard-block are the ones whose reviews are full of lost work.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, border: .dashed(Color.secondary.opacity(0.35)), fillWidth: true)
        .padding(.bottom, 8)
    }

    // MARK: success

    private var successState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52)).foregroundStyle(.green)
                Text("Report filed").font(.title3.weight(.semibold))
                Text(Formatters.mediumDate.string(from: Date()))
                    .font(.subheadline).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    line("Schools", stops.isEmpty ? "None" : stops.map(\.name).joined(separator: ", "))
                    line("Mileage", String(format: "%.1f mi · %@", mileageValue, vehicle.capitalized))
                    line("Shot", jobTypes.isEmpty ? "Nothing recorded" : jobTypes.sorted().joined(separator: ", "))
                    line("Cards", cardsScanned ?? "Not answered")
                    line("Photos", photos == 0 ? "None" : "\(photos)")
                }
                .ambientCard(density: .roomy, fillWidth: true)
                .padding(.top, 4)

                Button {
                    withAnimation(AmbientMotion.gentle) { submitted = false; applyDay() }
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
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Text(value).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
