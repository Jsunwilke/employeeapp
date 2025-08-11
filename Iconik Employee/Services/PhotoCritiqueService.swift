import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

class PhotoCritiqueService: ObservableObject {
    static let shared = PhotoCritiqueService()
    
    @Published var critiques: [Critique] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var filter: FilterType = .all
    
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()
    
    enum FilterType: String, CaseIterable {
        case all = "All Examples"
        case good = "Good Examples"
        case improvement = "Needs Improvement"
    }
    
    private init() {}
    
    // Start listening for critiques for the current user
    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("No authenticated user found")
            return
        }
        
        let organizationId = UserManager.shared.getCachedOrganizationID()
        guard !organizationId.isEmpty else {
            print("No organization ID found, fetching...")
            // Try to get organization ID and then start listening
            UserManager.shared.getCurrentUserOrganizationID { [weak self] orgId in
                guard let orgId = orgId else {
                    print("Failed to get organization ID")
                    return
                }
                self?.startListeningWithOrgId(userId: userId, organizationId: orgId)
            }
            return
        }
        
        startListeningWithOrgId(userId: userId, organizationId: organizationId)
    }
    
    private func startListeningWithOrgId(userId: String, organizationId: String) {
        isLoading = true
        error = nil
        
        listener = db.collection("photoCritiques")
            .whereField("targetPhotographerId", isEqualTo: userId)
            .whereField("organizationId", isEqualTo: organizationId)
            .whereField("status", isEqualTo: "published")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                self?.isLoading = false
                
                if let error = error {
                    print("Error fetching critiques: \(error.localizedDescription)")
                    self?.error = error
                    return
                }
                
                self?.critiques = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: Critique.self)
                } ?? []
                
                print("Loaded \(self?.critiques.count ?? 0) critiques")
            }
    }
    
    // Stop listening for changes
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    // Get filtered critiques based on current filter
    var filteredCritiques: [Critique] {
        switch filter {
        case .all:
            return critiques
        case .good:
            return critiques.filter { $0.isGoodExample }
        case .improvement:
            return critiques.filter { !$0.isGoodExample }
        }
    }
    
    // Calculate statistics
    var statistics: CritiqueStats {
        CritiqueStats(
            total: critiques.count,
            goodExamples: critiques.filter { $0.isGoodExample }.count,
            needsImprovement: critiques.filter { !$0.isGoodExample }.count
        )
    }
    
    // Refresh critiques
    func refresh() {
        stopListening()
        startListening()
    }
    
    // Get a specific critique by ID
    func getCritique(by id: String) -> Critique? {
        critiques.first { $0.id == id }
    }
}