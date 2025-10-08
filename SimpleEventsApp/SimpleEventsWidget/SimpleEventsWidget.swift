import WidgetKit
import SwiftUI

struct SimpleEventsEntry: TimelineEntry {
    let date: Date
    let eventIndex: Int
    let event: Event
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEventsEntry {
        defaultEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEventsEntry) -> Void) {
        completion(defaultEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEventsEntry>) -> Void) {
        guard let event = EventRepository.sampleEvents.first else {
            completion(Timeline(entries: [defaultEntry], policy: .never))
            return
        }

        let entry = SimpleEventsEntry(date: Date(), eventIndex: 0, event: event)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60))))
    }

    private var defaultEntry: SimpleEventsEntry {
        if let event = EventRepository.sampleEvents.first {
            return SimpleEventsEntry(date: Date(), eventIndex: 0, event: event)
        }

        let fallbackEvent = Event(title: "No Events", date: .now, location: "Check back soon")
        return SimpleEventsEntry(date: Date(), eventIndex: 0, event: fallbackEvent)
    }
}

struct SimpleEventsWidgetEntryView: View {
    var entry: Provider.Entry

    private let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next Event")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.event.title)
                .font(.headline)
                .lineLimit(2)
            Text(entry.event.location)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(dateFormatter.localizedString(for: entry.event.date, relativeTo: .now))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .widgetURL(URL(string: "simpleevents://event/\(entry.eventIndex)"))
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
