import SwiftUI

struct EventDetailTabsView: View {
    let feedEvent: EventFeedViewModel.FeedEvent
    let currentUserId: String
    let isEventOwner: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var photosViewModel: EventPhotosViewModel
    @StateObject private var commentsViewModel: EventPhotosViewModel

    init(feedEvent: EventFeedViewModel.FeedEvent, currentUserId: String, isEventOwner: Bool) {
        self.feedEvent = feedEvent
        self.currentUserId = currentUserId
        self.isEventOwner = isEventOwner
        _photosViewModel = StateObject(wrappedValue: EventPhotosViewModel(currentUserId: currentUserId))
        _commentsViewModel = StateObject(wrappedValue: EventPhotosViewModel(currentUserId: currentUserId))
    }

    var body: some View {
        NavigationStack {
            TabView {
                // Event Info Tab
                EventInfoTab(feedEvent: feedEvent)
                    .tabItem {
                        Label("Info", systemImage: "info.circle")
                    }

                // Photos Tab - Preloaded
                EventPhotosView(
                    eventId: feedEvent.event.id.uuidString,
                    isEventOwner: isEventOwner,
                    currentUserId: currentUserId,
                    viewModel: photosViewModel
                )
                .tabItem {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }

                // Comments Tab - Preloaded
                EventCommentsView(
                    eventId: feedEvent.event.id.uuidString,
                    isEventOwner: isEventOwner,
                    currentUserId: currentUserId,
                    viewModel: commentsViewModel
                )
                .tabItem {
                    Label("Comments", systemImage: "bubble.left.and.bubble.right")
                }
            }
            .navigationTitle(feedEvent.event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                // Preload photos and comments as soon as view appears
                async let photosLoad: Void = photosViewModel.loadPhotos(for: feedEvent.event.id.uuidString)
                async let commentsLoad: Void = commentsViewModel.loadComments(for: feedEvent.event.id.uuidString)
                _ = await (photosLoad, commentsLoad)
            }
        }
    }
}

// MARK: - Event Info Tab

struct EventInfoTab: View {
    let feedEvent: EventFeedViewModel.FeedEvent

    private let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Event Image
                AsyncImage(url: feedEvent.event.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 250)
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 250)
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 250)
                            .overlay {
                                ProgressView()
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 12) {
                    // Title
                    Text(feedEvent.event.title)
                        .font(.title.bold())

                    // Location
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.red)
                        Text(feedEvent.event.location)
                            .font(.headline)
                    }

                    // Date & Time
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.blue)
                        Text(absoluteFormatter.string(from: feedEvent.event.date))
                            .font(.subheadline)
                    }

                    // Attendance
                    if feedEvent.attendingCount > 0 {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.green)
                            Text("\(feedEvent.attendingCount) \(feedEvent.attendingCount == 1 ? "person" : "people") going")
                                .font(.subheadline)
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Who's Going
                    if !feedEvent.badges.isEmpty {
                        Text("Who's Going")
                            .font(.headline)

                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(feedEvent.badges.prefix(10)) { badge in
                                HStack {
                                    if let avatarURL = badge.friend.avatarURL {
                                        AsyncImage(url: avatarURL) { image in
                                            image.resizable()
                                        } placeholder: {
                                            Circle().fill(Color.blue)
                                        }
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 32, height: 32)
                                            .overlay {
                                                Text(badge.friend.name.prefix(1))
                                                    .foregroundColor(.white)
                                                    .font(.caption.bold())
                                            }
                                    }

                                    Text(badge.friend.name)
                                        .font(.subheadline)

                                    Spacer()

                                    badgeLabel(for: badge.role)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func badgeLabel(for role: EventFeedViewModel.FeedEvent.BadgeRole) -> some View {
        switch role {
        case .me:
            Text("You")
                .font(.caption.bold())
                .foregroundColor(.green)
        case .going:
            Text("Going")
                .font(.caption)
                .foregroundColor(.secondary)
        case .invitedMe:
            Text("Invited You")
                .font(.caption)
                .foregroundColor(.orange)
        case .invitedByMe:
            Text("Invited")
                .font(.caption)
                .foregroundColor(.blue)
        }
    }
}
