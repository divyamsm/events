import SwiftUI
import OSLog
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

@main
struct StepOutApp: App {
    @StateObject private var appState: AppState
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private static let logger = Logger(subsystem: "com.stepout2.app", category: "startup")

    init() {
        Self.configureFirebaseIfNeeded()
        _appState = StateObject(wrappedValue: Self.makeInitialAppState())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isOnboarded {
                    ContentView(appState: appState)
                        .environmentObject(appState)
                } else {
                    OnboardingFlowView()
                        .environmentObject(appState)
                }
            }
            .preferredColorScheme(appState.selectedTheme.colorScheme)
        }
    }

    private static func configureFirebaseIfNeeded() {
#if canImport(FirebaseCore)
        guard FirebaseApp.app() == nil else {
            logger.debug("Firebase already configured.")
            return
        }

        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") == nil {
#if DEBUG
            assertionFailure("Missing GoogleService-Info.plist in the StepOut target. Firebase will remain unconfigured.")
#endif
            logger.fault("GoogleService-Info.plist missing from main bundle; attempting FirebaseApp.configure() anyway.")
        }

        FirebaseApp.configure()
        logger.info("Firebase configured successfully.")
#endif
    }

    private static func makeInitialAppState() -> AppState {
        let state = AppState()
#if canImport(FirebaseAuth)
        if FirebaseApp.app() != nil, Auth.auth().currentUser != nil {
            state.isOnboarded = true
        }
#endif
        return state
    }
}
