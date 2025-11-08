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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    private static let logger = Logger(subsystem: "com.stepout2.app", category: "startup")

    init() {
        print("[StepOutApp] 🔴 init() START")
        Self.configureFirebaseIfNeeded()
        print("[StepOutApp] 🔴 After configureFirebaseIfNeeded")
        // SKIP setting APNs token - it's causing crashes
        // Self.setInitialAPNsToken()
        print("[StepOutApp] 🔴 Skipping APNs token for now")
        _appState = StateObject(wrappedValue: Self.makeInitialAppState())
        print("[StepOutApp] 🔴 init() END")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isOnboarded {
                    ContentView(appState: appState)
                        .environmentObject(appState)
                        .onAppear {
                            print("[StepOutApp] 🟢 ContentView appeared!")
                        }
                } else {
                    OnboardingFlowView()
                        .environmentObject(appState)
                        .onAppear {
                            print("[StepOutApp] 🟢 OnboardingFlowView appeared!")
                        }
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

        // Configure Firebase with custom options to ensure Auth is properly initialized
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            logger.fault("Failed to load FirebaseOptions from GoogleService-Info.plist")
            FirebaseApp.configure()
            return
        }

        FirebaseApp.configure(options: options)
        logger.info("Firebase configured successfully with explicit options.")
#endif
    }

    private static func setInitialAPNsToken() {
#if canImport(FirebaseAuth)
        #if canImport(FirebaseCore)
        // Verify Firebase is configured before accessing Auth
        guard FirebaseApp.app() != nil else {
            logger.error("Cannot set APNs token - Firebase not configured")
            return
        }
        #endif

        logger.info("About to set dummy APNs token...")
        // CRITICAL: Set dummy APNs token immediately after Firebase configuration
        // This prevents crashes when Auth.auth() is accessed before APNs registration completes
        let dummyToken = Data(count: 32)
        #if DEBUG
        Auth.auth().setAPNSToken(dummyToken, type: .sandbox)
        logger.info("✅ Set initial dummy APNs token (sandbox)")
        #else
        Auth.auth().setAPNSToken(dummyToken, type: .prod)
        logger.info("✅ Set initial dummy APNs token (prod)")
        #endif
#endif
    }

    private static func makeInitialAppState() -> AppState {
        print("[StepOutApp] 🔴 makeInitialAppState START")
        let state = AppState()
        print("[StepOutApp] 🔴 Created AppState")
#if canImport(FirebaseAuth)
        // SKIP checking currentUser - also causes crashes
        // if FirebaseApp.app() != nil, Auth.auth().currentUser != nil {
        //     state.isOnboarded = true
        // }
        print("[StepOutApp] 🔴 Skipping Auth.auth().currentUser check")
#endif
        print("[StepOutApp] 🔴 makeInitialAppState END - returning state")
        return state
    }
}
