import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

class PushNotificationManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    // Define notification types
    enum NotificationType: String {
        case flag = "flag"
        case jobBox = "jobbox"
        case unknown = "unknown"
    }
    
    // Singleton for easier access
    static let shared = PushNotificationManager()
    
    // Notification center for posting local notifications
    let notificationCenter = NotificationCenter.default
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure Firebase only once.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
        if #available(iOS 10.0, *) {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error = error {
                    print("Error requesting notification authorization: \(error.localizedDescription)")
                } else {
                    print("Notification permission granted: \(granted)")
                }
            }
            center.delegate = self
            Messaging.messaging().delegate = self
        }
        
        application.registerForRemoteNotifications()
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Pass the device token to Firebase Messaging.
        Messaging.messaging().apnsToken = deviceToken
        print("Registered for remote notifications with device token")
        
        // Also register with our JobBoxService
        JobBoxService.shared.registerDeviceToken(deviceToken)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show banner, list, and play sound even when app is in foreground.
        completionHandler([.banner, .list, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle the notification based on type
        handleNotification(userInfo: userInfo)
        
        completionHandler()
    }
    
    // MARK: - MessagingDelegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("Firebase registration token: \(String(describing: fcmToken))")
        // Save the FCM token to Firestore for the current user.
        guard let token = fcmToken, let uid = Auth.auth().currentUser?.uid else {
            return
        }
        let db = Firestore.firestore()
        db.collection("users").document(uid).updateData(["fcmToken": token]) { error in
            if let error = error {
                print("Error updating FCM token in Firestore: \(error.localizedDescription)")
            } else {
                print("Successfully updated FCM token in Firestore.")
            }
        }
    }
    
    // MARK: - Custom Notification Handling
    
    /// Handle incoming notifications
    func handleNotification(userInfo: [AnyHashable: Any]) {
        // Determine the notification type
        let type = userInfo["type"] as? String ?? ""
        let notificationType = NotificationType(rawValue: type) ?? .unknown
        
        switch notificationType {
        case .flag:
            // Post notification for flag event
            notificationCenter.post(name: Notification.Name("didReceiveFlagNotification"),
                                     object: nil,
                                     userInfo: userInfo)
        case .jobBox:
            // Process job box notification
            handleJobBoxNotification(userInfo: userInfo)
        case .unknown:
            print("Received unknown notification type: \(type)")
        }
    }
    
    /// Handle job box specific notifications
    private func handleJobBoxNotification(userInfo: [AnyHashable: Any]) {
        guard let status = userInfo["status"] as? String,
              let schoolName = userInfo["schoolName"] as? String,
              let scannedBy = userInfo["scannedBy"] as? String else {
            print("Missing required job box notification data")
            return
        }
        
        print("Received job box notification: Status: \(status), School: \(schoolName), Scanned by: \(scannedBy)")
        
        // Post a notification that Views can listen for
        notificationCenter.post(name: Notification.Name("didReceiveJobBoxNotification"),
                                 object: nil,
                                 userInfo: userInfo)
    }
}
