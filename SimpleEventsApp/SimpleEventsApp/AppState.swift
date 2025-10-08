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

    @Published var isOnboarded: Bool = false
    @Published var attendingEventIDs: Set<UUID> = []
    @Published var createdEvents: [Event] = []
    @Published var selectedTheme: AppTheme = .system
}
