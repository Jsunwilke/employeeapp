//
//  SupabaseAuthService.swift
//  Iconik Employee
//
//  Created on 2025-12-25
//  Authentication service using Supabase Auth
//

import Foundation
import Supabase
import Combine

/// Authentication service for Supabase
/// Handles sign in, sign up, sign out, and password reset
@MainActor
class SupabaseAuthService: ObservableObject {
    // MARK: - Singleton

    static let shared = SupabaseAuthService()

    // MARK: - Published Properties

    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    /// Becomes true once checkSession() has completed (regardless of outcome).
    /// RootView waits on this instead of a fixed 100ms sleep.
    @Published var sessionCheckComplete = false

    // MARK: - Private Properties

    private let supabase = SupabaseManager.shared.client
    private var authStateTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var currentUserId: String? {
        return currentUser?.id.uuidString.lowercased()
    }

    var currentUserEmail: String? {
        return currentUser?.email
    }

    // MARK: - Initialization

    private init() {
        // Get initial session
        Task {
            await checkSession()
            await setupAuthStateListener()
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Session Management

    /// Check if there's an active session
    func checkSession() async {
        do {
            let session = try await supabase.auth.session
            self.currentUser = session.user
            self.isAuthenticated = true
            print("[SupabaseAuthService] Active session found for user: \(session.user.id)")
        } catch {
            self.currentUser = nil
            self.isAuthenticated = false
            print("[SupabaseAuthService] No active session")
        }
        self.sessionCheckComplete = true
    }

    /// Setup auth state change listener
    private func setupAuthStateListener() async {
        authStateTask = Task {
            for await state in await supabase.auth.authStateChanges {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    switch state.event {
                    case .signedIn:
                        self.currentUser = state.session?.user
                        self.isAuthenticated = true
                        print("[SupabaseAuthService] User signed in: \(state.session?.user.id.uuidString ?? "unknown")")

                        // APNs hands us the device token during launch, which on a first-ever
                        // launch is before anyone has signed in — so it had nobody to attach to
                        // and was lost until the next cold launch. Store it now.
                        PushNotificationManager.flushPendingAPNsToken()

                    case .signedOut:
                        // NOTE: the APNs token is detached in signOut() above, not here.
                        // By the time this event fires the SDK has already removed the
                        // session, so a database write from this point runs unauthenticated
                        // and silently affects no rows.
                        self.currentUser = nil
                        self.isAuthenticated = false
                        print("[SupabaseAuthService] User signed out")

                    case .tokenRefreshed:
                        self.currentUser = state.session?.user
                        print("[SupabaseAuthService] Token refreshed")

                    case .userUpdated:
                        self.currentUser = state.session?.user
                        print("[SupabaseAuthService] User updated")

                    default:
                        break
                    }
                }
            }
        }
    }

    // MARK: - Email/Password Authentication

    /// Sign in with email and password
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )

            self.currentUser = session.user
            self.isAuthenticated = true

            print("[SupabaseAuthService] Sign in successful: \(session.user.id)")
        } catch {
            print("[SupabaseAuthService] Sign in error: \(error.localizedDescription)")
            throw error
        }
    }

    /// Sign up with email and password
    func signUp(email: String, password: String, metadata: [String: AnyJSON]? = nil) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: metadata
            )

            self.currentUser = session.user
            self.isAuthenticated = true

            print("[SupabaseAuthService] Sign up successful: \(session.user.id)")
        } catch {
            print("[SupabaseAuthService] Sign up error: \(error.localizedDescription)")
            throw error
        }
    }

    /// Sign out current user.
    ///
    /// Before the auth state flips to signed-out, purge ALL locally
    /// persisted user data — not just the SubscriptionCache. Shared iPads
    /// are handed between accounts (and sometimes to non-employees
    /// on-site), so student rosters, pending edit queues, chat caches,
    /// schedule caches, and the user's own PII must not survive into the
    /// next session. Wipes run BEFORE supabase.auth.signOut so they
    /// execute while auth context is still valid (defensive ordering),
    /// and each wipe is independent — one failing must not skip the rest.
    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }

        // 1. Gallery subscription cache (subject names, contact info)
        SubscriptionCache.shared.purgeAll()

        // 2. PowerSync roster database (student PII) — disconnect + clear
        await PowerSyncManager.shared.wipeForSignOut()

        // 3. Pending subject-edit command queue (payloads contain PII)
        do {
            try await CommandQueue.shared.purgeAll()
        } catch {
            print("[SupabaseAuthService] CommandQueue purge failed: \(error)")
        }

        // 4. Chat conversations/messages/users caches
        ChatCacheService.shared.clearAllCache()

        // 5. Schedule + time-entry disk caches
        await ScheduleCacheManager.shared.clearCache()
        await TimeEntryCacheManager.shared.clearCache()
        SessionService.shared.clearCache()

        // 6. Cached role/permissions map
        PermissionsService.shared.clear()

        // 6b. Detach this handset's push token from the account.
        //     MUST happen here, before supabase.auth.signOut() below, for exactly the
        //     reason this function's header comment gives: it is a database write and it
        //     needs a valid auth context. Doing it from the .signedOut auth-state event
        //     does not work — the SDK removes the session BEFORE emitting that event, so
        //     the update goes out on the anon key, matches zero rows under RLS, and
        //     returns 200 with an empty array, i.e. it silently does nothing while looking
        //     like it worked. Without this the next person to sign in on a shared iPad
        //     receives the previous user's notifications, including time-off denial
        //     reasons and chat previews.
        if let currentUserId = self.currentUser?.id.uuidString {
            await PushNotificationManager.clearAPNsTokenOnSignOut(userId: currentUserId)
        }

        // 7. PII + identity keys in UserDefaults (leave device prefs
        //    like appTheme alone — they are not account data)
        let piiKeys = [
            "userID", "userEmail", "userFirstName", "userLastName",
            "userDisplayName", "userHomeAddress", "userAddress",
            "userCity", "userState", "userZipCode", "userCountry",
            "userCoordinates", "userPhone", "userBio", "userPosition",
            "userPhotoURL", "userRole", "userRoleId", "userOrganizationID",
            "CLAUDE_API_KEY", "photoshootNotes", "jobNotes", "jobNotesSchool"
        ]
        for key in piiKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        do {
            try await supabase.auth.signOut()

            self.currentUser = nil
            self.isAuthenticated = false

            print("[SupabaseAuthService] Sign out successful")
        } catch {
            print("[SupabaseAuthService] Sign out error: \(error.localizedDescription)")
            throw error
        }
    }

    /// Send password reset email
    func resetPassword(email: String, redirectTo: URL? = nil) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabase.auth.resetPasswordForEmail(
                email,
                redirectTo: redirectTo
            )
            print("[SupabaseAuthService] Password reset email sent to \(email)")
        } catch {
            print("[SupabaseAuthService] Password reset error: \(error.localizedDescription)")
            throw error
        }
    }

    /// Update password for current user
    func updatePassword(newPassword: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabase.auth.update(user: UserAttributes(password: newPassword))
            print("[SupabaseAuthService] Password updated successfully")
        } catch {
            print("[SupabaseAuthService] Password update error: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - OAuth Support

    /// Handle OAuth callback (deep link)
    /// Used by Supabase's OAuth system for provider callbacks
    func handleOAuthCallback(url: URL) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            // Extract session from OAuth callback URL
            try await supabase.auth.session(from: url)

            // Session will be automatically updated via auth state listener
            print("[SupabaseAuthService] OAuth callback handled successfully")
        } catch {
            print("[SupabaseAuthService] OAuth callback error: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - User Management

    /// Get current session
    func getCurrentSession() async throws -> Auth.Session {
        return try await supabase.auth.session
    }

    /// Refresh current session
    func refreshSession() async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await supabase.auth.refreshSession()
            self.currentUser = session.user
            print("[SupabaseAuthService] Session refreshed")
        } catch {
            print("[SupabaseAuthService] Session refresh error: \(error.localizedDescription)")
            throw error
        }
    }
}
