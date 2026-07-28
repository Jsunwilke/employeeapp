import UIKit
import UserNotifications
import Supabase

class PushNotificationManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Define notification types
    enum NotificationType: String {
        case flag = "flag"
        case jobBox = "jobbox"
        case chatMessage = "chat_message"
        case sessionNew = "session_new"
        case sessionUpdate = "session_update"
        case sessionDelete = "session_delete"
        case clockReminder = "clock_reminder"
        case reportReminder = "report_reminder"
        case photoCritique = "photo_critique"
        case unknown = "unknown"
    }
    
    // Singleton for easier access
    static let shared = PushNotificationManager()
    
    // Notification center for posting local notifications
    let notificationCenter = NotificationCenter.default
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Request notification permissions
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error.localizedDescription)")
            } else {
                print("Notification permission granted: \(granted)")
            }
        }
        center.delegate = self

        // Register for remote notifications (APNs)
        application.registerForRemoteNotifications()
        return true
    }

    // MARK: - Deep Link Handling

    /// Handle URL callbacks (Supabase OAuth + Google Sign-In)
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("📱 Received URL: \(url.absoluteString)")

        // Handle Supabase OAuth callback
        if url.scheme == "iconikemployee" && url.host == "auth-callback" {
            print("🔐 Processing Supabase OAuth callback")

            Task {
                do {
                    try await SupabaseAuthService.shared.handleOAuthCallback(url: url)
                    print("✅ OAuth callback processed successfully")

                    // Post notification to update UI
                    NotificationCenter.default.post(
                        name: Notification.Name("didCompleteOAuthSignIn"),
                        object: nil
                    )
                } catch {
                    print("❌ OAuth callback error: \(error.localizedDescription)")

                    // Post error notification
                    NotificationCenter.default.post(
                        name: Notification.Name("didFailOAuthSignIn"),
                        object: nil,
                        userInfo: ["error": error.localizedDescription]
                    )
                }
            }

            return true
        }

        // No other URL handlers needed (Google Sign-In removed)
        return false
    }
    
    /// The most recent device token APNs handed us this launch.
    ///
    /// Registration happens in `didFinishLaunchingWithOptions`, which on a first-ever launch
    /// runs BEFORE anybody has signed in — so the save below has no user to attach the token
    /// to and does nothing. Holding the token here lets `flushPendingAPNsToken()` store it the
    /// moment a session appears, instead of losing it until the user's next cold launch.
    private var pendingDeviceToken: String?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert device token to hex string for APNs
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        pendingDeviceToken = tokenString

        // Save APNs token to Supabase
        saveAPNsTokenToSupabase(token: tokenString)
    }

    /// APNs refused to issue a device token.
    ///
    /// Without this, registration failure is completely silent — the app simply never has a
    /// token and nothing anywhere says why. That invisibility is half of why PSH.1's bug
    /// survived: every layer failed quietly.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("‼️ [Push] APNs registration FAILED — this device will receive no notifications: \(error.localizedDescription)")
    }

    /// Store the token we already hold, now that a user has signed in.
    ///
    /// Called from `SupabaseAuthService` on the `signedIn` auth-state event.
    func flushPendingAPNsToken() {
        guard let token = pendingDeviceToken else { return }
        saveAPNsTokenToSupabase(token: token)
    }

    /// Save APNs device token to Supabase users table, together with the Apple push
    /// environment that minted it.
    ///
    /// The environment matters as much as the token: a sandbox token presented to Apple's
    /// production service is rejected with `BadDeviceToken`, which is exactly what PSH.1
    /// found happening to every push this app has ever sent. The sender reads this column to
    /// choose the right endpoint per token, so a development install and a TestFlight install
    /// can both work at once.
    private func saveAPNsTokenToSupabase(token: String) {
        guard let userId = UserManager.shared.getCurrentUserIDUnified() else {
            print("⚠️ [Push] APNs token received before sign-in; holding it until a session exists.")
            return
        }

        let environment = APNsEnvironment.current

        Task {
            do {
                let supabase = SupabaseManager.shared.client

                // Update apns_token in users table
                try await supabase
                    .from("users")
                    .update([
                        "apns_token": AnyJSON.string(token),
                        "apns_environment": AnyJSON.string(environment.rawValue)
                    ])
                    .eq("id", value: userId.lowercased())
                    .execute()

                print("✅ [Push] APNs token stored (\(environment.rawValue)).")

                // The token is safely stored; stop holding it for a post-sign-in retry.
                await MainActor.run { self.pendingDeviceToken = nil }
            } catch {
                // Deliberately loud. The previous version swallowed this into a bare print with
                // no marker, so a token that never reached the database looked identical to one
                // that did.
                print("‼️ [Push] FAILED to store APNs token — this device will receive no notifications: \(error.localizedDescription)")
            }
        }
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
        case .chatMessage:
            // Process chat notification
            handleChatNotification(userInfo: userInfo)
        case .sessionNew:
            // Process new session notification
            handleSessionNotification(userInfo: userInfo, isNew: true)
        case .sessionUpdate:
            // Process session update notification
            handleSessionNotification(userInfo: userInfo, isNew: false)
        case .sessionDelete:
            // Process session deletion notification
            handleSessionDeleteNotification(userInfo: userInfo)
        case .clockReminder:
            // Process clock reminder notification
            handleClockReminderNotification(userInfo: userInfo)
        case .reportReminder:
            // Process report reminder notification
            handleReportReminderNotification(userInfo: userInfo)
        case .photoCritique:
            // Process photo critique notification
            handlePhotoCritiqueNotification(userInfo: userInfo)
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
    
    /// Handle chat message notifications
    private func handleChatNotification(userInfo: [AnyHashable: Any]) {
        // Check if this is a chat notification
        if let conversationId = userInfo["conversationId"] as? String {
            // Handle chat notification
            print("Received chat notification")
            
            let senderId = userInfo["senderId"] as? String
            let senderName = userInfo["senderName"] as? String ?? "Someone"
            let messageText = userInfo["messageText"] as? String ?? "New message"
            
            print("From: \(senderName), ConversationId: \(conversationId)")
            
            // Post notification for chat
            notificationCenter.post(name: Notification.Name("didReceiveChatNotification"),
                                     object: nil,
                                     userInfo: userInfo)
        } else {
            print("Unknown chat notification format")
        }
    }
    
    /// Handle session notifications (new or updated)
    private func handleSessionNotification(userInfo: [AnyHashable: Any], isNew: Bool) {
        guard let sessionId = userInfo["sessionId"] as? String,
              let schoolName = userInfo["schoolName"] as? String else {
            print("Missing required session notification data")
            return
        }
        
        let changeType = userInfo["changeType"] as? String
        
        print("Received session \(isNew ? "new" : "update") notification: Session: \(sessionId), School: \(schoolName), Changes: \(changeType ?? "N/A")")
        
        // Post a notification that Views can listen for
        notificationCenter.post(name: Notification.Name(isNew ? "didReceiveNewSessionNotification" : "didReceiveSessionUpdateNotification"),
                                 object: nil,
                                 userInfo: userInfo)
    }

    /// Handle session deletion notifications
    private func handleSessionDeleteNotification(userInfo: [AnyHashable: Any]) {
        guard let sessionId = userInfo["sessionId"] as? String,
              let schoolName = userInfo["schoolName"] as? String else {
            print("Missing required session delete notification data")
            return
        }

        let sessionDate = userInfo["sessionDate"] as? String ?? "Unknown date"

        print("Received session delete notification: Session: \(sessionId), School: \(schoolName), Date: \(sessionDate)")

        // Post a notification that Views can listen for
        notificationCenter.post(name: Notification.Name("didReceiveSessionDeleteNotification"),
                                 object: nil,
                                 userInfo: userInfo)
    }

    /// Handle clock reminder notifications
    private func handleClockReminderNotification(userInfo: [AnyHashable: Any]) {
        guard let reminderType = userInfo["reminderType"] as? String else {
            print("Missing reminder type in clock notification")
            return
        }
        
        print("Received clock reminder notification: Type: \(reminderType)")
        
        if reminderType == "clock_in" {
            let sessionId = userInfo["sessionId"] as? String
            let schoolName = userInfo["schoolName"] as? String ?? "your session"
            print("Clock-in reminder for session at \(schoolName)")
        } else if reminderType == "clock_out" {
            print("Clock-out reminder received")
        }
        
        // Post a notification that Views can listen for
        notificationCenter.post(name: Notification.Name("didReceiveClockReminderNotification"),
                                 object: nil,
                                 userInfo: userInfo)
    }
    
    /// Handle daily report reminder notifications
    private func handleReportReminderNotification(userInfo: [AnyHashable: Any]) {
        let date = userInfo["date"] as? String ?? "today"
        let sessionsCount = userInfo["sessionsCount"] as? Int ?? 0
        
        print("Received report reminder notification: Date: \(date), Sessions: \(sessionsCount)")
        
        // Post a notification that Views can listen for
        notificationCenter.post(name: Notification.Name("didReceiveReportReminderNotification"),
                                 object: nil,
                                 userInfo: userInfo)
    }
    
    /// Handle photo critique notifications
    private func handlePhotoCritiqueNotification(userInfo: [AnyHashable: Any]) {
        guard let critiqueId = userInfo["critiqueId"] as? String,
              let submitterName = userInfo["submitterName"] as? String else {
            print("Missing required photo critique notification data")
            return
        }
        
        let exampleType = userInfo["exampleType"] as? String ?? "unknown"
        
        print("Received photo critique notification: From: \(submitterName), Type: \(exampleType), ID: \(critiqueId)")
        
        // Post a notification that Views can listen for
        notificationCenter.post(name: Notification.Name("didReceivePhotoCritiqueNotification"),
                                 object: nil,
                                 userInfo: userInfo)
    }
}
