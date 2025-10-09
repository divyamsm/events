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
        let isEditable: Bool
        let myArrivalTime: Date?

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
    private var friendsCatalog: [Friend] = EventRepository.friends
    private var latestEvents: [Event] = []

    var friendOptions: [Friend] {
        friendsCatalog.isEmpty ? EventRepository.friends : friendsCatalog
    }

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

            var combinedEvents = appState.createdEvents
            for event in snapshot.events where combinedEvents.contains(where: { $0.id == event.id }) == false {
                combinedEvents.append(event)
            }

            let createdIDs = Set(appState.createdEvents.map { $0.id })

            latestEvents = combinedEvents.map { event in
                var mutable = event
                if appState.attendingEventIDs.contains(event.id),
                   mutable.attendingFriendIDs.contains(session.user.id) == false {
                    mutable.attendingFriendIDs.append(session.user.id)
                } else if appState.attendingEventIDs.contains(event.id) == false {
                    mutable.attendingFriendIDs.removeAll(where: { $0 == session.user.id })
                }
                return mutable
            }

            appState.createdEvents = latestEvents.filter { createdIDs.contains($0.id) }

            feedEvents = buildFeedEvents(from: latestEvents, friends: snapshot.friends)
            persistWidgetSnapshot()
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

        if feedEvent.isEditable {
            let ids = recipients.map { $0.id }
            if let createdIndex = appState.createdEvents.firstIndex(where: { $0.id == feedEvent.event.id }) {
                var event = appState.createdEvents[createdIndex]
                event.sharedInviteFriendIDs = Array(Set(event.sharedInviteFriendIDs + ids))
                appState.createdEvents[createdIndex] = event
            }

            if let latestIndex = latestEvents.firstIndex(where: { $0.id == feedEvent.event.id }) {
                latestEvents[latestIndex].sharedInviteFriendIDs = Array(Set(latestEvents[latestIndex].sharedInviteFriendIDs + ids))
            }

            feedEvents = buildFeedEvents(from: latestEvents, friends: friendsCatalog)
            persistWidgetSnapshot()
            shareConfirmation = "Sent to \(recipients.count) friend\(recipients.count == 1 ? "" : "s")"
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

    func updateAttendance(for feedEvent: FeedEvent, going: Bool, arrivalTime: Date?) {
        let eventID = feedEvent.event.id

        if going {
            appState.attendingEventIDs.insert(eventID)
        } else {
            appState.attendingEventIDs.remove(eventID)
        }

        func applyUpdates(to event: inout Event) {
            if going {
                if event.attendingFriendIDs.contains(session.user.id) == false {
                    event.attendingFriendIDs.append(session.user.id)
                }
                if let arrivalTime {
                    event.arrivalTimes[session.user.id] = arrivalTime
                } else {
                    event.arrivalTimes.removeValue(forKey: session.user.id)
                }
            } else {
                event.attendingFriendIDs.removeAll { $0 == session.user.id }
                event.arrivalTimes.removeValue(forKey: session.user.id)
            }
        }

        if let createdIndex = appState.createdEvents.firstIndex(where: { $0.id == eventID }) {
            applyUpdates(to: &appState.createdEvents[createdIndex])
        }

        if let index = latestEvents.firstIndex(where: { $0.id == eventID }) {
            applyUpdates(to: &latestEvents[index])
        }

        feedEvents = buildFeedEvents(from: latestEvents, friends: friendsCatalog)
        persistWidgetSnapshot()
    }

    func createEvent(
        title: String,
        location: String,
        date: Date,
        coordinate: CLLocationCoordinate2D?,
        imageURL: URL,
        privacy: Event.Privacy,
        invitedFriendIDs: [UUID],
        localImageData: Data?
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)

        var event = Event(
            title: trimmedTitle,
            date: date,
            location: trimmedLocation,
            imageURL: imageURL,
            coordinate: coordinate,
            attendingFriendIDs: [session.user.id],
            sharedInviteFriendIDs: invitedFriendIDs,
            privacy: privacy,
            localImageData: localImageData,
            arrivalTimes: [session.user.id: date]
        )

        appState.createdEvents.insert(event, at: 0)
        appState.attendingEventIDs.insert(event.id)
        latestEvents.insert(event, at: 0)
        feedEvents = buildFeedEvents(from: latestEvents, friends: friendsCatalog)
        persistWidgetSnapshot()
    }

    func updateEvent(
        id: UUID,
        title: String,
        location: String,
        date: Date,
        coordinate: CLLocationCoordinate2D?,
        privacy: Event.Privacy,
        invitedFriendIDs: [UUID],
        localImageData: Data?
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)

        guard appState.createdEvents.contains(where: { $0.id == id }) else { return }

        if let createdIndex = appState.createdEvents.firstIndex(where: { $0.id == id }) {
            appState.createdEvents[createdIndex].title = trimmedTitle
            appState.createdEvents[createdIndex].location = trimmedLocation
            appState.createdEvents[createdIndex].date = date
            appState.createdEvents[createdIndex].coordinate = coordinate
            appState.createdEvents[createdIndex].privacy = privacy
            appState.createdEvents[createdIndex].sharedInviteFriendIDs = invitedFriendIDs
            appState.createdEvents[createdIndex].arrivalTimes[session.user.id] = appState.createdEvents[createdIndex].arrivalTimes[session.user.id] ?? date
            if let localImageData {
                appState.createdEvents[createdIndex].localImageData = localImageData
            }
        }

        if let latestIndex = latestEvents.firstIndex(where: { $0.id == id }) {
            latestEvents[latestIndex].title = trimmedTitle
            latestEvents[latestIndex].location = trimmedLocation
            latestEvents[latestIndex].date = date
            latestEvents[latestIndex].coordinate = coordinate
            latestEvents[latestIndex].privacy = privacy
            latestEvents[latestIndex].sharedInviteFriendIDs = invitedFriendIDs
            latestEvents[latestIndex].arrivalTimes[session.user.id] = latestEvents[latestIndex].arrivalTimes[session.user.id] ?? date
            if let localImageData {
                latestEvents[latestIndex].localImageData = localImageData
            }
        }

        feedEvents = buildFeedEvents(from: latestEvents, friends: friendsCatalog)
        persistWidgetSnapshot()
    }

    func deleteEvent(_ feedEvent: FeedEvent) {
        let eventID = feedEvent.event.id

        guard appState.createdEvents.contains(where: { $0.id == eventID }) else { return }

        appState.createdEvents.removeAll { $0.id == eventID }
        appState.attendingEventIDs.remove(eventID)
        latestEvents.removeAll { $0.id == eventID }
        feedEvents = buildFeedEvents(from: latestEvents, friends: friendsCatalog)
    }

    private func buildFeedEvents(from events: [Event], friends: [Friend]) -> [FeedEvent] {
        let createdIDs = Set(appState.createdEvents.map { $0.id })

        let visibleEvents = events.filter { event in
            event.privacy == .public || createdIDs.contains(event.id) || event.sharedInviteFriendIDs.contains(session.user.id)
        }

        let enriched = visibleEvents.map { event -> FeedEvent in
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
                attendingCount: attendingCount,
                isEditable: createdIDs.contains(event.id),
                myArrivalTime: event.arrivalTimes[session.user.id]
            )
        }

        return enriched.sorted { lhs, rhs in
            let lhsCreated = createdIDs.contains(lhs.event.id)
            let rhsCreated = createdIDs.contains(rhs.event.id)
            if lhsCreated != rhsCreated {
                return lhsCreated
            }
            if lhs.isInvite != rhs.isInvite {
                return lhs.isInvite
            }

            let lhsDistance = lhs.distance ?? .greatestFiniteMagnitude
            let rhsDistance = rhs.distance ?? .greatestFiniteMagnitude
            return lhsDistance < rhsDistance
        }
    }

    private func persistWidgetSnapshot() {
        WidgetTimelineBridge.save(events: latestEvents)
        #if canImport(WidgetKit)
        WidgetTimelineBridge.reloadWidgetTimelines()
        #endif
    }
}
