//
//  ResetPasswordView.swift
//  Iconik Employee
//
//  View for setting a new password after clicking reset link. Converted to
//  Ambient in AMB.12.
//
//  CONTAINMENT: presented as a sheet by `RootView` itself — deliberately, so a
//  reset link can open over the launch spinner, over Sign In, or over the signed-in
//  app — and it therefore owns its own `NavigationView` (D3: `NavigationView` +
//  Stack style, iOS 16.6 floor).
//
//  THE STATE THIS SCREEN GAINED, and the reason it is in scope at all: a bad or
//  expired link used to produce NO UI WHATSOEVER. The verification failed, the
//  view model set an error, and nothing ever presented a view to render it — the
//  user tapped a link from their email and watched the app do absolutely nothing
//  (G3). The sheet is now presented on that path too, showing what happened and
//  what to do about it.
//

import SwiftUI

struct ResetPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PasswordResetViewModel

    @FocusState private var focusedField: AuthFormField?

    var body: some View {
        NavigationView {
            AuthScreen {
                if viewModel.passwordUpdated {
                    // Success state
                    successView
                } else if viewModel.linkExpired {
                    // G3 — the link could not be verified. Before AMB.12 this
                    // state existed only in the documentation.
                    expiredView
                } else {
                    // Password entry form
                    passwordFormView
                }
            }
            .navigationTitle("Set New Password")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.reset()
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .interactiveDismissDisabled(viewModel.isLoading)
    }

    // MARK: - Password Form View

    @ViewBuilder
    private var passwordFormView: some View {
        AmbientFormSection(title: "Set a new password", status: "", statusTint: nil) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter your new password below.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                AuthTextField(placeholder: "New Password",
                              text: $viewModel.newPassword,
                              isSecure: true,
                              contentType: .newPassword,
                              isEnabled: !viewModel.isLoading,
                              focus: $focusedField,
                              field: .password) {
                    focusedField = .confirmPassword
                }

                AuthTextField(placeholder: "Confirm Password",
                              text: $viewModel.confirmPassword,
                              isSecure: true,
                              contentType: .newPassword,
                              submitLabel: .done,
                              isEnabled: !viewModel.isLoading,
                              focus: $focusedField,
                              field: .confirmPassword) {
                    submit()
                }

                Divider()

                // The rule checklist Create Account now draws too, from the one
                // definition of what this app considers a password (G36).
                AuthPasswordChecklist(password: viewModel.newPassword,
                                      confirmation: viewModel.confirmPassword)
            }
        }

        if let error = viewModel.error {
            AuthErrorText(error)
        }

        AmbientActionButton(title: "Update Password",
                            tint: AuthStyle.tint,
                            isLoading: viewModel.isLoading,
                            isEnabled: viewModel.canSubmitPassword,
                            action: submit)
    }

    // MARK: - Invalid / expired link

    @ViewBuilder
    private var expiredView: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 60))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

        AmbientNoteCard(
            title: "This link has expired",
            text: "Password reset links can only be used once, and they expire. Request a new one from the sign-in screen.",
            accent: .orange,
            density: .compact)
    }

    // MARK: - Success View

    @ViewBuilder
    private var successView: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 60))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

        AmbientNoteCard(
            title: "Password Updated",
            text: "Your password has been successfully updated. You can now sign in with your new password.",
            accent: .green,
            density: .compact)

        AmbientActionButton(title: "Sign In",
                            tint: AuthStyle.tint) {
            viewModel.reset()
            dismiss()
        }
    }

    // MARK: - Actions

    private func submit() {
        guard viewModel.canSubmitPassword else { return }
        focusedField = nil
        Task {
            await viewModel.updatePassword()
        }
    }
}

struct ResetPasswordView_Previews: PreviewProvider {
    static var previews: some View {
        ResetPasswordView(viewModel: PasswordResetViewModel())
    }
}
