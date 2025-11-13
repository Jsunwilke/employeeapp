import SwiftUI
import Firebase

@main
struct EmployeeAppApp: App {
    // Use PushNotificationManager as your app delegate.
    @UIApplicationDelegateAdaptor(PushNotificationManager.self) var pushManager
    
    // Access the AppStorage value for app theme
    @AppStorage("appTheme") private var appTheme: String = "system"

    init() {
        FirebaseApp.configure()

        // Enable Firestore offline persistence for better caching and offline support
        let settings = FirestoreSettings()
        // Use the new cacheSettings property
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited))
        Firestore.firestore().settings = settings

        print("🔥 Firestore persistence enabled with unlimited cache")

        // Migrate existing JSON cache to CoreData (one-time migration)
        LocalSportsShootRepository.shared.migrateFromJSONCache()

        // Start background sync service for offline-first architecture
        BackgroundSyncService.shared.startMonitoring()
        print("🔄 BackgroundSyncService started monitoring for pending changes")

        // Apply the saved theme immediately during app initialization
        applyAppTheme()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    // Also apply theme when root view appears, for good measure
                    applyAppTheme()
                }
        }
    }
    
    // Apply the theme based on the AppStorage value
    private func applyAppTheme() {
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes
            guard let windowScene = scenes.first as? UIWindowScene else { return }
            
            for window in windowScene.windows {
                switch appTheme {
                case "light":
                    window.overrideUserInterfaceStyle = .light
                case "dark":
                    window.overrideUserInterfaceStyle = .dark
                default:
                    window.overrideUserInterfaceStyle = .unspecified
                }
            }
        }
    }
}
