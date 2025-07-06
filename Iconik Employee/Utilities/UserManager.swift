import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore

class UserManager: ObservableObject {
    static let shared = UserManager()
    
    private let db = Firestore.firestore()
    @Published var currentUserOrganizationID: String = ""
    
    private init() {}
    
    // Get current user's organizationID
    func getCurrentUserOrganizationID(completion: @escaping (String?) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            print("🔐 No authenticated user")
            completion(nil)
            return
        }
        
        db.collection("users").document(currentUser.uid).getDocument { document, error in
            if let error = error {
                print("🔐 Error fetching user organizationID: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data(),
                  let organizationID = data["organizationID"] as? String else {
                print("🔐 User document missing or no organizationID field")
                completion(nil)
                return
            }
            
            print("🔐 Found user organizationID: \(organizationID)")
            DispatchQueue.main.async {
                self.currentUserOrganizationID = organizationID
            }
            completion(organizationID)
        }
    }
    
    // Synchronous version that returns cached value
    func getCachedOrganizationID() -> String {
        return currentUserOrganizationID
    }
    
    // Get current user's Firebase Auth UID
    func getCurrentUserID() -> String? {
        return Auth.auth().currentUser?.uid
    }
    
    // Initialize user organization ID on app start
    func initializeOrganizationID() {
        getCurrentUserOrganizationID { _ in
            // Organization ID is now cached
        }
    }
}