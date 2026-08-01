//
//  ForgotPasswordView.swift
//  Iconik Employee
//
//  View for requesting a password reset email. Converted to Ambient in AMB.12.
//
//  CONTAINMENT: a sheet presented by `SignInView`, which hands it the
//  `NavigationView` — so this file adds none (NAV.1: one bar per screen).
//
//  NAMED, NOT FIXED, and deliberately: `requestPasswordReset()` sets
//  `emailSent = true` on BOTH branches, so the confirmation below replaces the
//  form whether the request succeeded or not, and the error it sets on the
//  failing branch is rendered by a view that is no longer on screen. That is
//  the enumeration-safety posture — it is what stops this screen telling a
//  stranger which email addresses have accounts — and changing it is a security
//  decision, not a design one. The error branch is kept exactly as it is.
//

import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PasswordResetViewModel

    @FocusState private var focusedField: AuthFormField?

    var body: some View {
        AuthScreen {
            if viewModel.emailSent {
                // Success state
                successView
            } else {
                // Email entry form
                emailFormView
            }
        }
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.large)
        .onDisappear {
            viewModel.resetForgotPasswordFlow()
        }
    }

    // MARK: - Email Form View

    @ViewBuilder
    private var emailFormView: some View {
        AmbientFormSection(title: "Reset password", status: "", statusTint: nil) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter your email address and we'll send you a link to reset your password.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                AuthTextField(placeholder: "Email",
                              text: $viewModel.email,
                              keyboard: .emailAddress,
                              contentType: .username,
                              submitLabel: .go,
                              isEnabled: !viewModel.isLoading,
                              focus: $focusedField,
                              field: .email) {
                    submit()
                }
            }
        }

        if let error = viewModel.error {
            AuthErrorText(error)
        }

        AmbientActionButton(title: "Send Reset Link",
                            tint: AuthStyle.tint,
                            isLoading: viewModel.isLoading,
                            isEnabled: viewModel.canSubmitEmail,
                            action: submit)
    }

    // MARK: - Success View

    @ViewBuilder
    private var successView: some View {
        Image(systemName: "envelope.circle.fill")
            .font(.system(size: 60))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

        AmbientNoteCard(
            title: "Check Your Email",
            text: "If an account exists with \(viewModel.email), you will receive a password reset link shortly. Click the link in the email to reset your password.",
            accent: .green,
            density: .compact)

        AmbientActionButton(title: "Back to Sign In",
                            tint: AuthStyle.tint) {
            dismiss()
        }
    }

    // MARK: - Actions

    private func submit() {
        guard viewModel.canSubmitEmail else { return }
        focusedField = nil
        Task {
            await viewModel.requestPasswordReset()
        }
    }
}

struct ForgotPasswordView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ForgotPasswordView(viewModel: PasswordResetViewModel())
        }
    }
}
