import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
public struct WidgetEventSummary: Codable, Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let location: String
    public let date: Date
    public let imageURL: URL?
    public let imageData: Data?

    public init(id: UUID, title: String, location: String, date: Date, imageURL: URL?, imageData: Data?) {
        self.id = id
        self.title = title
        self.location = location
        self.date = date
        self.imageURL = imageURL
        self.imageData = imageData
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

    static func save(events: [Event]) {
        let summaries = events
            .sorted { $0.date < $1.date }
            .prefix(6)
            .map { event in
                WidgetEventSummary(
                    id: event.id,
                    title: event.title,
                    location: event.location,
                    date: event.date,
                    imageURL: event.localImageData == nil ? event.imageURL : nil,
                    imageData: event.localImageData
                )
            }

        guard let data = try? encoder.encode(Array(summaries)),
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
        EventRepository.sampleEvents.map {
            WidgetEventSummary(
                id: $0.id,
                title: $0.title,
                location: $0.location,
                date: $0.date,
                imageURL: $0.imageURL,
                imageData: nil
            )
        }
    }

    #if canImport(WidgetKit)
    static func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "StepOutWidget")
    }
    #endif
}
