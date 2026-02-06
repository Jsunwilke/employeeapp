//
//  EquipmentModels.swift
//  Iconik Employee
//
//  Equipment Management Feature - Data Models
//

import Foundation
import SwiftUI

// MARK: - Equipment Status Enum

enum EquipmentStatus: String, Codable, CaseIterable {
    case available
    case checkedOut = "checked_out"
    case needsRepair = "needs_repair"
    case retired

    var label: String {
        switch self {
        case .available: return "Available"
        case .checkedOut: return "Checked Out"
        case .needsRepair: return "Needs Repair"
        case .retired: return "Retired"
        }
    }

    var color: Color {
        switch self {
        case .available: return Color(hex: "#22c55e")   // Green
        case .checkedOut: return Color(hex: "#3b82f6")  // Blue
        case .needsRepair: return Color(hex: "#f97316") // Orange
        case .retired: return Color(hex: "#6b7280")     // Gray
        }
    }

    var systemImage: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .checkedOut: return "person.fill"
        case .needsRepair: return "wrench.fill"
        case .retired: return "xmark.circle.fill"
        }
    }
}

// MARK: - Equipment Condition Enum

enum EquipmentCondition: String, Codable, CaseIterable {
    case excellent
    case good
    case fair
    case poor

    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    var color: Color {
        switch self {
        case .excellent: return Color(hex: "#22c55e") // Green
        case .good: return Color(hex: "#3b82f6")      // Blue
        case .fair: return Color(hex: "#eab308")      // Yellow
        case .poor: return Color(hex: "#ef4444")      // Red
        }
    }
}

// MARK: - Damage Severity Enum

enum DamageSeverity: String, Codable, CaseIterable {
    case minor
    case moderate
    case severe

    var label: String {
        switch self {
        case .minor: return "Minor"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }

    var description: String {
        switch self {
        case .minor: return "Cosmetic damage, fully functional"
        case .moderate: return "Partial functionality affected"
        case .severe: return "Major damage, unusable"
        }
    }

    var color: Color {
        switch self {
        case .minor: return Color(hex: "#eab308")    // Yellow
        case .moderate: return Color(hex: "#f97316") // Orange
        case .severe: return Color(hex: "#ef4444")   // Red
        }
    }
}

// MARK: - Damage Status Enum

enum DamageStatus: String, Codable, CaseIterable {
    case reported
    case acknowledged
    case inRepair = "in_repair"
    case resolved
    case writtenOff = "written_off"

    var label: String {
        switch self {
        case .reported: return "Reported"
        case .acknowledged: return "Acknowledged"
        case .inRepair: return "In Repair"
        case .resolved: return "Resolved"
        case .writtenOff: return "Written Off"
        }
    }
}

// MARK: - Request Status Enum

enum RequestStatus: String, Codable, CaseIterable {
    case pending
    case approved
    case denied
    case cancelled
    case fulfilled

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .denied: return "Denied"
        case .cancelled: return "Cancelled"
        case .fulfilled: return "Fulfilled"
        }
    }

    var color: Color {
        switch self {
        case .pending: return Color(hex: "#eab308")   // Yellow
        case .approved: return Color(hex: "#22c55e")  // Green
        case .denied: return Color(hex: "#ef4444")    // Red
        case .cancelled: return Color(hex: "#6b7280") // Gray
        case .fulfilled: return Color(hex: "#3b82f6") // Blue
        }
    }
}

// MARK: - Equipment Category Model

struct EquipmentCategory: Codable, Identifiable, Hashable {
    let id: UUID
    let organization_id: String  // TEXT type in database (Firebase-style ID)
    let name: String
    let description: String?
    let icon: String?
    let sort_order: Int?
    let created_at: Date
    let updated_at: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description, icon, sort_order
        case organization_id, created_at, updated_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        organization_id = try container.decode(String.self, forKey: .organization_id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        sort_order = try container.decodeIfPresent(Int.self, forKey: .sort_order)

        // Handle date parsing
        created_at = try Self.parseDate(from: container, forKey: .created_at) ?? Date()
        updated_at = try Self.parseDate(from: container, forKey: .updated_at) ?? Date()
    }

    private static func parseDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let dateValue = try? container.decode(Date.self, forKey: key) {
            return dateValue
        } else if let dateString = try? container.decode(String.self, forKey: key) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = isoFormatter.date(from: dateString) {
                return parsed
            }
            isoFormatter.formatOptions = [.withInternetDateTime]
            return isoFormatter.date(from: dateString)
        }
        return nil
    }
}

// MARK: - Equipment Item Model

struct EquipmentItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let organization_id: String  // TEXT type in database (Firebase-style ID)
    let category_id: UUID?
    let name: String
    let description: String?
    let brand: String?
    let model: String?
    let serial_number: String?
    let purchase_date: Date?
    let purchase_price: Double?
    let current_value: Double?
    let purchase_url: String?
    let warranty_expiration: Date?
    let condition: String
    let status: String
    let photos: [String]?  // jsonb array of photo URLs
    let qr_code_url: String?
    let notes: String?
    let created_at: Date
    let updated_at: Date
    let created_by: UUID?

    // Joined data (optional, from queries with joins)
    var category: EquipmentCategory?

    // Computed properties
    var statusEnum: EquipmentStatus {
        EquipmentStatus(rawValue: status) ?? .available
    }

    var conditionEnum: EquipmentCondition {
        EquipmentCondition(rawValue: condition) ?? .good
    }

    /// Primary photo URL (first in the photos array)
    var photo_url: String? {
        photos?.first
    }

    /// All photo URLs
    var allPhotoUrls: [String] {
        photos ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, brand, model, condition, status, notes, photos
        case organization_id, category_id, serial_number
        case purchase_date, purchase_price, current_value, purchase_url, warranty_expiration
        case qr_code_url
        case created_at, updated_at, created_by
        case category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        organization_id = try container.decode(String.self, forKey: .organization_id)
        category_id = try container.decodeIfPresent(UUID.self, forKey: .category_id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        serial_number = try container.decodeIfPresent(String.self, forKey: .serial_number)
        condition = try container.decodeIfPresent(String.self, forKey: .condition) ?? "good"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "available"
        photos = try container.decodeIfPresent([String].self, forKey: .photos)
        qr_code_url = try container.decodeIfPresent(String.self, forKey: .qr_code_url)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        purchase_url = try container.decodeIfPresent(String.self, forKey: .purchase_url)
        created_by = try container.decodeIfPresent(UUID.self, forKey: .created_by)

        // Handle purchase_price as Double or Decimal string
        if let priceDouble = try? container.decodeIfPresent(Double.self, forKey: .purchase_price) {
            purchase_price = priceDouble
        } else if let priceString = try? container.decodeIfPresent(String.self, forKey: .purchase_price),
                  let priceValue = Double(priceString) {
            purchase_price = priceValue
        } else {
            purchase_price = nil
        }

        // Handle current_value as Double or Decimal string
        if let valueDouble = try? container.decodeIfPresent(Double.self, forKey: .current_value) {
            current_value = valueDouble
        } else if let valueString = try? container.decodeIfPresent(String.self, forKey: .current_value),
                  let valueNum = Double(valueString) {
            current_value = valueNum
        } else {
            current_value = nil
        }

        // Handle date parsing
        purchase_date = try Self.parseDateOptional(from: container, forKey: .purchase_date)
        warranty_expiration = try Self.parseDateOptional(from: container, forKey: .warranty_expiration)
        created_at = try Self.parseDate(from: container, forKey: .created_at) ?? Date()
        updated_at = try Self.parseDate(from: container, forKey: .updated_at) ?? Date()

        // Joined data
        category = try container.decodeIfPresent(EquipmentCategory.self, forKey: .category)
    }

    private static func parseDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let dateValue = try? container.decode(Date.self, forKey: key) {
            return dateValue
        } else if let dateString = try? container.decode(String.self, forKey: key) {
            return parseISODate(dateString)
        }
        return nil
    }

    private static func parseDateOptional(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let dateValue = try? container.decodeIfPresent(Date.self, forKey: key) {
            return dateValue
        } else if let dateString = try? container.decodeIfPresent(String.self, forKey: key) {
            return parseISODate(dateString)
        }
        return nil
    }

    private static func parseISODate(_ string: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = isoFormatter.date(from: string) {
            return parsed
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let parsed = isoFormatter.date(from: string) {
            return parsed
        }
        // Try date-only format (YYYY-MM-DD)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: string)
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: EquipmentItem, rhs: EquipmentItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Equipment Assignment Model

struct EquipmentAssignment: Decodable, Identifiable, Hashable {
    let id: UUID
    let organization_id: String  // Note: text type in DB
    let equipment_id: UUID
    let assigned_to: UUID
    let assigned_by: UUID?
    let session_id: UUID?
    let checked_out_at: Date
    let expected_return_date: Date?
    let checked_in_at: Date?
    let checked_in_by: UUID?
    let condition_at_checkout: String?
    let condition_at_checkin: String?
    let checkin_notes: String?
    let status: String?  // active, returned, overdue
    let created_at: Date
    let updated_at: Date

    // Joined data (no equipment reference to avoid circular type)
    var assignedToUser: EquipmentUser?
    var assignedByUser: EquipmentUser?

    // Computed properties
    var isActive: Bool {
        status == "active" || (status == nil && checked_in_at == nil)
    }

    var isPermanent: Bool {
        expected_return_date == nil
    }

    var isOverdue: Bool {
        status == "overdue" || (isActive && expected_return_date != nil && Date() > Calendar.current.startOfDay(for: expected_return_date!))
    }

    var daysOverdue: Int? {
        guard isOverdue, let expectedReturn = expected_return_date else { return nil }
        return Calendar.current.dateComponents([.day], from: expectedReturn, to: Date()).day
    }

    var daysUntilDue: Int? {
        guard let expectedReturn = expected_return_date, !isOverdue, isActive else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expectedReturn).day
    }

    /// Extract kit name from checkin_notes if this assignment was part of a kit checkout
    var kitName: String? {
        guard let notes = checkin_notes, notes.contains("Kit:") else { return nil }
        let kitPart = notes.components(separatedBy: "Kit:").last?.components(separatedBy: ".").first
        return kitPart?.trimmingCharacters(in: .whitespaces)
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case organization_id, equipment_id, assigned_to, assigned_by, session_id
        case checked_out_at, expected_return_date, checked_in_at, checked_in_by
        case condition_at_checkout, condition_at_checkin, checkin_notes
        case created_at, updated_at
        case assignedToUser = "assigned_to_user"
        case assignedByUser = "assigned_by_user"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        organization_id = try container.decode(String.self, forKey: .organization_id)
        equipment_id = try container.decode(UUID.self, forKey: .equipment_id)
        assigned_to = try container.decode(UUID.self, forKey: .assigned_to)
        assigned_by = try container.decodeIfPresent(UUID.self, forKey: .assigned_by)
        session_id = try container.decodeIfPresent(UUID.self, forKey: .session_id)
        checked_in_by = try container.decodeIfPresent(UUID.self, forKey: .checked_in_by)
        condition_at_checkout = try container.decodeIfPresent(String.self, forKey: .condition_at_checkout)
        condition_at_checkin = try container.decodeIfPresent(String.self, forKey: .condition_at_checkin)
        checkin_notes = try container.decodeIfPresent(String.self, forKey: .checkin_notes)
        status = try container.decodeIfPresent(String.self, forKey: .status)

        // Handle date parsing
        checked_out_at = try Self.parseDate(from: container, forKey: .checked_out_at) ?? Date()
        expected_return_date = try Self.parseDateOptional(from: container, forKey: .expected_return_date)
        checked_in_at = try Self.parseDateOptional(from: container, forKey: .checked_in_at)
        created_at = try Self.parseDate(from: container, forKey: .created_at) ?? Date()
        updated_at = try Self.parseDate(from: container, forKey: .updated_at) ?? Date()

        // Joined data
        assignedToUser = try container.decodeIfPresent(EquipmentUser.self, forKey: .assignedToUser)
        assignedByUser = try container.decodeIfPresent(EquipmentUser.self, forKey: .assignedByUser)
    }

    private static func parseDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let dateValue = try? container.decode(Date.self, forKey: key) {
            return dateValue
        } else if let dateString = try? container.decode(String.self, forKey: key) {
            return parseISODate(dateString)
        }
        return nil
    }

    private static func parseDateOptional(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let dateValue = try? container.decodeIfPresent(Date.self, forKey: key) {
            return dateValue
        } else if let dateString = try? container.decodeIfPresent(String.self, forKey: key) {
            return parseISODate(dateString)
        }
        return nil
    }

    private static func parseISODate(_ string: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = isoFormatter.date(from: string) {
            return parsed
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let parsed = isoFormatter.date(from: string) {
            return parsed
        }
        // Try date-only format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: string)
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: EquipmentAssignment, rhs: EquipmentAssignment) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Equipment User Model (for joins)

struct EquipmentUser: Codable, Identifiable, Hashable {
    let id: UUID
    let email: String
    let first_name: String?
    let last_name: String?
    let photo_url: String?

    var fullName: String {
        [first_name, last_name].compactMap { $0 }.joined(separator: " ")
    }

    var displayName: String {
        fullName.isEmpty ? email : fullName
    }
}

// MARK: - Damage Report Model

struct DamageReport: Decodable, Identifiable, Hashable {
    let id: UUID
    let organization_id: String  // TEXT type in database (Firebase-style ID)
    let equipment_id: UUID
    let reported_by: UUID
    let assignment_id: UUID?
    let description: String
    let severity: String
    let photos: [String]?  // jsonb array of photo URLs
    let repair_cost: Double?
    let status: String
    let resolution_notes: String?
    let resolved_at: Date?
    let resolved_by: UUID?
    let created_at: Date
    let updated_at: Date

    // Joined data (no equipment reference to avoid circular type)
    var reportedByUser: EquipmentUser?

    // Computed properties
    var severityEnum: DamageSeverity {
        DamageSeverity(rawValue: severity) ?? .minor
    }

    var statusEnum: DamageStatus {
        DamageStatus(rawValue: status) ?? .reported
    }

    /// Convenience property for backward compatibility
    var photo_urls: [String]? {
        photos
    }

    enum CodingKeys: String, CodingKey {
        case id, description, severity, status, photos
        case organization_id, equipment_id, reported_by, assignment_id
        case repair_cost, resolution_notes, resolved_at, resolved_by
        case created_at, updated_at
        case reportedByUser = "reported_by_user"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        organization_id = try container.decode(String.self, forKey: .organization_id)
        equipment_id = try container.decode(UUID.self, forKey: .equipment_id)
        reported_by = try container.decode(UUID.self, forKey: .reported_by)
        assignment_id = try container.decodeIfPresent(UUID.self, forKey: .assignment_id)
        description = try container.decode(String.self, forKey: .description)
        severity = try container.decodeIfPresent(String.self, forKey: .severity) ?? "minor"
        photos = try container.decodeIfPresent([String].self, forKey: .photos)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "reported"
        resolution_notes = try container.decodeIfPresent(String.self, forKey: .resolution_notes)
        resolved_by = try container.decodeIfPresent(UUID.self, forKey: .resolved_by)

        // Handle repair_cost as Double or Decimal string
        if let costDouble = try? container.decodeIfPresent(Double.self, forKey: .repair_cost) {
            repair_cost = costDouble
        } else if let costString = try? container.decodeIfPresent(String.self, forKey: .repair_cost),
                  let costValue = Double(costString) {
            repair_cost = costValue
        } else {
            repair_cost = nil
        }

        // Handle date parsing
        resolved_at = try Self.parseDateOptional(from: container, forKey: .resolved_at)
        created_at = try Self.parseDate(from: container, forKey: .created_at) ?? Date()
        updated_at = try Self.parseDate(from: container, forKey: .updated_at) ?? Date()

        // Joined data
        reportedByUser = try container.decodeIfPresent(EquipmentUser.self, forKey: .reportedByUser)
    }

    private static func parseDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let dateValue = try? container.decode(Date.self, forKey: key) {
            return dateValue
        } else if let dateString = try? container.decode(String.self, forKey: key) {
            return parseISODate(dateString)
        }
        return nil
    }

    private static func parseDateOptional(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let dateValue = try? container.decodeIfPresent(Date.self, forKey: key) {
            return dateValue
        } else if let dateString = try? container.decodeIfPresent(String.self, forKey: key) {
            return parseISODate(dateString)
        }
        return nil
    }

    private static func parseISODate(_ string: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = isoFormatter.date(from: string) {
            return parsed
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: string)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DamageReport, rhs: DamageReport) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Equipment Request Model

struct EquipmentRequest: Decodable, Identifiable, Hashable {
    let id: UUID
    let organization_id: String  // TEXT type in database (Firebase-style ID)
    let requested_by: UUID
    let equipment_id: UUID?
    let category_id: UUID?
    let session_id: UUID?
    let assignment_id: UUID?
    let fulfilled_with: UUID?  // Equipment ID if request was fulfilled
    let needed_from: Date
    let needed_until: Date?
    let request_notes: String?
    let status: String
    let reviewed_by: UUID?
    let reviewed_at: Date?
    let review_notes: String?
    let created_at: Date
    let updated_at: Date

    // Joined data (no equipment reference to avoid circular type)
    var requestedByUser: EquipmentUser?

    // Computed properties
    var statusEnum: RequestStatus {
        RequestStatus(rawValue: status) ?? .pending
    }

    /// Convenience property for backward compatibility
    var requested_date: Date {
        needed_from
    }

    /// Convenience property for backward compatibility
    var requested_return_date: Date? {
        needed_until
    }

    /// Convenience property for backward compatibility
    var reason: String? {
        request_notes
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case organization_id, requested_by, equipment_id, category_id, session_id
        case assignment_id, fulfilled_with
        case needed_from, needed_until, request_notes
        case reviewed_by, reviewed_at, review_notes
        case created_at, updated_at
        case requestedByUser = "requested_by_user"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        organization_id = try container.decode(String.self, forKey: .organization_id)
        requested_by = try container.decode(UUID.self, forKey: .requested_by)
        equipment_id = try container.decodeIfPresent(UUID.self, forKey: .equipment_id)
        category_id = try container.decodeIfPresent(UUID.self, forKey: .category_id)
        session_id = try container.decodeIfPresent(UUID.self, forKey: .session_id)
        assignment_id = try container.decodeIfPresent(UUID.self, forKey: .assignment_id)
        fulfilled_with = try container.decodeIfPresent(UUID.self, forKey: .fulfilled_with)
        request_notes = try container.decodeIfPresent(String.self, forKey: .request_notes)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        reviewed_by = try container.decodeIfPresent(UUID.self, forKey: .reviewed_by)
        review_notes = try container.decodeIfPresent(String.self, forKey: .review_notes)

        // Handle date parsing
        needed_from = try Self.parseDate(from: container, forKey: .needed_from) ?? Date()
        needed_until = try Self.parseDateOptional(from: container, forKey: .needed_until)
        reviewed_at = try Self.parseDateOptional(from: container, forKey: .reviewed_at)
        created_at = try Self.parseDate(from: container, forKey: .created_at) ?? Date()
        updated_at = try Self.parseDate(from: container, forKey: .updated_at) ?? Date()

        // Joined data
        requestedByUser = try container.decodeIfPresent(EquipmentUser.self, forKey: .requestedByUser)
    }

    private static func parseDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let dateValue = try? container.decode(Date.self, forKey: key) {
            return dateValue
        } else if let dateString = try? container.decode(String.self, forKey: key) {
            return parseISODate(dateString)
        }
        return nil
    }

    private static func parseDateOptional(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let dateValue = try? container.decodeIfPresent(Date.self, forKey: key) {
            return dateValue
        } else if let dateString = try? container.decodeIfPresent(String.self, forKey: key) {
            return parseISODate(dateString)
        }
        return nil
    }

    private static func parseISODate(_ string: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = isoFormatter.date(from: string) {
            return parsed
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let parsed = isoFormatter.date(from: string) {
            return parsed
        }
        // Try date-only format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: string)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: EquipmentRequest, rhs: EquipmentRequest) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Kit Template Item Model (stored in JSONB 'items' column)

struct KitTemplateItem: Codable, Hashable {
    let type: String  // "specific" or "category"
    let equipment_id: UUID?  // For type="specific" - links to specific equipment item
    let equipment_name: String?  // Display name cached for UI
    let category_id: UUID?  // For type="category" - any item from this category
    let category_name: String?  // Display name cached for UI
    let quantity: Int?  // For type="category" - how many items needed

    enum CodingKeys: String, CodingKey {
        case type
        case equipment_id, equipment_name
        case category_id, category_name
        case quantity
    }
}

// MARK: - Kit Template Model

struct KitTemplate: Decodable, Identifiable, Hashable {
    let id: UUID
    let organization_id: String  // TEXT type in database (Firebase-style ID)
    let name: String
    let description: String?
    let color: String?  // Hex color code for kit identification tape
    let items: [KitTemplateItem]?  // JSONB array of kit items
    let is_active: Bool
    let created_by: UUID?
    let created_at: Date
    let updated_at: Date

    // Computed properties

    /// Get all specific equipment IDs from items
    var equipmentIds: [UUID] {
        items?.compactMap { $0.type == "specific" ? $0.equipment_id : nil } ?? []
    }

    /// Get item count (for display)
    var itemCount: Int {
        items?.count ?? 0
    }

    /// Check if the kit has a rainbow color
    var isRainbow: Bool {
        color?.lowercased() == "rainbow"
    }

    /// Get color as SwiftUI Color (returns nil for rainbow since it needs special handling)
    var kitColor: Color? {
        guard let hex = color, !isRainbow else { return nil }
        return Color(hex: hex)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, color, items
        case organization_id, is_active, created_by, created_at, updated_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        organization_id = try container.decode(String.self, forKey: .organization_id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        items = try container.decodeIfPresent([KitTemplateItem].self, forKey: .items)
        is_active = try container.decodeIfPresent(Bool.self, forKey: .is_active) ?? true
        created_by = try container.decodeIfPresent(UUID.self, forKey: .created_by)

        // Handle date parsing
        created_at = try Self.parseDate(from: container, forKey: .created_at) ?? Date()
        updated_at = try Self.parseDate(from: container, forKey: .updated_at) ?? Date()
    }

    private static func parseDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        if let dateValue = try? container.decode(Date.self, forKey: key) {
            return dateValue
        } else if let dateString = try? container.decode(String.self, forKey: key) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = isoFormatter.date(from: dateString) {
                return parsed
            }
            isoFormatter.formatOptions = [.withInternetDateTime]
            return isoFormatter.date(from: dateString)
        }
        return nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: KitTemplate, rhs: KitTemplate) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - User Kit Assignment (for My Kits view)

/// Groups a user's equipment assignments by kit
struct UserKitAssignment: Identifiable {
    let id: UUID  // Kit template ID or generated ID for "Other Equipment"
    let kitTemplate: KitTemplate?  // nil if items are not part of any kit
    let assignments: [EquipmentAssignment]  // All items in this kit assigned to user
    let items: [EquipmentItem]  // The actual equipment items

    /// Check if user has ALL items from the kit
    var isComplete: Bool {
        guard let kit = kitTemplate else { return false }
        return kit.equipmentIds.count == assignments.count
    }

    /// Check if this is a permanent assignment (no return date)
    var isPermanent: Bool {
        assignments.first?.expected_return_date == nil
    }

    /// Check if any items are overdue
    var isOverdue: Bool {
        assignments.contains { $0.isOverdue }
    }

    /// Get the expected return date (from first assignment)
    var expectedReturnDate: Date? {
        assignments.first?.expected_return_date
    }

    /// Get days overdue (max from all assignments)
    var daysOverdue: Int? {
        assignments.compactMap { $0.daysOverdue }.max()
    }

    /// Get kit name or "Other Equipment"
    var displayName: String {
        kitTemplate?.name ?? "Other Equipment"
    }

    /// Get kit color hex string (for rainbow support)
    var kitColorHex: String? {
        kitTemplate?.color
    }

    /// Get kit color or nil (returns nil for rainbow - use kitColorHex instead)
    var kitColor: Color? {
        kitTemplate?.kitColor
    }

    /// Get item count
    var itemCount: Int {
        items.count
    }
}

// MARK: - Equipment Permissions Helper

struct EquipmentPermissions {
    let userRole: String

    var canCreateEquipment: Bool {
        ["admin", "manager"].contains(userRole.lowercased())
    }

    var canEditEquipment: Bool {
        ["admin", "manager"].contains(userRole.lowercased())
    }

    var canDeleteEquipment: Bool {
        userRole.lowercased() == "admin"
    }

    var canCheckOutForOthers: Bool {
        ["admin", "manager"].contains(userRole.lowercased())
    }

    var canCheckInAnyItem: Bool {
        ["admin", "manager"].contains(userRole.lowercased())
    }

    var canViewAllAssignments: Bool {
        ["admin", "manager"].contains(userRole.lowercased())
    }

    var canResolveDamageReport: Bool {
        ["admin", "manager"].contains(userRole.lowercased())
    }

    var canApproveRequests: Bool {
        ["admin", "manager"].contains(userRole.lowercased())
    }

    var canManageCategories: Bool {
        ["admin", "manager"].contains(userRole.lowercased())
    }

    var canManageKitTemplates: Bool {
        ["admin", "manager"].contains(userRole.lowercased())
    }
}

// MARK: - Equipment Error Types

enum EquipmentError: LocalizedError {
    case itemNotFound
    case itemNotAvailable
    case kitItemsNotFound
    case itemsNotAvailable([String])
    case unauthorized
    case networkError(Error)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Equipment item not found"
        case .itemNotAvailable:
            return "Equipment is not available for checkout"
        case .kitItemsNotFound:
            return "Kit items could not be found"
        case .itemsNotAvailable(let names):
            return "The following items are not available: \(names.joined(separator: ", "))"
        case .unauthorized:
            return "You don't have permission to perform this action"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown(let message):
            return message
        }
    }
}
