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
    /// PSH.2: a tapped banner now NAVIGATES. `handleNotification` runs only from the tap
    /// callback (`didReceive`), sets the destination's pending id on
    /// `TabBarManager.shared` and then switches the tab; the target view consumes and
    /// clears the id. The one `NotificationCenter` post that had a real observer —
    /// `didReceiveJobBoxNotification`, which ShiftDetailView uses to live-refresh an open
    /// shift — is kept; the other per-type posts had ZERO observers anywhere in the app
    /// and were deleted with the routing that replaced them.
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
        // PSH.2: tokens live in user_devices, one row per device, so the sign-out delete
        // is exact — this handset's row goes, the person's OTHER devices keep theirs.
        // (Under the old single-column model this needed a token-match guard so an iPad
        // sign-out would not silence the iPhone; a per-device row makes that shape
        // structural instead of defensive.)
        guard let thisDeviceToken = pendingDeviceToken else {
            print("⚠️ [Push] No device token held this launch; nothing to detach on sign-out.")
            return
        }

        do {
            // `returning: .representation` so we can tell "deleted the row" from "matched
            // no rows". A DELETE that matches nothing is a 200 with an empty array, not an
            // error — reporting that as success is how the first version of the old clear
            // managed to print a tick while changing nothing. RLS scopes the delete to the
            // signing-out user's own rows, which is why this runs BEFORE auth.signOut().
            struct DeletedRow: Decodable { let token: String }

            let deleted: [DeletedRow] = try await SupabaseManager.shared.client
                .from("user_devices")
                .delete(returning: .representation)
                .eq("token", value: thisDeviceToken)
                .select("token")
                .execute()
                .value

            if !deleted.isEmpty {
                print("✅ [Push] Detached this device from the signed-out account (user \(userId)).")
            } else {
                // Not necessarily a fault: the token may never have been registered for
                // this account (e.g. notifications denied before any save succeeded).
                print("ℹ️ [Push] Sign-out device delete matched no row — this device was not registered to the account.")
            }
        } catch {
            print("‼️ [Push] FAILED to detach this device on sign-out — it may still receive that account's notifications: \(error.localizedDescription)")
        }

        // pendingDeviceToken is deliberately KEPT. It describes this handset, not the
        // account that just left, and the next person to sign in during this same launch
        // needs it — APNs only issues a token once per launch.
    }

    /// Register this device in user_devices (PSH.2: one row per device), together with the
    /// Apple push environment that minted its token.
    ///
    /// The environment matters as much as the token: a sandbox token presented to Apple's
    /// production service is rejected with `BadDeviceToken`, which is exactly what PSH.1
    /// found happening to every push this app has ever sent. The senders read it per row to
    /// choose the right endpoint per device, so a development install and a TestFlight
    /// install can both work at once.
    ///
    /// Goes through the register_push_device SECURITY DEFINER RPC rather than a direct
    /// insert ("push" in the name because public.register_device already belongs to the
    /// hardware/station registry),
    /// because registration must be able to EVICT a stale row: if the previous user of this
    /// handset signed out uncleanly (crash, reinstall), their row still points at this
    /// token, own-row RLS makes it untouchable from this account, and until it is evicted
    /// the previous user's notifications land on a device they no longer hold.
    private static func saveAPNsTokenToSupabase(token: String) {
        guard UserManager.shared.getCurrentUserIDUnified() != nil else {
            print("⚠️ [Push] APNs token received before sign-in; holding it until a session exists.")
            return
        }

        let environment = APNsEnvironment.current

        Task {
            do {
                let supabase = SupabaseManager.shared.client

                try await supabase
                    .rpc("register_push_device", params: [
                        "p_token": AnyJSON.string(token),
                        "p_environment": AnyJSON.string(environment.rawValue)
                    ])
                    .execute()

                print("✅ [Push] Device registered (\(environment.rawValue)).")

                // NOTE: pendingDeviceToken is deliberately NOT cleared here. APNs issues a
                // token once per launch, so if this person signs out and somebody else signs
                // in on the same handset without relaunching, the token has to still be
                // available to write against the new account. Holding it for the whole
                // launch is what makes that work.
            } catch {
                // Deliberately loud. The previous version swallowed this into a bare print with
                // no marker, so a token that never reached the database looked identical to one
                // that did.
                print("‼️ [Push] FAILED to register this device — it will receive no notifications: \(error.localizedDescription)")
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        let type = userInfo["type"] as? String
        let conversationId = userInfo["conversationId"] as? String

        // A chat push for the thread ALREADY ON SCREEN is suppressed (review round):
        // with the chat trigger wired, two people talking in-app would otherwise get a
        // banner and sound over every message of the conversation they are reading —
        // the realtime stream renders the message in place, so the banner adds nothing.
        // Every other type (and chat for a different thread) still presents.
        Task { @MainActor in
            if type == NotificationType.chatMessage.rawValue,
               let cid = conversationId,
               let visible = ChatManager.shared.visibleConversationId,
               visible.lowercased() == cid.lowercased() {
                completionHandler([])
                return
            }
            completionHandler([.banner, .list, .sound])
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle the notification based on type
        handleNotification(userInfo: userInfo)
        
        completionHandler()
    }
    
    // MARK: - Tap Routing (PSH.2)

    /// Route a TAPPED notification to its screen.
    ///
    /// Called only from `userNotificationCenter(_:didReceive:)` — the person pressed the
    /// banner, so switching tabs is what they asked for. The pending id is set BEFORE
    /// `selectedTab` on purpose: MainEmployeeView reacts to tab changes (it clears Home's
    /// push state on leave), and the consuming view may read the id the moment its tab
    /// appears. Everything runs on the main queue — UNUserNotificationCenter promises the
    /// delegate callback there, but `TabBarManager` is UI state and the hop is cheap
    /// insurance against a future caller.
    func handleNotification(userInfo: [AnyHashable: Any]) {
        let type = userInfo["type"] as? String ?? ""
        let notificationType = NotificationType(rawValue: type) ?? .unknown

        DispatchQueue.main.async {
            let tabs = TabBarManager.shared

            switch notificationType {
            case .flag:
                // Nowhere to land: the flagged-status surface is unmounted dead code (a
                // recorded SEC.* decision — build it or delete it). Opening the app is the
                // whole interaction; the note itself shows on the person's next load.
                print("Flag notification tapped — no in-app destination exists yet (SEC.*)")

            case .jobBox:
                // Live-refresh observer first (ShiftDetailView listens while a shift is
                // open), then navigate to the shift the box belongs to.
                self.notificationCenter.post(name: Notification.Name("didReceiveJobBoxNotification"),
                                             object: nil,
                                             userInfo: userInfo)
                if let shiftUid = userInfo["shiftUid"] as? String, !shiftUid.isEmpty {
                    tabs.pendingSession = PendingDeepLink(id: shiftUid)
                }
                tabs.selectedTab = "schedule"

            case .chatMessage:
                if let conversationId = userInfo["conversationId"] as? String {
                    tabs.pendingConversation = PendingDeepLink(id: conversationId)
                }
                tabs.selectedTab = "chat"

            case .sessionNew, .sessionUpdate:
                if let sessionId = userInfo["sessionId"] as? String {
                    tabs.pendingSession = PendingDeepLink(id: sessionId)
                }
                tabs.selectedTab = "schedule"

            case .sessionDelete:
                // The session is gone; there is no detail to open. The schedule itself is
                // the answer to "so what does my week look like now?".
                tabs.selectedTab = "schedule"

            case .clockReminder:
                tabs.selectedTab = "timeTracking"

            case .reportReminder:
                // If the org runs photoshoot-notes-only, this feature id is unavailable
                // and MainEmployeeView's guard redirects to Home — acceptable, and the
                // dispatcher only targets crews with sessions, so the mismatch is rare.
                tabs.selectedTab = "dailyJobReport"

            case .photoCritique:
                if let critiqueId = userInfo["critiqueId"] as? String {
                    tabs.pendingCritique = PendingDeepLink(id: critiqueId)
                }
                tabs.selectedTab = "training"

            case .timeOffSubmitted:
                // "Somebody needs you to decide" lands on the approvals queue…
                tabs.selectedTab = "timeOffApprovals"

            case .timeOffApproved, .timeOffDenied, .timeOffPartiallyApproved:
                // …and "your request was decided" lands on your own requests, where the
                // full decision (including any reason, kept off the lock screen by the
                // PSH.2 privacy change) is shown.
                tabs.selectedTab = "timeOffRequests"

            case .workflowStepScheduled:
                tabs.selectedTab = "tasks"

            case .unknown:
                print("Received unknown notification type: \(type)")
            }
        }
    }
}
