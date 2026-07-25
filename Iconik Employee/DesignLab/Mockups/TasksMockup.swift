//  TasksMockup.swift
//  Iconik Employee — AMB.5's mockup
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  THE QUESTION THIS SCREEN EXISTS TO ASK
//      Tasks is the one batch-1 surface where Ambient is not a restyle of a
//      card — it is the ARRIVAL of one. TaskListView today is a LazyVStack at
//      spacing 0 where each row is padding and then a full-width Divider: no
//      card, no background, no corner radius, no shadow anywhere in the whole
//      feature. Turning eighteen flat rows into eighteen glass cards is a real
//      visual change and it can go either way, so the switch at the top of this
//      screen draws BOTH and the operator flips between them on the device.
//
//      That is the decision to bring back: do the cards read as better, or just
//      as busier? Everything else here follows from it.
//
//  THE WASH  (D11)
//      Tasks' feature colour, #E93D82, straight out of FeatureTheme. Full
//      strength to start — this screen has not been judged for intensity, and
//      pink at 100% behind a long list is exactly the kind of thing that has to
//      be seen rather than argued about. Home settled at 90%.
//
//  ONE THING HERE IS NOT A RESTYLE, and it is labelled as such on the screen:
//      the failure banner. Tasks has NO error UI at all — the view model
//      publishes an error, four places set it, and no view ever reads it, so a
//      failed load or a failed save is silent. A restyle does not fix that, so
//      the toggle shows what fixing it would look like and AMB.5 gets to decide
//      whether it is in scope. It is drawn dashed for the same reason the lab
//      strip is: it is not the same kind of thing as the work around it.

import SwiftUI

struct TasksMockup: View {

    /// The five chips across the top, with My Tasks selected by default —
    /// which is the real default, not All.
    private enum Scope: String, CaseIterable {
        case all = "All"
        case mine = "My Tasks"
        case today = "Today"
        case urgent = "Urgent"
        case completed = "Completed"
    }

    private enum RowStyle: String, CaseIterable {
        case cards = "Ambient cards"
        case flat = "Today's flat rows"
    }

    @State private var wash: Double = 1
    @State private var style: RowStyle = .cards
    @State private var scope: Scope = .mine
    @State private var query = ""
    @State private var showFailure = false
    /// Ids whose completion is FLIPPED from what the sample data says — not a
    /// set of completed ids. Storing "completed" instead means a task that
    /// starts completed can never be un-ticked, which is exactly what happens
    /// the moment anyone taps a box under the Completed filter.
    @State private var flipped: Set<String> = []
    @State private var sheetTask: LabTask?

    private var feature: Color { FeatureTheme.color(for: "tasks") }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: wash)

            VStack(spacing: 10) {
                searchField.padding(.horizontal, 16)
                chips

                if showFailure { failureBanner.padding(.horizontal, 16) }

                list
            }
            .padding(.top, 8)
        }
        .sheet(item: $sheetTask) { task in
            // A SHEET, not a push — that is what the real detail is, and a
            // restyle phase does not get to change the shape of navigation.
            TaskDetailMockup(task: task, feature: feature)
        }
    }

    // MARK: - Lab chrome

    private var labStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Row style", selection: $style) {
                ForEach(RowStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Text("The decision. Flip it while scrolling — today's rows are flat with a divider between them, and nothing in Tasks has ever been a card.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.4)

            HStack {
                Circle().fill(feature).frame(width: 12, height: 12)
                Text("Tasks wash").font(.footnote.weight(.semibold))
                Spacer()
                Text(wash == 0 ? "off" : "\(Int(wash * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $wash, in: 0...1).tint(feature)

            Toggle(isOn: $showFailure.animation(AmbientMotion.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show the failure state").font(.footnote.weight(.semibold))
                    Text("NOT a restyle. Tasks has no error UI at all today — failures are silent. This is what fixing it would look like.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't save that change")
                    .font(.footnote.weight(.semibold))
                Text("You're offline. It will retry when you're back.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("Retry")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
        }
        .ambientCard(density: .compact, border: .dashed(Color.orange.opacity(0.6)), fillWidth: true)
    }

    // MARK: - Filters

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search tasks", text: $query)
                .font(.subheadline)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scope.allCases, id: \.self) { option in
                    chip(option)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ option: Scope) -> some View {
        let selected = option == scope
        return Button {
            withAnimation(AmbientMotion.snappy) { scope = option }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 5) {
                Text(option.rawValue).font(.caption.weight(.semibold))
                // The live counts the real chips carry. Counted the same way
                // the list filters, so a chip saying 11 opens onto 11 rows —
                // in the app each chip rescans the whole array on every body
                // pass, which is AMB.5's to fix, not the mockup's to imitate.
                Text("\(tasks(in: option, hidingCompleted: true).count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.75))
                                              : AnyShapeStyle(.tertiary))
            }
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if selected { Capsule().fill(feature) }
                else { Capsule().fill(.ultraThinMaterial) }
            }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.1)))
        }
        .buttonStyle(.plain)
    }

    /// `hidingCompleted` drops finished work from every scope except Completed
    /// itself — the rule the list uses, so a chip's count and the list it opens
    /// onto can never disagree.
    private func tasks(in scope: Scope, hidingCompleted: Bool = false) -> [LabTask] {
        DesignLabSampleData.tasks.filter { task in
            let inScope: Bool
            switch scope {
            case .all: inScope = true
            case .mine: inScope = task.mine
            case .today: inScope = task.due == "Today" || task.overdue
            case .urgent: inScope = task.priority == .urgent || task.priority == .high
            case .completed: inScope = isDone(task)
            }
            guard inScope else { return false }
            guard hidingCompleted, scope != .completed else { return true }
            return !isDone(task)
        }
    }

    private var visible: [LabTask] {
        tasks(in: scope, hidingCompleted: true).filter { task in
            guard !query.isEmpty else { return true }
            return task.title.lowercased().contains(query.lowercased())
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
            LazyVStack(spacing: style == .cards ? AmbientDensity.compact.stackSpacing : 0) {
                labStrip
                    .padding(.horizontal, 16)
                    .padding(.bottom, style == .cards ? 4 : 10)

                if visible.isEmpty {
                    AmbientEmptyState(
                        title: "Nothing here",
                        message: query.isEmpty
                            ? "No tasks match this filter."
                            : "No tasks match “\(query)”.",
                        systemImage: "checklist")
                } else {
                    ForEach(visible) { task in
                        Group {
                            switch style {
                            case .cards:
                                LabTaskCard(task: task, done: isDone(task),
                                            onToggle: { toggle(task) },
                                            onOpen: { sheetTask = task })
                                    .padding(.horizontal, 16)
                            case .flat:
                                LabTaskFlatRow(task: task, done: isDone(task),
                                               onToggle: { toggle(task) },
                                               onOpen: { sheetTask = task })
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 96)
            .animation(AmbientMotion.gentle, value: style)
        }
    }
}

// MARK: - The proposal: a task as a card

/// Everything the real row renders, in Ambient's vocabulary at compact: the
/// completion box, the priority bar, the title, and the metadata line of status
/// badge, due date, subtask count and comment count.
///
/// What is deliberately still NOT rendered, though the model carries it:
/// description, assignee, attachments, task type, estimated hours. The real row
/// leaves all five out and a restyle is not the place to start putting them in —
/// they are on the detail sheet, where they belong.
struct LabTaskCard: View {
    let task: LabTask
    let done: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            checkbox
            Capsule().fill(task.priority.color).frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: AmbientDensity.compact.contentSpacing) {
                Text(task.title)
                    .font(AmbientDensity.compact.titleFont)
                    .strikethrough(done, color: .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                metadata
            }

            Spacer(minLength: 0)

            if !done, task.priority == .urgent || task.priority == .high {
                Image(systemName: "exclamationmark.triangle.fill")
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

    private var checkbox: some View {
        Button(action: onToggle) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(done ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var metadata: some View {
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
    }
}

// MARK: - What ships today, for comparison

/// Tasks' row exactly as the app draws it now: padding, a divider, nothing else.
/// This is here so the card proposal is judged against the real thing rather
/// than against a memory of it.
struct LabTaskFlatRow: View {
    let task: LabTask
    let done: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(done ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain)

                Rectangle().fill(task.priority.color).frame(width: 3, height: 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.body)
                        .strikethrough(done, color: .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        Text(task.status.rawValue)
                            .font(.caption2)
                            .foregroundStyle(task.status.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(task.status.color.opacity(0.2)))
                        if let due = task.due {
                            Label(due, systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(task.overdue ? .red : .secondary)
                        }
                        if task.subtasks.1 > 0 {
                            Text("\(task.subtasks.0)/\(task.subtasks.1)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if task.comments > 0 {
                            Label("\(task.comments)", systemImage: "bubble.left")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 0)

                if task.priority == .urgent || task.priority == .high {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(task.priority.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            Divider()
        }
    }
}

// MARK: - Detail

/// The detail is a SHEET with a segmented picker over Details, Subtasks,
/// Comments and Activity — and Activity is a stub in the app that reads
/// "Activity feed coming soon". It is kept as a stub here on purpose: a mockup
/// that quietly fills in an unbuilt tab is proposing work nobody costed.
///
/// The title is not editable after creation in the app either. That is not a
/// restyle question, but it is worth the operator seeing while they are here.
struct TaskDetailMockup: View {
    let task: LabTask
    let feature: Color

    private enum Tab: String, CaseIterable {
        case details = "Details"
        case subtasks = "Subtasks"
        case comments = "Comments"
        case activity = "Activity"
    }

    @State private var tab: Tab = .details
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // The sheet is its own presentation, so it does supply a container —
        // that is what the real detail does, and it is not the shell's nav.
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: feature, intensity: 0.7)

                VStack(spacing: 12) {
                    Picker("Section", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            switch tab {
                            case .details: details
                            case .subtasks: subtasks
                            case .comments: comments
                            case .activity: activity
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    AmbientBadge(text: task.status.rawValue, tint: task.status.color)
                    AmbientBadge(text: task.priority.rawValue, tint: task.priority.color)
                    if let type = task.type {
                        AmbientBadge(text: type, tint: feature)
                    }
                }
            }
            .ambientCard(density: .roomy, state: .highlighted,
                         border: .hairline(feature.opacity(0.3)),
                         glow: feature, fillWidth: true)

            if let detail = task.detail {
                AmbientNoteCard(title: "Description", text: detail, accent: feature)
            }

            VStack(alignment: .leading, spacing: 0) {
                row("Due", task.due ?? "No due date",
                    task.overdue ? "exclamationmark.triangle.fill" : "calendar",
                    tint: task.overdue ? .red : .secondary)
                Divider().opacity(0.4)
                row("Assigned to", task.assignee ?? "Unassigned", "person.fill")
                Divider().opacity(0.4)
                row("Estimated", task.estimatedHours.map { "\(Formatters.duration($0 * 3600))" } ?? "—",
                    "hourglass")
                Divider().opacity(0.4)
                row("Attachments", "None", "paperclip")
            }
            .ambientCard(density: .roomy, fillWidth: true)

            Text("Description, assignee, type, estimated hours and attachments are all on the model and none of them appear in the list row. That is the right call — but it is a choice, and this is where you get to disagree with it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ label: String, _ value: String,
                     _ symbol: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(tint).frame(width: 20)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 9)
    }

    private var subtasks: some View {
        VStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
            AmbientSectionTitle("Subtasks",
                                trailing: "\(task.subtasks.0)/\(max(task.subtasks.1, DesignLabSampleData.sampleSubtasks.count))")
            ForEach(Array(DesignLabSampleData.sampleSubtasks.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(item.done ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                    Text(item.title)
                        .font(.subheadline)
                        .strikethrough(item.done, color: .secondary)
                    Spacer(minLength: 0)
                }
                .ambientCard(density: .compact, state: item.done ? .receded : .normal,
                             fillWidth: true)
            }
        }
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
            AmbientSectionTitle("Comments", trailing: "\(DesignLabSampleData.sampleComments.count)")
            ForEach(Array(DesignLabSampleData.sampleComments.enumerated()), id: \.offset) { _, comment in
                HStack(alignment: .top, spacing: 10) {
                    AmbientAvatar(name: comment.author, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(comment.author).font(.footnote.weight(.semibold))
                            Text(comment.when).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(comment.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .ambientCard(density: .compact, fillWidth: true)
            }
        }
    }

    private var activity: some View {
        AmbientEmptyState(title: "Activity feed coming soon",
                          message: "This tab is a stub in the app today. It is left as one here rather than mocked, so nothing gets approved that nobody has costed.",
                          systemImage: "clock.arrow.circlepath")
    }
}
