//
//  Config.swift
//  Iconik Employee
//
//  Created on 2025-12-27.
//  Configuration for app environments and API credentials
//

import Foundation

/// Application environment configuration
/// Manages API credentials and environment-specific settings
enum AppEnvironment {
    case production
    // Add development/staging cases here if needed in the future

    /// Current active environment
    static let current: AppEnvironment = .production

    /// Supabase project URL
    var supabaseURL: String {
        switch self {
        case .production:
            return "https://nofegnmrgnanpznavlqy.supabase.co"
        }
    }

    /// Supabase anonymous key (public, client-side key)
    /// Note: This is designed to be public. Security is enforced via Row Level Security (RLS) policies.
    var supabaseAnonKey: String {
        switch self {
        case .production:
            return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5vZmVnbm1yZ25hbnB6bmF2bHF5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU2Njk5NjIsImV4cCI6MjA4MTI0NTk2Mn0.cGf23USITKCUwUTwhyq0UKceOPCOslNYIlapAdxU1qc"
        }
    }
}
