# iOS App Supabase Migration Guide

This guide provides complete documentation for migrating the Iconik Employee iOS app from Firebase to Supabase. The web app has already been migrated and is running on Supabase.

---

## Table of Contents
1. [iOS App Repository](#ios-app-repository)
2. [Firebase Dependencies to Replace](#firebase-dependencies-to-replace)
3. [iOS Service Files to Migrate](#ios-service-files-to-migrate)
4. [Supabase Swift SDK Setup](#supabase-swift-sdk-setup)
5. [Authentication Migration](#authentication-migration)
6. [Database Query Patterns](#database-query-patterns)
7. [Real-time Subscriptions](#real-time-subscriptions)
8. [Storage Migration](#storage-migration)
9. [Field Name Mapping](#field-name-mapping)
10. [Complete Database Schema](#complete-database-schema)

---

## iOS App Repository

**GitHub:** https://github.com/Jsunwilke/employeeapp

**Platform Target:** iOS 16.0

**Chat System:** Uses Stream Chat (NOT Firebase) - no migration needed for chat.

---

## Firebase Dependencies to Replace

### Current Podfile Firebase Pods

```ruby
# REMOVE these Firebase pods:
pod 'Firebase/Auth'           # --> Supabase Auth
pod 'Firebase/Firestore'      # --> Supabase Database (PostgreSQL)
pod 'FirebaseFirestoreSwift'  # --> supabase-swift
pod 'Firebase/Storage'        # --> Supabase Storage
pod 'Firebase/Messaging'      # --> Keep APNs or alternative
pod 'Firebase/Core'           # --> Remove
pod 'Firebase/Analytics'      # --> Optional: keep or remove
pod 'Firebase/Functions'      # --> Supabase Edge Functions if needed

# KEEP these pods (not Firebase):
pod 'GoogleSignIn'               # Optional - can use Supabase OAuth
pod 'StreamChat', '~> 4.50.0'    # NOT Firebase - keep as-is
pod 'StreamChatUI', '~> 4.50.0'  # NOT Firebase - keep as-is
```

### New Supabase Pod

```ruby
pod 'Supabase', '~> 2.0'
```

---

## iOS Service Files to Migrate

### 1. UserProfileService.swift
**Firebase Operations to Replace:**
- `db.collection("users").document(id).getDocument()`
- `document.updateData([...])` with `FieldValue.serverTimestamp()`
- `document.addSnapshotListener()` for real-time
- `Auth.auth().addStateDidChangeListener()` for auth

**Model Fields (camelCase --> snake_case):**
- id, email
- firstName --> first_name
- lastName --> last_name
- displayName --> display_name
- photoURL --> photo_url
- organizationID --> organization_id
- role, position
- address, coordinates
- isActive --> is_active
- createdAt --> created_at
- updatedAt --> updated_at

### 2. OrganizationService.swift
**Firebase Operations to Replace:**
- `addSnapshotListener()` on organizations collection
- `getDocument()` for single fetch
- `updateData()` for feature toggles

**Model Fields:**
- id, name
- sessionTypes --> session_types (JSONB array)
- sessionOrderColors --> session_order_colors (JSONB)
- payPeriodSettings --> pay_period_settings (JSONB)
- enableSessionPublishing --> enable_session_publishing
- address, coordinates

### 3. TeamService.swift
**Firebase Operations to Replace:**
- `db.collection("users").whereField("organizationID", isEqualTo:)`
- `db.collection("users").document(userId).getDocument()`
- Timestamp conversion to Date

### 4. SessionService.swift (Schedule)
**Firebase Operations to Replace:**
- Real-time listeners with composite index (organizationID + isPublished + date)
- Cursor-based pagination
- Batch updates for color recalculation
- `FieldValue.delete()` and `FieldValue.serverTimestamp()`

**Model Fields:**
- id, organization_id, school_id, school_name
- date (text), start_time, end_time, location
- session_type, session_types (JSONB), photographers (JSONB)
- session_color, is_published, status
- workflow_id, notes, photographer_notes

### 5. TimeTrackingService.swift
**Firebase Operations to Replace:**
- `db.collection("timeEntries")` CRUD operations
- `addSnapshotListener()` for real-time clock status
- Queries limited to 100 documents with caching

**Model Fields:**
- id, user_id, organization_id
- session_id, start_time, end_time
- total_hours, status, created_at, updated_at

### 6. FirestoreManager+NFC.swift
**Collections Used:** records, job_boxes, sessions
**Features:** Offline queueing via OfflineDataManager, UserDefaults caching

### 7. TaskService.swift + CommentService.swift + TaskCacheService.swift
**Collections Used:** tasks, task_comments, task_attachments

---

## Supabase Swift SDK Setup

### Configuration

```swift
import Supabase

// Create a singleton or shared instance
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://nofegnmrgnanpznavlqy.supabase.co")!,
    supabaseKey: "YOUR_ANON_KEY"
)
```

### Environment Variables
Store these securely (e.g., in a Config.xcconfig or Info.plist):
- `SUPABASE_URL` = `https://nofegnmrgnanpznavlqy.supabase.co`
- `SUPABASE_ANON_KEY` = Your anon key from Supabase dashboard

---

## Authentication Migration

### Firebase vs Supabase Comparison

| Firebase | Supabase |
|----------|----------|
| `Auth.auth().signIn(withEmail:password:)` | `supabase.auth.signIn(email:password:)` |
| `Auth.auth().createUser(withEmail:password:)` | `supabase.auth.signUp(email:password:)` |
| `Auth.auth().signOut()` | `supabase.auth.signOut()` |
| `Auth.auth().addStateDidChangeListener()` | `supabase.auth.onAuthStateChange()` |
| `Auth.auth().currentUser?.uid` | `supabase.auth.session?.user.id` |
| `Auth.auth().sendPasswordReset(withEmail:)` | `supabase.auth.resetPasswordForEmail()` |

### Authentication Code Examples

```swift
// Sign In
func signIn(email: String, password: String) async throws {
    try await supabase.auth.signIn(email: email, password: password)
}

// Sign Up
func signUp(email: String, password: String) async throws {
    try await supabase.auth.signUp(email: email, password: password)
}

// Sign Out
func signOut() async throws {
    try await supabase.auth.signOut()
}

// Password Reset
func resetPassword(email: String) async throws {
    try await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: URL(string: "yourapp://reset-password")
    )
}

// Get Current User
var currentUser: User? {
    return supabase.auth.session?.user
}

var currentUserId: String? {
    return supabase.auth.session?.user.id.uuidString
}

// Auth State Listener
func setupAuthListener() {
    supabase.auth.onAuthStateChange { event, session in
        switch event {
        case .signedIn:
            if let user = session?.user {
                print("User signed in: \(user.id)")
                // Load user profile
            }
        case .signedOut:
            print("User signed out")
            // Clear local state
        case .tokenRefreshed:
            print("Token refreshed")
        default:
            break
        }
    }
}

// Get Current Session
func getSession() async throws -> Session? {
    return try await supabase.auth.session
}
```

### Important: User ID Difference
- **Firebase:** `Auth.auth().currentUser?.uid` (String)
- **Supabase:** `supabase.auth.session?.user.id` (UUID)

The `users` table uses `id` as text matching the auth UUID.

---

## Database Query Patterns

### Firebase vs Supabase Comparison

| Firestore | Supabase |
|-----------|----------|
| `db.collection("users").document(id).getDocument()` | `supabase.from("users").select().eq("id", id).single()` |
| `db.collection("users").whereField("org", isEqualTo:)` | `supabase.from("users").select().eq("organization_id", orgId)` |
| `document.addSnapshotListener()` | `supabase.channel().on(.postgres_changes)` |
| `batch.commit()` | Multiple queries or RPC function |
| `FieldValue.serverTimestamp()` | `Date().ISO8601Format()` or `now()` in SQL |
| `FieldValue.delete()` | Set field to `nil` or use `.update()` |

### Query Code Examples

```swift
// Define Codable models matching your database tables
struct UserProfile: Codable {
    let id: String
    let email: String?
    let first_name: String?
    let last_name: String?
    let display_name: String?
    let photo_url: String?
    let organization_id: String?
    let role: String?
    let is_active: Bool?
    let created_at: Date?
    let updated_at: Date?
}

// Fetch single record
func getUserProfile(userId: String) async throws -> UserProfile? {
    let response: UserProfile = try await supabase
        .from("users")
        .select()
        .eq("id", userId)
        .single()
        .execute()
        .value
    return response
}

// Fetch with filter
func getTeamMembers(organizationId: String) async throws -> [UserProfile] {
    let response: [UserProfile] = try await supabase
        .from("users")
        .select()
        .eq("organization_id", organizationId)
        .eq("is_active", true)
        .execute()
        .value
    return response
}

// Fetch with ordering
func getSessions(organizationId: String) async throws -> [Session] {
    let response: [Session] = try await supabase
        .from("sessions")
        .select()
        .eq("organization_id", organizationId)
        .eq("is_published", true)
        .order("date", ascending: false)
        .limit(50)
        .execute()
        .value
    return response
}

// Insert
func createTask(task: TaskInsert) async throws {
    try await supabase
        .from("tasks")
        .insert(task)
        .execute()
}

// Insert and return
func createTaskWithReturn(task: TaskInsert) async throws -> Task {
    let response: Task = try await supabase
        .from("tasks")
        .insert(task)
        .select()
        .single()
        .execute()
        .value
    return response
}

// Update
func updateUserProfile(userId: String, updates: [String: AnyEncodable]) async throws {
    try await supabase
        .from("users")
        .update(updates)
        .eq("id", userId)
        .execute()
}

// Delete
func deleteTask(taskId: String) async throws {
    try await supabase
        .from("tasks")
        .delete()
        .eq("id", taskId)
        .execute()
}

// Join related tables
func getTasksWithComments(organizationId: String) async throws -> [TaskWithComments] {
    let response: [TaskWithComments] = try await supabase
        .from("tasks")
        .select("*, task_comments(*)")
        .eq("organization_id", organizationId)
        .execute()
        .value
    return response
}

// Filter with multiple conditions
func getOpenTasks(organizationId: String, assigneeId: String) async throws -> [Task] {
    let response: [Task] = try await supabase
        .from("tasks")
        .select()
        .eq("organization_id", organizationId)
        .eq("assignee_id", assigneeId)
        .neq("status", "done")
        .order("due_date", ascending: true)
        .execute()
        .value
    return response
}
```

---

## Real-time Subscriptions

### Supabase Real-time Pattern

```swift
class SessionsViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    private var channel: RealtimeChannel?

    func subscribeToSessions(organizationId: String) {
        channel = supabase.channel("sessions-\(organizationId)")
            .onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: "sessions",
                filter: "organization_id=eq.\(organizationId)"
            ) { [weak self] change in
                Task { @MainActor in
                    await self?.handleChange(change)
                }
            }
            .subscribe()
    }

    @MainActor
    private func handleChange(_ change: AnyAction) async {
        // Refetch data on any change
        do {
            let response: [Session] = try await supabase
                .from("sessions")
                .select()
                .eq("organization_id", organizationId)
                .execute()
                .value
            self.sessions = response
        } catch {
            print("Error fetching sessions: \(error)")
        }
    }

    func unsubscribe() {
        if let channel = channel {
            supabase.removeChannel(channel)
        }
    }

    deinit {
        unsubscribe()
    }
}
```

### Subscribe to Specific Events

```swift
// Listen for INSERT events only
channel = supabase.channel("new-tasks")
    .onPostgresChange(
        InsertAction.self,
        schema: "public",
        table: "tasks",
        filter: "organization_id=eq.\(orgId)"
    ) { [weak self] insert in
        // Handle new task
        let newTask = insert.record
    }
    .subscribe()

// Listen for UPDATE events
channel = supabase.channel("task-updates")
    .onPostgresChange(
        UpdateAction.self,
        schema: "public",
        table: "tasks"
    ) { update in
        let oldRecord = update.oldRecord
        let newRecord = update.record
    }
    .subscribe()

// Listen for DELETE events
channel = supabase.channel("task-deletes")
    .onPostgresChange(
        DeleteAction.self,
        schema: "public",
        table: "tasks"
    ) { delete in
        let deletedRecord = delete.oldRecord
    }
    .subscribe()
```

---

## Storage Migration

### Firebase Storage vs Supabase Storage

| Firebase Storage | Supabase Storage |
|-----------------|------------------|
| `Storage.storage().reference()` | `supabase.storage.from("bucket")` |
| `ref.putData()` | `storage.upload()` |
| `ref.downloadURL()` | `storage.createSignedURL()` or `getPublicUrl()` |
| `ref.delete()` | `storage.remove()` |

### Storage Buckets

| Bucket | Purpose |
|--------|---------|
| `user-photos` | Profile pictures |
| `task-attachments` | Task file uploads |
| `chat-files` | Message attachments |
| `proof-images` | Photo proofing images |
| `yearbook-pdfs` | Yearbook PDF files |
| `workflow-videos` | Training videos |
| `organization-assets` | Logos, branding |

### Storage Code Examples

```swift
// Upload file
func uploadProfilePhoto(userId: String, imageData: Data) async throws -> String {
    let path = "\(userId)/profile.jpg"

    try await supabase.storage
        .from("user-photos")
        .upload(
            path: path,
            data: imageData,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )

    // Get public URL
    let publicUrl = supabase.storage
        .from("user-photos")
        .getPublicURL(path: path)

    return publicUrl.absoluteString
}

// Upload with signed URL (for private buckets)
func uploadPrivateFile(path: String, data: Data) async throws -> String {
    try await supabase.storage
        .from("private-bucket")
        .upload(path: path, data: data)

    // Create signed URL (expires in 1 hour)
    let signedUrl = try await supabase.storage
        .from("private-bucket")
        .createSignedURL(path: path, expiresIn: 3600)

    return signedUrl.absoluteString
}

// Download file
func downloadFile(bucket: String, path: String) async throws -> Data {
    return try await supabase.storage
        .from(bucket)
        .download(path: path)
}

// Delete file
func deleteFile(bucket: String, path: String) async throws {
    try await supabase.storage
        .from(bucket)
        .remove(paths: [path])
}

// List files in folder
func listFiles(bucket: String, folder: String) async throws -> [FileObject] {
    return try await supabase.storage
        .from(bucket)
        .list(path: folder)
}
```

---

## Field Name Mapping

**CRITICAL: Supabase uses snake_case, Firebase used camelCase**

| Firebase Field | Supabase Field |
|----------------|----------------|
| `organizationID` | `organization_id` |
| `firstName` | `first_name` |
| `lastName` | `last_name` |
| `displayName` | `display_name` |
| `photoURL` | `photo_url` |
| `isActive` | `is_active` |
| `createdAt` | `created_at` |
| `updatedAt` | `updated_at` |
| `sessionType` | `session_type` |
| `sessionTypes` | `session_types` |
| `schoolId` | `school_id` |
| `schoolName` | `school_name` |
| `userId` | `user_id` |
| `clockInTime` | `start_time` |
| `clockOutTime` | `end_time` |
| `isPublished` | `is_published` |
| `workflowId` | `workflow_id` |
| `templateId` | `template_id` |
| `assigneeId` | `assignee_id` |
| `dueDate` | `due_date` |

---

## Complete Database Schema

### Table 1: users
Primary user profiles table.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key (matches auth.uid) |
| email | text | | User email |
| first_name | text | | First name |
| last_name | text | | Last name |
| display_name | text | | Display/nickname |
| role | text | | admin, photographer, manager, etc. |
| position | text | | Job title |
| organization_id | text | | FK to organizations |
| photo_url | text | | Profile photo URL |
| original_photo_url | text | | Uncropped photo URL |
| photo_crop_settings | jsonb | {} | Crop parameters |
| is_active | boolean | true | Account active status |
| is_accountant | boolean | false | Accounting permissions |
| amount_per_mile | numeric | | Mileage reimbursement rate |
| is_temporary_invite | boolean | false | Pending invite |
| invited_at | timestamptz | | Invitation timestamp |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| is_photographer | boolean | false | Photographer role flag |
| address | text | | Full address string |
| bio | text | | User biography |
| city | text | | City |
| compensation_type | text | 'hourly' | hourly, salary |
| country | text | | Country |
| fcm_token | text | | Push notification token |
| fcm_token_updated_at | timestamptz | | Token update time |
| home_address | text | | Home address |
| hourly_rate | numeric | 0 | Pay rate |
| is_flagged | boolean | false | Flagged for attention |
| notify_on_proofing_approval | boolean | true | Email preference |
| overtime_threshold | integer | 40 | Weekly hours before OT |
| phone | text | | Phone number |
| salary_amount | numeric | 0 | Salary if salaried |
| state | text | | State/province |
| zip_code | text | | Postal code |
| preferences | jsonb | | User preferences |
| email_notifications | jsonb | | Email notification settings |

---

### Table 2: organizations
Multi-tenant organization/studio records.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| name | text | | Organization name |
| logo_url | text | | Logo image URL |
| session_order_colors | jsonb | [] | Color order for sessions |
| pay_period_settings | jsonb | {} | {startDate, frequency, isActive} |
| is_active | boolean | true | Account active |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| session_types | jsonb | [] | [{id, name, color}] |
| email | text | | Contact email |
| phone | text | | Contact phone |
| website | text | | Website URL |
| subscription | jsonb | {} | Plan details |
| preferences | jsonb | {} | Org preferences |
| address | jsonb | {} | Address object |
| operating_hours | jsonb | {} | Business hours |
| policies | jsonb | {} | Company policies |
| business_info | jsonb | {} | Additional info |
| enable_session_publishing | boolean | false | Session publish feature |
| pto_settings | jsonb | {} | PTO configuration |
| overtime_settings | jsonb | {} | OT rules |
| pricing | jsonb | {} | Pricing info |
| workflow_tab_order | jsonb | [] | UI tab ordering |
| yearbook_email | text | | Yearbook notifications email |

---

### Table 3: schools

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| name | text | | School name |
| address | text | | Full address |
| city | text | | City |
| state | text | | State |
| zip | text | | ZIP code |
| coordinates | jsonb | {} | {lat, lng} |
| is_active | boolean | true | Active status |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| street | text | | Street address |
| contact_name | text | | Primary contact |
| contact_email | text | | Contact email |
| contact_phone | text | | Contact phone |
| notes | text | | Notes |
| district_id | text | | FK to districts |
| district_name | text | | Denormalized district name |

---

### Table 4: districts

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| name | text | | District name |
| schools | jsonb | [] | Array of school references |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 5: sessions
Calendar/scheduling entries.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| user_id | text | | Primary assigned user |
| school_id | text | | FK to schools |
| date | text | | Date string (YYYY-MM-DD) |
| start_time | text | | Start time string |
| end_time | text | | End time string |
| location | text | | Location description |
| session_color | text | | Hex color code |
| is_time_off | boolean | false | Time off flag |
| reason | text | | Time off reason |
| status | text | 'active' | active, cancelled, etc. |
| workflow_id | text | | Linked workflow |
| notes | text | | Session notes |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| school_name | text | | Denormalized school name |
| title | text | | Session title |
| photographer_notes | text | | Notes for photographer |
| session_type | text | | Primary session type |
| session_types | jsonb | | Array of types |
| is_published | boolean | true | Visible to employees |
| photographers | jsonb | | [{id, name, notes}] |
| custom_session_type | text | | Custom type if "Other" |

---

### Table 6: time_entries
Clock in/out records.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| user_id | text | | FK to users |
| session_id | text | | Linked session |
| start_time | timestamptz | | Clock in time |
| end_time | timestamptz | | Clock out time |
| total_hours | numeric | | Calculated hours |
| status | text | 'active' | active, completed |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 7: time_off_requests

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| photographer_id | text | | FK to users |
| start_date | timestamptz | | Start of time off |
| end_date | timestamptz | | End of time off |
| status | text | 'pending' | pending, approved, denied |
| reason | text | | Request reason |
| type | text | | PTO, sick, etc. |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 8: pto_balances

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| user_id | text | | FK to users |
| balance | numeric | 0 | Current balance |
| accrued | numeric | 0 | Total accrued |
| used | numeric | 0 | Total used |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 9: pto_adjustments

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | |
| user_id | text | | |
| amount | numeric | | Adjustment amount |
| reason | text | | Reason for adjustment |
| adjusted_by | text | | Admin who made change |
| created_at | timestamptz | now() | |

---

### Table 10: tasks

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| title | text | | Task title |
| description | text | | Task description |
| status | text | 'todo' | todo, in_progress, done |
| priority | text | 'medium' | low, medium, high |
| assignee_id | text | | Single assignee |
| assigned_to | jsonb | [] | Multiple assignees |
| due_date | timestamptz | | Due date |
| task_order | integer | | Sort order |
| subtasks | jsonb | [] | [{id, title, completed}] |
| comment_count | integer | 0 | Cached comment count |
| time_entry_ids | jsonb | [] | Linked time entries |
| workflow_id | text | | Linked workflow |
| workflow_step_id | text | | Workflow step |
| session_id | text | | Linked session |
| auto_created | boolean | false | System-generated |
| sync_with_workflow | boolean | false | Auto-update with workflow |
| created_by | text | | Creator user ID |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| estimated_hours | numeric | | Time estimate |
| session_name | text | | Denormalized |
| session_date | text | | Denormalized |
| workflow_name | text | | Denormalized |
| workflow_step_name | text | | Denormalized |
| completed_at | timestamptz | | Completion time |
| completed_by | text | | Completer user ID |

---

### Table 11: task_comments

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| task_id | text | | FK to tasks |
| text | text | | Comment text |
| user_id | text | | Author ID |
| user_name | text | | Author name |
| created_at | timestamptz | now() | |

---

### Table 12: task_attachments

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| task_id | text | | FK to tasks |
| file_name | text | | Original filename |
| file_type | text | | MIME type |
| file_size | integer | | Size in bytes |
| file_url | text | | Storage URL |
| uploaded_by | text | | Uploader ID |
| created_at | timestamptz | now() | |

---

### Table 13: task_dependencies

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| task_id | text | | FK to tasks |
| depends_on_task_id | text | | Dependent task |
| dependency_type | text | | blocks, related |
| created_at | timestamptz | now() | |

---

### Table 14: task_activities

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| task_id | text | | FK to tasks |
| type | text | | Activity type |
| user_id | text | | Actor ID |
| organization_id | text | | |
| data | jsonb | {} | Activity data |
| timestamp | timestamptz | now() | |

---

### Table 15: task_notifications

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | |
| user_id | text | | Recipient |
| task_id | text | | Related task |
| type | text | | Notification type |
| is_read | boolean | false | Read status |
| created_at | timestamptz | now() | |
| title | text | | Notification title |
| message | text | | Notification body |
| data | jsonb | {} | Additional data |

---

### Table 16: task_templates

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| name | text | | Template name |
| description | text | | Template description |
| default_priority | text | | Default priority |
| default_assignee | text | | Default assignee |
| subtasks | jsonb | [] | Default subtasks |
| created_at | timestamptz | now() | |

---

### Table 17: recurring_tasks

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| task_template_id | text | | Template reference |
| frequency | text | | daily, weekly, monthly |
| day_of_week | integer | | 0-6 for weekly |
| day_of_month | integer | | 1-31 for monthly |
| is_active | boolean | true | Active status |
| next_occurrence | timestamptz | | Next scheduled |
| created_at | timestamptz | now() | |
| user_id | text | | Creator |
| title | text | | Task title |
| description | text | | Task description |
| interval | integer | 1 | Frequency interval |
| priority | text | 'medium' | Default priority |
| type | text | 'general' | Task type |
| assigned_to | text | | Default assignee |
| days_until_due | integer | 7 | Days before due |
| tags | jsonb | [] | Task tags |
| next_run | timestamptz | | Next execution |
| last_run | timestamptz | | Last execution |
| updated_at | timestamptz | now() | |

---

### Table 18: workflows

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| template_id | text | | FK to workflow_templates |
| session_id | text | | Linked session |
| status | text | 'pending' | pending, in_progress, completed |
| assignees | jsonb | [] | Assigned users |
| current_step | text | 0 | Current step index |
| completed_steps | jsonb | [] | Completed step IDs |
| data | jsonb | {} | Workflow data |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| hidden | boolean | false | Hidden from view |
| school_id | text | | School reference |
| school_name | text | | Denormalized |
| workflow_type | text | | Type classification |
| tracking_start_date | timestamptz | | Tracking period start |
| created_by | text | | Creator ID |
| custom_form_data | jsonb | {} | Form responses |
| custom_form_fields | jsonb | [] | Form field definitions |
| step_overrides | jsonb | {} | Step customizations |
| notes | text | | Workflow notes |
| auto_create_tasks | boolean | false | Auto-create tasks |
| academic_year | text | | Academic year |
| tracking_end_date | timestamptz | | Tracking period end |
| linked_gallery_id | text | | Linked proofing gallery |

---

### Table 19: workflow_templates

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| name | text | | Template name |
| description | text | | Template description |
| session_types | jsonb | [] | Applicable session types |
| is_active | boolean | true | Active status |
| version | integer | 1 | Version number |
| fields | jsonb | [] | Field definitions |
| steps | jsonb | [] | Step definitions |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| is_default | boolean | false | Default template |
| custom_form_fields | jsonb | [] | Custom fields |
| is_tracking_template | boolean | false | Tracking type |
| estimated_days | integer | 7 | Days to complete |
| groups | jsonb | [] | Step groups |
| proofing_gallery_mode | text | 'select' | Gallery creation mode |

---

### Table 20: sports_jobs

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| school_id | text | | FK to schools |
| shoot_date | timestamptz | | Shoot date |
| location | text | | Location |
| is_archived | boolean | false | Archive status |
| roster | jsonb | [] | Player roster data |
| job_data | jsonb | {} | Additional job data |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| school_name | text | | Denormalized |
| season_type | text | | fall, winter, spring |
| sport_name | text | | Sport name |
| photographer | text | | Assigned photographer |
| additional_notes | text | | Notes |
| session_id | text | | Linked session |

---

### Table 21: player_search_index

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| job_id | text | | FK to sports_jobs |
| organization_id | text | | FK to organizations |
| player_data | jsonb | {} | Player information |
| search_fields | jsonb | {} | Searchable fields |
| created_at | timestamptz | now() | |

---

### Table 22: records (NFC/SD Cards)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | NOT NULL | FK to organizations |
| card_number | text | | NFC card number |
| school | text | | School name |
| status | text | | Card status |
| user_id | text | | Associated user |
| timestamp | timestamptz | now() | Scan timestamp |
| uploaded_from_andys_house | boolean | | Upload location flag |
| uploaded_from_jasons_house | boolean | | Upload location flag |
| created_at | timestamptz | now() | |

---

### Table 23: job_boxes

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| job_id | text | | Job reference |
| status | text | | Box status |
| photographer | text | | Assigned photographer |
| school | text | | School name |
| updated_at | timestamptz | now() | |

---

### Table 24: sd_cards

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| job_id | text | | Job reference |
| status | text | | Card status |
| photographer | text | | Assigned photographer |
| updated_at | timestamptz | now() | |

---

### Table 25: conversations

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| participants | jsonb | [] | User IDs |
| type | text | 'direct' | direct, group |
| name | text | | Group name |
| default_name | text | | Default display name |
| last_activity | timestamptz | | Last message time |
| last_message | text | | Preview text |
| unread_counts | jsonb | {} | {userId: count} |
| created_at | timestamptz | now() | |

---

### Table 26: messages

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| conversation_id | text | | FK to conversations |
| sender_id | text | | Sender user ID |
| sender_name | text | | Sender name |
| text | text | | Message text |
| type | text | 'text' | text, file, image |
| file_url | text | | Attachment URL |
| file_data | jsonb | {} | File metadata |
| status | text | 'sent' | sent, delivered, read |
| read_by | jsonb | [] | User IDs who read |
| timestamp | timestamptz | now() | |
| created_at | timestamptz | now() | |

---

### Table 27: proof_galleries

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| name | text | | Gallery name |
| is_public | boolean | false | Public access |
| gallery_data | jsonb | {} | Additional data |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| is_archived | boolean | false | Archive status |
| school_id | text | | FK to schools |
| school_name | text | | Denormalized |
| workflow_id | text | | Linked workflow |
| client_name | text | | Client name |
| status | text | 'pending' | pending, approved, etc. |
| password | text | | Access password |
| total_images | integer | 0 | Total image count |
| approved_count | integer | 0 | Approved count |
| denied_count | integer | 0 | Denied count |
| archived_at | timestamptz | | Archive timestamp |
| last_approved_by | text | | Last approver |
| is_active | boolean | true | Active status |
| created_by | text | | Creator ID |
| created_by_name | text | | Creator name |
| deadline | timestamptz | | Review deadline |
| client_email | text | | Client email |
| last_reviewer_email | text | | Last reviewer |

---

### Table 28: proofs

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| gallery_id | text | | FK to proof_galleries |
| filename | text | | Original filename |
| image_url | text | | Full image URL |
| thumbnail_url | text | | Thumbnail URL |
| order | integer | 0 | Display order |
| status | text | 'pending' | pending, approved, denied |
| denial_notes | text | | Denial reason |
| current_version | integer | 1 | Current version |
| version_count | integer | 1 | Total versions |
| has_versions | boolean | false | Has revisions |
| last_revision_id | text | | Latest revision |
| reviewed_at | timestamptz | | Review timestamp |
| reviewed_by | text | | Reviewer |
| denied_by | text | | Denier |
| denied_at | timestamptz | | Denial timestamp |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 29: proof_images

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| gallery_id | text | | FK to proof_galleries |
| image_url | text | | Image URL |
| image_data | jsonb | {} | Metadata |
| created_at | timestamptz | now() | |

---

### Table 30: proof_revisions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| proof_id | text | | FK to proofs |
| gallery_id | text | | FK to proof_galleries |
| original_image_url | text | | Original URL |
| original_filename | text | | Original filename |
| new_image_url | text | | New image URL |
| new_filename | text | | New filename |
| version_number | integer | 1 | Version number |
| previous_version | integer | | Previous version |
| is_latest | boolean | true | Latest flag |
| is_current | boolean | true | Current flag |
| denial_notes | text | | Denial notes |
| studio_notes | text | | Studio notes |
| replaced_by | text | | Replacing revision |
| replaced_at | timestamptz | | Replace timestamp |
| created_at | timestamptz | now() | |

---

### Table 31: proof_activity

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| gallery_id | text | | FK to proof_galleries |
| action | text | | Action type |
| proof_id | text | | Related proof |
| filename | text | | Related file |
| count | integer | | Action count |
| user_email | text | | Actor email |
| timestamp | timestamptz | now() | |
| created_at | timestamptz | now() | |

---

### Table 32: yearbook_proofs

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | uuid | gen_random_uuid() | Primary key |
| organization_id | text | NOT NULL | FK to organizations |
| school_id | text | | FK to schools |
| school_name | text | | Denormalized |
| name | text | NOT NULL | Proof name |
| file_url | text | NOT NULL | PDF URL |
| file_name | text | NOT NULL | Original filename |
| file_size | integer | | File size in bytes |
| page_count | integer | | Total pages |
| version | integer | 1 | Version number |
| parent_id | uuid | | FK to parent proof |
| status | text | 'active' | active, archived |
| password | text | | Hashed password |
| client_email | text | | Client emails (comma-separated) |
| created_by | text | | Creator ID |
| created_by_name | text | | Creator name |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| academic_year | text | | Academic year |
| district_id | text | | FK to districts |
| district_name | text | | Denormalized |
| current_version_id | uuid | | FK to current version |
| latest_version | integer | 1 | Latest version number |

---

### Table 33: yearbook_proof_comments

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | uuid | gen_random_uuid() | Primary key |
| proof_id | uuid | NOT NULL | FK to yearbook_proofs |
| page_number | integer | NOT NULL | Page number |
| x_position | numeric | NOT NULL | X coordinate (%) |
| y_position | numeric | NOT NULL | Y coordinate (%) |
| text | text | NOT NULL | Comment text |
| author | text | | Author name |
| author_email | text | | Author email |
| resolved | boolean | false | Resolution status |
| resolved_at | timestamptz | | Resolution time |
| resolved_by | text | | Resolver |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 34: yearbook_page_assignments

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | uuid | gen_random_uuid() | Primary key |
| proof_id | uuid | NOT NULL | FK to yearbook_proofs |
| advisor_email | text | NOT NULL | Advisor email |
| advisor_name | text | | Advisor name |
| start_page | integer | NOT NULL | Start page |
| end_page | integer | NOT NULL | End page |
| approved_at | timestamptz | | Approval time |
| approved_by | text | | Approver |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 35: yearbook_proof_signoffs

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | uuid | gen_random_uuid() | Primary key |
| proof_id | uuid | NOT NULL | FK to yearbook_proofs |
| advisor_email | text | NOT NULL | Advisor email |
| advisor_name | text | | Advisor name |
| signed_off_at | timestamptz | now() | Signoff time |
| signed_off_by | text | | Signoff user |
| created_at | timestamptz | now() | |

---

### Table 36: yearbook_proof_activity

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | uuid | gen_random_uuid() | Primary key |
| proof_id | uuid | NOT NULL | FK to yearbook_proofs |
| event_type | text | NOT NULL | Event type |
| event_data | jsonb | | Event details |
| actor_email | text | | Actor email |
| actor_name | text | | Actor name |
| created_at | timestamptz | now() | |

---

### Table 37: yearbook_shoot_lists

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | NOT NULL | FK to organizations |
| school_id | text | | FK to schools |
| school_name | text | | Denormalized |
| school_year | text | | Academic year |
| start_date | timestamptz | | Period start |
| end_date | timestamptz | | Period end |
| is_active | boolean | false | Active status |
| copied_from_id | text | | Source list |
| completed_count | integer | 0 | Completed items |
| total_count | integer | 0 | Total items |
| items | jsonb | [] | Shoot list items |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 38: photo_critiques

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | NOT NULL | FK to organizations |
| submitter_id | text | | Submitter ID |
| submitter_name | text | | Submitter name |
| submitter_email | text | | Submitter email |
| target_photographer_id | text | | Target photographer |
| target_photographer_name | text | | Target name |
| photographer_id | text | | Alternative field |
| photographer_name | text | | Alternative field |
| image_url | text | | Single image URL |
| image_urls | jsonb | [] | Multiple images |
| thumbnail_url | text | | Single thumbnail |
| thumbnail_urls | jsonb | [] | Multiple thumbnails |
| image_count | integer | 0 | Image count |
| manager_notes | text | | Manager notes |
| notes | text | | General notes |
| example_type | text | | Example classification |
| type | text | | Critique type |
| status | text | 'published' | Status |
| feedback_count | integer | 0 | Feedback count |
| average_rating | numeric | 0 | Average rating |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 39: critique_feedback

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| critique_id | text | | FK to photo_critiques |
| organization_id | text | | FK to organizations |
| reviewer_id | text | | Reviewer ID |
| reviewer_name | text | | Reviewer name |
| rating | integer | | Rating value |
| comments | text | | Feedback text |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 40: daily_job_reports

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| user_id | text | | Reporter ID |
| your_name | text | | Reporter name |
| date | timestamptz | | Report date |
| total_mileage | numeric | | Total miles |
| report_data | jsonb | {} | Report content |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |
| timestamp | timestamptz | now() | |
| photographer | text | | Photographer name |
| template_id | text | | Template used |
| template_name | text | | Template name |
| template_version | integer | 1 | Template version |
| report_type | text | 'template' | Report type |
| smart_fields_used | jsonb | [] | Smart fields |
| notes | text | | Additional notes |
| school_name | text | | School name |
| school_id | text | | School ID |
| session_id | text | | Session ID |
| school_or_destination | text | | Destination |
| job_descriptions | jsonb | | Job descriptions |
| extra_items | jsonb | | Extra items |
| photoshoot_note_text | text | | Shoot notes |
| job_description_text | text | | Job text |
| job_box_and_camera_cards | text | | Equipment info |
| sports_background_shot | text | | Sports background |
| cards_scanned_choice | text | | Card scan choice |
| photo_urls | jsonb | | Attached photos |

---

### Table 41: report_templates

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| name | text | | Template name |
| sections | jsonb | [] | Template sections |
| is_active | boolean | true | Active status |
| updated_at | timestamptz | now() | |

---

### Table 42: blocked_dates

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| user_id | text | | User ID |
| start_date | timestamptz | | Block start |
| end_date | timestamptz | | Block end |
| reason | text | | Block reason |
| created_at | timestamptz | now() | |

---

### Table 43: class_group_jobs

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | NOT NULL | FK to organizations |
| school_id | text | | FK to schools |
| school_name | text | | Denormalized |
| session_id | text | | Linked session |
| session_date | timestamptz | | Session date |
| job_type | text | 'classGroups' | Job type |
| class_groups | jsonb | [] | Class group data |
| created_by | text | | Creator ID |
| last_modified_by | text | | Last modifier |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 44: photoshoot_notes

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | text | NOT NULL | Primary key |
| organization_id | text | | FK to organizations |
| note_data | jsonb | {} | Note content |
| location | jsonb | {} | Location data |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

### Table 45: school_advisors

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| id | uuid | gen_random_uuid() | Primary key |
| school_id | text | NOT NULL | FK to schools |
| name | text | NOT NULL | Advisor name |
| email | text | NOT NULL | Advisor email |
| created_at | timestamptz | now() | |
| updated_at | timestamptz | now() | |

---

## Row Level Security (RLS)

All tables have RLS enabled. Most policies check that the `organization_id` matches the authenticated user's organization.

Example policy pattern:
```sql
CREATE POLICY "Users can view their org data"
  ON table_name FOR SELECT
  USING (
    organization_id = (
      SELECT organization_id FROM users WHERE id = auth.uid()::text
    )
  );
```

---

## Migration Approach

### Phase 1: Core Infrastructure
1. Replace Firebase pods with `supabase-swift`
2. Create SupabaseManager singleton
3. Migrate AuthService

### Phase 2: User & Organization
1. UserProfileService --> uses `users` table
2. OrganizationService --> uses `organizations` table
3. TeamService --> queries `users` by `organization_id`

### Phase 3: Schedule/Sessions
1. SessionService --> uses `sessions` table
2. Migrate real-time listeners to Supabase channels
3. Handle date/time parsing differences

### Phase 4: Time Tracking
1. TimeTrackingService --> uses `time_entries` table
2. Migrate clock in/out operations
3. TimeOff --> uses `time_off_requests` table

### Phase 5: Tasks
1. TaskService --> uses `tasks` table
2. CommentService --> uses `task_comments` table
3. Attachments --> uses `task_attachments` + storage

### Phase 6: NFC/Records
1. FirestoreManager+NFC --> uses `records`, `job_boxes` tables
2. Update offline sync logic

### Phase 7: Other Features
1. Photo Critique --> `photo_critiques` table
2. Sports/Yearbook features

---

## Support

**Supabase Documentation:** https://supabase.com/docs
**Supabase Swift SDK:** https://github.com/supabase/supabase-swift
