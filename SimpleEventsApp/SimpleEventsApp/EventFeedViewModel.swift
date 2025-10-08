import Foundation
import CoreLocation

@MainActor
final class EventFeedViewModel: ObservableObject {
    struct FeedEvent: Identifiable, Hashable {
        enum BadgeRole {
            case me
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
        let isAttending: Bool
        let attendingCount: Int

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
    private let appState: AppState
    private var friendsCatalog: [Friend] = []
    private var latestEvents: [Event] = []

    init(backend: EventBackend, session: UserSession, appState: AppState) {
        self.backend = backend
        self.session = session
        self.appState = appState
    }

    func loadFeed() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await backend.fetchFeed(for: session.user, near: session.currentLocation)
            friendsCatalog = snapshot.friends

            latestEvents = snapshot.events.map { event in
                var mutable = event
                if appState.attendingEventIDs.contains(event.id),
                   mutable.attendingFriendIDs.contains(session.user.id) == false {
                    mutable.attendingFriendIDs.append(session.user.id)
                } else if appState.attendingEventIDs.contains(event.id) == false {
                    mutable.attendingFriendIDs.removeAll(where: { $0 == session.user.id })
                }
                return mutable
            }

            feedEvents = buildFeedEvents(from: latestEvents, friends: snapshot.friends)
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

    func toggleAttendance(for feedEvent: FeedEvent) {
        let eventID = feedEvent.event.id
        let isCurrentlyGoing = appState.attendingEventIDs.contains(eventID)

        if isCurrentlyGoing {
            appState.attendingEventIDs.remove(eventID)
        } else {
            appState.attendingEventIDs.insert(eventID)
        }

        if let index = latestEvents.firstIndex(where: { $0.id == eventID }) {
            var event = latestEvents[index]
            if isCurrentlyGoing {
                event.attendingFriendIDs.removeAll(where: { $0 == session.user.id })
            } else if event.attendingFriendIDs.contains(session.user.id) == false {
                event.attendingFriendIDs.append(session.user.id)
            }
            latestEvents[index] = event
        }

        feedEvents = buildFeedEvents(from: latestEvents, friends: friendsCatalog)
    }

    private func buildFeedEvents(from events: [Event], friends: [Friend]) -> [FeedEvent] {
        let enriched = events.map { event -> FeedEvent in
            let attending = friends.filter { event.attendingFriendIDs.contains($0.id) }
            let invitedMe = friends.filter { event.invitedByFriendIDs.contains($0.id) }
            let invitedByMe = friends.filter { event.sharedInviteFriendIDs.contains($0.id) }

            var badges: [FeedEvent.FriendBadge] =
                invitedMe.map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .invitedMe) } +
                attending.filter { friend in invitedMe.contains(where: { $0.id == friend.id }) == false }
                    .map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .going) } +
                invitedByMe.filter { friend in invitedMe.contains(where: { $0.id == friend.id }) == false }
                    .map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .invitedByMe) }

            let isAttending = appState.attendingEventIDs.contains(event.id)
            if isAttending {
                let meBadge = FeedEvent.FriendBadge(id: session.user.id, friend: session.user, role: .me)
                badges.insert(meBadge, at: 0)
            }

            let distance = event.distance(from: session.currentLocation)
            let attendingCount = attending.count + (isAttending ? 1 : 0)

            return FeedEvent(
                event: event,
                badges: badges,
                distance: distance,
                isAttending: isAttending,
                attendingCount: attendingCount
            )
        }

        return enriched.sorted { lhs, rhs in
            if lhs.isInvite != rhs.isInvite {
                return lhs.isInvite
            }

            let lhsDistance = lhs.distance ?? .greatestFiniteMagnitude
            let rhsDistance = rhs.distance ?? .greatestFiniteMagnitude
            return lhsDistance < rhsDistance
        }
    }
}
