import WidgetKit
import SwiftUI
import UIKit

struct StepOutEntry: TimelineEntry {
    let date: Date
    let eventIndex: Int
    let summary: WidgetEventSummary
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StepOutEntry {
        let fallback = WidgetTimelineBridge.fallbackSummaries().first ?? WidgetEventSummary(
            id: UUID(),
            title: "Upcoming Event",
            location: "Stay tuned",
            date: Date().addingTimeInterval(60 * 60),
            imageURL: nil,
            imageData: nil
        )
        return StepOutEntry(date: Date(), eventIndex: 0, summary: fallback)
    }

    func getSnapshot(in context: Context, completion: @escaping (StepOutEntry) -> Void) {
        let summaries = WidgetTimelineBridge.loadSummaries().sorted { $0.date < $1.date }
        let summary = summaries.first ?? WidgetTimelineBridge.fallbackSummaries().first ?? placeholder(in: context).summary
        completion(StepOutEntry(date: Date(), eventIndex: 0, summary: summary))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepOutEntry>) -> Void) {
        let summaries = WidgetTimelineBridge.loadSummaries().sorted { $0.date < $1.date }
        let entries: [StepOutEntry]

        if summaries.isEmpty {
            let fallback = WidgetTimelineBridge.fallbackSummaries().first ?? placeholder(in: context).summary
            entries = [StepOutEntry(date: Date(), eventIndex: 0, summary: fallback)]
        } else {
            entries = summaries.enumerated().map { index, summary in
                let entryDate = max(Date(), summary.date.addingTimeInterval(-30 * 60))
                return StepOutEntry(date: entryDate, eventIndex: index, summary: summary)
            }
        }

        let refresh = summaries.isEmpty ? Date().addingTimeInterval(30 * 60) : Date().addingTimeInterval(60 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct StepOutWidgetEntryView: View {
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
                backgroundImage(in: size)

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
                    Text(entry.summary.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(entry.summary.location)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Text(dateFormatter.localizedString(for: entry.summary.date, relativeTo: .now))
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
        .widgetURL(URL(string: "stepout://event/\(entry.summary.id.uuidString)"))
    }

    @ViewBuilder
    private func backgroundImage(in size: CGSize) -> some View {
        if let data = entry.summary.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
        } else if let url = entry.summary.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(width: size.width, height: size.height)
        } else {
            placeholder
                .frame(width: size.width, height: size.height)
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.systemGray5)
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.8))
        }
    }
}

struct StepOutWidget: Widget {
    let kind: String = "StepOutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            StepOutWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Event")
        .description("Keep an eye on what's coming up.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
