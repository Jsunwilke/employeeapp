//
//  ForgotPasswordView.swift
//  Iconik Employee
//
//  View for requesting a password reset email
//

import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PasswordResetViewModel

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.emailSent {
                // Success state
                successView
            } else {
                // Email entry form
                emailFormView
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.large)
        .onDisappear {
            viewModel.resetForgotPasswordFlow()
        }
    }

    // MARK: - Email Form View

    private var emailFormView: some View {
        VStack(spacing: 20) {
            Text("Enter your email address and we'll send you a link to reset your password.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            TextField("Email", text: $viewModel.email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disabled(viewModel.isLoading)

            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                Task {
                    await viewModel.requestPasswordReset()
                }
            }) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Send Reset Link")
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(viewModel.canSubmitEmail ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(!viewModel.canSubmitEmail)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
                .padding(.top, 30)

            Text("Check Your Email")
                .font(.title2)
                .fontWeight(.semibold)

            Text("If an account exists with \(viewModel.email), you will receive a password reset link shortly.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Click the link in the email to reset your password.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            Button(action: {
                dismiss()
            }) {
                Text("Back to Sign In")
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

struct ForgotPasswordView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ForgotPasswordView(viewModel: PasswordResetViewModel())
        }
    }
}
