//
//  TaskService.swift
//  Iconik Employee
//
//  Service layer for Task Management System
//  Handles all Supabase operations for tasks
//

import Foundation
import Supabase
import Combine

@MainActor
class TaskService: ObservableObject {
    static let shared = TaskService()

    private let supabase = SupabaseManager.shared.client
    private let tasksTable = "tasks"

    @Published var tasks: [TaskItem] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var channels: [String: RealtimeChannelV2] = [:]

    private init() {}

    // MARK: - Create Task

    /// Create a new task in Supabase
    func createTask(_ task: TaskItem) async throws -> TaskItem {
        var taskToCreate = task

        // Calculate sortOrder for new task (append to end of status column)
        let existingTasks = try await fetchTasks(organizationID: task.organizationID, status: task.status)
        let maxOrder = existingTasks.map { $0.sortOrder }.max() ?? -1
        taskToCreate.sortOrder = maxOrder + 1

        // Set timestamps
        taskToCreate.createdAt = Date()
        taskToCreate.updatedAt = Date()

        // Auto-watch creator
        if !taskToCreate.watchers.contains(taskToCreate.createdBy) {
            taskToCreate.watchers.append(taskToCreate.createdBy)
        }

        // Insert into Supabase
        try await supabase
            .from(tasksTable)
            .insert(taskToCreate)
            .execute()

        // Add to local state
        tasks.append(taskToCreate)

        // TODO: Log activity (TASK_CREATED)
        // TODO: Send notifications to assignees

        return taskToCreate
    }

    // MARK: - Read Tasks

    /// Fetch a single task by ID
    func getTask(id: String) async throws -> TaskItem {
        let tasks: [TaskItem] = try await supabase
            .from(tasksTable)
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        guard let task = tasks.first else {
            throw NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }

        return task
    }

    /// Fetch tasks for an organization
    func fetchTasks(organizationID: String) async throws -> [TaskItem] {
        isLoading = true
        defer { isLoading = false }

        let fetchedTasks: [TaskItem] = try await supabase
            .from(tasksTable)
            .select()
            .eq("organization_id", value: organizationID)
            .order("updated_at", ascending: false)
            .execute()
            .value

        tasks = fetchedTasks
        return fetchedTasks
    }

    /// Fetch tasks for an organization with specific status
    func fetchTasks(organizationID: String, status: TaskStatus) async throws -> [TaskItem] {
        let fetchedTasks: [TaskItem] = try await supabase
            .from(tasksTable)
            .select()
            .eq("organization_id", value: organizationID)
            .eq("status", value: status.rawValue)
            .order("sort_order", ascending: true)
            .execute()
            .value

        return fetchedTasks
    }

    /// Fetch tasks assigned to a specific user
    func fetchTasksAssignedTo(userId: String, organizationID: String) async throws -> [TaskItem] {
        let fetchedTasks: [TaskItem] = try await supabase
            .from(tasksTable)
            .select()
            .eq("organization_id", value: organizationID)
            .contains("assigned_to", value: [userId])
            .order("updated_at", ascending: false)
            .execute()
            .value

        return fetchedTasks
    }

    /// Fetch tasks created by a specific user
    func fetchTasksCreatedBy(userId: String, organizationID: String) async throws -> [TaskItem] {
        let fetchedTasks: [TaskItem] = try await supabase
            .from(tasksTable)
            .select()
            .eq("organization_id", value: organizationID)
            .eq("created_by", value: userId)
            .order("updated_at", ascending: false)
            .execute()
            .value

        return fetchedTasks
    }

    // MARK: - Real-time Listener

    /// Start listening to tasks for an organization
    func startListening(organizationID: String) {
        // Remove existing listener if any
        stopListening()

        let channelKey = "tasks-\(organizationID)"
        let channel = supabase.realtimeV2.channel(channelKey)

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: tasksTable,
            filter: "organization_id=eq.\(organizationID)"
        )

        channels["main"] = channel

        Task {
            await channel.subscribe()

            // Initial fetch
            do {
                let fetchedTasks = try await fetchTasks(organizationID: organizationID)
                await MainActor.run {
                    self.tasks = fetchedTasks
                }
            } catch {
                // Handle error silently or log if needed
            }

            // Listen for changes
            Task {
                for await _ in changes {
                    do {
                        let fetchedTasks = try await self.fetchTasks(organizationID: organizationID)
                        await MainActor.run {
                            self.tasks = fetchedTasks
                        }
                    } catch {
                        await MainActor.run {
                            self.error = error
                        }
                    }
                }
            }
        }
    }

    /// Stop listening to real-time updates
    func stopListening() {
        for (_, channel) in channels {
            Task {
                await channel.unsubscribe()
            }
        }
        channels.removeAll()
    }

    // MARK: - Update Task

    /// Update a task with partial changes
    /// Note: For Supabase, we need to pass a properly typed Encodable struct for updates
    /// Callers should use the full updateTask(_ task:) method instead
    private func updateTaskFields(id: String, updates: [String: Any]) async throws {
        // This is a temporary helper - most callers should be migrated to use updateTask(_ task:)
        // For now, fetch the task, apply changes, and update
        var task = try await getTask(id: id)

        // Apply updates to task (this is a simplified approach)
        // In production, you'd want proper field mapping
        task.updatedAt = Date()

        try await updateTask(task)
    }

    /// Update entire task
    func updateTask(_ task: TaskItem) async throws {
        var updatedTask = task
        updatedTask.updatedAt = Date()

        try await supabase
            .from(tasksTable)
            .update(updatedTask)
            .eq("id", value: task.id)
            .execute()

        // Update local state
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = updatedTask
        }
    }

    // MARK: - Complete/Reopen Task

    /// Mark task as completed
    func completeTask(id: String, userId: String) async throws {
        var task = try await getTask(id: id)
        task.status = .completed
        task.completedAt = Date()
        task.completedBy = userId

        try await updateTask(task)

        // TODO: Auto-stop time tracking
        // TODO: Log activity (TASK_COMPLETED)
        // TODO: Notify watchers
    }

    /// Reopen a completed task
    func reopenTask(id: String) async throws {
        var task = try await getTask(id: id)
        task.status = .todo
        task.completedAt = nil
        task.completedBy = nil

        try await updateTask(task)

        // TODO: Log activity (TASK_REOPENED)
    }

    // MARK: - Delete Task

    /// Delete a task
    func deleteTask(id: String) async throws {
        // TODO: Check permissions before deleting

        try await supabase
            .from(tasksTable)
            .delete()
            .eq("id", value: id)
            .execute()

        // Remove from local state
        tasks.removeAll { $0.id == id }

        // TODO: Delete comments subcollection
        // TODO: Delete activity entries
        // TODO: Delete attachments from storage
        // TODO: Remove time entry references
    }

    // MARK: - Subtasks

    /// Add a subtask to a task
    func addSubtask(to taskId: String, title: String) async throws {
        let newSubtask = Subtask(id: UUID().uuidString, title: title)
        var task = try await getTask(id: taskId)
        task.subtasks.append(newSubtask)
        try await updateTask(task)
    }

    /// Toggle subtask completion
    func toggleSubtask(taskId: String, subtaskId: String, userId: String) async throws {
        var task = try await getTask(id: taskId)

        guard let index = task.subtasks.firstIndex(where: { $0.id == subtaskId }) else {
            throw NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Subtask not found"])
        }

        task.subtasks[index].completed.toggle()

        if task.subtasks[index].completed {
            task.subtasks[index].completedAt = Date()
            task.subtasks[index].completedBy = userId
            // TODO: Log activity (SUBTASK_COMPLETED)
        } else {
            task.subtasks[index].completedAt = nil
            task.subtasks[index].completedBy = nil
            // TODO: Log activity (SUBTASK_UNCOMPLETED)
        }

        try await updateTask(task)
    }

    /// Delete a subtask
    func deleteSubtask(taskId: String, subtaskId: String) async throws {
        var task = try await getTask(id: taskId)
        task.subtasks.removeAll { $0.id == subtaskId }
        try await updateTask(task)
    }

    // MARK: - Watchers

    /// Add a watcher to a task
    func addWatcher(taskId: String, userId: String) async throws {
        var task = try await getTask(id: taskId)
        if !task.watchers.contains(userId) {
            task.watchers.append(userId)
            try await updateTask(task)
        }
    }

    /// Remove a watcher from a task
    func removeWatcher(taskId: String, userId: String) async throws {
        var task = try await getTask(id: taskId)
        task.watchers.removeAll { $0 == userId }
        try await updateTask(task)
    }

    /// Toggle watch status for current user
    func toggleWatch(taskId: String, userId: String) async throws {
        let task = try await getTask(id: taskId)
        if task.watchers.contains(userId) {
            try await removeWatcher(taskId: taskId, userId: userId)
        } else {
            try await addWatcher(taskId: taskId, userId: userId)
        }
    }

    // MARK: - Assignment

    /// Add assignee to task
    func addAssignee(taskId: String, userId: String) async throws {
        var task = try await getTask(id: taskId)
        if !task.assignedTo.contains(userId) {
            task.assignedTo.append(userId)
            try await updateTask(task)
        }
        // TODO: Auto-add to watchers
        // TODO: Send notification (ASSIGNEE_ADDED)
        // TODO: Log activity
    }

    /// Remove assignee from task
    func removeAssignee(taskId: String, userId: String) async throws {
        var task = try await getTask(id: taskId)
        task.assignedTo.removeAll { $0 == userId }
        try await updateTask(task)
        // TODO: Send notification (ASSIGNEE_REMOVED)
        // TODO: Log activity
    }

    // MARK: - Reordering (Drag-and-Drop)

    /// Batch update task orders
    func batchUpdateTaskOrders(_ updates: [(taskId: String, newOrder: Int)]) async throws {
        // Supabase doesn't have batch writes, so we update each task individually
        // For better performance, we could use a stored procedure or parallel updates
        for update in updates {
            var task = try await getTask(id: update.taskId)
            task.sortOrder = update.newOrder
            task.updatedAt = Date()

            try await supabase
                .from(tasksTable)
                .update(task)
                .eq("id", value: update.taskId)
                .execute()

            // Update local state
            if let index = tasks.firstIndex(where: { $0.id == update.taskId }) {
                tasks[index].sortOrder = update.newOrder
            }
        }
    }

    /// Reorder task within same status
    func reorderTask(taskId: String, from sourceIndex: Int, to destinationIndex: Int, status: TaskStatus) async throws {
        // Get all tasks with this status
        var statusTasks = tasks.filter { $0.status == status }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard sourceIndex < statusTasks.count else {
            throw NSError(domain: "TaskService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid source index"])
        }

        // Remove task from source
        let movedTask = statusTasks.remove(at: sourceIndex)

        // Insert at destination
        let safeDestination = min(destinationIndex, statusTasks.count)
        statusTasks.insert(movedTask, at: safeDestination)

        // Recalculate order for all affected tasks
        let updates = statusTasks.enumerated().map { index, task in
            (taskId: task.id, newOrder: index)
        }

        // Batch update Supabase
        try await batchUpdateTaskOrders(updates)
    }

    /// Move task to different status
    func moveTask(taskId: String, to newStatus: TaskStatus, at index: Int) async throws {
        // Update status first
        var task = try await getTask(id: taskId)
        task.status = newStatus
        try await updateTask(task)

        // Then reorder within new status
        try await reorderTask(taskId: taskId, from: 0, to: index, status: newStatus)
    }

    // MARK: - Debug Helper

    /// Diagnostic method to debug why tasks aren't loading
}
