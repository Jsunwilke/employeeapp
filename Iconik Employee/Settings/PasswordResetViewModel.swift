//
//  PasswordResetViewModel.swift
//  Iconik Employee
//
//  ViewModel for password reset flow
//

import Foundation
import SwiftUI

@MainActor
class PasswordResetViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var email = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var showingForgotPassword = false
    @Published var showingResetPassword = false
    @Published var emailSent = false
    @Published var passwordUpdated = false

    // MARK: - Private Properties

    private let authService = SupabaseAuthService.shared
    private let redirectURL = URL(string: "iconik://reset-password")!

    // MARK: - Validation

    var isEmailValid: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: email)
    }

    var passwordValidationError: String? {
        if newPassword.count < 6 {
            return "Password must be at least 6 characters long"
        }
        if newPassword != confirmPassword {
            return "Passwords do not match"
        }
        return nil
    }

    var canSubmitEmail: Bool {
        !email.isEmpty && isEmailValid && !isLoading
    }

    var canSubmitPassword: Bool {
        !newPassword.isEmpty && !confirmPassword.isEmpty && passwordValidationError == nil && !isLoading
    }

    // MARK: - Actions

    /// Request password reset email
    func requestPasswordReset() async {
        guard canSubmitEmail else { return }

        isLoading = true
        error = nil

        do {
            try await authService.resetPassword(email: email, redirectTo: redirectURL)
            emailSent = true
        } catch {
            // Use generic message for security (don't reveal if email exists)
            self.error = "If an account exists with this email, you will receive a password reset link."
            // Still show success state to prevent email enumeration
            emailSent = true
        }

        isLoading = false
    }

    /// Handle deep link from password reset email
    func handleDeepLink(url: URL) async {
        guard url.scheme == "iconik", url.host == "reset-password" else { return }

        isLoading = true
        error = nil

        do {
            // This sets up the session from the recovery token in the URL
            try await authService.handleOAuthCallback(url: url)
            showingResetPassword = true
        } catch {
            self.error = "Invalid or expired password reset link. Please request a new one."
        }

        isLoading = false
    }

    /// Update password with new value
    func updatePassword() async {
        guard canSubmitPassword else {
            error = passwordValidationError
            return
        }

        isLoading = true
        error = nil

        do {
            try await authService.updatePassword(newPassword: newPassword)
            try await authService.signOut()
            passwordUpdated = true
            showingResetPassword = false
        } catch {
            self.error = "Failed to update password. Please try again."
        }

        isLoading = false
    }

    /// Reset all state
    func reset() {
        email = ""
        newPassword = ""
        confirmPassword = ""
        error = nil
        emailSent = false
        passwordUpdated = false
        showingForgotPassword = false
        showingResetPassword = false
    }

    /// Reset just the forgot password flow
    func resetForgotPasswordFlow() {
        email = ""
        error = nil
        emailSent = false
    }

    /// Reset just the reset password flow
    func resetResetPasswordFlow() {
        newPassword = ""
        confirmPassword = ""
        error = nil
        passwordUpdated = false
    }
}
