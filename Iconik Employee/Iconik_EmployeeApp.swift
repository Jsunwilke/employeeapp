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
