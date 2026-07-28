import UIKit
import UserNotifications
import Supabase

class PushNotificationManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Define notification types
    /// THIS ENUM IS THE AUTHORITY for which delivered pushes this app recognises. A type
    /// string the sender uses that is missing here still shows its banner, but falls to
    /// `.unknown` and is not even logged as itself. Any new server-side notification type
    /// MUST be added here in the same change that starts sending it — PSH.1 shipped four
    /// time-off types without doing so and its own audit caught it.
    ///
    /// HONEST LIMIT, do not read more into the cases below than is there: recognising a
    /// type means it is logged and re-posted on `NotificationCenter`. It does NOT mean
    /// tapping the banner navigates anywhere. Of every push name this app posts, only
    /// `didReceiveJobBoxNotification` currently has an observer (ShiftDetailView). The
    /// notification itself is the deliverable — the person is told — and in-app deep
    /// linking is a separate piece of work recorded as PSH.2. This pre-dates PSH.1 and
    /// applies to chat and session pushes too; it is written down here rather than left
    /// to be rediscovered.
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
        // Sent by the trg_time_off_notification database trigger (PSH.1).
        case timeOffSubmitted = "time_off_submitted"
        case timeOffApproved = "time_off_approved"
        case timeOffDenied = "time_off_denied"
        case timeOffPartiallyApproved = "time_off_partially_approved"
        // Sent by the daily-workflow-check scheduled function.
        case workflowStepScheduled = "workflow_step_scheduled"
        case unknown = "unknown"
    }
    
    // NOTE (PSH.1): the `shared` singleton was DELETED here. It was never the object the
    // app actually ran — `@UIApplicationDelegateAdaptor(PushNotificationManager.self)` makes
    // SwiftUI construct its own instance — and it had zero callers, so the one piece of code
    // that did use it (this phase's own first attempt at the post-sign-in token retry) wrote
    // to one object and read from another and could never have worked. Anything that must be
    // reachable from outside the delegate is `static` instead, which both objects share.
    // Do not reintroduce it.

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
    ///
    /// DELIBERATELY STATIC, and this is load-bearing. `@UIApplicationDelegateAdaptor` makes
    /// SwiftUI construct its OWN instance of this class, which is NOT the `shared` singleton
    /// above — `shared` in fact had zero callers before PSH.1. An instance property here
    /// would be written by the adaptor's object and read by `shared`'s, so the flush would
    /// find nil forever and quietly do nothing. Static storage is seen by both.
    private static var pendingDeviceToken: String?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert device token to hex string for APNs
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        Self.pendingDeviceToken = tokenString

        // Save APNs token to Supabase
        Self.saveAPNsTokenToSupabase(token: tokenString)
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
    /// Called from `SupabaseAuthService` on the `signedIn` auth-state event. STATIC on
    /// purpose: see the note on `pendingDeviceToken`. An instance method here would be
    /// called on the `shared` singleton while the token lives on SwiftUI's own delegate
    /// instance, and would never find anything.
    ///
    /// This also covers the second-user case. APNs only hands out a token once per launch,
    /// so if one person signs out and another signs in without relaunching, nothing would
    /// otherwise write the new person's token. The token is kept for the whole launch and
    /// re-saved against whoever signs in.
    static func flushPendingAPNsToken() {
        guard let token = pendingDeviceToken else { return }
        saveAPNsTokenToSupabase(token: token)
    }

    /// Detach this device from the account that is signing out.
    ///
    /// Without this, the row keeps pointing at a handset the person no longer holds, and
    /// the next occupant of the phone receives their notifications — denial reasons, chat
    /// previews, session changes. That was harmless only while nothing was ever delivered;
    /// PSH.1 is the change that makes it real.
    /// AWAITED on purpose, and called from `signOut()` while the session is still valid.
    /// Fire-and-forget here would race the session teardown that follows it.
    static func clearAPNsTokenOnSignOut(userId: String) async {
        // Only clear the row if it is THIS handset's token sitting in it.
        //
        // There is one apns_token column per user, shared by all their devices, so an
        // unconditional clear would be wrong for somebody signed in on both an iPhone and
        // an iPad: signing out on the iPad would silence the iPhone. Matching on the token
        // means we only detach the device actually being signed out of. (A single column
        // still cannot serve two devices at once — the real fix is one row per device, and
        // that is recorded as PSH.2, not faked here.)
        guard let thisDeviceToken = pendingDeviceToken else {
            print("⚠️ [Push] No device token held this launch; nothing to detach on sign-out.")
            return
        }

        do {
            // `returning: .representation` so we can tell "cleared the row" from "matched no
            // rows". An UPDATE that matches nothing is a 200 with an empty array, not an
            // error — reporting that as success is how the first version of this fix managed
            // to print a tick while changing nothing.
            struct ClearedRow: Decodable { let id: String }

            let cleared: [ClearedRow] = try await SupabaseManager.shared.client
                .from("users")
                .update([
                    "apns_token": AnyJSON.null,
                    "apns_environment": AnyJSON.null
                ], returning: .representation)
                .eq("id", value: userId.lowercased())
                .eq("apns_token", value: thisDeviceToken)
                .select("id")
                .execute()
                .value

            if !cleared.isEmpty {
                print("✅ [Push] Detached this device from the signed-out account.")
            } else {
                // Not necessarily a fault: the account's stored token may belong to the
                // user's OTHER device, which we deliberately do not touch.
                print("ℹ️ [Push] Sign-out token clear matched no row — the account's stored token is not this device's.")
            }
        } catch {
            print("‼️ [Push] FAILED to clear APNs token on sign-out — this device may still receive that account's notifications: \(error.localizedDescription)")
        }

        // pendingDeviceToken is deliberately KEPT. It describes this handset, not the
        // account that just left, and the next person to sign in during this same launch
        // needs it — APNs only issues a token once per launch.
    }

    /// Save APNs device token to Supabase users table, together with the Apple push
    /// environment that minted it.
    ///
    /// The environment matters as much as the token: a sandbox token presented to Apple's
    /// production service is rejected with `BadDeviceToken`, which is exactly what PSH.1
    /// found happening to every push this app has ever sent. The sender reads this column to
    /// choose the right endpoint per token, so a development install and a TestFlight install
    /// can both work at once.
    private static func saveAPNsTokenToSupabase(token: String) {
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

                // NOTE: pendingDeviceToken is deliberately NOT cleared here. APNs issues a
                // token once per launch, so if this person signs out and somebody else signs
                // in on the same handset without relaunching, the token has to still be
                // available to write against the new account. Holding it for the whole
                // launch is what makes that work.
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
        case .timeOffSubmitted, .timeOffApproved, .timeOffDenied, .timeOffPartiallyApproved:
            handleTimeOffNotification(userInfo: userInfo, type: notificationType)
        case .workflowStepScheduled:
            notificationCenter.post(name: Notification.Name("didReceiveWorkflowStepNotification"),
                                     object: nil,
                                     userInfo: userInfo)
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
    
    /// Handle time-off notifications (submitted, approved, denied, partially approved).
    ///
    /// Sent by the `trg_time_off_notification` trigger on `time_off_requests`, so it fires
    /// whether the decision was made from this app or from the web app.
    private func handleTimeOffNotification(userInfo: [AnyHashable: Any], type: NotificationType) {
        let requestId = userInfo["requestId"] as? String
        let status = userInfo["status"] as? String ?? "unknown"

        print("Received time off notification: \(type.rawValue), request: \(requestId ?? "n/a"), status: \(status)")

        // Distinguish "somebody needs you to decide" from "your request was decided", since
        // the two land on different screens.
        let name = type == .timeOffSubmitted
            ? "didReceiveTimeOffRequestNotification"
            : "didReceiveTimeOffDecisionNotification"

        notificationCenter.post(name: Notification.Name(name),
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
