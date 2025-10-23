import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
public struct WidgetFriendSummary: Codable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let initials: String

    public init(id: UUID, name: String, initials: String) {
        self.id = id
        self.name = name
        self.initials = initials
    }
}

public struct WidgetEventSummary: Codable, Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let location: String
    public let date: Date
    public let imageURL: URL?
    public let imageData: Data?
    public let friendsGoing: [WidgetFriendSummary]

    public init(
        id: UUID,
        title: String,
        location: String,
        date: Date,
        imageURL: URL?,
        imageData: Data?,
        friendsGoing: [WidgetFriendSummary] = []
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.date = date
        self.imageURL = imageURL
        self.imageData = imageData
        self.friendsGoing = friendsGoing
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, location, date, imageURL, imageData, friendsGoing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        location = try container.decode(String.self, forKey: .location)
        date = try container.decode(Date.self, forKey: .date)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        friendsGoing = try container.decodeIfPresent([WidgetFriendSummary].self, forKey: .friendsGoing) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(location, forKey: .location)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(friendsGoing, forKey: .friendsGoing)
    }
}

enum WidgetTimelineBridge {
    private static let appGroupID = "group.com.stepout.shared"
    private static let storageKey = "widget.events"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func save(events: [Event], friends: [Friend], currentUser: Friend) async {
        let friendLookup = buildFriendLookup(friends: friends, currentUser: currentUser)
        let candidates = events.sorted { $0.date < $1.date }.prefix(6)

        var summaries: [WidgetEventSummary] = []
        summaries.reserveCapacity(candidates.count)

        for event in candidates {
            var resolvedImageData: Data? = event.localImageData
            if resolvedImageData == nil {
                resolvedImageData = await remoteImageData(for: event.imageURL)
            }

            let imageURLForWidget: URL? = {
                if resolvedImageData != nil {
                    return event.imageURL.isFileURL ? event.imageURL : nil
                } else {
                    return event.imageURL
                }
            }()

            let attending = attendeeSummaries(for: event, lookup: friendLookup, currentUser: currentUser)

            let summary = WidgetEventSummary(
                id: event.id,
                title: event.title,
                location: event.location,
                date: event.date,
                imageURL: imageURLForWidget,
                imageData: resolvedImageData,
                friendsGoing: attending
            )
            summaries.append(summary)
        }

        guard let data = try? encoder.encode(summaries),
              let defaults = UserDefaults(suiteName: appGroupID) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }

    static func loadSummaries() -> [WidgetEventSummary] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: storageKey),
              let summaries = try? decoder.decode([WidgetEventSummary].self, from: data) else {
            return fallbackSummaries()
        }
        return summaries
    }

    static func fallbackSummaries() -> [WidgetEventSummary] {
        // Create a placeholder user for widget fallback
        let placeholderUser = Friend(
            id: UUID(uuidString: "B2A4A608-1D12-4AC3-8C6C-5C9F0A2F9942")!,
            name: "User",
            avatarURL: nil
        )

        let lookup = buildFriendLookup(
            friends: EventRepository.friends,
            currentUser: placeholderUser
        )

        return EventRepository.sampleEvents.map { event in
            WidgetEventSummary(
                id: event.id,
                title: event.title,
                location: event.location,
                date: event.date,
                imageURL: event.imageURL,
                imageData: nil,
                friendsGoing: attendeeSummaries(
                    for: event,
                    lookup: lookup,
                    currentUser: placeholderUser
                )
            )
        }
    }

    #if canImport(WidgetKit)
    static func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "StepOutWidget")
    }
    #endif

    private static func buildFriendLookup(friends: [Friend], currentUser: Friend) -> [UUID: Friend] {
        var lookup: [UUID: Friend] = [:]
        lookup[currentUser.id] = currentUser
        for friend in friends {
            lookup[friend.id] = friend
        }
        return lookup
    }

    private static func attendeeSummaries(
        for event: Event,
        lookup: [UUID: Friend],
        currentUser: Friend
    ) -> [WidgetFriendSummary] {
        let attendees = event.attendingFriendIDs
            .compactMap { id -> WidgetFriendSummary? in
                if id == currentUser.id {
                    return WidgetFriendSummary(id: id, name: currentUser.name, initials: currentUser.initials)
                }
                guard let friend = lookup[id] else { return nil }
                return WidgetFriendSummary(id: friend.id, name: friend.name, initials: friend.initials)
            }
        return Array(attendees.prefix(4))
    }

    private static func remoteImageData(for url: URL) async -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
