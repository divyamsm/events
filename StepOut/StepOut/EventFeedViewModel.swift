import Foundation
import CoreLocation
import SwiftUI
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
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
        let badges: [FriendBadge]  // All badges including guests (for detail view)
        let cardBadges: [FriendBadge]  // Only non-guest badges (for card view)
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

    @Published private(set) var allFeedEvents: [FeedEvent] = []
    @Published private(set) var isLoading = false
    @Published var shareContext: ShareContext?
    @Published var presentError: String?
    @Published var shareConfirmation: String?
    @Published var toastEntry: ToastEntry?
    @Published private(set) var pastFeedEvents: [FeedEvent] = []
    @Published var showAllPastEvents: Bool = false
    @Published var searchText: String = "" {
        didSet { applyFilters() }
    }
    @Published var selectedCategories: Set<EventCategory> = [] {
        didSet { applyFilters() }
    }
    @Published var maxDistance: Double? = nil {
        didSet { applyFilters() }
    }
    @Published var showFilters: Bool = false
    @Published private(set) var feedEvents: [FeedEvent] = []
    @Published private(set) var hiddenEventIDs: Set<String> = []
    @Published private(set) var hiddenEventTimestamps: [String: Date] = [:]
    @Published private(set) var blockedUserIDs: Set<String> = []

    var visiblePastFeedEvents: [FeedEvent] {
        showAllPastEvents ? pastFeedEvents : Array(pastFeedEvents.prefix(5))
    }

    private let backend: EventBackend
    private var session: UserSession
    private let appState: AppState
    private var friendsCatalog: [Friend] = []
    private var latestEvents: [Event] = []
    private var authObserver: NSObjectProtocol?
    private var refreshFeedObserver: NSObjectProtocol?

    var friendOptions: [Friend] {
        friendsCatalog
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
        
        // Listen for feed refresh requests (e.g., after unblocking a user)
        refreshFeedObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name("RefreshFeed"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            print("[EventFeedViewModel] 🔄 Received RefreshFeed notification, reloading feed...")
            Task { await self.loadFeed() }
        }
    }

    deinit {
        print("[EventFeedViewModel] 💀 DEINIT called for session: \(session.firebaseUID ?? "nil")")
        print("[EventFeedViewModel] 💀   User name: \(session.user.name)")
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
        if let refreshFeedObserver {
            NotificationCenter.default.removeObserver(refreshFeedObserver)
        }
    }

    func updateSession(_ newSession: UserSession) {
        self.session = newSession

        // Clear cached data from previous user
        hiddenEventIDs.removeAll()
        hiddenEventTimestamps.removeAll()
        blockedUserIDs.removeAll()
        friendsCatalog.removeAll()
        latestEvents.removeAll()
        allFeedEvents.removeAll()
        feedEvents.removeAll()
        pastFeedEvents.removeAll()
        appState.createdEvents.removeAll()
        appState.attendingEventIDs.removeAll()

        Task {
            await loadFeed()
        }
    }

    func loadFeed() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        // Load hidden events and blocked users first
        await loadHiddenEventsAndBlockedUsers()

        do {
            let snapshot = try await backend.fetchFeed(for: session.user, near: session.currentLocation)
            friendsCatalog = snapshot.friends

            // Only log for events we're debugging
            for event in snapshot.events where event.title.contains("Bharath") {
                print("[EventFeedViewModel] 🔍 Event: \(event.title) (ID: \(event.id))")
                print("[EventFeedViewModel] 🔍   attendingFriendIDs: \(event.attendingFriendIDs)")
                print("[EventFeedViewModel] 🔍   sharedInviteFriendIDs: \(event.sharedInviteFriendIDs)")
            }

            // Build a lookup of backend events by ID
            let backendEventLookup = Dictionary(uniqueKeysWithValues: snapshot.events.map { ($0.id, $0) })
            let createdIDs = Set(appState.createdEvents.map { $0.id })

            // Merge: Prefer backend data for existing events, keep local-only events
            var combinedEvents: [Event] = []

            // First, add all backend events (updates existing ones with fresh data)
            for event in snapshot.events {
                combinedEvents.append(event)
            }

            // Then, add local events that don't exist in backend
            for localEvent in appState.createdEvents {
                if backendEventLookup[localEvent.id] == nil {
                    combinedEvents.append(localEvent)
                }
            }

            // Backend is source of truth for attendingFriendIDs - no need to manipulate locally
            latestEvents = combinedEvents

            appState.createdEvents = latestEvents.filter { createdIDs.contains($0.id) }

            refreshFeeds()
            persistWidgetSnapshot()
            presentError = nil
        } catch {
            print("[Feed] ❌ Fetch failed: \(error.localizedDescription)")
            
            // Check if it's a network error
            if let nsError = error as NSError?, nsError.domain == "NSURLErrorDomain" {
                print("[Feed] 🌐 Network error detected, will retry on next refresh")
                presentError = "Network connection issue. Pull to refresh to try again."
            } else if error.localizedDescription.contains("Stream removed") || error.localizedDescription.contains("Connection reset") {
                print("[Feed] 🔄 Firebase stream error (temporary), ignoring")
                // Don't show error for temporary stream issues
            } else {
                presentError = "Couldn't refresh events. Please try again."
            }
        }
    }

    func beginShare(for feedEvent: FeedEvent) {
        print("[EventFeedViewModel] beginShare called. friendsCatalog count: \(friendsCatalog.count), names: \(friendsCatalog.map { $0.name })")
        var available = friendsCatalog.filter { $0.id != session.user.id }
        print("[EventFeedViewModel] After filtering self: \(available.count)")
        available.removeAll(where: { feedEvent.event.sharedInviteFriendIDs.contains($0.id) })
        print("[EventFeedViewModel] After filtering already shared: \(available.count), names: \(available.map { $0.name })")
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
        print("[EventFeedViewModel] 🎯 updateAttendance called")
        print("[EventFeedViewModel] 🎯   Current session user ID: \(session.user.id)")
        print("[EventFeedViewModel] 🎯   Current session firebaseUID: \(session.firebaseUID ?? "nil")")
        print("[EventFeedViewModel] 🎯   Event: \(feedEvent.event.title)")
        print("[EventFeedViewModel] 🎯   Going: \(going)")
        
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
        endDate: Date,
        coordinate: CLLocationCoordinate2D?,
        imageURL: URL,
        privacy: Event.Privacy,
        invitedFriendIDs: [UUID],
        localImageData: Data?,
        categories: [EventCategory] = [.other]
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
                        "endAt", endDate,
                        "location", trimmedLocation,
                        "privacy", privacy.rawValue,
                        "categories", categories
                    ])
                    _ = try await remoteBackend.createEvent(
                        owner: session.user,
                        title: trimmedTitle,
                        description: nil,
                        startAt: date,
                        endAt: endDate,
                        location: trimmedLocation,
                        coordinate: coordinate,
                        privacy: privacy,
                        categories: categories
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
            ownerId: session.firebaseUID,
            attendingFriendIDs: [session.user.id],
            sharedInviteFriendIDs: invitedFriendIDs,
            privacy: privacy,
            localImageData: localImageData,
            arrivalTimes: [session.user.id: date],
            categories: categories
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
        localImageData: Data?,
        categories: [EventCategory]
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
            appState.createdEvents[createdIndex].categories = categories
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
            latestEvents[latestIndex].categories = categories
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
                        sharedInviteFriendIDs: invitedFriendIDs,
                        categories: categories
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

    private func loadHiddenEventsAndBlockedUsers() async {
        #if canImport(FirebaseFirestore)
        guard let firebaseUID = session.firebaseUID else {
            print("[EventFeedViewModel] ⚠️ No Firebase UID available")
            return
        }
        
        print("[EventFeedViewModel] 📂 Loading hidden/blocked for firebaseUID: \(firebaseUID)")

        do {
            let db = Firestore.firestore()
            let now = Date()
            let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)

            // Load hidden events with timestamps
            // Use server source to avoid cached queries from old sessions
            let hiddenSnapshot = try await db.collection("users")
                .document(firebaseUID)
                .collection("hiddenEvents")
                .getDocuments(source: .server)

            var validHiddenEventIDs: Set<String> = []
            var timestamps: [String: Date] = [:]
            var expiredEventIDs: [String] = []

            for doc in hiddenSnapshot.documents {
                let eventId = doc.documentID

                // Get the timestamp
                if let timestamp = doc.data()["hiddenAt"] as? Timestamp {
                    let hiddenDate = timestamp.dateValue()

                    // Check if it's been more than 24 hours
                    if hiddenDate > twentyFourHoursAgo {
                        // Still within 24 hours - keep hidden
                        validHiddenEventIDs.insert(eventId)
                        timestamps[eventId] = hiddenDate
                    } else {
                        // Expired - mark for deletion
                        expiredEventIDs.append(eventId)
                    }
                } else {
                    // No timestamp - keep it hidden (safety fallback)
                    validHiddenEventIDs.insert(eventId)
                }
            }

            hiddenEventIDs = validHiddenEventIDs
            hiddenEventTimestamps = timestamps

            // Clean up expired hidden events from Firebase
            for eventId in expiredEventIDs {
                try? await db.collection("users")
                    .document(firebaseUID)
                    .collection("hiddenEvents")
                    .document(eventId)
                    .delete()
            }

            // Load blocked users
            // Use server source to avoid cached queries from old sessions
            let blockedSnapshot = try await db.collection("users")
                .document(firebaseUID)
                .collection("blocked")
                .getDocuments(source: .server)

            blockedUserIDs = Set(blockedSnapshot.documents.map { $0.documentID })

            print("[EventFeedViewModel] 📛 Loaded \(hiddenEventIDs.count) hidden events (\(expiredEventIDs.count) expired/removed) and \(blockedUserIDs.count) blocked users")
        } catch {
            print("[EventFeedViewModel] ⚠️ Error loading hidden events/blocked users: \(error.localizedDescription)")
        }
        #endif
    }

    private func buildFeedEvents(from events: [Event], friends: [Friend], ascending: Bool) -> [FeedEvent] {
        let createdIDs = Set(appState.createdEvents.map { $0.id })
        let friendLookup = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0) })

        // Filter out hidden events and events from blocked users
        let visibleEvents = events.filter { event in
            // Check if event is hidden
            guard !hiddenEventIDs.contains(event.id.uuidString) else {
                print("[EventFeedViewModel] 📛 Filtering out hidden event: \(event.title)")
                return false
            }

            // Check if event owner is blocked
            if let ownerId = event.ownerId, blockedUserIDs.contains(ownerId) {
                print("[EventFeedViewModel] 🚫 Filtering out event from blocked user: \(event.title)")
                return false
            }

            // Apply privacy filters
            return event.privacy == .public || createdIDs.contains(event.id) || event.sharedInviteFriendIDs.contains(session.user.id)
        }

        let enriched = visibleEvents.map { event -> FeedEvent in
            let attendingIDs = Array(Set(event.attendingFriendIDs))
            let invitedMeIDs = Array(Set(event.invitedByFriendIDs))
            let invitedByMeIDs = Array(Set(event.sharedInviteFriendIDs))

            let attending = attendingIDs.map { resolveFriend(for: $0, in: event, lookup: friendLookup) }
            let invitedMe = invitedMeIDs.map { resolveFriend(for: $0, in: event, lookup: friendLookup) }
            let invitedByMe = invitedByMeIDs.map { resolveFriend(for: $0, in: event, lookup: friendLookup) }

            let invitedMeBadges = invitedMe.map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .invitedMe) }
            let attendingBadges = attending.filter { friend in invitedMe.contains(where: { $0.id == friend.id }) == false }
                .map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .going) }
            let invitedByMeBadges = invitedByMe.filter { friend in invitedMe.contains(where: { $0.id == friend.id }) == false }
                .map { FeedEvent.FriendBadge(id: $0.id, friend: $0, role: .invitedByMe) }

            var badges: [FeedEvent.FriendBadge] = invitedMeBadges + attendingBadges + invitedByMeBadges

            // Only log for events we're debugging
            if event.title.contains("Bharath") {
                print("[EventFeedViewModel] 🔍 Building badges for: \(event.title)")
                print("[EventFeedViewModel] 🔍   invitedByMeIDs: \(invitedByMeIDs)")
                print("[EventFeedViewModel] 🔍   invitedByMe friends: \(invitedByMe.map { $0.name })")
                print("[EventFeedViewModel] 🔍   invitedByMeBadges count: \(invitedByMeBadges.count)")
            }

            // Skip host badge for now since ownerId is Firebase UID (String), not UUID
            // TODO: Resolve Firebase UID to Friend
            // if let ownerId = event.ownerId {
            //     let host = resolveFriend(for: ownerId, in: event, lookup: friendLookup)
            //     if badges.contains(where: { $0.friend.id == host.id }) == false {
            //         badges.insert(FeedEvent.FriendBadge(id: host.id, friend: host, role: .invitedByMe), at: 0)
            //     }
            // }

            // Determine if user is attending from backend data, not local state
            let isAttending = event.attendingFriendIDs.contains(session.user.id)
            if isAttending {
                let meBadge = FeedEvent.FriendBadge(id: session.user.id, friend: session.user, role: .me)
                if badges.contains(where: { $0.friend.id == meBadge.friend.id }) == false {
                    badges.insert(meBadge, at: 0)
                }
            }

            let distance = event.distance(from: session.currentLocation)
            let attendingCount = max(attendingIDs.count, badges.filter { $0.role == .going || $0.role == .me }.count)

            // Only log for events we're debugging
            if event.title.contains("Bharath") {
                print("[EventFeedViewModel] 🔍 FINAL badges count: \(badges.count)")
                print("[EventFeedViewModel] 🔍 FINAL badges: \(badges.map { "\($0.friend.name) (\($0.role))" })")
            }

            // Filter out guests for card display (guests have names like "Guest XXXX")
            let cardBadges = badges.filter { !$0.friend.name.starts(with: "Guest") }
            
            return FeedEvent(
                event: event,
                badges: badges,  // All badges including guests
                cardBadges: cardBadges,  // Only non-guest badges for card
                distance: distance,
                isAttending: isAttending,
                attendingCount: attendingCount,
                isEditable: (event.ownerId == session.firebaseUID) || createdIDs.contains(event.id),
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

        allFeedEvents = buildFeedEvents(from: upcomingEvents, friends: friendsCatalog, ascending: true)
        pastFeedEvents = buildFeedEvents(from: pastEvents, friends: friendsCatalog, ascending: false)
        if pastFeedEvents.count <= 5 {
            showAllPastEvents = true
        } else if pastFeedEvents.count > 5 {
            // keep user's toggle state
        }
        applyFilters()
    }

    private func applyFilters() {
        var filtered = allFeedEvents

        // Text search filter
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let searchLower = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            filtered = filtered.filter { feedEvent in
                feedEvent.event.title.lowercased().contains(searchLower) ||
                feedEvent.event.location.lowercased().contains(searchLower)
            }
        }

        // Category filter
        if !selectedCategories.isEmpty {
            filtered = filtered.filter { feedEvent in
                feedEvent.event.categories.contains(where: { selectedCategories.contains($0) })
            }
        }

        // Distance filter
        if let maxDist = maxDistance {
            filtered = filtered.filter { feedEvent in
                guard let distance = feedEvent.distance else { return false }
                return distance / 1000 <= maxDist // Convert meters to km
            }
        }

        feedEvents = filtered
    }

    private func resolveFriend(for id: UUID, in event: Event, lookup: [UUID: Friend]) -> Friend {
        if let friend = lookup[id] {
            return friend
        }
        if id == session.user.id {
            return session.user
        }
        // ownerId is now a Firebase UID string, not UUID - skip this check
        // if let ownerId = event.ownerId, ownerId == id {
        //     return Friend(id: id, name: "Host", avatarURL: nil)
        // }
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
