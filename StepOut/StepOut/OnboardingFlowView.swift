import SwiftUI
import FirebaseAuth

struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ModernOnboardingFlow { user in
            // User successfully signed up or logged in
            print("[OnboardingFlow] ✅ User authenticated: \(user.uid)")
            appState.isOnboarded = true
        }
    }
}
