//
//  TasksViewModel.swift
//  Iconik Employee
//
//  ViewModel for TasksView (AMB.5) and for the home dashboard's TasksWidget,
//  which uses the same object.
//
//  Cache-first loading with real-time updates. The loading strategy, the service
//  calls and the filter semantics are unchanged by AMB.5 — D12 keeps data layers
//  out of a redesign phase. What AMB.5 added is on top of them:
//
//    - arrange(), which does ONE filter-and-sort pass and buckets the result into
//      the reading bands the redesign groups by. The old screen called
//      filteredTasks twice per body pass and taskCount five more times, so a
//      single keystroke in the search field ran seven full passes over the whole
//      array. That is L4 in the plan — fold the data into an index once per
//      change — and it is the pattern for any converted list.
//    - assignee names, resolved through TeamService (see AMB5_TASKS_PARITY.md
//      finding 4 for why that is a presentation join and not a new data path).
//    - the error surface the failure banner reads. The error was already
//      published and already set in four places; no view had ever read it.
//
//  And one defect fixed, because the redesign made it unavoidable rather than
//  optional: every call to fetchAllTasks used to open ANOTHER subscription to
//  TaskService.$tasks without cancelling the last one. Refresh, Clear Cache,
//  creating a task and ticking a checkbox all route through fetchAllTasks, so
//  after ten toggles in one visit there were eleven live sinks, and each realtime
//  delivery ran the merge and wrote the whole task list to disk eleven times.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class TasksViewModel: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var isLoading = false
    @Published var error: Error?

    /// Lowercased user id to full name, for the assignee line. Empty until the
    /// team loads; every reader falls back to the model's own
    /// `assignmentDisplayText`, so the line degrades to "3 assignees" rather than
    /// to blank.
    @Published private(set) var memberNames: [String: String] = [:]

    private let taskService = TaskService.shared
    private let cacheService = TaskCacheService.shared

    /// The ONE subscription to the service's task stream. Held on its own rather
    /// than in a bag, so re-subscribing replaces it instead of stacking on it.
    private var taskStreamSubscription: AnyCancellable?

    /// Guards the team fetch so it runs once per organization rather than on
    /// every appearance.
    private var loadedTeamForOrganization: String?

    /// The failed WRITE that Retry should re-run, if the last failure was a write
    /// rather than a read. Its presence is also what stops a later successful fetch
    /// from clearing the banner: a create that never happened is still unfixed no
    /// matter how well the list reloads afterwards.
    private var pendingRetry: (() -> Void)?

    private var currentUserId: String {
        return (UserManager.shared.getCurrentUserIDUnified() ?? "").lowercased()
    }

    private var currentOrganizationId: String {
        // Get organization ID from UserManager
        let orgId = UserManager.shared.getCachedOrganizationID()

        if orgId.isEmpty {
            // Try to initialize if not already done
            UserManager.shared.initializeOrganizationID()
            return UserManager.shared.getCachedOrganizationID()
        } else {
            return orgId
        }
    }

    // MARK: - Load Tasks (Cache-First Strategy)

    func loadTasks() {

        guard !currentUserId.isEmpty else {
            return
        }


        // Check if we have organization ID
        let orgId = UserManager.shared.getCachedOrganizationID()

        if orgId.isEmpty {
            isLoading = true

            // Fetch organization ID first
            UserManager.shared.getCurrentUserOrganizationID { [weak self] fetchedOrgId in
                guard let self = self, let fetchedOrgId = fetchedOrgId else {
                    self?.isLoading = false
                    return
                }

                // Now load tasks with the fetched org ID
                self.loadTasksWithOrgId(fetchedOrgId)
            }
        } else {
            // Organization ID already cached, load immediately
            loadTasksWithOrgId(orgId)
        }
    }

    private func loadTasksWithOrgId(_ orgId: String) {
        loadTeamIfNeeded(orgId: orgId)

        // Step 1: Load from cache immediately
        if let cachedTasks = cacheService.getCachedTasks(userId: currentUserId, orgId: orgId) {
            self.tasks = cachedTasks

            // Get cache timestamp for incremental updates
            let cacheTimestamp = cacheService.getLatestTimestamp(userId: currentUserId, orgId: orgId)

            // Start real-time listener for updates AFTER cache timestamp
            startIncrementalListener(afterTimestamp: cacheTimestamp)
        } else {
            // No cache - fetch all tasks
            fetchAllTasks()
        }
    }

    // MARK: - Assignee names
    //
    // TaskItem carries assignedTo as user ids. TeamService already exists,
    // already reads users filtered by organization_id, and is already used by
    // other screens in this app — so this is a presentation join over a service
    // the app owns, not a new data path. No schema, RLS or PowerSync change.

    private func loadTeamIfNeeded(orgId: String) {
        guard !orgId.isEmpty, loadedTeamForOrganization != orgId else { return }
        loadedTeamForOrganization = orgId

        Task { [weak self] in
            guard let self else { return }
            do {
                let members = try await TeamService.shared.getTeamMembers(organizationID: orgId)
                var names: [String: String] = [:]
                for member in members {
                    // Lowercased on both sides, always — Supabase stores lowercase
                    // and Swift string comparison is case sensitive.
                    names[member.id.lowercased()] = member.fullName
                }
                self.memberNames = names
            } catch {
                // A missing name is not a failure worth putting on screen: every
                // reader falls back to assignmentDisplayText. Let the team fetch
                // be retried on the next organization change.
                self.loadedTeamForOrganization = nil
            }
        }
    }

    /// Who a task is assigned to, in words.
    ///
    /// Falls back to the model's own `assignmentDisplayText` whenever a name
    /// cannot be resolved, so the line reads "Unassigned", "1 assignee" or
    /// "3 assignees" rather than going blank.
    func assigneeLabel(for task: TaskItem) -> String? {
        guard !task.assignedTo.isEmpty else { return task.assignmentDisplayText }

        let names = task.assignedTo.compactMap { memberNames[$0.lowercased()] }
        guard let first = names.first else { return task.assignmentDisplayText }

        if task.assignedTo.count == 1 { return first }
        return "\(first) +\(task.assignedTo.count - 1)"
    }

    func isAssignedToCurrentUser(_ task: TaskItem) -> Bool {
        let userId = currentUserId
        return task.assignedTo.contains { $0.lowercased() == userId }
    }

    // MARK: - Fetch All Tasks

    private func fetchAllTasks() {
        Task {
            isLoading = true
            defer { isLoading = false }


            do {
                let fetchedTasks = try await taskService.fetchTasks(organizationID: currentOrganizationId)

                if fetchedTasks.isEmpty {
                }

                self.tasks = fetchedTasks

                // A load that worked clears the failure banner. Without this the
                // banner is permanent for the life of the screen: nothing but the
                // user's own Retry or Dismiss ever cleared `error`, so one failed
                // fetch left a warning sitting over data that had since arrived.
                //
                // BUT NOT WHEN A WRITE IS STILL OUTSTANDING. If creating a task
                // failed, that task still does not exist, and a healthy re-read
                // says nothing about it — clearing here would report the failure
                // and then erase the report.
                if self.pendingRetry == nil {
                    self.error = nil
                }

                // Cache the fetched tasks
                self.cacheService.setCachedTasks(fetchedTasks, userId: self.currentUserId, orgId: self.currentOrganizationId)

                // Start real-time listener
                self.startIncrementalListener(afterTimestamp: nil)
            } catch {
                self.error = error
            }
        }
    }

    // MARK: - Incremental Listener

    private func startIncrementalListener(afterTimestamp: Date?) {
        // Start listening to real-time updates
        taskService.startListening(organizationID: currentOrganizationId)

        // ONE subscription. Cancelling first is the whole point: every path into
        // fetchAllTasks lands here, and without this each Refresh, Clear Cache,
        // created task and ticked checkbox added another live sink that re-ran the
        // merge and rewrote the disk cache on every realtime delivery.
        taskStreamSubscription?.cancel()
        taskStreamSubscription = taskService.$tasks
            .sink { [weak self] newTasks in
                guard let self = self else { return }

                // Merge new tasks with cached tasks
                if !newTasks.isEmpty {
                    let merged = self.cacheService.mergeTasks(cached: self.tasks, new: newTasks)
                    self.tasks = merged

                    // Update cache
                    self.cacheService.setCachedTasks(merged, userId: self.currentUserId, orgId: self.currentOrganizationId)
                }
            }
    }

    // MARK: - Stop Listening

    nonisolated func stopListening() {
        Task { @MainActor in
            taskService.stopListening()
            taskStreamSubscription?.cancel()
            taskStreamSubscription = nil
        }
    }

    // MARK: - Refresh Tasks

    func refreshTasks() {
        fetchAllTasks()
    }

    // MARK: - Failure surface

    func clearError() {
        error = nil
        pendingRetry = nil
    }

    /// What the failure banner's Retry does.
    ///
    /// IT RE-RUNS THE THING THAT FAILED. The first cut always re-fetched the list,
    /// which is wrong in the case that matters most: if CREATING a task failed, a
    /// re-fetch succeeds, `error` is cleared by that success, the banner
    /// disappears — and the task was never created. The failure was reported and
    /// then silently erased, which is worse than not reporting it.
    func retryAfterFailure() {
        error = nil
        if let retry = pendingRetry {
            pendingRetry = nil
            retry()
        } else {
            fetchAllTasks()
        }
    }

    /// Records a failed WRITE so Retry can re-run it and so a later successful read
    /// does not clear the banner out from under it.
    private func recordFailure(_ failure: Error, retry: @escaping () -> Void) {
        error = failure
        pendingRetry = retry
    }

    // MARK: - Clear Cache and Reload

    func clearCacheAndReload() {
        cacheService.clearCache(userId: currentUserId, orgId: currentOrganizationId)
        tasks.removeAll()
        fetchAllTasks()
    }

    // MARK: - Create Task

    func createTask(_ task: TaskItem) {
        Task {
            do {
                _ = try await taskService.createTask(task)

                // Clear cache to force refresh (prevents ghost tasks)
                self.cacheService.clearOrganizationCache(orgId: self.currentOrganizationId)

                // Refresh tasks
                self.refreshTasks()
            } catch {
                // Retry must re-attempt the CREATE. A task that failed to save does
                // not exist, and re-reading the list will not conjure it.
                self.recordFailure(error) { [weak self] in self?.createTask(task) }
            }
        }
    }

    // MARK: - Update Task

    func updateTask(_ task: TaskItem) {
        Task {
            do {
                try await taskService.updateTask(task)

                // Clear cache to force refresh
                self.cacheService.clearOrganizationCache(orgId: self.currentOrganizationId)

                // Update local state
                if let index = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[index] = task
                }
            } catch {
                self.recordFailure(error) { [weak self] in self?.updateTask(task) }
            }
        }
    }

    // MARK: - Toggle Task Completion

    func toggleTaskCompletion(_ task: TaskItem) {
        Task {
            do {
                if task.status == .completed {
                    // Reopen task
                    try await taskService.reopenTask(id: task.id)
                    self.cacheService.clearOrganizationCache(orgId: self.currentOrganizationId)
                    self.refreshTasks()
                } else {
                    // Complete task
                    try await taskService.completeTask(id: task.id, userId: currentUserId)
                    self.cacheService.clearOrganizationCache(orgId: self.currentOrganizationId)
                    self.refreshTasks()
                }
            } catch {
                self.recordFailure(error) { [weak self] in self?.toggleTaskCompletion(task) }
            }
        }
    }

    // MARK: - Filtering

    func filteredTasks(searchText: String, filter: TaskFilter, status: TaskStatus?, priority: TaskPriority?) -> [TaskItem] {
        var filtered = tasks

        // Apply filter
        switch filter {
        case .all:
            // Exclude done tasks from "All" view
            filtered = filtered.filter { $0.status != .completed }
        case .myTasks:
            // Show only tasks ASSIGNED to user (not tasks they created for others)
            filtered = filtered.filter { task in
                task.assignedTo.contains { $0.lowercased() == currentUserId } &&
                task.status != .completed
            }
        case .today:
            // Show only tasks due today, excluding done
            filtered = filtered.filter { task in
                guard let dueDate = task.dueDate else { return false }
                return Calendar.current.isDateInToday(dueDate) && task.status != .completed
            }
        case .urgent:
            // Show only urgent/overdue tasks, excluding done
            filtered = filtered.filter {
                ($0.priority == .urgent || $0.isOverdue) &&
                $0.status != .completed
            }
        case .completed:
            // Only show done tasks
            filtered = filtered.filter { $0.status == .completed }
        }

        // Apply status filter
        if let status = status {
            filtered = filtered.filter { $0.status == status }
        }

        // Apply priority filter
        if let priority = priority {
            filtered = filtered.filter { $0.priority == priority }
        }

        // Apply search
        if !searchText.isEmpty {
            filtered = filtered.filter { task in
                task.title.localizedCaseInsensitiveContains(searchText) ||
                (task.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Sort by priority (urgent first), then by due date
        return filtered.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority.sortOrder > rhs.priority.sortOrder
            }

            if let lhsDue = lhs.dueDate, let rhsDue = rhs.dueDate {
                return lhsDue < rhsDue
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    // MARK: - Arrangement (AMB.5)

    /// The filtered, sorted, grouped result the list renders — produced in ONE
    /// pass and consumed by the empty check, the rows AND the chip counts.
    struct Arrangement {
        /// Populated for the four active filters.
        let groups: [TaskGroup]
        /// Populated for Completed, which is not banded.
        let flat: [TaskItem]
        let grouped: Bool
        /// Live count per chip. `.all` is deliberately ABSENT rather than zero —
        /// the old screen's taskCount(for: .all) returned nil so the All chip shows
        /// no count, and a missing key is how that survives a dictionary.
        let counts: [TaskFilter: Int]

        var isEmpty: Bool { grouped ? groups.isEmpty : flat.isEmpty }
    }

    /// Filter, sort, then bucket into reading bands.
    ///
    /// COMPLETED IS NOT BANDED, on purpose. The bands say what is late and what is
    /// due, and neither means anything for finished work — a done task with a date
    /// last month would sit under a header reading "Overdue". Completed stays a
    /// flat list in the same sort the rest of the screen uses.
    func arrange(searchText: String, filter: TaskFilter,
                 status: TaskStatus?, priority: TaskPriority?) -> Arrangement {
        // The calendar and the clock are read ONCE for the whole call — the counts
        // and the bands must agree with each other, and both must agree with the
        // red styling on a row, which reads TaskItem.isOverdue against Date().
        let calendar = Calendar.current
        let now = Date()

        let counts = countsForChips(calendar: calendar, now: now)

        let sorted = filteredTasks(searchText: searchText, filter: filter,
                                   status: status, priority: priority)

        guard filter != .completed else {
            return Arrangement(groups: [], flat: sorted, grouped: false, counts: counts)
        }

        // One walk, preserving the sort inside each band.
        var buckets: [TaskWhen: [TaskItem]] = [:]
        for task in sorted {
            let band = TaskWhen.band(for: task.dueDate, calendar: calendar, now: now)
            buckets[band, default: []].append(task)
        }

        // allCases order IS the reading order — overdue first.
        let groups = TaskWhen.allCases.compactMap { when -> TaskGroup? in
            guard let bucket = buckets[when], !bucket.isEmpty else { return nil }
            return TaskGroup(when: when, tasks: bucket)
        }

        return Arrangement(groups: groups, flat: [], grouped: true, counts: counts)
    }

    // MARK: - Task Counts

    /// One walk over `tasks` filling every chip's count, instead of the five
    /// separate walks the old screen triggered from its body. `.all` is left out so
    /// its chip shows none.
    ///
    /// COMPUTED PER ARRANGEMENT, NOT CACHED ON A tasks CHANGE. Two of these counts
    /// read the clock — "Today" and the overdue half of "Urgent" — so a cached
    /// value goes stale at midnight and after an overnight resume, and the chips
    /// would then disagree with the list they filter. One walk per render is the
    /// price of the chips telling the truth; it still replaces seven.
    private func countsForChips(calendar: Calendar, now: Date) -> [TaskFilter: Int] {
        let userId = currentUserId
        var mine = 0, today = 0, urgent = 0, completed = 0

        for task in tasks {
            if task.status == .completed {
                completed += 1
                continue
            }

            if task.assignedTo.contains(where: { $0.lowercased() == userId }) { mine += 1 }
            if let dueDate = task.dueDate, calendar.isDateInToday(dueDate) { today += 1 }
            // Matches filteredTasks(.urgent): urgent priority OR overdue.
            let isOverdue = (task.dueDate.map { $0 < now }) ?? false
            if task.priority == .urgent || isOverdue { urgent += 1 }
        }

        return [.myTasks: mine, .today: today, .urgent: urgent, .completed: completed]
    }
}
