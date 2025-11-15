//
//  TasksViewModel.swift
//  Iconik Employee
//
//  ViewModel for TasksMainView
//  Implements cache-first loading with real-time updates
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

class TasksViewModel: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let taskService = TaskService.shared
    private let cacheService = TaskCacheService.shared
    private var cancellables = Set<AnyCancellable>()

    private var currentUserId: String {
        return Auth.auth().currentUser?.uid ?? ""
    }

    private var currentOrganizationId: String {
        // Get organization ID from UserManager (which fetches from Firestore)
        let orgId = UserManager.shared.getCachedOrganizationID()

        if orgId.isEmpty {
            print("⚠️ WARNING: organizationID is empty! Attempting to initialize...")
            // Try to initialize if not already done
            UserManager.shared.initializeOrganizationID()
            return UserManager.shared.getCachedOrganizationID()
        } else {
            print("✓ Using organizationID from UserManager: \(orgId)")
            return orgId
        }
    }

    // MARK: - Load Tasks (Cache-First Strategy)

    func loadTasks() {
        guard !currentUserId.isEmpty else {
            print("❌ Cannot load tasks: Missing user ID")
            return
        }

        // Check if we have organization ID
        let orgId = UserManager.shared.getCachedOrganizationID()

        if orgId.isEmpty {
            print("⚠️ Organization ID not available, fetching from Firestore...")
            isLoading = true

            // Fetch organization ID first
            UserManager.shared.getCurrentUserOrganizationID { [weak self] fetchedOrgId in
                guard let self = self, let fetchedOrgId = fetchedOrgId else {
                    print("❌ Failed to get organization ID")
                    self?.isLoading = false
                    return
                }

                print("✅ Got organization ID: \(fetchedOrgId)")
                // Now load tasks with the fetched org ID
                self.loadTasksWithOrgId(fetchedOrgId)
            }
        } else {
            // Organization ID already cached, load immediately
            print("✓ Using cached organization ID: \(orgId)")
            loadTasksWithOrgId(orgId)
        }
    }

    private func loadTasksWithOrgId(_ orgId: String) {
        // Step 1: Load from cache immediately
        if let cachedTasks = cacheService.getCachedTasks(userId: currentUserId, orgId: orgId) {
            print("✅ Loaded \(cachedTasks.count) tasks from cache")
            self.tasks = cachedTasks

            // Get cache timestamp for incremental updates
            let cacheTimestamp = cacheService.getLatestTimestamp(userId: currentUserId, orgId: orgId)

            // Start real-time listener for updates AFTER cache timestamp
            startIncrementalListener(afterTimestamp: cacheTimestamp)
        } else {
            print("⚠️ No cache found - fetching all tasks from Firestore")
            // No cache - fetch all tasks
            fetchAllTasks()
        }
    }

    // MARK: - Fetch All Tasks

    private func fetchAllTasks() {
        isLoading = true

        taskService.fetchTasks(organizationID: currentOrganizationId) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false

            switch result {
            case .success(let tasks):
                print("📥 Fetched \(tasks.count) tasks from Firestore")
                self.tasks = tasks

                // Cache the fetched tasks
                self.cacheService.setCachedTasks(tasks, userId: self.currentUserId, orgId: self.currentOrganizationId)

                // Start real-time listener
                self.startIncrementalListener(afterTimestamp: nil)

            case .failure(let error):
                print("❌ Failed to fetch tasks: \(error.localizedDescription)")
                self.error = error
            }
        }
    }

    // MARK: - Incremental Listener

    private func startIncrementalListener(afterTimestamp: Timestamp?) {
        // Start listening to real-time updates
        taskService.startListening(organizationID: currentOrganizationId)

        // Subscribe to task updates
        taskService.$tasks
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
            .store(in: &cancellables)
    }

    // MARK: - Stop Listening

    func stopListening() {
        taskService.stopListening()
        cancellables.removeAll()
    }

    // MARK: - Refresh Tasks

    func refreshTasks() {
        print("🔄 Refreshing tasks...")
        fetchAllTasks()
    }

    // MARK: - Clear Cache and Reload

    func clearCacheAndReload() {
        print("🗑 Clearing cache and reloading...")
        cacheService.clearCache(userId: currentUserId, orgId: currentOrganizationId)
        tasks.removeAll()
        fetchAllTasks()
    }

    // MARK: - Create Task

    func createTask(_ task: TaskItem) {
        taskService.createTask(task) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let createdTask):
                print("✅ Task created: \(createdTask.title)")

                // Clear cache to force refresh (prevents ghost tasks)
                self.cacheService.clearOrganizationCache(orgId: self.currentOrganizationId)

                // Refresh tasks
                self.refreshTasks()

            case .failure(let error):
                print("❌ Failed to create task: \(error.localizedDescription)")
                self.error = error
            }
        }
    }

    // MARK: - Update Task

    func updateTask(_ task: TaskItem) {
        taskService.updateTask(task) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                print("✅ Task updated: \(task.title)")

                // Clear cache to force refresh
                self.cacheService.clearOrganizationCache(orgId: self.currentOrganizationId)

                // Update local state
                if let index = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[index] = task
                }

            case .failure(let error):
                print("❌ Failed to update task: \(error.localizedDescription)")
                self.error = error
            }
        }
    }

    // MARK: - Toggle Task Completion

    func toggleTaskCompletion(_ task: TaskItem) {
        if task.status == .completed {
            // Reopen task
            taskService.reopenTask(id: task.id) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    print("✅ Task reopened: \(task.title)")
                    self.cacheService.clearOrganizationCache(orgId: self.currentOrganizationId)
                    self.refreshTasks()

                case .failure(let error):
                    print("❌ Failed to reopen task: \(error.localizedDescription)")
                    self.error = error
                }
            }
        } else {
            // Complete task
            taskService.completeTask(id: task.id, userId: currentUserId) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    print("✅ Task completed: \(task.title)")
                    self.cacheService.clearOrganizationCache(orgId: self.currentOrganizationId)
                    self.refreshTasks()

                case .failure(let error):
                    print("❌ Failed to complete task: \(error.localizedDescription)")
                    self.error = error
                }
            }
        }
    }

    // MARK: - Filtering

    func filteredTasks(searchText: String, filter: TaskFilter, status: TaskStatus?, priority: TaskPriority?) -> [TaskItem] {
        var filtered = tasks

        // Apply filter
        switch filter {
        case .all:
            // Exclude completed tasks from "All" view
            filtered = filtered.filter { $0.status != .completed }
        case .myTasks:
            // Show only user's tasks, excluding completed
            filtered = filtered.filter {
                ($0.isAssignedTo(userId: currentUserId) || $0.createdBy == currentUserId) &&
                $0.status != .completed
            }
        case .today:
            // Show only tasks due today, excluding completed
            filtered = filtered.filter { task in
                guard let dueDate = task.dueDate else { return false }
                return Calendar.current.isDateInToday(dueDate) && task.status != .completed
            }
        case .urgent:
            // Show only urgent/overdue tasks, excluding completed
            filtered = filtered.filter {
                ($0.priority == .urgent || $0.isOverdue) &&
                $0.status != .completed
            }
        case .completed:
            // Only show completed tasks
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

    // MARK: - Task Counts

    func taskCount(for filter: TaskFilter) -> Int? {
        switch filter {
        case .all:
            return nil  // Don't show count for "all"
        case .myTasks:
            return tasks.filter {
                ($0.isAssignedTo(userId: currentUserId) || $0.createdBy == currentUserId) &&
                $0.status != .completed
            }.count
        case .today:
            return tasks.filter { task in
                guard let dueDate = task.dueDate else { return false }
                return Calendar.current.isDateInToday(dueDate) && task.status != .completed
            }.count
        case .urgent:
            return tasks.filter {
                ($0.priority == .urgent || $0.isOverdue) &&
                $0.status != .completed
            }.count
        case .completed:
            return tasks.filter { $0.status == .completed }.count
        }
    }
}
