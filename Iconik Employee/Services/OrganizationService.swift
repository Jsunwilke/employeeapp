import Foundation
import FirebaseFirestore
import FirebaseAuth

// Session type definition from organization
struct SessionTypeDefinition: Identifiable {
    let id: String
    let name: String
    let color: String  // Hex color string
}

class OrganizationService: ObservableObject {
    static let shared = OrganizationService()
    private let db = Firestore.firestore()
    
    @Published var sessionTypes: [SessionTypeDefinition] = []
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
    
    // Stop listening
    func stopListening() {
        organizationListener?.remove()
        organizationListener = nil
    }
}