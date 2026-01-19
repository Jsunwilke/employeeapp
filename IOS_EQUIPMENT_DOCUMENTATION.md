# Equipment Management Feature - iOS Implementation Guide

## Table of Contents
1. [Feature Overview](#1-feature-overview)
2. [Database Schema](#2-database-schema)
3. [Swift Data Models](#3-swift-data-models)
4. [API Queries](#4-api-queries)
5. [Core Workflows](#5-core-workflows)
6. [UI Components](#6-ui-components)
7. [Business Logic](#7-business-logic)
8. [Photo Storage](#8-photo-storage)
9. [QR Code Integration](#9-qr-code-integration)
10. [Permissions Model](#10-permissions-model)
11. [Edge Cases & Considerations](#11-edge-cases--considerations)

---

## 1. Feature Overview

The Equipment Management system provides comprehensive tracking of photography equipment including:

- **Inventory Management**: Track all equipment items with categories, serial numbers, and photos
- **Check-out/Check-in**: Assign equipment to employees with return dates
- **Kit Templates**: Bundle commonly-used equipment sets for quick assignment
- **Damage Reporting**: Document equipment issues with photos and descriptions
- **Equipment Requests**: Allow employees to request equipment with approval workflow
- **QR Code Scanning**: Quick equipment lookup via QR codes

### Key Concepts

| Concept | Description |
|---------|-------------|
| Equipment Item | A single piece of equipment (camera, lens, etc.) |
| Category | Grouping for equipment types (Cameras, Lenses, Lighting) |
| Assignment | A check-out record linking equipment to an employee |
| Kit Template | A saved bundle of equipment items for quick assignment |
| Damage Report | Documentation of equipment damage with photos |
| Equipment Request | Employee request for equipment, pending approval |

---

## 2. Database Schema

### 2.1 equipment_categories

Organizes equipment into logical groups.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `uuid_generate_v4()` | Primary key |
| `organization_id` | UUID | NO | - | FK to organizations |
| `name` | TEXT | NO | - | Category name (e.g., "Cameras") |
| `description` | TEXT | YES | - | Optional description |
| `icon` | TEXT | YES | - | Icon identifier (lucide icon name) |
| `color` | TEXT | YES | - | Hex color code for UI |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NO | `now()` | Last update timestamp |

**Indexes:**
- `equipment_categories_organization_id_idx` on `organization_id`

---

### 2.2 equipment_items

Core table for all equipment inventory.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `uuid_generate_v4()` | Primary key |
| `organization_id` | UUID | NO | - | FK to organizations |
| `category_id` | UUID | YES | - | FK to equipment_categories |
| `name` | TEXT | NO | - | Equipment name |
| `description` | TEXT | YES | - | Detailed description |
| `serial_number` | TEXT | YES | - | Manufacturer serial number |
| `purchase_date` | DATE | YES | - | When purchased |
| `purchase_price` | DECIMAL(10,2) | YES | - | Cost in dollars |
| `condition` | TEXT | NO | `'good'` | Current condition |
| `status` | TEXT | NO | `'available'` | Availability status |
| `photo_url` | TEXT | YES | - | Primary photo URL |
| `photo_urls` | JSONB | YES | `'[]'` | Array of additional photo URLs |
| `qr_code` | TEXT | YES | - | QR code identifier |
| `notes` | TEXT | YES | - | Additional notes |
| `is_active` | BOOLEAN | NO | `true` | Soft delete flag |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NO | `now()` | Last update timestamp |
| `created_by` | UUID | YES | - | FK to users |

**Status Values:**
| Status | Description |
|--------|-------------|
| `available` | Ready for check-out |
| `checked_out` | Currently assigned to someone |
| `needs_repair` | Damaged, awaiting repair |
| `retired` | No longer in service |

**Condition Values:**
| Condition | Description |
|-----------|-------------|
| `excellent` | Like new |
| `good` | Normal wear, fully functional |
| `fair` | Visible wear, still functional |
| `poor` | Significant wear, may have issues |

**Indexes:**
- `equipment_items_organization_id_idx` on `organization_id`
- `equipment_items_category_id_idx` on `category_id`
- `equipment_items_status_idx` on `status`
- `equipment_items_qr_code_idx` on `qr_code`

---

### 2.3 equipment_assignments

Tracks equipment check-outs and returns.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `uuid_generate_v4()` | Primary key |
| `organization_id` | UUID | NO | - | FK to organizations |
| `equipment_id` | UUID | NO | - | FK to equipment_items |
| `assigned_to` | UUID | NO | - | FK to users (employee) |
| `assigned_by` | UUID | NO | - | FK to users (admin/manager) |
| `checked_out_at` | TIMESTAMPTZ | NO | `now()` | Check-out timestamp |
| `expected_return_date` | DATE | YES | - | When item should be returned |
| `returned_at` | TIMESTAMPTZ | YES | - | Actual return timestamp |
| `return_condition` | TEXT | YES | - | Condition when returned |
| `return_notes` | TEXT | YES | - | Notes about return |
| `notes` | TEXT | YES | - | Check-out notes |
| `session_id` | UUID | YES | - | FK to sessions (if for specific job) |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Creation timestamp |

**Key Logic:**
- `returned_at = NULL` means item is currently checked out
- When checking in, set `returned_at` to current timestamp
- Update equipment_items.status to 'available' on return

**Indexes:**
- `equipment_assignments_equipment_id_idx` on `equipment_id`
- `equipment_assignments_assigned_to_idx` on `assigned_to`
- `equipment_assignments_returned_at_idx` on `returned_at`

---

### 2.4 equipment_damage_reports

Documents equipment damage with evidence.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `uuid_generate_v4()` | Primary key |
| `organization_id` | UUID | NO | - | FK to organizations |
| `equipment_id` | UUID | NO | - | FK to equipment_items |
| `reported_by` | UUID | NO | - | FK to users |
| `assignment_id` | UUID | YES | - | FK to equipment_assignments |
| `description` | TEXT | NO | - | Damage description |
| `severity` | TEXT | NO | `'minor'` | Damage severity level |
| `photo_urls` | JSONB | YES | `'[]'` | Array of damage photo URLs |
| `status` | TEXT | NO | `'reported'` | Report status |
| `resolution_notes` | TEXT | YES | - | How damage was resolved |
| `resolved_at` | TIMESTAMPTZ | YES | - | When resolved |
| `resolved_by` | UUID | YES | - | FK to users |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Report timestamp |

**Severity Values:**
| Severity | Description |
|----------|-------------|
| `minor` | Cosmetic, doesn't affect function |
| `moderate` | Some functional impact |
| `severe` | Major functional issues |
| `critical` | Equipment unusable |

**Status Values:**
| Status | Description |
|--------|-------------|
| `reported` | Newly reported |
| `acknowledged` | Admin has seen it |
| `in_repair` | Being repaired |
| `resolved` | Fixed and back in service |
| `written_off` | Equipment retired due to damage |

---

### 2.5 equipment_requests

Employee requests for equipment with approval workflow.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `uuid_generate_v4()` | Primary key |
| `organization_id` | UUID | NO | - | FK to organizations |
| `requested_by` | UUID | NO | - | FK to users (requester) |
| `equipment_id` | UUID | NO | - | FK to equipment_items |
| `session_id` | UUID | YES | - | FK to sessions (optional) |
| `requested_date` | DATE | NO | - | When equipment is needed |
| `requested_return_date` | DATE | YES | - | Expected return date |
| `reason` | TEXT | YES | - | Why equipment is needed |
| `status` | TEXT | NO | `'pending'` | Request status |
| `reviewed_by` | UUID | YES | - | FK to users (approver) |
| `reviewed_at` | TIMESTAMPTZ | YES | - | When reviewed |
| `review_notes` | TEXT | YES | - | Approval/denial reason |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Request timestamp |

**Status Values:**
| Status | Description |
|--------|-------------|
| `pending` | Awaiting review |
| `approved` | Request approved |
| `denied` | Request denied |
| `cancelled` | Cancelled by requester |
| `fulfilled` | Equipment has been checked out |

---

### 2.6 equipment_kit_templates

Pre-defined bundles of equipment for common setups.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `uuid_generate_v4()` | Primary key |
| `organization_id` | UUID | NO | - | FK to organizations |
| `name` | TEXT | NO | - | Kit name (e.g., "Portrait Setup") |
| `description` | TEXT | YES | - | Kit description |
| `color` | TEXT | YES | - | Hex color code for identification tape (e.g., "#3b82f6") |
| `equipment_ids` | UUID[] | NO | `'{}'` | Array of equipment_item IDs |
| `is_active` | BOOLEAN | NO | `true` | Whether kit is available |
| `created_by` | UUID | YES | - | FK to users |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NO | `now()` | Last update timestamp |

**Color Usage:**
- Each kit can have an assigned color for physical identification
- Use colored tape on equipment and bags to match the kit color
- Equipment items in a kit inherit the kit's color for visual display
- Common tape colors: Red (#ef4444), Orange (#f97316), Yellow (#eab308), Green (#22c55e), Blue (#3b82f6), Purple (#a855f7), Pink (#ec4899)

**Usage:**
- Kit templates allow checking out multiple items at once
- When checking out a kit, create separate assignments for each item
- Validate all items are available before kit checkout

---

## 3. Swift Data Models

### 3.1 Core Models

```swift
import Foundation

// MARK: - Equipment Category
struct EquipmentCategory: Codable, Identifiable {
    let id: UUID
    let organizationId: UUID
    let name: String
    let description: String?
    let icon: String?
    let color: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case name, description, icon, color
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Equipment Item
struct EquipmentItem: Codable, Identifiable {
    let id: UUID
    let organizationId: UUID
    let categoryId: UUID?
    let name: String
    let description: String?
    let serialNumber: String?
    let purchaseDate: Date?
    let purchasePrice: Decimal?
    let condition: EquipmentCondition
    let status: EquipmentStatus
    let photoUrl: String?
    let photoUrls: [String]
    let qrCode: String?
    let notes: String?
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    let createdBy: UUID?

    // Joined data (optional, from queries with joins)
    var category: EquipmentCategory?
    var currentAssignment: EquipmentAssignment?

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case categoryId = "category_id"
        case name, description
        case serialNumber = "serial_number"
        case purchaseDate = "purchase_date"
        case purchasePrice = "purchase_price"
        case condition, status
        case photoUrl = "photo_url"
        case photoUrls = "photo_urls"
        case qrCode = "qr_code"
        case notes
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case createdBy = "created_by"
        case category
        case currentAssignment = "current_assignment"
    }
}

enum EquipmentStatus: String, Codable {
    case available
    case checkedOut = "checked_out"
    case needsRepair = "needs_repair"
    case retired
}

enum EquipmentCondition: String, Codable {
    case excellent
    case good
    case fair
    case poor
}

// MARK: - Equipment Assignment
struct EquipmentAssignment: Codable, Identifiable {
    let id: UUID
    let organizationId: UUID
    let equipmentId: UUID
    let assignedTo: UUID
    let assignedBy: UUID
    let checkedOutAt: Date
    let expectedReturnDate: Date?
    let returnedAt: Date?
    let returnCondition: String?
    let returnNotes: String?
    let notes: String?
    let sessionId: UUID?
    let createdAt: Date

    // Joined data
    var equipment: EquipmentItem?
    var assignedToUser: User?
    var assignedByUser: User?

    var isActive: Bool {
        returnedAt == nil
    }

    var isOverdue: Bool {
        guard let expectedReturn = expectedReturnDate,
              returnedAt == nil else { return false }
        return Date() > expectedReturn
    }

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case equipmentId = "equipment_id"
        case assignedTo = "assigned_to"
        case assignedBy = "assigned_by"
        case checkedOutAt = "checked_out_at"
        case expectedReturnDate = "expected_return_date"
        case returnedAt = "returned_at"
        case returnCondition = "return_condition"
        case returnNotes = "return_notes"
        case notes
        case sessionId = "session_id"
        case createdAt = "created_at"
        case equipment
        case assignedToUser = "assigned_to_user"
        case assignedByUser = "assigned_by_user"
    }
}

// MARK: - Damage Report
struct DamageReport: Codable, Identifiable {
    let id: UUID
    let organizationId: UUID
    let equipmentId: UUID
    let reportedBy: UUID
    let assignmentId: UUID?
    let description: String
    let severity: DamageSeverity
    let photoUrls: [String]
    let status: DamageStatus
    let resolutionNotes: String?
    let resolvedAt: Date?
    let resolvedBy: UUID?
    let createdAt: Date

    // Joined data
    var equipment: EquipmentItem?
    var reportedByUser: User?

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case equipmentId = "equipment_id"
        case reportedBy = "reported_by"
        case assignmentId = "assignment_id"
        case description, severity
        case photoUrls = "photo_urls"
        case status
        case resolutionNotes = "resolution_notes"
        case resolvedAt = "resolved_at"
        case resolvedBy = "resolved_by"
        case createdAt = "created_at"
        case equipment
        case reportedByUser = "reported_by_user"
    }
}

enum DamageSeverity: String, Codable {
    case minor
    case moderate
    case severe
    case critical
}

enum DamageStatus: String, Codable {
    case reported
    case acknowledged
    case inRepair = "in_repair"
    case resolved
    case writtenOff = "written_off"
}

// MARK: - Equipment Request
struct EquipmentRequest: Codable, Identifiable {
    let id: UUID
    let organizationId: UUID
    let requestedBy: UUID
    let equipmentId: UUID
    let sessionId: UUID?
    let requestedDate: Date
    let requestedReturnDate: Date?
    let reason: String?
    let status: RequestStatus
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let reviewNotes: String?
    let createdAt: Date

    // Joined data
    var equipment: EquipmentItem?
    var requestedByUser: User?

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case requestedBy = "requested_by"
        case equipmentId = "equipment_id"
        case sessionId = "session_id"
        case requestedDate = "requested_date"
        case requestedReturnDate = "requested_return_date"
        case reason, status
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case reviewNotes = "review_notes"
        case createdAt = "created_at"
        case equipment
        case requestedByUser = "requested_by_user"
    }
}

enum RequestStatus: String, Codable {
    case pending
    case approved
    case denied
    case cancelled
    case fulfilled
}

// MARK: - Kit Template Item (stored in JSONB 'items' column)
struct KitTemplateItem: Codable {
    let type: String  // "specific" or "category"
    let equipmentId: UUID?  // For type="specific" - links to specific equipment item
    let equipmentName: String?  // Display name cached for UI
    let categoryId: UUID?  // For type="category" - any item from this category
    let categoryName: String?  // Display name cached for UI
    let quantity: Int?  // For type="category" - how many items needed

    enum CodingKeys: String, CodingKey {
        case type
        case equipmentId = "equipment_id"
        case equipmentName = "equipment_name"
        case categoryId = "category_id"
        case categoryName = "category_name"
        case quantity
    }
}

// MARK: - Kit Template
struct KitTemplate: Codable, Identifiable {
    let id: UUID
    let organizationId: UUID
    let name: String
    let description: String?
    let color: String?  // Hex color code for kit identification tape (e.g., "#ef4444")
    let items: [KitTemplateItem]?  // JSONB array of kit items
    let isActive: Bool
    let createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    // Joined/computed data
    var equipmentItems: [EquipmentItem]?

    // Helper to get all specific equipment IDs from items
    var equipmentIds: [UUID] {
        items?.compactMap { $0.type == "specific" ? $0.equipmentId : nil } ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case name, description, color, items
        case isActive = "is_active"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case equipmentItems = "equipment_items"
    }
}
```

### 3.2 Simple User Model (for joins)

```swift
struct User: Codable, Identifiable {
    let id: UUID
    let email: String
    let firstName: String?
    let lastName: String?
    let photoUrl: String?

    var fullName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id, email
        case firstName = "first_name"
        case lastName = "last_name"
        case photoUrl = "photo_url"
    }
}
```

---

## 4. API Queries

### 4.1 Equipment Items

```swift
// Fetch all equipment items for organization
func getEquipmentItems(organizationId: UUID) async throws -> [EquipmentItem] {
    try await supabase
        .from("equipment_items")
        .select("""
            *,
            category:equipment_categories(*),
            current_assignment:equipment_assignments!equipment_id(
                *,
                assigned_to_user:users!assigned_to(id, email, first_name, last_name, photo_url)
            )
        """)
        .eq("organization_id", value: organizationId)
        .eq("is_active", value: true)
        .order("name")
        .execute()
        .value
}

// Fetch single equipment item with full details
func getEquipmentItem(id: UUID) async throws -> EquipmentItem {
    try await supabase
        .from("equipment_items")
        .select("""
            *,
            category:equipment_categories(*),
            current_assignment:equipment_assignments!equipment_id(
                *,
                assigned_to_user:users!assigned_to(id, email, first_name, last_name, photo_url)
            )
        """)
        .eq("id", value: id)
        .single()
        .execute()
        .value
}

// Fetch equipment by QR code
func getEquipmentByQRCode(qrCode: String, organizationId: UUID) async throws -> EquipmentItem? {
    try await supabase
        .from("equipment_items")
        .select("*")
        .eq("organization_id", value: organizationId)
        .eq("qr_code", value: qrCode)
        .eq("is_active", value: true)
        .single()
        .execute()
        .value
}

// Create equipment item
func createEquipmentItem(_ item: EquipmentItemCreate) async throws -> EquipmentItem {
    try await supabase
        .from("equipment_items")
        .insert(item)
        .select()
        .single()
        .execute()
        .value
}

// Update equipment item
func updateEquipmentItem(id: UUID, updates: EquipmentItemUpdate) async throws -> EquipmentItem {
    try await supabase
        .from("equipment_items")
        .update(updates)
        .eq("id", value: id)
        .select()
        .single()
        .execute()
        .value
}

// Soft delete (set is_active = false)
func deleteEquipmentItem(id: UUID) async throws {
    try await supabase
        .from("equipment_items")
        .update(["is_active": false])
        .eq("id", value: id)
        .execute()
}

// MARK: - Kit Color Association
// Equipment items don't store their own color - they inherit from their kit.
// To display kit colors on equipment items, fetch kit templates and build a mapping.

struct EquipmentWithKitColor {
    let item: EquipmentItem
    let kitName: String?
    let kitColor: String?
}

func getEquipmentItemsWithKitColors(organizationId: UUID) async throws -> [EquipmentWithKitColor] {
    // Fetch all equipment items
    let items = try await getEquipmentItems(organizationId: organizationId)

    // Fetch all kit templates to build kit -> equipment mapping
    let kits = try await getKitTemplates(organizationId: organizationId)

    // Build a map of equipment_id -> (kit_name, kit_color)
    var equipmentKitMap: [UUID: (name: String, color: String?)] = [:]
    for kit in kits {
        // Parse kit.items JSONB array to get equipment IDs
        // Kit items can be 'specific' (with equipment_id) or 'category' (matched by category)
        if let items = kit.items {
            for kitItem in items {
                if kitItem.type == "specific", let equipmentId = kitItem.equipmentId {
                    equipmentKitMap[equipmentId] = (name: kit.name, color: kit.color)
                }
            }
        }
    }

    // Map equipment items with their kit colors
    return items.map { item in
        let kitInfo = equipmentKitMap[item.id]
        return EquipmentWithKitColor(
            item: item,
            kitName: kitInfo?.name,
            kitColor: kitInfo?.color
        )
    }
}
```

### 4.2 Categories

```swift
// Fetch all categories
func getCategories(organizationId: UUID) async throws -> [EquipmentCategory] {
    try await supabase
        .from("equipment_categories")
        .select("*")
        .eq("organization_id", value: organizationId)
        .order("name")
        .execute()
        .value
}

// Create category
func createCategory(_ category: CategoryCreate) async throws -> EquipmentCategory {
    try await supabase
        .from("equipment_categories")
        .insert(category)
        .select()
        .single()
        .execute()
        .value
}

// Update category
func updateCategory(id: UUID, updates: CategoryUpdate) async throws -> EquipmentCategory {
    try await supabase
        .from("equipment_categories")
        .update(updates)
        .eq("id", value: id)
        .select()
        .single()
        .execute()
        .value
}

// Delete category
func deleteCategory(id: UUID) async throws {
    try await supabase
        .from("equipment_categories")
        .delete()
        .eq("id", value: id)
        .execute()
}
```

### 4.3 Assignments (Check-out/Check-in)

```swift
// Get active assignments (equipment currently checked out)
func getActiveAssignments(organizationId: UUID) async throws -> [EquipmentAssignment] {
    try await supabase
        .from("equipment_assignments")
        .select("""
            *,
            equipment:equipment_items(*),
            assigned_to_user:users!assigned_to(id, email, first_name, last_name, photo_url),
            assigned_by_user:users!assigned_by(id, email, first_name, last_name, photo_url)
        """)
        .eq("organization_id", value: organizationId)
        .is("returned_at", value: nil)
        .order("checked_out_at", ascending: false)
        .execute()
        .value
}

// Get assignments for a specific user
func getUserAssignments(userId: UUID) async throws -> [EquipmentAssignment] {
    try await supabase
        .from("equipment_assignments")
        .select("""
            *,
            equipment:equipment_items(*)
        """)
        .eq("assigned_to", value: userId)
        .is("returned_at", value: nil)
        .order("checked_out_at", ascending: false)
        .execute()
        .value
}

// Get assignment history for equipment
func getEquipmentHistory(equipmentId: UUID) async throws -> [EquipmentAssignment] {
    try await supabase
        .from("equipment_assignments")
        .select("""
            *,
            assigned_to_user:users!assigned_to(id, email, first_name, last_name, photo_url),
            assigned_by_user:users!assigned_by(id, email, first_name, last_name, photo_url)
        """)
        .eq("equipment_id", value: equipmentId)
        .order("checked_out_at", ascending: false)
        .execute()
        .value
}

// Check out equipment
func checkOutEquipment(
    equipmentId: UUID,
    assignedTo: UUID,
    assignedBy: UUID,
    organizationId: UUID,
    expectedReturnDate: Date?,
    notes: String?,
    sessionId: UUID?
) async throws -> EquipmentAssignment {
    // Create assignment
    let assignment = try await supabase
        .from("equipment_assignments")
        .insert([
            "equipment_id": equipmentId,
            "assigned_to": assignedTo,
            "assigned_by": assignedBy,
            "organization_id": organizationId,
            "expected_return_date": expectedReturnDate,
            "notes": notes,
            "session_id": sessionId
        ])
        .select()
        .single()
        .execute()
        .value

    // Update equipment status
    try await supabase
        .from("equipment_items")
        .update(["status": "checked_out"])
        .eq("id", value: equipmentId)
        .execute()

    return assignment
}

// Check in equipment
func checkInEquipment(
    assignmentId: UUID,
    equipmentId: UUID,
    returnCondition: String?,
    returnNotes: String?
) async throws {
    // Update assignment
    try await supabase
        .from("equipment_assignments")
        .update([
            "returned_at": Date(),
            "return_condition": returnCondition,
            "return_notes": returnNotes
        ])
        .eq("id", value: assignmentId)
        .execute()

    // Update equipment status
    try await supabase
        .from("equipment_items")
        .update(["status": "available"])
        .eq("id", value: equipmentId)
        .execute()
}
```

### 4.4 Damage Reports

```swift
// Get damage reports for organization
func getDamageReports(organizationId: UUID, status: DamageStatus? = nil) async throws -> [DamageReport] {
    var query = supabase
        .from("equipment_damage_reports")
        .select("""
            *,
            equipment:equipment_items(id, name, photo_url),
            reported_by_user:users!reported_by(id, email, first_name, last_name, photo_url)
        """)
        .eq("organization_id", value: organizationId)

    if let status = status {
        query = query.eq("status", value: status.rawValue)
    }

    return try await query
        .order("created_at", ascending: false)
        .execute()
        .value
}

// Create damage report
func createDamageReport(
    equipmentId: UUID,
    reportedBy: UUID,
    organizationId: UUID,
    description: String,
    severity: DamageSeverity,
    photoUrls: [String],
    assignmentId: UUID?
) async throws -> DamageReport {
    let report = try await supabase
        .from("equipment_damage_reports")
        .insert([
            "equipment_id": equipmentId,
            "reported_by": reportedBy,
            "organization_id": organizationId,
            "description": description,
            "severity": severity.rawValue,
            "photo_urls": photoUrls,
            "assignment_id": assignmentId
        ])
        .select()
        .single()
        .execute()
        .value

    // Update equipment status to needs_repair
    try await supabase
        .from("equipment_items")
        .update(["status": "needs_repair"])
        .eq("id", value: equipmentId)
        .execute()

    return report
}

// Resolve damage report
func resolveDamageReport(
    id: UUID,
    equipmentId: UUID,
    resolvedBy: UUID,
    resolutionNotes: String,
    newStatus: DamageStatus
) async throws {
    try await supabase
        .from("equipment_damage_reports")
        .update([
            "status": newStatus.rawValue,
            "resolution_notes": resolutionNotes,
            "resolved_by": resolvedBy,
            "resolved_at": Date()
        ])
        .eq("id", value: id)
        .execute()

    // Update equipment status based on resolution
    let equipmentStatus = newStatus == .writtenOff ? "retired" : "available"
    try await supabase
        .from("equipment_items")
        .update(["status": equipmentStatus])
        .eq("id", value: equipmentId)
        .execute()
}
```

### 4.5 Equipment Requests

```swift
// Get pending requests (for admins)
func getPendingRequests(organizationId: UUID) async throws -> [EquipmentRequest] {
    try await supabase
        .from("equipment_requests")
        .select("""
            *,
            equipment:equipment_items(id, name, photo_url, status),
            requested_by_user:users!requested_by(id, email, first_name, last_name, photo_url)
        """)
        .eq("organization_id", value: organizationId)
        .eq("status", value: "pending")
        .order("created_at", ascending: false)
        .execute()
        .value
}

// Get my requests (for employees)
func getMyRequests(userId: UUID) async throws -> [EquipmentRequest] {
    try await supabase
        .from("equipment_requests")
        .select("""
            *,
            equipment:equipment_items(id, name, photo_url)
        """)
        .eq("requested_by", value: userId)
        .order("created_at", ascending: false)
        .execute()
        .value
}

// Create request
func createRequest(
    equipmentId: UUID,
    requestedBy: UUID,
    organizationId: UUID,
    requestedDate: Date,
    requestedReturnDate: Date?,
    reason: String?,
    sessionId: UUID?
) async throws -> EquipmentRequest {
    try await supabase
        .from("equipment_requests")
        .insert([
            "equipment_id": equipmentId,
            "requested_by": requestedBy,
            "organization_id": organizationId,
            "requested_date": requestedDate,
            "requested_return_date": requestedReturnDate,
            "reason": reason,
            "session_id": sessionId
        ])
        .select()
        .single()
        .execute()
        .value
}

// Approve request
func approveRequest(id: UUID, reviewedBy: UUID, notes: String?) async throws {
    try await supabase
        .from("equipment_requests")
        .update([
            "status": "approved",
            "reviewed_by": reviewedBy,
            "reviewed_at": Date(),
            "review_notes": notes
        ])
        .eq("id", value: id)
        .execute()
}

// Deny request
func denyRequest(id: UUID, reviewedBy: UUID, reason: String) async throws {
    try await supabase
        .from("equipment_requests")
        .update([
            "status": "denied",
            "reviewed_by": reviewedBy,
            "reviewed_at": Date(),
            "review_notes": reason
        ])
        .eq("id", value: id)
        .execute()
}
```

### 4.6 Kit Templates

```swift
// Get all kit templates
func getKitTemplates(organizationId: UUID) async throws -> [KitTemplate] {
    try await supabase
        .from("equipment_kit_templates")
        .select("*")
        .eq("organization_id", value: organizationId)
        .eq("is_active", value: true)
        .order("name")
        .execute()
        .value
}

// Get kit template with equipment items
func getKitTemplateWithItems(id: UUID) async throws -> KitTemplate {
    // First get the template
    var template: KitTemplate = try await supabase
        .from("equipment_kit_templates")
        .select("*")
        .eq("id", value: id)
        .single()
        .execute()
        .value

    // Then fetch the equipment items
    if !template.equipmentIds.isEmpty {
        let items: [EquipmentItem] = try await supabase
            .from("equipment_items")
            .select("*")
            .in("id", values: template.equipmentIds)
            .execute()
            .value
        template.equipmentItems = items
    }

    return template
}

// Create kit template
func createKitTemplate(
    name: String,
    description: String?,
    color: String?,  // Hex color for identification tape (e.g., "#3b82f6")
    equipmentIds: [UUID],
    organizationId: UUID,
    createdBy: UUID
) async throws -> KitTemplate {
    try await supabase
        .from("equipment_kit_templates")
        .insert([
            "name": name,
            "description": description,
            "color": color,
            "equipment_ids": equipmentIds,
            "organization_id": organizationId,
            "created_by": createdBy
        ])
        .select()
        .single()
        .execute()
        .value
}

// Update kit template
func updateKitTemplate(
    id: UUID,
    name: String,
    description: String?,
    color: String?,  // Hex color for identification tape (e.g., "#3b82f6")
    equipmentIds: [UUID]
) async throws -> KitTemplate {
    try await supabase
        .from("equipment_kit_templates")
        .update([
            "name": name,
            "description": description,
            "color": color,
            "equipment_ids": equipmentIds,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ])
        .eq("id", value: id)
        .select()
        .single()
        .execute()
        .value
}

// Check out entire kit
func checkOutKit(
    templateId: UUID,
    assignedTo: UUID,
    assignedBy: UUID,
    organizationId: UUID,
    expectedReturnDate: Date?,
    notes: String?
) async throws -> [EquipmentAssignment] {
    // Get kit template
    let template = try await getKitTemplateWithItems(id: templateId)

    // Check all items are available
    guard let items = template.equipmentItems else {
        throw EquipmentError.kitItemsNotFound
    }

    let unavailable = items.filter { $0.status != .available }
    if !unavailable.isEmpty {
        throw EquipmentError.itemsNotAvailable(unavailable.map { $0.name })
    }

    // Check out each item
    var assignments: [EquipmentAssignment] = []
    for item in items {
        let assignment = try await checkOutEquipment(
            equipmentId: item.id,
            assignedTo: assignedTo,
            assignedBy: assignedBy,
            organizationId: organizationId,
            expectedReturnDate: expectedReturnDate,
            notes: "Kit: \(template.name). \(notes ?? "")",
            sessionId: nil
        )
        assignments.append(assignment)
    }

    return assignments
}
```

---

## 5. Core Workflows

### 5.1 Equipment Check-Out Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                         CHECK-OUT WORKFLOW                            │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────────┐    │
│  │   SELECT    │────▶│   VERIFY     │────▶│   CREATE            │    │
│  │  EQUIPMENT  │     │  AVAILABLE   │     │   ASSIGNMENT        │    │
│  └─────────────┘     └──────────────┘     └─────────────────────┘    │
│        │                    │                       │                 │
│        ▼                    ▼                       ▼                 │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────────┐    │
│  │  Or scan    │     │ If checked   │     │ Update equipment    │    │
│  │  QR code    │     │ out, show    │     │ status to           │    │
│  │             │     │ current user │     │ "checked_out"       │    │
│  └─────────────┘     └──────────────┘     └─────────────────────┘    │
│                                                     │                 │
│                                                     ▼                 │
│                                           ┌─────────────────────┐    │
│                                           │ Send notification   │    │
│                                           │ to assigned user    │    │
│                                           └─────────────────────┘    │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘

User Inputs:
- Equipment ID (from list or QR scan)
- Assigned To (employee user ID)
- Expected Return Date (optional)
- Notes (optional)
- Session ID (if for specific job)
```

### 5.2 Equipment Check-In Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                         CHECK-IN WORKFLOW                             │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────────┐    │
│  │   SELECT    │────▶│   INSPECT    │────▶│   UPDATE            │    │
│  │  ASSIGNMENT │     │  CONDITION   │     │   ASSIGNMENT        │    │
│  └─────────────┘     └──────────────┘     └─────────────────────┘    │
│        │                    │                       │                 │
│        ▼                    ▼                       ▼                 │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────────┐    │
│  │  Or scan    │     │  If damaged, │     │ Set returned_at     │    │
│  │  QR code    │     │  prompt for  │     │ to now              │    │
│  │             │     │  report      │     │                     │    │
│  └─────────────┘     └──────────────┘     └─────────────────────┘    │
│                             │                       │                 │
│                             ▼                       ▼                 │
│                      ┌──────────────┐     ┌─────────────────────┐    │
│                      │ Create       │     │ Update equipment    │    │
│                      │ damage       │     │ status to           │    │
│                      │ report       │     │ "available" or      │    │
│                      │              │     │ "needs_repair"      │    │
│                      └──────────────┘     └─────────────────────┘    │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘

User Inputs:
- Assignment ID (from list or QR scan of equipment)
- Return Condition (excellent/good/fair/poor)
- Return Notes (optional)
- Report Damage? (triggers damage report flow)
```

### 5.3 Equipment Request Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                       REQUEST WORKFLOW                                │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  EMPLOYEE SIDE:                                                       │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────────┐    │
│  │   BROWSE    │────▶│   SELECT     │────▶│   SUBMIT            │    │
│  │  EQUIPMENT  │     │  DATE/REASON │     │   REQUEST           │    │
│  └─────────────┘     └──────────────┘     └─────────────────────┘    │
│                                                     │                 │
│                                                     ▼                 │
│                                           ┌─────────────────────┐    │
│                                           │ Status: PENDING     │    │
│                                           │ Notify admins       │    │
│                                           └─────────────────────┘    │
│                                                     │                 │
├─────────────────────────────────────────────────────┼─────────────────┤
│                                                     │                 │
│  ADMIN SIDE:                                        ▼                 │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────────┐    │
│  │   VIEW      │────▶│   REVIEW     │────▶│   APPROVE/DENY      │    │
│  │  REQUESTS   │     │   DETAILS    │     │                     │    │
│  └─────────────┘     └──────────────┘     └─────────────────────┘    │
│                                                     │                 │
│                              ┌──────────────────────┴──────┐         │
│                              ▼                             ▼         │
│                       ┌──────────────┐           ┌─────────────────┐ │
│                       │  APPROVED    │           │    DENIED       │ │
│                       │  Ready for   │           │  With reason    │ │
│                       │  checkout    │           │                 │ │
│                       └──────────────┘           └─────────────────┘ │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

### 5.4 Damage Report Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                      DAMAGE REPORT WORKFLOW                           │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────────┐    │
│  │  IDENTIFY   │────▶│   DESCRIBE   │────▶│   TAKE PHOTOS       │    │
│  │  EQUIPMENT  │     │   DAMAGE     │     │   (1-5 photos)      │    │
│  └─────────────┘     └──────────────┘     └─────────────────────┘    │
│                             │                       │                 │
│                             ▼                       ▼                 │
│                      ┌──────────────┐     ┌─────────────────────┐    │
│                      │  SET         │────▶│   SUBMIT REPORT     │    │
│                      │  SEVERITY    │     │                     │    │
│                      └──────────────┘     └─────────────────────┘    │
│                                                     │                 │
│                                                     ▼                 │
│                                           ┌─────────────────────┐    │
│                                           │ Equipment status    │    │
│                                           │ → "needs_repair"    │    │
│                                           │ Notify admins       │    │
│                                           └─────────────────────┘    │
│                                                                       │
│  ADMIN RESOLUTION:                                                    │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────────┐    │
│  │   REVIEW    │────▶│   REPAIR OR  │────▶│   RESOLVE           │    │
│  │   REPORT    │     │   WRITE OFF  │     │   (with notes)      │    │
│  └─────────────┘     └──────────────┘     └─────────────────────┘    │
│                                                     │                 │
│                              ┌──────────────────────┴──────┐         │
│                              ▼                             ▼         │
│                       ┌──────────────┐           ┌─────────────────┐ │
│                       │  RESOLVED    │           │  WRITTEN OFF    │ │
│                       │  Equipment   │           │  Equipment      │ │
│                       │  → available │           │  → retired      │ │
│                       └──────────────┘           └─────────────────┘ │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 6. UI Components

### 6.1 Main Views

| Component | Purpose | Key Features |
|-----------|---------|--------------|
| `EquipmentListView` | Main inventory list | Category filters, search, status badges |
| `EquipmentDetailView` | Single item details | Photo gallery, history, check-out button |
| `CheckOutView` | Check-out form | Employee picker, date picker, notes |
| `CheckInView` | Check-in form | Condition picker, damage report option |
| `MyEquipmentView` | User's checked-out items | List with return dates, check-in button |
| `DamageReportsView` | Admin damage list | Filter by status, resolution actions |
| `RequestsView` | Admin requests list | Approve/deny buttons, filters |
| `KitTemplatesView` | Kit management | Create/edit kits, check-out kit button |

### 6.2 UI Design Specifications

#### Status Badge Colors

```swift
extension EquipmentStatus {
    var color: Color {
        switch self {
        case .available:   return Color(hex: "#22c55e") // Green
        case .checkedOut:  return Color(hex: "#3b82f6") // Blue
        case .needsRepair: return Color(hex: "#f97316") // Orange
        case .retired:     return Color(hex: "#6b7280") // Gray
        }
    }

    var label: String {
        switch self {
        case .available:   return "Available"
        case .checkedOut:  return "Checked Out"
        case .needsRepair: return "Needs Repair"
        case .retired:     return "Retired"
        }
    }
}
```

#### Condition Badge Colors

```swift
extension EquipmentCondition {
    var color: Color {
        switch self {
        case .excellent: return Color(hex: "#22c55e") // Green
        case .good:      return Color(hex: "#3b82f6") // Blue
        case .fair:      return Color(hex: "#eab308") // Yellow
        case .poor:      return Color(hex: "#ef4444") // Red
        }
    }
}
```

#### Severity Badge Colors

```swift
extension DamageSeverity {
    var color: Color {
        switch self {
        case .minor:    return Color(hex: "#eab308") // Yellow
        case .moderate: return Color(hex: "#f97316") // Orange
        case .severe:   return Color(hex: "#ef4444") // Red
        case .critical: return Color(hex: "#dc2626") // Dark Red
        }
    }
}
```

### 6.3 SwiftUI Component Examples

#### Equipment List Item

```swift
struct EquipmentListItem: View {
    let item: EquipmentItem

    var body: some View {
        HStack(spacing: 12) {
            // Photo
            AsyncImage(url: URL(string: item.photoUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)

                if let category = item.category {
                    Text(category.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let serial = item.serialNumber {
                    Text("SN: \(serial)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status badge
            StatusBadge(status: item.status)
        }
        .padding(.vertical, 8)
    }
}

struct StatusBadge: View {
    let status: EquipmentStatus

    var body: some View {
        Text(status.label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color)
            .cornerRadius(12)
    }
}
```

#### Kit Template List Item (with color indicator)

```swift
struct KitTemplateListItem: View {
    let kit: KitTemplate

    var body: some View {
        HStack(spacing: 12) {
            // Icon with color indicator
            ZStack(alignment: .topLeading) {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)

                // Color dot overlay (if kit has a color)
                if let colorHex = kit.color {
                    Circle()
                        .fill(Color(hex: colorHex))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .offset(x: -4, y: -4)
                }
            }

            // Kit info
            VStack(alignment: .leading, spacing: 4) {
                Text(kit.name)
                    .font(.headline)

                if let description = kit.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Item count
                Text("\(kit.equipmentIds.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}
```

#### Equipment List Item with Kit Color Border

When equipment belongs to a kit with a color assigned, show a colored left border:

```swift
struct EquipmentListItemWithKitColor: View {
    let item: EquipmentItem
    let kitColor: String?  // Passed from parent based on kit membership

    var body: some View {
        HStack(spacing: 0) {
            // Kit color indicator (left border)
            if let colorHex = kitColor {
                Rectangle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 4)
            }

            HStack(spacing: 12) {
                // Photo
                AsyncImage(url: URL(string: item.photoUrl ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)

                    if let category = item.category {
                        Text(category.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                StatusBadge(status: item.status)
            }
            .padding(.leading, kitColor != nil ? 8 : 0)
        }
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}
```

#### Kit Color Picker

Color picker for kit templates (HSL-based like web version):

```swift
struct KitColorPicker: View {
    @Binding var selectedColor: String?
    @Environment(\.dismiss) private var dismiss

    // HSL state
    @State private var hue: Double = 210
    @State private var saturation: Double = 80
    @State private var lightness: Double = 55

    // Preset colors (matching web app)
    let presets = [
        "#3b82f6", "#10b981", "#8b5cf6", "#f59e0b",
        "#ef4444", "#06b6d4", "#ec4899", "#14b8a6",
        "#6366f1", "#84cc16", "#f97316", "#0ea5e9",
        "#a855f7", "#22c55e", "#8b5a3c", "#6b7280"
    ]

    var currentColor: Color {
        Color(hue: hue / 360, saturation: saturation / 100, brightness: lightness / 100)
    }

    var currentHex: String {
        hslToHex(h: hue, s: saturation, l: lightness)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Color preview
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(currentColor)
                        .frame(width: 60, height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    Text(currentHex.uppercased())
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding()

                // HSL Sliders
                VStack(spacing: 16) {
                    SliderRow(label: "Hue", value: $hue, range: 0...360)
                    SliderRow(label: "Saturation", value: $saturation, range: 0...100)
                    SliderRow(label: "Lightness", value: $lightness, range: 0...100)
                }
                .padding(.horizontal)

                // Preset colors
                VStack(alignment: .leading) {
                    Text("Quick picks")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                        ForEach(presets, id: \.self) { preset in
                            Circle()
                                .fill(Color(hex: preset))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(currentHex == preset ? Color.primary : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    applyPreset(preset)
                                }
                        }
                    }
                }
                .padding()

                Spacer()

                // Actions
                HStack {
                    Button("Clear") {
                        selectedColor = nil
                        dismiss()
                    }
                    .foregroundColor(.secondary)

                    Spacer()

                    Button("Done") {
                        selectedColor = currentHex
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Kit Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func applyPreset(_ hex: String) {
        let hsl = hexToHsl(hex)
        hue = hsl.h
        saturation = hsl.s
        lightness = hsl.l
    }

    // Color conversion helpers
    private func hslToHex(h: Double, s: Double, l: Double) -> String {
        let s = s / 100
        let l = l / 100
        let a = s * min(l, 1 - l)

        func f(_ n: Double) -> Int {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            let color = l - a * max(min(k - 3, 9 - k, 1), -1)
            return Int(round(255 * color))
        }

        return String(format: "#%02x%02x%02x", f(0), f(8), f(4))
    }

    private func hexToHsl(_ hex: String) -> (h: Double, s: Double, l: Double) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255

        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        var h: Double = 0
        var s: Double = 0
        let l = (maxVal + minVal) / 2

        if maxVal != minVal {
            let d = maxVal - minVal
            s = l > 0.5 ? d / (2 - maxVal - minVal) : d / (maxVal + minVal)

            switch maxVal {
            case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6
            case g: h = ((b - r) / d + 2) / 6
            case b: h = ((r - g) / d + 4) / 6
            default: break
            }
        }

        return (h * 360, s * 100, l * 100)
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Slider(value: $value, in: range)
        }
    }
}
```

#### Kit Detail View with Color

```swift
struct KitDetailView: View {
    let kit: KitTemplate
    @State private var equipmentItems: [EquipmentItem] = []

    var body: some View {
        List {
            // Kit info section
            Section {
                if let description = kit.description {
                    Text(description)
                        .foregroundColor(.secondary)
                }

                // Color indicator row
                if let colorHex = kit.color {
                    HStack {
                        Circle()
                            .fill(Color(hex: colorHex))
                            .frame(width: 24, height: 24)

                        Text("Tape Color: \(colorHex.uppercased())")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Equipment items section
            Section("Equipment (\(equipmentItems.count))") {
                ForEach(equipmentItems) { item in
                    EquipmentListItemWithKitColor(item: item, kitColor: kit.color)
                }
            }
        }
        .navigationTitle(kit.name)
    }
}
```

#### Color Hex Extension

```swift
extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
```

#### Check-Out Form

```swift
struct CheckOutFormView: View {
    let equipment: EquipmentItem
    @State private var selectedEmployee: User?
    @State private var expectedReturnDate: Date = Date().addingTimeInterval(86400 * 7)
    @State private var notes: String = ""
    @State private var isSubmitting = false

    var body: some View {
        Form {
            Section("Equipment") {
                HStack {
                    AsyncImage(url: URL(string: equipment.photoUrl ?? ""))
                        .frame(width: 50, height: 50)
                        .cornerRadius(8)

                    VStack(alignment: .leading) {
                        Text(equipment.name)
                            .font(.headline)
                        if let serial = equipment.serialNumber {
                            Text("SN: \(serial)")
                                .font(.caption)
                        }
                    }
                }
            }

            Section("Assign To") {
                NavigationLink {
                    EmployeePickerView(selection: $selectedEmployee)
                } label: {
                    HStack {
                        Text("Employee")
                        Spacer()
                        Text(selectedEmployee?.fullName ?? "Select...")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Return Date") {
                DatePicker(
                    "Expected Return",
                    selection: $expectedReturnDate,
                    displayedComponents: .date
                )
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }
        }
        .navigationTitle("Check Out")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm") {
                    checkOut()
                }
                .disabled(selectedEmployee == nil || isSubmitting)
            }
        }
    }

    private func checkOut() {
        // Implementation
    }
}
```

---

## 7. Business Logic

### 7.1 Availability Rules

```swift
func canCheckOut(equipment: EquipmentItem) -> Bool {
    return equipment.status == .available && equipment.isActive
}

func canCheckIn(assignment: EquipmentAssignment) -> Bool {
    return assignment.returnedAt == nil
}

func canRequestEquipment(equipment: EquipmentItem) -> Bool {
    // Can request even if currently checked out (for future date)
    return equipment.isActive && equipment.status != .retired
}
```

### 7.2 Overdue Detection

```swift
func isOverdue(assignment: EquipmentAssignment) -> Bool {
    guard let expectedReturn = assignment.expectedReturnDate,
          assignment.returnedAt == nil else {
        return false
    }
    return Date() > Calendar.current.startOfDay(for: expectedReturn)
}

func daysOverdue(assignment: EquipmentAssignment) -> Int? {
    guard isOverdue(assignment: assignment),
          let expectedReturn = assignment.expectedReturnDate else {
        return nil
    }
    let days = Calendar.current.dateComponents([.day], from: expectedReturn, to: Date()).day
    return days
}
```

### 7.3 Statistics Calculations

```swift
struct EquipmentStats {
    let total: Int
    let available: Int
    let checkedOut: Int
    let needsRepair: Int
    let retired: Int
    let overdueCount: Int

    var utilizationRate: Double {
        guard total > 0 else { return 0 }
        return Double(checkedOut) / Double(total - retired) * 100
    }
}

func calculateStats(items: [EquipmentItem], assignments: [EquipmentAssignment]) -> EquipmentStats {
    let activeItems = items.filter { $0.isActive }

    return EquipmentStats(
        total: activeItems.count,
        available: activeItems.filter { $0.status == .available }.count,
        checkedOut: activeItems.filter { $0.status == .checkedOut }.count,
        needsRepair: activeItems.filter { $0.status == .needsRepair }.count,
        retired: activeItems.filter { $0.status == .retired }.count,
        overdueCount: assignments.filter { isOverdue(assignment: $0) }.count
    )
}
```

---

## 8. Photo Storage

### 8.1 Storage Bucket

Equipment photos are stored in Supabase Storage bucket: `equipment-photos`

**Folder Structure:**
```
equipment-photos/
├── {organization_id}/
│   ├── items/
│   │   ├── {equipment_id}/
│   │   │   ├── main.jpg          # Primary photo
│   │   │   ├── photo_1.jpg       # Additional photos
│   │   │   ├── photo_2.jpg
│   │   │   └── ...
│   └── damage/
│       ├── {damage_report_id}/
│       │   ├── photo_1.jpg
│       │   ├── photo_2.jpg
│       │   └── ...
```

### 8.2 Signed URLs

Photos use signed URLs that expire. Always fetch fresh URLs when displaying.

```swift
func getSignedPhotoUrl(path: String) async throws -> URL? {
    let signedUrl = try await supabase.storage
        .from("equipment-photos")
        .createSignedURL(path: path, expiresIn: 3600) // 1 hour
    return URL(string: signedUrl)
}

// For multiple photos
func getSignedPhotoUrls(paths: [String]) async throws -> [URL] {
    var urls: [URL] = []
    for path in paths {
        if let url = try await getSignedPhotoUrl(path: path) {
            urls.append(url)
        }
    }
    return urls
}
```

### 8.3 Photo Upload

```swift
func uploadEquipmentPhoto(
    equipmentId: UUID,
    organizationId: UUID,
    imageData: Data,
    isMain: Bool = false
) async throws -> String {
    let fileName = isMain ? "main.jpg" : "photo_\(UUID().uuidString).jpg"
    let path = "\(organizationId)/items/\(equipmentId)/\(fileName)"

    try await supabase.storage
        .from("equipment-photos")
        .upload(
            path: path,
            file: imageData,
            options: FileOptions(contentType: "image/jpeg")
        )

    return path
}

func uploadDamagePhoto(
    damageReportId: UUID,
    organizationId: UUID,
    imageData: Data
) async throws -> String {
    let fileName = "photo_\(UUID().uuidString).jpg"
    let path = "\(organizationId)/damage/\(damageReportId)/\(fileName)"

    try await supabase.storage
        .from("equipment-photos")
        .upload(
            path: path,
            file: imageData,
            options: FileOptions(contentType: "image/jpeg")
        )

    return path
}
```

---

## 9. QR Code Integration

### 9.1 QR Code Format

Equipment QR codes contain a simple string identifier:

```
Format: "EQ-{UUID}"
Example: "EQ-550e8400-e29b-41d4-a716-446655440000"
```

### 9.2 QR Code Generation

```swift
import CoreImage.CIFilterBuiltins

func generateQRCode(for equipmentId: UUID) -> UIImage? {
    let qrString = "EQ-\(equipmentId.uuidString)"

    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(qrString.utf8)
    filter.correctionLevel = "M"

    guard let outputImage = filter.outputImage else { return nil }

    // Scale up for clarity
    let transform = CGAffineTransform(scaleX: 10, y: 10)
    let scaledImage = outputImage.transformed(by: transform)

    guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
        return nil
    }

    return UIImage(cgImage: cgImage)
}
```

### 9.3 QR Code Scanning

```swift
import AVFoundation

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession!
    var onCodeScanned: ((String) -> Void)?

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let stringValue = metadataObject.stringValue,
              stringValue.hasPrefix("EQ-") else {
            return
        }

        // Extract UUID
        let uuidString = String(stringValue.dropFirst(3))
        onCodeScanned?(uuidString)
    }
}

// Process scanned code
func processScannedCode(_ code: String) async throws -> EquipmentItem? {
    guard let uuid = UUID(uuidString: code) else { return nil }

    return try await supabase
        .from("equipment_items")
        .select("*")
        .eq("id", value: uuid)
        .single()
        .execute()
        .value
}
```

---

## 10. Permissions Model

### 10.1 Role-Based Access

| Action | Admin | Manager | Photographer | Employee |
|--------|-------|---------|--------------|----------|
| View all equipment | ✅ | ✅ | ✅ | ✅ |
| Create equipment | ✅ | ✅ | ❌ | ❌ |
| Edit equipment | ✅ | ✅ | ❌ | ❌ |
| Delete equipment | ✅ | ❌ | ❌ | ❌ |
| Check out (for self) | ✅ | ✅ | ✅ | ✅ |
| Check out (for others) | ✅ | ✅ | ❌ | ❌ |
| Check in (own items) | ✅ | ✅ | ✅ | ✅ |
| Check in (any item) | ✅ | ✅ | ❌ | ❌ |
| View all assignments | ✅ | ✅ | ❌ | ❌ |
| Create damage report | ✅ | ✅ | ✅ | ✅ |
| Resolve damage report | ✅ | ✅ | ❌ | ❌ |
| Request equipment | ✅ | ✅ | ✅ | ✅ |
| Approve/deny requests | ✅ | ✅ | ❌ | ❌ |
| Manage categories | ✅ | ✅ | ❌ | ❌ |
| Manage kit templates | ✅ | ✅ | ❌ | ❌ |

### 10.2 Swift Permission Helper

```swift
struct EquipmentPermissions {
    let userRole: String

    var canCreateEquipment: Bool {
        ["admin", "manager"].contains(userRole)
    }

    var canEditEquipment: Bool {
        ["admin", "manager"].contains(userRole)
    }

    var canDeleteEquipment: Bool {
        userRole == "admin"
    }

    var canCheckOutForOthers: Bool {
        ["admin", "manager"].contains(userRole)
    }

    var canCheckInAnyItem: Bool {
        ["admin", "manager"].contains(userRole)
    }

    var canViewAllAssignments: Bool {
        ["admin", "manager"].contains(userRole)
    }

    var canResolveDamageReport: Bool {
        ["admin", "manager"].contains(userRole)
    }

    var canApproveRequests: Bool {
        ["admin", "manager"].contains(userRole)
    }

    var canManageCategories: Bool {
        ["admin", "manager"].contains(userRole)
    }

    var canManageKitTemplates: Bool {
        ["admin", "manager"].contains(userRole)
    }
}
```

---

## 11. Edge Cases & Considerations

### 11.1 Data Validation

1. **Serial Number Uniqueness**: Serial numbers should be unique within an organization
2. **Category Deletion**: Cannot delete category if equipment items reference it
3. **Equipment Deletion**: Soft delete only (set `is_active = false`)
4. **Kit Validation**: Before kit checkout, verify all items are available

### 11.2 State Transitions

**Equipment Status Transitions:**
```
available ──────────┬──────────▶ checked_out
                    │
                    └──────────▶ needs_repair
                                      │
checked_out ────────┬──────────▶ available
                    │
                    └──────────▶ needs_repair
                                      │
needs_repair ───────┬──────────▶ available (after repair)
                    │
                    └──────────▶ retired (written off)
```

### 11.3 Offline Considerations

- Cache equipment list locally for offline viewing
- Queue check-out/check-in operations when offline
- Sync when connection restored
- Show "pending sync" indicator for queued operations

### 11.4 Notifications

Send push notifications for:
- Equipment assigned to you
- Equipment you checked out is overdue
- Damage report on equipment you manage
- Equipment request approved/denied
- Return reminder (day before expected return)

### 11.5 Performance Tips

1. **Pagination**: Use limit/offset for large equipment lists
2. **Lazy Loading**: Load assignment history on demand
3. **Image Caching**: Cache equipment photos locally
4. **Prefetching**: Preload equipment detail when user hovers on list item

---

## Verification Checklist

After implementation, verify:

- [ ] Equipment list displays with correct status badges
- [ ] Category filtering works correctly
- [ ] Search filters by name and serial number
- [ ] QR code scanning opens correct equipment detail
- [ ] Check-out flow updates status to "checked_out"
- [ ] Check-in flow updates status to "available"
- [ ] Damage report changes status to "needs_repair"
- [ ] Overdue items show visual indicator
- [ ] Request workflow sends notifications
- [ ] Kit checkout assigns all items
- [ ] Photos upload and display correctly
- [ ] Signed URLs refresh before expiry
- [ ] Permission checks enforce role-based access
- [ ] Offline queue syncs when online
