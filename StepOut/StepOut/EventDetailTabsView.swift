import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct EventDetailTabsView: View {
    let feedEvent: EventFeedViewModel.FeedEvent
    let currentUserId: String
    let isEventOwner: Bool
    let onContentModerated: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var photosViewModel: EventPhotosViewModel
    @StateObject private var commentsViewModel: EventPhotosViewModel
    @StateObject private var blockedUsersManager = BlockedUsersManager()
    @State private var showReportAlert = false
    @State private var reportSubmitted = false
    @State private var showBlockAlert = false
    @State private var userBlocked = false

    init(feedEvent: EventFeedViewModel.FeedEvent, currentUserId: String, isEventOwner: Bool, onContentModerated: (() -> Void)? = nil) {
        self.feedEvent = feedEvent
        self.currentUserId = currentUserId
        self.isEventOwner = isEventOwner
        self.onContentModerated = onContentModerated
        _photosViewModel = StateObject(wrappedValue: EventPhotosViewModel(currentUserId: currentUserId))
        _commentsViewModel = StateObject(wrappedValue: EventPhotosViewModel(currentUserId: currentUserId))
    }

    var body: some View {
        NavigationStack {
            contentWithAlerts
                .navigationTitle(feedEvent.event.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        closeButton
                    }

                    if !isEventOwner {
                        ToolbarItem(placement: .primaryAction) {
                            actionsMenu
                        }
                    }
                }
        }
    }

    private var contentWithAlerts: some View {
        tabContent
            .alert("Report Event", isPresented: $showReportAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Report as Inappropriate", role: .destructive) {
                    reportEvent()
                }
            } message: {
                Text("Report this event for inappropriate content? We will review it within 24 hours.")
            }
            .alert("Report Submitted", isPresented: $reportSubmitted) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Thank you for your report. We will review this content within 24 hours.")
            }
            .alert("Block Event Owner?", isPresented: $showBlockAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Block", role: .destructive) {
                    blockUser()
                }
            } message: {
                Text("They will no longer be able to see your events or interact with you. You won't see their events in your feed.")
            }
            .alert("User Blocked", isPresented: $userBlocked) {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("The event owner has been blocked. Their events will no longer appear in your feed.")
            }
            .task {
                // Preload photos and comments as soon as view appears
                async let photosLoad: Void = photosViewModel.loadPhotos(for: feedEvent.event.id.uuidString)
                async let commentsLoad: Void = commentsViewModel.loadComments(for: feedEvent.event.id.uuidString)
                _ = await (photosLoad, commentsLoad)
            }
    }

    private func reportEvent() {
        print("[EventDetailTabsView] 🚨 reportEvent() called")
        print("[EventDetailTabsView] 📍 Event ID: \(feedEvent.event.id.uuidString)")
        print("[EventDetailTabsView] 👤 Reporter ID: \(currentUserId)")

        #if canImport(FirebaseFirestore)
        Task {
            do {
                let db = Firestore.firestore()

                print("[EventDetailTabsView] ✅ Firebase initialized, creating report document...")

                // Create the report
                let reportRef = try await db.collection("reports").addDocument(data: [
                    "type": "event",
                    "eventId": feedEvent.event.id.uuidString,
                    "reportedBy": currentUserId,
                    "reason": "inappropriate_content",
                    "timestamp": FieldValue.serverTimestamp()
                ])

                print("[EventDetailTabsView] ✅ Report created with ID: \(reportRef.documentID)")

                // Hide the event from the reporter's feed by adding to their hidden events
                try await db.collection("users").document(currentUserId)
                    .collection("hiddenEvents").document(feedEvent.event.id.uuidString)
                    .setData([
                        "hiddenAt": FieldValue.serverTimestamp(),
                        "reason": "reported"
                    ])

                print("[EventDetailTabsView] ✅ Event hidden in Firebase: users/\(currentUserId)/hiddenEvents/\(feedEvent.event.id.uuidString)")

                await MainActor.run {
                    print("[EventDetailTabsView] ✅ Showing report submitted confirmation")
                    reportSubmitted = true

                    // Trigger feed refresh
                    print("[EventDetailTabsView] 🔄 Calling onContentModerated to refresh feed")
                    onContentModerated?()

                    // Close the sheet after reporting
                    dismiss()
                }
            } catch {
                print("[EventDetailTabsView] ❌ ERROR reporting event: \(error.localizedDescription)")
                print("[EventDetailTabsView] ❌ Full error: \(error)")
            }
        }
        #else
        print("[EventDetailTabsView] ⚠️ Firebase not available - cannot report event")
        #endif
    }

    private var tabContent: some View {
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
    }

    private var closeButton: some View {
        Button("Close") {
            dismiss()
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button(role: .destructive) {
                showReportAlert = true
            } label: {
                Label("Report Event", systemImage: "exclamationmark.triangle")
            }

            Button(role: .destructive) {
                showBlockAlert = true
            } label: {
                Label("Block Event Owner", systemImage: "hand.raised.fill")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.primary)
        }
    }

    private func blockUser() {
        print("[EventDetailTabsView] 🚫 blockUser() called")
        print("[EventDetailTabsView] 📍 Event ID: \(feedEvent.event.id.uuidString)")
        print("[EventDetailTabsView] 👤 Current User ID: \(currentUserId)")

        #if canImport(FirebaseFirestore)
        guard let eventOwnerId = feedEvent.event.ownerId else {
            print("[EventDetailTabsView] ❌ ERROR: No owner ID for event")
            return
        }

        print("[EventDetailTabsView] 🎯 Blocking user: \(eventOwnerId)")

        Task {
            do {
                let db = Firestore.firestore()

                print("[EventDetailTabsView] ✅ Firebase initialized, blocking user...")

                // Block the user
                try await db.collection("users").document(currentUserId)
                    .collection("blocked").document(eventOwnerId)
                    .setData([
                        "blockedAt": FieldValue.serverTimestamp()
                    ])

                print("[EventDetailTabsView] ✅ User blocked in Firebase: users/\(currentUserId)/blocked/\(eventOwnerId)")

                // Update the blocked users manager
                await MainActor.run {
                    print("[EventDetailTabsView] ✅ Updating blocked users manager")
                    blockedUsersManager.blockedUsers.insert(eventOwnerId)
                    userBlocked = true
                    print("[EventDetailTabsView] ✅ Showing user blocked confirmation")

                    // Trigger feed refresh
                    print("[EventDetailTabsView] 🔄 Calling onContentModerated to refresh feed")
                    onContentModerated?()
                }
            } catch {
                print("[EventDetailTabsView] ❌ ERROR blocking user: \(error.localizedDescription)")
                print("[EventDetailTabsView] ❌ Full error: \(error)")
            }
        }
        #else
        print("[EventDetailTabsView] ⚠️ Firebase not available - cannot block user")
        #endif
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

                    // Friends Going
                    if !feedEvent.cardBadges.isEmpty {
                        Text("Friends Going")
                            .font(.headline)

                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(feedEvent.cardBadges.prefix(10)) { badge in
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
