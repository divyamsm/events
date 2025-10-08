import WidgetKit
import SwiftUI
import UIKit

struct SimpleEventsEntry: TimelineEntry {
    let date: Date
    let eventIndex: Int
    let event: Event
    let image: UIImage?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEventsEntry {
        defaultEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEventsEntry) -> Void) {
        guard let event = EventRepository.sampleEvents.first else {
            completion(defaultEntry)
            return
        }

        loadImage(for: event) { image in
            completion(SimpleEventsEntry(date: Date(), eventIndex: 0, event: event, image: image))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEventsEntry>) -> Void) {
        guard let event = EventRepository.sampleEvents.first else {
            completion(Timeline(entries: [defaultEntry], policy: .atEnd))
            return
        }

        loadImage(for: event) { image in
            let entry = SimpleEventsEntry(date: Date(), eventIndex: 0, event: event, image: image)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60))))
        }
    }

    private var defaultEntry: SimpleEventsEntry {
        if let event = EventRepository.sampleEvents.first {
            return SimpleEventsEntry(date: Date(), eventIndex: 0, event: event, image: nil)
        }

        let fallbackEvent = Event(
            title: "No Events",
            date: .now,
            location: "Check back soon",
            imageURL: URL(string: "https://images.unsplash.com/photo-1498050108023-c5249f4df085?auto=format&fit=crop&w=1400&q=80")!
        )
        return SimpleEventsEntry(date: Date(), eventIndex: 0, event: fallbackEvent, image: nil)
    }

    private func loadImage(for event: Event, completion: @escaping (UIImage?) -> Void) {
        let request = URLRequest(url: event.imageURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)

        if let cached = URLCache.shared.cachedResponse(for: request)?.data, let image = UIImage(data: cached) {
            completion(image)
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, _ in
            var finalData = data
            if let data = data, let response = response {
                let cachedResponse = CachedURLResponse(response: response, data: data)
                URLCache.shared.storeCachedResponse(cachedResponse, for: request)
            } else {
                finalData = URLCache.shared.cachedResponse(for: request)?.data
            }

            let image = finalData.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
}

struct SimpleEventsWidgetEntryView: View {
    var entry: Provider.Entry
    private let cornerRadius: CGFloat = 20

    private let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            ZStack(alignment: .bottomLeading) {
                if let image = entry.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                } else {
                    placeholder
                        .frame(width: size.width, height: size.height)
                }

                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.65), .black.opacity(0.15)]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Next Event")
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(entry.event.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(entry.event.location)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Text(dateFormatter.localizedString(for: entry.event.date, relativeTo: .now))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding()
                .frame(width: size.width, height: size.height, alignment: .bottomLeading)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(shape)
            .compositingGroup()
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.05)))
        }
        .foregroundStyle(.white)
        .widgetURL(URL(string: "simpleevents://event/\(entry.eventIndex)"))
    }

    private var placeholder: some View {
        ZStack {
            Color(.systemGray5)
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.8))
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "photo")
                .foregroundStyle(.white.opacity(0.8))
                .font(.title2)
        }
    }
}

struct SimpleEventsWidget: Widget {
    let kind: String = "SimpleEventsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SimpleEventsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Event")
        .description("Keep an eye on what's coming up.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
