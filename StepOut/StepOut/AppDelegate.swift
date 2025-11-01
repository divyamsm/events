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
        if FirebaseApp.app() == nil {
            print("[AppDelegate] 🔴 Configuring Firebase...")
            FirebaseApp.configure()
            print("[AppDelegate] 🟢 Firebase configured")
        }
#endif

#if canImport(FirebaseMessaging)
        // Set FCM messaging delegate
        Messaging.messaging().delegate = self
        print("[AppDelegate] 🟢 FCM messaging delegate set")
#endif

        // Request notification permissions and register for APNs
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("[AppDelegate] Notification authorization error: \(error.localizedDescription)")
            }
            if granted {
                print("[AppDelegate] ✅ Notification authorization granted")
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                print("[AppDelegate] ❌ Notification authorization denied - using test phone numbers")
            }
        }

        print("[AppDelegate] 🔴 didFinishLaunchingWithOptions END")
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("[AppDelegate] 🟢 Got APNs device token!")

#if canImport(FirebaseMessaging)
        // Set APNs token for FCM
        Messaging.messaging().apnsToken = deviceToken
        print("[AppDelegate] ✅ APNs token set for FCM")
#endif
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
        print("[AppDelegate] 🔵 Notification data: \(userInfo)")
#if canImport(FirebaseAuth)
        if Auth.auth().canHandleNotification(userInfo) {
            print("[AppDelegate] 🟢 Firebase Auth handled the notification!")
            completionHandler(.noData)
            return
        }
        print("[AppDelegate] 🟡 Firebase Auth did NOT handle this notification")
#endif

        completionHandler(.noData)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        print("[AppDelegate] 🔵 didReceiveRemoteNotification (no completion) called")
        print("[AppDelegate] 🔵 Notification data: \(userInfo)")
#if canImport(FirebaseAuth)
        if Auth.auth().canHandleNotification(userInfo) {
            print("[AppDelegate] 🟢 Firebase Auth handled the notification!")
            return
        }
        print("[AppDelegate] 🟡 Firebase Auth did NOT handle this notification")
#endif
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
#if canImport(FirebaseAuth)
        if Auth.auth().canHandleNotification(notification.request.content.userInfo) {
            print("[AppDelegate] 🟢 Firebase Auth handled the notification!")
            completionHandler([])
            return
        }
        print("[AppDelegate] 🟡 Firebase Auth did NOT handle this notification")
#endif
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        print("[AppDelegate] 🔵 userNotificationCenter didReceive response called")
        print("[AppDelegate] 🔵 Response: \(response.notification.request.content.userInfo)")
#if canImport(FirebaseAuth)
        if Auth.auth().canHandleNotification(response.notification.request.content.userInfo) {
            print("[AppDelegate] 🟢 Firebase Auth handled the notification!")
            completionHandler()
            return
        }
        print("[AppDelegate] 🟡 Firebase Auth did NOT handle this notification")
#endif
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
