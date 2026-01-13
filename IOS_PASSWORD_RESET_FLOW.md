# iOS Password Reset Flow

This document explains how to implement the password reset functionality in the iOS app using Supabase Auth.

---

## Overview

The password reset flow has two main parts:
1. **Request Reset** - User enters email, Supabase sends a magic link
2. **Set New Password** - User clicks link, enters new password

---

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PASSWORD RESET FLOW                              │
└─────────────────────────────────────────────────────────────────────────┘

┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Login      │    │   Forgot     │    │   Email      │    │   Reset      │
│   Screen     │───▶│   Password   │───▶│   Sent       │    │   Password   │
│              │    │   Screen     │    │   Success    │    │   Screen     │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
       │                   │                                        │
       │            User enters                              User enters
       │            email address                           new password
       │                   │                                        │
       │                   ▼                                        ▼
       │            ┌──────────────┐                         ┌──────────────┐
       │            │   Supabase   │                         │   Supabase   │
       │            │   sends      │                         │   updates    │
       │            │   reset      │                         │   password   │
       │            │   email      │                         │              │
       │            └──────────────┘                         └──────────────┘
       │                   │                                        │
       │                   ▼                                        ▼
       │            ┌──────────────┐                         ┌──────────────┐
       │            │   User       │                         │   Redirect   │
       │            │   clicks     │────────────────────────▶│   to Login   │
       │            │   email      │   Deep link opens app   │              │
       │            │   link       │   with recovery token   │              │
       │            └──────────────┘                         └──────────────┘
       │                                                            │
       ◀────────────────────────────────────────────────────────────┘
```

---

## Screens Required

### 1. Forgot Password Screen
**Entry Point:** "Forgot password?" link on Login screen

**UI Elements:**
- Back button (to return to Login)
- Title: "Reset Password"
- Description: "Enter your email address and we'll send you a link to reset your password."
- Email input field
- "Send Reset Link" button
- Loading state while sending

**States:**
- Default (form visible)
- Loading (sending email)
- Success (email sent confirmation)
- Error (invalid email, user not found, etc.)

### 2. Reset Password Screen
**Entry Point:** Deep link from email (`iconik://reset-password` or custom URL scheme)

**UI Elements:**
- Title: "Set New Password"
- Description: "Enter your new password below"
- New Password input field
- Confirm Password input field
- "Update Password" button
- "Back to Login" link
- Loading state while updating

**States:**
- Checking (verifying recovery token)
- Valid session (form visible)
- Invalid/Expired link (error with "Back to Login" button)
- Success (password updated confirmation)
- Error (password validation failed, etc.)

---

## Supabase API Calls

### 1. Request Password Reset

```swift
// Swift - Request password reset email
func requestPasswordReset(email: String) async throws {
    try await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: URL(string: "iconik://reset-password")! // Your app's deep link URL
    )
}
```

**Notes:**
- `redirectTo` should be your iOS app's deep link URL scheme
- Supabase will append auth tokens to this URL as query parameters
- The email contains a link that opens your app

### 2. Handle Deep Link & Set Session

When the user clicks the email link, your app receives a deep link like:
```
iconik://reset-password#access_token=xxx&refresh_token=xxx&type=recovery
```

```swift
// Swift - Handle the deep link
func handlePasswordResetDeepLink(url: URL) async throws {
    // Extract the fragment (everything after #)
    guard let fragment = url.fragment else {
        throw AuthError.invalidLink
    }

    // Parse the fragment as URL parameters
    let params = parseURLFragment(fragment)

    // Check if this is a recovery link
    guard params["type"] == "recovery" else {
        throw AuthError.invalidLink
    }

    // Supabase SDK should automatically detect and set the session
    // from the URL parameters. You may need to call:
    try await supabase.auth.session(from: url)

    // Navigate to Reset Password screen
}
```

### 3. Update Password

```swift
// Swift - Update the user's password
func updatePassword(newPassword: String) async throws {
    try await supabase.auth.update(user: UserAttributes(password: newPassword))
}
```

### 4. Sign Out After Password Change

```swift
// Swift - Sign out after successful password update
func signOutAfterPasswordChange() async throws {
    try await supabase.auth.signOut()
    // Navigate to Login screen
}
```

---

## Deep Link Setup (iOS)

### 1. URL Scheme Configuration

Add to your `Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>iconik</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.iconikschools.iconik</string>
    </dict>
</array>
```

### 2. Handle Deep Link in AppDelegate/SceneDelegate

```swift
// SceneDelegate.swift
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url else { return }

    if url.scheme == "iconik" && url.host == "reset-password" {
        // Handle password reset deep link
        Task {
            do {
                try await handlePasswordResetDeepLink(url: url)
            } catch {
                // Show error
            }
        }
    }
}
```

### 3. Alternative: Universal Links (Recommended)

For a better user experience, use Universal Links with your domain:
```
https://app.iconikschools.com/reset-password
```

This requires:
1. Apple App Site Association file on your server
2. Associated Domains entitlement in your app

---

## Validation Rules

### Password Requirements
- Minimum 6 characters
- Passwords must match (new password == confirm password)

```swift
func validatePassword(_ password: String, confirm: String) -> String? {
    if password.count < 6 {
        return "Password must be at least 6 characters long"
    }
    if password != confirm {
        return "Passwords do not match"
    }
    return nil // Valid
}
```

---

## Error Handling

### Common Errors

| Error | User Message |
|-------|--------------|
| Invalid email format | "Please enter a valid email address" |
| User not found | "No account found with this email" (or generic for security) |
| Invalid/expired link | "Invalid or expired password reset link. Please request a new one." |
| Password too short | "Password must be at least 6 characters long" |
| Passwords don't match | "Passwords do not match" |
| Network error | "Unable to connect. Please check your internet connection." |
| Rate limited | "Too many attempts. Please try again later." |

### Security Note
For security, don't reveal whether an email exists in your system. Use a generic success message:
> "If an account exists with this email, you will receive a password reset link."

---

## Complete Flow Example

```swift
// PasswordResetViewModel.swift

class PasswordResetViewModel: ObservableObject {
    @Published var email = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var state: ResetState = .enterEmail

    enum ResetState {
        case enterEmail
        case emailSent
        case enterNewPassword
        case success
        case invalidLink
    }

    // Step 1: Request reset email
    func requestReset() async {
        isLoading = true
        error = nil

        do {
            try await supabase.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: "iconik://reset-password")!
            )
            await MainActor.run {
                state = .emailSent
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to send reset email. Please try again."
                isLoading = false
            }
        }
    }

    // Step 2: Handle deep link (called from AppDelegate)
    func handleDeepLink(url: URL) async {
        isLoading = true

        do {
            try await supabase.auth.session(from: url)
            await MainActor.run {
                state = .enterNewPassword
                isLoading = false
            }
        } catch {
            await MainActor.run {
                state = .invalidLink
                self.error = "Invalid or expired reset link."
                isLoading = false
            }
        }
    }

    // Step 3: Update password
    func updatePassword() async {
        // Validate
        if let validationError = validatePassword(newPassword, confirm: confirmPassword) {
            error = validationError
            return
        }

        isLoading = true
        error = nil

        do {
            try await supabase.auth.update(user: UserAttributes(password: newPassword))
            try await supabase.auth.signOut()

            await MainActor.run {
                state = .success
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to update password. Please try again."
                isLoading = false
            }
        }
    }

    private func validatePassword(_ password: String, confirm: String) -> String? {
        if password.count < 6 {
            return "Password must be at least 6 characters long"
        }
        if password != confirm {
            return "Passwords do not match"
        }
        return nil
    }
}
```

---

## Supabase Dashboard Configuration

Make sure your Supabase project is configured correctly:

1. **Authentication > URL Configuration**
   - Site URL: `https://app.iconikschools.com` (your web app)
   - Redirect URLs: Add `iconik://reset-password` (your iOS deep link)

2. **Authentication > Email Templates**
   - Customize the "Reset Password" email template if desired
   - The `{{ .ConfirmationURL }}` variable contains the reset link

---

## Testing Checklist

- [ ] "Forgot password?" link visible on login screen
- [ ] Forgot password screen shows email input
- [ ] Valid email triggers reset email
- [ ] Success message shown after sending email
- [ ] Reset email received with correct link
- [ ] Clicking link opens iOS app (not web)
- [ ] Reset password screen shows password inputs
- [ ] Password validation works (min 6 chars, must match)
- [ ] Successful password update shows confirmation
- [ ] User redirected to login after success
- [ ] Invalid/expired links show appropriate error
- [ ] User can successfully log in with new password
