//
//  ResetPasswordView.swift
//  Iconik Employee
//
//  View for setting a new password after clicking reset link
//

import SwiftUI

struct ResetPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PasswordResetViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if viewModel.passwordUpdated {
                    // Success state
                    successView
                } else {
                    // Password entry form
                    passwordFormView
                }

                Spacer()
            }
            .padding()
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
        .interactiveDismissDisabled(viewModel.isLoading)
    }

    // MARK: - Password Form View

    private var passwordFormView: some View {
        VStack(spacing: 20) {
            Text("Enter your new password below.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            SecureField("New Password", text: $viewModel.newPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(viewModel.isLoading)

            SecureField("Confirm Password", text: $viewModel.confirmPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(viewModel.isLoading)

            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            // Password requirements hint
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: viewModel.newPassword.count >= 6 ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(viewModel.newPassword.count >= 6 ? .green : .gray)
                        .font(.caption)
                    Text("At least 6 characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Image(systemName: !viewModel.confirmPassword.isEmpty && viewModel.newPassword == viewModel.confirmPassword ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(!viewModel.confirmPassword.isEmpty && viewModel.newPassword == viewModel.confirmPassword ? .green : .gray)
                        .font(.caption)
                    Text("Passwords match")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            Button(action: {
                Task {
                    await viewModel.updatePassword()
                }
            }) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Update Password")
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(viewModel.canSubmitPassword ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(!viewModel.canSubmitPassword)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
                .padding(.top, 30)

            Text("Password Updated")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your password has been successfully updated. You can now sign in with your new password.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                viewModel.reset()
                dismiss()
            }) {
                Text("Sign In")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.top, 20)
        }
    }
}

struct ResetPasswordView_Previews: PreviewProvider {
    static var previews: some View {
        ResetPasswordView(viewModel: PasswordResetViewModel())
    }
}
