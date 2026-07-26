//
//  EquipmentService.swift
//  Iconik Employee
//
//  Equipment Management Feature - Supabase Service
//

import Foundation
import Supabase

// MARK: - Update Request Structs (for Supabase updates)

private struct DamageReportResolution: Encodable {
    let status: String
    let resolution_notes: String
    let resolved_by: String
    let resolved_at: String
}

private struct RequestReview: Encodable {
    let status: String
    let reviewed_by: String
    let reviewed_at: String
    let review_notes: String
}

@MainActor
class EquipmentService: ObservableObject {
    static let shared = EquipmentService()

    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Published Properties

    @Published var equipment: [EquipmentItem] = []
    @Published var categories: [EquipmentCategory] = []
    @Published var kitTemplates: [KitTemplate] = []
    @Published var userAssignments: [EquipmentAssignment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Initialization

    private init() {}

    // MARK: - Equipment Items

    /// Fetch all equipment items for organization
    /// Note: organizationId is a text string (not UUID) in the database
    func getEquipmentItems(organizationId: String) async throws -> [EquipmentItem] {
        // Note: No FK relationship exists between equipment_assignments and users,
        // so we can't use join syntax. Fetch items with category only.
        let items: [EquipmentItem] = try await supabase
            .from("equipment_items")
            .select("""
                *,
                category:equipment_categories(*)
            """)
            .eq("organization_id", value: organizationId)
            .order("name")
            .execute()
            .value

        return items
    }

    /// Fetch single equipment item with full details
    func getEquipmentItem(id: UUID) async throws -> EquipmentItem {
        // Note: No FK relationship exists between equipment_assignments and users,
        // so we can't use join syntax. Fetch item with category only.
        let item: EquipmentItem = try await supabase
            .from("equipment_items")
            .select("""
                *,
                category:equipment_categories(*)
            """)
            .eq("id", value: id.uuidString.lowercased())
            .single()
            .execute()
            .value

        return item
    }

    /// Fetch equipment by QR code
    func getEquipmentByQRCode(qrCode: String, organizationId: String) async throws -> EquipmentItem? {
        // QR code format: "EQ-{UUID}"
        let equipmentIdString = qrCode.hasPrefix("EQ-") ? String(qrCode.dropFirst(3)) : qrCode

        guard let equipmentId = UUID(uuidString: equipmentIdString) else {
            return nil
        }

        // Note: No is_active column in schema. Status field is used instead.
        // Fetching without status filter to allow QR lookup of any equipment.
        let items: [EquipmentItem] = try await supabase
            .from("equipment_items")
            .select("*")
            .eq("organization_id", value: organizationId)
            .eq("id", value: equipmentId.uuidString.lowercased())
            .execute()
            .value

        return items.first
    }

    /// Create equipment item
    func createEquipmentItem(
        organizationId: String,
        categoryId: UUID?,
        name: String,
        description: String?,
        serialNumber: String?,
        purchaseDate: Date?,
        purchasePrice: Double?,
        condition: EquipmentCondition,
        notes: String?,
        createdBy: UUID
    ) async throws -> EquipmentItem {
        // Note: No is_active column in schema. Status field controls availability.
        var insertData: [String: AnyJSON] = [
            "organization_id": .string(organizationId),
            "name": .string(name),
            "condition": .string(condition.rawValue),
            "status": .string(EquipmentStatus.available.rawValue),
            "created_by": .string(createdBy.uuidString.lowercased())
        ]

        if let categoryId = categoryId {
            insertData["category_id"] = .string(categoryId.uuidString.lowercased())
        }
        if let description = description {
            insertData["description"] = .string(description)
        }
        if let serialNumber = serialNumber {
            insertData["serial_number"] = .string(serialNumber)
        }
        if let purchaseDate = purchaseDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            insertData["purchase_date"] = .string(dateFormatter.string(from: purchaseDate))
        }
        if let purchasePrice = purchasePrice {
            insertData["purchase_price"] = .double(purchasePrice)
        }
        if let notes = notes {
            insertData["notes"] = .string(notes)
        }

        let item: EquipmentItem = try await supabase
            .from("equipment_items")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        return item
    }

    /// Update equipment item
    func updateEquipmentItem(
        id: UUID,
        name: String? = nil,
        description: String? = nil,
        categoryId: UUID? = nil,
        serialNumber: String? = nil,
        condition: EquipmentCondition? = nil,
        status: EquipmentStatus? = nil,
        notes: String? = nil
    ) async throws {
        var updateData: [String: AnyJSON] = [:]

        if let name = name {
            updateData["name"] = .string(name)
        }
        if let description = description {
            updateData["description"] = .string(description)
        }
        if let categoryId = categoryId {
            updateData["category_id"] = .string(categoryId.uuidString.lowercased())
        }
        if let serialNumber = serialNumber {
            updateData["serial_number"] = .string(serialNumber)
        }
        if let condition = condition {
            updateData["condition"] = .string(condition.rawValue)
        }
        if let status = status {
            updateData["status"] = .string(status.rawValue)
        }
        if let notes = notes {
            updateData["notes"] = .string(notes)
        }

        guard !updateData.isEmpty else { return }

        try await supabase
            .from("equipment_items")
            .update(updateData)
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    /// Soft delete equipment item by setting status to 'retired'
    /// Note: No is_active column in schema. Status field is used instead.
    func deleteEquipmentItem(id: UUID) async throws {
        try await supabase
            .from("equipment_items")
            .update(["status": EquipmentStatus.retired.rawValue])
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    // MARK: - Categories

    /// Fetch all categories for organization
    func getCategories(organizationId: String) async throws -> [EquipmentCategory] {
        let categories: [EquipmentCategory] = try await supabase
            .from("equipment_categories")
            .select("*")
            .eq("organization_id", value: organizationId)
            .order("name")
            .execute()
            .value

        return categories
    }

    // MARK: - Assignments

    /// Get active assignments (equipment currently checked out) for organization
    func getActiveAssignments(organizationId: String) async throws -> [EquipmentAssignment] {
        // Note: No FK relationship exists between equipment_assignments and users,
        // so we can't use join syntax. User data must be fetched separately if needed.
        let allAssignments: [EquipmentAssignment] = try await supabase
            .from("equipment_assignments")
            .select("*")
            .eq("organization_id", value: organizationId)
            .order("checked_out_at", ascending: false)
            .execute()
            .value

        // Filter to only active (not returned) assignments client-side
        return allAssignments.filter { $0.isActive }
    }

    /// Get assignments for a specific user
    func getUserAssignments(userId: UUID, organizationId: String) async throws -> [EquipmentAssignment] {
        let allAssignments: [EquipmentAssignment] = try await supabase
            .from("equipment_assignments")
            .select("*")
            .eq("organization_id", value: organizationId)
            .eq("assigned_to", value: userId.uuidString.lowercased())
            .order("checked_out_at", ascending: false)
            .execute()
            .value

        // Filter to only active (not returned) assignments client-side
        return allAssignments.filter { $0.isActive }
    }

    /// Get assignment history for equipment
    func getEquipmentHistory(equipmentId: UUID) async throws -> [EquipmentAssignment] {
        // Note: No FK relationship exists between equipment_assignments and users,
        // so we can't use join syntax. User data must be fetched separately if needed.
        let assignments: [EquipmentAssignment] = try await supabase
            .from("equipment_assignments")
            .select("*")
            .eq("equipment_id", value: equipmentId.uuidString.lowercased())
            .order("checked_out_at", ascending: false)
            .execute()
            .value

        return assignments
    }

    /// Check out equipment to a user
    func checkOutEquipment(
        equipmentId: UUID,
        assignedTo: UUID,
        assignedBy: UUID,
        organizationId: String,
        expectedReturnDate: Date?,
        conditionAtCheckout: EquipmentCondition?,
        sessionId: UUID? = nil
    ) async throws -> EquipmentAssignment {
        var insertData: [String: AnyJSON] = [
            "equipment_id": .string(equipmentId.uuidString.lowercased()),
            "assigned_to": .string(assignedTo.uuidString.lowercased()),
            "assigned_by": .string(assignedBy.uuidString.lowercased()),
            "organization_id": .string(organizationId),
            "status": .string("active")
        ]

        if let expectedReturnDate = expectedReturnDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            insertData["expected_return_date"] = .string(dateFormatter.string(from: expectedReturnDate))
        }
        if let conditionAtCheckout = conditionAtCheckout {
            insertData["condition_at_checkout"] = .string(conditionAtCheckout.rawValue)
        }
        if let sessionId = sessionId {
            insertData["session_id"] = .string(sessionId.uuidString.lowercased())
        }

        // Create assignment
        let assignment: EquipmentAssignment = try await supabase
            .from("equipment_assignments")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        // Update equipment status
        try await supabase
            .from("equipment_items")
            .update(["status": EquipmentStatus.checkedOut.rawValue])
            .eq("id", value: equipmentId.uuidString.lowercased())
            .execute()

        return assignment
    }

    /// Check in equipment
    func checkInEquipment(
        assignmentId: UUID,
        equipmentId: UUID,
        checkedInBy: UUID,
        returnCondition: EquipmentCondition?,
        checkinNotes: String?
    ) async throws {
        var updateData: [String: AnyJSON] = [
            "checked_in_at": .string(ISO8601DateFormatter().string(from: Date())),
            "checked_in_by": .string(checkedInBy.uuidString.lowercased()),
            "status": .string("returned")
        ]

        if let returnCondition = returnCondition {
            updateData["condition_at_checkin"] = .string(returnCondition.rawValue)
        }
        if let checkinNotes = checkinNotes {
            updateData["checkin_notes"] = .string(checkinNotes)
        }

        // Update assignment
        try await supabase
            .from("equipment_assignments")
            .update(updateData)
            .eq("id", value: assignmentId.uuidString.lowercased())
            .execute()

        // Update equipment status to available
        try await supabase
            .from("equipment_items")
            .update(["status": EquipmentStatus.available.rawValue])
            .eq("id", value: equipmentId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Kit Templates

    /// Get all kit templates for organization
    func getKitTemplates(organizationId: String) async throws -> [KitTemplate] {
        let templates: [KitTemplate] = try await supabase
            .from("equipment_kit_templates")
            .select("*")
            .eq("organization_id", value: organizationId)
            .eq("is_active", value: true)
            .order("name")
            .execute()
            .value

        return templates
    }

    /// Check out entire kit
    func checkOutKit(
        template: KitTemplate,
        assignedTo: UUID,
        assignedBy: UUID,
        organizationId: String,
        expectedReturnDate: Date?,
        conditionAtCheckout: EquipmentCondition? = nil
    ) async throws -> [EquipmentAssignment] {
        // Get all equipment IDs from the kit
        let equipmentIds = template.equipmentIds

        guard !equipmentIds.isEmpty else {
            throw EquipmentError.kitItemsNotFound
        }

        // Fetch equipment items to verify availability
        let items: [EquipmentItem] = try await supabase
            .from("equipment_items")
            .select("*")
            .in("id", values: equipmentIds.map { $0.uuidString.lowercased() })
            .execute()
            .value

        // Check all items are available
        let unavailable = items.filter { $0.statusEnum != .available }
        if !unavailable.isEmpty {
            throw EquipmentError.itemsNotAvailable(unavailable.map { $0.name })
        }

        // Check out each item with their current condition
        var assignments: [EquipmentAssignment] = []
        let itemConditions = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.conditionEnum) })

        for equipmentId in equipmentIds {
            let itemCondition = conditionAtCheckout ?? itemConditions[equipmentId]
            let assignment = try await checkOutEquipment(
                equipmentId: equipmentId,
                assignedTo: assignedTo,
                assignedBy: assignedBy,
                organizationId: organizationId,
                expectedReturnDate: expectedReturnDate,
                conditionAtCheckout: itemCondition,
                sessionId: nil
            )
            assignments.append(assignment)
        }

        return assignments
    }

    /// Check in all items in a kit (by assignments)
    func checkInKit(
        assignments: [EquipmentAssignment],
        checkedInBy: UUID,
        returnConditions: [UUID: EquipmentCondition]?,
        checkinNotes: String?
    ) async throws {
        for assignment in assignments {
            let condition = returnConditions?[assignment.equipment_id]
            try await checkInEquipment(
                assignmentId: assignment.id,
                equipmentId: assignment.equipment_id,
                checkedInBy: checkedInBy,
                returnCondition: condition,
                checkinNotes: checkinNotes
            )
        }
    }

    // MARK: - Damage Reports

    /// Create damage report
    func createDamageReport(
        equipmentId: UUID,
        reportedBy: UUID,
        organizationId: String,
        description: String,
        severity: DamageSeverity,
        photoUrls: [String]?,
        assignmentId: UUID? = nil
    ) async throws -> DamageReport {
        var insertData: [String: AnyJSON] = [
            "equipment_id": .string(equipmentId.uuidString.lowercased()),
            "reported_by": .string(reportedBy.uuidString.lowercased()),
            "organization_id": .string(organizationId),
            "description": .string(description),
            "severity": .string(severity.rawValue),
            "status": .string(DamageStatus.reported.rawValue)
        ]

        if let photoUrls = photoUrls, !photoUrls.isEmpty {
            insertData["photos"] = .array(photoUrls.map { .string($0) })
        }
        if let assignmentId = assignmentId {
            insertData["assignment_id"] = .string(assignmentId.uuidString.lowercased())
        }

        let report: DamageReport = try await supabase
            .from("equipment_damage_reports")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        // Update equipment status to needs_repair
        try await supabase
            .from("equipment_items")
            .update(["status": EquipmentStatus.needsRepair.rawValue])
            .eq("id", value: equipmentId.uuidString.lowercased())
            .execute()

        return report
    }

    /// Get damage reports for organization
    func getDamageReports(organizationId: String, status: DamageStatus? = nil) async throws -> [DamageReport] {
        // Note: No FK relationship exists between equipment_damage_reports and users,
        // so we can't use join syntax. User data must be fetched separately if needed.
        var query = supabase
            .from("equipment_damage_reports")
            .select("*")
            .eq("organization_id", value: organizationId)

        if let status = status {
            query = query.eq("status", value: status.rawValue)
        }

        let reports: [DamageReport] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value

        return reports
    }

    /// Resolve damage report
    func resolveDamageReport(
        id: UUID,
        equipmentId: UUID,
        resolvedBy: UUID,
        resolutionNotes: String,
        newStatus: DamageStatus
    ) async throws {
        let resolution = DamageReportResolution(
            status: newStatus.rawValue,
            resolution_notes: resolutionNotes,
            resolved_by: resolvedBy.uuidString.lowercased(),
            resolved_at: ISO8601DateFormatter().string(from: Date())
        )

        try await supabase
            .from("equipment_damage_reports")
            .update(resolution)
            .eq("id", value: id.uuidString.lowercased())
            .execute()

        // Update equipment status based on resolution
        let equipmentStatus: EquipmentStatus = newStatus == .writtenOff ? .retired : .available
        try await supabase
            .from("equipment_items")
            .update(["status": equipmentStatus.rawValue])
            .eq("id", value: equipmentId.uuidString.lowercased())
            .execute()
    }

    // MARK: - Equipment Requests

    /// Create equipment request
    func createRequest(
        equipmentId: UUID?,
        categoryId: UUID? = nil,
        requestedBy: UUID,
        organizationId: String,
        neededFrom: Date,
        neededUntil: Date?,
        requestNotes: String?,
        sessionId: UUID? = nil
    ) async throws -> EquipmentRequest {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var insertData: [String: AnyJSON] = [
            "requested_by": .string(requestedBy.uuidString.lowercased()),
            "organization_id": .string(organizationId),
            "needed_from": .string(dateFormatter.string(from: neededFrom)),
            "status": .string(RequestStatus.pending.rawValue)
        ]

        if let equipmentId = equipmentId {
            insertData["equipment_id"] = .string(equipmentId.uuidString.lowercased())
        }
        if let categoryId = categoryId {
            insertData["category_id"] = .string(categoryId.uuidString.lowercased())
        }
        if let neededUntil = neededUntil {
            insertData["needed_until"] = .string(dateFormatter.string(from: neededUntil))
        }
        if let requestNotes = requestNotes {
            insertData["request_notes"] = .string(requestNotes)
        }
        if let sessionId = sessionId {
            insertData["session_id"] = .string(sessionId.uuidString.lowercased())
        }

        let request: EquipmentRequest = try await supabase
            .from("equipment_requests")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        return request
    }

    /// Get pending requests for organization (for admins)
    func getPendingRequests(organizationId: String) async throws -> [EquipmentRequest] {
        // Note: No FK relationship exists between equipment_requests and users,
        // so we can't use join syntax. User data must be fetched separately if needed.
        let requests: [EquipmentRequest] = try await supabase
            .from("equipment_requests")
            .select("*")
            .eq("organization_id", value: organizationId)
            .eq("status", value: RequestStatus.pending.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value

        return requests
    }

    /// Get user's requests
    func getMyRequests(userId: UUID) async throws -> [EquipmentRequest] {
        // Fetch requests without joins to avoid FK relationship issues
        let requests: [EquipmentRequest] = try await supabase
            .from("equipment_requests")
            .select("*")
            .eq("requested_by", value: userId.uuidString.lowercased())
            .order("created_at", ascending: false)
            .execute()
            .value

        return requests
    }

    /// Approve request
    func approveRequest(id: UUID, reviewedBy: UUID, notes: String?) async throws {
        var updateData: [String: AnyJSON] = [
            "status": .string(RequestStatus.approved.rawValue),
            "reviewed_by": .string(reviewedBy.uuidString.lowercased()),
            "reviewed_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]

        if let notes = notes {
            updateData["review_notes"] = .string(notes)
        }

        try await supabase
            .from("equipment_requests")
            .update(updateData)
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    /// Deny request
    func denyRequest(id: UUID, reviewedBy: UUID, reason: String) async throws {
        let review = RequestReview(
            status: RequestStatus.denied.rawValue,
            reviewed_by: reviewedBy.uuidString.lowercased(),
            reviewed_at: ISO8601DateFormatter().string(from: Date()),
            review_notes: reason
        )

        try await supabase
            .from("equipment_requests")
            .update(review)
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

    // MARK: - Photo Upload

    /// Upload equipment photo
    func uploadEquipmentPhoto(
        equipmentId: UUID,
        organizationId: String,
        imageData: Data,
        isMain: Bool = false
    ) async throws -> String {
        let fileName = isMain ? "main.jpg" : "photo_\(UUID().uuidString).jpg"
        let path = "\(organizationId)/items/\(equipmentId.uuidString.lowercased())/\(fileName)"

        try await supabase.storage
            .from("equipment-photos")
            .upload(
                path: path,
                file: imageData,
                options: FileOptions(contentType: "image/jpeg")
            )

        return path
    }

    /// Upload damage report photo
    func uploadDamagePhoto(
        damageReportId: UUID,
        organizationId: String,
        imageData: Data
    ) async throws -> String {
        let fileName = "photo_\(UUID().uuidString).jpg"
        let path = "\(organizationId)/damage/\(damageReportId.uuidString.lowercased())/\(fileName)"

        try await supabase.storage
            .from("equipment-photos")
            .upload(
                path: path,
                file: imageData,
                options: FileOptions(contentType: "image/jpeg")
            )

        return path
    }

    /// Get signed URL for photo
    func getSignedPhotoUrl(path: String) async throws -> URL {
        let signedUrl = try await supabase.storage
            .from("equipment-photos")
            .createSignedURL(path: path, expiresIn: 3600)

        return signedUrl
    }

    // MARK: - Helper Methods

    /// Group user's assignments by kit
    func groupAssignmentsByKit(
        assignments: [EquipmentAssignment],
        equipmentItems: [EquipmentItem],
        kitTemplates: [KitTemplate]
    ) -> [UserKitAssignment] {
        // Build a map of equipment_id -> equipment item
        var equipmentById: [UUID: EquipmentItem] = [:]
        for item in equipmentItems {
            equipmentById[item.id] = item
        }

        // Build a map of equipment_id -> kit
        var equipmentToKit: [UUID: KitTemplate] = [:]
        for kit in kitTemplates {
            for equipmentId in kit.equipmentIds {
                equipmentToKit[equipmentId] = kit
            }
        }

        // Group assignments by kit
        var kitGroups: [UUID: (kit: KitTemplate?, assignments: [EquipmentAssignment], items: [EquipmentItem])] = [:]
        var otherAssignments: [EquipmentAssignment] = []
        var otherItems: [EquipmentItem] = []

        for assignment in assignments {
            let item = equipmentById[assignment.equipment_id]

            if let kit = equipmentToKit[assignment.equipment_id] {
                if kitGroups[kit.id] == nil {
                    kitGroups[kit.id] = (kit: kit, assignments: [], items: [])
                }
                kitGroups[kit.id]?.assignments.append(assignment)
                if let item = item {
                    kitGroups[kit.id]?.items.append(item)
                }
            } else {
                otherAssignments.append(assignment)
                if let item = item {
                    otherItems.append(item)
                }
            }
        }

        // Convert to UserKitAssignment array
        var result: [UserKitAssignment] = []

        for (kitId, group) in kitGroups {
            result.append(UserKitAssignment(
                id: kitId,
                kitTemplate: group.kit,
                assignments: group.assignments,
                items: group.items
            ))
        }

        // Add "Other Equipment" group if there are items not in kits
        if !otherAssignments.isEmpty {
            result.append(UserKitAssignment(
                id: UUID(), // Generate new ID for "Other"
                kitTemplate: nil,
                assignments: otherAssignments,
                items: otherItems
            ))
        }

        // Sort: kits first (alphabetically), then "Other Equipment" last
        result.sort { a, b in
            if a.kitTemplate == nil { return false }
            if b.kitTemplate == nil { return true }
            return a.displayName < b.displayName
        }

        return result
    }

    // `loadMyKitsData` was deleted in AMB.3 along with its only caller, MyKitsView.
    // It fetched equipment and kit templates a THIRD time beside loadAllEquipmentData
    // and returned the kit templates without publishing them, which is why the one
    // screen that replaced both tabs calls loadAllEquipmentData + getUserAssignments
    // and groups them with `groupAssignmentsByKit` below — one fetch of each table
    // instead of two, and `kitTemplates` populated for everything that reads it.

    /// Load all equipment data (for browse view)
    func loadAllEquipmentData(organizationId: String) async throws {
        isLoading = true
        errorMessage = nil

        // `defer`, not a trailing assignment: this method rethrows, so the old
        // `isLoading = false` on the last line was skipped on every failure and the
        // flag stayed true for the rest of the app's life. Any view driven by it
        // would have shown a spinner behind the error alert with no way back.
        defer { isLoading = false }

        do {
            async let equipmentTask = getEquipmentItems(organizationId: organizationId)
            async let categoriesTask = getCategories(organizationId: organizationId)
            async let kitsTask = getKitTemplates(organizationId: organizationId)

            let (equipmentItems, categoryItems, kitItems) = try await (equipmentTask, categoriesTask, kitsTask)

            self.equipment = equipmentItems
            self.categories = categoryItems
            self.kitTemplates = kitItems
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
