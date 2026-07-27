//  DailyReportView.swift
//  Iconik Employee — the daily job report, converted in AMB.7
//
//  Replaces Misc Features/DailyJobReportView.swift, deleted in the same commit.
//
//  THE DESIGN IS NOT COPIED FROM A MOCKUP — IT IS IMPORTED FROM ONE.
//      Every piece of chrome on this screen comes from Reports/ReportFormKit.swift
//      and every rule from Reports/ReportRules.swift and ReportSchoolLink.swift,
//      which are the SAME files the lab's ReportProposalMockup draws and runs.
//      There is therefore nothing to "match": this screen cannot have different
//      padding, a different checkbox, a different confirm layout or a different
//      school-ownership rule, because it does not own any of them. That is the
//      answer to the operator's question — how do you build it exactly as
//      designed rather than treating the design as inspiration.
//
//      scripts/test_report_rules.sh compiles those real files and runs them.
//
//  WHAT THE APPROVED DESIGN IS (v3, after two rejections)
//      ONE SCREEN. Nothing collapses, nothing expands. Ten peer sections with
//      the same heading, the same card and a status on the right of each, because
//      "nothing is secondary. it is all important" — a wrong school or vehicle is
//      a payroll error and a missing job description is a billing error.
//
//  WHAT THIS PHASE DELIBERATELY DID NOT BUILD, and why it is not a silent gap
//      · No draft and no autosave for the report itself. The mockup draws a draft
//        strip and marks it PROPOSED; drawing "Draft saved" here when nothing is
//        saved would be a lie, so the strip is NOT ported. Real draft persistence
//        is a data-layer change and is arc DJR.1.
//      · No offline handling. The live form has none, the mockup adds none.
//      · The mockup's success screen is not ported: on a real submit this screen
//        posts the shell's toast notification and the shell jumps to Home, which
//        is the shipped behaviour and is kept exactly.

import SwiftUI
import CoreLocation
import MapKit
import Supabase

/// A photographer the report can be filed under. Moved here from the deleted
/// DailyJobReportView, which was its only home and its only user.
struct PhotographerOption: Identifiable {
    let id: String            // user id
    let firstName: String
    let lastName: String

    var displayName: String { "\(firstName) \(lastName)" }
}

struct DailyReportView: View {

    // MARK: - Stored account data

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""
    @AppStorage("userHomeAddress") private var storedUserHomeAddress: String = ""
    /// The local photoshoot-note scratchpad, shared with PhotoshootNotesView and
    /// the iPad dashboard widget. Unchanged storage — a single JSON blob.
    @AppStorage("photoshootNotes") private var storedNotesData: Data = Data()

    // MARK: - What the app fills in

    @State private var reportDate = Date()
    @State private var photographers: [PhotographerOption] = []
    @State private var selectedPhotographerID: String = ""
    @StateObject private var schedule = ReportSchedule()
    /// Which session this report is for. The rule — first unreported session,
    /// once per date, a manual pick latches — lives in the tested type.
    @State private var sessionPick = SessionAutoSelect()
    /// Which schools are on the report and who put them there. Tested type.
    @State private var link = ReportSchoolLink()
    @State private var schoolOptions: [SchoolItem] = []
    @State private var isLoadingSchools = true
    /// The number and the one rule about it: a typed value is never overwritten.
    @State private var mileage = ReportMileage()
    @State private var isCalculatingMileage = false
    /// No default; both options take a second tap. Tested type.
    @State private var vehicle = VehicleSelection()

    // MARK: - The work

    @State private var shot: Set<String> = []
    @State private var extras: Set<String> = []
    @State private var cardsScanned: String?
    @State private var jobBox: String?
    @State private var sportsBackground: String?
    @State private var notes = ""
    @State private var selectedImages: [UIImage] = []

    // MARK: - Photoshoot note attachment

    @State private var photoshootNotes: [PhotoshootNote] = []
    @State private var attachedNoteID: UUID?

    // MARK: - Sheets, alerts, submission

    @State private var showSchoolPicker = false
    @State private var showImagePicker = false
    @State private var tempImage: UIImage?
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    /// Median mileage this photographer has claimed at a school before, per
    /// school id. Loaded once per school, only used for the advisory.
    @State private var usualMiles: [String: Double] = [:]
    /// Which route measurement is current. See `recalculateMileage`.
    @State private var mileageRun = 0
    @FocusState private var fieldFocused: Bool
    @ObservedObject private var tabBarManager = TabBarManager.shared

    /// The daily job report's own colour (D11) and the wash behind this screen.
    private var feature: Color { FeatureTheme.color(for: "dailyJobReport") }

    // MARK: - Derived

    private var dateKey: String { Formatters.isoDate.string(from: reportDate) }

    /// Schools on the report, resolved in ROUTE order — the order they were
    /// added, which is the order the mileage is calculated along.
    private var stops: [SchoolItem] {
        link.stops.compactMap { id in schoolOptions.first { $0.id == id } }
    }

    private var session: Session? {
        sessionPick.selection.flatMap { id in schedule.sessions.first { $0.id == id } }
    }

    private var selectedPhotographer: PhotographerOption? {
        photographers.first { $0.id == selectedPhotographerID }
    }

    /// Local drafts available to attach. A submitted note is not offered.
    private var availableNotes: [PhotoshootNote] {
        photoshootNotes.filter { $0.status == .draft }
    }

    private var attachedNote: PhotoshootNote? {
        attachedNoteID.flatMap { id in photoshootNotes.first { $0.id == id } }
    }

    private var miles: Double { mileage.value }

    /// Is the figure well out of line with what this photographer usually claims
    /// at this school? Only meaningful for a single-stop day.
    private var mileageLooksOff: Bool {
        guard stops.count == 1, let usual = usualMiles[stops[0].id], usual > 0 else { return false }
        return abs(miles - usual) / usual > 0.5
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: 0.3)
            form
        }
        .navigationTitle("Daily Job Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Submit lives in the bar and is NEVER blocked by a warning —
                // the one thing it validates is the vehicle, exactly as before.
                Button(action: attemptSubmit) {
                    if isSubmitting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Submit").font(.body.weight(.semibold))
                    }
                }
                .disabled(isSubmitting)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }
            }
        }
        .onAppear(perform: load)
        .onDisappear { schedule.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            // Re-subscribe when the app returns to the foreground. This must NOT
            // reset auto-select — a listener re-fire that clobbers a manual pick
            // is the bug SessionAutoSelect's latch exists to prevent.
            schedule.start(for: reportDate, onChange: runAutoSelect)
        }
        // The route changed, so the calculated figure changes. ReportMileage is
        // what guarantees this cannot clobber a value the photographer typed.
        .onChange(of: link) { _ in
            recalculateMileage()
            loadUsualMileage()
        }
        .onChange(of: reportDate) { newDate in
            // A new date is a different day's sessions, so auto-select starts
            // over — and "which sessions have I already reported" is re-asked,
            // because the answer is per-day.
            sessionPick.dateChanged()
            link.set(nil, for: .session)
            schedule.start(for: newDate, onChange: runAutoSelect)
            refreshReported()
        }
        .alert("Error", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showSchoolPicker) {
            ReportSchoolPickerSheet(
                schools: $schoolOptions,
                chosen: link.stops,
                organizationID: storedUserOrganizationID,
                onPick: { school in
                    withAnimation(AmbientMotion.snappy) { link.addStop(school.id) }
                    showSchoolPicker = false
                },
                onCancel: { showSchoolPicker = false })
        }
        .sheet(isPresented: $showImagePicker) {
            // One image per presentation, photo library only — unchanged. The
            // camera is Photoshoot Notes' capability and stays there.
            ImagePicker(selectedImage: $tempImage)
                .onDisappear {
                    if let image = tempImage {
                        selectedImages.append(image)
                        tempImage = nil
                    }
                }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                whenSection
                sessionSection
                schoolsSection
                mileageSection
                shotSection
                extrasSection
                scanSection
                noteAttachmentSection
                notesSection
                photosSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .ambientNoBounceWhenShort()
    }

    // MARK: - Section chrome, delegated not duplicated

    private func section<Content: View>(_ title: String, status: String,
                                        statusTint: Color? = nil,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        ReportSection(title: title, status: status, statusTint: statusTint, content: content)
    }

    // MARK: - 1. Date and photographer

    private var whenSection: some View {
        section("Date and photographer", status: Formatters.relativeDay(reportDate)) {
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
                    if photographers.isEmpty {
                        HStack(spacing: 6) {
                            Text("Loading photographers…").font(.subheadline).foregroundStyle(.tertiary)
                            ProgressView().scaleEffect(0.7)
                        }
                    } else {
                        Picker("", selection: $selectedPhotographerID) {
                            ForEach(photographers) { person in
                                Text(person.displayName).tag(person.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: selectedPhotographerID) { _ in
                            // "Already reported" is keyed on the photographer, so
                            // a change re-asks the question before auto-select
                            // can use the answer.
                            refreshReported()
                        }
                    }
                }
                .padding(.vertical, 7)
            }
        }
    }

    // MARK: - 2. Session

    /// THE SESSION LINK — `session_id` / `session_name` on the row. It is what
    /// ties a report to the schedule and what fills the school in. Off-schedule
    /// is a first-class choice, not a fallback.
    private var sessionSection: some View {
        section("Session",
                status: session == nil ? "off-schedule" : "linked",
                statusTint: session == nil ? nil : feature) {
            VStack(alignment: .leading, spacing: 2) {
                if schedule.isLoadingSessions {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Checking your schedule…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                ForEach(schedule.sessions) { option in
                    sessionRow(option)
                }
                sessionRow(nil)

                Divider()

                if let session {
                    Label("Filled in \(session.schoolName) below. Change anything it got wrong.",
                          systemImage: "arrow.turn.down.right")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if schedule.sessions.isEmpty && !schedule.isLoadingSessions {
                    Text("Nothing scheduled for this day. The report still files normally.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not linked to the schedule. The report still files normally.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !schedule.sessions.isEmpty {
                    // The live form's green "N sessions scheduled today" line,
                    // kept — minus the hardcoded "today", which it printed even
                    // on a back-dated report.
                    Text("\(schedule.sessions.count) session\(schedule.sessions.count == 1 ? "" : "s") scheduled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// `nil` renders the off-schedule row.
    private func sessionRow(_ option: Session?) -> some View {
        let on = sessionPick.selection == option?.id
        let reported = option.map { schedule.reportedSessionIDs.contains($0.id) } ?? false
        return Button {
            withAnimation(AmbientMotion.snappy) {
                sessionPick.pick(option?.id)
                // Picking a session REPLACES its school; choosing off-schedule
                // removes it. A school added by hand, or one the photoshoot note
                // is holding, is never touched. Tested rule.
                link.set(schoolID(named: option?.schoolName), for: .session)
            }
            AmbientHaptics.selection()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? AnyShapeStyle(feature) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option?.reportDisplayLabel ?? "No scheduled session (off-schedule)")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if reported {
                        Text("You already filed a report for this one")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }

    private func schoolID(named name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        return schoolOptions.first { $0.name == name }?.id
    }

    // MARK: - 3. Schools

    private var schoolsSection: some View {
        section("Schools",
                status: stops.isEmpty ? "none yet" : "\(stops.count) selected",
                statusTint: stops.isEmpty ? nil : feature) {
            VStack(alignment: .leading, spacing: 10) {
                if isLoadingSchools && schoolOptions.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading schools…").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if stops.isEmpty {
                    Text("No schools on this report yet — an off-schedule day still needs one.")
                        .font(.subheadline).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    AmbientFlowLayout(spacing: 7, lineSpacing: 7) {
                        ForEach(stops) { school in
                            HStack(spacing: 6) {
                                Text(school.name).font(.system(size: 13, weight: .semibold))
                                Button {
                                    withAnimation(AmbientMotion.snappy) { link.removeStop(school.id) }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(school.name)")
                            }
                            .foregroundStyle(feature)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            // ambient-allow: a token chip is a control, not a card.
                            .background(Capsule().fill(feature.opacity(0.13)))
                        }
                    }
                }

                Button { showSchoolPicker = true } label: {
                    Label("Add a school", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(feature)
                }
                .buttonStyle(.plain)
                .disabled(schoolOptions.isEmpty)
            }
        }
    }

    // MARK: - 4. Mileage and vehicle

    private var mileageSection: some View {
        section("Mileage and vehicle",
                status: vehicle.confirmed == nil
                    ? String(format: "%.1f mi · vehicle needed", miles)
                    : String(format: "%.1f mi · %@", miles, vehicle.confirmed!.rawValue.capitalized),
                statusTint: (mileageLooksOff || vehicle.confirmed == nil) ? .orange : feature) {
            mileageBody
        }
    }

    private var mileageBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Total").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                TextField(String(format: "%.1f", mileage.calculated),
                          text: Binding(get: { mileage.displayText },
                                        set: { mileage.type($0) }))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(width: 84)
                    .focused($fieldFocused)
                Text("miles").font(.subheadline).foregroundStyle(.secondary)
            }

            Divider()

            // Vehicle lives WITH the mileage — one decision, not two sections —
            // and the two-step confirmation appears inline, directly under the
            // buttons that raised it.
            ReportVehiclePicker(selection: $vehicle, tint: feature)

            if isCalculatingMileage {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Calculating route distances…").font(.caption).foregroundStyle(.secondary)
                }
            }

            // The route, always. A bare number is what gets accepted unread.
            if !stops.isEmpty && !mileage.isOverridden {
                Text((["Home"] + stops.map(\.name) + ["Home"]).joined(separator: " → "))
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if storedUserHomeAddress.isEmpty {
                Label("No home address on your profile, so the route cannot be measured. Type the mileage in yourself.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if mileage.isOverridden {
                HStack(spacing: 6) {
                    Text("You typed this — it won't be overwritten.")
                        .font(.caption).foregroundStyle(.orange)
                    Button {
                        withAnimation(AmbientMotion.snappy) { mileage.useCalculated() }
                    } label: {
                        Text("Use \(String(format: "%.1f", mileage.calculated))")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
            if mileageLooksOff, let usual = stops.first.flatMap({ usualMiles[$0.id] }) {
                Label(String(format: "You usually claim %.1f at %@", usual, stops.first?.name ?? ""),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 5 and 6. The two lists

    private var shotSection: some View {
        listSection(title: "What did you shoot?",
                    groups: ReportOptions.jobDescriptionGroups,
                    selection: $shot,
                    tint: .orange)
    }

    private var extrasSection: some View {
        listSection(title: "Anything extra?",
                    groups: ReportOptions.extraItemGroups,
                    selection: $extras,
                    tint: .pink)
    }

    private func listSection(title: String, groups: [(String, [String])],
                             selection: Binding<Set<String>>, tint: Color) -> some View {
        section(title,
                status: selection.wrappedValue.isEmpty
                    ? "select all that apply"
                    : "\(selection.wrappedValue.count) selected",
                statusTint: selection.wrappedValue.isEmpty ? nil : tint) {
            ReportMultiSelect(groups: groups, selection: selection, tint: tint)
        }
    }

    // MARK: - 7. Cards and job box

    private var scanSection: some View {
        let answered = [cardsScanned, jobBox, sportsBackground].compactMap { $0 }.count
        return section("Cards and job box",
                       status: "\(answered) of 3 answered",
                       statusTint: answered == 3 ? .teal : nil) {
            VStack(alignment: .leading, spacing: 14) {
                ReportChoiceRow(title: "Cards scanned",
                                options: ReportOptions.yesNo, selection: $cardsScanned)
                ReportChoiceRow(title: "Job box and camera cards turned in",
                                options: ReportOptions.yesNoNA, selection: $jobBox)
                ReportChoiceRow(title: "Sports background shot",
                                options: ReportOptions.yesNoNA, selection: $sportsBackground)
            }
        }
    }

    // MARK: - 8. Photoshoot note

    /// Attaching a note fills the school in, COPIES the note's photos onto the
    /// report, and its text is editable here and saved on every keystroke. On a
    /// successful submit the note is consumed.
    private var noteAttachmentSection: some View {
        section("Photoshoot note",
                status: attachedNote == nil ? "none attached" : "attached",
                statusTint: attachedNote == nil ? nil : feature) {
            VStack(alignment: .leading, spacing: 10) {
                if availableNotes.isEmpty {
                    Text("No photoshoot notes available.")
                        .font(.subheadline).foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(availableNotes) { note in
                            noteRow(note)
                        }
                        noteRow(nil)
                    }
                }

                if let attached = attachedNote,
                   let index = photoshootNotes.firstIndex(where: { $0.id == attached.id }) {
                    Divider()
                    Text(attached.school.isEmpty ? "Note" : "Note for \(attached.school)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    // THE ONLY AUTOSAVE ON THIS SCREEN, and it is the live
                    // behaviour: every keystroke writes back to the shared blob.
                    TextEditor(text: Binding(
                        get: { photoshootNotes[index].noteText },
                        set: { newValue in
                            photoshootNotes[index].noteText = newValue
                            savePhotoshootNotes()
                        }))
                        .frame(minHeight: 72)
                        .font(.subheadline)
                        .scrollContentBackground(.hidden)
                        .focused($fieldFocused)
                    if !attached.photoURLs.isEmpty {
                        Label("\(attached.photoURLs.count) photo\(attached.photoURLs.count == 1 ? "" : "s") from this note will be copied onto the report.",
                              systemImage: "photo.on.rectangle.angled")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// `nil` renders the "don't attach one" row.
    private func noteRow(_ note: PhotoshootNote?) -> some View {
        let on = attachedNoteID == note?.id
        return Button {
            withAnimation(AmbientMotion.snappy) { attach(note) }
            AmbientHaptics.selection()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? AnyShapeStyle(feature) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.map { noteLabel($0) } ?? "No photoshoot note")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note, !note.noteText.isEmpty {
                        Text(note.noteText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }

    private func noteLabel(_ note: PhotoshootNote) -> String {
        let time = Formatters.shortTime.string(from: note.timestamp)
        return note.school.isEmpty ? "\(time) — no school yet" : "\(time) — \(note.school)"
    }

    // MARK: - 9. Notes

    private var notesSection: some View {
        section("Notes",
                status: notes.isEmpty ? "nothing written" : "\(notes.count) characters",
                statusTint: notes.isEmpty ? nil : feature) {
            TextEditor(text: $notes)
                .frame(minHeight: 96)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .focused($fieldFocused)
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

    // MARK: - 10. Photos

    private var photosSection: some View {
        section("Photos",
                status: selectedImages.isEmpty ? "none attached" : "\(selectedImages.count) attached",
                statusTint: selectedImages.isEmpty ? nil : feature) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
                        // ambient-allow: a photo thumbnail is content, not a card.
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(AmbientMotion.snappy) {
                                    guard selectedImages.indices.contains(index) else { return }
                                    selectedImages.remove(at: index)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .padding(3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove photo \(index + 1)")
                        }
                }
                Button { showImagePicker = true } label: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(height: 76)
                        .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add photo")
            }
        }
    }

    // MARK: - Loading

    private func load() {
        loadPhotoshootNotes()
        loadPhotographers()
        loadSchools()
        schedule.start(for: reportDate, onChange: runAutoSelect)
    }

    private func loadPhotoshootNotes() {
        // A corrupt blob currently wipes every visible draft with no message
        // (finding R5). Not repaired here — it is shared storage three screens
        // write, and repairing it belongs with that storage, not with a restyle.
        photoshootNotes = (try? JSONDecoder().decode([PhotoshootNote].self, from: storedNotesData)) ?? []
        // Auto-select ONLY when there is exactly one, which is the live rule.
        if attachedNoteID == nil, availableNotes.count == 1 {
            attach(availableNotes[0])
        }
    }

    private func savePhotoshootNotes() {
        if let encoded = try? JSONEncoder().encode(photoshootNotes) {
            storedNotesData = encoded
        }
    }

    private func loadPhotographers() {
        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "Unable to load photographers: not signed in or organization not found"
            return
        }
        Task {
            do {
                let members = try await TeamService.shared.getTeamMembers(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    let people = members
                        .map { PhotographerOption(id: $0.id, firstName: $0.firstName, lastName: $0.lastName ?? "") }
                        .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
                    self.photographers = people
                    if self.selectedPhotographerID.isEmpty {
                        // Exact first+last match on the stored name, else the first.
                        let mine = people.first {
                            $0.firstName == self.storedUserFirstName && $0.lastName == self.storedUserLastName
                        }
                        self.selectedPhotographerID = (mine ?? people.first)?.id ?? ""
                    }
                    self.refreshReported()
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func loadSchools() {
        guard !storedUserOrganizationID.isEmpty else {
            isLoadingSchools = false
            errorMessage = "Unable to load schools: not signed in or organization not found"
            return
        }
        Task {
            do {
                let schools = try await SchoolService.shared.getSchools(organizationID: storedUserOrganizationID)
                await MainActor.run {
                    self.schoolOptions = schools
                        .map { school in
                            SchoolItem(id: school.id,
                                       name: school.value,
                                       address: Self.address(of: school),
                                       coordinates: school.coordinates)
                        }
                        .sorted { $0.name.lowercased() < $1.name.lowercased() }
                    self.isLoadingSchools = false
                    // A session may already be picked but unresolvable until now.
                    self.runAutoSelect()
                    self.recalculateMileage()
                    self.loadUsualMileage()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSchools = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// The same address assembly the live form used, so a school reads the same
    /// here as everywhere else and the coordinate fallback is unchanged.
    private static func address(of school: School) -> String {
        let parts = [school.street, school.city, school.state, school.zip]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? school.value : parts.joined(separator: ", ")
    }

    private func refreshReported() {
        guard let photographer = selectedPhotographer else { return }
        Task {
            await schedule.refreshReported(photographerFirstName: photographer.firstName,
                                           organizationID: storedUserOrganizationID)
            await MainActor.run { runAutoSelect() }
        }
    }

    /// Runs the tested rule, then applies whatever it chose through the other
    /// tested rule. Both are safe to call repeatedly — auto-select runs at most
    /// once per date and never overrides a manual pick.
    private func runAutoSelect() {
        // Every gate here is one the live form had, for the same reason:
        //   · latched — a manual pick is never overridden by a listener re-fire
        //   · already run for this date — it decides once per date
        //   · schools loaded — a session must be able to resolve to a school, or
        //     the one deciding call would fill in nothing and never come back
        //   · photographer known and "already reported" answered — otherwise the
        //     first run offers a session that has already been filed
        guard !sessionPick.isLatched,
              sessionPick.ranFor != dateKey,
              !schedule.isLoadingSessions,
              schedule.hasCheckedReported,
              !schoolOptions.isEmpty else { return }

        sessionPick.run(for: dateKey, sessions: schedule.autoSelectCandidates)
        // Only the deciding call touches the school list, so a school the
        // photographer removed by hand is not silently put back by a refresh.
        link.set(schoolID(named: session?.schoolName), for: .session)
    }

    // MARK: - Mileage

    private func recalculateMileage() {
        // Every recalculation gets a number. A slow route measured for a school
        // list the photographer has since changed must not land on top of the
        // current one — the live form had no such guard, so an in-flight
        // calculation could overwrite the figure for a different route.
        mileageRun += 1
        let run = mileageRun

        guard !storedUserHomeAddress.isEmpty else {
            // No home address means no route to measure. The live form CLEARED
            // the field here, wiping a typed value; ReportMileage leaves a typed
            // value alone and simply has nothing calculated to offer.
            mileage.recalculate(to: 0)
            isCalculatingMileage = false
            return
        }

        let route: [String] = [storedUserHomeAddress]
            + stops.compactMap { stop -> String? in
                if let coordinates = stop.coordinates, !coordinates.isEmpty { return coordinates }
                return stop.address.isEmpty ? nil : stop.address
            }
            + [storedUserHomeAddress]

        guard route.count > 2 else {
            mileage.recalculate(to: 0)
            isCalculatingMileage = false
            return
        }

        isCalculatingMileage = true
        Task {
            var total = 0.0
            for index in 0..<(route.count - 1) {
                if let leg = await ReportRoute.miles(from: route[index], to: route[index + 1]) {
                    total += leg
                }
            }
            await MainActor.run {
                guard run == self.mileageRun else { return }
                self.mileage.recalculate(to: total)
                self.isCalculatingMileage = false
            }
        }
    }

    /// What this photographer usually claims at a single-stop school, so a
    /// figure well out of line with it can be flagged in place. Read-only, cached
    /// per school for the life of the screen.
    private func loadUsualMileage() {
        guard stops.count == 1, let school = stops.first,
              usualMiles[school.id] == nil,
              let photographer = selectedPhotographer,
              !storedUserOrganizationID.isEmpty else { return }

        let end = Date()
        guard let start = Calendar.current.date(byAdding: .month, value: -12, to: end) else { return }
        let schoolID = school.id
        let schoolName = school.name
        let firstName = photographer.firstName
        let organizationID = storedUserOrganizationID

        Task {
            do {
                let past = try await DailyJobReportService.shared.getReportsForSchool(
                    schoolName: schoolName, organizationID: organizationID,
                    startDate: start, endDate: end)
                let mine = past
                    .filter { $0.your_name == firstName && $0.total_mileage > 0 }
                    .map(\.total_mileage)
                    .sorted()
                guard mine.count >= 3 else { return }     // too few to be a norm
                let median = mine[mine.count / 2]
                await MainActor.run { usualMiles[schoolID] = median }
            } catch {
                print("⚠️ DailyReportView: mileage history lookup failed — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Attaching a note

    private func attach(_ note: PhotoshootNote?) {
        attachedNoteID = note?.id
        // Same rule as the session: replace this source's school, remove it when
        // you choose none, leave everything else alone.
        link.set(schoolID(named: note?.school), for: .note)
        if let note { importPhotos(from: note) }
    }

    /// Photos on a note are copied onto the report by downloading each URL — the
    /// live behaviour, kept.
    private func importPhotos(from note: PhotoshootNote) {
        for urlString in note.photoURLs {
            guard let url = URL(string: urlString) else { continue }
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }
                let incoming = image.pngData()
                await MainActor.run {
                    let alreadyHave = selectedImages.contains { $0.pngData() == incoming }
                    if !alreadyHave { selectedImages.append(image) }
                }
            }
        }
    }

    // MARK: - Submitting

    /// The ONE thing validated before submit, unchanged: the vehicle. A report
    /// with no school, no mileage and no job descriptions still submits.
    private func attemptSubmit() {
        guard let chosen = vehicle.confirmed else {
            errorMessage = "Please select whether this was your Personal vehicle or a Company vehicle before submitting."
            return
        }
        submit(vehicleType: chosen.rawValue)
    }

    private func submit(vehicleType: String) {
        guard let currentUserID = UserManager.shared.getCurrentUserIDUnified() else {
            errorMessage = "User not signed in."
            return
        }
        isSubmitting = true
        errorMessage = ""

        let note = attachedNote
        let images = selectedImages
        let organizationID = storedUserOrganizationID
        let stopNames = stops.map(\.name).joined(separator: ", ")
        // Always store a destination: when a session is picked but its school did
        // not resolve to a SchoolItem, fall back to the session's own name so the
        // destination is never lost.
        let destination = stopNames.isEmpty ? session?.schoolName : stopNames
        let yourName = selectedPhotographer?.firstName ?? ""

        Task {
            var photoURLs: [String] = []
            var failedUploads = 0

            if !images.isEmpty && !organizationID.isEmpty {
                let result = await ReportPhotoUpload.upload(
                    images, folder: "\(organizationID)/\(currentUserID)")
                photoURLs = result.urls
                failedUploads = result.failed
            } else if !images.isEmpty && organizationID.isEmpty {
                failedUploads = images.count
            }

            // Photos already on the attached note are carried across as URLs.
            if let note { photoURLs.append(contentsOf: note.photoURLs) }

            let report = DailyJobReport(
                id: UUID().uuidString.lowercased(),
                organizationID: organizationID,
                userId: currentUserID,
                date: reportDate,
                yourName: yourName,
                schoolOrDestination: destination,
                sessionId: session?.id,
                sessionName: session?.reportDisplayLabel,
                totalMileage: miles,
                vehicleType: vehicleType,
                jobDescriptions: shot.isEmpty ? nil : Array(shot),
                extraItems: extras.isEmpty ? nil : Array(extras),
                cardsScannedChoice: cardsScanned,
                jobBoxAndCameraCards: jobBox,
                sportsBackgroundShot: sportsBackground,
                jobDescriptionText: notes.isEmpty ? nil : notes,
                photoshootNoteID: note?.id.uuidString.lowercased(),
                photoshootNoteText: note?.noteText,
                photoURLs: photoURLs.isEmpty ? nil : photoURLs,
                reportType: "standard")

            do {
                let created = try await DailyJobReportService.shared.createReport(report)

                if let note {
                    do {
                        try await PhotoshootNoteService.shared.attachToReport(noteId: note.id,
                                                                             reportId: created.id)
                    } catch {
                        print("⚠️ DailyReportView: failed to link note to report — \(error.localizedDescription)")
                    }
                }

                await MainActor.run {
                    self.isSubmitting = false

                    // The used note is consumed now that its content is in the
                    // report. Its PHOTOS are deliberately not deleted — their
                    // URLs were copied onto the report above.
                    if let note, let index = self.photoshootNotes.firstIndex(where: { $0.id == note.id }) {
                        self.photoshootNotes.remove(at: index)
                        self.attachedNoteID = nil
                        self.savePhotoshootNotes()
                        Task { try? await PhotoshootNoteService.shared.deleteNote(id: note.id) }
                    }

                    if failedUploads > 0 {
                        // The report is filed either way — that is the shipped
                        // behaviour. What changes is that the loss is NAMED
                        // rather than being an error alert beside a success.
                        self.errorMessage = "Report submitted, but \(failedUploads) photo\(failedUploads == 1 ? "" : "s") could not be uploaded and \(failedUploads == 1 ? "is" : "are") not attached to it."
                    }

                    // The screen does not dismiss itself: it tells the shell,
                    // which shows the toast and returns to Home.
                    NotificationCenter.default.post(name: Notification.Name("ShowReportSuccessToast"), object: nil)
                    self.tabBarManager.selectedTab = "home"
                }
            } catch {
                await MainActor.run {
                    self.isSubmitting = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Route measurement

/// Driving distance between two waypoints, each either a "lat,lng" pair or a
/// street address. Lifted verbatim in behaviour from the deleted form — real
/// MKDirections driving routes, not straight lines — and wrapped in async so the
/// caller is a loop rather than a DispatchGroup.
enum ReportRoute {

    static func miles(from origin: String, to destination: String) async -> Double? {
        guard let start = await coordinate(for: origin),
              let end = await coordinate(for: destination) else { return nil }
        return await drive(from: start, to: end)
    }

    /// A waypoint written as "lat,lng" needs no geocoding at all, which is why
    /// schools carrying coordinates are preferred over their addresses.
    ///
    /// Deliberately NOT an overload of `coordinate(for:)` — a sync and an async
    /// function with the same name resolve to the async one inside an async
    /// context, so the "fast path" would have called itself forever.
    private static func parseCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func coordinate(for text: String) async -> CLLocationCoordinate2D? {
        if let parsed = parseCoordinate(text) { return parsed }
        let placemarks = try? await CLGeocoder().geocodeAddressString(text)
        return placemarks?.first?.location?.coordinate
    }

    private static func drive(from origin: CLLocationCoordinate2D,
                              to destination: CLLocationCoordinate2D) async -> Double? {
        let request = MKDirections.Request()
        request.transportType = .automobile
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return nil }
        return route.distance * 0.000621371
    }
}

// MARK: - Photo upload

/// Uploading a report's photos, and counting what did not make it.
///
/// The live form set an error alert inside its upload loop and then submitted
/// anyway, so a failed photo produced an error AND a success with the photo
/// silently missing (finding R34). The submit behaviour is unchanged — a photo
/// failure has never blocked a report and this phase does not change that — but
/// the count comes back so the caller can SAY what was lost.
enum ReportPhotoUpload {

    /// - Parameters:
    ///   - folder: the directory prefix inside the `daily-reports` bucket. Each
    ///     caller keeps the layout it already writes — the standard report uses
    ///     `org/user`, the template form `template-reports/user` — because the
    ///     objects already in storage are addressed by those paths.
    ///   - maxDimension: nil uploads the image as-is, which is what the standard
    ///     report has always done. The template path downsamples, so it passes a
    ///     number. Deliberately not harmonised: that would change the bytes this
    ///     phase stores, and a design phase does not do that quietly.
    static func upload(_ images: [UIImage], folder: String,
                       maxDimension: CGFloat? = nil) async -> (urls: [String], failed: Int) {
        let storage = SupabaseManager.shared.client.storage
        var urls: [String] = []
        var failed = 0

        for image in images {
            let encoded: Data? = maxDimension.map {
                image.downsampledJPEGData(maxDimension: $0, quality: 0.8)
            } ?? image.jpegData(compressionQuality: 0.8)
            guard let data = encoded else {
                failed += 1
                continue
            }
            let path = "\(folder)/\(Date().timeIntervalSince1970)_\(UUID().uuidString.lowercased()).jpg"
            do {
                _ = try await storage.from("daily-reports").upload(path, data: data)
                // Signed URL, one year — the app's existing expiry everywhere.
                let signed = try await storage.from("daily-reports")
                    .createSignedURL(path: path, expiresIn: 31_536_000)
                urls.append(signed.absoluteString)
            } catch {
                print("❌ ReportPhotoUpload: \(error.localizedDescription)")
                failed += 1
            }
        }
        return (urls, failed)
    }
}
