//
//  TaskModel.swift
//  Iconik Employee
//
//  Data models for Task Management System
//  Matches Firestore schema from web implementation
//

import Foundation
import FirebaseFirestore

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
    case onHold = "on_hold"
    case completed = "completed"
    case cancelled = "cancelled"

    var displayName: String {
        switch self {
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .onHold: return "On Hold"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var color: String {
        switch self {
        case .todo: return "gray"
        case .inProgress: return "blue"
        case .onHold: return "orange"
        case .completed: return "green"
        case .cancelled: return "red"
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
        case completedAt
        case completedBy
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
    var type: TaskType

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
        case organizationID
        case createdBy
        case title
        case description
        case type
        case status
        case priority
        case assignedTo
        case watchers
        case createdAt
        case updatedAt
        case dueDate
        case startDate
        case completedAt
        case completedBy
        case estimatedHours
        case order
        case subtasks
        case commentCount
        case timeEntryIds
        case workflowId
        case workflowStepId
        case workflowName
        case workflowStepName
        case autoCreated
        case syncWithWorkflow
        case sessionId
        case sessionName
        case sessionDate
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

    // MARK: - Firestore Conversion

    init?(from document: DocumentSnapshot) {
        guard let data = document.data(),
              let organizationID = data["organizationID"] as? String,
              let createdBy = data["createdBy"] as? String,
              let title = data["title"] as? String,
              let typeString = data["type"] as? String,
              let type = TaskType(rawValue: typeString),
              let statusString = data["status"] as? String,
              let status = TaskStatus(rawValue: statusString),
              let priorityString = data["priority"] as? String,
              let priority = TaskPriority(rawValue: priorityString),
              let createdAtTimestamp = data["createdAt"] as? Timestamp,
              let updatedAtTimestamp = data["updatedAt"] as? Timestamp else {
            return nil
        }

        self.id = document.documentID
        self.organizationID = organizationID
        self.createdBy = createdBy
        self.title = title
        self.description = data["description"] as? String
        self.type = type
        self.status = status
        self.priority = priority
        self.assignedTo = data["assignedTo"] as? [String] ?? []
        self.watchers = data["watchers"] as? [String] ?? []
        self.createdAt = createdAtTimestamp.dateValue()
        self.updatedAt = updatedAtTimestamp.dateValue()
        self.dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
        self.startDate = (data["startDate"] as? Timestamp)?.dateValue()
        self.completedAt = (data["completedAt"] as? Timestamp)?.dateValue()
        self.completedBy = data["completedBy"] as? String
        self.estimatedHours = data["estimatedHours"] as? Double ?? 0
        self.order = data["order"] as? Int ?? 0
        self.commentCount = data["commentCount"] as? Int ?? 0
        self.timeEntryIds = data["timeEntryIds"] as? [String] ?? []

        // Parse subtasks
        if let subtasksData = data["subtasks"] as? [[String: Any]] {
            self.subtasks = subtasksData.compactMap { subtaskDict in
                guard let id = subtaskDict["id"] as? String,
                      let title = subtaskDict["title"] as? String,
                      let completed = subtaskDict["completed"] as? Bool else {
                    return nil
                }
                return Subtask(
                    id: id,
                    title: title,
                    completed: completed,
                    completedAt: (subtaskDict["completedAt"] as? Timestamp)?.dateValue(),
                    completedBy: subtaskDict["completedBy"] as? String
                )
            }
        } else {
            self.subtasks = []
        }

        // Workflow fields
        self.workflowId = data["workflowId"] as? String
        self.workflowStepId = data["workflowStepId"] as? String
        self.workflowName = data["workflowName"] as? String
        self.workflowStepName = data["workflowStepName"] as? String
        self.autoCreated = data["autoCreated"] as? Bool
        self.syncWithWorkflow = data["syncWithWorkflow"] as? Bool

        // Session fields
        self.sessionId = data["sessionId"] as? String
        self.sessionName = data["sessionName"] as? String
        self.sessionDate = (data["sessionDate"] as? Timestamp)?.dateValue()
    }

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "organizationID": organizationID,
            "createdBy": createdBy,
            "title": title,
            "type": type.rawValue,
            "status": status.rawValue,
            "priority": priority.rawValue,
            "assignedTo": assignedTo,
            "watchers": watchers,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "estimatedHours": estimatedHours,
            "order": order,
            "commentCount": commentCount,
            "timeEntryIds": timeEntryIds,
            "subtasks": subtasks.map { subtask in
                var subtaskData: [String: Any] = [
                    "id": subtask.id,
                    "title": subtask.title,
                    "completed": subtask.completed
                ]
                if let completedAt = subtask.completedAt {
                    subtaskData["completedAt"] = Timestamp(date: completedAt)
                }
                if let completedBy = subtask.completedBy {
                    subtaskData["completedBy"] = completedBy
                }
                return subtaskData
            }
        ]

        // Add optional fields
        if let description = description {
            data["description"] = description
        }
        if let dueDate = dueDate {
            data["dueDate"] = Timestamp(date: dueDate)
        }
        if let startDate = startDate {
            data["startDate"] = Timestamp(date: startDate)
        }
        if let completedAt = completedAt {
            data["completedAt"] = Timestamp(date: completedAt)
        }
        if let completedBy = completedBy {
            data["completedBy"] = completedBy
        }
        if let workflowId = workflowId {
            data["workflowId"] = workflowId
        }
        if let workflowStepId = workflowStepId {
            data["workflowStepId"] = workflowStepId
        }
        if let workflowName = workflowName {
            data["workflowName"] = workflowName
        }
        if let workflowStepName = workflowStepName {
            data["workflowStepName"] = workflowStepName
        }
        if let autoCreated = autoCreated {
            data["autoCreated"] = autoCreated
        }
        if let syncWithWorkflow = syncWithWorkflow {
            data["syncWithWorkflow"] = syncWithWorkflow
        }
        if let sessionId = sessionId {
            data["sessionId"] = sessionId
        }
        if let sessionName = sessionName {
            data["sessionName"] = sessionName
        }
        if let sessionDate = sessionDate {
            data["sessionDate"] = Timestamp(date: sessionDate)
        }

        return data
    }

    // MARK: - Computed Properties

    /// Percentage of subtasks completed
    var subtaskProgress: Double {
        guard !subtasks.isEmpty else { return 0 }
        let completedCount = subtasks.filter { $0.completed }.count
        return Double(completedCount) / Double(subtasks.count)
    }

    /// Check if task is overdue
    var isOverdue: Bool {
        guard let dueDate = dueDate else { return false }
        return dueDate < Date() && status != .completed && status != .cancelled
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
