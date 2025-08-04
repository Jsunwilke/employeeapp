import Foundation
import FirebaseFirestore

class TeamService: ObservableObject {
    static let shared = TeamService()
    private let db = Firestore.firestore()
    
    @Published var teamMembers: [TeamMember] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {}
    
    // MARK: - Get Team Members for Organization
    func getTeamMembers(organizationID: String) async throws -> [TeamMember] {
        let query = db.collection("users")
            .whereField("organizationID", isEqualTo: organizationID)
        
        let snapshot = try await query.getDocuments()
        
        let members = snapshot.documents.compactMap { doc -> TeamMember? in
            var data = doc.data()
            data["id"] = doc.documentID
            
            // Convert Firestore timestamps to dates
            if let createdTimestamp = data["createdAt"] as? Timestamp {
                data["createdAt"] = createdTimestamp.dateValue()
            }
            if let updatedTimestamp = data["updatedAt"] as? Timestamp {
                data["updatedAt"] = updatedTimestamp.dateValue()
            }
            
            // Ensure required fields exist
            guard let organizationID = data["organizationID"] as? String,
                  let email = data["email"] as? String,
                  let firstName = data["firstName"] as? String,
                  let lastName = data["lastName"] as? String else {
                return nil
            }
            
            return TeamMember(
                id: doc.documentID,
                organizationID: organizationID,
                email: email,
                firstName: firstName,
                lastName: lastName,
                photoURL: data["photoURL"] as? String,
                isActive: data["isActive"] as? Bool ?? true,
                role: data["role"] as? String ?? "employee",
                displayName: data["displayName"] as? String,
                createdAt: data["createdAt"] as? Date,
                updatedAt: data["updatedAt"] as? Date
            )
        }
        
        // Sort by active status first, then by name
        return members.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
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
        let doc = try await db.collection("users").document(userId).getDocument()
        
        guard doc.exists, var data = doc.data() else {
            return nil
        }
        
        data["id"] = doc.documentID
        
        // Convert Firestore timestamps to dates
        if let createdTimestamp = data["createdAt"] as? Timestamp {
            data["createdAt"] = createdTimestamp.dateValue()
        }
        if let updatedTimestamp = data["updatedAt"] as? Timestamp {
            data["updatedAt"] = updatedTimestamp.dateValue()
        }
        
        guard let organizationID = data["organizationID"] as? String,
              let email = data["email"] as? String,
              let firstName = data["firstName"] as? String,
              let lastName = data["lastName"] as? String else {
            return nil
        }
        
        return TeamMember(
            id: doc.documentID,
            organizationID: organizationID,
            email: email,
            firstName: firstName,
            lastName: lastName,
            photoURL: data["photoURL"] as? String,
            isActive: data["isActive"] as? Bool ?? true,
            role: data["role"] as? String ?? "employee",
            displayName: data["displayName"] as? String,
            createdAt: data["createdAt"] as? Date,
            updatedAt: data["updatedAt"] as? Date
        )
    }
    
    // MARK: - Get Photographers Only
    func getPhotographers(organizationID: String) async throws -> [TeamMember] {
        let allMembers = try await getTeamMembers(organizationID: organizationID)
        
        // In many organizations, all team members can be assigned as photographers
        // You can filter by role if needed
        return allMembers.filter { $0.isActive }
    }
}