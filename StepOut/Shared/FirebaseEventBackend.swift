import Foundation
import CoreLocation
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

final class FirebaseEventBackend: EventBackend {
#if canImport(FirebaseFunctions)
    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    func fetchFeed(for user: Friend, near location: CLLocation) async throws -> EventFeedSnapshot {
        let callable = functions.httpsCallable("listFeed")
        print("[Backend] calling listFeed")
        let result: HTTPSCallableResult
        do {
            result = try await callable.call([String: Any]())
        } catch {
            print("[Backend] listFeed error: \(error.localizedDescription)")
            throw error
        }
        print("[Backend] listFeed response: \(String(describing: result.data))")
        guard let payload = result.data as? [String: Any] else {
            throw NSError(domain: "FirebaseEventBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed listFeed response"])
        }

        let friends = parseFriends(from: payload["friends"])
        let events = parseEvents(from: payload["events"])
        return EventFeedSnapshot(events: events, friends: friends.filter { $0.id != user.id })
    }

    func sendInvite(for eventID: UUID, from sender: Friend, to recipients: [Friend]) async throws {
        throw NSError(domain: "FirebaseEventBackend", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invites are not supported yet."])
    }

    func createEvent(
        owner: Friend,
        title: String,
        description: String?,
        startAt: Date,
        duration: TimeInterval,
        location: String,
        coordinate: CLLocationCoordinate2D?,
        privacy: Event.Privacy
    ) async throws -> UUID {
        let callable = functions.httpsCallable("createEvent")
        let endDate = startAt.addingTimeInterval(duration)

        var payload: [String: Any] = [
            "ownerId": owner.id.uuidString,
            "title": title,
            "description": description as Any,
            "startAt": ISO8601DateFormatter().string(from: startAt),
            "endAt": ISO8601DateFormatter().string(from: endDate),
            "location": location,
            "visibility": privacy == .public ? "public" : "invite-only",
            "maxGuests": NSNull()
        ]

        if let coordinate {
            payload["geo"] = [
                "lat": coordinate.latitude,
                "lng": coordinate.longitude
            ]
        }

        print("[Backend] calling createEvent")
        let result: HTTPSCallableResult
        do {
            result = try await callable.call(payload)
        } catch {
            print("[Backend] createEvent error: \(error.localizedDescription)")
            throw error
        }
        guard
            let response = result.data as? [String: Any],
            let eventIdString = response["eventId"] as? String,
            let eventId = UUID(uuidString: eventIdString)
        else {
            throw NSError(domain: "FirebaseEventBackend", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid createEvent response"])
        }
        return eventId
    }

    func rsvp(eventID: UUID, userId: UUID, status: String, arrival: Date?) async throws {
        let callable = functions.httpsCallable("rsvpEvent")
        var payload: [String: Any] = [
            "eventId": eventID.uuidString,
            "status": status
        ]
        if let arrival {
            payload["arrivalAt"] = ISO8601DateFormatter().string(from: arrival)
        }
        _ = try await callable.call(payload)
    }

    private func parseFriends(from value: Any?) -> [Friend] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let idString = dict["id"] as? String, let uuid = UUID(uuidString: idString) else {
                return nil
            }
            let name = dict["displayName"] as? String ?? "Friend"
            let avatarURL: URL?
            if let photoString = dict["photoURL"] as? String {
                avatarURL = URL(string: photoString)
            } else {
                avatarURL = nil
            }
            return Friend(id: uuid, name: name, avatarURL: avatarURL)
        }
    }

    private func parseEvents(from value: Any?) -> [Event] {
        guard let array = value as? [[String: Any]] else { return [] }

        let placeholderBase = "https://picsum.photos/seed"
        return array.compactMap { dict in
            guard
                let idString = dict["id"] as? String,
                let uuid = UUID(uuidString: idString),
                let title = dict["title"] as? String,
                let location = dict["location"] as? String
            else {
                return nil
            }

            let startMillis = dict["startAt"] as? TimeInterval
            let date = startMillis.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()

            let coverImagePath = dict["coverImagePath"] as? String
            let imageURL: URL
            if let coverImagePath,
               let storageURL = URL(string: coverImagePath) {
                imageURL = storageURL
            } else {
                imageURL = URL(string: "\(placeholderBase)/\(uuid.uuidString)/600/400")!
            }

            let attendingIDs = (dict["attendingFriendIds"] as? [String])?
                .compactMap(UUID.init(uuidString:)) ?? []
            let invitedByIDs = (dict["invitedFriendIds"] as? [String])?
                .compactMap(UUID.init(uuidString:)) ?? []
            let sharedInviteIDs = (dict["sharedInviteFriendIds"] as? [String])?
                .compactMap(UUID.init(uuidString:)) ?? []

            var arrivalTimes: [UUID: Date] = [:]
            if let arrivalDict = dict["arrivalTimes"] as? [String: TimeInterval] {
                for (key, value) in arrivalDict {
                    if let uuid = UUID(uuidString: key) {
                        arrivalTimes[uuid] = Date(timeIntervalSince1970: value / 1000)
                    }
                }
            }

            var coordinate: CLLocationCoordinate2D?
            if let geo = dict["geo"] as? [String: Any],
               let lat = geo["lat"] as? CLLocationDegrees,
               let lng = geo["lng"] as? CLLocationDegrees {
                coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }

            let privacyString = dict["visibility"] as? String ?? "public"
            let privacy: Event.Privacy = privacyString == "public" ? .public : .private

            return Event(
                id: uuid,
                title: title,
                date: date,
                location: location,
                imageURL: imageURL,
                coordinate: coordinate,
                attendingFriendIDs: attendingIDs,
                invitedByFriendIDs: invitedByIDs,
                sharedInviteFriendIDs: sharedInviteIDs,
                privacy: privacy,
                localImageData: nil,
                arrivalTimes: arrivalTimes
            )
        }
    }
#else
    init() {
        fatalError("FirebaseFunctions is not available in this build.")
    }

    func fetchFeed(for user: Friend, near location: CLLocation) async throws -> EventFeedSnapshot {
        throw NSError(domain: "FirebaseEventBackend", code: -1, userInfo: nil)
    }

    func sendInvite(for eventID: UUID, from sender: Friend, to recipients: [Friend]) async throws {}

    func createEvent(
        owner: Friend,
        title: String,
        description: String?,
        startAt: Date,
        duration: TimeInterval,
        location: String,
        coordinate: CLLocationCoordinate2D?,
        privacy: Event.Privacy
    ) async throws -> UUID {
        throw NSError(domain: "FirebaseEventBackend", code: -1, userInfo: nil)
    }

    func rsvp(eventID: UUID, userId: UUID, status: String, arrival: Date?) async throws {}
#endif
}
