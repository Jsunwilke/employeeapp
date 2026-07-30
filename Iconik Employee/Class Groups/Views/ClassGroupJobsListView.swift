//  ClassGroupJobsListView.swift
//  Iconik Employee — the Groups jobs list, converted to Ambient in AMB.10
//
//  The old screen is GONE from this file, not left beside the new one: the
//  segmented picker, the `InsetGroupedListStyle` rows, the private
//  `ClassGroupJobRowView` with its per-row `DateFormatter` and its never-
//  singularized "images", the toolbar "+", the deprecated
//  `NavigationLink(tag:selection:)`, and the global `struct EmptyStateView` (which
//  nothing outside this feature referenced — grep-verified before deleting).
//  Every piece of the design now lives in `Class Groups/ClassGroupsKit.swift`,
//  which the design lab's mockup also draws with, so the mockup and this screen
//  cannot diverge.
//
//  WHAT THIS SCREEN GAINED, and why each is in scope:
//    · THE DATE CARRIES THE YEAR. School photography runs the same weeks every
//      August and this list is sorted date-DESCENDING with no year anywhere on it,
//      so last year's job and this year's job were two identical rows.
//    · A FAILED LOAD SAYS SO. `service.error` is published and was read by nothing;
//      a missing organization id was a `print`. Both rendered as "no jobs" — the
//      empty-state-hides-a-failure shape that kept Chat dormant for a year.
//    · A FAILED DELETE SAYS SO. The job-level delete printed its failure and
//      nothing else, so a job that did not delete looked deleted until the next
//      load. (The ROW-level delete always alerted; only this one did not.)
//    · ONE CREATE ROUTE, REACHABLE ONE-HANDED. The toolbar "+" is replaced by a
//      floating button, not joined by one.
//
//  THIS IS STILL A `List`, AND THAT IS LOAD-BEARING RATHER THAN A STYLE CHOICE.
//  `.swipeActions`/`.onDelete` are List-only: on a row inside a LazyVStack they
//  compile, render, and silently do nothing. Swipe-to-delete a whole job is a real
//  capability here, so the cost of keeping it is stripping List's own chrome —
//  hidden scroll background, clear row backgrounds, no separators, insets set by
//  hand — so the ambient wash shows through. Same pattern as Chat (AMB.6).
//
//  CLEARANCE: this is a SHELL-WRAPPED feature — `MainEmployeeView.featureContainer`
//  applies `tabBarClearance` to this view inside its own `NavigationView`, so this
//  root must NOT apply it again, and the floating button sits inside the safe area
//  that inset creates.

import SwiftUI

/// One enum, one `.ambientPush` — the AMB.3 rule. It replaces the deprecated
/// `NavigationLink(tag:selection:)` the old list used so widget deep-links could
/// drive selection: that form needed the link to EXIST IN THE LIST, which is why
/// the widget path also had to switch segments first. The push here is a single
/// background link on the root, so it works whether or not the row is on screen.
private enum ClassGroupsListDestination: Identifiable {
    case detail(String)

    var id: String {
        switch self {
        case .detail(let jobId): return "detail-\(jobId)"
        }
    }
}

struct ClassGroupJobsListView: View {
    @StateObject private var service = ClassGroupJobService.shared
    @ObservedObject private var tabBarManager = TabBarManager.shared

    @State private var selectedTab = ClassGroupJobType.defaultType
    @State private var destination: ClassGroupsListDestination?
    @State private var showingCreateJob = false

    @State private var showingDeleteConfirmation = false
    /// Resolved to JOBS at swipe time, not an `IndexSet`: the confirmation alert
    /// leaves an unbounded gap during which the realtime refetch replaces and
    /// re-sorts the whole array, and an index kept across that gap would name —
    /// and destroy — a different job.
    @State private var jobsPendingDelete: [ClassGroupJob] = []

    /// A failure this VIEW owns — the organization-id lookup and the delete, both
    /// of which the service never publishes because neither goes through it.
    @State private var loadFailure: String?
    @State private var deleteFailure: String?
    @State private var showingDeleteFailureAlert = false

    private var tint: Color { ClassGroupsStyle.tint }

    private var filteredJobs: [ClassGroupJob] {
        service.classGroupJobs.filter { ClassGroupJobType.normalize($0.jobType) == selectedTab }
    }

    /// The service's own published error, which no view read before AMB.10, or the
    /// one this view produced itself.
    private var failureMessage: String? {
        if let loadFailure { return loadFailure }
        if let error = service.error { return error.localizedDescription }
        return nil
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: tint, intensity: 0.8)

            VStack(spacing: 12) {
                ClassGroupTypeSwitcher(jobType: $selectedTab, tint: tint)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                content
            }
        }
        // The button sits inside the ZStack's frame, and the shell's
        // `tabBarClearance` has already shrunk that frame by the bar's height — so
        // bottom-trailing here is above the floating bar, not under it.
        .overlay(alignment: .bottomTrailing) {
            ClassGroupAddButton(tint: tint) { showingCreateJob = true }
                .padding(.trailing, 18)
                .padding(.bottom, 18)
        }
        .navigationTitle(ClassGroupJobType.displayName(selectedTab))
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .detail(let jobId):
                ClassGroupJobDetailView(jobId: jobId)
            }
        }
        .sheet(isPresented: $showingCreateJob) {
            CreateClassGroupJobView(initialJobType: selectedTab) { jobId in
                // KEPT: the 0.5s hop. The sheet is still dismissing when this fires,
                // and a push set during a sheet dismissal is dropped. Removing it is
                // a timing change this phase cannot verify on a device, so it stays
                // and is named rather than quietly deleted.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    destination = .detail(jobId)
                }
            }
        }
        .alert("Delete Job?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { jobsPendingDelete = [] }
            Button("Delete", role: .destructive) {
                performDelete(jobsPendingDelete)
                jobsPendingDelete = []
            }
        } message: {
            Text("This will delete the entire job and all its \(ClassGroupJobType.rowNounPlural(selectedTab)). This action cannot be undone.")
        }
        // THE APPROVED FIX: a failed delete was a `print`, so the row vanished from
        // the list optimistically-looking and came back on the next load.
        .alert("Couldn't delete", isPresented: $showingDeleteFailureAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteFailure ?? "The job could not be deleted.")
        }
        .onAppear { loadData() }
        .onDisappear { service.stopListening() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if service.isLoading && service.classGroupJobs.isEmpty {
            ProgressView("Loading jobs…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            jobList
        }
    }

    private var jobList: some View {
        List {
            if let failureMessage {
                ClassGroupsFailureBanner(message: failureMessage, tint: tint) { loadData() }
                    .modifier(ClassGroupsListRow())
            }

            if filteredJobs.isEmpty {
                AmbientEmptyState(
                    title: "No \(ClassGroupJobType.singularTitle(selectedTab)) Jobs",
                    message: "Create a job for an upcoming session to start tracking \(ClassGroupJobType.rowNounPlural(selectedTab)).",
                    systemImage: ClassGroupJobType.listEmptyIcon(selectedTab),
                    actionTitle: "Create Job",
                    actionIcon: "plus.circle.fill",
                    action: { showingCreateJob = true },
                    actionTint: tint)
                .modifier(ClassGroupsListRow())
            } else {
                // ONE materialised array feeds both the ForEach and the swipe
                // handler, so the offsets always resolve against the rows that
                // were actually rendered — never against a `filteredJobs`
                // recomputed after a realtime refetch reordered the service
                // array.
                let jobs = filteredJobs
                ForEach(jobs) { job in
                    ClassGroupJobCard(job: job)
                        .contentShape(Rectangle())
                        .onTapGesture { destination = .detail(job.id) }
                        .modifier(ClassGroupsListRow())
                }
                .onDelete { offsets in deleteJobs(from: jobs, at: offsets) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    // MARK: - Data

    private func loadData() {
        loadFailure = nil

        UserManager.shared.getCurrentUserOrganizationID { orgId in
            DispatchQueue.main.async {
                guard let organizationId = orgId, !organizationId.isEmpty else {
                    // WAS A `print`. An org id this screen cannot resolve is a
                    // failure, and it used to render as an empty feature.
                    self.loadFailure = "We couldn't tell which organization you belong to, so your jobs can't be loaded."
                    return
                }

                self.service.startListening(organizationId: organizationId)
                self.checkForSelectedJob()
            }
        }
    }

    /// Resolved to JOBS here, at swipe time, against the array the ForEach
    /// RENDERED — before the confirmation alert opens its unbounded gap (see
    /// `jobsPendingDelete`).
    private func deleteJobs(from jobs: [ClassGroupJob], at offsets: IndexSet) {
        jobsPendingDelete = offsets.compactMap { index -> ClassGroupJob? in
            index < jobs.count ? jobs[index] : nil
        }
        showingDeleteConfirmation = true
    }

    private func performDelete(_ jobs: [ClassGroupJob]) {
        for job in jobs {
            service.deleteClassGroupJob(id: job.id, sessionId: job.sessionId, jobType: job.jobType) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        // THE SCREEN REFLECTS THE WRITE — refetch, don't trust
                        // realtime. The org channel filters on organization_id,
                        // and Supabase DELETE events carry only the primary key
                        // (no replica identity full), so a filtered subscription
                        // NEVER hears a delete: the card would sit there looking
                        // deleted-but-back-later. Found live in the AMB.10
                        // simulator smoke — the DB row was gone, the card stayed.
                        self.loadData()
                    case .failure(let error):
                        self.deleteFailure = "This job is still there — \(error.localizedDescription)"
                        self.showingDeleteFailureAlert = true
                    }
                }
            }
        }
    }

    /// The iPad dashboard's Group Jobs widget parks a job id and its type on
    /// `TabBarManager` and switches tab; this consumes it.
    private func checkForSelectedJob() {
        guard let selectedId = tabBarManager.selectedClassGroupJobId else { return }

        defer {
            tabBarManager.selectedClassGroupJobId = nil
            tabBarManager.selectedClassGroupJobType = nil
        }

        // The segment still moves with the deep link. The push no longer DEPENDS on
        // it — `.ambientPush` is a link on the root, not a row — but landing on the
        // list behind a candids job while the Class Groups segment is showing would
        // be a lie about where you are.
        if let jobType = tabBarManager.selectedClassGroupJobType {
            selectedTab = ClassGroupJobType.normalize(jobType)
        }

        // KEPT: the 0.5s hop, for the same reason as the create path — this runs
        // inside `.onAppear`'s completion, before the navigation container has
        // settled, and a push set there is dropped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.destination = .detail(selectedId)
        }
    }
}

/// Strips a List row back to nothing so the ambient wash shows through and the
/// cards supply all the spacing — while keeping the row a real List row, which is
/// what keeps `.onDelete` alive.
private struct ClassGroupsListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: AmbientDensity.roomy.stackSpacing / 2,
                                      leading: 16,
                                      bottom: AmbientDensity.roomy.stackSpacing / 2,
                                      trailing: 16))
    }
}
