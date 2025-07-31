import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

// User Profile Model
struct UserProfile {
    let uid: String
    var firstName: String
    var lastName: String
    var displayName: String
    var email: String
    var phone: String
    var homeAddress: String  // This stores coordinates as "lat,lng"
    var address: String  // This stores the full formatted address as a single string
    var city: String  // Kept for backward compatibility
    var state: String  // Kept for backward compatibility
    var zipCode: String  // Kept for backward compatibility
    var country: String  // Kept for backward compatibility
    var organizationID: String
    var role: String
    var bio: String
    var position: String
    var amountPerMile: Double
    var isActive: Bool
    var isFlagged: Bool
    var photoURL: String?
    var createdAt: Date
    var updatedAt: Date
    
    init(uid: String, data: [String: Any]) {
        self.uid = uid
        self.firstName = data["firstName"] as? String ?? ""
        self.lastName = data["lastName"] as? String ?? ""
        self.displayName = data["displayName"] as? String ?? ""
        self.email = data["email"] as? String ?? ""
        self.phone = data["phone"] as? String ?? ""
        self.homeAddress = data["homeAddress"] as? String ?? ""  // This is coordinates
        self.organizationID = data["organizationID"] as? String ?? ""
        self.role = data["role"] as? String ?? "employee"
        self.bio = data["bio"] as? String ?? ""
        self.position = data["position"] as? String ?? ""
        self.amountPerMile = data["amountPerMile"] as? Double ?? 0.3
        self.isActive = data["isActive"] as? Bool ?? true
        self.isFlagged = data["isFlagged"] as? Bool ?? false
        self.photoURL = data["photoURL"] as? String
        
        // Handle address - check for single string first, then fall back to components
        if let addressString = data["address"] as? String {
            // New format: address as a single string
            self.address = addressString
        } else if let addressData = data["address"] as? [String: String] {
            // Legacy format: address as components - reconstruct full address
            let street = addressData["street"] ?? ""
            let city = addressData["city"] ?? ""
            let state = addressData["state"] ?? ""
            let zipCode = addressData["zipCode"] ?? ""
            let country = addressData["country"] ?? ""
            
            // Reconstruct full address
            var components: [String] = []
            if !street.isEmpty { components.append(street) }
            if !city.isEmpty { components.append(city) }
            if !state.isEmpty { components.append(state) }
            if !zipCode.isEmpty { components.append(zipCode) }
            if !country.isEmpty { components.append(country) }
            
            self.address = components.joined(separator: ", ")
        } else {
            self.address = ""
        }
        
        // Extract individual components (for backward compatibility)
        self.city = data["city"] as? String ?? ""
        self.state = data["state"] as? String ?? ""
        self.zipCode = data["zipCode"] as? String ?? ""
        self.country = data["country"] as? String ?? ""
        
        // Parse timestamps
        if let createdTimestamp = data["createdAt"] as? Timestamp {
            self.createdAt = createdTimestamp.dateValue()
        } else {
            self.createdAt = Date()
        }
        
        if let updatedTimestamp = data["updatedAt"] as? Timestamp {
            self.updatedAt = updatedTimestamp.dateValue()
        } else {
            self.updatedAt = Date()
        }
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "firstName": firstName,
            "lastName": lastName,
            "displayName": displayName,
            "email": email,
            "phone": phone,
            "homeAddress": homeAddress,  // Coordinates stored here
            "address": address,  // Full formatted address as single string
            "city": city,  // Keep individual components for backward compatibility
            "state": state,
            "zipCode": zipCode,
            "country": country,
            "organizationID": organizationID,
            "role": role,
            "bio": bio,
            "position": position,
            "amountPerMile": amountPerMile,
            "isActive": isActive,
            "isFlagged": isFlagged,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if let photoURL = photoURL {
            dict["photoURL"] = photoURL
        }
        
        return dict
    }
}

class UserProfileService: ObservableObject {
    static let shared = UserProfileService()
    private let db = Firestore.firestore()
    
    @Published var currentUserProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if user != nil {
                self?.refreshCurrentUserProfile()
            } else {
                self?.currentUserProfile = nil
            }
        }
    }
    
    // Fetch user profile from Firestore
    func fetchUserProfile(uid: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        isLoading = true
        errorMessage = nil
        
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            self?.isLoading = false
            
            if let error = error {
                self?.errorMessage = error.localizedDescription
                completion(.failure(error))
                return
            }
            
            guard let data = snapshot?.data() else {
                let error = NSError(domain: "UserProfileService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User data not found"])
                self?.errorMessage = error.localizedDescription
                completion(.failure(error))
                return
            }
            
            let profile = UserProfile(uid: uid, data: data)
            
            // Update AppStorage
            self?.updateAppStorage(with: profile)
            
            // Update current profile if it's the current user
            if uid == Auth.auth().currentUser?.uid {
                DispatchQueue.main.async {
                    self?.currentUserProfile = profile
                }
            }
            
            completion(.success(profile))
        }
    }
    
    // Refresh current user's profile
    func refreshCurrentUserProfile() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        fetchUserProfile(uid: uid) { result in
            switch result {
            case .success(let profile):
                print("✅ Successfully refreshed user profile for \(profile.displayName)")
            case .failure(let error):
                print("❌ Failed to refresh user profile: \(error.localizedDescription)")
            }
        }
    }
    
    // Update user profile in Firestore
    func updateUserProfile(_ profile: UserProfile, completion: @escaping (Result<Void, Error>) -> Void) {
        guard profile.uid == Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "UserProfileService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Can only update own profile"])))
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        db.collection("users").document(profile.uid).updateData(profile.toDictionary()) { [weak self] error in
            self?.isLoading = false
            
            if let error = error {
                self?.errorMessage = error.localizedDescription
                completion(.failure(error))
                return
            }
            
            // Update local state
            DispatchQueue.main.async {
                self?.currentUserProfile = profile
                self?.updateAppStorage(with: profile)
            }
            
            completion(.success(()))
        }
    }
    
    // Update specific fields only
    func updateUserFields(_ fields: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "UserProfileService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])))
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        var updateData = fields
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        
        db.collection("users").document(uid).updateData(updateData) { [weak self] error in
            self?.isLoading = false
            
            if let error = error {
                self?.errorMessage = error.localizedDescription
                completion(.failure(error))
                return
            }
            
            // Refresh the profile to get the updated data
            self?.refreshCurrentUserProfile()
            
            completion(.success(()))
        }
    }
    
    // Update AppStorage with profile data
    private func updateAppStorage(with profile: UserProfile) {
        @AppStorage("userFirstName") var storedUserFirstName: String = ""
        @AppStorage("userLastName") var storedUserLastName: String = ""
        @AppStorage("userDisplayName") var storedUserDisplayName: String = ""
        @AppStorage("userEmail") var storedUserEmail: String = ""
        @AppStorage("userPhone") var storedUserPhone: String = ""
        @AppStorage("userHomeAddress") var storedUserHomeAddress: String = ""  // Coordinates
        @AppStorage("userAddress") var storedUserAddress: String = ""  // Full address
        @AppStorage("userCity") var storedUserCity: String = ""
        @AppStorage("userState") var storedUserState: String = ""
        @AppStorage("userZipCode") var storedUserZipCode: String = ""
        @AppStorage("userCountry") var storedUserCountry: String = ""
        @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
        @AppStorage("userRole") var storedUserRole: String = ""
        @AppStorage("userBio") var storedUserBio: String = ""
        @AppStorage("userPosition") var storedUserPosition: String = ""
        @AppStorage("userPhotoURL") var storedUserPhotoURL: String = ""
        
        storedUserFirstName = profile.firstName
        storedUserLastName = profile.lastName
        storedUserDisplayName = profile.displayName
        storedUserEmail = profile.email
        storedUserPhone = profile.phone
        storedUserHomeAddress = profile.homeAddress  // Coordinates
        storedUserAddress = profile.address  // Full address
        storedUserCity = profile.city
        storedUserState = profile.state
        storedUserZipCode = profile.zipCode
        storedUserCountry = profile.country
        storedUserOrganizationID = profile.organizationID
        storedUserRole = profile.role
        storedUserBio = profile.bio
        storedUserPosition = profile.position
        storedUserPhotoURL = profile.photoURL ?? ""
    }
    
    // Listen for real-time updates to user profile
    func listenToUserProfile(uid: String, onChange: @escaping (UserProfile?) -> Void) -> ListenerRegistration {
        return db.collection("users").document(uid).addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Error listening to user profile: \(error.localizedDescription)")
                onChange(nil)
                return
            }
            
            guard let data = snapshot?.data() else {
                onChange(nil)
                return
            }
            
            let profile = UserProfile(uid: uid, data: data)
            onChange(profile)
        }
    }
}