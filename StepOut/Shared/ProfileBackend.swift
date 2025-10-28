import Foundation
import CoreLocation
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

struct RemoteProfileResponse {
    struct RemoteProfile {
        let userId: UUID
        let displayName: String
        let username: String?
        let bio: String?
        let phoneNumber: String?
        let photoURL: URL?
        let joinDate: Date?
        let primaryLocation: (latitude: Double, longitude: Double)?
        let stats: ProfileStats
    }

    struct RemoteFriend: Identifiable {
        let id: UUID
        let displayName: String
        let photoURL: URL?
        let status: String
    }

    struct RemoteInvite: Identifiable {
        enum Direction: String {
            case sent
            case received
        }

        let id: UUID
        let displayName: String
        let direction: Direction
        let contact: String?
    }

    struct RemoteAttendedEvent: Identifiable {
        let id: UUID
        let title: String
        let startAt: Date?
        let endAt: Date?
        let location: String
        let coverImagePath: String?
    }

    let profile: RemoteProfile
    let friends: [RemoteFriend]
    let pendingInvites: [RemoteInvite]
    let attendedEvents: [RemoteAttendedEvent]

    init?(dictionary: [String: Any]) {
        guard let profileDict = dictionary["profile"] as? [String: Any],
              let userIdString = profileDict["userId"] as? String,
              let userUUID = UUID(uuidString: userIdString) else { return nil }

        let displayName = profileDict["displayName"] as? String ?? "Friend"
        let username = profileDict["username"] as? String
        let bio = profileDict["bio"] as? String
        let phoneNumber = profileDict["phoneNumber"] as? String
        let photoURL = (profileDict["photoURL"] as? String).flatMap(URL.init(string:))

        let joinDate: Date?
        if let joinDateString = profileDict["joinDate"] as? String {
            joinDate = ISO8601DateFormatter().date(from: joinDateString)
        } else {
            joinDate = nil
        }

        let primaryLocation: (latitude: Double, longitude: Double)?
        if let locationDict = profileDict["primaryLocation"] as? [String: Any],
           let lat = locationDict["lat"] as? Double,
           let lng = locationDict["lng"] as? Double {
            primaryLocation = (lat, lng)
        } else {
            primaryLocation = nil
        }

        let statsDict = profileDict["stats"] as? [String: Any] ?? [:]
        let stats = ProfileStats(
            hostedCount: statsDict["hostedCount"] as? Int ?? 0,
            attendedCount: statsDict["attendedCount"] as? Int ?? 0,
            friendCount: statsDict["friendCount"] as? Int ?? 0,
            invitesSent: statsDict["invitesSent"] as? Int ?? 0
        )

        profile = RemoteProfile(
            userId: userUUID,
            displayName: displayName,
            username: username,
            bio: bio,
            phoneNumber: phoneNumber,
            photoURL: photoURL,
            joinDate: joinDate,
            primaryLocation: primaryLocation,
            stats: stats
        )

        if let friendsArray = dictionary["friends"] as? [[String: Any]] {
            friends = friendsArray.compactMap { item in
                guard let idString = item["id"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
                let name = item["displayName"] as? String ?? "Friend"
                let photoURL = (item["photoURL"] as? String).flatMap(URL.init(string:))
                let status = item["status"] as? String ?? "on-app"
                return RemoteFriend(id: uuid, displayName: name, photoURL: photoURL, status: status)
            }
        } else {
            friends = []
        }

        if let invitesArray = dictionary["pendingInvites"] as? [[String: Any]] {
            pendingInvites = invitesArray.compactMap { item in
                guard let idString = item["id"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
                let displayName = item["displayName"] as? String ?? "Friend"
                let directionRaw = item["direction"] as? String ?? "sent"
                let direction = RemoteInvite.Direction(rawValue: directionRaw) ?? .sent
                let contact = item["contact"] as? String
                return RemoteInvite(id: uuid, displayName: displayName, direction: direction, contact: contact)
            }
        } else {
            pendingInvites = []
        }

        if let attendedArray = dictionary["attendedEvents"] as? [[String: Any]] {
            attendedEvents = attendedArray.compactMap { item in
                guard let idString = item["eventId"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
                let title = item["title"] as? String ?? "Event"
                let location = item["location"] as? String ?? ""
                let coverImagePath = item["coverImagePath"] as? String
                let startAt = (item["startAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                let endAt = (item["endAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                return RemoteAttendedEvent(id: uuid, title: title, startAt: startAt, endAt: endAt, location: location, coverImagePath: coverImagePath)
            }
        } else {
            attendedEvents = []
        }
    }
}

protocol ProfileBackend {
    func fetchProfile(userId: UUID) async throws -> RemoteProfileResponse
    func updateProfile(userId: UUID, displayName: String, username: String?, bio: String?, primaryLocation: CLLocationCoordinate2D?) async throws -> RemoteProfileResponse
    func fetchAttendedEvents(userId: UUID, limit: Int) async throws -> [RemoteProfileResponse.RemoteAttendedEvent]
}

#if canImport(FirebaseFunctions)
final class FirebaseProfileBackend: ProfileBackend {
    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    func fetchProfile(userId: UUID) async throws -> RemoteProfileResponse {
        let callable = functions.httpsCallable("getProfile")
        let result = try await callable.call(["userId": userId.uuidString])

        print("🔍 [ProfileBackend] Raw API response:")
        if let data = result.data as? [String: Any] {
            if let invites = data["pendingInvites"] as? [[String: Any]] {
                print("   pendingInvites count: \(invites.count)")
            } else {
                print("   ❌ pendingInvites key not found in data")
            }
        }

        guard let data = result.data as? [String: Any], let response = RemoteProfileResponse(dictionary: data) else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed getProfile response"])
        }

        print("   ✅ Parsed response has \(response.pendingInvites.count) invites")

        return response
    }

    func updateProfile(userId: UUID, displayName: String, username: String?, bio: String?, primaryLocation: CLLocationCoordinate2D?) async throws -> RemoteProfileResponse {
        let callable = functions.httpsCallable("updateProfile")
        var payload: [String: Any] = ["userId": userId.uuidString, "displayName": displayName]
        if let username { payload["username"] = username }
        if let bio { payload["bio"] = bio }
        if let primaryLocation {
            payload["primaryLocation"] = ["lat": primaryLocation.latitude, "lng": primaryLocation.longitude]
        }
        let result = try await callable.call(payload)
        guard let data = result.data as? [String: Any], let response = RemoteProfileResponse(dictionary: data) else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed updateProfile response"])
        }
        return response
    }

    func fetchAttendedEvents(userId: UUID, limit: Int) async throws -> [RemoteProfileResponse.RemoteAttendedEvent] {
        let callable = functions.httpsCallable("listAttendedEvents")
        let result = try await callable.call(["userId": userId.uuidString, "limit": limit])
        guard let data = result.data as? [String: Any], let events = data["events"] as? [[String: Any]] else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed listAttendedEvents response"])
        }
        return events.compactMap { item in
            guard let idString = item["eventId"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
            let title = item["title"] as? String ?? "Event"
            let location = item["location"] as? String ?? ""
            let coverImagePath = item["coverImagePath"] as? String
            let startAt = (item["startAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            let endAt = (item["endAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            return RemoteProfileResponse.RemoteAttendedEvent(id: uuid, title: title, startAt: startAt, endAt: endAt, location: location, coverImagePath: coverImagePath)
        }
    }

    func listFriends(userId: UUID, includeInvites: Bool) async throws -> ([RemoteProfileResponse.RemoteFriend], [RemoteProfileResponse.RemoteInvite]) {
        let callable = functions.httpsCallable("listFriends")
        let payload: [String: Any] = ["userId": userId.uuidString, "includeInvites": includeInvites]
        print("[Backend] calling listFriends")
        let result = try await callable.call(payload)
        guard let data = result.data as? [String: Any] else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1)
        }

        let friends = (data["friends"] as? [[String: Any]] ?? []).compactMap { item -> RemoteProfileResponse.RemoteFriend? in
            guard let idString = item["id"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
            return RemoteProfileResponse.RemoteFriend(
                id: uuid,
                displayName: item["displayName"] as? String ?? "Friend",
                photoURL: (item["photoURL"] as? String).flatMap(URL.init),
                status: item["status"] as? String ?? "on-app"
            )
        }

        let invites = (data["pendingInvites"] as? [[String: Any]] ?? []).compactMap { item -> RemoteProfileResponse.RemoteInvite? in
            guard let idString = item["id"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
            let directionRaw = item["direction"] as? String ?? "sent"
            let direction = RemoteProfileResponse.RemoteInvite.Direction(rawValue: directionRaw) ?? .sent
            return RemoteProfileResponse.RemoteInvite(
                id: uuid,
                displayName: item["displayName"] as? String ?? "Friend",
                direction: direction,
                contact: item["contact"] as? String
            )
        }

        return (friends, invites)
    }

    func sendFriendInvite(senderId: UUID, recipientPhone: String?, recipientEmail: String?) async throws -> String {
        let callable = functions.httpsCallable("sendFriendInvite")
        var payload: [String: Any] = ["senderId": senderId.uuidString]
        if let phone = recipientPhone { payload["recipientPhone"] = phone }
        if let email = recipientEmail { payload["recipientEmail"] = email }
        print("[Backend] calling sendFriendInvite")
        let result = try await callable.call(payload)
        guard let data = result.data as? [String: Any], let inviteId = data["inviteId"] as? String else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1)
        }
        return inviteId
    }
}
#endif

struct MockProfileBackend: ProfileBackend {
    func fetchProfile(userId: UUID) async throws -> RemoteProfileResponse {
        let profile = ProfileRepository.sampleProfile
        let data: [String: Any] = [
            "profile": [
                "userId": profile.id.uuidString,
                "displayName": profile.displayName,
                "username": profile.username,
                "bio": profile.bio,
                "phoneNumber": profile.phoneNumber as Any,
                "photoURL": profile.photoURL?.absoluteString as Any,
                "joinDate": ISO8601DateFormatter().string(from: profile.joinDate),
                "primaryLocation": profile.primaryLocation.map { ["lat": $0.coordinate.latitude, "lng": $0.coordinate.longitude] } as Any,
                "stats": [
                    "hostedCount": profile.stats.hostedCount,
                    "attendedCount": profile.stats.attendedCount,
                    "friendCount": profile.stats.friendCount,
                    "invitesSent": profile.stats.invitesSent
                ]
            ],
            "friends": profile.friends.map { friend in
                [
                    "id": friend.id.uuidString,
                    "displayName": friend.name,
                    "photoURL": friend.avatarURL?.absoluteString as Any,
                    "status": "on-app"
                ]
            },
            "pendingInvites": profile.pendingInvites.map { invite in
                [
                    "id": invite.id.uuidString,
                    "displayName": invite.name,
                    "direction": invite.direction.rawValue,
                    "contact": invite.contact as Any
                ]
            },
            "attendedEvents": profile.attendedEvents.map { event in
                [
                    "eventId": event.eventID.uuidString,
                    "title": "Event",
                    "startAt": ISO8601DateFormatter().string(from: event.date),
                    "endAt": ISO8601DateFormatter().string(from: event.date),
                    "location": "",
                    "coverImagePath": event.coverImageURL?.absoluteString as Any
                ]
            }
        ]

        guard let response = RemoteProfileResponse(dictionary: data) else {
            throw NSError(domain: "MockProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed mock profile data"])
        }
        return response
    }

    func updateProfile(userId: UUID, displayName: String, username: String?, bio: String?, primaryLocation: CLLocationCoordinate2D?) async throws -> RemoteProfileResponse {
        try await fetchProfile(userId: userId)
    }

    func fetchAttendedEvents(userId: UUID, limit: Int) async throws -> [RemoteProfileResponse.RemoteAttendedEvent] {
        let response = try await fetchProfile(userId: userId)
        return Array(response.attendedEvents.prefix(limit))
    }
}
