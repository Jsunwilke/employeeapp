//
//  TaskDetailView.swift
//  Iconik Employee
//
//  The task detail in the Ambient design language (AMB.5).
//
//  Ported from the AMB.2 lab mockup the operator approved on iPhone and iPad
//  (DesignLab/Mockups/TasksMockup.swift, TaskDetailMockup).
//
//  THE STRUCTURAL CHANGE: ONE SCROLL, NOT FOUR TABS.
//      Details / Subtasks / Comments / Activity is a lot of navigation for a task
//      with three subtasks and two comments. Every tab's content survives, in the
//      order you actually need it, including Activity — which is a stub in the app
//      and is kept as a stub, because quietly building a real activity feed would
//      be proposing work nobody has costed.
//
//  IT IS STILL A SHEET. Turning a sheet into a push is a navigation-shape change
//  and D2 and D3 keep that out of a conversion phase.
//
//  THE TYPE NAME IS UNCHANGED ON PURPOSE. The home dashboard's TasksWidget
//  presents this same view (DashboardWidgets.swift), and that surface shipped in
//  AMB.4 — renaming the type would have pushed churn into a screen this phase has
//  no business touching.
//
//  THREE EDITORS THE APPROVED MOCKUP DID NOT CARRY ARE RESTORED HERE: the
//  priority segmented picker, the status menu picker, and the estimated-hours
//  stepper. The mockup moved priority and status up into header badges and drew
//  only the description editor in its editing state, which reads as though they
//  had become display-only. They are editable in the app today and they stay
//  editable. This is the AMB.3 lesson repeating: an approved mockup is a design
//  decision, not a capability inventory. See AMB5_TASKS_PARITY.md finding 1.
//

import SwiftUI

struct TaskDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    let task: TaskItem
    let onTaskUpdated: (TaskItem) -> Void

    @State private var isEditing = false
    @State private var editedTask: TaskItem

    // Comment state
    @StateObject private var commentService = CommentService.shared
    @State private var newCommentText = ""
    @State private var isSendingComment = false

    /// Names for the assigned-to line, from the service the rest of the app
    /// already uses. See AMB5_TASKS_PARITY.md finding 4.
    @State private var memberNames: [String: String] = [:]

    init(task: TaskItem, onTaskUpdated: @escaping (TaskItem) -> Void) {
        self.task = task
        self.onTaskUpdated = onTaskUpdated
        self._editedTask = State(initialValue: task)
    }

    private var feature: Color { FeatureTheme.color(for: "tasks") }

    private var currentUserId: String {
        return (UserManager.shared.getCurrentUserIDUnified() ?? "").lowercased()
    }

    private var currentUserName: String {
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? "Unknown User" : fullName
    }

    private var done: Bool { editedTask.status == .completed }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: feature, intensity: 0.7)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if hasWorkflowContext { context }
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
            // The task's own title, as the old detail had it — NOT the mockup's
            // static "Task". The title lives in the header card now, and the header
            // card scrolls away: on a task with a few comments there would be
            // nothing on screen saying which task you were in.
            .navigationTitle(editedTask.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing {
                            saveChanges()
                        } else {
                            withAnimation(AmbientMotion.snappy) { isEditing = true }
                        }
                    }
                    .fontWeight(isEditing ? .semibold : .regular)
                }
            }
            .onAppear {
                // Load comments when view appears
                Task {
                    try? await commentService.fetchComments(for: task.id)
                }
                loadMemberNames()
            }
            .onDisappear {
                commentService.stopListening(taskId: task.id)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(editedTask.title)
                    .font(.title3.weight(.semibold))
                    .strikethrough(done, color: .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // The watch star. It renders in the app and its action is an empty
                // TODO — kept, and kept honest. Wiring it would be a behaviour
                // change, and TaskService.toggleWatch already exists unused.
                Image(systemName: editedTask.isWatchedBy(userId: currentUserId) ? "star.fill" : "star")
                    .font(.system(size: 17))
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(editedTask.isWatchedBy(userId: currentUserId)
                                        ? "Watching this task" : "Not watching this task")
            }

            HStack(spacing: 6) {
                AmbientBadge(text: editedTask.priority.displayName,
                             tint: editedTask.priority.tint)
                AmbientBadge(text: editedTask.status.displayName,
                             tint: editedTask.status.tint)
                // Only when it says something. Every task the app creates is
                // .general, and a badge reading "General" on all of them is noise
                // where the mockup's sample data had descriptive types.
                if editedTask.taskType != .general {
                    AmbientBadge(text: editedTask.taskType.displayName, tint: feature)
                }
            }

            if let dueDate = editedTask.dueDate {
                Label(editedTask.isOverdue
                        ? "Was due \(TaskDateFormat.relative(dueDate))"
                        : "Due \(TaskDateFormat.relative(dueDate))",
                      systemImage: editedTask.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                    .font(.subheadline)
                    .foregroundStyle(editedTask.isOverdue ? .red : .secondary)
            }

            if !editedTask.subtasks.isEmpty {
                let completed = editedTask.subtasks.filter(\.completed).count
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(completed)/\(editedTask.subtasks.count) subtasks")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(editedTask.subtaskProgress * 100))%")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ProgressView(value: editedTask.subtaskProgress)
                        .tint(editedTask.subtaskProgress == 1 ? .green : feature)
                }
            }
        }
        .ambientCard(density: .roomy, state: .highlighted,
                     border: .hairline(feature.opacity(0.3)),
                     glow: feature, fillWidth: true)
    }

    // MARK: - Belongs to

    /// TaskItem carries workflowName and workflowStepName and NOTHING in the app
    /// rendered either of them — a task attached to a workflow could not show you
    /// the workflow.
    ///
    /// The SESSION half of the approved design is deliberately absent. TaskItem
    /// carries only sessionId, an opaque uuid with no name anywhere on the model
    /// and no join in TaskService, and a raw uuid on screen is worse than nothing.
    /// Making it real needs a sessions read Tasks does not have, which D12 puts
    /// out of scope for a redesign phase. Named, not faked — AMB.3's precedent.
    private var hasWorkflowContext: Bool {
        !(editedTask.workflowName ?? "").isEmpty || !(editedTask.workflowStepName ?? "").isEmpty
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Belongs to")
            if let workflow = editedTask.workflowName, !workflow.isEmpty {
                contextRow(workflow, systemImage: "arrow.triangle.branch", tint: feature)
            }
            if let step = editedTask.workflowStepName, !step.isEmpty {
                contextRow(step, systemImage: "arrow.turn.down.right", tint: .secondary)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func contextRow(_ label: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).font(.footnote).foregroundStyle(tint).frame(width: 18)
            Text(label).font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
    }

    // MARK: - Description

    private var description: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Description")
            if isEditing {
                TextEditor(text: Binding(
                    get: { editedTask.description ?? "" },
                    set: { editedTask.description = $0.isEmpty ? nil : $0 }
                ))
                .font(.subheadline)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15))
                )
            } else if let text = editedTask.description, !text.isEmpty {
                // Rendered from HTML with the tags stripped, as before.
                Text(AttributedString(html: text))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No description")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    // MARK: - Subtasks

    private var subtasks: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle(
                "Subtasks",
                trailing: editedTask.subtasks.isEmpty
                    ? nil
                    : "\(editedTask.subtasks.filter(\.completed).count)/\(editedTask.subtasks.count)")

            if isEditing {
                SubtaskComposer { title in
                    addSubtask(title)
                }
            }

            if editedTask.subtasks.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checklist").font(.footnote).foregroundStyle(.tertiary)
                    Text("No subtasks yet")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
            } else {
                ForEach(editedTask.subtasks) { subtask in
                    HStack(spacing: 10) {
                        Button {
                            toggleSubtask(subtask.id)
                        } label: {
                            Image(systemName: subtask.completed ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17))
                                .foregroundStyle(subtask.completed ? AnyShapeStyle(Color.green)
                                                                   : AnyShapeStyle(.tertiary))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(subtask.completed ? "Mark not done" : "Mark done")

                        Text(subtask.title)
                            .font(.subheadline)
                            .strikethrough(subtask.completed, color: .secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        if isEditing {
                            Button {
                                deleteSubtask(subtask.id)
                            } label: {
                                Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete subtask")
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    // MARK: - Comments

    /// THIS TASK's comments.
    ///
    /// CommentService is a singleton and `comments` is one shared array, so opening
    /// task B showed task A's comments — and its count — until B's fetch landed, or
    /// permanently when offline. Pre-existing, but the redesign puts a COUNT in the
    /// section title, which turns a brief flicker of the wrong list into a wrong
    /// number sitting on screen. TaskComment carries taskId, so filtering is exact.
    private var taskComments: [TaskComment] {
        commentService.comments.filter { $0.taskId == task.id }
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Comments", trailing: "\(taskComments.count)")

            if taskComments.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left").font(.footnote).foregroundStyle(.tertiary)
                    Text("No comments yet")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                ForEach(taskComments) { comment in
                    commentRow(comment)
                }
            }

            HStack(spacing: 8) {
                TextField("Add a comment…", text: $newCommentText)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                Button {
                    sendComment()
                } label: {
                    if isSendingComment {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.footnote)
                            .foregroundStyle(newCommentText.isEmpty ? AnyShapeStyle(.tertiary)
                                                                    : AnyShapeStyle(feature))
                    }
                }
                .buttonStyle(.plain)
                .disabled(newCommentText.isEmpty || isSendingComment)
                .accessibilityLabel("Send comment")
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func commentRow(_ comment: TaskComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AmbientAvatar(name: comment.displayName, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.displayName).font(.footnote.weight(.semibold))
                    Text(comment.timeAgoText).font(.caption2).foregroundStyle(.tertiary)
                }
                Text(comment.plainText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                // Attachments are real: name, size, and an image-or-document glyph.
                if !comment.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(comment.attachments, id: \.fileName) { attachment in
                                attachmentChip(attachment)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func attachmentChip(_ attachment: CommentAttachment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.isImage ? "photo" : "doc")
                .font(.caption).foregroundStyle(feature)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.fileName).font(.caption2).lineLimit(1)
                Text(attachment.fileSizeFormatted).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        // ambient-allow: attachment chip, not a card — a labelled inline token
        // inside a comment, sized to its content rather than to the column.
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.05)))
    }

    // MARK: - Details
    //
    // Read-only this reads as facts; in edit mode the three editors the app has
    // always had come back — priority segmented, status menu, hours stepper.

    private var facts: some View {
        VStack(alignment: .leading, spacing: 0) {
            AmbientSectionTitle("Details").padding(.bottom, 6)

            // The three editors appear in edit mode; the facts that are not
            // editable stay on screen in BOTH modes. The first cut swapped the
            // whole card, which took "Created" off the screen the moment you
            // tapped Edit — the old four-tab detail rendered it in both modes.
            if isEditing {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Priority").font(.subheadline).foregroundStyle(.secondary)
                        Picker("Priority", selection: $editedTask.priority) {
                            ForEach(TaskPriority.allCases, id: \.self) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }

                    HStack {
                        Text("Status").font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Picker("Status", selection: $editedTask.status) {
                            ForEach(TaskStatus.allCases, id: \.self) { status in
                                Text(status.displayName).tag(status)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    Stepper(value: $editedTask.estimatedHours, in: 0...100, step: 0.5) {
                        HStack {
                            Text("Estimated").font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(editedTask.estimatedHours == 0
                                 ? "Not set"
                                 : String(format: "%.1fh", editedTask.estimatedHours))
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
                .padding(.vertical, 4)

                Divider().opacity(0.4)
                fact("Assigned to", assignedToText, "person.fill")
                Divider().opacity(0.4)
                fact("Created", createdText, "clock.arrow.circlepath")
            } else {
                fact("Assigned to", assignedToText, "person.fill")
                Divider().opacity(0.4)
                fact("Estimated",
                     editedTask.estimatedHours == 0
                        ? "Not set"
                        : String(format: "%.1f hours", editedTask.estimatedHours),
                     "hourglass")
                Divider().opacity(0.4)
                fact("Created", createdText, "clock.arrow.circlepath")
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func fact(_ label: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(.secondary).frame(width: 18)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }

    /// Names where they resolve, and the model's own wording where they do not —
    /// so this reads "Unassigned" or "3 assignees" rather than going blank.
    private var assignedToText: String {
        guard !editedTask.assignedTo.isEmpty else { return editedTask.assignmentDisplayText }
        let names = editedTask.assignedTo.compactMap { memberNames[$0.lowercased()] }
        guard let first = names.first else { return editedTask.assignmentDisplayText }
        if editedTask.assignedTo.count == 1 { return first }
        return "\(first) +\(editedTask.assignedTo.count - 1)"
    }

    private var createdText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: editedTask.createdAt)
    }

    // MARK: - Activity

    /// Still a stub, on purpose. It says "Activity feed coming soon" in the app,
    /// and TaskService carries eleven unimplemented TODOs for the activity log
    /// that would have to exist first — building one here would be proposing work
    /// nobody has costed.
    private var activity: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.footnote).foregroundStyle(.tertiary)
            Text("Activity feed coming soon")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, border: .dashed(Color.primary.opacity(0.2)),
                     fillWidth: true)
    }

    // MARK: - Actions

    private func saveChanges() {
        onTaskUpdated(editedTask)
        withAnimation(AmbientMotion.snappy) { isEditing = false }
    }

    /// Ticking a subtask.
    ///
    /// THE BUG THIS FIXES: the old screen's checkbox was not gated on edit mode
    /// and mutated the local copy, but only Save persisted that copy and Save only
    /// existed in edit mode — so a subtask ticked while just reading animated,
    /// moved the counter and the progress bar, and was thrown away on dismiss. The
    /// four-tab layout hid subtasks behind a tab; this screen puts them in front
    /// of everyone, which is what makes it unavoidable rather than optional.
    ///
    /// IT GOES THROUGH TaskService.toggleSubtask, NOT THROUGH onTaskUpdated, and
    /// that distinction is the whole point. onTaskUpdated writes the ENTIRE task
    /// row from `editedTask` — a snapshot taken when the sheet opened — so using it
    /// for a casual checkbox tap would silently revert any title, status, priority
    /// or assignee change somebody else made in the meantime, on a database shared
    /// with the web app. toggleSubtask re-reads the row, flips that one subtask,
    /// and writes that; it also sets completedAt and completedBy, which the old
    /// inline toggle never did.
    ///
    /// In EDIT mode it stays local, because that is what Edit and Save mean.
    private func toggleSubtask(_ id: String) {
        guard let index = editedTask.subtasks.firstIndex(where: { $0.id == id }) else { return }

        let wasCompleted = editedTask.subtasks[index].completed
        applyToggle(at: index, completed: !wasCompleted)
        AmbientHaptics.impact(.light)

        guard !isEditing else { return }

        // Optimistically flipped above so the checkbox answers immediately; put it
        // back if the write fails, rather than showing a tick that never landed.
        Task { @MainActor in
            do {
                try await TaskService.shared.toggleSubtask(taskId: task.id,
                                                          subtaskId: id,
                                                          userId: currentUserId)
            } catch {
                if let index = editedTask.subtasks.firstIndex(where: { $0.id == id }) {
                    applyToggle(at: index, completed: wasCompleted)
                }
            }
        }
    }

    private func applyToggle(at index: Int, completed: Bool) {
        editedTask.subtasks[index].completed = completed
        if completed {
            editedTask.subtasks[index].completedAt = Date()
            editedTask.subtasks[index].completedBy = currentUserId
        } else {
            editedTask.subtasks[index].completedAt = nil
            editedTask.subtasks[index].completedBy = nil
        }
    }

    private func addSubtask(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editedTask.subtasks.append(Subtask(title: trimmed))
    }

    private func deleteSubtask(_ id: String) {
        editedTask.subtasks.removeAll { $0.id == id }
    }

    private func sendComment() {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingComment else { return }

        isSendingComment = true
        // @MainActor because the body writes @State (isSendingComment,
        // newCommentText). A bare Task{} here inherits no actor and would be
        // touching view state off the main thread.
        Task { @MainActor in
            defer { isSendingComment = false }
            do {
                try await commentService.addComment(
                    to: task.id,
                    text: text,
                    userId: currentUserId,
                    userName: currentUserName
                )
                newCommentText = ""
            } catch {
                print("❌ Failed to add comment: \(error.localizedDescription)")
            }
        }
    }

    private func loadMemberNames() {
        let orgId = UserManager.shared.getCachedOrganizationID()
        guard !orgId.isEmpty, memberNames.isEmpty else { return }

        // @MainActor: the body assigns to the memberNames @State.
        Task { @MainActor in
            do {
                let members = try await TeamService.shared.getTeamMembers(organizationID: orgId)
                var names: [String: String] = [:]
                for member in members {
                    names[member.id.lowercased()] = member.fullName
                }
                memberNames = names
            } catch {
                // The assigned-to line falls back to assignmentDisplayText, so a
                // failed name lookup costs wording, not information.
            }
        }
    }
}

// MARK: - Subtask composer

/// The add-a-subtask field, split out so its draft text is local state rather
/// than another @State on the detail — the old screen kept it on the tab view for
/// the same reason.
private struct SubtaskComposer: View {
    let onAdd: (String) -> Void
    @State private var title = ""

    var body: some View {
        HStack(spacing: 8) {
            // A Button, not a glyph. The old screen's plus was tappable and
            // disabled when empty; drawing it as decoration would have left the
            // most obvious-looking target inert.
            Button(action: add) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(title.isEmpty ? AnyShapeStyle(.tertiary)
                                                   : AnyShapeStyle(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(title.isEmpty)
            .accessibilityLabel("Add subtask")

            TextField("Add a subtask", text: $title)
                .font(.subheadline)
                .onSubmit(add)
        }
        .padding(.vertical, 4)
    }

    private func add() {
        onAdd(title)
        title = ""
    }
}

// MARK: - HTML

extension AttributedString {
    init(html htmlString: String) {
        // Strip HTML tags and decode entities for plain text display
        let cleanedString = htmlString
            .replacingOccurrences(of: "<p>", with: "")
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.init(cleanedString)
    }
}
