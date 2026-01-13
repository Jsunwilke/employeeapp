//
//  TaskDetailView.swift
//  Iconik Employee
//
//  Detailed view for viewing and editing a task
//

import SwiftUI

struct TaskDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    let task: TaskItem
    let onTaskUpdated: (TaskItem) -> Void

    @State private var selectedTab: DetailTab = .details
    @State private var isEditing = false
    @State private var editedTask: TaskItem

    // Comment state
    @StateObject private var commentService = CommentService.shared
    @State private var newCommentText = ""

    init(task: TaskItem, onTaskUpdated: @escaping (TaskItem) -> Void) {
        self.task = task
        self.onTaskUpdated = onTaskUpdated
        self._editedTask = State(initialValue: task)
    }

    private var currentUserId: String {
        return UserManager.shared.getCurrentUserIDUnified() ?? ""
    }

    private var currentUserName: String {
        let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? "Unknown User" : fullName
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                TaskDetailHeaderView(task: editedTask, isEditing: $isEditing, currentUserId: currentUserId)
                    .padding()

                // Tab Selector
                Picker("Tab", selection: $selectedTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                // Tab Content
                ScrollView {
                    switch selectedTab {
                    case .details:
                        TaskDetailsTabView(task: $editedTask, isEditing: isEditing)
                    case .subtasks:
                        SubtasksTabView(task: $editedTask, isEditing: isEditing)
                    case .comments:
                        CommentsTabView(
                            comments: commentService.comments,
                            newCommentText: $newCommentText,
                            onSendComment: sendComment
                        )
                    case .activity:
                        ActivityTabView(task: editedTask)
                    }
                }
            }
            .navigationTitle(editedTask.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            saveChanges()
                        }
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
            }
            .onAppear {
                // Load comments when view appears
                Task {
                    try? await commentService.fetchComments(for: task.id)
                }
            }
            .onDisappear {
                commentService.stopListening(taskId: task.id)
            }
        }
    }

    private func saveChanges() {
        onTaskUpdated(editedTask)
        isEditing = false
    }

    private func sendComment() {
        guard !newCommentText.isEmpty else { return }

        Task {
            do {
                try await commentService.addComment(
                    to: task.id,
                    text: newCommentText,
                    userId: currentUserId,
                    userName: currentUserName
                )
                newCommentText = ""
            } catch {
                print("❌ Failed to add comment: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Detail Tab Enum

enum DetailTab: String, CaseIterable {
    case details = "Details"
    case subtasks = "Subtasks"
    case comments = "Comments"
    case activity = "Activity"
}

// MARK: - Header View

struct TaskDetailHeaderView: View {
    let task: TaskItem
    @Binding var isEditing: Bool
    let currentUserId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Priority and Status Badges
            HStack(spacing: 8) {
                // Priority badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(priorityColor)
                        .frame(width: 8, height: 8)
                    Text(task.priority.displayName)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(priorityColor.opacity(0.2))
                .cornerRadius(12)

                // Status badge
                Text(task.status.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.2))
                    .foregroundColor(statusColor)
                    .cornerRadius(12)

                Spacer()

                // Watch button
                Button(action: {
                    // TODO: Toggle watch
                }) {
                    Image(systemName: task.isWatchedBy(userId: currentUserId) ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                }
            }

            // Due date (if exists)
            if let dueDate = task.dueDate {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(task.isOverdue ? .red : .secondary)
                    Text("Due \(dueDate, style: .date)")
                        .font(.subheadline)
                        .foregroundColor(task.isOverdue ? .red : .secondary)
                }
            }

            // Subtask progress (if exists)
            if !task.subtasks.isEmpty {
                let completed = task.subtasks.filter { $0.completed }.count
                let total = task.subtasks.count

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(completed)/\(total) subtasks completed")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(Int(task.subtaskProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: task.subtaskProgress)
                        .tint(task.subtaskProgress == 1.0 ? .green : .blue)
                }
            }
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .todo: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        }
    }
}

// MARK: - Details Tab

struct TaskDetailsTabView: View {
    @Binding var task: TaskItem
    let isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Description
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)

                if isEditing {
                    TextEditor(text: Binding(
                        get: { task.description ?? "" },
                        set: { task.description = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                } else {
                    Text(task.description ?? "No description")
                        .foregroundColor(task.description == nil ? .secondary : .primary)
                }
            }

            Divider()

            // Priority
            VStack(alignment: .leading, spacing: 8) {
                Text("Priority")
                    .font(.headline)

                if isEditing {
                    Picker("Priority", selection: $task.priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                } else {
                    Text(task.priority.displayName)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Status
            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.headline)

                if isEditing {
                    Picker("Status", selection: $task.status) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                } else {
                    Text(task.status.displayName)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Estimation
            VStack(alignment: .leading, spacing: 8) {
                Text("Estimated Hours")
                    .font(.headline)

                if isEditing {
                    Stepper(value: $task.estimatedHours, in: 0...100, step: 0.5) {
                        Text(task.estimatedHours == 0 ? "Not set" : "\(task.estimatedHours, specifier: "%.1f")h")
                    }
                } else {
                    Text(task.estimatedHours == 0 ? "Not set" : "\(task.estimatedHours, specifier: "%.1f") hours")
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Created info
            VStack(alignment: .leading, spacing: 4) {
                Text("Created")
                    .font(.headline)

                Text("\(task.createdAt, style: .date) at \(task.createdAt, style: .time)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Subtasks Tab

struct SubtasksTabView: View {
    @Binding var task: TaskItem
    let isEditing: Bool
    @State private var newSubtaskTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            // Add subtask (if editing)
            if isEditing {
                HStack {
                    TextField("New subtask", text: $newSubtaskTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button(action: addSubtask) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(newSubtaskTitle.isEmpty)
                }
                .padding()
            }

            // Subtask list
            if task.subtasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)

                    Text("No subtasks yet")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                ForEach($task.subtasks) { $subtask in
                    HStack(spacing: 12) {
                        Button(action: {
                            subtask.completed.toggle()
                        }) {
                            Image(systemName: subtask.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(subtask.completed ? .green : .gray)
                        }

                        Text(subtask.title)
                            .strikethrough(subtask.completed)

                        Spacer()

                        if isEditing {
                            Button(action: {
                                deleteSubtask(subtask)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))

                    Divider()
                }
            }
        }
    }

    private func addSubtask() {
        let newSubtask = Subtask(title: newSubtaskTitle)
        task.subtasks.append(newSubtask)
        newSubtaskTitle = ""
    }

    private func deleteSubtask(_ subtask: Subtask) {
        task.subtasks.removeAll { $0.id == subtask.id }
    }
}

// MARK: - Comments Tab

struct CommentsTabView: View {
    let comments: [TaskComment]
    @Binding var newCommentText: String
    let onSendComment: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Comment input
            HStack(spacing: 8) {
                TextField("Add a comment...", text: $newCommentText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: onSendComment) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .disabled(newCommentText.isEmpty)
            }
            .padding()

            Divider()

            // Comments list
            if comments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)

                    Text("No comments yet")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                ForEach(comments) { comment in
                    CommentRowView(comment: comment)
                    Divider()
                }
            }
        }
    }
}

struct CommentRowView: View {
    let comment: TaskComment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(comment.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(comment.timeAgoText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(comment.plainText)
                .font(.body)

            if !comment.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(comment.attachments, id: \.fileName) { attachment in
                            AttachmentBadge(attachment: attachment)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct AttachmentBadge: View {
    let attachment: CommentAttachment

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.isImage ? "photo" : "doc")
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption)
                    .lineLimit(1)

                Text(attachment.fileSizeFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Activity Tab

struct ActivityTabView: View {
    let task: TaskItem

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("Activity feed coming soon")
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
