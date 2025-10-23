import Foundation
import CoreLocation
import SwiftUI
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

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
    @Published var toastEntry: ToastEntry?
    @Published private(set) var pastFeedEvents: [FeedEvent] = []
    @Published var showAllPastEvents: Bool = false

    var visiblePastFeedEvents: [FeedEvent] {
        showAllPastEvents ? pastFeedEvents : Array(pastFeedEvents.prefix(5))
    }

    private let backend: EventBackend
    private var session: UserSession
    private let appState: AppState
    private var friendsCatalog: [Friend] = EventRepository.friends
    private var latestEvents: [Event] = []
    private var authObserver: NSObjectProtocol?

    var friendOptions: [Friend] {
        friendsCatalog.isEmpty ? EventRepository.friends : friendsCatalog
    }

    init(backend: EventBackend, session: UserSession, appState: AppState) {
        self.backend = backend
        self.session = session
        self.appState = appState

#if canImport(FirebaseAuth)
        authObserver = NotificationCenter.default.addObserver(forName: .firebaseAuthDidSignIn, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { await self.loadFeed() }
        }
#endif
    }

    deinit {
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
    }

    func updateSession(_ newSession: UserSession) {
        self.session = newSession
        Task {
            await loadFeed()
        }
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

            refreshFeeds()
            persistWidgetSnapshot()
            presentError = nil
        } catch {
            print("[Feed] fetch failed: \(error.localizedDescription)")
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
            // Always call backend to persist shares to Firebase
            try await backend.sendInvite(for: feedEvent.event.id, from: session.user, to: recipients)

            // Update local state for immediate UI feedback
            let ids = recipients.map { $0.id }
            if let createdIndex = appState.createdEvents.firstIndex(where: { $0.id == feedEvent.event.id }) {
                var event = appState.createdEvents[createdIndex]
                event.sharedInviteFriendIDs = Array(Set(event.sharedInviteFriendIDs + ids))
                appState.createdEvents[createdIndex] = event
            }

            if let latestIndex = latestEvents.firstIndex(where: { $0.id == feedEvent.event.id }) {
                latestEvents[latestIndex].sharedInviteFriendIDs = Array(Set(latestEvents[latestIndex].sharedInviteFriendIDs + ids))
            }

            refreshFeeds()
            persistWidgetSnapshot()
            shareConfirmation = "Sent to \(recipients.count) friend\(recipients.count == 1 ? "" : "s")"
            shareContext = nil
        } catch {
            presentError = "Couldn't send invites. Please try again."
        }
    }

    func updateAttendance(for feedEvent: FeedEvent, going: Bool, arrivalTime: Date?) {
        let previousAttending = appState.attendingEventIDs
        let previousCreatedEvents = appState.createdEvents
        let previousLatestEvents = latestEvents
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

        refreshFeeds()
        persistWidgetSnapshot()

        if let remoteBackend = backend as? FirebaseEventBackend {
            Task { @MainActor in
                do {
                    let backendIdentifier = feedEvent.event.backendIdentifier
                    print("[Feed] rsvp payload=", [
                        "eventId", backendIdentifier ?? eventID.uuidString,
                        "userId", session.user.id,
                        "status", going ? "going" : "declined",
                        "arrival", arrivalTime as Any
                    ])
                    try await remoteBackend.rsvp(
                        eventID: eventID,
                        backendIdentifier: backendIdentifier,
                        userId: session.user.id,
                        status: going ? "going" : "declined",
                        arrival: arrivalTime
                    )
                    await loadFeed()
                } catch {
                    print("[Feed] rsvp failed: \(error.localizedDescription)")
                    appState.attendingEventIDs = previousAttending
                    appState.createdEvents = previousCreatedEvents
                    latestEvents = previousLatestEvents
                    refreshFeeds()
                    presentError = "Couldn't update your RSVP. Please try again."
                }
            }
        }
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

        if let remoteBackend = backend as? FirebaseEventBackend {
            Task { @MainActor in
                do {
                    print("[Feed] createEvent payload=", [
                        "ownerId", session.user.id,
                        "title", trimmedTitle,
                        "startAt", date,
                        "location", trimmedLocation,
                        "privacy", privacy.rawValue
                    ])
                    _ = try await remoteBackend.createEvent(
                        owner: session.user,
                        title: trimmedTitle,
                        description: nil,
                        startAt: date,
                        duration: 60 * 60 * 2,
                        location: trimmedLocation,
                        coordinate: coordinate,
                        privacy: privacy
                    )
                    await loadFeed()
                    self.showCreationToast()
                } catch {
                    print("[Feed] createEvent failed: \(error.localizedDescription)")
                    presentError = "Couldn't create your event. Please try again."
                }
            }
            return
        }

        let event = Event(
            title: trimmedTitle,
            date: date,
            location: trimmedLocation,
            imageURL: imageURL,
            coordinate: coordinate,
            ownerId: session.user.id,
            attendingFriendIDs: [session.user.id],
            sharedInviteFriendIDs: invitedFriendIDs,
            privacy: privacy,
            localImageData: localImageData,
            arrivalTimes: [session.user.id: date]
        )

        appState.createdEvents.insert(event, at: 0)
        appState.attendingEventIDs.insert(event.id)
        latestEvents.insert(event, at: 0)
        refreshFeeds()
        persistWidgetSnapshot()
        showCreationToast()
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

        let createdIndex = appState.createdEvents.firstIndex(where: { $0.id == id })
        let latestIndex = latestEvents.firstIndex(where: { $0.id == id })
        guard createdIndex != nil || latestIndex != nil else {
            print("[Feed] updateEvent skipped — event not found in local caches")
            return
        }

        let previousCreatedEvents = appState.createdEvents
        let previousLatestEvents = latestEvents

        if let createdIndex {
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

        if let latestIndex {
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

        refreshFeeds()
        persistWidgetSnapshot()

        if let remoteBackend = backend as? FirebaseEventBackend {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await remoteBackend.updateEvent(
                        eventID: id,
                        title: trimmedTitle,
                        location: trimmedLocation,
                        startAt: date,
                        endAt: date.addingTimeInterval(60 * 60 * 2),
                        coordinate: coordinate,
                        privacy: privacy,
                        sharedInviteFriendIDs: invitedFriendIDs
                    )
                    await self.loadFeed()
                    self.showToast(message: "Event updated", systemImage: "pencil.circle.fill")
                } catch {
                    print("[Feed] updateEvent failed: \(error.localizedDescription)")
                    self.appState.createdEvents = previousCreatedEvents
                    self.latestEvents = previousLatestEvents
                    self.refreshFeeds()
                    self.persistWidgetSnapshot()
                    self.presentError = "Couldn't update the event. Please try again."
                }
            }
        } else {
            showToast(message: "Event updated", systemImage: "pencil.circle.fill")
        }
    }

    func deleteEvent(_ feedEvent: FeedEvent) {
        let eventID = feedEvent.event.id

        let isCreatedLocally = appState.createdEvents.contains(where: { $0.id == eventID })
        let existsInFeed = latestEvents.contains(where: { $0.id == eventID })
        guard isCreatedLocally || existsInFeed else {
            print("[Feed] deleteEvent skipped — event not found in local caches")
            return
        }

        let previousCreatedEvents = appState.createdEvents
        let previousAttending = appState.attendingEventIDs
        let previousLatestEvents = latestEvents

        if isCreatedLocally {
            appState.createdEvents.removeAll { $0.id == eventID }
        }
        appState.attendingEventIDs.remove(eventID)
        latestEvents.removeAll { $0.id == eventID }
        refreshFeeds()
        persistWidgetSnapshot()

        if let remoteBackend = backend as? FirebaseEventBackend {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await remoteBackend.deleteEvent(eventID: eventID, hardDelete: false)
                    await self.loadFeed()
                    self.showToast(message: "Event deleted", systemImage: "trash.circle.fill")
                } catch {
                    print("[Feed] deleteEvent failed: \(error.localizedDescription)")
                    self.appState.createdEvents = previousCreatedEvents
                    self.appState.attendingEventIDs = previousAttending
                    self.latestEvents = previousLatestEvents
                    self.refreshFeeds()
                    self.persistWidgetSnapshot()
                    self.presentError = "Couldn't delete the event. Please try again."
                }
            }
        } else {
            showToast(message: "Event deleted", systemImage: "trash.circle.fill")
        }
    }

    private func buildFeedEvents(from events: [Event], friends: [Friend], ascending: Bool) -> [FeedEvent] {
        let createdIDs = Set(appState.createdEvents.map { $0.id })
        let friendLookup = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0) })

        let visibleEvents = events.filter { event in
            event.privacy == .public || createdIDs.contains(event.id) || event.sharedInviteFriendIDs.contains(session.user.id)
        }

        let enriched = visibleEvents.map { event -> FeedEvent in
            let attendingIDs = Array(Set(event.attendingFriendIDs))
            let invitedMeIDs = Array(Set(event.invitedByFriendIDs))
            let invitedByMeIDs = Array(Set(event.sharedInviteFriendIDs))

            let attending = attendingIDs.map { resolveFriend(for: $0, in: event, lookup: friendLookup) }
            let invitedMe = invitedMeIDs.map { resolveFriend(for: $0, in: event, lookup: friendLookup) }
            let invitedByMe = invitedByMeIDs.map { resolveFriend(for: $0, in: event, lookup: friendLookup) }

            var badges: [FeedEvent.FriendBadge] =
                invitedMe.map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .invitedMe) } +
                attending.filter { friend in invitedMe.contains(where: { $0.id == friend.id }) == false }
                    .map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .going) } +
                invitedByMe.filter { friend in invitedMe.contains(where: { $0.id == friend.id }) == false }
                    .map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .invitedByMe) }

            if let ownerId = event.ownerId {
                let host = resolveFriend(for: ownerId, in: event, lookup: friendLookup)
                if badges.contains(where: { $0.friend.id == host.id }) == false {
                    badges.insert(FeedEvent.FriendBadge(id: host.id, friend: host, role: .invitedByMe), at: 0)
                }
            }

            let isAttending = appState.attendingEventIDs.contains(event.id)
            if isAttending {
                let meBadge = FeedEvent.FriendBadge(id: session.user.id, friend: session.user, role: .me)
                if badges.contains(where: { $0.friend.id == meBadge.friend.id }) == false {
                    badges.insert(meBadge, at: 0)
                }
            }

            let distance = event.distance(from: session.currentLocation)
            let attendingCount = max(attendingIDs.count, badges.filter { $0.role == .going || $0.role == .me }.count)

            return FeedEvent(
                event: event,
                badges: badges,
                distance: distance,
                isAttending: isAttending,
                attendingCount: attendingCount,
                isEditable: (event.ownerId == session.user.id) || createdIDs.contains(event.id),
                myArrivalTime: event.arrivalTimes[session.user.id]
            )
        }

        return enriched.sorted { lhs, rhs in
            if lhs.event.date != rhs.event.date {
                return ascending ? lhs.event.date < rhs.event.date : lhs.event.date > rhs.event.date
            }

            let lhsDistance = lhs.distance ?? .greatestFiniteMagnitude
            let rhsDistance = rhs.distance ?? .greatestFiniteMagnitude
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

            return lhs.event.id.uuidString < rhs.event.id.uuidString
        }
    }

    private func showCreationToast() {
        showToast(message: "Event created!", systemImage: "sparkles")
    }

    private func refreshFeeds() {
        let now = Date()
        let upcomingEvents = latestEvents.filter { $0.date >= now }
        let pastEvents = latestEvents.filter { $0.date < now }

        feedEvents = buildFeedEvents(from: upcomingEvents, friends: friendsCatalog, ascending: true)
        pastFeedEvents = buildFeedEvents(from: pastEvents, friends: friendsCatalog, ascending: false)
        if pastFeedEvents.count <= 5 {
            showAllPastEvents = true
        } else if pastFeedEvents.count > 5 {
            // keep user's toggle state
        }
    }

    private func resolveFriend(for id: UUID, in event: Event, lookup: [UUID: Friend]) -> Friend {
        if let friend = lookup[id] {
            return friend
        }
        if id == session.user.id {
            return session.user
        }
        if let ownerId = event.ownerId, ownerId == id {
            return Friend(id: id, name: "Host", avatarURL: nil)
        }
        let suffix = id.uuidString.prefix(4)
        return Friend(id: id, name: "Guest \(suffix)", avatarURL: nil)
    }

    private func showToast(message: String, systemImage: String = "checkmark.circle.fill") {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            toastEntry = ToastEntry(message: message, systemImage: systemImage)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.toastEntry = nil
            }
        }
    }

    private func persistWidgetSnapshot() {
        let events = latestEvents
        let friends = friendsCatalog
        let user = session.user

        Task.detached(priority: .background) {
            await WidgetTimelineBridge.save(events: events, friends: friends, currentUser: user)
            #if canImport(WidgetKit)
            await MainActor.run {
                WidgetTimelineBridge.reloadWidgetTimelines()
            }
            #endif
        }
    }

}
    struct ToastEntry: Identifiable {
        let id = UUID()
        let message: String
        let systemImage: String
    }
