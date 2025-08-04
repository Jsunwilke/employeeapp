import Foundation
import FirebaseFirestore
import FirebaseAuth

// Session type definition from organization
struct SessionTypeDefinition: Identifiable {
    let id: String
    let name: String
    let color: String  // Hex color string
}

// Organization model
struct Organization: Codable {
    let id: String
    let name: String
    let sessionTypes: [SessionType]?
    let sessionOrderColors: [String]?
    let enableSessionPublishing: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sessionTypes
        case sessionOrderColors
        case enableSessionPublishing
    }
}

class OrganizationService: ObservableObject {
    static let shared = OrganizationService()
    private let db = Firestore.firestore()
    
    @Published var sessionTypes: [SessionTypeDefinition] = []
    @Published var organizationAddress: String = ""
    @Published var organizationCoordinates: String = ""  // Format: "lat,lng"
    private var organizationListener: ListenerRegistration?
    
    private init() {}
    
    // Start listening to organization data for session types
    func startListeningToOrganization(organizationID: String) {
        print("🏢 Starting to listen to organization: \(organizationID)")
        // Remove existing listener if any
        organizationListener?.remove()
        
        organizationListener = db.collection("organizations").document(organizationID)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching organization: \(error)")
                    return
                }
                
                guard let data = snapshot?.data() else {
                    print("No organization data found")
                    return
                }
                
                // Parse session types
                if let sessionTypesData = data["sessionTypes"] as? [[String: Any]] {
                    self?.sessionTypes = sessionTypesData.compactMap { typeData in
                        guard let id = typeData["id"] as? String,
                              let name = typeData["name"] as? String,
                              let color = typeData["color"] as? String else {
                            return nil
                        }
                        return SessionTypeDefinition(id: id, name: name, color: color)
                    }
                    print("🎨 Loaded \(self?.sessionTypes.count ?? 0) session types: \(self?.sessionTypes.map { $0.name } ?? [])")
                } else {
                    print("No sessionTypes found in organization data")
                    self?.sessionTypes = []
                }
                
                // Parse organization address and coordinates
                if let address = data["address"] as? String {
                    self?.organizationAddress = address
                    print("🏢 Organization address: \(address)")
                }
                
                if let coordinates = data["coordinates"] as? String {
                    self?.organizationCoordinates = coordinates
                    print("📍 Organization coordinates: \(coordinates)")
                } else if let location = data["location"] as? [String: Any],
                          let lat = location["latitude"] as? Double,
                          let lng = location["longitude"] as? Double {
                    self?.organizationCoordinates = "\(lat),\(lng)"
                    print("📍 Organization coordinates: \(lat),\(lng)")
                }
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
        let doc = try await db.collection("organizations").document(organizationID).getDocument()
        
        guard doc.exists, var data = doc.data() else {
            return nil
        }
        
        data["id"] = doc.documentID
        
        // Parse session types if available
        var sessionTypes: [SessionType]? = nil
        if let sessionTypesData = data["sessionTypes"] as? [[String: Any]] {
            sessionTypes = sessionTypesData.compactMap { typeData in
                guard let id = typeData["id"] as? String,
                      let name = typeData["name"] as? String,
                      let color = typeData["color"] as? String else {
                    return nil
                }
                let order = typeData["order"] as? Int ?? 0
                return SessionType(id: id, name: name, color: color, order: order)
            }
        }
        
        return Organization(
            id: doc.documentID,
            name: data["name"] as? String ?? "",
            sessionTypes: sessionTypes,
            sessionOrderColors: data["sessionOrderColors"] as? [String],
            enableSessionPublishing: data["enableSessionPublishing"] as? Bool
        )
    }
    
    // Get organization session types
    func getOrganizationSessionTypes(organization: Organization) -> [SessionType] {
        var customTypes = organization.sessionTypes ?? []
        
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
            return lhs.order < rhs.order
        }
    }
    
    // Stop listening
    func stopListening() {
        organizationListener?.remove()
        organizationListener = nil
    }
}