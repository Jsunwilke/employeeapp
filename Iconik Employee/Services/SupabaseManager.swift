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
        let url: URL
        if let validURL = URL(string: urlString), validURL.scheme == "https" {
            url = validURL
        } else {
            print("❌ [SupabaseManager] FATAL: Invalid Supabase URL: \(urlString)")
            print("❌ Please check your Config.xcconfig file and ensure SUPABASE_URL is set correctly")
            // Use dummy URL for graceful degradation
            url = URL(string: "https://invalid.supabase.co")!
        }

        // Validate key is a JWT (basic check)
        let validatedKey: String
        if key.split(separator: ".").count == 3 {
            validatedKey = key
        } else {
            print("❌ [SupabaseManager] FATAL: Invalid Supabase anon key format (not a valid JWT)")
            print("❌ Please check your Config.xcconfig file and ensure SUPABASE_ANON_KEY is set correctly")
            // Use dummy key for graceful degradation
            validatedKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJpbnZhbGlkIiwicm9sZSI6ImFub24ifQ.invalid"
        }

        print("[SupabaseManager] Initializing with URL: \(urlString)")
        print("[SupabaseManager] Anon key: \(key.prefix(20))...")

        // Initialize Supabase client with session persistence enabled
        // Note: Session persistence is enabled by default in Supabase Swift SDK 2.x
        // emitLocalSessionAsInitialSession ensures locally stored session is always emitted
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: validatedKey,
            options: SupabaseClientOptions(
                auth: .init(
                    autoRefreshToken: true,
                    emitLocalSessionAsInitialSession: true
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
        return client.auth.currentUser?.id.uuidString.lowercased()
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
