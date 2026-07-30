//  ClassGroupsMockup.swift
//  Iconik Employee — AMB.10's Class Groups mockup, built in batch 3
//
//  ARC SCAFFOLDING. Deleted at AMB.10's close, with the rest of the lab going at
//  AMB.12.
//
//  WHAT THE DESIGN IS ARGUING, in four claims the operator can accept or reject
//
//      1. A JOB CARD SHOULD SAY WHEN — WITH THE YEAR — AND HOW MUCH IS DONE.
//         The live row formats the session date `"EEEE, MMM d"`
//         (`ClassGroupJobsListView.swift:241`) — no year. School photography runs
//         the same weeks every August, and the list is sorted date-DESCENDING with
//         no year anywhere on it, so last year's job and this year's job are two
//         cards reading "Tuesday, Aug 4". The date carries the year here, drawn
//         through `Formatters.longDate` rather than a fourth private formatter.
//
//      2. THE DETAIL SCREEN SHOULD SHOW THE DATE AND THE NOTE BODIES.
//         Today the detail screen never shows the session date at all (parity
//         §A.2) — you can stand in a school looking at a job and not be told which
//         day it is for. And a row with a note draws an orange "Has notes" HINT
//         (`ClassGroupJobDetailView.swift:259`): the body is only readable by
//         opening the Edit sheet. A note a photographer typed for themselves is
//         the whole reason the field exists; it goes on the row.
//
//      3. A GROUP ROW'S WHOLE CARD SHOULD BE TAPPABLE.
//         The live row carries `.contentShape(Rectangle())` with NO tap gesture
//         (`ClassGroupJobDetailView.swift:269`) — so the row reads tappable, and
//         is not. The only edit target is an invisible 36pt pencil. That is a
//         fake affordance, and on a phone held one-handed at a school it is a
//         missed tap every time. The card takes the tap; the slate keeps its own
//         button because it is a different, and much louder, destination.
//
//      4. THE SLATE STAYS A PLAIN WHITE WHITEBOARD, ON PURPOSE.
//         `ClassGroupSlateView` is deliberately not theme-aware: it is a
//         whiteboard held up in front of a class so the frame is labelled. It gets
//         NO ambient treatment, no wash, no card — styling it would break it. The
//         one change proposed is dismissal (see the slate section).
//
//  WHAT IS NOT BEING PROPOSED
//      No data layer, service, permission or business-rule changes (D12). Where a
//      drawn state needs one, it is captioned PROPOSED so approving the design is
//      not mistaken for approving the fix. Specifically NOT promised, per
//      AMB_BATCH3_PARITY.md §6: Class Groups EXPORT (`exportToCSV` has no caller
//      and no button), photos or thumbnails (the model carries free-text image
//      NUMBERS, never an image reference), per-item assignment (the model has no
//      assignee), and any club-specific field set (clubs share the class-group row
//      shape — `grade` holds the club name, `teacher` the advisor — and that shape
//      is a contract with the web app).
//
//  VOCABULARY COMES FROM PRODUCTION
//      Every label below resolves through `ClassGroupJobType` and the real
//      `ClassGroupJob` / `ClassGroup` models. The lab does not keep a second table
//      of the three types' nouns — that is the drift the "design lives in
//      production code the lab imports" rule exists to stop, and it is what let
//      the live row hardcode `person.3` for Clubs (parity §3).

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
    /// The feature's own colour (D11) — the registered `FeatureTheme` green from
    /// `DesignTokens.swift:47`, which today never reaches these screens: the
    /// feature uses zero design tokens (parity §0.1).
    static let featureTint = Color(hex: "#46A758")

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
                    typeSwitcher
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

    // MARK: 1 — the type switcher

    /// Replaces the segmented control (`ClassGroupJobsListView.swift:22-28`).
    /// Three capsule chips, the same control the rest of Ambient uses for a
    /// mutually-exclusive choice — a segmented picker cannot be tinted per option
    /// and reads as system chrome sitting on top of the wash rather than part of
    /// it. Selecting a type relabels the vocabulary everywhere below: for Clubs
    /// the rows are clubs, the fields are Club Name / Advisor Name.
    private var typeSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(ClassGroupJobType.all, id: \.self) { option in
                let selected = jobType == option
                Button {
                    withAnimation(AmbientMotion.snappy) { jobType = option }
                    AmbientHaptics.selection()
                } label: {
                    Text(ClassGroupJobType.displayName(option))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? .white : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        // ambient-allow: a selection chip is a control, not a
                        // container — it needs a solid tint to read as chosen.
                        .background(Capsule().fill(selected
                                                   ? AnyShapeStyle(Self.featureTint)
                                                   : AnyShapeStyle(.ultraThinMaterial)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.10)))
                }
                .buttonStyle(.plain)
            }
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
                        jobCard(job)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }

            // Swipe-to-delete a whole job is real and KEPT
            // (`ClassGroupJobsListView.swift:46`). It cannot be drawn here:
            // `.swipeActions` is List-only and these cards are a LazyVStack. The
            // converted screen keeps its `List` for exactly this reason.
            Text("Swipe a job to delete it — unchanged. Not drawable on these cards: swipe actions are List-only, so the real screen stays a List.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ROOMY, not compact. There are a handful of these a season, not three
    /// hundred — the live screen's `InsetGroupedListStyle` row is denser than the
    /// content deserves, and the two things a photographer needs off this card
    /// (which day, how far along) both want a line of their own.
    private func jobCard(_ job: ClassGroupJob) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // THE FIX: the year. `Formatters.longDate` is the app's existing
            // full-date formatter — "Tuesday, August 4, 2026".
            Text(Formatters.longDate.string(from: job.sessionDate))
                .font(AmbientDensity.roomy.titleFont)
                .fixedSize(horizontal: false, vertical: true)

            Text(job.schoolName)
                .font(AmbientDensity.roomy.subtitleFont)
                .foregroundStyle(.secondary)

            AmbientPillRow(pills: pills(for: job), density: .compact)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// The count badge and the image badge, with the type's own nouns. "No
    /// groups yet" is amber and ALWAYS drawn when the count is zero — the live
    /// row does the same thing and it is right: an empty job is the one you have
    /// to go back to.
    private func pills(for job: ClassGroupJob) -> [AmbientPill] {
        var pills: [AmbientPill] = []
        let count = job.classGroupCount
        if count > 0 {
            let noun = count == 1
                ? ClassGroupJobType.countNoun(job.jobType)
                : ClassGroupJobType.countNounPlural(job.jobType)
            pills.append(AmbientPill(id: "count", text: "\(count) \(noun)",
                                     systemImage: "person.3", tint: .blue))
        } else {
            pills.append(AmbientPill(id: "count",
                                     text: "No \(ClassGroupJobType.countNounPlural(job.jobType)) yet",
                                     systemImage: "exclamationmark.circle", tint: .orange))
        }
        // Images are omitted entirely at zero rather than drawn as "0 images" —
        // the live row's behaviour, and correct: an image count of zero on a job
        // you have not shot yet is not information.
        let images = job.totalImageCount
        if images > 0 {
            // Singularized, which the live row never is (parity §3, "images"
            // never singularized).
            pills.append(AmbientPill(id: "images",
                                     text: "\(images) \(images == 1 ? "image" : "images")",
                                     systemImage: "photo", tint: .green))
        }
        return pills
    }

    /// The live empty state's real copy and its real call to action, through the
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

    /// The destructive confirm, drawn as its copy so the words can be judged
    /// here. A real `.alert` cannot be evaluated in a mockup gallery — you would
    /// have to trigger it — and the words are the whole safety mechanism.
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

            Text("The copy is unchanged — it already names what goes, and says it cannot be undone. PROPOSED: a failure here is currently printed to the console and nothing else (`ClassGroupJobsListView.swift:114-115`), so a job that did not delete looks deleted until the next load. The row-level delete alerts; the job-level one does not.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 3 — the create route

    /// The live screen puts this in the nav bar (`ClassGroupJobsListView.swift:53-59`).
    /// Drawn here as a floating circle because the lab runner owns the nav bar,
    /// and at the BOTTOM LEADING corner because the runner's mockup switcher owns
    /// bottom-trailing. On the converted screen this is the operator's call:
    /// toolbar "+" (today) or a floating button (reachable one-handed, which the
    /// toolbar corner is not on a large phone).
    private var addButton: some View {
        Button {
            showingCreate = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                // ambient-allow: a floating action button is a control, not a
                // container — it needs a solid tint and a lift to read as the
                // screen's primary action.
                .background(Circle().fill(Self.featureTint))
                .shadow(color: Self.featureTint.opacity(0.35), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.leading, 18)
        .padding(.bottom, 26)
    }
}

// MARK: - Detail

/// The job's rows. Three fixes land here: the session date exists, the note
/// bodies are readable, and the whole row takes the tap.
private struct ClassGroupJobDetailMockup: View {
    let job: ClassGroupJob

    @State private var editing: ClassGroup?
    @State private var slate: ClassGroup?

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: ClassGroupsMockup.featureTint, intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
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

    /// THE FIX: the session date. The live detail screen shows the school name in
    /// `.largeTitle` and the type below it, and never shows the date anywhere
    /// (parity §A.2). It also blanks the nav title to do it, which NAV.1 spent a
    /// session undoing elsewhere — so the title goes back in the bar and the hero
    /// carries the three facts that identify the job.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(job.schoolName)
                    .font(.system(size: 22, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                AmbientBadge(text: ClassGroupJobType.badgeLabel(job.jobType),
                             systemImage: "person.3",
                             tint: ClassGroupsMockup.featureTint)
            }

            Text(Formatters.longDate.string(from: job.sessionDate))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(totalsLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .ambientCard(density: .hero, state: .highlighted,
                     glow: ClassGroupsMockup.featureTint, fillWidth: true)
    }

    private var totalsLine: String {
        let count = job.classGroupCount
        let noun = count == 1
            ? ClassGroupJobType.countNoun(job.jobType)
            : ClassGroupJobType.countNounPlural(job.jobType)
        let images = job.totalImageCount
        return "\(count) \(noun) · \(images) \(images == 1 ? "image" : "images")"
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(job.classGroups) { group in
                    row(group)
                        .ambientScrollFade()
                }
            }

            Text("Swipe a row to delete — unchanged. Not drawable on these cards: swipe actions are List-only, so the real screen stays a List.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// COMPACT — this is the list you scan between frames, one row per group, and
    /// the live row's hard 22pt title is bigger than anything else in the app.
    ///
    /// The whole card is the edit target (claim 3). The slate keeps a button
    /// because it is a full-screen, brightness-changing destination you must not
    /// be able to reach by fumbling a row.
    private func row(_ group: ClassGroup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                editing = group
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title(group))
                        .font(.system(size: 17, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    imagesLine(group)

                    // THE FIX: the note BODY, not a hint that one exists.
                    if !group.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "note.text")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                            Text(group.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                slate = group
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    // ambient-allow: a round icon control, not a container — the
                    // slate is a separate destination from editing the row.
                    .background(Circle().fill(ClassGroupsMockup.featureTint))
            }
            .buttonStyle(.plain)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    /// The dangling-dash fix. The live row renders `"\(grade) - \(teacher)"`
    /// unconditionally, so a group with no teacher reads "3rd Grade - "
    /// (`ClassGroupJobDetailView.swift:257`) — teacher is optional, only the grade
    /// is required. Em dash when both exist, grade alone when it does not.
    private func title(_ group: ClassGroup) -> String {
        let teacher = group.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        return teacher.isEmpty ? group.grade : "\(group.grade) — \(teacher)"
    }

    /// One line, truncated, with the count beside it. The live row sets
    /// `lineLimit(nil)` on the raw comma list, so a group with forty frames pushes
    /// every other row off the screen.
    @ViewBuilder
    private func imagesLine(_ group: ClassGroup) -> some View {
        if group.hasImages {
            HStack(spacing: 6) {
                Text("Images: \(group.image_numbers)")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .truncationMode(.tail)
                AmbientBadge(text: "\(group.imageCount)", tint: .blue)
            }
        } else {
            Text("No images")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// The live detail screen's empty state, with the PLURAL display name it
    /// really uses (the list's uses the singular — an inconsistency worth keeping
    /// an eye on rather than silently harmonising).
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

    /// PROPOSED. `class_group_jobs.notes` — the JOB-level note — exists in the
    /// model, is written by the web app, and is never displayed or editable
    /// anywhere in the iOS feature (parity §3, `ClassGroupModels.swift:121`).
    /// Drawn read-only: showing what is already stored costs nothing, editing it
    /// needs a service method that does not exist.
    @ViewBuilder
    private var jobNotes: some View {
        if let notes = job.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                AmbientNoteCard(title: "Job notes", text: notes,
                                accent: ClassGroupsMockup.featureTint, density: .compact)
                Text("PROPOSED — read-only. The job-level note is stored and written by the web app but has never been shown on iOS.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Add / Edit form

/// ONE form for add and edit. The live feature has two line-for-line duplicate
/// views (`AddClassGroupView.swift:3` and `:178`) differing only in container,
/// title and dismissal API — which is how they came to disagree about navigation
/// style (`NavigationView` + Stack vs `NavigationStack`). One form, one set of
/// rules.
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

    private var trimmedGrade: String {
        grade.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The live count: a naive comma split, so `"12,"` reads as 1. Kept as-is —
    /// it is what the stored string means, and a mockup that quietly counts
    /// better than production is a mockup that lies.
    private var imageCount: Int {
        let trimmed = imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? 0 : trimmed.split(separator: ",").count
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
                        whiteboardButton
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
                        .disabled(trimmedGrade.isEmpty)
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
            // THE SLATE GETS A REAL SCHOOL NAME HERE. Both live form paths pass
            // `schoolName: nil` (`AddClassGroupView.swift:135`, `:315`), so the
            // slate opened from the form is missing the one line that tells you
            // which school you are standing in — even though the form was reached
            // from a job that knows.
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
                field(ClassGroupJobType.primaryFieldLabel(jobType), text: $grade)

                // The live form hides 14 grades behind a `Menu` you have to know
                // to open. Chips put them on the surface — one tap, and the tap
                // target is the thing you are choosing.
                if ClassGroupJobType.showsGradeSuggestions(jobType) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ClassGroup.commonGrades, id: \.self) { option in
                                Button {
                                    withAnimation(AmbientMotion.snappy) { grade = option }
                                    AmbientHaptics.selection()
                                } label: {
                                    Text(option)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(grade == option ? .white : .primary)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        // ambient-allow: a suggestion chip is a
                                        // control, not a container.
                                        .background(Capsule().fill(grade == option
                                                                   ? AnyShapeStyle(ClassGroupsMockup.featureTint)
                                                                   : AnyShapeStyle(.ultraThinMaterial)))
                                        .overlay(Capsule().strokeBorder(Color.primary.opacity(grade == option ? 0 : 0.10)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }

                Divider()
                field(ClassGroupJobType.secondaryFieldLabel(jobType), text: $teacher)
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
            status: imageCount == 0 ? "none yet" : "\(imageCount) \(imageCount == 1 ? "number" : "numbers")",
            statusTint: imageCount == 0 ? nil : .blue
        ) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("1042, 1043, 1051", text: $imageNumbers)
                    .font(.subheadline)
                    .keyboardType(.numbersAndPunctuation)
                Text("Comma separated. These are frame NUMBERS, not photos — nothing in this feature stores an image.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The live editor has NO placeholder (`AddClassGroupView.swift`, notes
    /// section) — an empty grey box with a heading. One is added, drawn as an
    /// overlay because `TextEditor` has no placeholder API on iOS 16.
    private var notesSection: some View {
        AmbientFormSection(
            title: "Notes",
            status: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "optional" : "written",
            statusTint: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .orange
        ) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .font(.subheadline)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                if notes.isEmpty {
                    Text("Retakes, a missing student, anything the next person needs to know.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Disabled until the grade exists — the live rule, kept. The slate with no
    /// grade on it is a blank whiteboard.
    private var whiteboardButton: some View {
        VStack(spacing: 6) {
            Button {
                showingSlate = true
            } label: {
                Label("Show Whiteboard", systemImage: "camera.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // ambient-allow: a filled primary control, not a card.
                    .background(Capsule().fill(trimmedGrade.isEmpty
                                               ? Color.gray
                                               : ClassGroupsMockup.featureTint))
            }
            .buttonStyle(.plain)
            .disabled(trimmedGrade.isEmpty)

            if trimmedGrade.isEmpty {
                Text("Enter a \(ClassGroupJobType.primaryFieldLabel(jobType).lowercased()) first.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .font(.subheadline)
        }
    }
}

// MARK: - Create job

/// Pick a session, get a job. The design change is honesty about the window: the
/// live empty state says "in the next 2 weeks" and offers no escape, and the
/// window is hard-coded server-side (`ClassGroupJobService.swift:90-91`) — so a
/// date-range control here would be a promise the service cannot keep. The
/// caption says what the list is instead.
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
                        sessionRow(session)
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

    private func sessionRow(_ session: LabClassGroupSession) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.dateLabel)
                    .font(AmbientDensity.compact.titleFont)
                Text(session.schoolName)
                    .font(AmbientDensity.compact.subtitleFont)
                    .foregroundStyle(.secondary)
                Text(session.sessionTypes.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            Spacer(minLength: 0)
            if selected == session.id {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ClassGroupsMockup.featureTint)
            }
        }
        .ambientCard(density: .compact,
                     state: selected == session.id ? .highlighted : .normal,
                     border: selected == session.id
                        ? .hairline(ClassGroupsMockup.featureTint.opacity(0.55))
                        : .none,
                     fillWidth: true)
    }

    private var noSessionsState: some View {
        VStack(spacing: 10) {
            AmbientEmptyState(
                title: "No Available Sessions",
                message: "There are no upcoming sessions without \(ClassGroupJobType.rowNoun(jobType)) jobs in the next 2 weeks.",
                systemImage: "calendar.badge.exclamationmark")
            Text("Sessions in the next 2 weeks without a job — the window is server-side, so there is nothing to widen from here. The live screen leaves you at this wall with no explanation of what \"available\" means.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }
}

// MARK: - The slate

/// EXACTLY a whiteboard, and deliberately outside the design language: hard
/// white, huge black text, no wash, no card, no dark-mode adaptation. It is held
/// up in front of a class so the frame is labelled, and every Ambient instinct —
/// glass, tint, restraint — makes it worse.
///
/// ONE change is proposed, and it is the reason this screen is in the mockup at
/// all: dismissal.
private struct ClassGroupSlateMockup: View {
    let grade: String
    let teacher: String
    let schoolName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // ambient-allow: the slate is a physical whiteboard, not a container —
            // it must stay hard white in both appearances.
            Color.white.ignoresSafeArea()

            VStack(spacing: 12) {
                Text(grade)
                    .font(.system(size: 96, weight: .bold))
                    .foregroundStyle(.black)
                    .minimumScaleFactor(0.3)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if !teacher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(teacher)
                        .font(.system(size: 86, weight: .bold))
                        .foregroundStyle(.black)
                        .minimumScaleFactor(0.3)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                if !schoolName.isEmpty {
                    Text(schoolName)
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(Color.gray)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 24)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.gray.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                // PROPOSED — the live slate dismisses on a tap ANYWHERE
                // (`ClassGroupSlateView.swift:65-69`). A photographer holding a
                // phone in one hand and a camera in the other loses the slate
                // mid-shoot to a stray thumb, and there is no undo: they find out
                // when the frame comes back unlabelled. This draft removes the
                // tap-anywhere gesture, so only the X dismisses.
                Text("PROPOSED — only the X closes this. Today a tap anywhere closes it, which loses the slate mid-shoot.")
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

    /// The live format, `"EEE, MMM d 'at' h:mm a"`, assembled from the shared
    /// formatters rather than a fourth private `DateFormatter`.
    var dateLabel: String {
        "\(Formatters.weekdayShort.string(from: date)), \(Formatters.monthDay.string(from: date)) at \(Formatters.shortTime.string(from: date))"
    }
}

/// Seeded to contain every case that decides the design: all three job types, a
/// job with ZERO groups (the amber badge), a job with 14 groups and 300 images
/// (the count that has to stay legible), a group with a BLANK teacher (the
/// dangling-dash case), a group with a long comma list (the one-line
/// truncation), a group with a note (the body preview), and club rows using the
/// club-name / advisor vocabulary in the shared `grade` / `teacher` keys.
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
        // Class Groups — LAST year's job. On the live list this card and the two
        // above are indistinguishable at a glance, because the row has no year.
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
            // THE DANGLING-DASH CASE: grade only, no teacher. The live row renders
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
