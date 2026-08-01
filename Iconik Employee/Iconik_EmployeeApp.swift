import SwiftUI

// Notification for when app returns to foreground - views can listen to re-subscribe
extension Notification.Name {
    static let appDidBecomeActive = Notification.Name("appDidBecomeActive")
}

@main
struct EmployeeAppApp: App {
    // Use PushNotificationManager as your app delegate.
    @UIApplicationDelegateAdaptor(PushNotificationManager.self) var pushManager

    // Access the AppStorage value for app theme
    @AppStorage("appTheme") private var appTheme: String = "system"

    // Track scene phase for background/foreground handling
    @Environment(\.scenePhase) private var scenePhase

    // Password reset view model for deep link handling
    @StateObject private var passwordResetVM = PasswordResetViewModel()

    init() {
        // Initialize Supabase (singleton pattern - initialized on first access)
        _ = SupabaseManager.shared
        print("✅ Supabase initialized and ready")

        // Initialize PowerSync for offline-first sync
        Task {
            do {
                try await PowerSyncManager.shared.initialize()
                print("⚡ PowerSync initialized and connected")
            } catch {
                print("⚠️ PowerSync initialization failed: \(error)")
            }
        }

        // Apply the saved theme immediately during app initialization
        applyAppTheme()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(passwordResetVM)
                .onAppear {
                    // Also apply theme when root view appears, for good measure
                    applyAppTheme()
                }
                .onChange(of: scenePhase) { newPhase in
                    handleScenePhaseChange(newPhase)
                }
                .onOpenURL { url in
                    handleDeepLink(url: url)
                }
        }
    }

    // Handle deep links (password reset, etc.)
    private func handleDeepLink(url: URL) {
        print("📱 Received deep link: \(url)")

        // Handle password reset deep links
        if url.scheme == "iconik" && url.host == "reset-password" {
            Task {
                await passwordResetVM.handleDeepLink(url: url)
            }
        }
    }

    // Handle app going to background/foreground
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            print("📱 App entering background - pausing subscriptions")
            // Stop all realtime subscriptions to save resources
            Task {
                // Schedule services
                SessionService.shared.stopAllListeners()

                // Sports roster services
                await RosterEntryService.shared.unsubscribeAll()
                await GroupImageService.shared.unsubscribeAll()

                // Task services
                TaskService.shared.stopListening()
                CommentService.shared.stopAllListeners()

                // Time off
                await TimeOffService.shared.stopListening()

                // Organization
                OrganizationService.shared.stopListening()
            }

        case .active:
            print("📱 App becoming active - notifying views to re-subscribe")
            // Post notification so views can re-establish their subscriptions
            NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)

        case .inactive:
            // Transitional state, no action needed
            break

        @unknown default:
            break
        }
    }
    
    /// Apply the stored theme. One applier, in `Utilities/AppTheme.swift`.
    ///
    /// There were TWO copies of this with different bodies — this one and
    /// `MainEmployeeView`'s, which additionally wrote an "AppleInterfaceStyle"
    /// string into UserDefaults and posted a system-looking notification that
    /// nothing in the repo reads or observes. Merged at AMB.12; the two dead
    /// statements went with the merge.
    private func applyAppTheme() {
        AppTheme.apply(storedValue: appTheme)
    }
}
