//  AuthKit.swift
//  Iconik Employee — the four auth screens' shared vocabulary, added in AMB.12
//
//  WHY THIS FILE EXISTS. Sign In, Create Account, Forgot Password and Reset
//  Password are four screens that ask for the same three things — an email, a
//  password, a password again — and before this phase they answered those
//  questions four different ways: two of them enforced a 6-character minimum and
//  two enforced nothing, one routed errors through the app's user-facing mapper
//  and three printed whatever the server said, and the password-rule checklist
//  existed on exactly one of them (G36). A shared kit is the only way those four
//  screens stay in agreement about what a password is.
//
//  It follows `ClassGroupsKit` (AMB.10): a style constant, the field, the rules,
//  and the page scaffold — nothing that knows about a specific screen.

import SwiftUI

// MARK: - Style

enum AuthStyle {
    /// The tint for auth CONTROLS.
    ///
    /// The Settings tree — which owns these four files — has no registered
    /// `FeatureTheme` colour (there is no `"settings"` case in the map, so it
    /// falls to the map's `default: .gray`), and grey is not a colour a primary
    /// button can be. The company blue is the deliberate answer: it is what the
    /// app already uses where a surface needs to feel like THIS APP rather than
    /// like one of its features, which is exactly what a signed-out screen is.
    ///
    /// The page WASH is a separate decision and is not made here: D14 (operator,
    /// 2026-07-30) put every production screen on one wash, so these screens call
    /// `AmbientBackdrop()` with no arguments like all sixty of their siblings.
    static var tint: Color { AmbientStyle.brand }
}

// MARK: - Fields

/// Every field any of the four screens can focus. One enum rather than one per
/// screen, so `AuthTextField` can be shared.
enum AuthFormField: Hashable {
    case organization
    case firstName
    case lastName
    case email
    case password
    case confirmPassword
}

/// The auth text field: plain or secure, one look.
///
/// Placeholder-only, which is what ships today and what the approved design
/// draws — the placeholder IS the label on these screens, and every one of those
/// placeholder strings is a shipped string that must not change.
struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var capitalization: TextInputAutocapitalization = .never
    var submitLabel: SubmitLabel = .next
    var isEnabled: Bool = true
    let focus: FocusState<AuthFormField?>.Binding
    let field: AuthFormField
    var onSubmit: () -> Void = {}

    var body: some View {
        // The secure/plain branch is fixed at the call site and never changes at
        // runtime, so the identity switch it introduces can never fire mid-edit
        // and drop what has been typed.
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(.subheadline)
        .keyboardType(keyboard)
        .textContentType(contentType)
        .textInputAutocapitalization(capitalization)
        .autocorrectionDisabled(true)
        .submitLabel(submitLabel)
        .focused(focus, equals: field)
        .onSubmit(onSubmit)
        .disabled(!isEnabled)
    }
}

// MARK: - Password rules

/// ONE definition of what this app considers a password.
///
/// Before AMB.12 the reset screen enforced six characters and drew a checklist
/// while Create Account enforced nothing and drew none, so the same account could
/// be given a two-character password at signup and then refused that password at
/// reset (G36). The rule, the checklist and the message now all come from here.
enum AuthPasswordRules {
    static let minimumLength = 6

    static func isLongEnough(_ password: String) -> Bool {
        password.count >= minimumLength
    }

    /// A confirmation only counts once something has been typed into it —
    /// two empty fields are not a match, they are an unanswered question.
    static func matches(_ password: String, _ confirmation: String) -> Bool {
        !confirmation.isEmpty && password == confirmation
    }

    /// The app's existing message for a short password, hoisted here so both
    /// screens say the same sentence rather than inventing a second one.
    static let tooShortMessage = "Password must be at least 6 characters long"
}

/// The live rule checklist — shipped on Reset Password since it was written, and
/// now on Create Account too, which is the whole point of sharing it.
struct AuthPasswordChecklist: View {
    let password: String
    let confirmation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            rule(met: AuthPasswordRules.isLongEnough(password),
                 text: "At least \(AuthPasswordRules.minimumLength) characters")
            rule(met: AuthPasswordRules.matches(password, confirmation),
                 text: "Passwords match")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rule(met: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? Color.green : Color.secondary)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(met ? "\(text): met" : "\(text): not met")
    }
}

// MARK: - Errors

/// The one error treatment across the four screens.
///
/// Sign In was the ONLY auth screen routing its errors through
/// `UserFacing` (`Utilities/UserFacingError.swift`); the others printed raw
/// `localizedDescription`, so a duplicate key or an RLS violation put Postgrest
/// text on the screen. Callers now all pass `error.userFacingMessage`, and this
/// draws it the same way everywhere.
struct AuthErrorText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Page scaffold

/// The page every auth screen is drawn on: the app wash, a scroll, the standard
/// 16/16 inset and the 14pt rhythm between blocks.
///
/// Deliberately NOT a navigation container. The four screens disagree about
/// containment for real reasons — Sign In owns its `NavigationView`, Create
/// Account is pushed inside it, Forgot Password is a sheet handed a
/// `NavigationView` by Sign In, and Reset Password is a sheet presented by
/// `RootView` so it can appear over the launch spinner — and a scaffold that
/// guessed would give one of them two navigation bars (NAV.1: one bar per
/// screen).
struct AuthScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
    }
}
