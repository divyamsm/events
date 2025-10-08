import Foundation

final class AppState: ObservableObject {
    @Published var isOnboarded: Bool = false
    @Published var attendingEventIDs: Set<UUID> = []
}
