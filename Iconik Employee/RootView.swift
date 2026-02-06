import SwiftUI
import Supabase

struct RootView: View {
    @State private var isCheckingAuth = true
    @State private var isSignedIn = false
    @StateObject private var userManager = UserManager.shared
    @StateObject private var profileService = UserProfileService.shared
    @ObservedObject private var authService = SupabaseAuthService.shared
    @EnvironmentObject var passwordResetVM: PasswordResetViewModel
    
    var body: some View {
        Group {
            if isCheckingAuth {
                ProgressView()
            } else if isSignedIn {
                MainEmployeeView(isSignedIn: $isSignedIn)
            } else {
                SignInView(isSignedIn: $isSignedIn)
            }
        }
        .onAppear {
            // Check for existing Supabase session
            // Note: SupabaseAuthService.shared already checks session in its init()
            Task {
                // Wait briefly for SDK to restore session from keychain
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

                let hasSupabaseSession = authService.isAuthenticated

                if hasSupabaseSession {
                    // IMPORTANT: Initialize organization ID BEFORE showing main view
                    // This fixes the race condition where views load before org ID is available
                    await userManager.initializeOrganizationIDAsync()

                    // Refresh user profile before showing main view
                    await profileService.refreshCurrentUserProfile()

                    // Verify we have the org ID before proceeding
                    let orgID = userManager.getCachedOrganizationID()
                    if orgID.isEmpty {
                        // One more attempt via profile service
                        await profileService.refreshCurrentUserProfile()
                    }

                    // NOW show the main view
                    await MainActor.run {
                        isSignedIn = true
                        isCheckingAuth = false
                    }
                } else {
                    // No session - show sign in view
                    await MainActor.run {
                        isCheckingAuth = false
                    }
                }
            }
        }
        .onChange(of: authService.isAuthenticated) { isAuthenticated in
            if isAuthenticated {
                // Initialize org ID and refresh profile BEFORE showing main view
                Task {
                    await userManager.initializeOrganizationIDAsync()
                    await profileService.refreshCurrentUserProfile()

                    await MainActor.run {
                        isSignedIn = true
                        isCheckingAuth = false
                    }
                }
            } else {
                // Sign out - update immediately
                isSignedIn = false
                isCheckingAuth = false
            }
        }
        .sheet(isPresented: $passwordResetVM.showingResetPassword) {
            ResetPasswordView(viewModel: passwordResetVM)
        }
    }
}

