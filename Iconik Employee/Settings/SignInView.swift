//  SignInView.swift
//  Iconik Employee — the first screen every user sees, converted to Ambient in AMB.12
//
//  SELF-NAV. This screen owns its `NavigationView` because `RootView` shows it
//  bare, outside the app shell — so unlike a feature it is handed no bar and no
//  tab bar (NAV.1, D3: `NavigationView` + Stack style, never `NavigationStack`,
//  on the iOS 16.6 floor).
//
//  THE CHANGE THAT MATTERS HERE IS NOT THE PAINT. Before AMB.12 this screen
//  signed the user IN even when the profile fetch failed: they landed in the app
//  with an empty organization id, a role defaulted to "employee" and no
//  permissions loaded, after which every org-scoped screen guarded out to blank —
//  which reads as an app with no data rather than as a failed sign-in (G1). The
//  profile fetch is a GATE now. See `completeSignIn(userId:)`.

import SwiftUI

struct SignInView: View {
    @Binding var isSignedIn: Bool
    @EnvironmentObject var passwordResetVM: PasswordResetViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showingForgotPassword = false

    /// G1 — sign-in succeeded at the auth layer but the profile could not be
    /// read, so the session was torn down again and the user is still out.
    @State private var profileLoadFailed = false

    /// Handed back by Create Account when it pops (G38): that screen used to
    /// print its confirmation and sit there with the form — password and all —
    /// still filled in.
    @State private var accountCreatedMessage = ""

    @FocusState private var focusedField: AuthFormField?

    // Supabase services
    @ObservedObject private var authService = SupabaseAuthService.shared

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationView {
            AuthScreen {
                credentialsSection

                AmbientActionButton(title: "Sign In",
                                    tint: AuthStyle.tint,
                                    isLoading: isLoading,
                                    isEnabled: canSubmit,
                                    action: signIn)

                NavigationLink(destination: CreateAccountView { message in
                    accountCreatedMessage = message
                }) {
                    Text("Don't have an account? Create one.")
                        .font(.subheadline)
                        .foregroundStyle(AuthStyle.tint)
                }
                .disabled(isLoading)

                if !errorMessage.isEmpty {
                    AuthErrorText(errorMessage)
                }

                if profileLoadFailed {
                    profileFailureBlock
                }

                if !accountCreatedMessage.isEmpty {
                    AmbientNoteCard(title: "Account created",
                                    text: accountCreatedMessage,
                                    accent: .green,
                                    density: .compact)
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingForgotPassword) {
            NavigationView {
                ForgotPasswordView(viewModel: passwordResetVM)
            }
        }
    }

    // MARK: - Sections

    private var credentialsSection: some View {
        AmbientFormSection(title: "Sign in", status: "", statusTint: nil) {
            VStack(alignment: .leading, spacing: 10) {
                AuthTextField(placeholder: "Email",
                              text: $email,
                              keyboard: .emailAddress,
                              contentType: .username,
                              isEnabled: !isLoading,
                              focus: $focusedField,
                              field: .email) {
                    focusedField = .password
                }

                Divider()

                AuthTextField(placeholder: "Password",
                              text: $password,
                              isSecure: true,
                              contentType: .password,
                              submitLabel: .go,
                              isEnabled: !isLoading,
                              focus: $focusedField,
                              field: .password) {
                    if canSubmit { signIn() }
                }

                Button("Forgot password?") {
                    showingForgotPassword = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AuthStyle.tint)
                .disabled(isLoading)
            }
        }
    }

    /// G1's surface: what failed, what it would have cost to ignore it, and a way
    /// to try again.
    private var profileFailureBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientNoteCard(
                title: "Couldn't load your profile",
                // The approved drawing said "You are signed in, but…". That was
                // true of the state it DREW — a proposal against code that let
                // the sign-in stand. The shipped fix does not let it stand: the
                // session is signed back out, so by the time this card is on
                // screen the sentence would be false. Approved copy that the
                // implementation makes untrue is worse than an edited string, so
                // the first clause states what actually happened. The rest is
                // the approved wording, unchanged.
                text: "Your password was accepted, but we couldn't read your organization or your permissions. Try again — signing in without them leaves every screen empty.",
                accent: .red,
                density: .compact)

            AmbientActionButton(title: "Retry",
                                systemImage: "arrow.clockwise",
                                size: .small,
                                tint: AuthStyle.tint,
                                fillWidth: false,
                                isLoading: isLoading,
                                action: signIn)
        }
    }

    // MARK: - Actions

    func signIn() {
        errorMessage = ""
        profileLoadFailed = false
        accountCreatedMessage = ""
        isLoading = true
        focusedField = nil

        Task {
            do {
                // Sign in with Supabase
                try await authService.signIn(email: email, password: password)

                guard let userId = authService.currentUserId else {
                    await MainActor.run {
                        errorMessage = "Failed to get user ID"
                        isLoading = false
                    }
                    return
                }

                await completeSignIn(userId: userId)

            } catch {
                await MainActor.run {
                    errorMessage = error.userFacingMessage
                    isLoading = false
                }
            }
        }
    }

    /// Load the identity the app cannot run without, and only then open the app.
    ///
    /// G1 — WHY THE SESSION IS TORN DOWN RATHER THAN LEFT ALIVE BEHIND A RETRY.
    /// It is not `isSignedIn` that admits a user to the app: `RootView` watches
    /// `SupabaseAuthService.isAuthenticated` and pushes into `MainEmployeeView`
    /// on its own the moment that flips true. So a screen that kept the session
    /// and merely declined to set its own flag would be overruled — the user
    /// would land in exactly the empty app this fix exists to prevent. Signing
    /// back out puts the session in the one state the whole app already agrees
    /// on (signed out, local PII purged), and the retry re-runs the full sign-in
    /// from the credentials still in memory. Nothing is logged or persisted.
    func completeSignIn(userId: String) async {
        do {
            // Reuse the app's own fetch instead of the inline query and the
            // duplicate `struct UserProfile` this view used to declare (G40 —
            // that copy also selected `coordinates`, a school-only column that
            // is not on `users`). It decodes the real model and writes ALL of
            // the identity @AppStorage keys, including `userEmail`,
            // `userDisplayName`, `userPhotoURL` and `userPhone`, which this
            // screen never wrote — so the home toolbar avatar could come up
            // blank on a first sign-in (G39).
            let profile = try await UserProfileService.shared.fetchUserProfile(uid: userId)

            // Phase 7 RBAC — the permissions cache has to be populated BEFORE
            // the app opens, because every synchronous permission gate reads it.
            // The fetch above also kicks this off, but detached; awaiting it
            // here is what makes the ordering a fact. An empty role_id CLEARS
            // the cache rather than inheriting one — on a shared iPad the
            // alternative is running as the last person who signed in.
            await PermissionsService.shared.load(roleId: profile.role_id ?? "")

            // THE SAME ADMISSION RULE THE LAUNCH GATE APPLIES, because this
            // screen is now the sole decider on the sign-in path — `RootView`
            // no longer enters the app on its own when a session appears, so
            // whatever this screen decides is what happens.
            //
            // A profile can decode with an EMPTY organization id, and that is the
            // state the whole defect is about: every org-scoped screen then
            // guards out to blank and the app reads as having no data rather than
            // as having failed to sign you in.
            await UserManager.shared.initializeOrganizationIDAsync()
            guard !UserManager.shared.getCachedOrganizationID().isEmpty else {
                throw SignInAdmissionError.noOrganization
            }

            await MainActor.run {
                isLoading = false
                isSignedIn = true
            }

        } catch {
            // Do NOT proceed. See the note above for why the session goes with it.
            try? await authService.signOut()

            await MainActor.run {
                isLoading = false
                profileLoadFailed = true
            }
        }
    }
}

/// Why a sign-in was refused after the password was already accepted.
enum SignInAdmissionError: LocalizedError {
    case noOrganization

    var errorDescription: String? {
        "Signed in, but no organization could be resolved for this account."
    }
}

struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView(isSignedIn: .constant(false))
            .environmentObject(PasswordResetViewModel())
    }
}
