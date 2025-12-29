import Foundation
import SwiftUI
import Supabase

// User Profile Model (Supabase version - properties use snake_case to match database)
// All String fields are optional to handle NULL values in database
struct UserProfile: Codable {
    let id: String
    var first_name: String?
    var last_name: String?
    var display_name: String?
    var email: String?
    var phone: String?
    var home_address: String?  // This stores coordinates as "lat,lng"
    var address: String?  // This stores the full formatted address as a single string
    var city: String?
    var state: String?
    var zip_code: String?
    var country: String?
    var organization_id: String?
    var role: String?
    var bio: String?
    var position: String?
    var amount_per_mile: Double?
    var is_active: Bool?
    var is_flagged: Bool?
    var photo_url: String?
    var created_at: Date?
    var updated_at: Date?

    // Photographer/Role flags
    var is_photographer: Bool?
    var is_accountant: Bool?

    // Payroll fields
    var compensation_type: String?  // "hourly" or "salary"
    var hourly_rate: Double?
    var salary_amount: Double?
    var overtime_threshold: Int?  // Default 40

    // Photo fields
    var original_photo_url: String?
    var photo_crop_settings: AnyJSON?  // JSONB - native object from Supabase

    // Push notifications
    var fcm_token: String?
    var fcm_token_updated_at: Date?

    // Invitation fields
    var is_temporary_invite: Bool?
    var invited_at: Date?

    // Preferences (JSONB - native objects from Supabase)
    var preferences: AnyJSON?
    var email_notifications: AnyJSON?
    var notify_on_proofing_approval: Bool?

    // Computed properties for backward compatibility with camelCase (with defaults)
    var uid: String { id }
    var firstName: String { first_name ?? "" }
    var lastName: String { last_name ?? "" }
    var displayName: String { display_name ?? "" }
    var emailAddress: String { email ?? "" }  // Use emailAddress to avoid conflict with email field
    var phoneNumber: String { phone ?? "" }  // Use phoneNumber to avoid conflict with phone field
    var fullAddress: String { address ?? "" }  // Use fullAddress to avoid conflict with address field
    var cityName: String { city ?? "" }
    var stateName: String { state ?? "" }
    var countryName: String { country ?? "" }
    var bioText: String { bio ?? "" }
    var positionTitle: String { position ?? "" }
    var userRole: String { role ?? "employee" }
    var photoURL: String? { photo_url }
    var homeAddress: String { home_address ?? "" }
    var zipCode: String { zip_code ?? "" }
    var organizationID: String { organization_id ?? "" }
    var amountPerMile: Double { amount_per_mile ?? 0.3 }
    var isActive: Bool { is_active ?? true }
    var isFlagged: Bool { is_flagged ?? false }
    var createdAt: Date? { created_at }
    var updatedAt: Date? { updated_at }

    // New camelCase computed properties
    var isPhotographer: Bool { is_photographer ?? false }
    var isAccountant: Bool { is_accountant ?? false }
    var compensationType: String? { compensation_type }
    var hourlyRate: Double? { hourly_rate }
    var salaryAmount: Double? { salary_amount }
    var overtimeThreshold: Int { overtime_threshold ?? 40 }
    var originalPhotoURL: String? { original_photo_url }
    var photoCropSettings: String? {
        guard let json = photo_crop_settings else { return nil }
        if let data = try? JSONEncoder().encode(json) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    var fcmToken: String? { fcm_token }
    var fcmTokenUpdatedAt: Date? { fcm_token_updated_at }
    var isTemporaryInvite: Bool { is_temporary_invite ?? false }
    var invitedAt: Date? { invited_at }
    var notifyOnProofingApproval: Bool { notify_on_proofing_approval ?? false }
    var emailNotifications: String? {
        guard let json = email_notifications else { return nil }
        if let data = try? JSONEncoder().encode(json) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    // Default initializer with all values (all optional with nil defaults)
    init(id: String, first_name: String? = nil, last_name: String? = nil, display_name: String? = nil,
         email: String? = nil, phone: String? = nil, home_address: String? = nil, address: String? = nil,
         city: String? = nil, state: String? = nil, zip_code: String? = nil, country: String? = nil,
         organization_id: String? = nil, role: String? = nil, bio: String? = nil,
         position: String? = nil, amount_per_mile: Double? = nil, is_active: Bool? = nil,
         is_flagged: Bool? = nil, photo_url: String? = nil,
         created_at: Date? = nil, updated_at: Date? = nil,
         is_photographer: Bool? = nil, is_accountant: Bool? = nil,
         compensation_type: String? = nil, hourly_rate: Double? = nil,
         salary_amount: Double? = nil, overtime_threshold: Int? = nil,
         original_photo_url: String? = nil, photo_crop_settings: AnyJSON? = nil,
         fcm_token: String? = nil, fcm_token_updated_at: Date? = nil,
         is_temporary_invite: Bool? = nil, invited_at: Date? = nil,
         preferences: AnyJSON? = nil, email_notifications: AnyJSON? = nil,
         notify_on_proofing_approval: Bool? = nil) {
        self.id = id
        self.first_name = first_name
        self.last_name = last_name
        self.display_name = display_name
        self.email = email
        self.phone = phone
        self.home_address = home_address
        self.address = address
        self.city = city
        self.state = state
        self.zip_code = zip_code
        self.country = country
        self.organization_id = organization_id
        self.role = role
        self.bio = bio
        self.position = position
        self.amount_per_mile = amount_per_mile
        self.is_active = is_active
        self.is_flagged = is_flagged
        self.photo_url = photo_url
        self.created_at = created_at
        self.updated_at = updated_at
        self.is_photographer = is_photographer
        self.is_accountant = is_accountant
        self.compensation_type = compensation_type
        self.hourly_rate = hourly_rate
        self.salary_amount = salary_amount
        self.overtime_threshold = overtime_threshold
        self.original_photo_url = original_photo_url
        self.photo_crop_settings = photo_crop_settings
        self.fcm_token = fcm_token
        self.fcm_token_updated_at = fcm_token_updated_at
        self.is_temporary_invite = is_temporary_invite
        self.invited_at = invited_at
        self.preferences = preferences
        self.email_notifications = email_notifications
        self.notify_on_proofing_approval = notify_on_proofing_approval
    }
}

@MainActor
class UserProfileService: ObservableObject {
    static let shared = UserProfileService()
    private let supabase = SupabaseManager.shared.client

    @Published var currentUserProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var authStateTask: Task<Void, Never>?

    private init() {
        // Listen for auth state changes from Supabase
        authStateTask = Task {
            for await state in await supabase.auth.authStateChanges {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    if state.session != nil {
                        Task {
                            await self.refreshCurrentUserProfile()
                        }
                    } else {
                        self.currentUserProfile = nil
                    }
                }
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }
    
    // Fetch user profile from Supabase (async/await version)
    func fetchUserProfile(uid: String) async throws -> UserProfile {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let profile: UserProfile = try await supabase
                .from("users")
                .select()
                .eq("id", value: uid.lowercased())
                .single()
                .execute()
                .value

            // Update AppStorage
            updateAppStorage(with: profile)

            // Update current profile if it's the current user
            if uid == supabase.auth.currentUser?.id.uuidString {
                self.currentUserProfile = profile
            }

            return profile

        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // Legacy completion-based fetch for backward compatibility
    func fetchUserProfile(uid: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        Task {
            do {
                let profile = try await fetchUserProfile(uid: uid)
                completion(.success(profile))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // Refresh current user's profile
    func refreshCurrentUserProfile() async {
        guard let uid = supabase.auth.currentUser?.id.uuidString else { return }

        do {
            let profile = try await fetchUserProfile(uid: uid)
            print("✅ Successfully refreshed user profile for \(profile.displayName)")
        } catch {
            print("❌ Failed to refresh user profile: \(error.localizedDescription)")
        }
    }

    // Update user profile in Supabase
    func updateUserProfile(_ profile: UserProfile) async throws {
        guard profile.uid == supabase.auth.currentUser?.id.uuidString else {
            throw NSError(domain: "UserProfileService", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Can only update own profile"])
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Update profile using Codable directly (Supabase SDK 2.x)
            try await supabase
                .from("users")
                .update(profile)
                .eq("id", value: profile.id)
                .execute()

            // Update local state
            self.currentUserProfile = profile
            updateAppStorage(with: profile)

        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // Legacy completion-based update for backward compatibility
    func updateUserProfile(_ profile: UserProfile, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await updateUserProfile(profile)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // Update specific fields only (using snake_case field names)
    func updateUserFields(_ fields: [String: AnyJSON]) async throws {
        guard let uid = supabase.auth.currentUser?.id.uuidString else {
            throw NSError(domain: "UserProfileService", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Note: Fields should be in snake_case for Supabase
            try await supabase
                .from("users")
                .update(fields)
                .eq("id", value: uid.lowercased())
                .execute()

            // Refresh the profile to get the updated data
            await refreshCurrentUserProfile()

        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // Legacy completion-based field update for backward compatibility
    func updateUserFields(_ fields: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                // Convert [String: Any] to [String: AnyJSON]
                let jsonFields = try fields.mapValues { value -> AnyJSON in
                    let data = try JSONSerialization.data(withJSONObject: value)
                    return try JSONDecoder().decode(AnyJSON.self, from: data)
                }
                try await updateUserFields(jsonFields)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
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

        storedUserFirstName = profile.first_name ?? ""
        storedUserLastName = profile.last_name ?? ""
        storedUserDisplayName = profile.display_name ?? ""
        storedUserEmail = profile.email ?? ""
        storedUserPhone = profile.phone ?? ""
        storedUserHomeAddress = profile.home_address ?? ""  // Coordinates
        storedUserAddress = profile.address ?? ""  // Full address
        storedUserCity = profile.city ?? ""
        storedUserState = profile.state ?? ""
        storedUserZipCode = profile.zip_code ?? ""
        storedUserCountry = profile.country ?? ""
        storedUserOrganizationID = profile.organization_id ?? ""
        storedUserRole = profile.role ?? ""
        storedUserBio = profile.bio ?? ""
        storedUserPosition = profile.position ?? ""
        storedUserPhotoURL = profile.photo_url ?? ""
    }
    
    // Listen for real-time updates to user profile using Supabase channels
    func listenToUserProfile(uid: String, onChange: @escaping (UserProfile?) -> Void) -> RealtimeChannelV2 {
        let channel = supabase.channel("user-profile-\(uid)")

        // Set up the postgres change listener
        _ = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "users",
            filter: "id=eq.\(uid)"
        ) { [weak self] _ in
            // Refetch the profile when changes are detected
            Task { @MainActor in
                do {
                    guard let self = self else { return }
                    let profile = try await self.fetchUserProfile(uid: uid)
                    onChange(profile)
                } catch {
                    print("❌ Error fetching updated user profile: \(error.localizedDescription)")
                    onChange(nil)
                }
            }
        }

        // Subscribe to the channel
        Task {
            await channel.subscribe()
        }

        return channel
    }

    // Helper to unsubscribe from a channel
    func unsubscribe(from channel: RealtimeChannelV2) async {
        await supabase.removeChannel(channel)
    }
}