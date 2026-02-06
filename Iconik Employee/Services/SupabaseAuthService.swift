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

                    case .signedOut:
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

    /// Sign out current user
    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }

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
