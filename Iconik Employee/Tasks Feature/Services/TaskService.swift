//
//  TaskService.swift
//  Iconik Employee
//
//  Service layer for Task Management System
//  Handles all Firestore operations for tasks
//

import Foundation
import FirebaseFirestore
import Combine

class TaskService: ObservableObject {
    static let shared = TaskService()

    private let db = Firestore.firestore()
    private let tasksCollection = "tasks"

    @Published var tasks: [TaskItem] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var listeners: [String: ListenerRegistration] = [:]

    private init() {}

    // MARK: - Create Task

    /// Create a new task in Firestore
    func createTask(_ task: TaskItem, completion: @escaping (Result<TaskItem, Error>) -> Void) {
        var taskToCreate = task

        // Calculate order for new task (append to end of status column)
        fetchTasks(organizationID: task.organizationID, status: task.status) { [weak self] (result: Result<[TaskItem], Error>) in
            guard let self = self else { return }

            switch result {
            case .success(let existingTasks):
                let maxOrder = existingTasks.map { $0.order }.max() ?? -1
                taskToCreate.order = maxOrder + 1

                // Set timestamps
                taskToCreate.createdAt = Date()
                taskToCreate.updatedAt = Date()

                // Auto-watch creator
                if !taskToCreate.watchers.contains(taskToCreate.createdBy) {
                    taskToCreate.watchers.append(taskToCreate.createdBy)
                }

                // Create document in Firestore
                let docRef = self.db.collection(self.tasksCollection).document(taskToCreate.id)
                docRef.setData(taskToCreate.toFirestoreData()) { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        // Add to local state
                        self.tasks.append(taskToCreate)
                        completion(.success(taskToCreate))

                        // TODO: Log activity (TASK_CREATED)
                        // TODO: Send notifications to assignees
                    }
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Read Tasks

    /// Fetch a single task by ID
    func getTask(id: String, completion: @escaping (Result<TaskItem, Error>) -> Void) {
        db.collection(tasksCollection).document(id).getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let snapshot = snapshot, snapshot.exists else {
                completion(.failure(NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task not found"])))
                return
            }

            if let task = TaskItem(from: snapshot) {
                completion(.success(task))
            } else {
                completion(.failure(NSError(domain: "TaskService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse task"])))
            }
        }
    }

    /// Fetch tasks for an organization
    func fetchTasks(organizationID: String, completion: @escaping (Result<[TaskItem], Error>) -> Void) {
        isLoading = true

        db.collection(tasksCollection)
            .whereField("organizationID", isEqualTo: organizationID)
            .order(by: "updatedAt", descending: true)
            .getDocuments { [weak self] snapshot, error in
                self?.isLoading = false

                if let error = error {
                    self?.error = error
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let tasks = documents.compactMap { TaskItem(from: $0) }
                self?.tasks = tasks
                completion(.success(tasks))
            }
    }

    /// Fetch tasks for an organization with specific status
    func fetchTasks(organizationID: String, status: TaskStatus, completion: @escaping (Result<[TaskItem], Error>) -> Void) {
        db.collection(tasksCollection)
            .whereField("organizationID", isEqualTo: organizationID)
            .whereField("status", isEqualTo: status.rawValue)
            .order(by: "order", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let tasks = documents.compactMap { TaskItem(from: $0) }
                completion(.success(tasks))
            }
    }

    /// Fetch tasks assigned to a specific user
    func fetchTasksAssignedTo(userId: String, organizationID: String, completion: @escaping (Result<[TaskItem], Error>) -> Void) {
        db.collection(tasksCollection)
            .whereField("organizationID", isEqualTo: organizationID)
            .whereField("assignedTo", arrayContains: userId)
            .order(by: "updatedAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let tasks = documents.compactMap { TaskItem(from: $0) }
                completion(.success(tasks))
            }
    }

    /// Fetch tasks created by a specific user
    func fetchTasksCreatedBy(userId: String, organizationID: String, completion: @escaping (Result<[TaskItem], Error>) -> Void) {
        db.collection(tasksCollection)
            .whereField("organizationID", isEqualTo: organizationID)
            .whereField("createdBy", isEqualTo: userId)
            .order(by: "updatedAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                let tasks = documents.compactMap { TaskItem(from: $0) }
                completion(.success(tasks))
            }
    }

    // MARK: - Real-time Listener

    /// Start listening to tasks for an organization
    func startListening(organizationID: String) {
        // Remove existing listener if any
        stopListening()

        let listener = db.collection(tasksCollection)
            .whereField("organizationID", isEqualTo: organizationID)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Task listener error: \(error.localizedDescription)")
                    self?.error = error
                    return
                }

                guard let documents = snapshot?.documents else { return }

                let tasks = documents.compactMap { TaskItem(from: $0) }
                self?.tasks = tasks
            }

        listeners["main"] = listener
    }

    /// Stop listening to real-time updates
    func stopListening() {
        for (_, listener) in listeners {
            listener.remove()
        }
        listeners.removeAll()
    }

    // MARK: - Update Task

    /// Update a task with partial changes
    func updateTask(id: String, updates: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        var finalUpdates = updates
        finalUpdates["updatedAt"] = Timestamp(date: Date())

        db.collection(tasksCollection).document(id).updateData(finalUpdates) { [weak self] error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // Update local state
            if let index = self?.tasks.firstIndex(where: { $0.id == id }) {
                self?.getTask(id: id) { result in
                    if case .success(let updatedTask) = result {
                        self?.tasks[index] = updatedTask
                    }
                }
            }

            completion(.success(()))
        }
    }

    /// Update entire task
    func updateTask(_ task: TaskItem, completion: @escaping (Result<Void, Error>) -> Void) {
        var updatedTask = task
        updatedTask.updatedAt = Date()

        db.collection(tasksCollection).document(task.id).setData(updatedTask.toFirestoreData(), merge: true) { [weak self] error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // Update local state
            if let index = self?.tasks.firstIndex(where: { $0.id == task.id }) {
                self?.tasks[index] = updatedTask
            }

            completion(.success(()))
        }
    }

    // MARK: - Complete/Reopen Task

    /// Mark task as completed
    func completeTask(id: String, userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        updateTask(id: id, updates: [
            "status": TaskStatus.completed.rawValue,
            "completedAt": Timestamp(date: Date()),
            "completedBy": userId
        ]) { result in
            // TODO: Auto-stop time tracking
            // TODO: Log activity (TASK_COMPLETED)
            // TODO: Notify watchers
            completion(result)
        }
    }

    /// Reopen a completed task
    func reopenTask(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        updateTask(id: id, updates: [
            "status": TaskStatus.todo.rawValue,
            "completedAt": FieldValue.delete(),
            "completedBy": FieldValue.delete()
        ]) { result in
            // TODO: Log activity (TASK_REOPENED)
            completion(result)
        }
    }

    // MARK: - Delete Task

    /// Delete a task
    func deleteTask(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // TODO: Check permissions before deleting

        db.collection(tasksCollection).document(id).delete { [weak self] error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // Remove from local state
            self?.tasks.removeAll { $0.id == id }

            // TODO: Delete comments subcollection
            // TODO: Delete activity entries
            // TODO: Delete attachments from storage
            // TODO: Remove time entry references

            completion(.success(()))
        }
    }

    // MARK: - Subtasks

    /// Add a subtask to a task
    func addSubtask(to taskId: String, title: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let newSubtask = Subtask(id: UUID().uuidString, title: title)

        getTask(id: taskId) { [weak self] (result: Result<TaskItem, Error>) in
            switch result {
            case .success(var task):
                task.subtasks.append(newSubtask)
                self?.updateTask(task, completion: completion)

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Toggle subtask completion
    func toggleSubtask(taskId: String, subtaskId: String, userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        getTask(id: taskId) { [weak self] (result: Result<TaskItem, Error>) in
            switch result {
            case .success(var task):
                if let index = task.subtasks.firstIndex(where: { $0.id == subtaskId }) {
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

                    self?.updateTask(task, completion: completion)
                } else {
                    completion(.failure(NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Subtask not found"])))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Delete a subtask
    func deleteSubtask(taskId: String, subtaskId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        getTask(id: taskId) { [weak self] (result: Result<TaskItem, Error>) in
            switch result {
            case .success(var task):
                task.subtasks.removeAll { $0.id == subtaskId }
                self?.updateTask(task, completion: completion)

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Watchers

    /// Add a watcher to a task
    func addWatcher(taskId: String, userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        updateTask(id: taskId, updates: [
            "watchers": FieldValue.arrayUnion([userId])
        ], completion: completion)
    }

    /// Remove a watcher from a task
    func removeWatcher(taskId: String, userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        updateTask(id: taskId, updates: [
            "watchers": FieldValue.arrayRemove([userId])
        ], completion: completion)
    }

    /// Toggle watch status for current user
    func toggleWatch(taskId: String, userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        getTask(id: taskId) { [weak self] (result: Result<TaskItem, Error>) in
            switch result {
            case .success(let task):
                if task.watchers.contains(userId) {
                    self?.removeWatcher(taskId: taskId, userId: userId, completion: completion)
                } else {
                    self?.addWatcher(taskId: taskId, userId: userId, completion: completion)
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Assignment

    /// Add assignee to task
    func addAssignee(taskId: String, userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        updateTask(id: taskId, updates: [
            "assignedTo": FieldValue.arrayUnion([userId])
        ]) { result in
            // TODO: Auto-add to watchers
            // TODO: Send notification (ASSIGNEE_ADDED)
            // TODO: Log activity
            completion(result)
        }
    }

    /// Remove assignee from task
    func removeAssignee(taskId: String, userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        updateTask(id: taskId, updates: [
            "assignedTo": FieldValue.arrayRemove([userId])
        ]) { result in
            // TODO: Send notification (ASSIGNEE_REMOVED)
            // TODO: Log activity
            completion(result)
        }
    }

    // MARK: - Reordering (Drag-and-Drop)

    /// Batch update task orders
    func batchUpdateTaskOrders(_ updates: [(taskId: String, newOrder: Int)], completion: @escaping (Result<Void, Error>) -> Void) {
        let batch = db.batch()

        for update in updates {
            let ref = db.collection(tasksCollection).document(update.taskId)
            batch.updateData([
                "order": update.newOrder,
                "updatedAt": Timestamp(date: Date())
            ], forDocument: ref)
        }

        batch.commit { [weak self] error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // Update local state
            for update in updates {
                if let index = self?.tasks.firstIndex(where: { $0.id == update.taskId }) {
                    self?.tasks[index].order = update.newOrder
                }
            }

            completion(.success(()))
        }
    }

    /// Reorder task within same status
    func reorderTask(taskId: String, from sourceIndex: Int, to destinationIndex: Int, status: TaskStatus, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get all tasks with this status
        var statusTasks = tasks.filter { $0.status == status }
            .sorted { $0.order < $1.order }

        guard sourceIndex < statusTasks.count else {
            completion(.failure(NSError(domain: "TaskService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid source index"])))
            return
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

        // Batch update Firestore
        batchUpdateTaskOrders(updates, completion: completion)
    }

    /// Move task to different status
    func moveTask(taskId: String, to newStatus: TaskStatus, at index: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        // Update status first
        updateTask(id: taskId, updates: [
            "status": newStatus.rawValue
        ]) { [weak self] result in
            switch result {
            case .success:
                // Then reorder within new status
                self?.reorderTask(taskId: taskId, from: 0, to: index, status: newStatus, completion: completion)

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
