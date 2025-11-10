import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("[AppDelegate] 🔴 didFinishLaunchingWithOptions START")

#if canImport(FirebaseCore)
        // CRITICAL: Configure Firebase HERE in AppDelegate, not in StepOutApp.init()
        // This ensures method swizzling is set up correctly
        if FirebaseApp.app() == nil {
            print("[AppDelegate] 🔴 Configuring Firebase with explicit options...")
            guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                  let options = FirebaseOptions(contentsOfFile: path) else {
                print("[AppDelegate] ⚠️ Failed to load GoogleService-Info.plist, using default config")
                FirebaseApp.configure()
                print("[AppDelegate] 🟢 Firebase configured (default)")
                return true
            }
            FirebaseApp.configure(options: options)
            print("[AppDelegate] 🟢 Firebase configured with explicit options")
        }
#endif

#if canImport(FirebaseMessaging)
        // Set FCM messaging delegate
        Messaging.messaging().delegate = self
        print("[AppDelegate] 🟢 FCM messaging delegate set")
#endif

        // Register for remote notifications
        // With swizzling enabled, Firebase will automatically intercept APNs callbacks
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("[AppDelegate] 🟢 Notification permission granted")
            } else {
                print("[AppDelegate] 🔴 Notification permission denied")
            }
            if let error = error {
                print("[AppDelegate] 🔴 Notification permission error: \(error.localizedDescription)")
            }
        }
        application.registerForRemoteNotifications()
        print("[AppDelegate] 🔵 Registered for remote notifications with swizzling enabled")

        print("[AppDelegate] 🔴 didFinishLaunchingWithOptions END")
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("[AppDelegate] 🟢 Got APNs device token!")

#if canImport(FirebaseMessaging)
        // Set APNs token for FCM (for push messaging)
        Messaging.messaging().apnsToken = deviceToken
        print("[AppDelegate] ✅ APNs token set for FCM")
#endif

#if canImport(FirebaseAuth)
        // Check notification permission status
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("[AppDelegate] 🔵 Notification authorization status: \(settings.authorizationStatus.rawValue)")

            if settings.authorizationStatus == .authorized {
                // Permission granted - use Silent Push
                #if DEBUG
                Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
                print("[AppDelegate] 🟢 Notifications authorized - Silent Push enabled (sandbox)")
                #else
                Auth.auth().setAPNSToken(deviceToken, type: .prod)
                print("[AppDelegate] 🟢 Notifications authorized - Silent Push enabled (prod)")
                #endif
            } else {
                // Permission denied or not determined - force SMS mode
                print("[AppDelegate] 🟡 Notifications NOT authorized - Firebase Auth will use SMS mode")
                print("[AppDelegate] 🟡 Status: \(settings.authorizationStatus == .denied ? "denied" : "not determined")")
                // Don't set APNs token for Auth - this forces Firebase to use SMS
            }
        }
#endif

        print("[AppDelegate] ✅ APNs token configured based on notification permission")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[AppDelegate] 🔴 Failed to register for remote notifications: \(error.localizedDescription)")
        print("[AppDelegate] 🟡 Phone auth will use reCAPTCHA verification")
        // SKIP setting dummy APNs token - it crashes Firebase Auth
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("[AppDelegate] 🔵 didReceiveRemoteNotification with fetchCompletionHandler called")
        print("[AppDelegate] 🔵 FULL Notification payload: \(userInfo)")

        // Log every key-value pair
        for (key, value) in userInfo {
            print("[AppDelegate] 🔵   Key: \(key) = Value: \(value)")
        }

        // NOTE: With swizzling enabled, Firebase Auth automatically intercepts its notifications
        // This method is for non-Firebase notifications (FCM messages, etc.)
        print("[AppDelegate] 🔵 Notification received - Firebase handles auth via swizzling")

        completionHandler(.noData)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        print("[AppDelegate] 🔵 didReceiveRemoteNotification (no completion) called")
        print("[AppDelegate] 🔵 Notification data: \(userInfo)")
        // NOTE: With swizzling enabled, Firebase Auth handles its own notifications
        print("[AppDelegate] 🔵 Notification received - Firebase handles auth via swizzling")
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
#if canImport(FirebaseAuth)
        if Auth.auth().canHandle(url) {
            return true
        }
#endif
        return false
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("[AppDelegate] 🔵 userNotificationCenter willPresent called")
        print("[AppDelegate] 🔵 Notification: \(notification.request.content.userInfo)")
        // NOTE: With swizzling enabled, Firebase Auth handles its own notifications
        // This is for app notifications (chat messages, event updates, etc.)
        print("[AppDelegate] 🔵 Displaying notification - Firebase handles auth via swizzling")
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        print("[AppDelegate] 🔵 userNotificationCenter didReceive response called")
        print("[AppDelegate] 🔵 Response: \(response.notification.request.content.userInfo)")
        // NOTE: With swizzling enabled, Firebase Auth handles its own notifications
        // This is for handling user taps on app notifications
        print("[AppDelegate] 🔵 User tapped notification - Firebase handles auth via swizzling")
        completionHandler()
    }

    // MARK: MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("[AppDelegate] 🟢 FCM registration token: \(fcmToken ?? "nil")")

        guard let fcmToken = fcmToken else {
            print("[AppDelegate] ❌ No FCM token received")
            return
        }

#if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        // Store token in Firestore for the current user
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[AppDelegate] 🟡 No user logged in, token will be saved on next login")
            return
        }

        let db = Firestore.firestore()
        db.collection("users").document(uid).setData([
            "pushTokens": FieldValue.arrayUnion([fcmToken])
        ], merge: true) { error in
            if let error = error {
                print("[AppDelegate] ❌ Error saving FCM token: \(error.localizedDescription)")
            } else {
                print("[AppDelegate] ✅ FCM token saved to Firestore for user: \(uid)")
            }
        }
#endif
    }
}
