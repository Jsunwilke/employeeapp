//
//  SupabaseManager.swift
//  Iconik Employee
//
//  Created on 2025-12-25
//  Supabase client singleton for backend communication
//

import Foundation
import Supabase

/// Singleton manager for Supabase client
/// Provides centralized access to Supabase services (database, auth, storage, realtime)
class SupabaseManager {
    // MARK: - Singleton

    static let shared = SupabaseManager()

    // MARK: - Properties

    let client: SupabaseClient

    // MARK: - Initialization

    private init() {
        // Get Supabase configuration from AppEnvironment
        let urlString = AppEnvironment.current.supabaseURL
        let key = AppEnvironment.current.supabaseAnonKey

        // Validate URL format
        guard let url = URL(string: urlString), url.scheme == "https" else {
            fatalError("[SupabaseManager] Invalid Supabase URL: \(urlString)")
        }

        // Validate key is a JWT (basic check)
        guard key.split(separator: ".").count == 3 else {
            fatalError("[SupabaseManager] Invalid Supabase anon key format (not a valid JWT)")
        }

        print("[SupabaseManager] Initializing with URL: \(urlString)")
        print("[SupabaseManager] Anon key: \(key.prefix(20))...")

        // Initialize Supabase client with session persistence enabled
        // Note: Session persistence is enabled by default in Supabase Swift SDK 2.x
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(
                    autoRefreshToken: true
                )
            )
        )

        print("[SupabaseManager] ✅ Successfully initialized with session persistence")
    }

    // MARK: - Convenience Accessors
    // Note: Direct access to client properties works in Supabase SDK 2.x
    // The client.auth, client.storage etc. return the correct types automatically

    // MARK: - Helper Methods

    /// Get the current user ID
    var currentUserId: String? {
        return client.auth.currentUser?.id.uuidString
    }

    /// Get the current session
    var currentSession: Auth.Session? {
        return client.auth.currentSession
    }

    /// Check if user is authenticated
    var isAuthenticated: Bool {
        return currentSession != nil
    }
}
