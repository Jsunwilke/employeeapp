//
//  TasksMainView.swift
//  Iconik Employee
//
//  Main view for Task Management System
//  Implements cache-first loading with real-time updates
//

import SwiftUI

struct TasksMainView: View {
    @StateObject private var viewModel = TasksViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: TaskFilter = .myTasks
    @State private var selectedStatus: TaskStatus? = nil
    @State private var selectedPriority: TaskPriority? = nil
    @State private var showingCreateTask = false
    @State private var selectedTask: TaskItem? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                SearchBar(text: $searchText)
                    .padding()

                // Filter Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(TaskFilter.allCases, id: \.self) { filter in
                            TaskFilterChip(
                                title: filter.displayName,
                                count: viewModel.taskCount(for: filter),
                                isSelected: selectedFilter == filter
                            ) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)

                // Status Filter (if not "all")
                if selectedFilter != .all {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text("Status:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach([nil] + TaskStatus.allCases.map { $0 as TaskStatus? }, id: \.self) { status in
                                StatusChip(
                                    status: status,
                                    isSelected: selectedStatus == status
                                ) {
                                    selectedStatus = status
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                }

                // Task List
                if viewModel.isLoading && viewModel.tasks.isEmpty {
                    LoadingView()
                } else if viewModel.filteredTasks(
                    searchText: searchText,
                    filter: selectedFilter,
                    status: selectedStatus,
                    priority: selectedPriority
                ).isEmpty {
                    EmptyTasksView(filter: selectedFilter)
                } else {
                    TaskListView(
                        tasks: viewModel.filteredTasks(
                            searchText: searchText,
                            filter: selectedFilter,
                            status: selectedStatus,
                            priority: selectedPriority
                        ),
                        onTaskTap: { task in
                            selectedTask = task
                        },
                        onToggleComplete: { task in
                            viewModel.toggleTaskCompletion(task)
                        }
                    )
                }
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HomeToolbarButton()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingCreateTask = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: {
                            viewModel.refreshTasks()
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button(action: {
                            // Clear cache and reload
                            viewModel.clearCacheAndReload()
                        }) {
                            Label("Clear Cache", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
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
    }
}

// MARK: - Task Filter Enum

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
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search tasks...", text: $text)
                .textFieldStyle(PlainTextFieldStyle())

            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Task Filter Chip

struct TaskFilterChip: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)

                if let count = count, count > 0 {
                    Text("(\(count))")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

// MARK: - Status Chip

struct StatusChip: View {
    let status: TaskStatus?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(status?.displayName ?? "All")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? statusColor : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
    }

    private var statusColor: Color {
        guard let status = status else { return .blue }
        switch status {
        case .todo: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        }
    }
}

// MARK: - Task List View

struct TaskListView: View {
    let tasks: [TaskItem]
    let onTaskTap: (TaskItem) -> Void
    let onToggleComplete: (TaskItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(tasks) { task in
                    TaskRowView(task: task, onTap: {
                        onTaskTap(task)
                    }, onToggleComplete: {
                        onToggleComplete(task)
                    })
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()
                }
            }
        }
    }
}

// MARK: - Task Row View

struct TaskRowView: View {
    let task: TaskItem
    let onTap: () -> Void
    let onToggleComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggleComplete) {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(task.status == .completed ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Priority indicator + Title
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(priorityColor)
                        .frame(width: 3, height: 16)

                    Text(task.title)
                        .font(.body)
                        .strikethrough(task.status == .completed)
                        .lineLimit(2)
                }

                // Metadata row
                HStack(spacing: 12) {
                    // Status badge
                    Text(task.status.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.2))
                        .foregroundColor(statusColor)
                        .cornerRadius(4)

                    // Due date
                    if let dueDate = task.dueDate {
                        Label(
                            relativeDateString(from: dueDate),
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundColor(task.isOverdue ? .red : .secondary)
                    }

                    // Subtasks progress
                    if !task.subtasks.isEmpty {
                        let completed = task.subtasks.filter { $0.completed }.count
                        Label("\(completed)/\(task.subtasks.count)", systemImage: "checklist")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Comments count
                    if task.commentCount > 0 {
                        Label("\(task.commentCount)", systemImage: "bubble.left")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Priority badge (for urgent/high only)
            if task.priority == .urgent || task.priority == .high {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(priorityColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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

    private func relativeDateString(from date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Empty View

struct EmptyTasksView: View {
    let filter: TaskFilter

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyIcon)
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text(emptyMessage)
                .font(.title3)
                .foregroundColor(.secondary)

            Text(emptySubtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyIcon: String {
        switch filter {
        case .all: return "tray"
        case .myTasks: return "person.crop.circle"
        case .today: return "calendar"
        case .urgent: return "exclamationmark.triangle"
        case .completed: return "checkmark.circle"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all: return "No tasks yet"
        case .myTasks: return "No tasks assigned to you"
        case .today: return "No tasks due today"
        case .urgent: return "No urgent tasks"
        case .completed: return "No completed tasks"
        }
    }

    private var emptySubtitle: String {
        switch filter {
        case .all: return "Tap + to create your first task"
        case .myTasks: return "You're all caught up!"
        case .today: return "You're all caught up for today!"
        case .urgent: return "Great! No urgent tasks require attention."
        case .completed: return "Complete tasks to see them here"
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading tasks...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
