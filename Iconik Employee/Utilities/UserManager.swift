import Foundation
import UIKit
import Combine
import Supabase

class UserManager: ObservableObject {
    static let shared = UserManager()

    @Published var currentUserOrganizationID: String = ""
    @Published var isRefreshing = false

    private var userChannel: RealtimeChannelV2?
    private var cancellables = Set<AnyCancellable>()
    private var supabaseAuthTask: Task<Void, Never>?
    
    private init() {
        // Check for Supabase authenticated user first
        checkSupabaseAuth()

        // Listen for app foreground to refresh profile
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.refreshUserProfile()
            }
            .store(in: &cancellables)
    }
    
    // Get current user's organizationID
    func getCurrentUserOrganizationID(completion: @escaping (String?) -> Void) {
        // Check Supabase auth
        let supabase = SupabaseManager.shared.client
        guard supabase.auth.currentUser != nil else {
            completion(nil)
            return
        }

        // Supabase user - get org ID from UserDefaults (SignInView saves it there)
        if let orgID = UserDefaults.standard.string(forKey: "userOrganizationID"), !orgID.isEmpty {
            DispatchQueue.main.async {
                self.currentUserOrganizationID = orgID
            }
            completion(orgID)
        } else {
            completion(nil)
        }
    }
    
    // Synchronous version that returns cached value
    // Falls back to UserDefaults if @Published property not set yet
    func getCachedOrganizationID() -> String {
        // First try the cached @Published property
        if !currentUserOrganizationID.isEmpty {
            return currentUserOrganizationID
        }

        // Fallback to reading from UserDefaults (where SignInView saves it)
        // This ensures org ID is available immediately after Supabase sign-in
        if let orgID = UserDefaults.standard.string(forKey: "userOrganizationID"), !orgID.isEmpty {
            return orgID
        }

        return ""
    }
    
    // Get current user's ID (returns Supabase ID)
    func getCurrentUserID() -> String? {
        return getCurrentSupabaseUserID()
    }

    // Get current user's Supabase ID
    func getCurrentSupabaseUserID() -> String? {
        let supabase = SupabaseManager.shared.client
        return supabase.auth.currentUser?.id.uuidString.lowercased()
    }

    // Get current user ID (Supabase only)
    func getCurrentUserIDUnified() -> String? {
        return getCurrentSupabaseUserID()
    }
    
    // Initialize user organization ID on app start
    func initializeOrganizationID() {
        getCurrentUserOrganizationID { _ in
            // Organization ID is now cached
        }
    }

    /// Async version that waits for organization ID to be available
    /// Use this on app launch to ensure org ID is ready before showing views
    func initializeOrganizationIDAsync() async {
        // First check if we already have it cached
        if !currentUserOrganizationID.isEmpty {
            return
        }

        // Try to get from UserDefaults
        if let orgID = UserDefaults.standard.string(forKey: "userOrganizationID"), !orgID.isEmpty {
            await MainActor.run {
                currentUserOrganizationID = orgID
            }
            return
        }

        // Fallback: fetch from Supabase users table
        let supabase = SupabaseManager.shared.client
        guard let userId = supabase.auth.currentUser?.id.uuidString.lowercased() else {
            return
        }

        do {
            // Query users table for organization_id
            let response = try await supabase
                .from("users")
                .select("organization_id")
                .eq("id", value: userId)
                .limit(1)
                .single()
                .execute()

            // Decode the response
            struct UserOrgResponse: Codable {
                let organization_id: String
            }

            let decoder = JSONDecoder()
            let userOrg = try decoder.decode(UserOrgResponse.self, from: response.data)

            await MainActor.run {
                self.currentUserOrganizationID = userOrg.organization_id
                UserDefaults.standard.set(userOrg.organization_id, forKey: "userOrganizationID")
            }
        } catch {
            // Silent failure - org ID will remain empty
        }
    }

    /// Force refresh the organization ID from the database
    /// Use this when cached values may be stale (e.g., case mismatch)
    func forceRefreshOrganizationID() async -> String? {
        let supabase = SupabaseManager.shared.client
        guard let userId = supabase.auth.currentUser?.id.uuidString.lowercased() else {
            return nil
        }

        do {
            struct UserOrgResponse: Codable {
                let organization_id: String
            }

            let response = try await supabase
                .from("users")
                .select("organization_id")
                .eq("id", value: userId)
                .limit(1)
                .single()
                .execute()

            let decoder = JSONDecoder()
            let userOrg = try decoder.decode(UserOrgResponse.self, from: response.data)

            await MainActor.run {
                self.currentUserOrganizationID = userOrg.organization_id
                UserDefaults.standard.set(userOrg.organization_id, forKey: "userOrganizationID")
            }

            print("🔄 UserManager: Force refreshed organization ID to '\(userOrg.organization_id)'")
            return userOrg.organization_id
        } catch {
            print("❌ UserManager: Failed to force refresh organization ID: \(error.localizedDescription)")
            return nil
        }
    }
    
    // Refresh user profile data
    func refreshUserProfile() {
        // Check Supabase auth
        let supabase = SupabaseManager.shared.client
        guard supabase.auth.currentUser != nil else { return }

        DispatchQueue.main.async {
            self.isRefreshing = true
        }

        // Use UserProfileService to refresh profile
        Task {
            await UserProfileService.shared.refreshCurrentUserProfile()
        }

        // Also refresh organization ID
        getCurrentUserOrganizationID { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRefreshing = false
            }
        }
    }
    
    // Start listening to real-time updates for user profile using Supabase
    private func startListeningToUserProfile(uid: String) {
        stopListeningToUserProfile()

        let supabase = SupabaseManager.shared.client

        // Create a new channel for this user
        let channel = supabase.channel("user-\(uid)")

        // Set up postgres change listener for user changes
        _ = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "users",
            filter: "id=eq.\(uid)"
        ) { [weak self] _ in
            // Refetch user data when changes are detected
            Task { @MainActor in
                guard let self = self else { return }
                await self.fetchAndUpdateUserProfile(userId: uid)
            }
        }

        // Subscribe to the channel
        Task {
            await channel.subscribe()
        }

        // Store the channel reference
        self.userChannel = channel
        print("🔄 UserManager: Started Supabase realtime listener for user \(uid)")
    }

    // Fetch and update user profile data
    private func fetchAndUpdateUserProfile(userId: String) async {
        do {
            let supabase = SupabaseManager.shared.client

            struct UserOrgResponse: Codable {
                let organization_id: String
            }

            let users: [UserOrgResponse] = try await supabase
                .from("users")
                .select("organization_id")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value

            if let user = users.first {
                if self.currentUserOrganizationID != user.organization_id {
                    self.currentUserOrganizationID = user.organization_id
                    UserDefaults.standard.set(user.organization_id, forKey: "userOrganizationID")
                    // Trigger profile refresh when organization changes
                    await UserProfileService.shared.refreshCurrentUserProfile()
                    print("🔄 UserManager: Organization ID updated to \(user.organization_id)")
                }
            }
        } catch {
            print("❌ UserManager: Failed to fetch user profile: \(error.localizedDescription)")
        }
    }

    // Stop listening to user profile updates
    private func stopListeningToUserProfile() {
        if let channel = userChannel {
            Task {
                let supabase = SupabaseManager.shared.client
                await supabase.removeChannel(channel)
            }
            userChannel = nil
        }
    }

    // MARK: - Supabase Auth Support

    /// Check for active Supabase session and load organization ID
    private func checkSupabaseAuth() {
        Task { @MainActor in
            do {
                let supabase = SupabaseManager.shared.client
                _ = try await supabase.auth.session

                // If we got here, there's an active Supabase session
                let userDefaultsOrgID = UserDefaults.standard.string(forKey: "userOrganizationID")

                if let orgID = userDefaultsOrgID, !orgID.isEmpty {
                    self.currentUserOrganizationID = orgID
                }
            } catch {
                // No active Supabase session, that's OK
            }

            // Set up listener for Supabase auth state changes
            await self.setupSupabaseAuthListener()
        }
    }

    /// Listen for Supabase auth state changes
    private func setupSupabaseAuthListener() async {
        supabaseAuthTask?.cancel()

        supabaseAuthTask = Task { @MainActor in
            let supabase = SupabaseManager.shared.client

            for await state in await supabase.auth.authStateChanges {
                guard !Task.isCancelled else { return }

                switch state.event {
                case .signedIn:
                    // Load organization ID from AppStorage
                    if let orgID = UserDefaults.standard.string(forKey: "userOrganizationID"), !orgID.isEmpty {
                        self.currentUserOrganizationID = orgID
                    }

                case .signedOut:
                    self.currentUserOrganizationID = ""

                default:
                    break
                }
            }
        }
    }

    deinit {
        stopListeningToUserProfile()
        supabaseAuthTask?.cancel()
    }
}