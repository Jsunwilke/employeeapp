# Task Management System - iOS Implementation Specification

## Executive Summary

This document provides comprehensive technical specifications for implementing the Task Management system in the iOS version of Focal Point. The web implementation uses React 18 with Firebase Firestore and includes features like real-time collaboration, workflow integration, time tracking, and cache-optimized data loading.

---

## 1. Data Structure & Schema

### 1.1 Firestore Collection: `tasks`

**Collection Path:** `/tasks/{taskId}`

#### Core Task Document Fields

```typescript
{
  // Identity & Ownership
  id: string,                    // Document ID
  organizationID: string,         // REQUIRED - Organization reference
  createdBy: string,             // REQUIRED - User ID of creator

  // Basic Information
  title: string,                 // REQUIRED - Task title
  description: string,           // Rich text content (HTML)
  type: string,                  // "general" | "session" | "workflow"

  // Status & Priority
  status: string,                // "todo" | "in_progress" | "on_hold" | "completed" | "cancelled"
  priority: string,              // "low" | "medium" | "high" | "urgent"

  // Assignment & Collaboration
  assignedTo: string[],          // Array of user IDs
  watchers: string[],            // Array of user IDs watching this task

  // Dates & Timeline
  createdAt: Timestamp,          // Auto-generated on create
  updatedAt: Timestamp,          // Auto-updated on every change
  dueDate: Timestamp | null,     // Optional due date
  startDate: Timestamp | null,   // Optional start date
  completedAt: Timestamp | null, // Set when status = "completed"
  completedBy: string | null,    // User ID who completed the task

  // Estimation & Tracking
  estimatedHours: number,        // Estimated work hours (default: 0)
  order: number,                 // For drag-and-drop ordering (0-based index)

  // Subtasks
  subtasks: Array<{
    id: string,                  // Unique ID (generated client-side)
    title: string,
    completed: boolean,
    completedAt: Timestamp | null,
    completedBy: string | null
  }>,

  // Comments & Activity
  commentCount: number,          // Cached count (default: 0)
  timeEntryIds: string[],        // References to time tracking entries

  // Workflow Integration (Optional - only if type === "workflow")
  workflowId: string | undefined,      // Reference to workflow document
  workflowStepId: string | undefined,  // Reference to specific step
  workflowName: string | undefined,    // Cached workflow name
  workflowStepName: string | undefined, // Cached step name
  autoCreated: boolean,          // True if auto-generated from workflow
  syncWithWorkflow: boolean,     // True if status should sync with workflow

  // Session Integration (Optional - only if type === "session")
  sessionId: string | undefined,       // Reference to session document
  sessionName: string | undefined,     // Cached session name
  sessionDate: Timestamp | undefined   // Cached session date
}
```

#### Critical Field Notes

1. **Field Naming Consistency:** Use **camelCase** throughout (`workflowId`, `workflowStepId`, `sessionId`, `organizationID`)

2. **Status Values:**
   ```typescript
   TASK_STATUS = {
     TODO: 'todo',
     IN_PROGRESS: 'in_progress',
     ON_HOLD: 'on_hold',
     COMPLETED: 'completed',
     CANCELLED: 'cancelled'
   }
   ```

3. **Priority Values:**
   ```typescript
   TASK_PRIORITY = {
     LOW: 'low',
     MEDIUM: 'medium',
     HIGH: 'high',
     URGENT: 'urgent'
   }
   ```

4. **Order Field:** Used for manual drag-and-drop ordering within the same status column. Higher numbers appear later.

---

### 1.2 Subcollection: `tasks/{taskId}/comments`

**Collection Path:** `/tasks/{taskId}/comments/{commentId}`

```typescript
{
  id: string,                    // Document ID
  userId: string,                // REQUIRED - Commenter user ID
  userName: string,              // REQUIRED - Cached display name
  text: string,                  // REQUIRED - Comment text
  mentions: Array<{
    userId: string,
    userName: string
  }>,
  attachments: Array<{
    fileName: string,
    fileUrl: string,
    fileType: string,
    fileSize: number
  }>,
  createdAt: Timestamp,          // Auto-generated
  updatedAt: Timestamp           // Auto-updated on edit
}
```

---

### 1.3 Related Collections

#### Task Notifications Collection

**Collection:** `taskNotifications`

```typescript
{
  userId: string,                // Recipient user ID
  organizationID: string,
  taskId: string,                // Reference to task
  type: string,                  // "mention" | "assignment" | "comment" | "status_change" | etc.
  title: string,                 // Notification title
  message: string,               // Notification message
  triggeredBy: string,           // User ID who triggered notification
  data: object,                  // Additional context data
  read: boolean,                 // Read status
  readAt: Timestamp | null,
  createdAt: Timestamp
}
```

#### Activity Log Collection

**Collection:** `activity`

```typescript
{
  targetId: string,              // Task ID
  targetType: string,            // "task"
  activityType: string,          // See ACTIVITY_TYPES below
  metadata: object,              // Type-specific data
  performedBy: string,           // User ID
  organizationID: string,
  timestamp: Timestamp
}
```

**Activity Types:**
- `TASK_CREATED`
- `STATUS_CHANGED`
- `PRIORITY_CHANGED`
- `DUE_DATE_CHANGED`
- `TITLE_UPDATED`
- `DESCRIPTION_UPDATED`
- `ASSIGNEE_ADDED`
- `ASSIGNEE_REMOVED`
- `COMMENT_ADDED`
- `SUBTASK_COMPLETED`
- `SUBTASK_UNCOMPLETED`
- `TASK_COMPLETED`
- `TASK_REOPENED`
- `ATTACHMENT_UPLOADED`
- `ATTACHMENT_DELETED`
- `TIME_LOGGED`

---

### 1.4 Required Firestore Indexes

```json
[
  {
    "collectionGroup": "tasks",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "organizationID", "order": "ASCENDING" },
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "order", "order": "DESCENDING" }
    ]
  },
  {
    "collectionGroup": "tasks",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "organizationID", "order": "ASCENDING" },
      { "fieldPath": "assignedTo", "arrayConfig": "CONTAINS" },
      { "fieldPath": "dueDate", "order": "ASCENDING" }
    ]
  },
  {
    "collectionGroup": "tasks",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "organizationID", "order": "ASCENDING" },
      { "fieldPath": "createdBy", "order": "ASCENDING" },
      { "fieldPath": "dueDate", "order": "ASCENDING" }
    ]
  },
  {
    "collectionGroup": "tasks",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "organizationID", "order": "ASCENDING" },
      { "fieldPath": "workflowId", "order": "ASCENDING" },
      { "fieldPath": "workflowStepId", "order": "ASCENDING" },
      { "fieldPath": "createdAt", "order": "DESCENDING" }
    ]
  },
  {
    "collectionGroup": "tasks",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "organizationID", "order": "ASCENDING" },
      { "fieldPath": "assignedTo", "arrayConfig": "CONTAINS" },
      { "fieldPath": "updatedAt", "order": "DESCENDING" }
    ]
  },
  {
    "collectionGroup": "tasks",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "organizationID", "order": "ASCENDING" },
      { "fieldPath": "createdBy", "order": "ASCENDING" },
      { "fieldPath": "updatedAt", "order": "DESCENDING" }
    ]
  }
]
```

---

## 2. Core Features & Business Logic

### 2.1 Task Creation

**Required Flow:**

1. **Validate Required Fields:**
   - `title` (non-empty string)
   - `organizationID` (current user's organization)
   - `createdBy` (current user's ID)

2. **Calculate Initial Order:**
   ```swift
   // Query existing tasks with same organizationID and status
   let existingTasks = try await fetchTasks(
     organizationID: orgId,
     status: "todo"
   )
   let maxOrder = existingTasks.map { $0.order }.max() ?? -1
   let newOrder = maxOrder + 1
   ```

3. **Set Default Values:**
   ```swift
   Task(
     status: "todo",
     priority: "medium",
     commentCount: 0,
     subtasks: [],
     timeEntryIds: [],
     watchers: [],
     assignedTo: [],
     createdAt: Timestamp.now(),
     updatedAt: Timestamp.now()
   )
   ```

4. **Create Task Document**

5. **Clear Organization Cache** (critical for preventing ghost tasks)

6. **Log Activity:** Create `TASK_CREATED` activity entry

7. **Send Notifications:** If `assignedTo` is not empty, notify assigned users

**Auto-Assignment Behavior:**
- If user creates task without explicit assignment, they become the implicit owner
- Task appears under "My Tasks" for the creator

---

### 2.2 Task Updates

**Tracked Changes (with activity logging):**

| Field Change | Activity Type | Send Notifications |
|-------------|---------------|-------------------|
| Status | `STATUS_CHANGED` | Yes (watchers) |
| Priority | `PRIORITY_CHANGED` | No |
| Due Date | `DUE_DATE_CHANGED` | Yes (assignees) |
| Title | `TITLE_UPDATED` | No |
| Description | `DESCRIPTION_UPDATED` | No |
| Add Assignee | `ASSIGNEE_ADDED` | Yes (new assignee) |
| Remove Assignee | `ASSIGNEE_REMOVED` | Yes (removed assignee) |

**Time Tracking Auto-Stop:**

When status changes FROM "in_progress" TO any other status:
```swift
if oldStatus == .inProgress && newStatus != .inProgress {
  // Check for active time entry
  if let activeEntry = try await getActiveTimeEntry(userId: currentUserId, taskId: taskId) {
    // Auto-stop the time entry
    try await stopTimeEntry(activeEntry.id)

    // Log activity
    try await logActivity(
      type: .TIME_LOGGED,
      metadata: ["action": "auto_stopped_tracking"]
    )
  }
}
```

**Time Tracking Auto-Start:**

When status changes TO "in_progress":
```swift
if newStatus == .inProgress && oldStatus != .inProgress {
  if let activeEntry = try await getCurrentTimeEntry(userId: currentUserId) {
    // Add this task to existing time entry
    try await addTaskToTimeEntry(activeEntry.id, taskId: taskId)
  } else {
    // Start new time entry
    try await startTimeEntry(userId: currentUserId, taskId: taskId)
  }

  // Log activity
  try await logActivity(
    type: .TIME_LOGGED,
    metadata: ["action": "auto_started_tracking"]
  )
}
```

---

### 2.3 Task Deletion

**Permission Rules:**

| User Role | Can Delete Own Tasks | Can Delete Others' Tasks | Can Delete Completed |
|-----------|---------------------|-------------------------|---------------------|
| Admin | Yes | Yes | Yes |
| Manager | Yes | Yes (org only) | No |
| User | Yes (if not completed) | No | No |

**Deletion Flow:**

```swift
func deleteTask(taskId: String) async throws {
  // 1. Check permissions BEFORE attempting delete
  guard canDeleteTask(taskId) else {
    throw TaskError.permissionDenied
  }

  // 2. Delete task document
  try await firestore.collection("tasks").document(taskId).delete()

  // 3. CRITICAL: Clear organization cache
  taskCacheService.clearOrganizationCache(orgId)

  // 4. Remove from local state
  tasks.removeAll { $0.id == taskId }

  // 5. TODO: Clean up orphaned data
  // - Delete comments subcollection
  // - Delete activity entries
  // - Delete attachments from storage
  // - Remove time entry references
}
```

---

### 2.4 Task Completion

**Completion Flow:**

```swift
func completeTask(taskId: String) async throws {
  // 1. Update task status
  try await updateTask(taskId, updates: [
    "status": "completed",
    "completedAt": Timestamp.now(),
    "completedBy": currentUserId
  ])

  // 2. Auto-stop time tracking if active
  if let activeEntry = try await getActiveTimeEntry(userId: currentUserId, taskId: taskId) {
    try await stopTimeEntry(activeEntry.id)
  }

  // 3. Log activity
  try await logActivity(type: .TASK_COMPLETED, taskId: taskId)

  // 4. Send notifications to watchers
  try await notifyWatchers(taskId: taskId, type: .taskCompleted)
}
```

**Reopening a Task:**

```swift
func reopenTask(taskId: String) async throws {
  try await updateTask(taskId, updates: [
    "status": "todo",  // or previous status
    "completedAt": FieldValue.delete(),
    "completedBy": FieldValue.delete()
  ])

  try await logActivity(type: .TASK_REOPENED, taskId: taskId)
}
```

---

### 2.5 Subtasks

**Structure:**
```swift
struct Subtask: Codable {
  let id: String                  // Client-generated (e.g., "subtask_\(Date().timeIntervalSince1970)")
  var title: String
  var completed: Bool
  var completedAt: Timestamp?
  var completedBy: String?
}
```

**Operations:**

**Add Subtask:**
```swift
func addSubtask(to taskId: String, title: String) async throws {
  let newSubtask = Subtask(
    id: "subtask_\(Date().timeIntervalSince1970)",
    title: title,
    completed: false,
    completedAt: nil,
    completedBy: nil
  )

  try await updateTask(taskId, updates: [
    "subtasks": FieldValue.arrayUnion([newSubtask.dictionary])
  ])
}
```

**Toggle Subtask:**
```swift
func toggleSubtask(taskId: String, subtaskId: String) async throws {
  // 1. Get current task
  let task = try await getTask(taskId)

  // 2. Find and toggle subtask
  var updatedSubtasks = task.subtasks
  if let index = updatedSubtasks.firstIndex(where: { $0.id == subtaskId }) {
    updatedSubtasks[index].completed.toggle()

    if updatedSubtasks[index].completed {
      updatedSubtasks[index].completedAt = Timestamp.now()
      updatedSubtasks[index].completedBy = currentUserId

      // Log activity
      try await logActivity(
        type: .SUBTASK_COMPLETED,
        metadata: ["subtaskTitle": updatedSubtasks[index].title]
      )
    } else {
      updatedSubtasks[index].completedAt = nil
      updatedSubtasks[index].completedBy = nil

      try await logActivity(type: .SUBTASK_UNCOMPLETED)
    }
  }

  // 3. Update task
  try await updateTask(taskId, updates: [
    "subtasks": updatedSubtasks.map { $0.dictionary }
  ])
}
```

---

### 2.6 Comments

**Creation Flow:**

```swift
func addComment(taskId: String, text: String) async throws {
  // 1. Extract mentions from text
  let mentions = extractMentions(from: text)

  // 2. Create comment document
  let comment = Comment(
    id: UUID().uuidString,
    userId: currentUserId,
    userName: currentUserName,
    text: text,
    mentions: mentions,
    attachments: [],
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now()
  )

  try await firestore
    .collection("tasks").document(taskId)
    .collection("comments").document(comment.id)
    .setData(comment.dictionary)

  // 3. Increment task's commentCount
  try await firestore
    .collection("tasks").document(taskId)
    .updateData(["commentCount": FieldValue.increment(Int64(1))])

  // 4. Create notifications for mentions
  for mention in mentions {
    try await createNotification(
      userId: mention.userId,
      taskId: taskId,
      type: .mention,
      triggeredBy: currentUserId
    )

    // Auto-watch task for mentioned user
    try await addWatcher(taskId: taskId, userId: mention.userId)
  }

  // 5. Notify watchers about new comment
  try await notifyWatchers(taskId: taskId, type: .comment)

  // 6. Log activity
  try await logActivity(
    type: .COMMENT_ADDED,
    metadata: ["commentPreview": String(text.prefix(100))]
  )
}
```

**Mention Extraction:**
```swift
func extractMentions(from text: String) -> [Mention] {
  // Pattern: @First Last or @FirstName LastName
  let pattern = #"@([A-Z][a-z]+(?: [A-Z][a-z]+)+)"#
  let regex = try! NSRegularExpression(pattern: pattern)
  let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

  return matches.compactMap { match in
    guard let range = Range(match.range(at: 1), in: text) else { return nil }
    let name = String(text[range])

    // Look up user by name
    return findUser(byName: name).map { user in
      Mention(userId: user.id, userName: user.fullName)
    }
  }
}
```

---

### 2.7 Watchers

**Auto-Watch Triggers:**
- User is mentioned in a comment
- User is assigned to the task
- User creates the task (implicit)

**Manual Watch/Unwatch:**
```swift
func toggleWatch(taskId: String) async throws {
  let task = try await getTask(taskId)

  if task.watchers.contains(currentUserId) {
    // Unwatch
    try await firestore
      .collection("tasks").document(taskId)
      .updateData([
        "watchers": FieldValue.arrayRemove([currentUserId])
      ])
  } else {
    // Watch
    try await firestore
      .collection("tasks").document(taskId)
      .updateData([
        "watchers": FieldValue.arrayUnion([currentUserId])
      ])
  }
}
```

**Notifications Sent to Watchers:**
- Status changes
- New comments
- Task completion
- Assignee changes
- Priority changes (high/urgent only)

---

### 2.8 Drag-and-Drop Reordering

**Implementation:**

```swift
func reorderTask(
  taskId: String,
  from sourceIndex: Int,
  to destinationIndex: Int,
  status: TaskStatus
) async throws {
  // 1. Get all tasks with this status
  var statusTasks = tasks.filter { $0.status == status }
    .sorted { $0.order < $1.order }

  // 2. Remove task from source
  let movedTask = statusTasks.remove(at: sourceIndex)

  // 3. Insert at destination
  statusTasks.insert(movedTask, at: destinationIndex)

  // 4. Recalculate order for all affected tasks
  let updates: [(String, Int)] = statusTasks.enumerated().map { index, task in
    (task.id, index)
  }

  // 5. Batch update Firestore
  try await batchUpdateTaskOrders(updates)

  // 6. Update local state optimistically
  updateLocalTaskOrders(updates)
}

func batchUpdateTaskOrders(_ updates: [(String, Int)]) async throws {
  let batch = firestore.batch()

  for (taskId, newOrder) in updates {
    let ref = firestore.collection("tasks").document(taskId)
    batch.updateData(["order": newOrder], forDocument: ref)
  }

  try await batch.commit()
}
```

**Drag Between Status Columns:**
```swift
func moveTask(
  taskId: String,
  to newStatus: TaskStatus,
  at index: Int
) async throws {
  // 1. Update status
  try await updateTask(taskId, updates: [
    "status": newStatus.rawValue
  ])

  // 2. Reorder within new status
  try await reorderTask(taskId: taskId, to: index, status: newStatus)
}
```

---

### 2.9 Workflow Integration

**When Task is Linked to Workflow:**

```swift
struct WorkflowTask: Task {
  let type: String = "workflow"
  let workflowId: String
  let workflowStepId: String
  let workflowName: String       // Cached for display
  let workflowStepName: String   // Cached for display
  let autoCreated: Bool          // True if auto-generated
  let syncWithWorkflow: Bool     // True if bidirectional sync enabled
}
```

**Bidirectional Sync Logic:**

```swift
func handleWorkflowTaskStatusChange(task: WorkflowTask, newStatus: TaskStatus) async throws {
  // Update task status
  try await updateTask(task.id, updates: ["status": newStatus.rawValue])

  // If sync enabled, update workflow step
  if task.syncWithWorkflow {
    if newStatus == .completed {
      try await markWorkflowStepComplete(
        workflowId: task.workflowId,
        stepId: task.workflowStepId
      )
    } else if newStatus == .inProgress {
      try await markWorkflowStepInProgress(
        workflowId: task.workflowId,
        stepId: task.workflowStepId
      )
    }
  }
}
```

**Query Tasks by Workflow:**
```swift
func fetchWorkflowTasks(workflowId: String, stepId: String) async throws -> [Task] {
  return try await firestore
    .collection("tasks")
    .whereField("organizationID", isEqualTo: currentOrgId)
    .whereField("workflowId", isEqualTo: workflowId)
    .whereField("workflowStepId", isEqualTo: stepId)
    .getDocuments()
    .documents
    .compactMap { try? $0.data(as: Task.self) }
}
```

---

### 2.10 Session Integration

**When Task is Linked to Session:**

```swift
struct SessionTask: Task {
  let type: String = "session"
  let sessionId: String
  let sessionName: String        // Cached: school/client name
  let sessionDate: Timestamp     // Cached session date
}
```

**Use Case:** Photography session tasks (e.g., "Edit photos for Lincoln HS graduation session")

**Query Tasks by Session:**
```swift
func fetchSessionTasks(sessionId: String) async throws -> [Task] {
  return try await firestore
    .collection("tasks")
    .whereField("organizationID", isEqualTo: currentOrgId)
    .whereField("sessionId", isEqualTo: sessionId)
    .order(by: "createdAt", descending: true)
    .getDocuments()
    .documents
    .compactMap { try? $0.data(as: Task.self) }
}
```

---

## 3. Caching & Performance Optimization

### 3.1 Cache-First Loading Pattern

**CRITICAL REQUIREMENT:** Implement cache-first loading to prevent excessive Firestore reads.

**Pattern:**
```swift
class TaskViewModel: ObservableObject {
  @Published var tasks: [Task] = []
  @Published var loading = false

  private let taskService: TaskService
  private let cacheService: TaskCacheService
  private let readCounter = ReadCounter.shared

  func loadTasks() {
    // Step 1: Load from cache immediately
    if let cachedTasks = cacheService.getCachedTasks(
      userId: currentUserId,
      orgId: currentOrgId
    ) {
      self.tasks = cachedTasks
      readCounter.recordCacheHit("tasks", "TaskListView", cachedTasks.count)

      // Step 2: Check if cache is fresh enough
      if cacheService.isCacheFresh() {
        return  // Use cache only
      }
    } else {
      readCounter.recordCacheMiss("tasks", "TaskListView")
    }

    // Step 3: Subscribe to real-time updates (optimized)
    let latestTimestamp = cacheService.getLatestTimestamp()

    taskService.subscribeToTasks(
      userId: currentUserId,
      afterTimestamp: latestTimestamp
    ) { [weak self] newTasks, isIncremental in
      guard let self = self else { return }

      if isIncremental {
        // Merge new tasks with cached
        self.tasks = self.cacheService.mergeNewTasks(newTasks)
      } else {
        // Full refresh
        self.tasks = newTasks
        self.cacheService.setCachedTasks(newTasks)
      }
    }
  }
}
```

---

### 3.2 Task Cache Service

**Implementation:**

```swift
class TaskCacheService {
  private let cacheVersion = "1.1"
  private let cacheAge: TimeInterval = 24 * 60 * 60  // 24 hours
  private let userDefaults = UserDefaults.standard

  // MARK: - Cache Keys

  private func tasksKey(userId: String, orgId: String) -> String {
    return "focal_tasks_\(cacheVersion)_\(orgId)_\(userId)"
  }

  private func teamTasksKey(orgId: String) -> String {
    return "focal_team_tasks_\(cacheVersion)_\(orgId)"
  }

  private func timestampKey(userId: String, orgId: String) -> String {
    return "focal_tasks_timestamp_\(orgId)_\(userId)"
  }

  // MARK: - Cache Operations

  func getCachedTasks(userId: String, orgId: String) -> [Task]? {
    guard let data = userDefaults.data(forKey: tasksKey(userId: userId, orgId: orgId)) else {
      return nil
    }

    do {
      let cachedData = try JSONDecoder().decode(CachedTaskData.self, from: data)

      // Check expiration
      if Date().timeIntervalSince(cachedData.cachedAt) > cacheAge {
        clearCache(userId: userId, orgId: orgId)
        return nil
      }

      return cachedData.tasks
    } catch {
      print("Failed to decode cached tasks: \(error)")
      return nil
    }
  }

  func setCachedTasks(_ tasks: [Task], userId: String, orgId: String) {
    let cachedData = CachedTaskData(
      tasks: tasks,
      cachedAt: Date(),
      version: cacheVersion
    )

    do {
      let data = try JSONEncoder().encode(cachedData)
      userDefaults.set(data, forKey: tasksKey(userId: userId, orgId: orgId))

      // Update timestamp
      if let latestTask = tasks.max(by: { $0.updatedAt < $1.updatedAt }) {
        setLatestTimestamp(latestTask.updatedAt, userId: userId, orgId: orgId)
      }
    } catch {
      print("Failed to cache tasks: \(error)")
    }
  }

  func clearOrganizationCache(orgId: String) {
    // Clear all cache keys containing this org ID
    let allKeys = userDefaults.dictionaryRepresentation().keys
    let orgKeys = allKeys.filter { $0.contains(orgId) }

    for key in orgKeys {
      userDefaults.removeObject(forKey: key)
    }
  }

  func clearCache(userId: String, orgId: String) {
    userDefaults.removeObject(forKey: tasksKey(userId: userId, orgId: orgId))
    userDefaults.removeObject(forKey: timestampKey(userId: userId, orgId: orgId))
  }

  // MARK: - Timestamp Management

  func getLatestTimestamp(userId: String, orgId: String) -> Timestamp? {
    guard let seconds = userDefaults.object(forKey: timestampKey(userId: userId, orgId: orgId)) as? Int64 else {
      return nil
    }
    return Timestamp(seconds: seconds, nanoseconds: 0)
  }

  private func setLatestTimestamp(_ timestamp: Timestamp, userId: String, orgId: String) {
    userDefaults.set(timestamp.seconds, forKey: timestampKey(userId: userId, orgId: orgId))
  }

  // MARK: - Merge Operations

  func mergeNewTasks(_ newTasks: [Task]) -> [Task] {
    // Implementation depends on your merge strategy
    // Example: Replace existing tasks with same ID, append new ones
    var existingTasks = tasks  // Assume tasks is stored somewhere

    for newTask in newTasks {
      if let index = existingTasks.firstIndex(where: { $0.id == newTask.id }) {
        existingTasks[index] = newTask
      } else {
        existingTasks.append(newTask)
      }
    }

    return existingTasks
  }
}

// MARK: - Supporting Types

struct CachedTaskData: Codable {
  let tasks: [Task]
  let cachedAt: Date
  let version: String
}
```

---

### 3.3 Read Counter Integration

**Implementation:**

```swift
class ReadCounter {
  static let shared = ReadCounter()

  private var reads: [ReadOperation] = []
  private var cacheHits: [CacheOperation] = []
  private var cacheMisses: [CacheOperation] = []

  // MARK: - Recording Methods

  func recordRead(
    operation: String,
    collection: String,
    component: String,
    count: Int
  ) {
    let read = ReadOperation(
      operation: operation,
      collection: collection,
      component: component,
      count: count,
      timestamp: Date()
    )
    reads.append(read)

    print("📖 Firestore Read: \(collection).\(operation) in \(component) (\(count) docs)")
  }

  func recordCacheHit(
    collection: String,
    component: String,
    savedReads: Int
  ) {
    let hit = CacheOperation(
      collection: collection,
      component: component,
      count: savedReads,
      timestamp: Date()
    )
    cacheHits.append(hit)

    print("✅ Cache Hit: \(collection) in \(component) (saved \(savedReads) reads)")
  }

  func recordCacheMiss(
    collection: String,
    component: String
  ) {
    let miss = CacheOperation(
      collection: collection,
      component: component,
      count: 0,
      timestamp: Date()
    )
    cacheMisses.append(miss)

    print("❌ Cache Miss: \(collection) in \(component)")
  }

  // MARK: - Statistics

  func getTodayStats() -> ReadStats {
    let today = Calendar.current.startOfDay(for: Date())
    let todayReads = reads.filter { $0.timestamp >= today }
    let todayHits = cacheHits.filter { $0.timestamp >= today }
    let todayMisses = cacheMisses.filter { $0.timestamp >= today }

    let totalReads = todayReads.reduce(0) { $0 + $1.count }
    let savedReads = todayHits.reduce(0) { $0 + $1.count }

    return ReadStats(
      totalReads: totalReads,
      savedReads: savedReads,
      cacheHitRate: todayHits.count > 0 ? Double(todayHits.count) / Double(todayHits.count + todayMisses.count) : 0
    )
  }
}

struct ReadOperation {
  let operation: String
  let collection: String
  let component: String
  let count: Int
  let timestamp: Date
}

struct CacheOperation {
  let collection: String
  let component: String
  let count: Int
  let timestamp: Date
}

struct ReadStats {
  let totalReads: Int
  let savedReads: Int
  let cacheHitRate: Double

  var displayString: String {
    """
    📊 Today's Stats:
    - Total Reads: \(totalReads)
    - Saved Reads: \(savedReads)
    - Cache Hit Rate: \(Int(cacheHitRate * 100))%
    """
  }
}
```

**Usage Example:**
```swift
// Cache hit
if let cachedTasks = cacheService.getCachedTasks() {
  readCounter.recordCacheHit("tasks", "TaskListView", cachedTasks.count)
}

// Cache miss
readCounter.recordCacheMiss("tasks", "TaskListView")

// Firestore read
let snapshot = try await firestore.collection("tasks").getDocuments()
readCounter.recordRead("query", "tasks", "fetchUserTasks", snapshot.documents.count)
```

---

### 3.4 Optimized Real-Time Listeners

**Key Principle:** Only fetch data updated AFTER the cached timestamp

**User Tasks Listener:**
```swift
func subscribeToUserTasks(
  userId: String,
  orgId: String,
  afterTimestamp: Timestamp?,
  completion: @escaping ([Task], Bool) -> Void
) -> ListenerRegistration {

  // Query 1: Tasks assigned to user
  var assignedQuery = firestore.collection("tasks")
    .whereField("organizationID", isEqualTo: orgId)
    .whereField("assignedTo", arrayContains: userId)
    .order(by: "updatedAt", descending: true)

  // Query 2: Tasks created by user
  var createdQuery = firestore.collection("tasks")
    .whereField("organizationID", isEqualTo: orgId)
    .whereField("createdBy", isEqualTo: userId)
    .order(by: "updatedAt", descending: true)

  // Optimization: Only fetch tasks updated after cache timestamp
  if let timestamp = afterTimestamp {
    assignedQuery = assignedQuery.whereField("updatedAt", isGreaterThan: timestamp)
    createdQuery = createdQuery.whereField("updatedAt", isGreaterThan: timestamp)
  }

  // Note: Firestore doesn't support OR queries directly
  // You'll need to combine results from both queries

  let listener = assignedQuery.addSnapshotListener { snapshot, error in
    guard let documents = snapshot?.documents else { return }

    let tasks = documents.compactMap { try? $0.data(as: Task.self) }
    let isIncremental = afterTimestamp != nil

    ReadCounter.shared.recordRead(
      operation: "listener",
      collection: "tasks",
      component: "subscribeToUserTasks",
      count: documents.count
    )

    completion(tasks, isIncremental)
  }

  return listener
}
```

---

## 4. UI Components & Views

### 4.1 Task Panel (Side Panel)

**Design:** Slide-in panel from right side of screen

**Features:**
- Renders as overlay (full-screen modal background)
- Two modes: List View and Detail View
- Swipe gesture to dismiss (iOS)

**List View Components:**

1. **Header:**
   - User selector: "My Tasks" | "All Tasks" | Specific user
   - Close button (X)

2. **Quick Add Form:**
   - Title input (compact)
   - Due date picker (inline)
   - Priority selector (compact)
   - Add button
   - Auto-assigns to current user
   - Auto-sets status to "todo"

3. **Search Bar:**
   - Debounced search (300ms delay)
   - Searches title, description, assignees

4. **Filter Tabs:**
   - All
   - Today (due today)
   - Urgent (priority = urgent OR overdue)
   - Completed (today only)

5. **Task List:**
   - Drag-and-drop reorderable
   - Pull-to-refresh
   - Infinite scroll (if paginated)

6. **Empty States:**
   - No tasks: "No tasks yet" with "Create Task" CTA
   - No search results: "No tasks found"
   - No tasks today: "You're all caught up!"

7. **Footer:**
   - "View all tasks" button (navigates to Tasks Page)

**Task Panel Item:**
```swift
struct TaskPanelRow: View {
  let task: Task
  let onToggleComplete: () -> Void
  let onTap: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      // Checkbox
      Button(action: onToggleComplete) {
        Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
          .foregroundColor(task.status == .completed ? .green : .gray)
      }

      VStack(alignment: .leading, spacing: 4) {
        // Priority indicator + Title
        HStack(spacing: 6) {
          Rectangle()
            .fill(task.priority.color)
            .frame(width: 3, height: 16)

          Text(task.title)
            .font(.body)
            .strikethrough(task.status == .completed)
        }

        // Metadata row
        HStack(spacing: 8) {
          // Due date
          if let dueDate = task.dueDate {
            Label(
              dueDate.formatted(.relative(presentation: .named)),
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
          }

          // Comments count
          if task.commentCount > 0 {
            Label("\(task.commentCount)", systemImage: "bubble.left")
              .font(.caption)
          }
        }
      }

      Spacer()

      // Quick actions menu
      Menu {
        Button("View Details") { onTap() }
        Button("Duplicate") { /* duplicate */ }
        Button("Delete", role: .destructive) { /* delete */ }
      } label: {
        Image(systemName: "ellipsis")
      }
    }
    .padding()
    .background(Color(.systemBackground))
    .onTapGesture(perform: onTap)
  }
}
```

---

### 4.2 Task Panel Detail View

**Header:**
- Back button (← return to list)
- Task title (large, bold)
- Priority badge
- Completion badge (if completed)
- Watch/Unwatch button (heart icon)

**Tab Navigation:**
1. Details
2. Subtasks
3. Comments
4. Activity
5. Attachments
6. Time

**Details Tab (View Mode):**
```swift
struct TaskDetailView: View {
  @StateObject var viewModel: TaskDetailViewModel
  @State private var isEditing = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Description
        if let description = viewModel.task.description, !description.isEmpty {
          HTMLTextView(html: description)
        }

        // Priority
        DetailRow(label: "Priority") {
          PriorityBadge(priority: viewModel.task.priority)
        }

        // Status
        DetailRow(label: "Status") {
          StatusBadge(status: viewModel.task.status)
        }

        // Due Date
        DetailRow(label: "Due Date") {
          if let dueDate = viewModel.task.dueDate {
            Text(dueDate.formatted(date: .abbreviated, time: .omitted))
          } else {
            Text("No due date")
              .foregroundColor(.secondary)
          }
        }

        // Estimated Hours
        DetailRow(label: "Estimated Hours") {
          Text("\(viewModel.task.estimatedHours, specifier: "%.1f") hours")
        }

        // Assigned To
        DetailRow(label: "Assigned To") {
          HStack {
            ForEach(viewModel.assignees) { user in
              UserAvatar(user: user, size: 32)
            }
          }
        }

        // Workflow/Session Link
        if viewModel.task.type == .workflow {
          DetailRow(label: "Workflow") {
            VStack(alignment: .leading) {
              Text(viewModel.task.workflowName ?? "Unknown")
              Text(viewModel.task.workflowStepName ?? "Unknown step")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        // Metadata
        VStack(alignment: .leading, spacing: 4) {
          Text("Created \(viewModel.task.createdAt.formatted(.relative(presentation: .named)))")
            .font(.caption)
            .foregroundColor(.secondary)

          Text("Last updated \(viewModel.task.updatedAt.formatted(.relative(presentation: .named)))")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding()
    }

    // Footer
    HStack {
      Button("Edit") {
        isEditing = true
      }

      Spacer()

      if viewModel.task.status != .completed {
        Button("Complete") {
          Task {
            await viewModel.completeTask()
          }
        }
        .buttonStyle(.borderedProminent)
      }

      if viewModel.canDelete {
        Button("Delete", role: .destructive) {
          Task {
            await viewModel.deleteTask()
          }
        }
      }
    }
    .padding()
    .sheet(isPresented: $isEditing) {
      TaskEditView(task: viewModel.task)
    }
  }
}
```

**Subtasks Tab:**
```swift
struct SubtasksTab: View {
  @StateObject var viewModel: TaskDetailViewModel
  @State private var newSubtaskTitle = ""

  var body: some View {
    VStack {
      // Add new subtask
      HStack {
        TextField("Add subtask...", text: $newSubtaskTitle)
          .textFieldStyle(.roundedBorder)

        Button("Add") {
          Task {
            await viewModel.addSubtask(title: newSubtaskTitle)
            newSubtaskTitle = ""
          }
        }
        .disabled(newSubtaskTitle.isEmpty)
      }
      .padding()

      // Subtasks list
      List {
        ForEach(viewModel.task.subtasks) { subtask in
          HStack {
            Button(action: {
              Task {
                await viewModel.toggleSubtask(subtask.id)
              }
            }) {
              Image(systemName: subtask.completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(subtask.completed ? .green : .gray)
            }

            Text(subtask.title)
              .strikethrough(subtask.completed)

            Spacer()

            if subtask.completed, let completedAt = subtask.completedAt {
              Text(completedAt.formatted(.relative(presentation: .numeric)))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        .onDelete { indexSet in
          Task {
            await viewModel.deleteSubtasks(at: indexSet)
          }
        }
      }
    }
  }
}
```

**Comments Tab:**
```swift
struct CommentsTab: View {
  @StateObject var viewModel: TaskDetailViewModel
  @State private var newComment = ""

  var body: some View {
    VStack {
      // Comments list
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          ForEach(viewModel.comments) { comment in
            CommentView(comment: comment)
          }
        }
        .padding()
      }

      // Comment input
      HStack(alignment: .bottom) {
        TextField("Add a comment...", text: $newComment, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(1...5)

        Button(action: {
          Task {
            await viewModel.addComment(text: newComment)
            newComment = ""
          }
        }) {
          Image(systemName: "paperplane.fill")
        }
        .disabled(newComment.isEmpty)
      }
      .padding()
    }
  }
}

struct CommentView: View {
  let comment: Comment

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      UserAvatar(userId: comment.userId, size: 36)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(comment.userName)
            .fontWeight(.semibold)

          Text(comment.createdAt.formatted(.relative(presentation: .named)))
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Text(comment.text)
          .font(.body)

        // Attachments
        if !comment.attachments.isEmpty {
          ScrollView(.horizontal) {
            HStack {
              ForEach(comment.attachments, id: \.fileName) { attachment in
                AttachmentThumbnail(attachment: attachment)
              }
            }
          }
        }
      }
    }
  }
}
```

---

### 4.3 Tasks Page (Full Page View)

**Header:**
- Title: "Tasks" with count badge
- View mode toggle: List | Board | Calendar
- New Task button (+)
- Export button (CSV/PDF)

**Statistics Cards:**
```swift
struct TaskStatsView: View {
  let stats: TaskStatistics

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 16) {
        StatCard(
          title: "To Do",
          count: stats.todoCount,
          color: .blue
        )

        StatCard(
          title: "In Progress",
          count: stats.inProgressCount,
          color: .orange
        )

        StatCard(
          title: "Completed",
          count: stats.completedCount,
          color: .green
        )

        StatCard(
          title: "Overdue",
          count: stats.overdueCount,
          color: .red
        )
      }
      .padding(.horizontal)
    }
  }
}
```

**Filters Sidebar:**
```swift
struct TaskFiltersView: View {
  @Binding var filters: TaskFilters

  var body: some View {
    Form {
      Section("Search") {
        TextField("Search tasks...", text: $filters.searchQuery)
      }

      Section("Assignee") {
        Picker("Show tasks", selection: $filters.assigneeFilter) {
          Text("My Tasks").tag(AssigneeFilter.me)
          Text("All Team Tasks").tag(AssigneeFilter.all)
        }
      }

      Section("Status") {
        ForEach(TaskStatus.allCases, id: \.self) { status in
          Toggle(status.label, isOn: Binding(
            get: { filters.statuses.contains(status) },
            set: { isOn in
              if isOn {
                filters.statuses.insert(status)
              } else {
                filters.statuses.remove(status)
              }
            }
          ))
        }
      }

      Section("Priority") {
        ForEach(TaskPriority.allCases, id: \.self) { priority in
          Toggle(priority.label, isOn: Binding(
            get: { filters.priorities.contains(priority) },
            set: { isOn in
              if isOn {
                filters.priorities.insert(priority)
              } else {
                filters.priorities.remove(priority)
              }
            }
          ))
        }
      }

      Section("Type") {
        ForEach(TaskType.allCases, id: \.self) { type in
          Toggle(type.label, isOn: Binding(
            get: { filters.types.contains(type) },
            set: { isOn in
              if isOn {
                filters.types.insert(type)
              } else {
                filters.types.remove(type)
              }
            }
          ))
        }
      }

      Section {
        Button("Reset Filters") {
          filters = TaskFilters()
        }
      }
    }
  }
}
```

**Board View (Kanban):**
```swift
struct TaskBoardView: View {
  @StateObject var viewModel: TasksViewModel

  var body: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .top, spacing: 16) {
        TaskColumn(
          title: "To Do",
          tasks: viewModel.todoTasks,
          color: .blue
        )

        TaskColumn(
          title: "In Progress",
          tasks: viewModel.inProgressTasks,
          color: .orange
        )

        TaskColumn(
          title: "On Hold",
          tasks: viewModel.onHoldTasks,
          color: .red
        )

        TaskColumn(
          title: "Completed",
          tasks: viewModel.completedTasks,
          color: .green
        )
      }
      .padding()
    }
  }
}

struct TaskColumn: View {
  let title: String
  let tasks: [Task]
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header
      HStack {
        Text(title)
          .font(.headline)

        Spacer()

        Text("\(tasks.count)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      // Tasks
      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(tasks) { task in
            TaskCard(task: task)
          }
        }
      }
    }
    .frame(width: 280)
    .padding()
    .background(Color(.secondarySystemBackground))
    .cornerRadius(12)
  }
}
```

---

### 4.4 Create Task Modal

```swift
struct CreateTaskView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject var viewModel: CreateTaskViewModel

  @State private var title = ""
  @State private var description = ""
  @State private var type: TaskType = .general
  @State private var priority: TaskPriority = .medium
  @State private var dueDate: Date?
  @State private var estimatedHours: Double = 0
  @State private var selectedAssignees: Set<User> = []
  @State private var subtasks: [String] = []

  var body: some View {
    NavigationView {
      Form {
        // Basic Info
        Section("Basic Information") {
          TextField("Task title", text: $title)

          TextEditor(text: $description)
            .frame(height: 100)
        }

        // Type
        Section("Type") {
          Picker("Type", selection: $type) {
            ForEach(TaskType.allCases, id: \.self) { type in
              Text(type.label).tag(type)
            }
          }
          .pickerStyle(.segmented)

          if type == .session {
            Picker("Session", selection: $viewModel.selectedSession) {
              ForEach(viewModel.sessions) { session in
                Text(session.name).tag(session)
              }
            }
          } else if type == .workflow {
            Picker("Workflow", selection: $viewModel.selectedWorkflow) {
              ForEach(viewModel.workflows) { workflow in
                Text(workflow.name).tag(workflow)
              }
            }

            if let workflow = viewModel.selectedWorkflow {
              Picker("Step", selection: $viewModel.selectedStep) {
                ForEach(workflow.steps) { step in
                  Text(step.name).tag(step)
                }
              }
            }
          }
        }

        // Timeline & Priority
        Section("Details") {
          Picker("Priority", selection: $priority) {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
              Label(priority.label, systemImage: "flag.fill")
                .foregroundColor(priority.color)
                .tag(priority)
            }
          }

          DatePicker(
            "Due Date",
            selection: Binding(
              get: { dueDate ?? Date() },
              set: { dueDate = $0 }
            ),
            displayedComponents: [.date]
          )

          // Quick date presets
          HStack {
            Button("Today") { dueDate = Date() }
            Button("Tomorrow") { dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) }
            Button("Next Week") { dueDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) }
            Button("Clear") { dueDate = nil }
          }
          .buttonStyle(.bordered)
          .font(.caption)

          HStack {
            Text("Estimated Hours")
            TextField("Hours", value: $estimatedHours, format: .number)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
          }
        }

        // Assignment
        Section("Assignment") {
          // Multi-select user picker
          ForEach(viewModel.teamMembers) { user in
            Toggle(isOn: Binding(
              get: { selectedAssignees.contains(user) },
              set: { isOn in
                if isOn {
                  selectedAssignees.insert(user)
                } else {
                  selectedAssignees.remove(user)
                }
              }
            )) {
              HStack {
                UserAvatar(user: user, size: 32)
                Text(user.fullName)
              }
            }
          }
        }

        // Subtasks
        Section("Subtasks") {
          ForEach(subtasks.indices, id: \.self) { index in
            HStack {
              TextField("Subtask", text: $subtasks[index])

              Button(action: {
                subtasks.remove(at: index)
              }) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundColor(.red)
              }
            }
          }

          Button("Add Subtask") {
            subtasks.append("")
          }
        }
      }
      .navigationTitle("New Task")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            Task {
              await viewModel.createTask(
                title: title,
                description: description,
                type: type,
                priority: priority,
                dueDate: dueDate,
                estimatedHours: estimatedHours,
                assignees: Array(selectedAssignees),
                subtasks: subtasks.filter { !$0.isEmpty }
              )
              dismiss()
            }
          }
          .disabled(!isValid)
        }
      }
    }
  }

  private var isValid: Bool {
    !title.isEmpty &&
    (type != .session || viewModel.selectedSession != nil) &&
    (type != .workflow || (viewModel.selectedWorkflow != nil && viewModel.selectedStep != nil))
  }
}
```

---

## 5. Permissions & Access Control

### 5.1 Permission Matrix

| Action | Admin | Manager | Task Creator | Assignee | Other |
|--------|-------|---------|--------------|----------|-------|
| View Own Tasks | ✅ | ✅ | ✅ | ✅ | ✅ |
| View Team Tasks | ✅ | ✅ | ❌ | ❌ | ❌ |
| Create Task | ✅ | ✅ | ✅ | ✅ | ✅ |
| Edit Own Task | ✅ | ✅ | ✅ | ✅ | ❌ |
| Edit Team Task | ✅ | ✅ | ❌ | ✅ | ❌ |
| Delete Own Task (Not Completed) | ✅ | ✅ | ✅ | ❌ | ❌ |
| Delete Own Task (Completed) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Delete Team Task | ✅ | ❌ | ❌ | ❌ | ❌ |
| Assign to Anyone | ✅ | ✅ | ✅ | ❌ | ❌ |
| Assign to Self | ✅ | ✅ | ✅ | ✅ | ✅ |

### 5.2 Permission Check Implementation

```swift
struct TaskPermissions {
  let user: User
  let task: Task

  var canView: Bool {
    // Everyone can view tasks in their organization
    task.organizationID == user.organizationID &&
    (
      // Admins and managers can view all
      user.role.isAdminOrManager ||
      // Task is assigned to user
      task.assignedTo.contains(user.id) ||
      // User created the task
      task.createdBy == user.id
    )
  }

  var canEdit: Bool {
    guard task.organizationID == user.organizationID else { return false }

    return user.role == .admin ||
           user.role == .manager ||
           task.createdBy == user.id ||
           task.assignedTo.contains(user.id)
  }

  var canDelete: Bool {
    guard task.organizationID == user.organizationID else { return false }

    // Only admins can delete completed tasks
    if task.status == .completed {
      return user.role == .admin
    }

    // Admins and managers can delete any non-completed task
    if user.role.isAdminOrManager {
      return true
    }

    // Users can only delete their own non-completed tasks
    return task.createdBy == user.id
  }

  var canAssign: Bool {
    return user.role.isAdminOrManager || task.createdBy == user.id
  }

  var canComment: Bool {
    return canView
  }

  var canWatch: Bool {
    return canView
  }
}

extension UserRole {
  var isAdminOrManager: Bool {
    self == .admin || self == .manager
  }
}
```

---

## 6. Search, Filtering & Sorting

### 6.1 Search Implementation

```swift
class TaskSearchService {
  func searchTasks(query: String, in tasks: [Task], users: [User]) -> [Task] {
    let lowercased = query.lowercased()

    return tasks.filter { task in
      // Search in title
      task.title.lowercased().contains(lowercased) ||

      // Search in description
      (task.description?.lowercased().contains(lowercased) ?? false) ||

      // Search in assignee names
      task.assignedTo.contains { userId in
        users.first(where: { $0.id == userId })?.fullName.lowercased().contains(lowercased) ?? false
      } ||

      // Search in workflow name
      (task.workflowName?.lowercased().contains(lowercased) ?? false) ||

      // Search in session name
      (task.sessionName?.lowercased().contains(lowercased) ?? false)
    }
  }
}
```

**Debounced Search:**
```swift
class TaskSearchViewModel: ObservableObject {
  @Published var searchQuery = ""
  @Published var searchResults: [Task] = []

  private var debounceTask: Task<Void, Never>?

  init() {
    $searchQuery
      .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
      .sink { [weak self] query in
        self?.performSearch(query)
      }
      .store(in: &cancellables)
  }

  private func performSearch(_ query: String) {
    guard !query.isEmpty else {
      searchResults = []
      return
    }

    searchResults = searchService.searchTasks(query: query, in: allTasks, users: teamMembers)
  }
}
```

---

### 6.2 Filtering

```swift
struct TaskFilters: Equatable {
  enum AssigneeFilter: Equatable {
    case me
    case all
    case specific(userId: String)
  }

  var assigneeFilter: AssigneeFilter = .me
  var statuses: Set<TaskStatus> = [.todo, .inProgress, .onHold, .completed]
  var priorities: Set<TaskPriority> = []
  var types: Set<TaskType> = []
  var dueAfter: Date?
  var dueBefore: Date?
  var searchQuery: String = ""

  func apply(to tasks: [Task], currentUserId: String) -> [Task] {
    var filtered = tasks

    // Assignee filter
    switch assigneeFilter {
    case .me:
      filtered = filtered.filter { task in
        task.assignedTo.contains(currentUserId) ||
        (task.createdBy == currentUserId && task.assignedTo.isEmpty)
      }
    case .all:
      break  // No filtering
    case .specific(let userId):
      filtered = filtered.filter { task in
        task.assignedTo.contains(userId) ||
        (task.createdBy == userId && task.assignedTo.isEmpty)
      }
    }

    // Status filter
    if !statuses.isEmpty {
      filtered = filtered.filter { statuses.contains($0.status) }
    }

    // Priority filter
    if !priorities.isEmpty {
      filtered = filtered.filter { priorities.contains($0.priority) }
    }

    // Type filter
    if !types.isEmpty {
      filtered = filtered.filter { types.contains($0.type) }
    }

    // Date range filter
    if let after = dueAfter {
      filtered = filtered.filter { task in
        guard let dueDate = task.dueDate else { return false }
        return dueDate >= after
      }
    }

    if let before = dueBefore {
      filtered = filtered.filter { task in
        guard let dueDate = task.dueDate else { return false }
        return dueDate <= before
      }
    }

    return filtered
  }
}
```

---

### 6.3 Sorting

```swift
class TaskSortService {
  enum SortOption {
    case smart  // Overdue first, then by due date, priority, created date
    case dueDate
    case priority
    case createdDate
    case updatedDate
    case title
  }

  func sort(_ tasks: [Task], by option: SortOption) -> [Task] {
    switch option {
    case .smart:
      return smartSort(tasks)
    case .dueDate:
      return tasks.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    case .priority:
      return tasks.sorted { $0.priority.rank < $1.priority.rank }
    case .createdDate:
      return tasks.sorted { $0.createdAt > $1.createdAt }
    case .updatedDate:
      return tasks.sorted { $0.updatedAt > $1.updatedAt }
    case .title:
      return tasks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
  }

  private func smartSort(_ tasks: [Task]) -> [Task] {
    return tasks.sorted { a, b in
      // 1. Overdue tasks first
      let aOverdue = a.isOverdue
      let bOverdue = b.isOverdue
      if aOverdue != bOverdue {
        return aOverdue
      }

      // 2. By due date (earliest first)
      if let aDate = a.dueDate, let bDate = b.dueDate {
        if aDate != bDate {
          return aDate < bDate
        }
      } else if a.dueDate != nil {
        return true
      } else if b.dueDate != nil {
        return false
      }

      // 3. By priority (urgent → high → medium → low)
      if a.priority != b.priority {
        return a.priority.rank < b.priority.rank
      }

      // 4. By created date (newest first)
      return a.createdAt > b.createdAt
    }
  }
}

extension TaskPriority {
  var rank: Int {
    switch self {
    case .urgent: return 0
    case .high: return 1
    case .medium: return 2
    case .low: return 3
    }
  }
}

extension Task {
  var isOverdue: Bool {
    guard let dueDate = dueDate else { return false }
    return dueDate < Date() && status != .completed
  }
}
```

---

## 7. Notifications & Email

### 7.1 In-App Notifications

**Notification Types:**
```swift
enum TaskNotificationType: String {
  case mention = "mention"
  case assignment = "assignment"
  case comment = "comment"
  case statusChange = "status_change"
  case dueDateSoon = "due_date_soon"
  case dueDateOverdue = "due_date_overdue"
  case taskCompleted = "task_completed"
  case priorityChange = "priority_change"
  case subtaskCompleted = "subtask_completed"
}
```

**Create Notification:**
```swift
func createTaskNotification(
  userId: String,
  taskId: String,
  type: TaskNotificationType,
  title: String,
  message: String,
  triggeredBy: String
) async throws {
  let notification = TaskNotification(
    id: UUID().uuidString,
    userId: userId,
    organizationID: currentOrgId,
    taskId: taskId,
    type: type.rawValue,
    title: title,
    message: message,
    triggeredBy: triggeredBy,
    data: [:],
    read: false,
    readAt: nil,
    createdAt: Timestamp.now()
  )

  try await firestore
    .collection("taskNotifications")
    .document(notification.id)
    .setData(notification.dictionary)

  // Send push notification
  await sendPushNotification(
    to: userId,
    title: title,
    body: message,
    data: ["taskId": taskId, "type": type.rawValue]
  )
}
```

**Notification Examples:**

**Assignment:**
```swift
await createTaskNotification(
  userId: assigneeId,
  taskId: task.id,
  type: .assignment,
  title: "New Task Assigned",
  message: "\(currentUser.fullName) assigned you to \(task.title)",
  triggeredBy: currentUserId
)
```

**Mention:**
```swift
await createTaskNotification(
  userId: mentionedUserId,
  taskId: task.id,
  type: .mention,
  title: "Mentioned in Task",
  message: "\(currentUser.fullName) mentioned you in \(task.title)",
  triggeredBy: currentUserId
)
```

**Due Date Soon:**
```swift
await createTaskNotification(
  userId: task.createdBy,
  taskId: task.id,
  type: .dueDateSoon,
  title: "Task Due Soon",
  message: "\(task.title) is due tomorrow",
  triggeredBy: "system"
)
```

---

### 7.2 Push Notifications

**APNs Integration:**
```swift
class PushNotificationService {
  func sendPushNotification(
    to userId: String,
    title: String,
    body: String,
    data: [String: String]
  ) async {
    // Get user's FCM token
    guard let token = try? await getUserFCMToken(userId: userId) else {
      return
    }

    // Send via Firebase Cloud Messaging
    let message = [
      "token": token,
      "notification": [
        "title": title,
        "body": body
      ],
      "data": data,
      "apns": [
        "payload": [
          "aps": [
            "sound": "default",
            "badge": 1
          ]
        ]
      ]
    ]

    try? await functions.httpsCallable("sendPushNotification").call(message)
  }
}
```

---

### 7.3 Email Notifications

**Firebase Cloud Function (Reference):**
```javascript
// This would be implemented in Firebase Cloud Functions
exports.sendTaskEmail = functions.https.onCall(async (data, context) => {
  const { to, subject, templateId, templateData } = data;

  // Use SendGrid, Mailgun, or similar service
  await sendEmail({
    to,
    subject,
    template: templateId,
    data: templateData
  });
});
```

**iOS Trigger:**
```swift
func sendTaskAssignmentEmail(task: Task, assignee: User) async {
  let emailData: [String: Any] = [
    "to": assignee.email,
    "subject": "You've been assigned to: \(task.title)",
    "templateId": "task_assignment",
    "templateData": [
      "assigneeName": assignee.fullName,
      "assignerName": currentUser.fullName,
      "taskTitle": task.title,
      "taskDescription": task.description ?? "",
      "dueDate": task.dueDate?.formatted() ?? "No due date",
      "taskLink": generateTaskDeepLink(task.id)
    ]
  ]

  try? await functions.httpsCallable("sendTaskEmail").call(emailData)
}
```

---

## 8. Time Tracking Integration

### 8.1 Time Entry Structure

```swift
struct TimeEntry: Identifiable, Codable {
  let id: String
  let userId: String
  let organizationID: String
  let taskId: String?           // Optional - can track without task
  let sessionId: String?        // Optional
  let workflowId: String?       // Optional
  let startTime: Timestamp
  var endTime: Timestamp?       // Null if still active
  var duration: TimeInterval    // Calculated in seconds
  let notes: String?
  let createdAt: Timestamp
  let updatedAt: Timestamp

  var isActive: Bool {
    endTime == nil
  }

  var formattedDuration: String {
    let hours = Int(duration) / 3600
    let minutes = (Int(duration) % 3600) / 60
    let seconds = Int(duration) % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
  }
}
```

---

### 8.2 Auto-Tracking on Status Change

**Implementation in Task Update:**
```swift
func updateTaskStatus(_ taskId: String, to newStatus: TaskStatus) async throws {
  let task = try await getTask(taskId)
  let oldStatus = task.status

  // Update task status
  try await firestore
    .collection("tasks").document(taskId)
    .updateData(["status": newStatus.rawValue])

  // Handle time tracking
  if newStatus == .inProgress && oldStatus != .inProgress {
    try await handleStartTracking(taskId: taskId)
  } else if oldStatus == .inProgress && newStatus != .inProgress {
    try await handleStopTracking(taskId: taskId)
  }
}

private func handleStartTracking(taskId: String) async throws {
  // Check for existing active entry
  if let activeEntry = try await getCurrentTimeEntry(userId: currentUserId) {
    // Add task to existing entry
    try await firestore
      .collection("timeEntries").document(activeEntry.id)
      .updateData(["taskId": taskId])
  } else {
    // Start new entry
    let entry = TimeEntry(
      id: UUID().uuidString,
      userId: currentUserId,
      organizationID: currentOrgId,
      taskId: taskId,
      sessionId: nil,
      workflowId: nil,
      startTime: Timestamp.now(),
      endTime: nil,
      duration: 0,
      notes: nil,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now()
    )

    try await firestore
      .collection("timeEntries").document(entry.id)
      .setData(entry.dictionary)
  }

  // Log activity
  try await logActivity(
    type: .TIME_LOGGED,
    taskId: taskId,
    metadata: ["action": "auto_started_tracking"]
  )
}

private func handleStopTracking(taskId: String) async throws {
  // Find active entry for this task
  guard let activeEntry = try await getActiveTimeEntry(userId: currentUserId, taskId: taskId) else {
    return
  }

  let endTime = Timestamp.now()
  let duration = endTime.seconds - activeEntry.startTime.seconds

  try await firestore
    .collection("timeEntries").document(activeEntry.id)
    .updateData([
      "endTime": endTime,
      "duration": duration,
      "updatedAt": Timestamp.now()
    ])

  // Log activity
  try await logActivity(
    type: .TIME_LOGGED,
    taskId: taskId,
    metadata: [
      "action": "auto_stopped_tracking",
      "duration": duration
    ]
  )
}
```

---

### 8.3 Time Tracking UI

**Active Time Badge:**
```swift
struct ActiveTimeTrackingBadge: View {
  let task: Task
  @StateObject private var timer = TimeTrackingTimer()

  var body: some View {
    if timer.isTracking {
      HStack(spacing: 4) {
        Circle()
          .fill(Color.red)
          .frame(width: 8, height: 8)

        Text(timer.elapsedTime)
          .font(.caption)
          .monospacedDigit()
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color.red.opacity(0.1))
      .cornerRadius(8)
    }
  }
}

class TimeTrackingTimer: ObservableObject {
  @Published var elapsedTime: String = "00:00:00"
  @Published var isTracking = false

  private var timer: Timer?
  private var startTime: Date?

  func start() {
    startTime = Date()
    isTracking = true

    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.updateElapsedTime()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    isTracking = false
    elapsedTime = "00:00:00"
  }

  private func updateElapsedTime() {
    guard let start = startTime else { return }
    let elapsed = Date().timeIntervalSince(start)

    let hours = Int(elapsed) / 3600
    let minutes = (Int(elapsed) % 3600) / 60
    let seconds = Int(elapsed) % 60

    elapsedTime = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
  }
}
```

---

## 9. Known Issues & Recommendations

### 9.1 Critical Web Bugs (DO NOT REPLICATE)

**Bug #1: Field Naming Inconsistency**
- Web uses both `workflowId` and `workflowID`
- Queries fail silently when using wrong case
- **iOS MUST USE:** Consistent camelCase (`workflowId`, `workflowStepId`, `sessionId`)

**Bug #2: Comment Count Increment**
- Web incorrectly uses `arrayUnion().length`
- **iOS MUST USE:** `FieldValue.increment(1)`

**Bug #3: Missing Permission Check**
- Web doesn't validate permissions before delete in TaskContext
- **iOS MUST:** Always check `canDeleteTask()` before attempting

**Bug #4: No Orphaned Data Cleanup**
- Web doesn't delete comments/attachments when task deleted
- **iOS SHOULD:** Batch delete subcollections and storage files

**Bug #5: Cache Not Cleared on Delete**
- Can cause "ghost tasks" to appear
- **iOS MUST:** Call `clearOrganizationCache()` after every delete

---

### 9.2 Architecture Recommendations

**Use MVVM Pattern:**
```
Models/
  Task.swift
  Comment.swift
  TimeEntry.swift

ViewModels/
  TaskListViewModel.swift
  TaskDetailViewModel.swift
  CreateTaskViewModel.swift

Views/
  Tasks/
    TasksPage.swift
    TaskPanel.swift
    TaskDetailView.swift
    CreateTaskView.swift
    Components/
      TaskRow.swift
      TaskCard.swift
      SubtasksTab.swift
      CommentsTab.swift

Services/
  TaskService.swift
  TaskCacheService.swift
  CommentService.swift
  NotificationService.swift
  ReadCounter.swift

Repositories/
  TaskRepository.swift
  CommentRepository.swift
```

**Use Dependency Injection:**
```swift
@main
struct FocalPointApp: App {
  @StateObject private var appState = AppState()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(appState)
        .environmentObject(appState.taskService)
        .environmentObject(appState.cacheService)
    }
  }
}
```

---

### 9.3 Testing Strategy

**Unit Tests:**
- Task creation/update/delete logic
- Permission checks
- Search and filter algorithms
- Sorting logic
- Cache serialization
- Timestamp handling

**Integration Tests:**
- Firestore operations
- Real-time listeners
- Cache-first loading
- Batch operations

**UI Tests:**
- Task creation flow
- Task editing flow
- Comment adding flow
- Search and filter
- Drag-and-drop reordering

---

## 10. Example Task JSON

```json
{
  "id": "task_abc123",
  "organizationID": "org_xyz789",
  "createdBy": "user_123",
  "title": "Edit photos for Lincoln HS graduation",
  "description": "<p>Edit and color-correct 200 senior portraits</p><ul><li>Apply standard filter</li><li>Remove blemishes</li><li>Export as high-res</li></ul>",
  "type": "session",
  "status": "in_progress",
  "priority": "high",
  "assignedTo": ["user_123", "user_456"],
  "watchers": ["user_123", "user_456", "user_789"],
  "createdAt": { "seconds": 1638234567, "nanoseconds": 890000000 },
  "updatedAt": { "seconds": 1638321000, "nanoseconds": 123000000 },
  "dueDate": { "seconds": 1638407400, "nanoseconds": 0 },
  "startDate": null,
  "completedAt": null,
  "completedBy": null,
  "estimatedHours": 8.5,
  "order": 3,
  "subtasks": [
    {
      "id": "subtask_1638234567890",
      "title": "Apply filters",
      "completed": true,
      "completedAt": { "seconds": 1638307200, "nanoseconds": 0 },
      "completedBy": "user_123"
    },
    {
      "id": "subtask_1638234567891",
      "title": "Remove blemishes",
      "completed": false,
      "completedAt": null,
      "completedBy": null
    },
    {
      "id": "subtask_1638234567892",
      "title": "Export high-res",
      "completed": false,
      "completedAt": null,
      "completedBy": null
    }
  ],
  "commentCount": 5,
  "timeEntryIds": ["time_abc", "time_def"],
  "sessionId": "session_xyz",
  "sessionName": "Lincoln High School",
  "sessionDate": { "seconds": 1638234567, "nanoseconds": 0 }
}
```

---

## 11. Priority & Status Color Schemes

### Priority Colors

```swift
extension TaskPriority {
  var color: Color {
    switch self {
    case .low:
      return Color(hex: "6b7280")      // Gray
    case .medium:
      return Color(hex: "3b82f6")      // Blue
    case .high:
      return Color(hex: "f59e0b")      // Amber
    case .urgent:
      return Color(hex: "ef4444")      // Red
    }
  }

  var label: String {
    switch self {
    case .low: return "Low"
    case .medium: return "Medium"
    case .high: return "High"
    case .urgent: return "Urgent"
    }
  }
}
```

### Status Colors

```swift
extension TaskStatus {
  var color: Color {
    switch self {
    case .todo:
      return Color(hex: "3b82f6")       // Blue
    case .inProgress:
      return Color(hex: "f59e0b")       // Amber
    case .onHold:
      return Color(hex: "ef4444")       // Red
    case .completed:
      return Color(hex: "10b981")       // Green
    case .cancelled:
      return Color(hex: "6b7280")       // Gray
    }
  }

  var label: String {
    switch self {
    case .todo: return "To Do"
    case .inProgress: return "In Progress"
    case .onHold: return "On Hold"
    case .completed: return "Completed"
    case .cancelled: return "Cancelled"
    }
  }
}
```

---

## 12. Conclusion

This specification provides comprehensive technical details for implementing the Task Management system in iOS. Key priorities:

1. **Implement cache-first loading** to prevent excessive Firestore reads
2. **Track all reads** using ReadCounter for cost monitoring
3. **Avoid known bugs** from web implementation
4. **Use consistent field naming** (camelCase throughout)
5. **Implement proper permission checks** before all operations
6. **Clean up orphaned data** on task deletion
7. **Follow Firebase best practices** (offline persistence, optimized listeners, batch writes)

The web implementation is production-ready with real-time collaboration and advanced features. iOS should achieve feature parity while improving upon identified weaknesses.

---

## Questions & Support

For questions about this specification, refer to the web source code:

- `/src/firebase/tasks.js` - Core Firebase operations
- `/src/contexts/TaskContext.jsx` - State management & business logic
- `/src/components/tasks/` - All UI components
- `/src/services/taskCacheService.js` - Caching reference implementation

Good luck with your iOS implementation!
