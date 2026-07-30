//  ClassGroupsMockup.swift
//  Iconik Employee — AMB.10's Class Groups mockup, built in batch 3
//
//  ARC SCAFFOLDING. Deleted at AMB.10's close, with the rest of the lab going at
//  AMB.12.
//
//  THE DESIGN NO LONGER LIVES HERE. Since the AMB.10 conversion this file IMPORTS
//  `Class Groups/ClassGroupsKit.swift` and `Class Groups/ClassGroupsRules.swift` —
//  the same components and the same sentences the real screens draw — so the lab
//  and production cannot diverge. What is left in this file is the three things a
//  lab is for: SAMPLE DATA seeded with the cases that decide the design, the
//  lab-state pickers, and the PROPOSED captions that state which parts of the
//  design are asking for a decision rather than describing today.
//  See [[design-lives-in-production-code]].
//
//  WHAT THE DESIGN IS ARGUING, in four claims the operator accepted 2026-07-29
//
//      1. A JOB CARD SHOULD SAY WHEN — WITH THE YEAR — AND HOW MUCH IS DONE.
//         The old row formatted the session date `"EEEE, MMM d"` — no year. School
//         photography runs the same weeks every August, and the list is sorted
//         date-DESCENDING with no year anywhere on it, so last year's job and this
//         year's job were two cards reading "Tuesday, Aug 4". The date carries the
//         year now, drawn through `Formatters.longDate` rather than a fourth
//         private formatter. → `ClassGroupJobCard`
//
//      2. THE DETAIL SCREEN SHOULD SHOW THE DATE AND THE NOTE BODIES.
//         The old detail screen never showed the session date at all (parity §A.2)
//         — you could stand in a school looking at a job and not be told which day
//         it is for. And a row with a note drew an orange "Has notes" HINT: the
//         body was only readable by opening the Edit sheet. A note a photographer
//         typed for themselves is the whole reason the field exists; it goes on the
//         row. → `ClassGroupJobHero`, `ClassGroupRowCard`
//
//      3. A GROUP ROW'S WHOLE CARD SHOULD BE TAPPABLE.
//         The old row carried `.contentShape(Rectangle())` with NO tap gesture — so
//         the row read tappable, and was not. The only edit target was an invisible
//         36pt pencil. The card takes the tap; the slate keeps its own button
//         because it is a different, and much louder, destination.
//         → `ClassGroupRowCard`
//
//      4. THE SLATE STAYS A PLAIN WHITE WHITEBOARD, ON PURPOSE.
//         `ClassGroupSlateView` is deliberately not theme-aware: it is a whiteboard
//         held up in front of a class so the frame is labelled. It gets NO ambient
//         treatment, no wash, no card — styling it would break it. The one change
//         made is dismissal (see the slate section). → `ClassGroupSlateBoard`
//
//  WHAT IS NOT PROPOSED
//      No data layer, service, permission or business-rule changes (D12).
//      Specifically NOT promised, per AMB_BATCH3_PARITY.md §6: Class Groups EXPORT
//      (`exportToCSV` has no caller and no button), photos or thumbnails (the model
//      carries free-text image NUMBERS, never an image reference), per-item
//      assignment (the model has no assignee), and any club-specific field set
//      (clubs share the class-group row shape — `grade` holds the club name,
//      `teacher` the advisor — and that shape is a contract with the web app).
//
//  VOCABULARY COMES FROM PRODUCTION
//      Every label below resolves through `ClassGroupJobType` and the real
//      `ClassGroupJob` / `ClassGroup` models. The lab does not keep a second table
//      of the three types' nouns — that is the drift the "design lives in
//      production code the lab imports" rule exists to stop, and it is what let the
//      old row hardcode `person.3` for Clubs (parity §3).

import SwiftUI

// MARK: - Destinations

/// One enum, one `.ambientPush` — the AMB.3 rule. It carries the job's id so the
/// pushed screen is about the card that was tapped rather than about the first
/// card in the array.
private enum ClassGroupsDestination: Identifiable {
    case detail(String)

    var id: String {
        switch self {
        case .detail(let jobId): return "detail-\(jobId)"
        }
    }
}

/// Which state the root list is showing. A lab control, not a design element.
private enum ClassGroupsListState: String, CaseIterable, Identifiable {
    case populated = "Jobs"
    case empty = "Empty"
    case deleting = "Deleting"

    var id: String { rawValue }
}

// MARK: - Root: the jobs list

struct ClassGroupsMockup: View {
    /// The feature's own colour (D11) — the registered `FeatureTheme` green,
    /// `#46A758`, read through the kit rather than restated here.
    static let featureTint = ClassGroupsStyle.tint

    @State private var jobType: String = ClassGroupJobType.classGroups
    @State private var state: ClassGroupsListState = .populated
    @State private var destination: ClassGroupsDestination?
    @State private var showingCreate = false

    private var jobs: [ClassGroupJob] {
        ClassGroupsLabData.jobs.filter { $0.jobType == jobType }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    // 1 — THE TYPE SWITCHER, the real one. Three capsule chips
                    // replacing a segmented control that could not be tinted per
                    // option and read as system chrome on top of the wash.
                    ClassGroupTypeSwitcher(jobType: $jobType, tint: Self.featureTint)
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()

            addButton
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .detail(let jobId):
                ClassGroupJobDetailMockup(job: ClassGroupsLabData.job(id: jobId))
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateClassGroupJobMockup(jobType: jobType)
        }
    }

    // MARK: lab chrome

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · state", trailing: "not a design element")
            Picker("State", selection: $state) {
                ForEach(ClassGroupsListState.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: 2 — the list and its states

    @ViewBuilder
    private var content: some View {
        switch state {
        case .populated:
            if jobs.isEmpty { emptyState } else { list }
        case .empty:
            emptyState
        case .deleting:
            deletingState
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVStack(spacing: AmbientDensity.roomy.stackSpacing) {
                ForEach(jobs) { job in
                    Button {
                        destination = .detail(job.id)
                    } label: {
                        ClassGroupJobCard(job: job)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }

            // Swipe-to-delete a whole job is real and KEPT. It cannot be drawn
            // here: `.swipeActions`/`.onDelete` are List-only and these cards are a
            // LazyVStack. The converted screen keeps its `List` for exactly this
            // reason.
            Text("Swipe a job to delete it — unchanged. Not drawable on these cards: swipe actions are List-only, so the real screen stays a List.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The empty state's real copy and its real call to action, through the
    /// component's action slot — the slot that exists because AMB.6 lost Chat's
    /// button by converting to a component that had none.
    private var emptyState: some View {
        AmbientEmptyState(
            title: "No \(ClassGroupJobType.singularTitle(jobType)) Jobs",
            message: "Create a job for an upcoming session to start tracking \(ClassGroupJobType.rowNounPlural(jobType)).",
            systemImage: ClassGroupJobType.listEmptyIcon(jobType),
            actionTitle: "Create Job",
            actionIcon: "plus.circle.fill",
            action: { showingCreate = true },
            actionTint: Self.featureTint)
    }

    /// The destructive confirm, drawn as its copy so the words can be judged here.
    /// A real `.alert` cannot be evaluated in a mockup gallery — you would have to
    /// trigger it — and the words are the whole safety mechanism.
    private var deletingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            AmbientNoteCard(
                title: "Delete Job?",
                text: "This will delete the entire job and all its \(ClassGroupJobType.rowNounPlural(jobType)). This action cannot be undone.",
                accent: .red,
                density: .roomy)

            HStack(spacing: 8) {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    // ambient-allow: alert buttons, drawn so the pair can be read
                    // together — a control, not a container.
                    .background(Capsule().fill(.ultraThinMaterial))
                Text("Delete")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    // ambient-allow: a control.
                    .background(Capsule().fill(Color.red))
            }

            Text("The copy is unchanged — it already names what goes, and says it cannot be undone. SHIPPED with the conversion: a failed job delete used to be printed to the console and nothing else, so a job that did not delete looked deleted until the next load. It raises its own alert now, like the row-level delete always did.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 3 — the create route

    /// The real floating button. Drawn at the BOTTOM LEADING corner here only
    /// because the lab runner's mockup switcher owns bottom-trailing; on the
    /// converted screen it is bottom-TRAILING, reachable one-handed, and it
    /// REPLACED the toolbar "+" rather than joining it.
    private var addButton: some View {
        ClassGroupAddButton(tint: Self.featureTint) { showingCreate = true }
            .padding(.leading, 18)
            .padding(.bottom, 26)
    }
}

// MARK: - Detail

/// The job's rows. Three fixes land here: the session date exists, the note bodies
/// are readable, and the whole row takes the tap.
private struct ClassGroupJobDetailMockup: View {
    let job: ClassGroupJob

    @State private var editing: ClassGroup?
    @State private var slate: ClassGroup?

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: ClassGroupsMockup.featureTint, intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ClassGroupJobHero(schoolName: job.schoolName,
                                      jobType: job.jobType,
                                      sessionDate: job.sessionDate,
                                      totalsLine: ClassGroupsRules.totalsLine(
                                        jobType: job.jobType,
                                        groupCount: job.classGroupCount,
                                        imageCount: job.totalImageCount),
                                      tint: ClassGroupsMockup.featureTint)
                    if job.classGroups.isEmpty {
                        emptyState
                    } else {
                        rows
                    }
                    jobNotes
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(ClassGroupJobType.displayName(job.jobType))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { group in
            ClassGroupFormMockup(jobType: job.jobType, group: group, schoolName: job.schoolName)
        }
        .fullScreenCover(item: $slate) { group in
            ClassGroupSlateMockup(grade: group.grade, teacher: group.teacher,
                                  schoolName: job.schoolName)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(job.classGroups) { group in
                    ClassGroupRowCard(group: group,
                                      onEdit: { editing = group },
                                      onSlate: { slate = group },
                                      tint: ClassGroupsMockup.featureTint)
                        .ambientScrollFade()
                }
            }

            Text("Swipe a row to delete — unchanged. Not drawable on these cards: swipe actions are List-only, so the real screen stays a List.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The detail screen's empty state, with the PLURAL display name it really uses
    /// (the list's uses the singular — an inconsistency worth keeping an eye on
    /// rather than silently harmonising).
    private var emptyState: some View {
        AmbientEmptyState(
            title: "No \(ClassGroupJobType.displayName(job.jobType))",
            message: "Tap the + button to add \(ClassGroupJobType.rowNounPlural(job.jobType)) as you photograph them.",
            systemImage: ClassGroupJobType.detailEmptyIcon(job.jobType),
            actionTitle: "Add \(ClassGroupJobType.singularTitle(job.jobType))",
            actionIcon: "plus.circle.fill",
            action: {},
            actionTint: ClassGroupsMockup.featureTint)
    }

    /// `class_group_jobs.notes` — the JOB-level note — exists in the model, is
    /// written by the web app, and had never been displayed or editable anywhere in
    /// the iOS feature (parity §3). Read-only: showing what is already stored costs
    /// nothing, editing it needs a service method that does not exist.
    @ViewBuilder
    private var jobNotes: some View {
        if let notes = job.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                AmbientNoteCard(title: "Job notes", text: notes,
                                accent: ClassGroupsMockup.featureTint, density: .compact)
                Text("SHIPPED read-only. The job-level note is stored and written by the web app and had never been shown on iOS.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Add / Edit form

/// ONE form for add and edit. The feature used to have two line-for-line duplicate
/// views differing only in container, title and dismissal API — which is how they
/// came to disagree about navigation style (`NavigationView` + Stack vs
/// `NavigationStack`). One form, one set of rules: the real one is
/// `Class Groups/Views/ClassGroupFormView.swift`, and it draws these same sections.
private struct ClassGroupFormMockup: View {
    let jobType: String
    let group: ClassGroup
    let schoolName: String

    @Environment(\.dismiss) private var dismiss

    @State private var grade = ""
    @State private var teacher = ""
    @State private var imageNumbers = ""
    @State private var notes = ""
    @State private var showingSlate = false

    @FocusState private var focusedField: ClassGroupFormField?

    private var trimmedGrade: String {
        grade.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The live count: a naive comma split, so `"12,"` reads as 1. Kept as-is — it
    /// is what the stored string means, and a mockup that quietly counts better
    /// than production is a mockup that lies. It is `ClassGroupsRules.imageCount`,
    /// the same function the real form and the row badge call.
    private var imageCount: Int {
        ClassGroupsRules.imageCount(imageNumbers)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: ClassGroupsMockup.featureTint, intensity: 0.6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        informationSection
                        imagesSection
                        notesSection
                        ClassGroupWhiteboardButton(
                            primaryFieldLabel: ClassGroupJobType.primaryFieldLabel(jobType),
                            isEnabled: ClassGroupsRules.isFormValid(grade: grade),
                            tint: ClassGroupsMockup.featureTint) { showingSlate = true }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Edit \(ClassGroupJobType.singularTitle(jobType))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { dismiss() }
                        .disabled(!ClassGroupsRules.isFormValid(grade: grade))
                }
            }
        }
        .onAppear {
            grade = group.grade
            teacher = group.teacher
            imageNumbers = group.image_numbers
            notes = group.notes
        }
        .fullScreenCover(isPresented: $showingSlate) {
            // THE SLATE GETS A REAL SCHOOL NAME. Both old form paths passed
            // `schoolName: nil`, so the slate opened from the form was missing the
            // one line that tells you which school you are standing in — even
            // though the form was reached from a job that knows. Fixed in the
            // conversion: the detail screen passes it down.
            ClassGroupSlateMockup(grade: trimmedGrade, teacher: teacher, schoolName: schoolName)
        }
    }

    /// "Class Information" / "Candid Information" / "Club Information", and the
    /// field labels follow: Grade / Club Name, Teacher Name / Advisor Name.
    private var informationSection: some View {
        AmbientFormSection(
            title: "\(ClassGroupJobType.formNoun(jobType)) Information",
            status: trimmedGrade.isEmpty ? "required" : trimmedGrade,
            statusTint: trimmedGrade.isEmpty ? .orange : nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ClassGroupTextField(label: ClassGroupJobType.primaryFieldLabel(jobType),
                                    text: $grade,
                                    focus: $focusedField,
                                    field: .primary) {
                    focusedField = .secondary
                }

                // The old form hid 14 grades behind a `Menu` you had to know to
                // open. Chips put them on the surface — one tap, and the tap target
                // is the thing you are choosing.
                if ClassGroupJobType.showsGradeSuggestions(jobType) {
                    ClassGroupGradeChips(grade: $grade, tint: ClassGroupsMockup.featureTint)
                }

                Divider()
                ClassGroupTextField(label: ClassGroupJobType.secondaryFieldLabel(jobType),
                                    text: $teacher,
                                    focus: $focusedField,
                                    field: .secondary) {
                    focusedField = .images
                }
                Text("Optional. A row with no \(ClassGroupJobType.secondaryFieldLabel(jobType).lowercased()) shows the \(ClassGroupJobType.primaryFieldLabel(jobType).lowercased()) alone — not a dangling dash.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var imagesSection: some View {
        AmbientFormSection(
            title: "Images",
            status: ClassGroupsRules.imagesFieldStatus(count: imageCount),
            statusTint: imageCount == 0 ? nil : .blue
        ) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("1042, 1043, 1051", text: $imageNumbers)
                    .font(.subheadline)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focusedField, equals: .images)
                Text("Comma separated. These are frame NUMBERS, not photos — nothing in this feature stores an image.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The old editor had NO placeholder — an empty grey box with a heading. One is
    /// added, drawn as an overlay because `TextEditor` has no placeholder API on
    /// iOS 16.
    private var notesSection: some View {
        AmbientFormSection(
            title: "Notes",
            status: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "optional" : "written",
            statusTint: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .orange
        ) {
            ClassGroupNotesEditor(notes: $notes, focus: $focusedField)
        }
    }
}

// MARK: - Create job

/// Pick a session, get a job. The design change is honesty about the window: the
/// old empty state said "in the next 2 weeks" and offered no escape, and the window
/// is hard-coded server-side (`ClassGroupJobService.swift:90-91`) — so a date-range
/// control here would be a promise the service cannot keep. The caption says what
/// the list is instead.
private struct CreateClassGroupJobMockup: View {
    let jobType: String

    private enum LabState: String, CaseIterable, Identifiable {
        case sessions = "Sessions"
        case none = "No sessions"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var labState: LabState = .sessions
    @State private var selected: String?

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: ClassGroupsMockup.featureTint, intensity: 0.6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            AmbientSectionTitle("Lab · state", trailing: "not a design element")
                            Picker("State", selection: $labState) {
                                ForEach(LabState.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }

                        if labState == .none {
                            noSessionsState
                        } else {
                            sessionList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Create \(ClassGroupJobType.singularTitle(jobType)) Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Job") { dismiss() }
                        .disabled(selected == nil)
                }
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Available sessions",
                                trailing: "\(ClassGroupsLabData.sessions.count)")

            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(ClassGroupsLabData.sessions) { session in
                    Button {
                        withAnimation(AmbientMotion.snappy) { selected = session.id }
                        AmbientHaptics.selection()
                    } label: {
                        ClassGroupSessionCard(
                            dateLabel: ClassGroupSessionCard.dateLabel(for: session.date),
                            schoolName: session.schoolName,
                            sessionTypes: session.sessionTypes,
                            isSelected: selected == session.id,
                            tint: ClassGroupsMockup.featureTint)
                    }
                    .buttonStyle(.plain)
                }
            }

            // The honest caption, replacing a control the service cannot support.
            Text("Sessions in the next 2 weeks without a \(ClassGroupJobType.rowNoun(jobType)) job. The window is set on the server — there is no date range to change here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Selection is single and CANNOT be cleared once made, exactly as the
            // live screen behaves. Said out loud rather than discovered.
            Text("One session per job, and the choice can't be cleared once made — unchanged.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var noSessionsState: some View {
        VStack(spacing: 10) {
            AmbientEmptyState(
                title: "No Available Sessions",
                message: "There are no upcoming sessions without \(ClassGroupJobType.rowNoun(jobType)) jobs in the next 2 weeks.",
                systemImage: "calendar.badge.exclamationmark")
            Text("\"Available\" means a scheduled session in the next 2 weeks that has no job yet — the window is server-side, so there is nothing to widen from here. The old screen left you at this wall with no explanation of what \"available\" meant.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }
}

// MARK: - The slate

/// EXACTLY a whiteboard, and deliberately outside the design language: hard white,
/// huge black text, no wash, no card, no dark-mode adaptation. It is held up in
/// front of a class so the frame is labelled, and every Ambient instinct — glass,
/// tint, restraint — makes it worse.
///
/// The board itself is `ClassGroupSlateBoard`, the production component. What the
/// lab does NOT get is the real screen's brightness and idle-timer behaviour — a
/// gallery must not turn the device's brightness to 1.0.
private struct ClassGroupSlateMockup: View {
    let grade: String
    let teacher: String
    let schoolName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ClassGroupSlateBoard(grade: grade, teacher: teacher,
                                 schoolName: schoolName) { dismiss() }

            VStack {
                Spacer()

                // SHIPPED — the old slate dismissed on a tap ANYWHERE. A
                // photographer holding a phone in one hand and a camera in the
                // other lost the slate mid-shoot to a stray thumb, and there is no
                // undo: they found out when the frame came back unlabelled. The
                // tap-anywhere gesture is gone; only the X dismisses.
                Text("Only the X closes this. It used to close on a tap anywhere, which lost the slate mid-shoot.")
                    .font(.caption2)
                    .foregroundStyle(Color.gray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .statusBarHidden()
    }
}

// MARK: - Sample data

/// A session offered by the create screen. There is no production type for this
/// shape — the live screen builds it from an embedded `sessions + session_days`
/// read — so it stays a small lab struct.
private struct LabClassGroupSession: Identifiable {
    let id: String
    let date: Date
    let schoolName: String
    let sessionTypes: [String]
}

/// Seeded to contain every case that decides the design: all three job types, a
/// job with ZERO groups (the amber badge), a job with 14 groups and 300 images (the
/// count that has to stay legible), a group with a BLANK teacher (the dangling-dash
/// case), a group with a long comma list (the one-line truncation), a group with a
/// note (the body preview), and club rows using the club-name / advisor vocabulary
/// in the shared `grade` / `teacher` keys.
private enum ClassGroupsLabData {

    static let jobs: [ClassGroupJob] = [
        // Class Groups — the full case: many rows, many images.
        ClassGroupJob(
            id: "cg-1",
            sessionDate: DesignLabSampleData.day(6),
            schoolName: "Riverside Elementary",
            jobType: ClassGroupJobType.classGroups,
            classGroups: riversideGroups,
            notes: "Gym is being refinished — shoot in the cafeteria. Principal wants the 5th grade last."),
        // Class Groups — ZERO rows. The amber badge, and the detail screen's
        // empty state.
        ClassGroupJob(
            id: "cg-2",
            sessionDate: DesignLabSampleData.day(13),
            schoolName: "Northgate Middle School",
            jobType: ClassGroupJobType.classGroups,
            classGroups: []),
        // Class Groups — LAST year's job. On the old list this card and the two
        // above were indistinguishable at a glance, because the row had no year.
        ClassGroupJob(
            id: "cg-3",
            sessionDate: DesignLabSampleData.day(-361),
            schoolName: "Riverside Elementary",
            jobType: ClassGroupJobType.classGroups,
            classGroups: Array(riversideGroups.prefix(4))),
        // Candids.
        ClassGroupJob(
            id: "cc-1",
            sessionDate: DesignLabSampleData.day(2),
            schoolName: "Westbrook High School",
            jobType: ClassGroupJobType.classCandids,
            classGroups: candidGroups),
        // Clubs — the club name lives in `grade`, the advisor in `teacher`.
        ClassGroupJob(
            id: "cb-1",
            sessionDate: DesignLabSampleData.day(9),
            schoolName: "Westbrook High School",
            jobType: ClassGroupJobType.clubs,
            classGroups: clubGroups)
    ]

    static func job(id: String) -> ClassGroupJob {
        jobs.first { $0.id == id } ?? jobs[0]
    }

    /// 14 rows, 300 images between them.
    private static let riversideGroups: [ClassGroup] = {
        var groups: [ClassGroup] = [
            ClassGroup(id: "g1", grade: "Pre-K", teacher: "Mrs. Alvarez",
                       imageNumbers: "1042, 1043, 1051, 1052, 1053, 1061, 1062, 1071, 1072, 1080, 1081, 1082, 1083, 1084, 1090, 1091, 1092, 1093",
                       notes: "Two children out sick — retakes on the 14th."),
            // THE DANGLING-DASH CASE: grade only, no teacher. The old row rendered
            // "Kindergarten - " here.
            ClassGroup(id: "g2", grade: "Kindergarten", teacher: "",
                       imageNumbers: "1101, 1102, 1103"),
            ClassGroup(id: "g3", grade: "1st Grade", teacher: "Mr. Whitfield",
                       imageNumbers: "1120, 1121, 1122, 1130, 1131"),
            ClassGroup(id: "g4", grade: "2nd Grade", teacher: "Ms. Okonkwo",
                       imageNumbers: "",
                       notes: "Class was at an assembly — come back after lunch."),
            ClassGroup(id: "g5", grade: "3rd Grade", teacher: "Mrs. Alvarez",
                       imageNumbers: "1150, 1151, 1152, 1160")
        ]
        // Nine more so the totals line has a real number behind it.
        for index in 6...14 {
            groups.append(ClassGroup(id: "g\(index)",
                                     grade: "\(index - 1)th Grade",
                                     teacher: "Teacher \(index)",
                                     imageNumbers: (1...30).map { "\(1200 + index * 40 + $0)" }
                                        .joined(separator: ", ")))
        }
        return groups
    }()

    private static let candidGroups: [ClassGroup] = [
        ClassGroup(id: "c1", grade: "Lunch period", teacher: "Ms. Reyes",
                   imageNumbers: "2201, 2202, 2203, 2204"),
        ClassGroup(id: "c2", grade: "Hallway", teacher: "",
                   imageNumbers: "2210, 2211"),
        ClassGroup(id: "c3", grade: "Chemistry lab", teacher: "Dr. Bhatt",
                   imageNumbers: "",
                   notes: "Goggles on everyone — the yearbook adviser asked for it.")
    ]

    /// Clubs use the SAME four keys — `grade` carries the club name and `teacher`
    /// the advisor. The vocabulary changes; the row shape does not.
    private static let clubGroups: [ClassGroup] = [
        ClassGroup(id: "b1", grade: "Robotics Club", teacher: "Mr. Duarte",
                   imageNumbers: "3301, 3302, 3303, 3304, 3305, 3306",
                   notes: "Bring the wide lens — they want the whole build table in frame."),
        ClassGroup(id: "b2", grade: "Jazz Band", teacher: "Ms. Lindqvist",
                   imageNumbers: "3310, 3311, 3312"),
        // A club with no advisor recorded — the dangling-dash case again, in the
        // vocabulary where it reads worst: "Debate Team - ".
        ClassGroup(id: "b3", grade: "Debate Team", teacher: "",
                   imageNumbers: "")
    ]

    static let sessions: [LabClassGroupSession] = [
        LabClassGroupSession(id: "s1", date: DesignLabSampleData.day(4),
                             schoolName: "Riverside Elementary",
                             sessionTypes: ["Underclass", "Class Groups"]),
        LabClassGroupSession(id: "s2", date: DesignLabSampleData.day(5, hour: 13),
                             schoolName: "Northgate Middle School",
                             sessionTypes: ["Retakes"]),
        LabClassGroupSession(id: "s3", date: DesignLabSampleData.day(11, hour: 8),
                             schoolName: "Westbrook High School",
                             sessionTypes: ["Senior Portraits", "Clubs"])
    ]
}
