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

    /// Supabase project URL - read from Info.plist (injected from Config.xcconfig)
    var supabaseURL: String {
        if let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String, !url.isEmpty, !url.hasPrefix("$") {
            return url
        }
        // Fallback for backwards compatibility during transition
        return "https://nofegnmrgnanpznavlqy.supabase.co"
    }

    /// Supabase anonymous key (public, client-side key)
    /// Note: This is designed to be public. Security is enforced via Row Level Security (RLS) policies.
    /// Read from Info.plist (injected from Config.xcconfig)
    var supabaseAnonKey: String {
        if let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !key.isEmpty, !key.hasPrefix("$") {
            return key
        }
        // Fallback for backwards compatibility during transition
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5vZmVnbm1yZ25hbnB6bmF2bHF5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU2Njk5NjIsImV4cCI6MjA4MTI0NTk2Mn0.cGf23USITKCUwUTwhyq0UKceOPCOslNYIlapAdxU1qc"
    }
}
