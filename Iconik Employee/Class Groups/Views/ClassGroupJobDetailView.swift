//  ClassGroupJobDetailView.swift
//  Iconik Employee — one Groups job, converted to Ambient in AMB.10
//
//  The old screen is GONE from this file: the blanked nav title with a
//  `.largeTitle` school name in the body, the hand-rolled
//  `Color(.systemGray6)` + `.cornerRadius(10)` row, the 22pt "\(grade) - \(teacher)"
//  with its dangling dash, the `lineLimit(nil)` comma list that pushed every other
//  row off the screen, the "Has notes" HINT you had to open a sheet to read, the
//  `.contentShape(Rectangle())` with no gesture behind it, the empty `onSlate: { }`
//  closure passed to every row, and the empty `refreshJob()`.
//
//  WHAT THIS SCREEN GAINED, and why each is in scope:
//    · THE SESSION DATE EXISTS. The old screen never showed it anywhere — you could
//      stand in a school looking at a job and not be told which day it was for.
//    · THE NOTE BODIES ARE READABLE, on the row, two lines.
//    · THE WHOLE ROW TAKES THE TAP. The only edit target used to be an invisible
//      36pt pencil; the row read tappable and was not.
//    · THE JOB-LEVEL NOTE IS SHOWN. `class_group_jobs.notes` is in the model, is
//      written by the web app, and had never been displayed anywhere on iOS.
//      READ-ONLY: showing what is already stored costs nothing; editing it needs a
//      service method that does not exist.
//    · THE SHEETS ACTUALLY REFRESH THE JOB. `refreshJob()` was an empty function
//      with a comment saying realtime would handle it, and both sheet completions
//      called it — so their `success: Bool` did nothing at all.
//
//  A `List` for the same load-bearing reason as the jobs list: `.onDelete` is
//  List-only, swipe-to-delete a row is a real capability, and the hero and the job
//  note ride in the same List as rows so there is ONE scroll surface.
//
//  CLEARANCE: this screen is PUSHED, so it insets ITSELF — a container's root inset
//  is not inherited by what it pushes (see Navigation/BottomTabBar.swift).

import SwiftUI

struct ClassGroupJobDetailView: View {
    let jobId: String

    /// ONE sheet, one binding — the same enum shape `YearbookChecklistView` uses.
    /// Its mixed `.sheet(item:)` + `.sheet(isPresented:)` pair failed on device
    /// (item taps did nothing) and unifying fixed it; this screen's add/edit pair
    /// was the same mixed shape, so it gets the same one-enum sheet. Not asserted
    /// as a general law — plain chained sheets ship and work elsewhere.
    private enum DetailSheet: Identifiable {
        case add
        case edit(ClassGroup)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let group): return "edit-\(group.id)"
            }
        }
    }

    @State private var job: ClassGroupJob?
    @State private var isLoading = true
    @State private var sheet: DetailSheet?
    @State private var slateGroup: ClassGroup?
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var showingDeleteConfirmation = false
    /// Resolved to ROWS at swipe time, not an `IndexSet`: the confirmation alert
    /// leaves an unbounded gap during which the realtime refetch can reorder the
    /// array, and an index kept across that gap would name a different row.
    @State private var groupsPendingDelete: [ClassGroup] = []
    @State private var listenerWrapper: ListenerRegistrationWrapper?

    private let service = ClassGroupJobService.shared

    private var tint: Color { ClassGroupsStyle.tint }

    private var jobType: String { ClassGroupJobType.normalize(job?.jobType) }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            content
        }
        .tabBarClearance()
        // THE NAV BAR GETS ITS TITLE BACK. The old screen set `.navigationTitle("")`
        // and drew the real title in the body — the shape NAV.1 spent a session
        // undoing elsewhere.
        .navigationTitle(ClassGroupJobType.displayName(job?.jobType))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Only when the job is actually here: over "Job not found" a live
            // "+" would open a form whose successful save this screen could
            // neither refresh from nor display.
            if job != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { sheet = .add } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add \(ClassGroupJobType.singularTitle(job?.jobType))")
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add:
                ClassGroupFormView(mode: .add,
                                   jobId: jobId,
                                   jobType: jobType,
                                   schoolName: job?.schoolName) { success in
                    if success { reloadJob() }
                }
            case .edit(let group):
                ClassGroupFormView(mode: .edit(group),
                                   jobId: jobId,
                                   jobType: jobType,
                                   schoolName: job?.schoolName) { success in
                    if success { reloadJob() }
                }
            }
        }
        // THE SLATE IS OPENED BY THE SCREEN, NOT BY THE ROW. It used to be a
        // `fullScreenCover` on every row, so a list of fourteen groups carried
        // fourteen presenters and fourteen `showingSlate` flags.
        .fullScreenCover(item: $slateGroup) { group in
            ClassGroupSlateView(grade: group.grade,
                                teacher: group.teacher,
                                schoolName: job?.schoolName)
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Delete \(ClassGroupJobType.singularTitle(job?.jobType))?",
               isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { groupsPendingDelete = [] }
            Button("Delete", role: .destructive) {
                performDelete(groupsPendingDelete)
                groupsPendingDelete = []
            }
        } message: {
            Text("Are you sure you want to delete this \(ClassGroupJobType.rowNoun(job?.jobType))?")
        }
        .onAppear { loadJob() }
        .onDisappear { listenerWrapper?.remove() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        // Gated on `job == nil`, not on `isLoading` alone: `onAppear` refires when
        // the slate's fullScreenCover closes, and a screen that already holds its
        // job must not swap the whole list for a spinner while it re-subscribes.
        if isLoading && job == nil {
            ProgressView("Loading job details…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let job {
            jobList(job)
        } else {
            AmbientEmptyState(title: "Job not found",
                              message: "This job is no longer in your organization's list.",
                              systemImage: "questionmark.folder")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func jobList(_ job: ClassGroupJob) -> some View {
        List {
            ClassGroupJobHero(schoolName: job.schoolName,
                              jobType: job.jobType,
                              sessionDate: job.sessionDate,
                              totalsLine: ClassGroupsRules.totalsLine(jobType: job.jobType,
                                                                      groupCount: job.classGroupCount,
                                                                      imageCount: job.totalImageCount),
                              tint: tint)
                .modifier(ClassGroupsDetailRow())

            if job.classGroups.isEmpty {
                AmbientEmptyState(
                    title: "No \(ClassGroupJobType.displayName(job.jobType))",
                    message: "Tap the + button to add \(ClassGroupJobType.rowNounPlural(job.jobType)) as you photograph them.",
                    systemImage: ClassGroupJobType.detailEmptyIcon(job.jobType),
                    actionTitle: "Add \(ClassGroupJobType.singularTitle(job.jobType))",
                    actionIcon: "plus.circle.fill",
                    action: { sheet = .add },
                    actionTint: tint)
                .modifier(ClassGroupsDetailRow())
            } else {
                ForEach(job.classGroups) { group in
                    ClassGroupRowCard(group: group,
                                      onEdit: { sheet = .edit(group) },
                                      onSlate: { slateGroup = group },
                                      tint: tint)
                        .modifier(ClassGroupsDetailRow())
                }
                // Resolved against the SAME `job` value this ForEach rendered,
                // not `self.job`, which the realtime callback can have replaced.
                .onDelete { offsets in deleteGroups(in: job, at: offsets) }
            }

            jobNotes(job)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// The JOB-level note, read-only. Stored and written by the web app, never
    /// shown on iOS until now.
    @ViewBuilder
    private func jobNotes(_ job: ClassGroupJob) -> some View {
        if let notes = job.notes,
           !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AmbientNoteCard(title: "Job notes",
                            text: notes,
                            accent: tint,
                            density: .compact)
                .modifier(ClassGroupsDetailRow())
        }
    }

    // MARK: - Data

    private func loadJob() {
        isLoading = true

        listenerWrapper = service.subscribeToJobUpdates(jobId: jobId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updatedJob):
                    self.job = updatedJob
                    self.isLoading = false
                case .failure(let error):
                    self.errorMessage = "Failed to load job: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                    self.isLoading = false
                }
            }
        }
    }

    /// THE DEAD CONTROL THIS PHASE HAD TO FIX. `refreshJob()` was empty, so a saved
    /// row appeared only if the realtime channel happened to deliver.
    ///
    /// Re-reads ONE row by id (AMB.10 review — the first version downloaded every
    /// job in the organization to refresh this one), compared EXACTLY as stored
    /// (`class_group_jobs.id` is app-minted UPPERCASE; case-folding is the AMB.9
    /// critical). A successful fetch that finds NO row is said out loud rather
    /// than leaving the stale screen — realtime cannot heal it, because filtered
    /// subscriptions never receive DELETE events.
    private func reloadJob() {
        service.fetchClassGroupJob(byId: jobId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let refreshed):
                    if let refreshed {
                        self.job = refreshed
                    } else {
                        // Deleted elsewhere: show the job-not-found state
                        // instead of silently keeping a job that no longer
                        // exists.
                        self.job = nil
                        self.isLoading = false
                    }
                case .failure(let error):
                    self.errorMessage = "Saved, but this screen couldn't refresh: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }

    /// Resolved to ROWS here, at swipe time — before the confirmation alert opens
    /// its unbounded gap, during which the realtime callback can replace `job`
    /// and reorder the array underneath a stored index. `job` is the value the
    /// swiped ForEach actually rendered.
    private func deleteGroups(in job: ClassGroupJob, at offsets: IndexSet) {
        groupsPendingDelete = offsets.compactMap { index -> ClassGroup? in
            index < job.classGroups.count ? job.classGroups[index] : nil
        }
        showingDeleteConfirmation = true
    }

    private func performDelete(_ groups: [ClassGroup]) {
        for group in groups {
            service.deleteClassGroup(fromJobId: jobId, classGroupId: group.id) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.reloadJob()
                    case .failure(let error):
                        self.errorMessage = "Failed to delete: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
}

/// Same row strip as the jobs list — clear background, no separator, the cards
/// supply the spacing — while the rows stay real List rows so `.onDelete` lives.
private struct ClassGroupsDetailRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: AmbientDensity.compact.stackSpacing / 2,
                                      leading: 16,
                                      bottom: AmbientDensity.compact.stackSpacing / 2,
                                      trailing: 16))
    }
}
