import Foundation
import Supabase

// Session type definition from organization
struct SessionTypeDefinition: Identifiable {
    let id: String
    let name: String
    let color: String  // Hex color string
}

// Pay Period Settings model - matches the JSON structure in database
// Structure: {"type": "bi-weekly", "config": {"start_date": "2024-12-29"}, "is_active": true}
struct PayPeriodSettings: Codable {
    let type: String? // "bi-weekly", "weekly", "monthly"
    let config: PayPeriodConfig?
    let is_active: Bool?

    // Backward compatibility computed properties
    var startDate: String? { config?.start_date }
    var isActive: Bool { is_active ?? false }

    struct PayPeriodConfig: Codable {
        let start_date: String?
    }
}

// Organization model (snake_case for Supabase)
// JSONB fields are decoded as native Swift types (Supabase returns native JSONB)
struct Organization: Codable {
    let id: String
    let name: String?
    let session_types: [SessionType]?  // Native JSONB array
    let session_order_colors: [String]?  // Native JSONB array
    let enable_session_publishing: Bool?
    let pay_period_settings: PayPeriodSettings?  // Native JSONB object
    let address: AnyJSON?  // JSONB object - flexible type
    let coordinates: String?  // Format: "lat,lng"
    let created_at: String?  // ISO8601 string
    let updated_at: String?  // ISO8601 string
    let use_photoshoot_notes_only: Bool?  // NEW: Toggle for photoshoot notes vs daily reports

    // Backward compatibility computed properties
    var enableSessionPublishing: Bool? { enable_session_publishing }
    var usePhotoshootNotesOnly: Bool { use_photoshoot_notes_only ?? false }

    // Extract address string from JSONB object
    var addressString: String? {
        guard let address = address else { return nil }
        // If it's a string, return it directly
        if case .string(let str) = address { return str }
        // If it's an object, try to get a "formatted" or "full" key, or convert to string
        if case .object(let dict) = address {
            if case .string(let formatted) = dict["formatted"] { return formatted }
            if case .string(let full) = dict["full"] { return full }
            if case .string(let street) = dict["street"] { return street }
        }
        return nil
    }
}

@MainActor
class OrganizationService: ObservableObject {
    static let shared = OrganizationService()
    private let supabase = SupabaseManager.shared.client

    @Published var sessionTypes: [SessionTypeDefinition] = []
    @Published var organizationAddress: String = ""
    @Published var organizationCoordinates: String = ""  // Format: "lat,lng"
    @Published var organizationHasPublishing: Bool = false
    @Published var usePhotoshootNotesOnly: Bool = false  // NEW: Toggle for photoshoot notes vs daily reports
    private var organizationChannel: RealtimeChannelV2?

    private init() {}
    
    // Start listening to organization data for session types
    func startListeningToOrganization(organizationID: String) {
        print("🏢 Starting to listen to organization: \(organizationID)")

        // Remove existing channel if any
        if let channel = organizationChannel {
            Task {
                await channel.unsubscribe()
            }
            organizationChannel = nil
        }

        // Create a new channel for this organization using realtimeV2
        let channel = supabase.realtimeV2.channel("organization-\(organizationID)")

        // Set up postgres change listener
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "organizations",
            filter: "id=eq.\(organizationID)"
        )

        // Store the channel reference
        self.organizationChannel = channel

        Task {
            // Subscribe to the channel
            await channel.subscribe()

            // Initial fetch
            await fetchAndUpdateOrganization(organizationID: organizationID)

            // Listen for changes
            Task {
                for await _ in changes {
                    await self.fetchAndUpdateOrganization(organizationID: organizationID)
                }
            }
        }
    }

    // Helper to fetch and update organization data
    private func fetchAndUpdateOrganization(organizationID: String) async {
        do {
            guard let org = try await getOrganization(organizationID: organizationID) else {
                print("No organization data found")
                return
            }

            // Get session types from JSONB (native array from Supabase)
            if let sessionTypesArray = org.session_types {
                self.sessionTypes = sessionTypesArray.map { type in
                    SessionTypeDefinition(id: type.id, name: type.name, color: type.color)
                }
                print("🎨 Loaded \(self.sessionTypes.count) session types: \(self.sessionTypes.map { $0.name })")
            } else {
                print("No sessionTypes found in organization data")
                self.sessionTypes = []
            }

            // Update organization address
            if let address = org.addressString {
                self.organizationAddress = address
                print("🏢 Organization address: \(address)")
            }

            // Update organization coordinates
            if let coordinates = org.coordinates {
                self.organizationCoordinates = coordinates
                print("📍 Organization coordinates: \(coordinates)")
            }

            // Update publishing setting
            self.organizationHasPublishing = org.enable_session_publishing ?? false
            print("📝 Organization has publishing: \(self.organizationHasPublishing)")

            // Update photoshoot notes only setting
            self.usePhotoshootNotesOnly = org.use_photoshoot_notes_only ?? false
            print("📸 Organization uses photoshoot notes only: \(self.usePhotoshootNotesOnly)")

        } catch {
            print("Error fetching organization: \(error.localizedDescription)")
        }
    }
    
    // Get session type by ID or name (for backward compatibility)
    func getSessionType(by idOrName: String) -> SessionTypeDefinition? {
        print("🔍 Looking for session type '\(idOrName)' in \(sessionTypes.count) types")
        // First try to match by ID
        if let typeById = sessionTypes.first(where: { $0.id == idOrName }) {
            print("✅ Found by ID: \(typeById.name)")
            return typeById
        }
        // Then try to match by name (case insensitive)
        if let typeByName = sessionTypes.first(where: { $0.name.lowercased() == idOrName.lowercased() }) {
            print("✅ Found by name: \(typeByName.name)")
            return typeByName
        }
        print("❌ Not found: '\(idOrName)'")
        return nil
    }
    
    // Get organization by ID
    func getOrganization(organizationID: String) async throws -> Organization? {
        // Query organization from Supabase (Codable handles JSONB automatically)
        let orgs: [Organization] = try await supabase
            .from("organizations")
            .select()
            .eq("id", value: organizationID)
            .limit(1)
            .execute()
            .value

        if orgs.isEmpty {
            print("❌ OrganizationService: No organization found for id \(organizationID)")
        }

        return orgs.first
    }
    
    // Get organization session types
    func getOrganizationSessionTypes(organization: Organization) -> [SessionType] {
        var customTypes = organization.session_types ?? []
        
        // Add order field to types that don't have it
        customTypes = customTypes.enumerated().map { index, type in
            var updatedType = type
            if updatedType.order == 0 {
                updatedType.order = type.id == "other" ? 9999 : index + 1
            }
            return updatedType
        }
        
        // Always ensure "Other" is available
        let hasOther = customTypes.contains { $0.id == "other" }
        if !hasOther {
            customTypes.append(SessionType(
                id: "other",
                name: "Other",
                color: "#000000",
                order: 9999
            ))
        }
        
        // Sort by order, ensuring "Other" is always last
        return customTypes.sorted { lhs, rhs in
            if lhs.id == "other" { return false }
            if rhs.id == "other" { return true }
            return (lhs.order ?? 0) < (rhs.order ?? 0)
        }
    }
    
    // Enable session publishing for organization
    func enableSessionPublishing(organizationID: String) async throws {
        try await supabase
            .from("organizations")
            .update(["enable_session_publishing": AnyJSON.bool(true)])
            .eq("id", value: organizationID)
            .execute()

        print("✅ Enabled session publishing for organization: \(organizationID)")
    }

    // Stop listening
    func stopListening() {
        if let channel = organizationChannel {
            Task {
                await channel.unsubscribe()
            }
            organizationChannel = nil
        }
    }
}