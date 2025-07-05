import UIKit
import GoogleSignIn

extension PushNotificationManager {
    // This method handles the URL scheme for Google Sign-In
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}
