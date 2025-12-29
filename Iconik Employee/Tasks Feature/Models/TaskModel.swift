//
//  TaskModel.swift
//  Iconik Employee
//
//  Data models for Task Management System
//  Migrated to Supabase
//

import Foundation
import Supabase

// MARK: - Task Type Enum

enum TaskType: String, Codable, CaseIterable {
    case general = "general"
    case session = "session"
    case workflow = "workflow"

    var displayName: String {
        switch self {
        case .general: return "General"
        case .session: return "Session"
        case .workflow: return "Workflow"
        }
    }
}

// MARK: - Task Status Enum

enum TaskStatus: String, Codable, CaseIterable {
    case todo = "todo"
    case inProgress = "in_progress"
    case completed = "completed"

    var displayName: String {
        switch self {
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }

    var color: String {
        switch self {
        case .todo: return "gray"
        case .inProgress: return "blue"
        case .completed: return "green"
        }
    }
}

// MARK: - Task Priority Enum

enum TaskPriority: String, Codable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case urgent = "urgent"

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    var color: String {
        switch self {
        case .low: return "gray"
        case .medium: return "blue"
        case .high: return "orange"
        case .urgent: return "red"
        }
    }

    var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .urgent: return 3
        }
    }
}

// MARK: - Subtask Model

struct Subtask: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var completed: Bool
    var completedAt: Date?
    var completedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case completed
        case completedAt = "completed_at"
        case completedBy = "completed_by"
    }

    init(id: String = UUID().uuidString, title: String, completed: Bool = false, completedAt: Date? = nil, completedBy: String? = nil) {
        self.id = id
        self.title = title
        self.completed = completed
        self.completedAt = completedAt
        self.completedBy = completedBy
    }
}

// MARK: - Task Model

struct TaskItem: Identifiable, Codable {
    // Identity & Ownership
    var id: String
    var organizationID: String
    var createdBy: String

    // Basic Information
    var title: String
    var description: String?
    var type: TaskType?

    // Status & Priority
    var status: TaskStatus
    var priority: TaskPriority

    // Assignment & Collaboration
    var assignedTo: [String]
    var watchers: [String]

    // Dates & Timeline
    var createdAt: Date
    var updatedAt: Date
    var dueDate: Date?
    var startDate: Date?
    var completedAt: Date?
    var completedBy: String?

    // Estimation & Tracking
    var estimatedHours: Double
    var order: Int

    // Subtasks
    var subtasks: [Subtask]

    // Comments & Activity
    var commentCount: Int
    var timeEntryIds: [String]

    // Workflow Integration (Optional - only if type === "workflow")
    var workflowId: String?
    var workflowStepId: String?
    var workflowName: String?
    var workflowStepName: String?
    var autoCreated: Bool?
    var syncWithWorkflow: Bool?

    // Session Integration (Optional - only if type === "session")
    var sessionId: String?
    var sessionName: String?
    var sessionDate: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case organizationID = "organization_id"
        case createdBy = "created_by"
        case title
        case description
        case type
        case status
        case priority
        case assignedTo = "assigned_to"
        case watchers
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dueDate = "due_date"
        case startDate = "start_date"
        case completedAt = "completed_at"
        case completedBy = "completed_by"
        case estimatedHours = "estimated_hours"
        case order = "task_order"
        case subtasks
        case commentCount = "comment_count"
        case timeEntryIds = "time_entry_ids"
        case workflowId = "workflow_id"
        case workflowStepId = "workflow_step_id"
        case workflowName = "workflow_name"
        case workflowStepName = "workflow_step_name"
        case autoCreated = "auto_created"
        case syncWithWorkflow = "sync_with_workflow"
        case sessionId = "session_id"
        case sessionName = "session_name"
        case sessionDate = "session_date"
    }

    // MARK: - Custom Decoder (Handle Missing Fields)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields
        id = try container.decode(String.self, forKey: .id)
        organizationID = try container.decode(String.self, forKey: .organizationID)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(TaskStatus.self, forKey: .status)
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // Optional fields with defaults
        description = try container.decodeIfPresent(String.self, forKey: .description)
        type = try container.decodeIfPresent(TaskType.self, forKey: .type)

        // Arrays with defaults
        assignedTo = try container.decodeIfPresent([String].self, forKey: .assignedTo) ?? []
        watchers = try container.decodeIfPresent([String].self, forKey: .watchers) ?? []
        subtasks = try container.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
        timeEntryIds = try container.decodeIfPresent([String].self, forKey: .timeEntryIds) ?? []

        // Optional dates
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        completedBy = try container.decodeIfPresent(String.self, forKey: .completedBy)

        // Numbers with defaults
        estimatedHours = try container.decodeIfPresent(Double.self, forKey: .estimatedHours) ?? 0
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0

        // Workflow fields
        workflowId = try container.decodeIfPresent(String.self, forKey: .workflowId)
        workflowStepId = try container.decodeIfPresent(String.self, forKey: .workflowStepId)
        workflowName = try container.decodeIfPresent(String.self, forKey: .workflowName)
        workflowStepName = try container.decodeIfPresent(String.self, forKey: .workflowStepName)
        autoCreated = try container.decodeIfPresent(Bool.self, forKey: .autoCreated)
        syncWithWorkflow = try container.decodeIfPresent(Bool.self, forKey: .syncWithWorkflow)

        // Session fields
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName)
        sessionDate = try container.decodeIfPresent(Date.self, forKey: .sessionDate)
    }

    // MARK: - Initializer

    init(
        id: String = UUID().uuidString,
        organizationID: String,
        createdBy: String,
        title: String,
        description: String? = nil,
        type: TaskType = .general,
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        assignedTo: [String] = [],
        watchers: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dueDate: Date? = nil,
        startDate: Date? = nil,
        completedAt: Date? = nil,
        completedBy: String? = nil,
        estimatedHours: Double = 0,
        order: Int = 0,
        subtasks: [Subtask] = [],
        commentCount: Int = 0,
        timeEntryIds: [String] = [],
        workflowId: String? = nil,
        workflowStepId: String? = nil,
        workflowName: String? = nil,
        workflowStepName: String? = nil,
        autoCreated: Bool? = nil,
        syncWithWorkflow: Bool? = nil,
        sessionId: String? = nil,
        sessionName: String? = nil,
        sessionDate: Date? = nil
    ) {
        self.id = id
        self.organizationID = organizationID
        self.createdBy = createdBy
        self.title = title
        self.description = description
        self.type = type
        self.status = status
        self.priority = priority
        self.assignedTo = assignedTo
        self.watchers = watchers
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueDate = dueDate
        self.startDate = startDate
        self.completedAt = completedAt
        self.completedBy = completedBy
        self.estimatedHours = estimatedHours
        self.order = order
        self.subtasks = subtasks
        self.commentCount = commentCount
        self.timeEntryIds = timeEntryIds
        self.workflowId = workflowId
        self.workflowStepId = workflowStepId
        self.workflowName = workflowName
        self.workflowStepName = workflowStepName
        self.autoCreated = autoCreated
        self.syncWithWorkflow = syncWithWorkflow
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.sessionDate = sessionDate
    }

    // MARK: - Note
    // Task uses Codable for automatic Supabase JSON encoding/decoding
    // CodingKeys map Swift camelCase properties to Supabase snake_case fields

    // MARK: - Computed Properties

    /// Task type with default value
    var taskType: TaskType {
        return type ?? .general
    }

    /// Percentage of subtasks completed
    var subtaskProgress: Double {
        guard !subtasks.isEmpty else { return 0 }
        let completedCount = subtasks.filter { $0.completed }.count
        return Double(completedCount) / Double(subtasks.count)
    }

    /// Check if task is overdue
    var isOverdue: Bool {
        guard let dueDate = dueDate else { return false }
        return dueDate < Date() && status != .completed
    }

    /// Check if task is assigned to a specific user
    func isAssignedTo(userId: String) -> Bool {
        return assignedTo.contains(userId)
    }

    /// Check if user is watching this task
    func isWatchedBy(userId: String) -> Bool {
        return watchers.contains(userId)
    }

    /// Get display text for assignment (e.g., "3 assignees")
    var assignmentDisplayText: String {
        switch assignedTo.count {
        case 0: return "Unassigned"
        case 1: return "1 assignee"
        default: return "\(assignedTo.count) assignees"
        }
    }
}

// MARK: - Task Extensions

extension TaskItem {
    /// Create a new task with default values
    static func new(organizationID: String, createdBy: String, title: String) -> TaskItem {
        return TaskItem(
            organizationID: organizationID,
            createdBy: createdBy,
            title: title,
            status: .todo,
            priority: .medium,
            assignedTo: [],
            watchers: [createdBy] // Creator automatically watches
        )
    }

    /// Duplicate an existing task
    func duplicate() -> TaskItem {
        var duplicated = self
        duplicated.id = UUID().uuidString
        duplicated.title = "\(title) (Copy)"
        duplicated.createdAt = Date()
        duplicated.updatedAt = Date()
        duplicated.status = .todo
        duplicated.completedAt = nil
        duplicated.completedBy = nil
        duplicated.commentCount = 0
        duplicated.timeEntryIds = []

        // Reset subtasks completion status
        duplicated.subtasks = subtasks.map { subtask in
            var newSubtask = subtask
            newSubtask.id = UUID().uuidString
            newSubtask.completed = false
            newSubtask.completedAt = nil
            newSubtask.completedBy = nil
            return newSubtask
        }

        return duplicated
    }
}
