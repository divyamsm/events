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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
#if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
#endif

        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
            if granted == false {
                print("Notification authorization not granted; Firebase phone auth will use reCAPTCHA fallback.")
            }
        }

        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
        }

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
#if canImport(FirebaseAuth)
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        #endif
#endif

#if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
#endif
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
#if canImport(FirebaseAuth)
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
#endif

        completionHandler(.noData)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
#if canImport(FirebaseAuth)
        if Auth.auth().canHandleNotification(userInfo) {
            return
        }
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
#if canImport(FirebaseAuth)
        if Auth.auth().canHandleNotification(notification.request.content.userInfo) {
            completionHandler([])
            return
        }
#endif
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
#if canImport(FirebaseAuth)
        if Auth.auth().canHandleNotification(response.notification.request.content.userInfo) {
            completionHandler()
            return
        }
#endif
        completionHandler()
    }
}
