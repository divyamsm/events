import Foundation
import CoreLocation

@MainActor
final class EventFeedViewModel: ObservableObject {
    struct FeedEvent: Identifiable, Hashable {
        enum BadgeRole {
            case invitedMe
            case going
            case invitedByMe
        }

        struct FriendBadge: Identifiable, Hashable {
            let id: UUID
            let friend: Friend
            let role: BadgeRole
        }

        let event: Event
        let badges: [FriendBadge]
        let distance: CLLocationDistance?

        var id: UUID { event.id }
        var isInvite: Bool {
            badges.contains(where: { $0.role == .invitedMe })
        }
    }

    struct ShareContext: Identifiable {
        let id = UUID()
        let feedEvent: FeedEvent
        let availableFriends: [Friend]
    }

    @Published private(set) var feedEvents: [FeedEvent] = []
    @Published private(set) var isLoading = false
    @Published var shareContext: ShareContext?
    @Published var presentError: String?
    @Published var shareConfirmation: String?

    private let backend: EventBackend
    private let session: UserSession
    private var friendsCatalog: [Friend] = []

    init(backend: EventBackend, session: UserSession) {
        self.backend = backend
        self.session = session
    }

    func loadFeed() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await backend.fetchFeed(for: session.user, near: session.currentLocation)
            friendsCatalog = snapshot.friends

            let enriched = snapshot.events.map { event -> FeedEvent in
                let attending = snapshot.friends.filter { event.attendingFriendIDs.contains($0.id) }
                let invitedMe = snapshot.friends.filter { event.invitedByFriendIDs.contains($0.id) }
                let invitedByMe = snapshot.friends.filter { event.sharedInviteFriendIDs.contains($0.id) }

                let badges: [FeedEvent.FriendBadge] =
                    invitedMe.map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .invitedMe) } +
                    attending.filter { friend in invitedMe.contains(where: { $0.id == friend.id }) == false }
                        .map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .going) } +
                    invitedByMe.filter { friend in invitedMe.contains(where: { $0.id == friend.id }) == false }
                        .map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .invitedByMe) }

                let distance = event.distance(from: session.currentLocation)

                return FeedEvent(event: event, badges: badges, distance: distance)
            }

            feedEvents = enriched.sorted { lhs, rhs in
                if lhs.isInvite != rhs.isInvite {
                    return lhs.isInvite
                }

                let lhsDistance = lhs.distance ?? .greatestFiniteMagnitude
                let rhsDistance = rhs.distance ?? .greatestFiniteMagnitude
                return lhsDistance < rhsDistance
            }
        } catch {
            presentError = "Couldn't refresh events. Please try again."
        }
    }

    func beginShare(for feedEvent: FeedEvent) {
        var available = friendsCatalog.filter { $0.id != session.user.id }
        available.removeAll(where: { feedEvent.event.sharedInviteFriendIDs.contains($0.id) })
        shareContext = ShareContext(feedEvent: feedEvent, availableFriends: available)
    }

    func completeShare(for feedEvent: FeedEvent, to recipients: [Friend]) async {
        guard recipients.isEmpty == false else {
            shareContext = nil
            return
        }

        do {
            try await backend.sendInvite(for: feedEvent.event.id, from: session.user, to: recipients)
            shareConfirmation = "Sent to \(recipients.count) friend\(recipients.count == 1 ? "" : "s")"
            shareContext = nil
            await loadFeed()
        } catch {
            presentError = "Couldn't send invites. Please try again."
        }
    }
}
