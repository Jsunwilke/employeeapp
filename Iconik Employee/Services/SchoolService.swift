import Foundation
import Supabase

@MainActor
class SchoolService: ObservableObject {
    static let shared = SchoolService()
    private let supabase = SupabaseManager.shared.client

    @Published var schools: [School] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {}

    // MARK: - Decoder Error Helper
    private func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing field '\(key.stringValue)' at: \(path.isEmpty ? "root" : path)"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch for \(type) at: \(path.isEmpty ? "root" : path) - \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Null value for \(type) at: \(path.isEmpty ? "root" : path)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Corrupted data at: \(path.isEmpty ? "root" : path) - \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
    
    // MARK: - Get Schools for Organization
    func getSchools(organizationID: String) async throws -> [School] {
        do {
            // Query schools from Supabase (Codable handles snake_case automatically)
            let schools: [School] = try await supabase
                .from("schools")
                .select()
                .eq("organization_id", value: organizationID)
                .execute()
                .value

            // Sort alphabetically by name
            return schools.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        } catch {
            print("❌ SchoolService decode error: \(describeDecodingError(error))")
            throw error
        }
    }
    
    // MARK: - Load Schools with Loading State
    @MainActor
    func loadSchools(organizationID: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            schools = try await getSchools(organizationID: organizationID)
        } catch {
            errorMessage = error.localizedDescription
            print("Error loading schools: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Get School by ID
    func getSchool(schoolId: String) async throws -> School? {
        // Query single school from Supabase by ID
        let schools: [School] = try await supabase
            .from("schools")
            .select()
            .eq("id", value: schoolId)
            .limit(1)
            .execute()
            .value

        return schools.first
    }

    // MARK: - Create School
    func createSchool(
        organizationID: String,
        name: String,
        address: String,
        coordinates: String,
        street: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zip: String? = nil,
        contactName: String? = nil,
        contactEmail: String? = nil,
        contactPhone: String? = nil,
        notes: String? = nil
    ) async throws -> School {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Build the school data dictionary
        var schoolData: [String: AnyJSON] = [
            "organization_id": .string(organizationID),
            "name": .string(name),
            "address": .string(address),
            "coordinates": .string(coordinates),
            "is_active": .bool(true)
        ]

        // Add optional fields if provided
        if let street = street { schoolData["street"] = .string(street) }
        if let city = city { schoolData["city"] = .string(city) }
        if let state = state { schoolData["state"] = .string(state) }
        if let zip = zip { schoolData["zip"] = .string(zip) }
        if let contactName = contactName { schoolData["contact_name"] = .string(contactName) }
        if let contactEmail = contactEmail { schoolData["contact_email"] = .string(contactEmail) }
        if let contactPhone = contactPhone { schoolData["contact_phone"] = .string(contactPhone) }
        if let notes = notes { schoolData["notes"] = .string(notes) }

        do {
            let school: School = try await supabase
                .from("schools")
                .insert(schoolData)
                .select()
                .single()
                .execute()
                .value

            return school
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Update School
    func updateSchool(
        schoolId: String,
        name: String? = nil,
        address: String? = nil,
        coordinates: String? = nil,
        street: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zip: String? = nil,
        contactName: String? = nil,
        contactEmail: String? = nil,
        contactPhone: String? = nil,
        notes: String? = nil,
        isActive: Bool? = nil
    ) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Build update data with only provided fields
        var updateData: [String: AnyJSON] = [:]

        if let name = name { updateData["name"] = .string(name) }
        if let address = address { updateData["address"] = .string(address) }
        if let coordinates = coordinates { updateData["coordinates"] = .string(coordinates) }
        if let street = street { updateData["street"] = .string(street) }
        if let city = city { updateData["city"] = .string(city) }
        if let state = state { updateData["state"] = .string(state) }
        if let zip = zip { updateData["zip"] = .string(zip) }
        if let contactName = contactName { updateData["contact_name"] = .string(contactName) }
        if let contactEmail = contactEmail { updateData["contact_email"] = .string(contactEmail) }
        if let contactPhone = contactPhone { updateData["contact_phone"] = .string(contactPhone) }
        if let notes = notes { updateData["notes"] = .string(notes) }
        if let isActive = isActive { updateData["is_active"] = .bool(isActive) }

        guard !updateData.isEmpty else { return }

        do {
            try await supabase
                .from("schools")
                .update(updateData)
                .eq("id", value: schoolId)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Update Location Photos
    // Note: locationPhotos stored as JSONB array in Supabase
    func updateLocationPhotos(schoolId: String, photos: [[String: String]]) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Convert to AnyJSON array
            let photosJSON: [AnyJSON] = photos.map { dict in
                let jsonDict: [String: AnyJSON] = dict.mapValues { .string($0) }
                return .object(jsonDict)
            }

            try await supabase
                .from("schools")
                .update(["location_photos": AnyJSON.array(photosJSON)])
                .eq("id", value: schoolId)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}