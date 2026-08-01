//  RootView.swift
//  Iconik Employee — the launch gate
//
//  CONVERTED IN AMB.12, as one of the five shell surfaces that belonged to no
//  phase (operator ruling D15). It is the FIRST FRAME of the app and it was one
//  line: a bare, unmodified `ProgressView()` — no text, no logo, no background,
//  no tint — on screen for anything up to its own ten-second deadline while three
//  unbounded network awaits ran behind it.
//
//  WHAT WAS ABSENT, verified by a full read of the file rather than assumed to be
//  handled elsewhere: a spinner label, any branding, a timeout state, offline
//  detection, any error surface for the two profile refreshes, and a terminal
//  state for "signed in but we still do not know which organization you are in".
//
//  THE THREE REAL FIXES, beyond the look:
//
//  1. THE CANCELLED-SLEEP SPIN. The session poll slept 50ms per iteration with
//     `try?`, which SWALLOWS the cancellation error — so a cancelled task did not
//     stop, it span on the main actor until the ten-second deadline expired.
//     `MainEmployeeView:522-530` explicitly `break`s out of exactly this and
//     documents why; this file had no such break. It does now.
//
//  2. ENTERING THE APP WITH NO ORGANIZATION. If the org id was still empty after
//     two profile refreshes, the old code entered `MainEmployeeView` anyway.
//     Every org-scoped screen then guards out to blank, so the app reads as
//     having no data rather than as having failed to sign you in. This is the
//     same defect class as the sign-in path's (G1), at launch instead of at
//     sign-in, and it is fixed the same way: say so, and offer a way forward.
//
//  3. `onChange` COULD DEFEAT THE SIGN-IN FIX. `SignInView` now refuses to
//     complete a sign-in whose profile fetch failed — but this view also watched
//     `authService.isAuthenticated` and set `isSignedIn = true` the moment the
//     Supabase session appeared, regardless. Two places deciding the same thing
//     with different rules is how the fix in one gets undone by the other, so
//     this path now applies the same rule.

import SwiftUI
import Supabase

struct RootView: View {
    /// What the launch gate is doing, so the screen can say it.
    private enum LaunchState: Equatable {
        case checking
        /// The session check never finished inside its deadline — we do not know
        /// whether this person is signed in, which is different from knowing they
        /// are not.
        case unreachable
        /// Signed in, but the organization never resolved. The app cannot show
        /// anything useful in this state, and silently pretending otherwise is
        /// what this replaces.
        case noOrganization
    }

    @State private var launchState: LaunchState = .checking
    @State private var isCheckingAuth = true
    @State private var isSignedIn = false
    @StateObject private var userManager = UserManager.shared
    @StateObject private var profileService = UserProfileService.shared
    @ObservedObject private var authService = SupabaseAuthService.shared
    @EnvironmentObject var passwordResetVM: PasswordResetViewModel

    var body: some View {
        Group {
            if isCheckingAuth {
                launchScreen
            } else if isSignedIn {
                MainEmployeeView(isSignedIn: $isSignedIn)
            } else {
                SignInView(isSignedIn: $isSignedIn)
            }
        }
        .task {
            await resolveSession()
        }
        // ONLY the sign-OUT direction. This used to also enter the app whenever a
        // Supabase session appeared, and that made TWO deciders for one question.
        //
        // It mattered as soon as `SignInView` started refusing to complete a
        // sign-in whose profile fetch failed: that screen signs the session back
        // out, while this watcher — racing it — could resolve an organization and
        // push into the app first. The user would be dropped into the dashboard
        // for an instant and then bounced back to a BLANK sign-in screen, with
        // the explanation destroyed along with the view that carried it.
        //
        // Entry now has exactly one owner per path: `SignInView` after a
        // sign-in, `resolveSession()` at launch. Both apply the same rule.
        //
        // IT ALSO FIXES A COPY LIE. `signUp` flips `isAuthenticated` too, so this
        // watcher used to drop a brand-new account straight into the app while
        // Create Account's own shipped message said "Account created
        // successfully. Please sign in." Now that sentence is true.
        .onChange(of: authService.isAuthenticated) { isAuthenticated in
            guard !isAuthenticated else { return }
            // Sign out — immediate, and it must never be blocked by anything else.
            isSignedIn = false
            isCheckingAuth = false
            launchState = .checking
        }
        .sheet(isPresented: $passwordResetVM.showingResetPassword) {
            ResetPasswordView(viewModel: passwordResetVM)
        }
    }

    // MARK: - The screen

    private var launchScreen: some View {
        ZStack {
            AmbientBackdrop(intensity: 0.85)

            VStack(spacing: 18) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(AmbientStyle.brand)
                    .accessibilityHidden(true)

                Text("Iconik")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))

                switch launchState {
                case .checking:
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Signing you in…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Signing you in")

                case .unreachable:
                    VStack(spacing: 12) {
                        AmbientFailureCard(
                            message: "Can't reach the server right now.",
                            action: { retry() })
                        AmbientActionButton(title: "Sign in instead",
                                            role: .secondary,
                                            fillWidth: false) {
                            // The old code fell through to Sign In silently on
                            // this path. It is still reachable — it is just a
                            // choice now rather than a surprise.
                            launchState = .checking
                            isCheckingAuth = false
                        }
                    }

                case .noOrganization:
                    VStack(spacing: 12) {
                        AmbientFailureCard(
                            message: "We couldn't load your organization.",
                            action: { retry() })
                        Text("You're signed in, but we couldn't read which organization you belong to — without it every screen would be empty.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        AmbientActionButton(title: "Sign out",
                                            role: .destructive,
                                            fillWidth: false) {
                            Task { try? await authService.signOut() }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 420)
        }
    }

    // MARK: - Session resolution

    private func retry() {
        launchState = .checking
        isCheckingAuth = true
        Task { await resolveSession() }
    }

    private func resolveSession() async {
        // Wait for SupabaseAuthService to finish checkSession().
        //
        // Token refresh is a network call that can take 200-600ms — a fixed 100ms
        // sleep was not reliably long enough, causing isAuthenticated to still be
        // false when read, leading to empty data screens on first open.
        //
        // `sessionCheckComplete` means THE CHECK FINISHED, not that it succeeded:
        // SupabaseAuthService sets it on both branches of its do/catch.
        let deadline = Date().addingTimeInterval(10)
        while !authService.sessionCheckComplete && Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: 50_000_000) // poll every 50ms
            } catch {
                // Cancelled. Break rather than spin — `try?` here is what turned
                // a cancelled poll into a ten-second main-actor spin.
                return
            }
        }

        guard authService.sessionCheckComplete else {
            // The deadline won. We do NOT know whether this person has a session,
            // so we do not quietly assert that they do not.
            await MainActor.run { launchState = .unreachable }
            return
        }

        guard authService.isAuthenticated else {
            await MainActor.run {
                launchState = .checking
                isCheckingAuth = false
            }
            return
        }

        await enterAppIfReady()
    }

    /// The ONE rule for "may this person enter the app", used by both the launch
    /// path and the sign-in path.
    private func enterAppIfReady() async {
        // IMPORTANT: resolve the organization BEFORE showing the main view. This
        // is the race that made views load before the org ID was available.
        await userManager.initializeOrganizationIDAsync()
        await profileService.refreshCurrentUserProfile()

        if userManager.getCachedOrganizationID().isEmpty {
            // One more attempt via the profile service.
            await profileService.refreshCurrentUserProfile()
        }

        let hasOrganization = !userManager.getCachedOrganizationID().isEmpty

        await MainActor.run {
            if hasOrganization {
                launchState = .checking
                isSignedIn = true
                isCheckingAuth = false
            } else {
                // Signed in with no organization. Previously this entered the app
                // anyway and every screen guarded out to blank.
                launchState = .noOrganization
                isSignedIn = false
                isCheckingAuth = true
            }
        }
    }
}
