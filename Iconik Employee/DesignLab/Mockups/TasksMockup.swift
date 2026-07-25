//  TasksMockup.swift
//  Iconik Employee — AMB.5's mockup
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  A REDESIGN under D12, with the parity list in AMB_BATCH1_PARITY.md.
//
//  THE STRUCTURAL CHANGE: THE LIST IS GROUPED BY WHEN.
//      Today the list is one flat run sorted by priority, and the only way to
//      discover that something is LATE is to drive the chip bar over to Urgent —
//      which is defined as "urgent priority OR overdue", so an overdue medium
//      task hides behind four urgent ones that are not actually late. There is a
//      task in the sample data that does exactly this (the tripod head, medium,
//      overdue). Watch where it lands.
//
//      So: Overdue, Today, This week, Later, No date. Inside each group the
//      app's real sort is kept — priority descending, then due date, then
//      newest. Nothing is removed: all five filters still work, still carry
//      their live counts, and still have their own empty states.
//
//  WHAT THE FIRST CUT OF THIS MOCKUP GOT WRONG, and the parity pass caught:
//      - Urgent is "urgent OR OVERDUE", not "urgent or high"
//      - All EXCLUDES completed
//      - there are FIVE distinct empty states, one per filter, each with its own
//        icon, headline and subtitle — not one generic one
//      - the All chip deliberately shows NO count (taskCount returns nil for it)
//
//  THE DETAIL IS ONE SCREEN, NOT FOUR TABS.
//      Details / Subtasks / Comments / Activity is a lot of navigation for a
//      task with three subtasks and two comments. It is one scroll now. Every
//      tab's content survives, including Activity — which is a stub in the app
//      and is kept as a stub here, because quietly mocking a real activity feed
//      would be proposing work nobody has costed.
//
//  ONE ADDITION, LABELLED ON SCREEN: the failure banner. Tasks publishes an
//  error, four places set it, and no view has ever read it — every failure in
//  this feature is silent. Under D12 that is in scope.

import SwiftUI

struct TasksMockup: View {

    private enum Scope: String, CaseIterable {
        case all = "All"
        case mine = "My Tasks"
        case today = "Today"
        case urgent = "Urgent"
        case completed = "Completed"

        var emptyIcon: String {
            switch self {
            case .all: return "tray"
            case .mine: return "person.crop.circle"
            case .today: return "calendar"
            case .urgent: return "exclamationmark.triangle"
            case .completed: return "checkmark.circle"
            }
        }

        var emptyTitle: String {
            switch self {
            case .all: return "No tasks yet"
            case .mine: return "No tasks assigned to you"
            case .today: return "No tasks due today"
            case .urgent: return "No urgent tasks"
            case .completed: return "No completed tasks"
            }
        }

        var emptyMessage: String {
            switch self {
            case .all: return "Tap + to create your first task"
            case .mine: return "You're all caught up!"
            case .today: return "You're all caught up for today!"
            case .urgent: return "Great! No urgent tasks require attention."
            case .completed: return "Complete tasks to see them here"
            }
        }
    }

    @State private var wash: Double = 1
    @State private var scope: Scope = .mine
    @State private var statusFilter: LabTask.Status?
    @State private var query = ""
    @State private var showFailure = false
    /// Ids whose completion is FLIPPED from the sample data — not a set of
    /// completed ids, which would mean a task that starts completed could never
    /// be un-ticked, and un-ticking is the whole of the Completed filter.
    @State private var flipped: Set<String> = []
    @State private var sheetTask: LabTask?

    private var feature: Color { FeatureTheme.color(for: "tasks") }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: wash)

            VStack(spacing: 10) {
                searchField.padding(.horizontal, 16)
                scopeChips
                // The app shows the status row only when the filter is not All.
                if scope != .all { statusChips }
                if showFailure { failureBanner.padding(.horizontal, 16) }
                list
            }
            .padding(.top, 8)
        }
        .sheet(item: $sheetTask) { task in
            // A SHEET, because that is what the real detail is. A redesign of
            // the CONTENT is in scope; turning a sheet into a push is a
            // navigation-shape change and is not.
            TaskDetailMockup(task: task, feature: feature, done: isDone(task))
        }
    }

    // MARK: - Lab chrome

    private var labStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(feature).frame(width: 12, height: 12)
                Text("Tasks wash").font(.footnote.weight(.semibold))
                Spacer()
                Text(wash == 0 ? "off" : "\(Int(wash * 100))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $wash, in: 0...1).tint(feature)

            Text("The list is grouped by WHEN now, inside whatever filter is on. Watch the tripod-head task — it is only medium priority but it is late, and today it sorts below four urgent things that are not.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $showFailure.animation(AmbientMotion.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show the failure state").font(.footnote.weight(.semibold))
                    Text("Tasks has no error UI at all today — it publishes an error nothing reads, so failures are silent.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(feature)
        }
        .ambientCard(density: .compact, border: .dashed(Color.primary.opacity(0.25)), fillWidth: true)
    }

    private var failureBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't save that change").font(.footnote.weight(.semibold))
                Text("You're offline. It will retry when you're back.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("Retry").font(.caption.weight(.bold)).foregroundStyle(.orange)
        }
        .ambientCard(density: .compact, border: .dashed(Color.orange.opacity(0.6)), fillWidth: true)
    }

    // MARK: - Filters

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Search tasks", text: $query)
                .font(.subheadline).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scope.allCases, id: \.self) { option in
                    let selected = option == scope
                    Button {
                        withAnimation(AmbientMotion.snappy) { scope = option }
                        AmbientHaptics.selection()
                    } label: {
                        HStack(spacing: 5) {
                            Text(option.rawValue).font(.caption.weight(.semibold))
                            // No count on All — deliberate in the app, where
                            // taskCount(for: .all) returns nil.
                            if option != .all {
                                Text("\(tasks(in: option).count)")
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
            }
            .padding(.horizontal, 16)
        }
    }

    private var statusChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Status")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                statusChip(nil, label: "All")
                ForEach(LabTask.Status.allCases, id: \.self) { status in
                    statusChip(status, label: status.rawValue)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func statusChip(_ status: LabTask.Status?, label: String) -> some View {
        let selected = statusFilter == status
        return Button {
            withAnimation(AmbientMotion.snappy) { statusFilter = status }
            AmbientHaptics.selection()
        } label: {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selected ? .white : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background {
                    if selected { Capsule().fill(status?.color ?? feature) }
                    else { Capsule().fill(.ultraThinMaterial) }
                }
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtering  (the app's real semantics, not what they look like)

    private func tasks(in scope: Scope) -> [LabTask] {
        DesignLabSampleData.tasks.filter { task in
            let done = isDone(task)
            switch scope {
            case .all:       return !done
            case .mine:      return task.mine && !done
            case .today:     return task.when == .today && !done
            // urgent OR OVERDUE — not "urgent or high", which is what the first
            // cut of this mockup had.
            case .urgent:    return (task.priority == .urgent || task.overdue) && !done
            case .completed: return done
            }
        }
    }

    private var visible: [LabTask] {
        tasks(in: scope)
            .filter { task in
                if let statusFilter, task.status != statusFilter { return false }
                guard !query.isEmpty else { return true }
                let needle = query.lowercased()
                // The app searches title AND description.
                return task.title.lowercased().contains(needle)
                    || (task.detail?.lowercased().contains(needle) ?? false)
            }
            // The app's sort, kept exactly: priority descending, then due date,
            // then newest. Grouping changes the reading order, not this.
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return priorityRank(lhs.priority) > priorityRank(rhs.priority)
                }
                return lhs.id < rhs.id
            }
    }

    private func priorityRank(_ priority: LabTask.Priority) -> Int {
        switch priority {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .urgent: return 3
        }
    }

    private var groups: [(when: LabTaskWhen, tasks: [LabTask])] {
        LabTaskWhen.allCases.compactMap { when in
            let matching = visible.filter { $0.when == when }
            return matching.isEmpty ? nil : (when: when, tasks: matching)
        }
    }

    private func isDone(_ task: LabTask) -> Bool {
        flipped.contains(task.id) ? !task.isCompleted : task.isCompleted
    }

    private func toggle(_ task: LabTask) {
        withAnimation(AmbientMotion.gentle) {
            if flipped.contains(task.id) { flipped.remove(task.id) }
            else { flipped.insert(task.id) }
        }
        AmbientHaptics.impact(.medium)
    }

    // MARK: - The list

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                labStrip.padding(.horizontal, 16).padding(.bottom, 4)

                if visible.isEmpty {
                    // Five distinct empty states, one per filter — icon,
                    // headline and subtitle all differ.
                    AmbientEmptyState(title: scope.emptyTitle,
                                      message: query.isEmpty ? scope.emptyMessage
                                                             : "Nothing matches “\(query)”.",
                                      systemImage: scope.emptyIcon)
                        .padding(.horizontal, 16)
                } else {
                    ForEach(groups, id: \.when) { group in
                        groupHeader(group.when, count: group.tasks.count)
                            .padding(.horizontal, 16)
                            .padding(.top, group.when == groups.first?.when ? 2 : 12)

                        ForEach(group.tasks) { task in
                            LabTaskCard(task: task, done: isDone(task),
                                        onToggle: { toggle(task) },
                                        onOpen: { sheetTask = task })
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.bottom, 96)
            .animation(AmbientMotion.gentle, value: scope)
        }
    }

    private func groupHeader(_ when: LabTaskWhen, count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: when.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(when.tint)
            Text(when.rawValue)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(when == .overdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.primary))
            Text("\(count)")
                .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - The row

/// Everything TaskRowView renders, in Ambient's vocabulary at compact: the
/// checkbox, the priority bar, the title, and the metadata line of status
/// badge, due date, subtask count and comment count, plus the warning glyph
/// for urgent and high.
struct LabTaskCard: View {
    let task: LabTask
    let done: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(done ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)

            Capsule().fill(task.priority.color).frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: AmbientDensity.compact.contentSpacing) {
                Text(task.title)
                    .font(AmbientDensity.compact.titleFont)
                    .strikethrough(done, color: .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    AmbientBadge(text: task.status.rawValue, tint: task.status.color)
                    if let due = task.due {
                        Label(due, systemImage: task.overdue ? "exclamationmark.triangle.fill" : "calendar")
                            .font(.caption2)
                            .foregroundStyle(task.overdue ? .red : .secondary)
                    }
                    if task.subtasks.1 > 0 {
                        Label("\(task.subtasks.0)/\(task.subtasks.1)", systemImage: "checklist")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if task.comments > 0 {
                        Label("\(task.comments)", systemImage: "bubble.left")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)

                // Not rendered anywhere in the app today, though TaskItem has
                // carried it all along: which job this belongs to.
                if let session = task.sessionLabel {
                    Label(session, systemImage: "camera.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Under All, a task assigned to someone else needs to say so.
                if !task.mine, let assignee = task.assignee {
                    Label(assignee, systemImage: "person.fill")
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if !done, task.priority == .urgent || task.priority == .high {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(task.priority.color)
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
        if task.overdue { return .red.opacity(0.45) }
        return Color.primary.opacity(0.08)
    }
}

// MARK: - Detail

/// One scrolling screen instead of four tabs. Everything the tabs carried is
/// still here, in the order you actually need it.
struct TaskDetailMockup: View {
    let task: LabTask
    let feature: Color
    let done: Bool

    @State private var editing = false
    @State private var watching = false
    @Environment(\.dismiss) private var dismiss

    private var subtaskProgress: Double {
        let total = DesignLabSampleData.sampleSubtasks.count
        guard total > 0 else { return 0 }
        return Double(DesignLabSampleData.sampleSubtasks.filter(\.done).count) / Double(total)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: feature, intensity: 0.7)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if task.sessionLabel != nil || task.workflowLabel != nil { context }
                        description
                        subtasks
                        comments
                        facts
                        activity
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editing ? "Save" : "Edit") {
                        withAnimation(AmbientMotion.snappy) { editing.toggle() }
                    }
                    .fontWeight(editing ? .semibold : .regular)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .strikethrough(done, color: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // The watch star. It renders in the app and its action is a
                // TODO — kept, and kept honest.
                Button {
                    watching.toggle()
                    AmbientHaptics.impact(.light)
                } label: {
                    Image(systemName: watching ? "star.fill" : "star")
                        .font(.system(size: 17))
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                AmbientBadge(text: task.priority.rawValue, tint: task.priority.color)
                AmbientBadge(text: task.status.rawValue, tint: task.status.color)
                if let type = task.type { AmbientBadge(text: type, tint: feature) }
            }

            if let due = task.due {
                Label(task.overdue ? "Was due \(due)" : "Due \(due)",
                      systemImage: task.overdue ? "exclamationmark.triangle.fill" : "calendar")
                    .font(.subheadline)
                    .foregroundStyle(task.overdue ? .red : .secondary)
            }

            if !DesignLabSampleData.sampleSubtasks.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(DesignLabSampleData.sampleSubtasks.filter(\.done).count)/\(DesignLabSampleData.sampleSubtasks.count) subtasks")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(subtaskProgress * 100))%")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ProgressView(value: subtaskProgress)
                        .tint(subtaskProgress == 1 ? .green : feature)
                }
            }
        }
        .ambientCard(density: .roomy, state: .highlighted,
                     border: .hairline(feature.opacity(0.3)),
                     glow: feature, fillWidth: true)
    }

    /// TaskItem carries sessionId, workflowName and workflowStepName and NOTHING
    /// in the app renders any of them — a task attached to a job cannot show you
    /// the job. This is an addition, and it is the one that makes Tasks feel
    /// like part of this app rather than a generic to-do list.
    private var context: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Belongs to")
            if let session = task.sessionLabel {
                contextRow(session, systemImage: "camera.fill", tint: FeatureTheme.color(for: "schedule"))
            }
            if let workflow = task.workflowLabel {
                contextRow(workflow, systemImage: "arrow.triangle.branch", tint: feature)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func contextRow(_ label: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).font(.footnote).foregroundStyle(tint).frame(width: 18)
            Text(label).font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Description")
            if editing {
                // A TextEditor with a visible edge, matching what the app opens
                // when you tap Edit.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15))
                    .frame(height: 110)
                    .overlay(alignment: .topLeading) {
                        Text(task.detail ?? "")
                            .font(.subheadline)
                            .padding(10)
                    }
            } else if let detail = task.detail {
                // The app renders this from HTML with the tags stripped.
                Text(detail).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No description").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private var subtasks: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Subtasks",
                                trailing: "\(DesignLabSampleData.sampleSubtasks.filter(\.done).count)/\(DesignLabSampleData.sampleSubtasks.count)")
            if editing {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(feature)
                    Text("Add a subtask").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
            ForEach(Array(DesignLabSampleData.sampleSubtasks.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(item.done ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                    Text(item.title)
                        .font(.subheadline)
                        .strikethrough(item.done, color: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if editing {
                        Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Comments", trailing: "\(DesignLabSampleData.sampleComments.count)")

            ForEach(DesignLabSampleData.sampleComments) { comment in
                HStack(alignment: .top, spacing: 10) {
                    AmbientAvatar(name: comment.author, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(comment.author).font(.footnote.weight(.semibold))
                            Text(comment.when).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(comment.text).font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        // Attachments are real in the app: name, size, and an
                        // image-or-document glyph.
                        if let attachment = comment.attachment {
                            HStack(spacing: 6) {
                                Image(systemName: attachment.isImage ? "photo" : "doc")
                                    .font(.caption).foregroundStyle(feature)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(attachment.fileName).font(.caption2).lineLimit(1)
                                    Text(attachment.size).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05)))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 8) {
                Text("Add a comment…").font(.subheadline).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Image(systemName: "paperplane.fill").font(.footnote).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 0) {
            AmbientSectionTitle("Details").padding(.bottom, 6)
            fact("Assigned to", task.assignee ?? "Unassigned", "person.fill")
            Divider().opacity(0.4)
            fact("Estimated", task.estimatedHours.map { String(format: "%.1f hours", $0) } ?? "Not set",
                 "hourglass")
            Divider().opacity(0.4)
            fact("Created", "Jul 21, 2026 at 9:14 AM", "clock.arrow.circlepath")
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func fact(_ label: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(.secondary).frame(width: 18)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 9)
    }

    /// Still a stub, on purpose. It says "Activity feed coming soon" in the app,
    /// and mocking a real one here would propose work nobody has costed.
    private var activity: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.footnote).foregroundStyle(.tertiary)
            Text("Activity feed coming soon")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, border: .dashed(Color.primary.opacity(0.2)), fillWidth: true)
    }
}
