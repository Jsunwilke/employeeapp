# iOS Password Reset Flow

**This describes the flow the app SHIPS, as of AMB.12 (2026-08-01). It is not a
proposal and not a tutorial.**

It was previously written as an implementation guide, before the code existed,
and it was never corrected afterwards — so it went on describing an error state
that could not be reached, a "Back to Login" link that was never built, an
"Invalid/Expired link" screen that did not exist, and four error messages that
appear nowhere in the codebase. One of those inventions hid a real defect for
months: the doc said a bad link showed an error, so nobody noticed that a bad
link showed *nothing at all*. **If you change the flow, change this file in the
same commit.**

---

## Overview

Two parts, and they are reached from completely different places:

1. **Request a reset** — the user taps "Forgot password?" on the Sign In screen,
   enters an email, Supabase sends a link.
2. **Set a new password** — the user opens that link, which deep-links back into
   the app, and the app presents the reset screen over whatever is on screen.

---

## Files

| File | Role |
|---|---|
| `Iconik Employee/Settings/SignInView.swift` | Owns the "Forgot password?" entry point and presents Forgot Password as a **sheet** |
| `Iconik Employee/Settings/ForgotPasswordView.swift` | The email form and its confirmation. A sheet; Sign In hands it the `NavigationView` |
| `Iconik Employee/Settings/ResetPasswordView.swift` | The new-password form, the expired-link state and the success state. Owns its own `NavigationView` |
| `Iconik Employee/Settings/PasswordResetViewModel.swift` | All three network calls and every message. `@MainActor`, injected app-wide as an `@EnvironmentObject` |
| `Iconik Employee/Settings/AuthKit.swift` | The shared field, the shared password rules and checklist, the page scaffold |
| `Iconik Employee/RootView.swift` | Presents `ResetPasswordView` as a sheet — **deliberately at the root**, so a reset link works over the launch spinner, over Sign In, and over the signed-in app |
| `Iconik Employee/Iconik_EmployeeApp.swift` | `.onOpenURL` — filters `iconik://reset-password` and hands it to the view model |

---

## Screen 1 — Forgot Password

**Entry point:** "Forgot password?" inside the Sign In form. Presented as a sheet.

**Navigation title:** "Reset Password" (large).

**Form state**
- Section "Reset password" containing:
  - "Enter your email address and we'll send you a link to reset your password."
  - an "Email" field
- Button **"Send Reset Link"** — disabled until the address passes the email
  regex, and while the request is in flight (it shows a spinner then).

**Confirmation state** — replaces the form:
- a green `envelope.circle.fill`
- a note card titled **"Check Your Email"** reading
  "If an account exists with \(email), you will receive a password reset link
  shortly. Click the link in the email to reset your password."
- **"Back to Sign In"**, which dismisses the sheet.

**There is no reachable error state on this screen, and that is deliberate.**
`requestPasswordReset()` sets `emailSent = true` on BOTH the success and the
failure branch, so the confirmation replaces the form either way. That is what
stops the screen from telling a stranger which email addresses have accounts.
The generic message it assigns on the failing branch — "If an account exists with
this email, you will receive a password reset link." — is therefore never drawn.
Changing this is a security decision, not a design one.

**Invalid email is handled by disabling the button, not by a message.** There is
no "Please enter a valid email address" string in the app.

---

## Screen 2 — Reset Password

**Entry point:** the deep link from the email. Presented as a sheet by
`RootView`, so it can appear over anything.

**Navigation title:** "Set New Password" (large). **Toolbar: "Cancel"** — there
is no "Back to Login" link on this screen and never has been. "Sign In" appears
only in the success state.

**Form state**
- Section "Set a new password" containing:
  - "Enter your new password below."
  - "New Password", "Confirm Password"
  - the live rule checklist: **"At least 6 characters"**, **"Passwords match"**
- Button **"Update Password"** — disabled until both rules pass.
- On failure, the view model's message is shown inline in red.

**Invalid / expired link state** (built in AMB.12 — before that, this failure
produced no UI at all):
- an orange `exclamationmark.triangle.fill`
- a note card titled **"This link has expired"** reading "Password reset links
  can only be used once, and they expire. Request a new one from the sign-in
  screen."
- "Cancel" is the way out.

**Success state**
- a green `checkmark.circle.fill`
- a note card titled **"Password Updated"** reading "Your password has been
  successfully updated. You can now sign in with your new password."
- **"Sign In"**, which resets the view model and dismisses.

**There is no "Checking" state.** Verification of the recovery token happens
BEFORE this screen is presented, in `handleDeepLink(url:)`. The screen only ever
opens on a decided outcome: a valid session (form) or a failure (expired card).

`.interactiveDismissDisabled(viewModel.isLoading)` — the sheet cannot be swiped
away mid-update.

**The user is signed out after a successful password change**
(`updatePassword()` calls `signOut()`), which is why the success copy sends them
back to sign in.

---

## What the code actually calls

| Step | View model | Auth service | Supabase |
|---|---|---|---|
| Request | `requestPasswordReset()` | `resetPassword(email:redirectTo:)` | `auth.resetPasswordForEmail` |
| Deep link | `handleDeepLink(url:)` | `handleOAuthCallback(url:)` | `auth.session(from:)` |
| Update | `updatePassword()` | `updatePassword(newPassword:)` then `signOut()` | `auth.update(user: UserAttributes(password:))`, then `auth.signOut()` |

`redirectURL` is `URL(string: "iconik://reset-password")` — **safely unwrapped**;
if it ever failed to parse, the email is requested without a redirect rather than
the app trapping.

### Deep link handling, as written

```swift
// Iconik_EmployeeApp.swift
.onOpenURL { url in
    if url.scheme == "iconik" && url.host == "reset-password" {
        Task { await passwordResetVM.handleDeepLink(url: url) }
    }
}
```

`handleDeepLink` re-checks the same scheme/host, then calls
`handleOAuthCallback(url:)`. **The fragment is not parsed and `type=recovery` is
not checked** — the Supabase SDK reads the URL itself. On success it sets
`showingResetPassword = true`; on failure it sets `linkExpired = true` **and**
`showingResetPassword = true`, so the sheet is presented either way. Setting only
the error, which is what the code did before AMB.12, meant the sheet never
appeared and the user watched a link do nothing.

### URL scheme

Registered in `Iconik-Employee-Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array><string>iconik</string></array>
        <key>CFBundleURLName</key>
        <string>com.iconikschools.iconik</string>
    </dict>
</array>
```

Universal Links are **not** set up. The custom scheme is what works today.

---

## Validation rules

One definition, in `AuthKit.swift`, used by Reset Password **and** Create Account
— before AMB.12 the two screens disagreed, and an account could be created with a
password its owner could never set again:

```swift
enum AuthPasswordRules {
    static let minimumLength = 6
    static func isLongEnough(_ password: String) -> Bool
    static func matches(_ password: String, _ confirmation: String) -> Bool
    static let tooShortMessage = "Password must be at least 6 characters long"
}
```

---

## Every message this flow can produce

| Where | Message | Reachable? |
|---|---|---|
| Reset Password, short password | "Password must be at least 6 characters long" | Only via the guard — the button is disabled first |
| Reset Password, mismatch | "Passwords do not match" | Only via the guard — the button is disabled first |
| Reset Password, update failed | "Failed to update password. Please try again." | Yes |
| Reset Password, bad link | the "This link has expired" card | Yes |
| Forgot Password, request failed | "If an account exists with this email, you will receive a password reset link." | **No** — enumeration-safe by design (see above) |

There is no "No account found with this email", no "Too many attempts. Please try
again later.", no "Unable to connect. Please check your internet connection." and
no "Please enter a valid email address" anywhere in this flow. Rate-limit and
network failures collapse into the enumeration-safe confirmation.

---

## Supabase dashboard configuration

1. **Authentication > URL Configuration** — Redirect URLs must include
   `iconik://reset-password`.
2. **Authentication > Email Templates** — the "Reset Password" template's
   `{{ .ConfirmationURL }}` is the link that opens the app.

---

## Testing checklist

- [ ] "Forgot password?" is visible inside the Sign In form
- [ ] The email field rejects submission until the address is well-formed (the
      button stays grey — there is no message)
- [ ] Sending shows the "Check Your Email" card with the address in it
- [ ] "Back to Sign In" dismisses the sheet
- [ ] The reset email arrives and its link opens the app rather than a browser
- [ ] A **valid** link opens "Set New Password" with the form
- [ ] Both rules tick live as they are met; "Update Password" stays disabled
      until they are
- [ ] A successful update shows "Password Updated" and signs the user out
- [ ] Signing in with the new password works
- [ ] A **used or expired** link opens "Set New Password" showing the
      "This link has expired" card — verified in the simulator at AMB.12 with
      `xcrun simctl openurl <udid> 'iconik://reset-password#access_token=expired&type=recovery'`,
      from both the foreground and a backgrounded app
