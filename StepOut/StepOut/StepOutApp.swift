import SwiftUI

@main
struct StepOutApp: App {
    @StateObject private var appState = AppState()

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
}
