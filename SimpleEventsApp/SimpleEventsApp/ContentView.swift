import SwiftUI
import MapKit
import PhotosUI
import CoreLocation
import UIKit

@MainActor
struct ContentView: View {
    let appState: AppState
    @StateObject private var viewModel: EventFeedViewModel
    @State private var alertContext: AlertContext?
    @State private var showingCreateEvent = false
    @State private var editingEvent: EventFeedViewModel.FeedEvent?
    @State private var deleteTarget: EventFeedViewModel.FeedEvent?
    @State private var showAttendanceSheet: EventFeedViewModel.FeedEvent?

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
                                                EventCardView(
                                                    feedEvent: feedEvent,
                                                    shareAction: {
                                                        viewModel.beginShare(for: feedEvent)
                                                    },
                                                    rsvpAction: {
                                                        viewModel.toggleAttendance(for: feedEvent)
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
                                        viewModel.toggleAttendance(for: feedEvent)
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
            .navigationTitle("Upcoming Events")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingCreateEvent = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Create event")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileView()
                            .environmentObject(appState)
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
        .sheet(isPresented: $showingCreateEvent) {
            CreateEventView(friends: viewModel.friendOptions) { title, location, date, coordinate, imageURL, privacy, invitedIDs, imageData in
                viewModel.createEvent(
                    title: title,
                    location: location,
                    date: date,
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
        .environmentObject(appState)
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
                if let editAction, let deleteAction {
                    Menu {
                        Button("Edit", action: editAction)
                        Button("Delete", role: .destructive, action: deleteAction)
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(18)
                    }
                    .accessibilityLabel("Event actions")
                }
            }
            .overlay(alignment: .topTrailing) {
                privacyBadge
                    .padding(.top, 18)
                    .padding(.trailing, 24)
                    .offset(x: editAction == nil ? 0 : -50)
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

                if badges.count > 2, let onShowAll {
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

    var body: some View {
        NavigationStack {
            List {
                Section("People going") {
                    ForEach(feedEvent.badges.filter { $0.role == .going || $0.role == .me }) { badge in
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
        }
        .padding(.vertical, 4)
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
    let onCreate: (String, String, Date, CLLocationCoordinate2D?, URL, Event.Privacy, [UUID], Data?) -> Void

    @State private var title: String = ""
    @State private var location: String = ""
    @State private var eventDate: Date = Date().addingTimeInterval(60 * 60)
    @State private var selectedPrivacy: Event.Privacy = .public
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var lookupStatus: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?

    private let geocoder = CLGeocoder()

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                Section(header: Text("Details")) {
                    TextField("Event name", text: $title)
                    TextField("Location", text: $location)
                    DatePicker("When", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section(header: Text("Location"), footer: lookupFooter) {
                    Button("Find in Apple Maps") {
                        geocodeLocation(openInMaps: true)
                    }
                    Button("Open in Google Maps") {
                        openInGoogleMaps()
                    }
                    if let coordinate {
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
                            if let imageData, let image = UIImage(data: imageData) {
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
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
        }
    }

    @ViewBuilder
    private var lookupFooter: some View {
        if let lookupStatus {
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
        onCreate(trimmedTitle, trimmedLocation, eventDate, coordinate, url, selectedPrivacy, Array(selectedFriendIDs), imageData)
        dismiss()
    }

    private func loadImageData(from item: PhotosPickerItem?) async -> Data? {
        guard let item else { return nil }
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
                    if let coordinate {
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
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
        if let lookupStatus {
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
        guard let item else { return nil }
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
