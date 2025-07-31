import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
import Combine

class UserManager: ObservableObject {
    static let shared = UserManager()
    
    private let db = Firestore.firestore()
    @Published var currentUserOrganizationID: String = ""
    @Published var isRefreshing = false
    
    private var profileListener: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user {
                self?.startListeningToUserProfile(uid: user.uid)
                self?.refreshUserProfile()
            } else {
                self?.stopListeningToUserProfile()
            }
        }
        
        // Listen for app foreground to refresh profile
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.refreshUserProfile()
            }
            .store(in: &cancellables)
    }
    
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
    
    // Refresh user profile data
    func refreshUserProfile() {
        guard Auth.auth().currentUser != nil else { return }
        
        DispatchQueue.main.async {
            self.isRefreshing = true
        }
        
        // Use UserProfileService to refresh profile
        UserProfileService.shared.refreshCurrentUserProfile()
        
        // Also refresh organization ID
        getCurrentUserOrganizationID { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRefreshing = false
            }
        }
    }
    
    // Start listening to real-time updates for user profile
    private func startListeningToUserProfile(uid: String) {
        stopListeningToUserProfile()
        
        profileListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, error in
            if let error = error {
                print("🔐 Error listening to user profile: \(error.localizedDescription)")
                return
            }
            
            guard let data = snapshot?.data(),
                  let organizationID = data["organizationID"] as? String else {
                return
            }
            
            DispatchQueue.main.async {
                if self?.currentUserOrganizationID != organizationID {
                    self?.currentUserOrganizationID = organizationID
                    // Trigger profile refresh when organization changes
                    UserProfileService.shared.refreshCurrentUserProfile()
                }
            }
        }
    }
    
    // Stop listening to user profile updates
    private func stopListeningToUserProfile() {
        profileListener?.remove()
        profileListener = nil
    }
    
    deinit {
        stopListeningToUserProfile()
    }
}