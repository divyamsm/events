import Foundation
import SwiftUI

final class AppState: ObservableObject {
    enum AppTheme: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    @Published var isOnboarded: Bool {
        didSet {
            UserDefaults.standard.set(isOnboarded, forKey: "hasCompletedOnboarding")
        }
    }

    @Published var attendingEventIDs: Set<UUID> = []
    @Published var createdEvents: [Event] = []
    @Published var selectedTheme: AppTheme = .system

    init() {
        // Load the persisted onboarding state
        self.isOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }
    
    func clearUserData() {
        print("[AppState] 🧹 Clearing user-specific data")
        attendingEventIDs.removeAll()
        createdEvents.removeAll()
    }
}
