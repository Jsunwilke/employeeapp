//
//  TasksView.swift
//  Iconik Employee
//
//  Tasks in the Ambient design language (AMB.5).
//
//  Replaces TasksMainView, deleted in the same commit. Ported from the AMB.2 lab
//  mockup the operator approved on iPhone and iPad
//  (DesignLab/Mockups/TasksMockup.swift).
//
//  THE ONE STRUCTURAL CHANGE: THE LIST IS GROUPED BY WHEN.
//      Today the list is one flat run sorted by priority, so the only way to find
//      out something is LATE is to drive the chip bar over to Urgent — and Urgent
//      is defined as "urgent priority OR overdue", which means an overdue medium
//      task sorts below four urgent ones that are not late at all.
//
//      So: Overdue, Today, This week, Later, No date, inside whatever filter is
//      active. The app's real sort is kept INSIDE each group — priority
//      descending, then due date ascending, then newest. Nothing is removed: all
//      five filters still work, still carry their live counts, and still have
//      their own five distinct empty states.
//
//      THE COMPLETED FILTER IS NOT GROUPED, and that is deliberate. The bands
//      exist to say what is late and what is due, and neither means anything for
//      finished work — a done task with a due date last month would sit under a
//      header reading "Overdue", which is visibly wrong. Completed is a flat list
//      in the app's own sort. Named in the closeout as a decision, not a drop.
//
//  Capability inventory for this surface: AMB5_TASKS_PARITY.md, which is also
//  where the four things the approved mockup could not carry are recorded.
//

import SwiftUI

// MARK: - Shared presentation colours
//
// These were written out four times between TasksMainView and TaskDetailView —
// the same switch over the same enum in the row, the chip, the detail header and
// the create form. One definition each. `tint` rather than `color` because the
// model already has a `color: String` and overloading on return type alone is
// ambiguous at the call site.

extension TaskPriority {
    var tint: Color {
        switch self {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

extension TaskStatus {
    var tint: Color {
        switch self {
        case .todo: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        }
    }
}

// MARK: - The reading order

/// The band a task falls in, which is what the redesign groups by.
///
/// Overdue leads, because that is the thing the flat priority-sorted list could
/// not tell you.
enum TaskWhen: String, CaseIterable, Identifiable {
    case overdue = "Overdue"
    case today = "Today"
    case thisWeek = "This week"
    case later = "Later"
    case noDate = "No date"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overdue: return "exclamationmark.triangle.fill"
        case .today: return "sun.max.fill"
        case .thisWeek: return "calendar"
        case .later: return "clock"
        case .noDate: return "tray"
        }
    }

    var tint: Color {
        switch self {
        case .overdue: return .red
        case .today: return .orange
        case .thisWeek: return .blue
        case .later: return .secondary
        case .noDate: return .secondary
        }
    }

    /// Which band a due date falls in.
    ///
    /// PAST FIRST, and that ordering is the whole correctness of this function. A
    /// task due at 09:00 today, read at 17:00, is late — `TaskItem.isOverdue` is
    /// `dueDate < Date()`, so the row already draws its date in red with a warning
    /// triangle. Testing `isDateInToday` first would file that row under a "Today"
    /// header while it rendered as overdue, which is the screen contradicting
    /// itself. The same `dueDate < now` test is used here, in the chip counts, and
    /// by `isOverdue`, so all three always agree.
    ///
    /// It reads the DATE rather than `isOverdue` itself because `isOverdue` is
    /// false for a completed task, and a defensive band function should not depend
    /// on the caller having excluded those.
    static func band(for dueDate: Date?, calendar: Calendar = .current,
                     now: Date = Date()) -> TaskWhen {
        guard let dueDate else { return .noDate }
        if dueDate < now { return .overdue }
        if calendar.isDateInToday(dueDate) { return .today }
        let startOfToday = calendar.startOfDay(for: now)
        guard let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday) else {
            return .later
        }
        return dueDate < endOfWeek ? .thisWeek : .later
    }
}

/// One band and the tasks in it. Built once per change by the view model rather
/// than per body pass — L4 in the plan, the pattern for any converted list.
struct TaskGroup: Identifiable {
    let when: TaskWhen
    let tasks: [TaskItem]
    var id: String { when.rawValue }
}

// MARK: - The screen

struct TasksView: View {
    @StateObject private var viewModel = TasksViewModel()

    @State private var searchText = ""
    @State private var selectedFilter: TaskFilter = .myTasks
    @State private var selectedStatus: TaskStatus? = nil
    /// Passed through to the filter and never set: there is no priority filter UI
    /// anywhere in the app, and there never was. Kept so the view model's
    /// signature does not quietly lose a parameter. See AMB5_TASKS_PARITY.md.
    @State private var selectedPriority: TaskPriority? = nil

    @State private var showingCreateTask = false
    @State private var selectedTask: TaskItem? = nil

    private var feature: Color { FeatureTheme.color(for: "tasks") }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: feature)

                // ONE filter pass per body render, reused by the empty check, the
                // group list and nothing else. The old screen called
                // filteredTasks twice and taskCount five more times, so every
                // keystroke in the search field ran seven full filter-and-sort
                // passes over the whole task array.
                let result = viewModel.arrange(
                    searchText: searchText,
                    filter: selectedFilter,
                    status: selectedStatus,
                    priority: selectedPriority
                )

                VStack(spacing: 10) {
                    searchField.padding(.horizontal, 16)
                    filterChips(result.counts)
                    // The app shows the status row only when the filter is not All.
                    if selectedFilter != .all { statusChips }
                    if viewModel.error != nil { failureBanner.padding(.horizontal, 16) }
                    list(result)
                }
                .padding(.top, 8)
            }
            // Room for the app's floating bar. Applied INSIDE this screen's own
            // navigation container, because the shell cannot reach into a self-nav
            // feature (AMB.4). The mockup's own 96pt bottom padding was lab-local
            // and is deliberately not ported — the two would have doubled.
            .tabBarClearance()
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Placement kept exactly as it was: Home and the overflow both
                // leading, create trailing. On iPad HomeToolbarButton renders
                // nothing, so the overflow takes the slot on its own.
                ToolbarItem(placement: .navigationBarLeading) {
                    HomeToolbarButton()
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button {
                            viewModel.refreshTasks()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button {
                            viewModel.clearCacheAndReload()
                        } label: {
                            Label("Clear Cache", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreateTask = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("New task")
                }
            }
            .sheet(isPresented: $showingCreateTask) {
                CreateTaskView(onTaskCreated: { newTask in
                    viewModel.createTask(newTask)
                    showingCreateTask = false
                })
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task, onTaskUpdated: { updatedTask in
                    viewModel.updateTask(updatedTask)
                })
            }
            .onAppear {
                viewModel.loadTasks()
            }
            .onDisappear {
                viewModel.stopListening()
            }
        }
        // Matches the shell's own convention and the approved mockup's detail —
        // every other navigation container in this app is a stack. Without it a
        // plain NavigationView takes iPad's split behaviour. Named in the
        // closeout as a deliberate change.
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            // The app searches title AND description.
            TextField("Search tasks", text: $searchText)
                .font(.subheadline)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    // MARK: - Filters

    private func filterChips(_ counts: [TaskFilter: Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskFilter.allCases, id: \.self) { filter in
                    filterChip(filter, count: counts[filter])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(_ filter: TaskFilter, count: Int?) -> some View {
        let selected = filter == selectedFilter
        return Button {
            withAnimation(AmbientMotion.snappy) {
                selectedFilter = filter
                // The status row is hidden under All — it always has been. But the
                // status filter itself was still being APPLIED, so picking
                // "In Progress" under My Tasks and then switching to All left All
                // silently filtered by a chip that was no longer on screen, and
                // All is the one chip with no count to contradict it. Clearing it
                // on the way in is the only honest option: either the control is
                // visible or it is not in effect.
                if filter == .all { selectedStatus = nil }
            }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 5) {
                Text(filter.displayName).font(.caption.weight(.semibold))
                // No count on All — deliberate in the app, where the old
                // taskCount(for: .all) returned nil.
                if let count {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.75))
                                                  : AnyShapeStyle(.tertiary))
                }
            }
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background {
                if selected { Capsule().fill(feature) }
                else { Capsule().fill(.ultraThinMaterial) }
            }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.1)))
        }
        .buttonStyle(.plain)
    }

    private var statusChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Status")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                statusChip(nil, label: "All")
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    statusChip(status, label: status.displayName)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func statusChip(_ status: TaskStatus?, label: String) -> some View {
        let selected = selectedStatus == status
        return Button {
            withAnimation(AmbientMotion.snappy) { selectedStatus = status }
            AmbientHaptics.selection()
        } label: {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selected ? .white : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background {
                    if selected { Capsule().fill(status?.tint ?? feature) }
                    else { Capsule().fill(.ultraThinMaterial) }
                }
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Failure

    /// Tasks publishes an error, four places set it, and until now NO view had
    /// ever read it — every failure in this feature was silent. Under D12 that is
    /// a state that should exist and does not, so it is in scope.
    ///
    /// Retry is a real control. The mockup drew it as static text, and shipping a
    /// dead one is exactly what AMB.3 had to fix three of.
    private var failureBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tasks couldn't update").font(.footnote.weight(.semibold))
                Text(viewModel.error?.localizedDescription ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.retryAfterFailure()
            } label: {
                Text("Retry").font(.caption.weight(.bold)).foregroundStyle(.orange)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(AmbientMotion.snappy) { viewModel.clearError() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .ambientCard(density: .compact, border: .dashed(Color.orange.opacity(0.6)),
                     fillWidth: true)
    }

    // MARK: - The list

    @ViewBuilder
    private func list(_ result: TasksViewModel.Arrangement) -> some View {
        if viewModel.isLoading && viewModel.tasks.isEmpty {
            loadingView
        } else {
            ScrollView {
                LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                    if result.isEmpty {
                        emptyState
                            .padding(.horizontal, 16)
                    } else if result.grouped {
                        ForEach(Array(result.groups.enumerated()), id: \.element.id) { index, group in
                            groupHeader(group.when, count: group.tasks.count)
                                .padding(.horizontal, 16)
                                .padding(.top, index == 0 ? 2 : 12)

                            ForEach(group.tasks) { task in
                                row(task)
                            }
                        }
                    } else {
                        // Completed: one flat list in the app's sort. See the file
                        // header for why the bands are not applied to done work.
                        ForEach(result.flat) { task in
                            row(task)
                        }
                    }
                }
                .padding(.top, 2)
                .animation(AmbientMotion.gentle, value: selectedFilter)
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        TaskCardRow(
            task: task,
            assignee: viewModel.assigneeLabel(for: task),
            isMine: viewModel.isAssignedToCurrentUser(task),
            onToggleComplete: { viewModel.toggleTaskCompletion(task) },
            onOpen: { selectedTask = task }
        )
        .padding(.horizontal, 16)
    }

    private func groupHeader(_ when: TaskWhen, count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: when.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(when.tint)
            Text(when.rawValue)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(when == .overdue ? AnyShapeStyle(Color.red)
                                                  : AnyShapeStyle(Color.primary))
            Text("\(count)")
                .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    /// Five distinct empty states, one per filter — icon, headline and subtitle
    /// all differ — plus a sixth for a search that matched nothing, which the old
    /// screen could not distinguish from an empty filter.
    private var emptyState: some View {
        AmbientEmptyState(
            title: searchText.isEmpty ? selectedFilter.emptyTitle : "No matches",
            message: searchText.isEmpty
                ? selectedFilter.emptyMessage
                : "Nothing in \(selectedFilter.displayName) matches “\(searchText)”.",
            systemImage: searchText.isEmpty ? selectedFilter.emptyIcon : "magnifyingglass"
        )
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading tasks…")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Task Filter

enum TaskFilter: String, CaseIterable {
    case all = "all"
    case myTasks = "my_tasks"
    case today = "today"
    case urgent = "urgent"
    case completed = "completed"

    var displayName: String {
        switch self {
        case .all: return "All"
        case .myTasks: return "My Tasks"
        case .today: return "Today"
        case .urgent: return "Urgent"
        case .completed: return "Completed"
        }
    }

    // The five empty states, carried verbatim from the screen this replaces.

    var emptyIcon: String {
        switch self {
        case .all: return "tray"
        case .myTasks: return "person.crop.circle"
        case .today: return "calendar"
        case .urgent: return "exclamationmark.triangle"
        case .completed: return "checkmark.circle"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "No tasks yet"
        case .myTasks: return "No tasks assigned to you"
        case .today: return "No tasks due today"
        case .urgent: return "No urgent tasks"
        case .completed: return "No completed tasks"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "Tap + to create your first task"
        case .myTasks: return "You're all caught up!"
        case .today: return "You're all caught up for today!"
        case .urgent: return "Great! No urgent tasks require attention."
        case .completed: return "Complete tasks to see them here"
        }
    }
}

// MARK: - The row

/// Everything TaskRowView rendered, in Ambient's vocabulary at compact.
///
/// THE PRIORITY SPINE IS GONE (operator, 2026-07-25 — it did not read right on a
/// card). Priority reaches the row only through the trailing glyph, which fires
/// for urgent and high, so low and medium are no longer distinguishable here.
/// That is acceptable because grouping by WHEN carries the urgency the spine was
/// competing to express, the in-group sort is still by priority, and the detail
/// still badges it. The dashboard's own task row lost the spine in AMB.4 and
/// gained the same glyph, so the two readings of the same object still agree.
struct TaskCardRow: View {
    let task: TaskItem
    /// Resolved through TeamService where a name is known, and the model's own
    /// assignmentDisplayText where it is not — so this degrades to "3 assignees"
    /// rather than to blank. See AMB5_TASKS_PARITY.md finding 4.
    let assignee: String?
    let isMine: Bool
    let onToggleComplete: () -> Void
    let onOpen: () -> Void

    private var done: Bool { task.status == .completed }

    var body: some View {
        HStack(spacing: 10) {
            // Outside the row's tap target, so ticking a task off never opens it.
            Button(action: onToggleComplete) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(done ? AnyShapeStyle(Color.green)
                                          : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: AmbientDensity.compact.contentSpacing) {
                Text(task.title)
                    .font(AmbientDensity.compact.titleFont)
                    .strikethrough(done, color: .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    AmbientBadge(text: task.status.displayName, tint: task.status.tint)

                    if let dueDate = task.dueDate {
                        Label(TaskDateFormat.relative(dueDate),
                              systemImage: task.isOverdue ? "exclamationmark.triangle.fill"
                                                          : "calendar")
                            .font(.caption2)
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                    }

                    if !task.subtasks.isEmpty {
                        let completed = task.subtasks.filter(\.completed).count
                        Label("\(completed)/\(task.subtasks.count)", systemImage: "checklist")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    if task.commentCount > 0 {
                        Label("\(task.commentCount)", systemImage: "bubble.left")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)

                // Which workflow this belongs to. On the model all along and
                // rendered nowhere in the app. The SESSION half of the approved
                // design is absent on purpose: TaskItem carries only sessionId,
                // and a raw uuid is worse than nothing. See AMB5_TASKS_PARITY.md.
                if let workflow = task.workflowName, !workflow.isEmpty {
                    Label(workflow, systemImage: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Under All, a task assigned to someone else needs to say so.
                if !isMine, let assignee, !assignee.isEmpty {
                    Label(assignee, systemImage: "person.fill")
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // NOT gated on `done`, and this deviates from the mockup deliberately.
            // The mockup hid the glyph on a completed row; combined with the
            // approved removal of the priority spine, that left rows in the
            // Completed filter — the one filter showing nothing but completed
            // tasks — with NO priority signal at all, where the old row carried
            // both. The receded card state and the strikethrough already say
            // "done", so the glyph does not compete with them.
            if task.priority == .urgent || task.priority == .high {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(task.priority.tint)
            }
        }
        .ambientCard(density: .compact,
                     state: done ? .receded : .normal,
                     border: .hairline(borderTint))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private var borderTint: Color {
        if done { return Color.primary.opacity(0.06) }
        if task.isOverdue { return .red.opacity(0.45) }
        return Color.primary.opacity(0.08)
    }
}

// MARK: - Dates

/// The relative date the row and the detail both show. One definition; the row
/// carried its own private copy before.
///
/// The formatter comes from the app's shared `Formatters` cache, which exists for
/// exactly this reason. The first cut built a DateFormatter inside this function —
/// so once per row, on every re-render, meaning once per row per keystroke in the
/// search field. DateFormatter construction is genuinely expensive.
enum TaskDateFormat {
    static func relative(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return Formatters.shortDate.string(from: date)
    }
}
