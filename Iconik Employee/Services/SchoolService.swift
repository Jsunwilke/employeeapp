import Foundation
import FirebaseFirestore

class SchoolService: ObservableObject {
    static let shared = SchoolService()
    private let db = Firestore.firestore()
    
    @Published var schools: [School] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {}
    
    // MARK: - Get Schools for Organization
    func getSchools(organizationID: String) async throws -> [School] {
        let query = db.collection("schools")
            .whereField("organizationID", isEqualTo: organizationID)
        
        let snapshot = try await query.getDocuments()
        
        let schools = snapshot.documents.compactMap { doc -> School? in
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
                  let value = data["value"] as? String else {
                return nil
            }
            
            return School(
                id: doc.documentID,
                organizationID: organizationID,
                value: value,
                isActive: data["isActive"] as? Bool ?? true,
                createdAt: data["createdAt"] as? Date,
                updatedAt: data["updatedAt"] as? Date
            )
        }
        
        // Sort alphabetically by name
        return schools.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
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
        let doc = try await db.collection("schools").document(schoolId).getDocument()
        
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
              let value = data["value"] as? String else {
            return nil
        }
        
        return School(
            id: doc.documentID,
            organizationID: organizationID,
            value: value,
            isActive: data["isActive"] as? Bool ?? true,
            createdAt: data["createdAt"] as? Date,
            updatedAt: data["updatedAt"] as? Date
        )
    }
}