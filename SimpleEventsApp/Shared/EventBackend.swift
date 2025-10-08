import Foundation
import CoreLocation

struct EventFeedSnapshot {
    var events: [Event]
    var friends: [Friend]
}

protocol EventBackend {
    func fetchFeed(for user: Friend, near location: CLLocation) async throws -> EventFeedSnapshot
    func sendInvite(for eventID: UUID, from sender: Friend, to recipients: [Friend]) async throws
}

enum EventBackendError: Error {
    case eventNotFound
}

final class MockEventBackend: EventBackend {
    private var events: [UUID: Event]
    private var friends: [UUID: Friend]
    private var inviteLedger: [UUID: [UUID: Set<UUID>]] // recipient -> eventID -> senders
    private let queue = DispatchQueue(label: "MockEventBackend")

    init(
        seedEvents: [Event] = EventRepository.sampleEvents,
        seedFriends: [Friend] = EventRepository.friends,
        currentUser: Friend = EventRepository.currentUser
    ) {
        var combinedFriends = seedFriends
        if combinedFriends.contains(where: { $0.id == currentUser.id }) == false {
            combinedFriends.append(currentUser)
        }

        self.events = Dictionary(uniqueKeysWithValues: seedEvents.map { ($0.id, $0) })
        self.friends = Dictionary(uniqueKeysWithValues: combinedFriends.map { ($0.id, $0) })
        self.inviteLedger = [:]

        seedEvents.forEach { event in
            if event.invitedByFriendIDs.isEmpty == false {
                var senders = inviteLedger[currentUser.id, default: [:]][event.id, default: Set<UUID>()]
                event.invitedByFriendIDs.forEach { senders.insert($0) }
                var eventsForRecipient = inviteLedger[currentUser.id, default: [:]]
                eventsForRecipient[event.id] = senders
                inviteLedger[currentUser.id] = eventsForRecipient
            }
        }
    }

    func fetchFeed(for user: Friend, near location: CLLocation) async throws -> EventFeedSnapshot {
        try await Task.sleep(nanoseconds: 120_000_000)

        return queue.sync {
            let baseEvents = events.values.map { event -> Event in
                var mutable = event
                if let incoming = inviteLedger[user.id]?[event.id] {
                    let incomingIDs = Array(incoming)
                    mutable.invitedByFriendIDs = Array(Set(mutable.invitedByFriendIDs + incomingIDs))
                }
                return mutable
            }
            let friendList = Array(friends.values.filter { $0.id != user.id })
            return EventFeedSnapshot(events: baseEvents, friends: friendList)
        }
    }

    func sendInvite(for eventID: UUID, from sender: Friend, to recipients: [Friend]) async throws {
        try await Task.sleep(nanoseconds: 80_000_000)

        try queue.sync {
            guard var event = events[eventID] else {
                throw EventBackendError.eventNotFound
            }

            var updatedShared = Set(event.sharedInviteFriendIDs)
            recipients.forEach { friend in
                updatedShared.insert(friend.id)
                var eventsForRecipient = inviteLedger[friend.id, default: [:]]
                var senders = eventsForRecipient[eventID, default: Set<UUID>()]
                senders.insert(sender.id)
                eventsForRecipient[eventID] = senders
                inviteLedger[friend.id] = eventsForRecipient
            }

            event.sharedInviteFriendIDs = Array(updatedShared)
            events[eventID] = event
        }
    }
}
