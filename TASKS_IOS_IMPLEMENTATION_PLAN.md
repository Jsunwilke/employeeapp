# Tasks Feature - iOS Implementation Plan

**Based on**: task_feature.md specification (2,824 lines)
**Target**: Iconik Employee iOS App
**Firestore Collection**: `tasks/` (top-level)

---

## Table of Contents

1. [Data Models](#phase-1-data-models)
2. [Service Layer](#phase-2-service-layer)
3. [UI Components](#phase-3-ui-components)
4. [Advanced Features](#phase-4-advanced-features)
5. [Integration](#phase-5-integration)
6. [Critical Notes](#critical-notes)
7. [Implementation Checklist](#checklist)

---

## PHASE 1: Data Models

### Task Model
**File**: `Iconik Employee/Tasks Feature/Models/TaskModel.swift` (NEW)

```swift
struct Task: Identifiable, Codable {
  // Identity & Ownership
  var id: String
  var organizationID: String
  var createdBy: String

  // Basic Information
  var title: String
  var description: String?        // HTML content
  var type: TaskType              // general | session | workflow

  // Status & Priority
  var status: TaskStatus          // todo | in_progress | on_hold | completed | cancelled
  var priority: TaskPriority      // low | medium | high | urgent

  // Assignment & Collaboration
  var assignedTo: [String]        // User IDs
  var watchers: [String]          // User IDs

  // Dates & Timeline
  var createdAt: Date
  var updatedAt: Date
  var dueDate: Date?
  var startDate: Date?
  var completedAt: Date?
  var completedBy: String?

  // Estimation & Tracking
  var estimatedHours: Double
  var order: Int                  // For drag-and-drop ordering

  // Subtasks
  var subtasks: [Subtask]

  // Comments & Activity
  var commentCount: Int
  var timeEntryIds: [String]

  // Workflow Integration (Optional)
  var workflowId: String?
  var workflowStepId: String?
  var workflowName: String?
  var workflowStepName: String?
  var autoCreated: Bool?
  var syncWithWorkflow: Bool?

  // Session Integration (Optional)
  var sessionId: String?
  var sessionName: String?
  var sessionDate: Date?
}

struct Subtask: Identifiable, Codable {
  var id: String
  var title: String
  var completed: Bool
  var completedAt: Date?
  var completedBy: String?
}

enum TaskType: String, Codable, CaseIterable {
  case general = "general"
  case session = "session"
  case workflow = "workflow"
}

enum TaskStatus: String, Codable, CaseIterable {
  case todo = "todo"
  case inProgress = "in_progress"
  case onHold = "on_hold"
  case completed = "completed"
  case cancelled = "cancelled"
}

enum TaskPriority: String, Codable, CaseIterable {
  case low = "low"
  case medium = "medium"
  case high = "high"
  case urgent = "urgent"
}
```

### Comment Model
**File**: `Iconik Employee/Tasks Feature/Models/CommentModel.swift` (NEW)

```swift
struct TaskComment: Identifiable, Codable {
  var id: String
  var userId: String
  var userName: String
  var text: String
  var mentions: [Mention]
  var attachments: [Attachment]
  var createdAt: Date
  var updatedAt: Date
}

struct Mention: Codable {
  var userId: String
  var userName: String
}

struct Attachment: Codable {
  var fileName: String
  var fileUrl: String
  var fileType: String
  var fileSize: Int
}
```

---

## PHASE 2: Service Layer

### TaskService
**File**: `Iconik Employee/Tasks Feature/Services/TaskService.swift` (NEW)

**CRUD Operations:**

```swift
class TaskService {
  static let shared = TaskService()
  private let db = Firestore.firestore()
  private let cacheService = TaskCacheService.shared

  // CREATE
  func createTask(_ task: Task) async throws -> String {
    // 1. Calculate order (query max order in status)
    // 2. Set default values
    // 3. Create document
    // 4. Clear organization cache (CRITICAL)
    // 5. Log activity
    // 6. Send notifications if assigned
  }

  // READ
  func fetchTask(id: String) async throws -> Task
  func fetchMyTasks(userId: String, orgId: String) async throws -> [Task]
  func fetchTeamTasks(orgId: String) async throws -> [Task]
  func fetchTasksByWorkflow(workflowId: String, stepId: String) async throws -> [Task]
  func fetchTasksBySession(sessionId: String) async throws -> [Task]

  // UPDATE
  func updateTask(id: String, updates: [String: Any]) async throws {
    // 1. Track changes for activity log
    // 2. Update Firestore
    // 3. Handle time tracking auto-start/stop
    // 4. Send notifications for tracked changes
  }

  // DELETE
  func deleteTask(id: String) async throws {
    // 1. Check permissions FIRST
    // 2. Delete task document
    // 3. Clear organization cache (CRITICAL - prevents ghost tasks)
    // 4. TODO: Clean up subcollections (comments, activity)
  }

  // SPECIALIZED OPERATIONS
  func completeTask(id: String) async throws
  func reopenTask(id: String) async throws
  func addSubtask(to taskId: String, title: String) async throws
  func toggleSubtask(taskId: String, subtaskId: String) async throws
  func reorderTask(taskId: String, from: Int, to: Int, status: TaskStatus) async throws
  func moveTask(taskId: String, to newStatus: TaskStatus, at index: Int) async throws

  // REAL-TIME LISTENER (CRITICAL FOR PERFORMANCE)
  func subscribeToUserTasks(
    userId: String,
    orgId: String,
    afterTimestamp: Date?,
    completion: @escaping ([Task], Bool) -> Void
  ) -> ListenerRegistration
}
```

**Key Implementation Notes:**
- **Create**: Must calculate `order` field by querying max order in status
- **Delete**: MUST call `cacheService.clearOrganizationCache()` after delete
- **Update**: Track which fields changed for activity logging
- **Listener**: Only fetch tasks with `updatedAt > afterTimestamp` for efficiency

### CommentService
**File**: `Iconik Employee/Tasks Feature/Services/CommentService.swift` (NEW)

```swift
class CommentService {
  static let shared = CommentService()

  func addComment(taskId: String, text: String) async throws {
    // 1. Extract @mentions from text
    // 2. Create comment document in subcollection
    // 3. Increment task's commentCount using FieldValue.increment(1)
    // 4. Create notifications for mentions
    // 5. Auto-watch task for mentioned users
    // 6. Notify watchers
    // 7. Log activity
  }

  func fetchComments(taskId: String) async throws -> [TaskComment]
  func updateComment(taskId: String, commentId: String, text: String) async throws
  func deleteComment(taskId: String, commentId: String) async throws

  private func extractMentions(from text: String) -> [Mention] {
    // Pattern: @FirstName LastName
    // Lookup users by name
    // Return array of Mention objects
  }
}
```

### TaskCacheService (CRITICAL FOR PERFORMANCE)
**File**: `Iconik Employee/Tasks Feature/Services/TaskCacheService.swift` (NEW)

```swift
class TaskCacheService {
  static let shared = TaskCacheService()

  private let cacheVersion = "1.1"
  private let cacheAge: TimeInterval = 24 * 60 * 60  // 24 hours

  // Cache keys
  private func tasksKey(userId: String, orgId: String) -> String {
    return "focal_tasks_\(cacheVersion)_\(orgId)_\(userId)"
  }

  // CORE OPERATIONS
  func getCachedTasks(userId: String, orgId: String) -> [Task]? {
    // 1. Load from UserDefaults
    // 2. Check expiration (24 hours)
    // 3. Return tasks or nil
  }

  func setCachedTasks(_ tasks: [Task], userId: String, orgId: String) {
    // 1. Encode to JSON
    // 2. Save to UserDefaults with timestamp
    // 3. Update latest timestamp
  }

  func clearOrganizationCache(orgId: String) {
    // CRITICAL: Called after create/delete
    // Clear ALL cache keys containing this org ID
  }

  func getLatestTimestamp(userId: String, orgId: String) -> Date?
  func mergeNewTasks(_ newTasks: [Task], into existing: [Task]) -> [Task]
  func isCacheFresh(userId: String, orgId: String) -> Bool
}

struct CachedTaskData: Codable {
  let tasks: [Task]
  let cachedAt: Date
  let version: String
}
```

### ReadCounter (Cost Monitoring)
**File**: `Iconik Employee/Tasks Feature/Services/ReadCounter.swift` (NEW)

```swift
class ReadCounter {
  static let shared = ReadCounter()

  private var reads: [ReadOperation] = []
  private var cacheHits: [CacheOperation] = []
  private var cacheMisses: [CacheOperation] = []

  func recordRead(
    operation: String,
    collection: String,
    component: String,
    count: Int
  ) {
    // Log: "📖 Firestore Read: tasks.query in TaskListView (25 docs)"
  }

  func recordCacheHit(
    collection: String,
    component: String,
    savedReads: Int
  ) {
    // Log: "✅ Cache Hit: tasks in TaskListView (saved 25 reads)"
  }

  func recordCacheMiss(
    collection: String,
    component: String
  ) {
    // Log: "❌ Cache Miss: tasks in TaskListView"
  }

  func getTodayStats() -> ReadStats {
    // Return total reads, saved reads, cache hit rate
  }
}

struct ReadStats {
  let totalReads: Int
  let savedReads: Int
  let cacheHitRate: Double
}
```

---

## PHASE 3: UI Components

### TasksMainView (Main Tab)
**File**: `Iconik Employee/Tasks Feature/Views/TasksMainView.swift` (NEW)

**Layout:**
```
┌─────────────────────────────────────────┐
│ Tasks                  [Filter] [+ Add] │
├─────────────────────────────────────────┤
│ 📊 Stats: 12 To Do | 5 In Progress     │
├─────────────────────────────────────────┤
│ [My Tasks] [All Tasks] [Team]           │
├─────────────────────────────────────────┤
│ [View: List] [Board] [Calendar]         │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ 🔴 Edit photos for Lincoln HS       │ │
│ │ Due: Tomorrow | High Priority       │ │
│ │ Assigned to: John Smith         ▶  │ │
│ └─────────────────────────────────────┘ │
│ ┌─────────────────────────────────────┐ │
│ │ ⚪ Review contract                  │ │
│ │ Due: Next Week | Medium Priority    │ │
│ │ Assigned to: Me                 ▶  │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**Features:**
- Segmented control: My Tasks | All Tasks | Team
- View mode toggle: List | Board | Calendar
- Statistics cards at top
- Pull-to-refresh
- Search bar with debounced search (300ms)
- Filter panel (slide-in from right)
- Real-time updates via listener

**Implementation:**
```swift
struct TasksMainView: View {
  @StateObject private var viewModel = TasksViewModel()
  @State private var showingFilters = false
  @State private var showingCreateTask = false

  var body: some View {
    NavigationView {
      VStack {
        // Statistics
        TaskStatsView(stats: viewModel.statistics)

        // View mode toggle
        Picker("View", selection: $viewModel.viewMode) {
          Text("List").tag(ViewMode.list)
          Text("Board").tag(ViewMode.board)
          Text("Calendar").tag(ViewMode.calendar)
        }
        .pickerStyle(.segmented)

        // Content
        switch viewModel.viewMode {
        case .list:
          TaskListView(tasks: viewModel.filteredTasks)
        case .board:
          TaskBoardView(tasks: viewModel.tasksByStatus)
        case .calendar:
          TaskCalendarView(tasks: viewModel.filteredTasks)
        }
      }
      .navigationTitle("Tasks")
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: { showingCreateTask = true }) {
            Image(systemName: "plus")
          }
        }
        ToolbarItem(placement: .navigationBarLeading) {
          Button(action: { showingFilters = true }) {
            Image(systemName: "line.3.horizontal.decrease.circle")
          }
        }
      }
      .sheet(isPresented: $showingCreateTask) {
        CreateTaskView()
      }
      .sheet(isPresented: $showingFilters) {
        FilterPanelView(filters: $viewModel.filters)
      }
    }
    .onAppear {
      viewModel.loadTasks()  // Cache-first loading
    }
  }
}
```

### TaskDetailView (Detail Screen)
**File**: `Iconik Employee/Tasks Feature/Views/TaskDetailView.swift` (NEW)

**Tab Structure:**
1. **Details** - Status, priority, due date, assignees, description
2. **Subtasks** - List of subtasks with checkboxes
3. **Comments** - Comments with @mention support
4. **Activity** - Activity log (future)
5. **Time** - Time entries (future)

```swift
struct TaskDetailView: View {
  let taskId: String
  @StateObject private var viewModel: TaskDetailViewModel
  @State private var selectedTab = 0

  var body: some View {
    VStack {
      // Header
      TaskDetailHeader(task: viewModel.task)

      // Tab selector
      Picker("", selection: $selectedTab) {
        Text("Details").tag(0)
        Text("Subtasks").tag(1)
        Text("Comments").tag(2)
        Text("Activity").tag(3)
        Text("Time").tag(4)
      }
      .pickerStyle(.segmented)

      // Tab content
      TabView(selection: $selectedTab) {
        TaskDetailsTab(task: viewModel.task).tag(0)
        SubtasksTab(viewModel: viewModel).tag(1)
        CommentsTab(viewModel: viewModel).tag(2)
        ActivityTab(viewModel: viewModel).tag(3)
        TimeTab(viewModel: viewModel).tag(4)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))

      // Footer actions
      TaskDetailFooter(
        task: viewModel.task,
        canEdit: viewModel.canEdit,
        canDelete: viewModel.canDelete,
        onEdit: { viewModel.showEditSheet = true },
        onComplete: { await viewModel.completeTask() },
        onDelete: { await viewModel.deleteTask() }
      )
    }
    .sheet(isPresented: $viewModel.showEditSheet) {
      EditTaskView(task: viewModel.task)
    }
  }
}
```

### CreateTaskView (Create/Edit Form)
**File**: `Iconik Employee/Tasks Feature/Views/CreateTaskView.swift` (NEW)

**Form Sections:**
```swift
struct CreateTaskView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = CreateTaskViewModel()

  @State private var title = ""
  @State private var description = ""
  @State private var type: TaskType = .general
  @State private var priority: TaskPriority = .medium
  @State private var dueDate: Date?
  @State private var estimatedHours: Double = 0
  @State private var selectedAssignees: Set<User> = []

  var body: some View {
    NavigationView {
      Form {
        // Basic Information
        Section("Basic Information") {
          TextField("Task title*", text: $title)
          TextEditor(text: $description)
            .frame(height: 100)
        }

        // Type
        Section("Type") {
          Picker("Type", selection: $type) {
            ForEach(TaskType.allCases, id: \.self) { type in
              Text(type.rawValue.capitalized).tag(type)
            }
          }
          .pickerStyle(.segmented)

          // Show session/workflow pickers based on type
          if type == .session {
            Picker("Session", selection: $viewModel.selectedSession) {
              ForEach(viewModel.sessions) { session in
                Text(session.name).tag(session as Session?)
              }
            }
          } else if type == .workflow {
            Picker("Workflow", selection: $viewModel.selectedWorkflow) {
              ForEach(viewModel.workflows) { workflow in
                Text(workflow.name).tag(workflow as Workflow?)
              }
            }
          }
        }

        // Details
        Section("Details") {
          Picker("Priority", selection: $priority) {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
              Text(priority.rawValue.capitalized).tag(priority)
            }
          }

          DatePicker("Due Date", selection: Binding(
            get: { dueDate ?? Date() },
            set: { dueDate = $0 }
          ), displayedComponents: [.date])

          HStack {
            Text("Estimated Hours")
            TextField("0", value: $estimatedHours, format: .number)
              .keyboardType(.decimalPad)
          }
        }

        // Assignment
        Section("Assign To") {
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
      }
      .navigationTitle("New Task")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
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
                assignees: Array(selectedAssignees)
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
    !title.isEmpty
  }
}
```

### Reusable Components

**TaskRowView.swift** - List item component
```swift
struct TaskRowView: View {
  let task: Task
  let onTap: () -> Void
  let onToggleComplete: () -> Void

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
          if let dueDate = task.dueDate {
            Label(
              dueDate.formatted(.relative(presentation: .named)),
              systemImage: "calendar"
            )
            .font(.caption)
            .foregroundColor(task.isOverdue ? .red : .secondary)
          }

          if !task.subtasks.isEmpty {
            let completed = task.subtasks.filter { $0.completed }.count
            Label("\(completed)/\(task.subtasks.count)", systemImage: "checklist")
              .font(.caption)
          }

          if task.commentCount > 0 {
            Label("\(task.commentCount)", systemImage: "bubble.left")
              .font(.caption)
          }
        }
      }

      Spacer()
    }
    .padding()
    .background(Color(.systemBackground))
    .onTapGesture(perform: onTap)
  }
}
```

**Other Components:**
- `SubtasksTab.swift` - Subtask list with add/toggle
- `CommentsTab.swift` - Comments list with add comment
- `PriorityBadge.swift` - Colored priority indicator
- `StatusBadge.swift` - Status badge with color
- `TaskStatsView.swift` - Statistics cards

---

## PHASE 4: Advanced Features

### Search & Filtering
**Implementation in TasksViewModel:**

```swift
class TasksViewModel: ObservableObject {
  @Published var tasks: [Task] = []
  @Published var searchQuery = ""
  @Published var filters = TaskFilters()

  var filteredTasks: [Task] {
    var result = tasks

    // Apply search
    if !searchQuery.isEmpty {
      result = result.filter { task in
        task.title.localizedCaseInsensitiveContains(searchQuery) ||
        (task.description?.localizedCaseInsensitiveContains(searchQuery) ?? false)
      }
    }

    // Apply filters
    result = filters.apply(to: result, currentUserId: currentUserId)

    // Apply sorting
    result = sortService.sort(result, by: filters.sortOption)

    return result
  }
}

struct TaskFilters {
  var assigneeFilter: AssigneeFilter = .me
  var statuses: Set<TaskStatus> = [.todo, .inProgress]
  var priorities: Set<TaskPriority> = []
  var types: Set<TaskType> = []
  var dueAfter: Date?
  var dueBefore: Date?
  var sortOption: SortOption = .smart
}
```

### Permissions System
**Implementation:**

```swift
struct TaskPermissions {
  let user: User
  let task: Task

  var canView: Bool {
    task.organizationID == user.organizationID &&
    (
      user.role.isAdminOrManager ||
      task.assignedTo.contains(user.id) ||
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
}
```

### Drag-and-Drop Reordering

```swift
func reorderTask(
  taskId: String,
  from sourceIndex: Int,
  to destinationIndex: Int,
  status: TaskStatus
) async throws {
  // 1. Get all tasks with this status
  var statusTasks = tasks
    .filter { $0.status == status }
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
  let batch = db.batch()
  for (taskId, newOrder) in updates {
    let ref = db.collection("tasks").document(taskId)
    batch.updateData(["order": newOrder], forDocument: ref)
  }
  try await batch.commit()
}
```

---

## PHASE 5: Integration

### 5.1 Add to MainEmployeeView
**File**: `Iconik Employee/MainEmployeeView.swift`

**Line ~745** - Add to `featureView` switch:
```swift
case "tasks":
    TasksMainView()
```

### 5.2 Update Firestore Rules
**File**: `firestore.rules`

Add rules for tasks collection:
```javascript
match /tasks/{taskId} {
  // Read: authenticated users in same org
  allow read: if isAuthenticated() &&
                 resource.data.organizationID == getUserOrganization();

  // Create: anyone can create for self, admins/managers can assign to anyone
  allow create: if isAuthenticated() &&
                   request.resource.data.organizationID == getUserOrganization() &&
                   request.resource.data.createdBy == request.auth.uid &&
                   (request.resource.data.assignedTo.size() == 0 ||
                    request.resource.data.assignedTo.hasOnly([request.auth.uid]) ||
                    isAdminOrManager());

  // Update: creator, assignee, or admins/managers
  allow update: if isAuthenticated() &&
                   resource.data.organizationID == getUserOrganization() &&
                   (resource.data.createdBy == request.auth.uid ||
                    request.auth.uid in resource.data.assignedTo ||
                    isAdminOrManager());

  // Delete: creator or admins/managers, with restrictions on completed tasks
  allow delete: if isAuthenticated() &&
                   resource.data.organizationID == getUserOrganization() &&
                   (
                     (resource.data.status != 'completed' && resource.data.createdBy == request.auth.uid) ||
                     isAdminOrManager()
                   );

  // Comments subcollection
  match /comments/{commentId} {
    allow read: if isAuthenticated() &&
                   get(/databases/$(database)/documents/tasks/$(taskId)).data.organizationID == getUserOrganization();
    allow create: if isAuthenticated();
    allow update, delete: if isAuthenticated() && resource.data.userId == request.auth.uid;
  }
}
```

### 5.3 Create Firestore Indexes
**Required composite indexes:**

1. `organizationID` (ASC) + `status` (ASC) + `order` (DESC)
2. `organizationID` (ASC) + `assignedTo` (ARRAY) + `dueDate` (ASC)
3. `organizationID` (ASC) + `createdBy` (ASC) + `dueDate` (ASC)
4. `organizationID` (ASC) + `workflowId` (ASC) + `workflowStepId` (ASC) + `createdAt` (DESC)
5. `organizationID` (ASC) + `assignedTo` (ARRAY) + `updatedAt` (DESC)
6. `organizationID` (ASC) + `createdBy` (ASC) + `updatedAt` (DESC)

**Add via Firebase Console** or `firestore.indexes.json`

---

## CRITICAL NOTES

### ⚠️ Bugs to Avoid (from Web App)

1. **Field Naming Inconsistency**
   - ❌ DON'T mix `workflowId` and `workflowID`
   - ✅ USE consistent camelCase (`workflowId`, `workflowStepId`, `sessionId`)

2. **Comment Count Increment**
   - ❌ DON'T use `arrayUnion().length`
   - ✅ USE `FieldValue.increment(1)`

3. **Missing Permission Checks**
   - ❌ DON'T allow delete without checking permissions
   - ✅ ALWAYS check `canDelete` before attempting delete

4. **Orphaned Data Cleanup**
   - ❌ DON'T leave comments/attachments when task deleted
   - ✅ TODO: Batch delete subcollections (future enhancement)

5. **Cache Not Cleared on Delete**
   - ❌ DON'T skip cache clearing (causes ghost tasks)
   - ✅ ALWAYS call `clearOrganizationCache()` after create/delete

### ✅ Must-Implement Features

1. **Cache-First Loading** (Performance)
   - Load from cache immediately
   - Subscribe to real-time updates with timestamp filter
   - Only fetch tasks updated after cache timestamp

2. **Read Counter** (Cost Monitoring)
   - Track all Firestore reads
   - Log cache hits/misses
   - Report daily statistics

3. **Permission Checks** (Security)
   - Validate before ALL operations
   - Check user role and task ownership
   - Follow permission matrix

4. **Activity Logging** (Audit Trail)
   - Log all task changes
   - Track status changes, assignments, etc.
   - Store in `activity` collection

5. **Auto Time Tracking** (Workflow)
   - Start tracking when status → "in_progress"
   - Stop tracking when status changes from "in_progress"

---

## FILE STRUCTURE

```
Iconik Employee/
  Tasks Feature/                     (NEW FOLDER)
    Models/
      TaskModel.swift                (Task, Subtask, enums)
      CommentModel.swift             (TaskComment, Mention, Attachment)

    Services/
      TaskService.swift              (CRUD + queries)
      CommentService.swift           (Comment operations)
      TaskCacheService.swift         (Cache management)
      ReadCounter.swift              (Read tracking)

    ViewModels/
      TasksViewModel.swift           (List view logic)
      TaskDetailViewModel.swift      (Detail view logic)
      CreateTaskViewModel.swift      (Create form logic)

    Views/
      TasksMainView.swift            (Main list/board view)
      TaskDetailView.swift           (Detail with tabs)
      CreateTaskView.swift           (Create/edit form)

      Components/
        TaskRowView.swift            (List item)
        TaskCard.swift               (Board card)
        SubtasksTab.swift            (Subtasks tab)
        CommentsTab.swift            (Comments tab)
        PriorityBadge.swift          (Priority indicator)
        StatusBadge.swift            (Status badge)
        TaskStatsView.swift          (Statistics cards)

  MainEmployeeView.swift             (EDIT - add tasks case)
```

---

## CHECKLIST

### Phase 1: Models
- [ ] Create TaskModel.swift with all fields
- [ ] Create CommentModel.swift
- [ ] Create enums (TaskType, TaskStatus, TaskPriority)
- [ ] Add Codable conformance
- [ ] Add helper computed properties (isOverdue, etc.)

### Phase 2: Services
- [ ] Create TaskService with CRUD operations
- [ ] Implement real-time listener with timestamp filter
- [ ] Create CommentService
- [ ] Create TaskCacheService with cache-first loading
- [ ] Create ReadCounter for cost monitoring
- [ ] Test all service methods

### Phase 3: UI - Core
- [ ] Create TasksMainView (list + board)
- [ ] Create TaskDetailView with tabs
- [ ] Create CreateTaskView form
- [ ] Create TaskRowView component
- [ ] Add to MainEmployeeView navigation

### Phase 4: UI - Advanced
- [ ] Implement search with debounce
- [ ] Implement filter panel
- [ ] Implement sorting
- [ ] Implement drag-and-drop reordering
- [ ] Add pull-to-refresh
- [ ] Add empty states

### Phase 5: Features
- [ ] Implement permissions system
- [ ] Implement subtasks (add/toggle/delete)
- [ ] Implement comments with @mentions
- [ ] Implement activity logging
- [ ] Implement time tracking integration
- [ ] Add notifications (future)

### Phase 6: Integration
- [ ] Update Firestore rules
- [ ] Create Firestore indexes
- [ ] Test with real data
- [ ] Test permissions
- [ ] Test cache-first loading
- [ ] Verify read counter accuracy

---

## ESTIMATED EFFORT

| Phase | Tasks | Hours |
|-------|-------|-------|
| Phase 1 | Models | 2-3 |
| Phase 2 | Services | 8-10 |
| Phase 3 | Core UI | 12-15 |
| Phase 4 | Advanced UI | 8-10 |
| Phase 5 | Features | 6-8 |
| Phase 6 | Integration & Testing | 4-6 |
| **TOTAL** | | **40-52 hours** |

---

## REFERENCE DOCUMENTS

- **Full Specification**: `task_feature.md` (2,824 lines)
- **Firestore Schema**: Lines 17-75
- **Service Logic**: Lines 260-687
- **Cache Strategy**: Lines 785-956
- **UI Components**: Lines 1150-1896
- **Permissions**: Lines 1920-1981

---

## NEXT STEPS

1. ✅ Read and understand task_feature.md
2. ✅ Create this implementation plan
3. ⏳ Get user approval on plan
4. ⏳ Begin Phase 1 (Models)
5. ⏳ Implement iteratively, testing each phase

---

**Last Updated**: 2025-11-14
**Status**: Ready for implementation
