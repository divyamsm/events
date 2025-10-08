import SwiftUI

@main
struct SimpleEventsAppApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.isOnboarded {
                ContentView(appState: appState)
                    .environmentObject(appState)
            } else {
                OnboardingFlowView()
                    .environmentObject(appState)
            }
        }
    }
}
