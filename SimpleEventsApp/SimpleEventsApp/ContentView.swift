import SwiftUI

@MainActor
struct ContentView: View {
    let appState: AppState
    @StateObject private var viewModel: EventFeedViewModel
    @State private var alertContext: AlertContext?

    init(
        appState: AppState,
        viewModel: EventFeedViewModel? = nil
    ) {
        self.appState = appState
        _viewModel = StateObject(
            wrappedValue: viewModel ?? EventFeedViewModel(
                backend: MockEventBackend(),
                session: UserSession.sample,
                appState: appState
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if viewModel.feedEvents.isEmpty && viewModel.isLoading {
                    ProgressView("Loading events...")
                        .progressViewStyle(.circular)
                } else {
                    GeometryReader { proxy in
                        let containerHeight = proxy.size.height
                        let cardHeight = containerHeight * 0.78

                        Group {
                            if #available(iOS 17.0, *) {
                                ScrollView(.vertical, showsIndicators: false) {
                                    LazyVStack(spacing: 0) {
                                        ForEach(viewModel.feedEvents) { feedEvent in
                                            VStack {
                                                Spacer(minLength: 0)
                                                EventCardView(feedEvent: feedEvent) {
                                                    viewModel.beginShare(for: feedEvent)
                                                } rsvpAction: {
                                                    viewModel.toggleAttendance(for: feedEvent)
                                                }
                                                .frame(height: cardHeight)
                                                .padding(.horizontal, 24)
                                                Spacer(minLength: 0)
                                            }
                                            .frame(height: containerHeight)
                                        }
                                    }
                                }
                                .scrollTargetBehavior(.paging)
                            } else {
                                VerticalCarouselFallback(
                                    feedEvents: viewModel.feedEvents,
                                    containerSize: proxy.size,
                                    shareTapped: { feedEvent in
                                        viewModel.beginShare(for: feedEvent)
                                    },
                                    rsvpTapped: { feedEvent in
                                        viewModel.toggleAttendance(for: feedEvent)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Upcoming Events")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Open profile")
                }
            }
        }
        .task {
            await viewModel.loadFeed()
        }
        .refreshable {
            await viewModel.loadFeed()
        }
        .sheet(item: $viewModel.shareContext) { context in
            ShareEventSheet(
                context: context,
                onSend: { recipients in
                    Task {
                        await viewModel.completeShare(for: context.feedEvent, to: recipients)
                    }
                },
                onCancel: {
                    viewModel.shareContext = nil
                }
            )
        }
        .alert(item: $alertContext) { context in
            Alert(
                title: Text(context.title),
                message: Text(context.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: viewModel.presentError) { newValue in
            guard let message = newValue else { return }
            alertContext = AlertContext(title: "Heads up", message: message)
            viewModel.presentError = nil
        }
        .onChange(of: viewModel.shareConfirmation) { newValue in
            guard let message = newValue else { return }
            alertContext = AlertContext(title: "Shared", message: message)
            viewModel.shareConfirmation = nil
        }
    }
}

#Preview {
    let appState = AppState()
    appState.isOnboarded = true
    return ContentView(appState: appState)
}

private struct AlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct EventCardView: View {
    let feedEvent: EventFeedViewModel.FeedEvent
    let shareAction: () -> Void
    let rsvpAction: () -> Void

    private let cornerRadius: CGFloat = 28

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            ZStack {
                AsyncImage(url: feedEvent.event.imageURL, transaction: Transaction(animation: .easeInOut)) { phase in
                    image(for: phase, size: size)
                }
                .frame(width: size.width, height: size.height)

                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.85), .black.opacity(0.08)]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    FriendAvatarRow(badges: feedEvent.badges)
                        .padding(.top, 22)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 16)

                    eventInfoBox
                        .padding(.horizontal, 24)
                        .padding(.bottom, 22)
                }
                .frame(width: size.width, height: size.height)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(shape)
            .compositingGroup()
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.05)))
            .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 12)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func image(for phase: AsyncImagePhase, size: CGSize) -> some View {
        switch phase {
        case .empty:
            placeholder
                .frame(width: size.width, height: size.height)
        case .success(let image):
            image
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        case .failure:
            placeholderIcon
                .frame(width: size.width, height: size.height)
        @unknown default:
            placeholder
                .frame(width: size.width, height: size.height)
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 60)
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

    private var eventInfoBox: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardText
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                rsvpButton
                shareButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black.opacity(0.35))
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        )
    }

    private var cardText: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(feedEvent.event.title)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(feedEvent.event.location)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 2) {
                Text(relativeFormatter.localizedString(for: feedEvent.event.date, relativeTo: .now))
                    .font(.subheadline.weight(.semibold))
                Text(absoluteFormatter.string(from: feedEvent.event.date))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
            }

            if feedEvent.isAttending {
                let friendsCount = max(feedEvent.attendingCount - 1, 0)
                Text(friendsCount > 0 ? "You + \(friendsCount) friend\(friendsCount == 1 ? "" : "s") are going" : "You're going")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            } else if feedEvent.attendingCount > 0 {
                Text("\(feedEvent.attendingCount) friend\(feedEvent.attendingCount == 1 ? "" : "s") going")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var rsvpButton: some View {
        Button(action: rsvpAction) {
            HStack(spacing: 8) {
                Image(systemName: feedEvent.isAttending ? "checkmark.seal.fill" : "hands.clap.fill")
                Text(feedEvent.isAttending ? "Going" : "I'm going!")
            }
            .font(.callout.bold())
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .background(
                Capsule()
                    .fill(Color.white.opacity(feedEvent.isAttending ? 0.08 : 0.12))
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: feedEvent.isAttending ? [.green.opacity(0.8), .blue.opacity(0.6)] : [.white.opacity(0.35), .white.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: feedEvent.isAttending ? 2 : 1
                    )
            )
            .foregroundStyle(feedEvent.isAttending ? Color.white : Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(feedEvent.isAttending ? "Mark as not going" : "Mark as going")
    }

    private var shareButton: some View {
        Button(action: shareAction) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share \(feedEvent.event.title)")
    }
}

private struct FriendAvatarRow: View {
    let badges: [EventFeedViewModel.FeedEvent.FriendBadge]

    var body: some View {
        if badges.isEmpty {
            Color.clear
                .frame(height: 1)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(badges) { badge in
                        FriendBadgeView(badge: badge)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct FriendBadgeView: View {
    let badge: EventFeedViewModel.FeedEvent.FriendBadge

    var body: some View {
        VStack(spacing: 6) {
            avatar
                .frame(width: 52, height: 52)
                .overlay(circleBorder)

            Text(label)
                .font(.caption2.weight(.medium))
                .textCase(.uppercase)
                .foregroundStyle(labelColor.opacity(0.85))
        }
    }

    private var avatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        labelColor.opacity(0.7),
                        labelColor.opacity(0.45)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(badge.friend.initials)
                    .font(.headline)
                    .foregroundStyle(.white)
            )
    }

    private var circleBorder: some View {
        Circle()
            .strokeBorder(labelColor, lineWidth: 3)
    }

    private var label: String {
        switch badge.role {
        case .me:
            return "You"
        case .invitedMe:
            return "Invited"
        case .going:
            return "Going"
        case .invitedByMe:
            return "Sent"
        }
    }

    private var labelColor: Color {
        switch badge.role {
        case .me:
            return Color.cyan
        case .invitedMe:
            return Color.orange
        case .going:
            return Color.green
        case .invitedByMe:
            return Color.blue
        }
    }

}

private struct VerticalCarouselFallback: View {
    let feedEvents: [EventFeedViewModel.FeedEvent]
    let containerSize: CGSize
    let shareTapped: (EventFeedViewModel.FeedEvent) -> Void
    let rsvpTapped: (EventFeedViewModel.FeedEvent) -> Void

    var body: some View {
        TabView {
            ForEach(feedEvents) { feedEvent in
                EventCardView(feedEvent: feedEvent) {
                    shareTapped(feedEvent)
                } rsvpAction: {
                    rsvpTapped(feedEvent)
                }
                .frame(width: containerSize.width * 0.82, height: containerSize.height * 0.75)
                .padding(.horizontal, 24)
                .rotationEffect(.degrees(-90))
                .frame(width: containerSize.height, height: containerSize.width)
            }
        }
        .frame(width: containerSize.height, height: containerSize.width)
        .rotationEffect(.degrees(90), anchor: .topLeading)
        .offset(x: containerSize.width)
        .frame(width: containerSize.width, height: containerSize.height)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }
}

private struct ShareEventSheet: View {
    struct ShareTarget: Identifiable, Hashable {
        enum Kind: Hashable {
            case all
            case friend(Friend)
        }

        let id: UUID
        let kind: Kind

        init(kind: Kind) {
            switch kind {
            case .all:
                self.id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? UUID()
            case .friend(let friend):
                self.id = friend.id
            }
            self.kind = kind
        }
    }

    let context: EventFeedViewModel.ShareContext
    let onSend: ([Friend]) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFriendIDs: Set<UUID> = []

    private var targets: [ShareTarget] {
        var items = [ShareTarget(kind: .all)]
        items.append(contentsOf: context.availableFriends.map { ShareTarget(kind: .friend($0)) })
        return items
    }

    private var isAllSelected: Bool {
        let friendCount = context.availableFriends.count
        guard friendCount > 0 else { return false }
        return selectedFriendIDs.count == friendCount
    }

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Text("Send to...")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button("Send") {
                    let recipients = context.availableFriends.filter { selectedFriendIDs.contains($0.id) }
                    onSend(recipients)
                    dismiss()
                }
                .bold()
                .disabled(selectedFriendIDs.isEmpty)
                .foregroundStyle(selectedFriendIDs.isEmpty ? .white.opacity(0.4) : .white)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(context.feedEvent.event.title)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))

                if context.availableFriends.isEmpty {
                    Text("Invite friends to start sharing events.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 22)], spacing: 28) {
                    ForEach(targets) { target in
                        ShareTargetView(
                            target: target,
                            isSelected: isSelected(target)
                        )
                        .onTapGesture {
                            toggleSelection(for: target)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .background(Color.black)
        .presentationDetents([.fraction(0.55), .fraction(0.85)])
        .onAppear {
            selectedFriendIDs = []
        }
    }

    private func isSelected(_ target: ShareTarget) -> Bool {
        switch target.kind {
        case .all:
            return isAllSelected
        case .friend(let friend):
            return selectedFriendIDs.contains(friend.id)
        }
    }

    private func toggleSelection(for target: ShareTarget) {
        switch target.kind {
        case .all:
            if isAllSelected {
                selectedFriendIDs.removeAll()
            } else {
                selectedFriendIDs = Set(context.availableFriends.map { $0.id })
            }
        case .friend(let friend):
            if selectedFriendIDs.contains(friend.id) {
                selectedFriendIDs.remove(friend.id)
            } else {
                selectedFriendIDs.insert(friend.id)
            }
        }
    }
}

private struct ShareTargetView: View {
    let target: ShareEventSheet.ShareTarget
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : Color.white.opacity(0.08))
                    .frame(width: 68, height: 68)

                content
            }
            .overlay(
                Circle()
                    .strokeBorder(isSelected ? Color.blue : Color.white.opacity(0.2), lineWidth: 2)
            )

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch target.kind {
        case .all:
            Image(systemName: "person.3.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
        case .friend(let friend):
            if let url = friend.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        placeholder(friend)
                    case .failure:
                        placeholder(friend)
                    @unknown default:
                        placeholder(friend)
                    }
                }
                .clipShape(Circle())
            } else {
                placeholder(friend)
            }
        }
    }

    private func placeholder(_ friend: Friend) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
            Text(friend.initials)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    private var label: String {
        switch target.kind {
        case .all:
            return "All"
        case .friend(let friend):
            return friend.name.components(separatedBy: " ").first ?? friend.name
        }
    }
}
