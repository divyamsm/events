import SwiftUI
import MapKit
import PhotosUI
import CoreLocation
import UIKit
import FirebaseAuth

struct AlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
}

@MainActor
struct ContentView: View {
    let appState: AppState
    @StateObject private var authManager: AuthenticationManager
    @State private var viewModel: EventFeedViewModel?
    @State private var alertContext: AlertContext?
    @State private var showingCreateEvent = false
    @State private var editingEvent: EventFeedViewModel.FeedEvent?
    @State private var deleteTarget: EventFeedViewModel.FeedEvent?
    @State private var showAttendanceSheet: EventFeedViewModel.FeedEvent?
    @State private var pendingRSVP: EventFeedViewModel.FeedEvent?
    @State private var selectedFeedTab: FeedTab = .upcoming


    enum FeedTab: String, CaseIterable {
        case upcoming = "Upcoming"
        case past = "Past"
    }

    init(
        appState: AppState,
        authManager: AuthenticationManager? = nil,
        viewModel: EventFeedViewModel? = nil
    ) {
        self.appState = appState

        if let authManager = authManager {
            _authManager = StateObject(wrappedValue: authManager)
        } else {
            _authManager = StateObject(wrappedValue: AuthenticationManager())
        }

        // Don't create view model until authentication completes
        if let viewModel = viewModel {
            _viewModel = State(initialValue: viewModel)
        }
    }

    var body: some View {
        Group {
            if authManager.isLoading {
                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            } else if authManager.isAuthenticated, let session = authManager.currentSession {
                if viewModel != nil {
                    mainAppView
                        .onChange(of: authManager.currentSession) { newSession in
                            if let newSession = newSession {
                                viewModel?.updateSession(newSession)
                            }
                        }
                } else {
                    Color.clear
                        .onAppear {
                            createViewModel(with: session)
                        }
                }
            } else {
                EmailAuthView { user in
                    print("[ContentView] User signed in: \(user.uid)")
                }
            }
        }
    }

    private func createViewModel(with session: UserSession) {
        let backend: EventBackend
#if canImport(FirebaseFunctions)
        backend = FirebaseEventBackend()
#else
        backend = MockEventBackend()
#endif
        viewModel = EventFeedViewModel(
            backend: backend,
            session: session,
            appState: appState
        )
    }

    private var mainAppView: some View {
        guard let viewModel = viewModel else {
            return AnyView(Color.clear)
        }

        return AnyView(mainAppViewContent(with: viewModel))
    }

    private func mainAppViewContent(with viewModel: EventFeedViewModel) -> some View {
        MainAppContentView(
            viewModel: viewModel,
            appState: appState,
            authManager: authManager,
            selectedFeedTab: $selectedFeedTab,
            showingCreateEvent: $showingCreateEvent,
            editingEvent: $editingEvent,
            deleteTarget: $deleteTarget,
            showAttendanceSheet: $showAttendanceSheet,
            pendingRSVP: $pendingRSVP,
            alertContext: $alertContext
        )
    }
}

enum ViewMode {
    case cards
    case map
}

@MainActor
private struct MainAppContentView: View {
    @ObservedObject var viewModel: EventFeedViewModel
    let appState: AppState
    let authManager: AuthenticationManager?
    @Binding var selectedFeedTab: ContentView.FeedTab
    @Binding var showingCreateEvent: Bool
    @Binding var editingEvent: EventFeedViewModel.FeedEvent?
    @Binding var deleteTarget: EventFeedViewModel.FeedEvent?
    @Binding var showAttendanceSheet: EventFeedViewModel.FeedEvent?
    @Binding var pendingRSVP: EventFeedViewModel.FeedEvent?
    @Binding var alertContext: AlertContext?

    @State private var selectedMainTab: MainTab = .home
    @State private var viewMode: ViewMode = .cards

    enum MainTab {
        case home
        case chats
        case profile
    }

    var body: some View {
        TabView(selection: $selectedMainTab) {
            // Home Tab with Events
            NavigationStack {
                ZStack {
                    // Gradient background
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.05),
                            Color.purple.opacity(0.05),
                            Color(.systemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 0) {
                        // Modern header
                        ModernHomeHeader(
                            selectedTab: $selectedFeedTab,
                            viewMode: $viewMode,
                            onCreateTapped: { showingCreateEvent = true }
                        )

                        Group {
                            if selectedFeedTab == .upcoming {
                                if viewMode == .map {
                                    eventsMapView
                                } else {
                                    upcomingFeed
                                }
                            } else {
                                pastFeed
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("StepOut")
                                .font(.title3.bold())
                        }
                    }
                }
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(MainTab.home)

            // Chats Tab
            ChatsTabView(authManager: authManager)
                .tabItem {
                    Label("Chats", systemImage: "message.fill")
                }
                .tag(MainTab.chats)

            // Profile Tab
            NavigationStack {
                ProfileView(authManager: authManager)
                    .environmentObject(appState)
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
            .tag(MainTab.profile)
        }
        .tint(.primary)
        .task { await viewModel.loadFeed() }
        .refreshable { await viewModel.loadFeed() }
        .sheet(item: $viewModel.shareContext) { context in
            ShareEventSheet(
                context: context,
                onSend: { recipients in
                    Task { await viewModel.completeShare(for: context.feedEvent, to: recipients) }
                },
                onCancel: { viewModel.shareContext = nil }
            )
        }
        .sheet(isPresented: $showingCreateEvent) {
            CreateEventView(friends: viewModel.friendOptions) { title, location, date, endDate, coordinate, imageURL, privacy, invitedIDs, imageData in
                viewModel.createEvent(
                    title: title,
                    location: location,
                    date: date,
                    endDate: endDate,
                    coordinate: coordinate,
                    imageURL: imageURL,
                    privacy: privacy,
                    invitedFriendIDs: invitedIDs,
                    localImageData: imageData
                )
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingEvent) { editing in
            EditEventView(feedEvent: editing, friends: viewModel.friendOptions) { title, location, date, coordinate, privacy, invitedIDs, imageData in
                viewModel.updateEvent(
                    id: editing.id,
                    title: title,
                    location: location,
                    date: date,
                    coordinate: coordinate,
                    privacy: privacy,
                    invitedFriendIDs: invitedIDs,
                    localImageData: imageData
                )
            }
        }
        .confirmationDialog("Delete event?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { event in
            Button("Delete Event", role: .destructive) {
                viewModel.deleteEvent(event)
                deleteTarget = nil
            }
        } message: { _ in
            Text("This will remove the event for you and your friends.")
        }
        .sheet(item: $showAttendanceSheet) { feedEvent in
            AttendanceListView(feedEvent: feedEvent)
        }
        .sheet(item: $pendingRSVP) { feedEvent in
            RSVPArrivalSheet(feedEvent: feedEvent) { arrival in
                viewModel.updateAttendance(for: feedEvent, going: true, arrivalTime: arrival)
                pendingRSVP = nil
            } onCancel: {
                pendingRSVP = nil
            }
            .presentationDetents([.fraction(0.55), .large])
            .presentationDragIndicator(.visible)
        }
        .alert(item: $alertContext) { context in
            Alert(
                title: Text(context.title),
                message: context.message.map { Text($0) },
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
        .overlay(alignment: .top) {
            if let toast = viewModel.toastEntry {
                SuccessToast(text: toast.message, systemImage: toast.systemImage)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: viewModel.toastEntry?.id)
        .onChange(of: selectedFeedTab) { newTab in
            // Automatically switch to cards view when switching to Past tab
            if newTab == .past && viewMode == .map {
                withAnimation(.spring(response: 0.3)) {
                    viewMode = .cards
                }
            }
        }
    }

    @ViewBuilder
    private var upcomingFeed: some View {
        if viewModel.feedEvents.isEmpty && viewModel.isLoading {
            VStack {
                Spacer()
                ProgressView("Loading events...")
                    .progressViewStyle(.circular)
                Spacer()
            }
        } else if viewModel.feedEvents.isEmpty {
            // Beautiful empty state
            VStack(spacing: 32) {
                Spacer()

                // Gradient icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.15), .purple.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 12) {
                    Text("No Events Yet")
                        .font(.title.bold())
                        .foregroundStyle(.primary)

                    Text("Create your first event to start\nconnecting with friends")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                // CTA Button
                Button(action: { showingCreateEvent = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("Create Event")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(
                        color: .blue.opacity(0.4),
                        radius: 12,
                        x: 0,
                        y: 6
                    )
                }

                Spacer()
            }
            .padding(.horizontal, 40)
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
                                        EventCardView(
                                            feedEvent: feedEvent,
                                            shareAction: {
                                                viewModel.beginShare(for: feedEvent)
                                            },
                                            rsvpAction: {
                                                if feedEvent.isAttending {
                                                    viewModel.updateAttendance(for: feedEvent, going: false, arrivalTime: nil)
                                                } else {
                                                    pendingRSVP = feedEvent
                                                }
                                            },
                                            editAction: feedEvent.isEditable ? {
                                                editingEvent = feedEvent
                                            } : nil,
                                            deleteAction: feedEvent.isEditable ? {
                                                deleteTarget = feedEvent
                                            } : nil,
                                            showAllAttendees: feedEvent.badges.count > 2 ? {
                                                showAttendanceSheet = feedEvent
                                            } : nil
                                        )
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
                                if feedEvent.isAttending {
                                    viewModel.updateAttendance(for: feedEvent, going: false, arrivalTime: nil)
                                } else {
                                    pendingRSVP = feedEvent
                                }
                            },
                            editTapped: { feedEvent in
                                if feedEvent.isEditable {
                                    editingEvent = feedEvent
                                }
                            },
                            deleteTapped: { feedEvent in
                                if feedEvent.isEditable {
                                    deleteTarget = feedEvent
                                }
                            },
                            showAllTapped: { feedEvent in
                                showAttendanceSheet = feedEvent
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pastFeed: some View {
        if viewModel.visiblePastFeedEvents.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Text("No past events yet.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.visiblePastFeedEvents) { feedEvent in
                        PastEventRow(feedEvent: feedEvent)
                    }

                    if viewModel.pastFeedEvents.count > 5 {
                        Button(viewModel.showAllPastEvents ? "Show Less" : "Show More") {
                            withAnimation {
                                viewModel.showAllPastEvents.toggle()
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var eventsMapView: some View {
        EventsMapView(
            events: viewModel.feedEvents,
            onEventTapped: { feedEvent in
                // Handle event tap - could show detail sheet
                showAttendanceSheet = feedEvent
            },
            onRSVPTapped: { feedEvent in
                if feedEvent.isAttending {
                    viewModel.updateAttendance(for: feedEvent, going: false, arrivalTime: nil)
                } else {
                    pendingRSVP = feedEvent
                }
            }
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let appState = AppState()
        appState.isOnboarded = true
        return ContentView(appState: appState)
            .environmentObject(appState)
    }
}

private struct PastEventRow: View {
    let feedEvent: EventFeedViewModel.FeedEvent

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let gradientPalettes: [[Color]] = [
        [Color(red: 0.22, green: 0.37, blue: 0.94), Color(red: 0.57, green: 0.19, blue: 0.97)],
        [Color(red: 0.17, green: 0.63, blue: 0.75), Color(red: 0.08, green: 0.42, blue: 0.68)],
        [Color(red: 0.86, green: 0.31, blue: 0.55), Color(red: 0.99, green: 0.55, blue: 0.39)],
        [Color(red: 0.29, green: 0.51, blue: 0.35), Color(red: 0.13, green: 0.36, blue: 0.23)]
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            timelineIndicator

            VStack(alignment: .leading, spacing: 16) {
                Text(feedEvent.event.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Label(scheduleText, systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Label(feedEvent.event.location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                if feedEvent.badges.isEmpty == false {
                    attendeesSection
                }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(gradientBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: (gradientColors.last ?? .black).opacity(0.28), radius: 18, x: 0, y: 10)
    }

    private var gradientColors: [Color] {
        let palettes = Self.gradientPalettes
        let index = abs(feedEvent.event.id.uuidString.hashValue) % palettes.count
        return palettes[index]
    }

    private var gradientBackground: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var timelineIndicator: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(gradientBackground)
                    .frame(width: 26, height: 26)
                    .shadow(color: gradientColors.first?.opacity(0.45) ?? .clear, radius: 6, y: 3)

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 3, height: 72)
                .cornerRadius(1.5)
        }
        .frame(width: 30)
    }

    private var scheduleText: String {
        "\(Self.dateFormatter.string(from: feedEvent.event.date)) · \(Self.timeFormatter.string(from: feedEvent.event.date))"
    }

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attended by")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(feedEvent.badges) { badge in
                        attendeeChip(for: badge)
                    }
                }
                .padding(.leading, 4)
            }
            .frame(height: 40)
        }
    }

    private func attendeeChip(for badge: EventFeedViewModel.FeedEvent.FriendBadge) -> some View {
        HStack(spacing: 10) {
            MiniAvatar(badge: badge)
            Text(badge.friend.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.16))
        )
    }

    private struct MiniAvatar: View {
        let badge: EventFeedViewModel.FeedEvent.FriendBadge

        var body: some View {
            ZStack {
                if let url = badge.friend.avatarURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            placeholderInitials
                        case .failure:
                            placeholderInitials
                        @unknown default:
                            placeholderInitials
                        }
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                } else {
                    placeholderInitials
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }

        private var placeholderInitials: some View {
            Text(badge.friend.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
    }
}


private struct EventCardView: View {
    let feedEvent: EventFeedViewModel.FeedEvent
    let shareAction: () -> Void
    let rsvpAction: () -> Void
    let editAction: (() -> Void)?
    let deleteAction: (() -> Void)?
    let showAllAttendees: (() -> Void)?

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

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            ZStack {
                eventImage(for: size)
                    .frame(width: size.width, height: size.height)

                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.85), .black.opacity(0.08)]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    FriendAvatarRow(badges: feedEvent.badges, onShowAll: showAllAttendees)
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
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 12) {
                    if let editAction = editAction, let deleteAction = deleteAction {
                        Menu {
                            Button("Edit", action: editAction)
                            Button("Delete", role: .destructive, action: deleteAction)
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .accessibilityLabel("Event actions")
                    }

                    privacyBadge
                }
                .padding(.top, 18)
                .padding(.trailing, 24)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func eventImage(for size: CGSize) -> some View {
        if let data = feedEvent.event.localImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            AsyncImage(url: feedEvent.event.imageURL, transaction: Transaction(animation: .easeInOut)) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image
                        .resizable()
                        .renderingMode(.original)
                case .failure:
                    placeholderIcon
                @unknown default:
                    placeholder
                }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipped()
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
                if let arrival = feedEvent.myArrivalTime {
                    Text("Arriving \(timeFormatter.string(from: arrival))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Text("Arrival time TBD")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
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
    let onShowAll: (() -> Void)?

    init(badges: [EventFeedViewModel.FeedEvent.FriendBadge], onShowAll: (() -> Void)? = nil) {
        self.badges = badges
        self.onShowAll = onShowAll
    }

    var body: some View {
        if badges.isEmpty {
            Color.clear
                .frame(height: 1)
        } else {
            HStack(spacing: 14) {
                ForEach(Array(badges.prefix(2))) { badge in
                    FriendBadgeView(badge: badge)
                }

                if badges.count > 2, let onShowAll = onShowAll {
                    Button(action: onShowAll) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.3.fill")
                                .font(.caption)
                            Text("+\(badges.count - 2)")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.white.opacity(0.2))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
    }
}

private extension EventCardView {
    var privacyBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: feedEvent.event.privacy == .public ? "globe" : "lock.fill")
                .font(.caption)
            Text(feedEvent.event.privacy == .public ? "Public" : "Private")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.black.opacity(0.35))
        )
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

private struct AttendanceListView: View {
    let feedEvent: EventFeedViewModel.FeedEvent

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                Section("People going") {
                    ForEach(sortedGoingBadges) { badge in
                        attendeeRow(for: badge, role: badge.role == .me ? "You" : "Going")
                    }
                }

                if feedEvent.badges.contains(where: { $0.role == .invitedMe }) {
                    Section("Invited you") {
                        ForEach(feedEvent.badges.filter { $0.role == .invitedMe }) { badge in
                            attendeeRow(for: badge, role: "Invited you")
                        }
                    }
                }

                if feedEvent.badges.contains(where: { $0.role == .invitedByMe }) {
                    Section("You invited") {
                        ForEach(feedEvent.badges.filter { $0.role == .invitedByMe }) { badge in
                            attendeeRow(for: badge, role: "Invited")
                        }
                    }
                }
            }
            .navigationTitle(feedEvent.event.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func attendeeRow(for badge: EventFeedViewModel.FeedEvent.FriendBadge, role: String) -> some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.blue.opacity(0.25))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(badge.friend.initials)
                        .font(.headline)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(badge.friend.name)
                    .font(.body.weight(.semibold))
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(arrivalText(for: badge))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }

    private var sortedGoingBadges: [EventFeedViewModel.FeedEvent.FriendBadge] {
        feedEvent.badges
            .filter { $0.role == .going || $0.role == .me }
            .sorted { lhs, rhs in
                let lhsTime = arrivalTime(for: lhs) ?? Date.distantFuture
                let rhsTime = arrivalTime(for: rhs) ?? Date.distantFuture
                if lhsTime == rhsTime {
                    return lhs.friend.name < rhs.friend.name
                }
                return lhsTime < rhsTime
            }
    }

    private func arrivalTime(for badge: EventFeedViewModel.FeedEvent.FriendBadge) -> Date? {
        feedEvent.event.arrivalTimes[badge.friend.id]
    }

    private func arrivalText(for badge: EventFeedViewModel.FeedEvent.FriendBadge) -> String {
        guard badge.role == .going || badge.role == .me else { return "" }
        if let time = arrivalTime(for: badge) {
            return timeFormatter.string(from: time)
        }
        return "TBD"
    }
}

private struct RSVPArrivalSheet: View {
    enum Choice: String, CaseIterable, Identifiable {
        case onTime
        case custom
        case unsure

        var id: String { rawValue }

        var title: String {
            switch self {
            case .onTime: return "On time"
            case .custom: return "Pick a time"
            case .unsure: return "Not sure yet"
            }
        }
    }

    let feedEvent: EventFeedViewModel.FeedEvent
    let onConfirm: (Date?) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice: Choice = .onTime
    @State private var customTime: Date

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private let eventDetailFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(feedEvent: EventFeedViewModel.FeedEvent, onConfirm: @escaping (Date?) -> Void, onCancel: @escaping () -> Void) {
        self.feedEvent = feedEvent
        self.onConfirm = onConfirm
        self.onCancel = onCancel

        if let arrival = feedEvent.myArrivalTime {
            let calendar = Calendar.current
            if calendar.isDate(arrival, equalTo: feedEvent.event.date, toGranularity: .minute) {
                _choice = State(initialValue: .onTime)
                _customTime = State(initialValue: arrival)
            } else {
                _choice = State(initialValue: .custom)
                _customTime = State(initialValue: arrival)
            }
        } else {
            _choice = State(initialValue: .unsure)
            _customTime = State(initialValue: feedEvent.event.date)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemGroupedBackground), Color(.systemBackground)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        heroSection
                        arrivalOptionsCard

                        if attendeeArrivals.isEmpty == false {
                            attendeesCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                }
            }
            .navigationTitle("Confirm arrival")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        confirm()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var allowedRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: feedEvent.event.date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? feedEvent.event.date
        return start...end
    }

    private var summaryText: String {
        switch choice {
        case .onTime:
            return "Arrive at the scheduled start time (\(timeFormatter.string(from: feedEvent.event.date)))."
        case .custom:
            return "Custom arrival: \(timeFormatter.string(from: customTime))."
        case .unsure:
            return "We'll mark your arrival time as TBD."
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick when you'll arrive")
                .font(.title3.bold())

            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "clock.badge.checkmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(feedEvent.event.title)
                        .font(.headline)
                    Text(eventDetailFormatter.string(from: feedEvent.event.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(feedEvent.event.location)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var arrivalOptionsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Arrival time")
                .font(.headline)

            Picker("Arrival", selection: $choice) {
                ForEach(Choice.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if choice == .custom {
                DatePicker(
                    "Custom arrival",
                    selection: $customTime,
                    in: allowedRange,
                    displayedComponents: [.hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text(summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private var attendeesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Friends heading over")
                .font(.headline)

            VStack(spacing: 12) {
                ForEach(Array(attendeeArrivals.prefix(4))) { badge in
                    attendeePreviewRow(for: badge)
                }

                if attendeeArrivals.count > 4 {
                    Text("+\(attendeeArrivals.count - 4) more planning to go")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func attendeePreviewRow(for badge: EventFeedViewModel.FeedEvent.FriendBadge) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(badge.friend.initials)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(badge.role == .me ? "You" : badge.friend.name)
                    .font(.subheadline.weight(.semibold))
                Text(arrivalText(for: badge))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let arrival = arrivalTime(for: badge) {
                Text(timeFormatter.string(from: arrival))
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            } else {
                Text("TBD")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var attendeeArrivals: [EventFeedViewModel.FeedEvent.FriendBadge] {
        feedEvent.badges
            .filter { $0.role == .going || $0.role == .me }
            .sorted { lhs, rhs in
                let lhsTime = arrivalTime(for: lhs) ?? Date.distantFuture
                let rhsTime = arrivalTime(for: rhs) ?? Date.distantFuture
                if lhsTime == rhsTime {
                    return lhs.friend.name < rhs.friend.name
                }
                return lhsTime < rhsTime
            }
    }

    private func arrivalTime(for badge: EventFeedViewModel.FeedEvent.FriendBadge) -> Date? {
        feedEvent.event.arrivalTimes[badge.friend.id]
    }

    private func arrivalText(for badge: EventFeedViewModel.FeedEvent.FriendBadge) -> String {
        if arrivalTime(for: badge) != nil {
            return badge.role == .me ? "Your current arrival plan" : "Shared arrival time"
        }
        return badge.role == .me ? "Set when you'll head over" : "Hasn't picked a time yet"
    }

    private func confirm() {
        let selectedTime: Date?
        switch choice {
        case .onTime:
            selectedTime = feedEvent.event.date
        case .custom:
            selectedTime = customTime
        case .unsure:
            selectedTime = nil
        }
        onConfirm(selectedTime)
        dismiss()
    }
}

private struct VerticalCarouselFallback: View {
    let feedEvents: [EventFeedViewModel.FeedEvent]
    let containerSize: CGSize
    let shareTapped: (EventFeedViewModel.FeedEvent) -> Void
    let rsvpTapped: (EventFeedViewModel.FeedEvent) -> Void
    let editTapped: (EventFeedViewModel.FeedEvent) -> Void
    let deleteTapped: (EventFeedViewModel.FeedEvent) -> Void
    let showAllTapped: (EventFeedViewModel.FeedEvent) -> Void

    var body: some View {
        TabView {
            ForEach(feedEvents) { feedEvent in
                EventCardView(
                    feedEvent: feedEvent,
                    shareAction: { shareTapped(feedEvent) },
                    rsvpAction: { rsvpTapped(feedEvent) },
                    editAction: feedEvent.isEditable ? { editTapped(feedEvent) } : nil,
                    deleteAction: feedEvent.isEditable ? { deleteTapped(feedEvent) } : nil,
                    showAllAttendees: feedEvent.badges.count > 2 ? { showAllTapped(feedEvent) } : nil
                )
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

private struct CreateEventView: View {
    @Environment(\.dismiss) private var dismiss
    let friends: [Friend]
    let onCreate: (String, String, Date, Date, CLLocationCoordinate2D?, URL, Event.Privacy, [UUID], Data?) -> Void

    @State private var title: String = ""
    @State private var location: String = ""
    @State private var eventDate: Date = Date().addingTimeInterval(60 * 60)
    @State private var eventEndDate: Date = Date().addingTimeInterval(60 * 60 * 3) // Default 3 hours later
    @State private var selectedPrivacy: Event.Privacy = .public
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var lookupStatus: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showLocationSearch = false

    private let geocoder = CLGeocoder()

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        eventEndDate > eventDate
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLocation: String {
        location.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EmailVerificationBanner()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section(header: Text("Details")) {
                    TextField("Event name", text: $title)

                    // Location field with search button
                    HStack {
                        TextField("Location", text: $location)
                        Button(action: { showLocationSearch = true }) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.blue)
                                .font(.body.weight(.medium))
                        }
                        .buttonStyle(.plain)
                    }

                    DatePicker("Start time", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End time", selection: $eventEndDate, displayedComponents: [.date, .hourAndMinute])

                    if eventEndDate <= eventDate {
                        Text("End time must be after start time")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("Location"), footer: lookupFooter) {
                    Button("Find in Apple Maps") {
                        geocodeLocation(openInMaps: true)
                    }
                    Button("Open in Google Maps") {
                        openInGoogleMaps()
                    }
                    if let coordinate = coordinate {
                        Map(
                            coordinateRegion: Binding(
                                get: {
                                    MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                                },
                                set: { region in
                                    self.coordinate = region.center
                                }
                            ),
                            annotationItems: [MapAnnotationItem(coordinate: coordinate)]
                        ) { item in
                            MapMarker(coordinate: item.coordinate)
                        }
                        .frame(height: 160)
                        .cornerRadius(12)
                    }
                }

                Section(header: Text("Appearance")) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            if let imageData = imageData, let image = UIImage(data: imageData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.title2)
                                    .frame(width: 56, height: 56)
                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                            }
                            Text(imageData == nil ? "Add cover photo" : "Change cover photo")
                        }
                    }
                }

                Section(header: Text("Visibility")) {
                    Picker("Privacy", selection: $selectedPrivacy) {
                        Text("Public").tag(Event.Privacy.public)
                        Text("Private").tag(Event.Privacy.private)
                    }
                    .pickerStyle(.segmented)

                    if selectedPrivacy == .private {
                        FriendSelectionView(friends: friends, selectedFriendIDs: $selectedFriendIDs)
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") { createEvent() }
                        .disabled(!isValid)
                }
            }
            .task(id: photoItem) {
                if let data = await loadImageData(from: photoItem) {
                    imageData = data
                }
            }
            .onChange(of: selectedPrivacy) { newValue in
                if newValue == .public {
                    selectedFriendIDs.removeAll()
                }
            }
            .sheet(isPresented: $showLocationSearch) {
                LocationSearchView(selectedLocation: $location, selectedCoordinate: $coordinate)
            }
        }
    }

    @ViewBuilder
    private var lookupFooter: some View {
        if let lookupStatus = lookupStatus {
            Text(lookupStatus)
        } else {
            Text("Use the options above to confirm the exact spot in Maps.")
        }
    }

    private func geocodeLocation(openInMaps: Bool) {
        guard !trimmedLocation.isEmpty else { return }
        lookupStatus = "Finding location..."
        geocoder.cancelGeocode()
        geocoder.geocodeAddressString(trimmedLocation) { placemarks, error in
            if let coordinate = placemarks?.first?.location?.coordinate {
                self.coordinate = coordinate
                lookupStatus = "Location found"
                if openInMaps {
                    let encoded = trimmedLocation.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                lookupStatus = "Couldn't find that place"
            }
        }
    }

    private func openInGoogleMaps() {
        guard !trimmedLocation.isEmpty else { return }
        let encoded = trimmedLocation.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.google.com/?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    private func createEvent() {
        let seed = UUID().uuidString
        let url = URL(string: "https://picsum.photos/seed/\(seed)/1400/900")!
        onCreate(trimmedTitle, trimmedLocation, eventDate, eventEndDate, coordinate, url, selectedPrivacy, Array(selectedFriendIDs), imageData)
        dismiss()
    }

    private func loadImageData(from item: PhotosPickerItem?) async -> Data? {
        guard let item = item else { return nil }
        return try? await item.loadTransferable(type: Data.self)
    }
}

private struct EditEventView: View {
    @Environment(\.dismiss) private var dismiss
    let feedEvent: EventFeedViewModel.FeedEvent
    let friends: [Friend]
    let onSave: (String, String, Date, CLLocationCoordinate2D?, Event.Privacy, [UUID], Data?) -> Void

    @State private var title: String
    @State private var location: String
    @State private var eventDate: Date
    @State private var selectedPrivacy: Event.Privacy
    @State private var selectedFriendIDs: Set<UUID>
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var lookupStatus: String?

    private let geocoder = CLGeocoder()

    init(feedEvent: EventFeedViewModel.FeedEvent, friends: [Friend], onSave: @escaping (String, String, Date, CLLocationCoordinate2D?, Event.Privacy, [UUID], Data?) -> Void) {
        self.feedEvent = feedEvent
        self.friends = friends
        self.onSave = onSave
        _title = State(initialValue: feedEvent.event.title)
        _location = State(initialValue: feedEvent.event.location)
        _eventDate = State(initialValue: feedEvent.event.date)
        _selectedPrivacy = State(initialValue: feedEvent.event.privacy)
        _selectedFriendIDs = State(initialValue: Set(feedEvent.event.sharedInviteFriendIDs))
        _coordinate = State(initialValue: feedEvent.event.coordinate)
        _imageData = State(initialValue: feedEvent.event.localImageData)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details")) {
                    TextField("Event name", text: $title)
                    TextField("Location", text: $location)
                    DatePicker("When", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section(header: Text("Location"), footer: lookupFooter) {
                    Button("Refine in Apple Maps") {
                        geocodeLocation(openInMaps: true)
                    }
                    Button("Open in Google Maps") {
                        openInGoogleMaps()
                    }
                    if let coordinate = coordinate {
                        Map(
                            coordinateRegion: Binding(
                                get: {
                                    MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                                },
                                set: { region in
                                    self.coordinate = region.center
                                }
                            ),
                            annotationItems: [MapAnnotationItem(coordinate: coordinate)]
                        ) { item in
                            MapMarker(coordinate: item.coordinate)
                        }
                        .frame(height: 160)
                        .cornerRadius(12)
                    }
                }

                Section(header: Text("Cover photo")) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            if let data = imageData ?? feedEvent.event.localImageData, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                AsyncImage(url: feedEvent.event.imageURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    default:
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Text("Change cover photo")
                        }
                    }
                }

                Section(header: Text("Visibility")) {
                    Picker("Privacy", selection: $selectedPrivacy) {
                        Text("Public").tag(Event.Privacy.public)
                        Text("Private").tag(Event.Privacy.private)
                    }
                    .pickerStyle(.segmented)

                    if selectedPrivacy == .private {
                        FriendSelectionView(friends: friends, selectedFriendIDs: $selectedFriendIDs)
                    }
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveChanges() }
                        .disabled(!isValid)
                }
            }
            .task(id: photoItem) {
                if let data = await loadImageData(from: photoItem) {
                    imageData = data
                }
            }
            .onChange(of: selectedPrivacy) { newValue in
                if newValue == .public {
                    selectedFriendIDs.removeAll()
                }
            }
        }
    }

    @ViewBuilder
    private var lookupFooter: some View {
        if let lookupStatus = lookupStatus {
            Text(lookupStatus)
        } else {
            Text("Confirm the location using Maps if needed.")
        }
    }

    private func geocodeLocation(openInMaps: Bool) {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lookupStatus = "Finding location..."
        geocoder.cancelGeocode()
        geocoder.geocodeAddressString(trimmed) { placemarks, _ in
            if let coordinate = placemarks?.first?.location?.coordinate {
                self.coordinate = coordinate
                lookupStatus = "Location found"
                if openInMaps {
                    let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                lookupStatus = "Couldn't find that place"
            }
        }
    }

    private func openInGoogleMaps() {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.google.com/?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    private func saveChanges() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedLocation.isEmpty else { return }
        onSave(trimmedTitle, trimmedLocation, eventDate, coordinate, selectedPrivacy, Array(selectedFriendIDs), imageData)
        dismiss()
    }

    private func loadImageData(from item: PhotosPickerItem?) async -> Data? {
        guard let item = item else { return nil }
        return try? await item.loadTransferable(type: Data.self)
    }
}

private struct FriendSelectionView: View {
    let friends: [Friend]
    @Binding var selectedFriendIDs: Set<UUID>

    var body: some View {
        if friends.isEmpty {
            Text("No friends available yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(friends) { friend in
                Button {
                    toggle(friend.id)
                } label: {
                    HStack {
                        Circle()
                            .fill(Color.blue.opacity(0.25))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(friend.initials)
                                    .font(.caption.weight(.semibold))
                            )
                        Text(friend.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedFriendIDs.contains(friend.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedFriendIDs.contains(id) {
            selectedFriendIDs.remove(id)
        } else {
            selectedFriendIDs.insert(id)
        }
    }
}

fileprivate struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
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

private struct SuccessToast: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)

            Text(text)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.30, green: 0.41, blue: 1.00), Color(red: 0.62, green: 0.26, blue: 0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 16, y: 10)
        .allowsHitTesting(false)
    }
}


// MARK: - Email Verification Banner
private struct EmailVerificationBanner: View {
    @State private var isResending = false
    @State private var showSuccess = false
    @State private var showError = false

    var body: some View {
        if let user = Auth.auth().currentUser, !user.isEmailVerified {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email Not Verified")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)

                        Text("Please verify your email to unlock all features")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()
                }

                if showSuccess {
                    Text("✓ Verification email sent!")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }

                if showError {
                    Text("Failed to send email. Try again.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }

                HStack(spacing: 12) {
                    Button(action: {
                        Task { await resendVerification() }
                    }) {
                        HStack(spacing: 6) {
                            if isResending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "envelope.fill")
                            }
                            Text("Resend Email")
                                .font(.caption.bold())
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .disabled(isResending)

                    Button(action: {
                        Task { await checkVerification() }
                    }) {
                        Text("I've Verified")
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                    )
            )
        }
    }

    private func resendVerification() async {
        guard let user = Auth.auth().currentUser else { return }

        isResending = true
        showSuccess = false
        showError = false

        do {
            try await user.sendEmailVerification()
            showSuccess = true
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showSuccess = false
        } catch {
            showError = true
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showError = false
        }

        isResending = false
    }

    private func checkVerification() async {
        guard let user = Auth.auth().currentUser else { return }

        do {
            try await user.reload()
            if user.isEmailVerified {
                NotificationCenter.default.post(name: NSNotification.Name("EmailVerified"), object: nil)
            }
        } catch {
            print("[Verification] Error reloading user: \(error)")
        }
    }
}

// MARK: - Modern Home Header
struct ModernHomeHeader: View {
    @Binding var selectedTab: ContentView.FeedTab
    @Binding var viewMode: ViewMode
    let onCreateTapped: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Discover")
                        .font(.largeTitle.bold())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .primary.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Find amazing events near you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // View mode toggle (only for Upcoming tab)
                if selectedTab == .upcoming {
                    HStack(spacing: 8) {
                        Button(action: { withAnimation(.spring(response: 0.3)) { viewMode = .cards } }) {
                            Image(systemName: viewMode == .cards ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                                .font(.title3)
                                .foregroundStyle(
                                    viewMode == .cards ?
                                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                        LinearGradient(colors: [.secondary, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                        }

                        Button(action: { withAnimation(.spring(response: 0.3)) { viewMode = .map } }) {
                            Image(systemName: viewMode == .map ? "map.fill" : "map")
                                .font(.title3)
                                .foregroundStyle(
                                    viewMode == .map ?
                                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                        LinearGradient(colors: [.secondary, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                        }
                    }
                    .transition(.opacity)
                }

                // Create button with gradient
                Button(action: onCreateTapped) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)

                        Image(systemName: "plus")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    }
                }
                .accessibilityLabel("Create event")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Modern segmented control
            HStack(spacing: 12) {
                ForEach(ContentView.FeedTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.rawValue)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)

                            if selectedTab == tab {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 3)
                                    .cornerRadius(1.5)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
}

// MARK: - Location Search View
import MapKit

private struct LocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLocation: String
    @Binding var selectedCoordinate: CLLocationCoordinate2D?

    @StateObject private var searchCompleter = LocationSearchCompleter()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.body.weight(.medium))

                    TextField("Search for a place", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { newValue in
                            searchCompleter.search(query: newValue)
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchCompleter.results = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.body.weight(.medium))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Results list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchCompleter.results, id: \.self) { result in
                            LocationSearchResultRow(
                                result: result,
                                onSelect: {
                                    selectLocation(result)
                                }
                            )
                        }
                    }
                }

                if searchCompleter.results.isEmpty && !searchText.isEmpty && !searchCompleter.isSearching {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No places found")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                if searchText.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "map")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Search for a location")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Type to start searching")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Find Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func selectLocation(_ result: MKLocalSearchCompletion) {
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)

        search.start { response, error in
            guard let placemark = response?.mapItems.first?.placemark else { return }

            // Build full address
            var addressComponents: [String] = []
            if let name = placemark.name {
                addressComponents.append(name)
            }
            if let locality = placemark.locality {
                addressComponents.append(locality)
            }
            if let administrativeArea = placemark.administrativeArea {
                addressComponents.append(administrativeArea)
            }

            selectedLocation = addressComponents.joined(separator: ", ")
            selectedCoordinate = placemark.coordinate
            dismiss()
        }
    }
}

private struct LocationSearchResultRow: View {
    let result: MKLocalSearchCompletion
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.15), .purple.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(
            Color(.systemBackground)
                .contentShape(Rectangle())
        )
        Divider()
            .padding(.leading, 68)
    }
}

// Location search completer to handle MKLocalSearchCompleter
@MainActor
private class LocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }

        isSearching = true
        completer.queryFragment = query
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            results = completer.results
            isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            results = []
            isSearching = false
            print("[LocationSearchCompleter] Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Events Map View
struct EventsMapView: View {
    let events: [EventFeedViewModel.FeedEvent]
    let onEventTapped: (EventFeedViewModel.FeedEvent) -> Void
    let onRSVPTapped: (EventFeedViewModel.FeedEvent) -> Void

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to SF
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var selectedEventId: UUID?
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ZStack(alignment: .bottom) {
            // Map with custom styling
            Map(coordinateRegion: $region, annotationItems: eventsWithCoordinates) { event in
                MapAnnotation(coordinate: event.event.coordinate ?? CLLocationCoordinate2D()) {
                    EventMapMarker(
                        event: event,
                        isSelected: selectedEventId == event.id,
                        onTap: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedEventId = event.id
                            }
                        }
                    )
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                centerMapOnEvents()
            }

            // Horizontally scrollable event cards at bottom
            if !eventsWithCoordinates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(eventsWithCoordinates) { event in
                            EventMapCard(
                                event: event,
                                isSelected: selectedEventId == event.id,
                                onTap: {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedEventId = event.id
                                        // Center map on selected event
                                        if let coordinate = event.event.coordinate {
                                            region.center = coordinate
                                        }
                                    }
                                },
                                onRSVP: {
                                    onRSVPTapped(event)
                                }
                            )
                            .frame(width: 320)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }

            // Recenter button
            VStack {
                HStack {
                    Spacer()
                    Button(action: centerMapOnEvents) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBackground))
                                .frame(width: 44, height: 44)
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)

                            Image(systemName: "location.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }
                Spacer()
            }
        }
    }

    private var eventsWithCoordinates: [EventFeedViewModel.FeedEvent] {
        events.filter { $0.event.coordinate != nil }
    }

    private func centerMapOnEvents() {
        guard !eventsWithCoordinates.isEmpty else {
            // Use user's location if available
            if let userLocation = locationManager.location {
                region = MKCoordinateRegion(
                    center: userLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            }
            return
        }

        let coordinates = eventsWithCoordinates.compactMap { $0.event.coordinate }

        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)
        )

        withAnimation {
            region = MKCoordinateRegion(center: center, span: span)
        }
    }
}

// MARK: - Event Map Marker
struct EventMapMarker: View {
    let event: EventFeedViewModel.FeedEvent
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer pulse effect when selected
                if isSelected {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .scaleEffect(isSelected ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isSelected)
                }

                // Main marker
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isSelected ? [.blue, .purple] : [.blue.opacity(0.9), .purple.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: isSelected ? 50 : 40, height: isSelected ? 50 : 40)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.3), radius: isSelected ? 12 : 6, y: 4)

                // Icon
                Image(systemName: "calendar")
                    .font(.system(size: isSelected ? 20 : 16, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Event Map Card
struct EventMapCard: View {
    let event: EventFeedViewModel.FeedEvent
    let isSelected: Bool
    let onTap: () -> Void
    let onRSVP: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Card content
                HStack(alignment: .top, spacing: 16) {
                    // Event image/icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "calendar")
                            .font(.system(size: 32))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.event.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Label(event.event.location, systemImage: "mappin.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Label(Self.dateFormatter.string(from: event.event.date), systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        // RSVP Button
                        Button(action: onRSVP) {
                            HStack(spacing: 6) {
                                Image(systemName: event.isAttending ? "checkmark.circle.fill" : "plus.circle.fill")
                                Text(event.isAttending ? "Going" : "Join Event")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: event.isAttending ? [.green, .green.opacity(0.8)] : [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                isSelected ?
                                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                    LinearGradient(colors: [.clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.black.opacity(0.15), radius: isSelected ? 25 : 20, y: 10)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
    }
}

