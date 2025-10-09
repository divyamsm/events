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
    private let contentPadding: CGFloat = 16

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

                contentOverlay(in: size)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(shape)
            .compositingGroup()
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.05)))
        }
        .foregroundStyle(.white)
        .widgetURL(URL(string: "stepout://event/\(entry.summary.id.uuidString)"))
        .widgetContainerBackground()
    }

    private func contentOverlay(in size: CGSize) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next Event")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text(entry.summary.title)
                        .font(.system(size: min(size.width * 0.17, 26), weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                    Text(entry.summary.location)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 12)
                if entry.summary.friendsGoing.isEmpty == false {
                    friendsGoingView
                }
            }
            Spacer(minLength: 0)
            Text(dateFormatter.localizedString(for: entry.summary.date, relativeTo: .now))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, contentPadding)
        .padding(.vertical, contentPadding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var friendsGoingView: some View {
        let displayedFriends = Array(entry.summary.friendsGoing.prefix(3))
        let extraCount = max(entry.summary.friendsGoing.count - displayedFriends.count, 0)

        return VStack(alignment: .trailing, spacing: 6) {
            avatarStack(for: displayedFriends)
            Text(friendsSummaryText(for: displayedFriends, extraCount: extraCount))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 110, alignment: .trailing)
    }

    private func friendsSummaryText(for friends: [WidgetFriendSummary], extraCount: Int) -> String {
        var names = friends.map { firstName(from: $0.name) }
        if names.isEmpty {
            return ""
        }

        let summary: String
        if names.count == 1 {
            summary = names[0]
        } else {
            summary = names.prefix(2).joined(separator: ", ")
        }

        if extraCount > 0 {
            return summary + " +" + String(extraCount)
        }
        return summary
    }

    private func firstName(from fullName: String) -> String {
        fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    private func friendAvatar(for friend: WidgetFriendSummary) -> some View {
        Text(friend.initials)
            .font(.caption.weight(.bold))
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(avatarColor(for: friend.id))
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
            )
            .foregroundStyle(.white)
    }

    private func avatarColor(for id: UUID) -> Color {
        var hasher = Hasher()
        hasher.combine(id)
        let value = abs(hasher.finalize())
        let hue = Double(value % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }

    private func avatarStack(for friends: [WidgetFriendSummary]) -> some View {
        HStack(spacing: -10) {
            ForEach(friends, id: \.id) { friend in
                friendAvatar(for: friend)
            }
        }
        .frame(height: 32, alignment: .trailing)
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

private extension View {
    @ViewBuilder
    func widgetContainerBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(.clear, for: .widget)
        } else {
            background(Color.clear)
        }
    }
}
