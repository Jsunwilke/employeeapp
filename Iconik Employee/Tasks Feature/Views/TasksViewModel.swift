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

@MainActor
class TasksViewModel: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let taskService = TaskService.shared
    private let cacheService = TaskCacheService.shared
    private var cancellables = Set<AnyCancellable>()

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

    nonisolated func stopListening() {
        Task { @MainActor in
            taskService.stopListening()
            cancellables.removeAll()
        }
    }

    // MARK: - Refresh Tasks

    func refreshTasks() {
        fetchAllTasks()
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
                let createdTask = try await taskService.createTask(task)

                // Clear cache to force refresh (prevents ghost tasks)
                self.cacheService.clearOrganizationCache(orgId: self.currentOrganizationId)

                // Refresh tasks
                self.refreshTasks()
            } catch {
                self.error = error
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
                self.error = error
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
                self.error = error
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

    // MARK: - Task Counts

    func taskCount(for filter: TaskFilter) -> Int? {
        switch filter {
        case .all:
            return nil  // Don't show count for "all"
        case .myTasks:
            return tasks.filter { task in
                task.assignedTo.contains { $0.lowercased() == currentUserId } &&
                task.status != .completed
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
