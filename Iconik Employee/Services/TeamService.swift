import Foundation
import Supabase

@MainActor
class TeamService: ObservableObject {
    static let shared = TeamService()
    private let supabase = SupabaseManager.shared.client

    @Published var teamMembers: [TeamMember] = []
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
    
    // MARK: - Get Team Members for Organization
    func getTeamMembers(organizationID: String) async throws -> [TeamMember] {
        do {
            // Query users from Supabase (Codable handles snake_case automatically)
            let members: [TeamMember] = try await supabase
                .from("users")
                .select()
                .eq("organization_id", value: organizationID)
                .execute()
                .value

            // Sort by active status first, then by name
            return members.sorted { lhs, rhs in
                if lhs.is_active != rhs.is_active {
                    return lhs.is_active
                }
                return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
        } catch {
            print("❌ TeamService decode error: \(describeDecodingError(error))")
            throw error
        }
    }
    
    // MARK: - Load Team Members with Loading State
    @MainActor
    func loadTeamMembers(organizationID: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            teamMembers = try await getTeamMembers(organizationID: organizationID)
        } catch {
            errorMessage = error.localizedDescription
            print("Error loading team members: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Get Team Member by ID
    func getTeamMember(userId: String) async throws -> TeamMember? {
        // Query single user from Supabase by ID
        let members: [TeamMember] = try await supabase
            .from("users")
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value

        return members.first
    }
    
    // MARK: - Get Photographers Only
    func getPhotographers(organizationID: String) async throws -> [TeamMember] {
        let allMembers = try await getTeamMembers(organizationID: organizationID)

        // In many organizations, all team members can be assigned as photographers
        // You can filter by role if needed
        return allMembers.filter { $0.isActive }
    }

    // MARK: - Get Flagged Users
    func getFlaggedUsers(organizationID: String) async throws -> [TeamMember] {
        let members: [TeamMember] = try await supabase
            .from("users")
            .select()
            .eq("organization_id", value: organizationID)
            .eq("is_flagged", value: true)
            .execute()
            .value

        return members.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    // MARK: - Flag User (Admin Only)
    func flagUser(userId: String, note: String, flaggedBy: String) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            try await supabase
                .from("users")
                .update([
                    "is_flagged": AnyJSON.bool(true),
                    "flag_note": AnyJSON.string(note),
                    "flagged_by": AnyJSON.string(flaggedBy)
                ])
                .eq("id", value: userId)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Unflag User (Admin Only)
    func unflagUser(userId: String) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            try await supabase
                .from("users")
                .update([
                    "is_flagged": AnyJSON.bool(false),
                    "flag_note": AnyJSON.string(""),
                    "flagged_by": AnyJSON.null
                ])
                .eq("id", value: userId)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}