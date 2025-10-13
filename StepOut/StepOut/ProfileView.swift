import SwiftUI
import UIKit
import CoreLocation
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

// MARK: - Remote profile transport models

struct RemoteProfileResponse {
    struct RemoteProfile {
        let userId: UUID
        let displayName: String
        let username: String?
        let bio: String?
        let photoURL: URL?
        let joinDate: Date?
        let primaryLocation: (latitude: Double, longitude: Double)?
        let stats: ProfileStats
    }

    struct RemoteFriend: Identifiable {
        let id: UUID
        let displayName: String
        let photoURL: URL?
        let status: String
    }

    struct RemoteInvite: Identifiable {
        enum Direction: String {
            case sent
            case received
        }

        let id: UUID
        let displayName: String
        let direction: Direction
        let contact: String?
    }

    struct RemoteAttendedEvent: Identifiable {
        let id: UUID
        let title: String
        let startAt: Date?
        let endAt: Date?
        let location: String
        let coverImagePath: String?
    }

    let profile: RemoteProfile
    let friends: [RemoteFriend]
    let pendingInvites: [RemoteInvite]
    let attendedEvents: [RemoteAttendedEvent]

    init?(dictionary: [String: Any]) {
        guard let profileDict = dictionary["profile"] as? [String: Any],
              let userIdString = profileDict["userId"] as? String,
              let userUUID = UUID(uuidString: userIdString) else { return nil }

        let displayName = profileDict["displayName"] as? String ?? "Friend"
        let username = profileDict["username"] as? String
        let bio = profileDict["bio"] as? String
        let photoURL = (profileDict["photoURL"] as? String).flatMap(URL.init(string:))

        let joinDate: Date?
        if let joinDateString = profileDict["joinDate"] as? String {
            joinDate = ISO8601DateFormatter().date(from: joinDateString)
        } else {
            joinDate = nil
        }

        let primaryLocation: (latitude: Double, longitude: Double)?
        if let locationDict = profileDict["primaryLocation"] as? [String: Any],
           let lat = locationDict["lat"] as? Double,
           let lng = locationDict["lng"] as? Double {
            primaryLocation = (lat, lng)
        } else {
            primaryLocation = nil
        }

        let statsDict = profileDict["stats"] as? [String: Any] ?? [:]
        let stats = ProfileStats(
            hostedCount: statsDict["hostedCount"] as? Int ?? 0,
            attendedCount: statsDict["attendedCount"] as? Int ?? 0,
            friendCount: statsDict["friendCount"] as? Int ?? 0,
            invitesSent: statsDict["invitesSent"] as? Int ?? 0
        )

        profile = RemoteProfile(
            userId: userUUID,
            displayName: displayName,
            username: username,
            bio: bio,
            photoURL: photoURL,
            joinDate: joinDate,
            primaryLocation: primaryLocation,
            stats: stats
        )

        if let friendsArray = dictionary["friends"] as? [[String: Any]] {
            friends = friendsArray.compactMap { item in
                guard let idString = item["id"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
                let name = item["displayName"] as? String ?? "Friend"
                let photoURL = (item["photoURL"] as? String).flatMap(URL.init(string:))
                let status = item["status"] as? String ?? "on-app"
                return RemoteFriend(id: uuid, displayName: name, photoURL: photoURL, status: status)
            }
        } else {
            friends = []
        }

        if let invitesArray = dictionary["pendingInvites"] as? [[String: Any]] {
            pendingInvites = invitesArray.compactMap { item in
                guard let idString = item["id"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
                let displayName = item["displayName"] as? String ?? "Friend"
                let directionRaw = item["direction"] as? String ?? "sent"
                let direction = RemoteInvite.Direction(rawValue: directionRaw) ?? .sent
                let contact = item["contact"] as? String
                return RemoteInvite(id: uuid, displayName: displayName, direction: direction, contact: contact)
            }
        } else {
            pendingInvites = []
        }

        if let attendedArray = dictionary["attendedEvents"] as? [[String: Any]] {
            attendedEvents = attendedArray.compactMap { item in
                guard let idString = item["eventId"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
                let title = item["title"] as? String ?? "Event"
                let location = item["location"] as? String ?? ""
                let coverImagePath = item["coverImagePath"] as? String
                let startAt = (item["startAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                let endAt = (item["endAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                return RemoteAttendedEvent(id: uuid, title: title, startAt: startAt, endAt: endAt, location: location, coverImagePath: coverImagePath)
            }
        } else {
            attendedEvents = []
        }
    }
}

// MARK: - Backend abstraction

protocol ProfileBackend {
    func fetchProfile(userId: UUID) async throws -> RemoteProfileResponse
    func updateProfile(userId: UUID, displayName: String, username: String?, bio: String?, primaryLocation: CLLocationCoordinate2D?) async throws -> RemoteProfileResponse
    func fetchAttendedEvents(userId: UUID, limit: Int) async throws -> [RemoteProfileResponse.RemoteAttendedEvent]
}

#if canImport(FirebaseFunctions)
final class FirebaseProfileBackend: ProfileBackend {
    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    func fetchProfile(userId: UUID) async throws -> RemoteProfileResponse {
        let callable = functions.httpsCallable("getProfile")
        let result = try await callable.call(["userId": userId.uuidString])
        guard let data = result.data as? [String: Any], let response = RemoteProfileResponse(dictionary: data) else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed getProfile response"])
        }
        return response
    }

    func updateProfile(userId: UUID, displayName: String, username: String?, bio: String?, primaryLocation: CLLocationCoordinate2D?) async throws -> RemoteProfileResponse {
        let callable = functions.httpsCallable("updateProfile")
        var payload: [String: Any] = ["userId": userId.uuidString, "displayName": displayName]
        if let username { payload["username"] = username }
        if let bio { payload["bio"] = bio }
        if let primaryLocation {
            payload["primaryLocation"] = ["lat": primaryLocation.latitude, "lng": primaryLocation.longitude]
        }
        let result = try await callable.call(payload)
        guard let data = result.data as? [String: Any], let response = RemoteProfileResponse(dictionary: data) else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed updateProfile response"])
        }
        return response
    }

    func fetchAttendedEvents(userId: UUID, limit: Int) async throws -> [RemoteProfileResponse.RemoteAttendedEvent] {
        let callable = functions.httpsCallable("listAttendedEvents")
        let result = try await callable.call(["userId": userId.uuidString, "limit": limit])
        guard let data = result.data as? [String: Any], let events = data["events"] as? [[String: Any]] else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed listAttendedEvents response"])
        }
        return events.compactMap { item in
            guard let idString = item["eventId"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
            let title = item["title"] as? String ?? "Event"
            let location = item["location"] as? String ?? ""
            let coverImagePath = item["coverImagePath"] as? String
            let startAt = (item["startAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            let endAt = (item["endAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            return RemoteProfileResponse.RemoteAttendedEvent(id: uuid, title: title, startAt: startAt, endAt: endAt, location: location, coverImagePath: coverImagePath)
        }
    }
}
#endif

struct MockProfileBackend: ProfileBackend {
    func fetchProfile(userId: UUID) async throws -> RemoteProfileResponse {
        let profile = ProfileRepository.sampleProfile
        let data: [String: Any] = [
            "profile": [
                "userId": profile.id.uuidString,
                "displayName": profile.displayName,
                "username": profile.username,
                "bio": profile.bio,
                "photoURL": profile.photoURL?.absoluteString as Any,
                "joinDate": ISO8601DateFormatter().string(from: profile.joinDate),
                "primaryLocation": profile.primaryLocation.map { ["lat": $0.coordinate.latitude, "lng": $0.coordinate.longitude] } as Any,
                "stats": [
                    "hostedCount": profile.stats.hostedCount,
                    "attendedCount": profile.stats.attendedCount,
                    "friendCount": profile.stats.friendCount,
                    "invitesSent": profile.stats.invitesSent
                ]
            ],
            "friends": profile.friends.map { friend in
                [
                    "id": friend.id.uuidString,
                    "displayName": friend.name,
                    "photoURL": friend.avatarURL?.absoluteString as Any,
                    "status": "on-app"
                ]
            },
            "pendingInvites": profile.pendingInvites.map { invite in
                [
                    "id": invite.id.uuidString,
                    "displayName": invite.name,
                    "direction": invite.direction.rawValue,
                    "contact": invite.contact as Any
                ]
            },
            "attendedEvents": profile.attendedEvents.map { event in
                [
                    "eventId": event.eventID.uuidString,
                    "title": "Event",
                    "startAt": ISO8601DateFormatter().string(from: event.date),
                    "endAt": ISO8601DateFormatter().string(from: event.date),
                    "location": "",
                    "coverImagePath": event.coverImageURL?.absoluteString as Any
                ]
            }
        ]

        guard let response = RemoteProfileResponse(dictionary: data) else {
            throw NSError(domain: "MockProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed mock profile data"])
        }
        return response
    }

    func updateProfile(userId: UUID, displayName: String, username: String?, bio: String?, primaryLocation: CLLocationCoordinate2D?) async throws -> RemoteProfileResponse {
        try await fetchProfile(userId: userId)
    }

    func fetchAttendedEvents(userId: UUID, limit: Int) async throws -> [RemoteProfileResponse.RemoteAttendedEvent] {
        let response = try await fetchProfile(userId: userId)
        return Array(response.attendedEvents.prefix(limit))
    }
}

// MARK: - View model

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let backend: ProfileBackend
    private let userId: UUID

    init(userId: UUID = UserSession.sample.user.id, backend: ProfileBackend? = nil) {
        self.userId = userId
#if canImport(FirebaseFunctions)
        self.backend = backend ?? FirebaseProfileBackend()
#else
        self.backend = backend ?? MockProfileBackend()
#endif

#if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            profile = ProfileRepository.sampleProfile
        }
#endif
    }

    func loadProfile() async {
        // Only show loading if we don't have a profile yet
        let shouldShowLoading = profile == nil
        if shouldShowLoading {
            isLoading = true
        }
        defer {
            if shouldShowLoading {
                isLoading = false
            }
        }

        do {
            let response = try await backend.fetchProfile(userId: userId)
            profile = mapResponse(response)
            errorMessage = nil
            logDebug("loadProfile succeeded", extra: [
                "friends": profile?.friends.count ?? 0,
                "attended": profile?.attendedEvents.count ?? 0
            ])
        } catch {
            logFailure(context: "loadProfile", error: error)
            errorMessage = readableMessage(for: error)
#if DEBUG
            profile = ProfileRepository.sampleProfile
#endif
        }
    }

    func refreshAttendedEvents(limit: Int = 25) async {
        guard profile != nil else { return }
        do {
            let events = try await backend.fetchAttendedEvents(userId: userId, limit: limit)
            profile?.attendedEvents = events.map { convertAttendedEvent($0) }
            errorMessage = nil
            logDebug("refreshAttendedEvents succeeded", extra: ["count": events.count])
        } catch {
            logFailure(context: "refreshAttendedEvents", error: error)
            errorMessage = readableMessage(for: error)
        }
    }

    func saveProfile(displayName: String, username: String?, bio: String?, primaryLocation: CLLocationCoordinate2D?) async {
        do {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            var sanitizedUsername: String?
            if let username, username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
                sanitizedUsername = clean.hasPrefix("@") ? String(clean.dropFirst()) : clean
            }
            let response = try await backend.updateProfile(
                userId: userId,
                displayName: trimmed,
                username: sanitizedUsername,
                bio: bio,
                primaryLocation: primaryLocation
            )
            profile = mapResponse(response)
            errorMessage = nil
            logDebug("saveProfile succeeded", extra: [
                "displayName": trimmed,
                "username": sanitizedUsername ?? "(nil)"
            ])
        } catch {
            logFailure(context: "saveProfile", error: error)
            errorMessage = readableMessage(for: error)
        }
    }

    private func mapResponse(_ response: RemoteProfileResponse) -> UserProfile {
        let base = response.profile

        let friends = response.friends.map { Friend(id: $0.id, name: $0.displayName, avatarURL: $0.photoURL) }

        let pendingInvites = response.pendingInvites.map { invite in
            PendingInvite(
                id: invite.id,
                name: invite.displayName,
                direction: invite.direction == .sent ? .sent : .received,
                contact: invite.contact
            )
        }

        let attendedEvents = response.attendedEvents.map { convertAttendedEvent($0) }

        let usernameValue: String
        if let username = base.username, username.isEmpty == false {
            usernameValue = username.hasPrefix("@") ? username : "@\(username)"
        } else {
            usernameValue = "@stepout"
        }

        return UserProfile(
            id: base.userId,
            displayName: base.displayName,
            username: usernameValue,
            bio: base.bio ?? "Tap to add a bio",
            joinDate: base.joinDate ?? Date(),
            primaryLocation: base.primaryLocation.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) },
            photoURL: base.photoURL,
            friends: friends,
            pendingInvites: pendingInvites,
            attendedEvents: attendedEvents,
            stats: base.stats
        )
    }

    private func convertAttendedEvent(_ event: RemoteProfileResponse.RemoteAttendedEvent) -> AttendedEvent {
        AttendedEvent(
            eventID: event.id,
            date: event.startAt ?? Date(),
            title: event.title,
            location: event.location,
            startAt: event.startAt,
            endAt: event.endAt,
            coverImageName: nil,
            coverImageURL: event.coverImagePath.flatMap(URL.init(string:))
        )
    }

    private func readableMessage(for error: Error) -> String {
        let nsError = error as NSError
        if let details = nsError.userInfo[NSLocalizedDescriptionKey] as? String, details.isEmpty == false {
            return details
        }
        if let details = nsError.userInfo["message"] as? String, details.isEmpty == false {
            return details
        }
        return "Something went wrong loading your profile. Please try again."
    }

    private func logFailure(context: String, error: Error) {
        let nsError = error as NSError
        print("[Profile] \(context) failed:", nsError.domain, nsError.code, nsError.localizedDescription, nsError.userInfo)
    }

    private func logDebug(_ message: String, extra: [String: Any] = [:]) {
#if DEBUG
        print("[Profile]", message, extra)
#endif
    }
}

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    private let calendar = ProfileRepository.calendar
    private let focusMonth = ProfileRepository.focusMonth

    @StateObject private var viewModel = ProfileViewModel()
    @State private var showSettings = false
    @State private var showFriends = false
    @State private var showEditProfile = false
    @State private var selectedDayEvents: [AttendedEvent]?
    @State private var selectedDate: Date?

    var body: some View {
        content
        .background(Color(.systemBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings.toggle() } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                }
                .accessibilityLabel("Open settings")
            }
        }
        .task {
            await viewModel.loadProfile()
        }
        .sheet(isPresented: $showFriends) {
            if let profile = viewModel.profile {
                FriendsSheetView(
                    friends: profile.friends,
                    pendingInvites: profile.pendingInvites
                )
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showEditProfile) {
            if let profile = viewModel.profile {
                EditProfileSheetView(profile: profile) { updatedName, updatedUsername, updatedBio in
                    Task {
                        await viewModel.saveProfile(
                            displayName: updatedName,
                            username: updatedUsername.isEmpty ? nil : updatedUsername,
                            bio: updatedBio,
                            primaryLocation: nil
                        )
                    }
                } onResetPassword: {
                    viewModel.errorMessage = "Password resets will be enabled once authentication is live."
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showSettings) {
            VStack(spacing: 16) {
                Text("Settings")
                    .font(.headline)
                Text("Settings will be available once auth is enabled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Close") { showSettings = false }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .presentationDetents([.medium])
        }
        .alert("Heads up", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { value in
            if !value { viewModel.errorMessage = nil }
        })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { selectedDayEvents != nil },
            set: { if !$0 { selectedDayEvents = nil; selectedDate = nil } }
        )) {
            if let events = selectedDayEvents, let date = selectedDate {
                DayEventsSheetView(date: date, events: events)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let profile = viewModel.profile {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection(profile: profile)
                    actionRow(profile: profile)
                    calendarSection(profile: profile)
                    statsStrip(profile: profile)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .refreshable {
                await viewModel.loadProfile()
            }
        } else if viewModel.isLoading {
            VStack(spacing: 16) {
                ProgressView("Loading profile…")
                Text("Pulling your profile details")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                Text("We couldn’t load your profile")
                    .font(.headline)
                Button("Retry") {
                    Task { await viewModel.loadProfile() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func headerSection(profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.displayName)
                        .font(.title.bold())
                    Text(profile.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                    if profile.bio.isEmpty == false {
                        Text(profile.bio)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                avatarView(for: profile)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func actionRow(profile: UserProfile) -> some View {
        HStack(spacing: 18) {
            Button { showFriends.toggle() } label: {
                actionButtonLabel(
                    systemImage: "person.2.fill",
                    title: "\(profile.friends.count) Friends"
                )
            }
            .buttonStyle(.plain)

            Button { showEditProfile.toggle() } label: {
                actionButtonLabel(
                    systemImage: "pencil",
                    title: "Edit Profile"
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private func actionButtonLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
            Text(title)
                .font(.headline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(.primary)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func calendarSection(profile: UserProfile) -> some View {
        ProfileCalendarView(
            month: focusMonth,
            calendar: calendar,
            attendedEvents: profile.attendedEvents,
            onDayTapped: { day, events in
                selectedDate = calendar.date(from: DateComponents(
                    year: calendar.component(.year, from: focusMonth),
                    month: calendar.component(.month, from: focusMonth),
                    day: day
                ))
                selectedDayEvents = events
            }
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func statsStrip(profile: UserProfile) -> some View {
        HStack(spacing: 24) {
            statTile(
                icon: "heart.fill",
                title: "Attended",
                value: "\(profile.stats.attendedCount)"
            )

            statTile(
                icon: "flame.fill",
                title: "Hosted",
                value: "\(profile.stats.hostedCount)"
            )

            statTile(
                icon: "person.2.wave.2.fill",
                title: "Invites",
                value: "\(profile.stats.invitesSent)"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func statTile(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.primary)
            Text(value)
                .font(.headline.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func avatarView(for profile: UserProfile) -> some View {
        if let url = profile.photoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    placeholderAvatar(text: initials(for: profile.displayName))
                case .failure:
                    placeholderAvatar(text: initials(for: profile.displayName))
                @unknown default:
                    placeholderAvatar(text: initials(for: profile.displayName))
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(Circle())
        } else {
            placeholderAvatar(text: initials(for: profile.displayName))
                .frame(width: 68, height: 68)
        }
    }

    private func placeholderAvatar(text: String) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.8), .blue.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(text)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            )
    }

    private func initials(for name: String) -> String {
        let components = name.split(separator: " ").compactMap { $0.first }
        return String(components.prefix(2)).uppercased()
    }
}

private struct ProfileCalendarView: View {
    let month: Date
    let calendar: Calendar
    let attendedEvents: [AttendedEvent]
    let onDayTapped: (Int, [AttendedEvent]) -> Void

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    private var weekdaySymbols: [String] {
        calendar.shortWeekdaySymbols.map { String($0.prefix(1)) }
    }

    private var eventsByDay: [Int: [AttendedEvent]] {
        Dictionary(grouping: attendedEvents) { event in
            calendar.component(.day, from: event.date)
        }
    }

    private var dayGrid: [Int?] {
        let monthInterval = calendar.dateInterval(of: .month, for: month) ?? .init(start: month, duration: 0)
        let days = Array(calendar.range(of: .day, in: .month, for: month) ?? 1..<31)
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        let leadingEmpty = Array(repeating: Optional<Int>.none, count: leadingCount)
        let trailingEmptyCount: Int = {
            let total = leadingEmpty.count + days.count
            let remainder = total % 7
            return remainder == 0 ? 0 : 7 - remainder
        }()
        let trailingEmpty = Array(repeating: Optional<Int>.none, count: trailingEmptyCount)
        return leadingEmpty + days.map { Optional($0) } + trailingEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(monthFormatter.string(from: month))
                .font(.title3.bold())

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 12) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .id("weekday-\(index)")
                }

                ForEach(Array(dayGrid.enumerated()), id: \.offset) { offset, day in
                    CalendarDayCell(
                        day: day,
                        events: day.flatMap { eventsByDay[$0] } ?? []
                    )
                    .id("day-\(offset)")
                    .onTapGesture {
                        if let day = day {
                            let events = eventsByDay[day] ?? []
                            if !events.isEmpty {
                                onDayTapped(day, events)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CalendarDayCell: View {
    let day: Int?
    let events: [AttendedEvent]

    var body: some View {
        VStack(spacing: 6) {
            if let day {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.tertiarySystemBackground))
                        .frame(width: 40, height: 40)

                    if let event = events.first {
                        eventThumbnail(for: event)
                    }

                    if events.count > 1 {
                        Text("\(events.count)")
                            .font(.caption2.bold())
                            .padding(4)
                            .background(Color.black.opacity(0.75), in: Circle())
                            .foregroundStyle(.white)
                            .offset(x: 12, y: 12)
                    }
                }
                Text("\(day)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Color.clear
                    .frame(height: 48)
            }
        }
    }

    @ViewBuilder
    private func eventThumbnail(for event: AttendedEvent) -> some View {
        if let coverURL = event.coverImageURL {
            AsyncImage(url: coverURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    placeholder
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else if let coverName = event.coverImageName, UIImage(named: coverName) != nil {
            Image(coverName)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: 2)
                )
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.orange.opacity(0.8), .pink.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.white)
            )
    }
}

private struct FriendsSheetView: View {
    let friends: [Friend]
    let pendingInvites: [PendingInvite]

    var body: some View {
        NavigationStack {
            List {
                Section("Friends on StepOut") {
                    if friends.isEmpty {
                        Text("No friends yet. Send invites to start building your circle.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(friends) { friend in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.blue.opacity(0.16))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(friend.initials)
                                            .font(.caption.weight(.bold))
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.name)
                                        .font(.headline)
                                    Text("On StepOut")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Pending invites") {
                    if pendingInvites.isEmpty {
                        Text("No invites in flight.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pendingInvites) { invite in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.orange.opacity(0.14))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(invite.name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined())
                                            .font(.caption.weight(.bold))
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(invite.name)
                                        .font(.headline)
                                    Text(invite.direction == .sent ? "Invite sent" : "Awaiting your response")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let contact = invite.contact {
                                    Text(contact)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Your friends")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct EditProfileSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let profile: UserProfile
    let onSave: (String, String, String) -> Void
    let onResetPassword: () -> Void

    @State private var displayName: String
    @State private var username: String
    @State private var bio: String

    init(profile: UserProfile, onSave: @escaping (String, String, String) -> Void, onResetPassword: @escaping () -> Void) {
        self.profile = profile
        self.onSave = onSave
        self.onResetPassword = onResetPassword
        _displayName = State(initialValue: profile.displayName)
        let usernameValue = profile.username.hasPrefix("@") ? String(profile.username.dropFirst()) : profile.username
        _username = State(initialValue: usernameValue)
        _bio = State(initialValue: profile.bio)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Profile")) {
                    TextField("Display name", text: $displayName)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section {
                    Button("Reset password") {
                        onResetPassword()
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(displayName.trimmed(), username.trimmed(), bio)
                        dismiss()
                    }
                    .disabled(displayName.trimmed().isEmpty)
                }
            }
        }
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Day Events Sheet
private struct DayEventsSheetView: View {
    let date: Date
    let events: [AttendedEvent]
    @Environment(\.dismiss) private var dismiss
    @Namespace private var animation

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        eventsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(dateFormatter.string(from: date))
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("\(events.count) event\(events.count == 1 ? "" : "s") attended")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var eventsSection: some View {
        VStack(spacing: 16) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                EventCard(event: event, index: index)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }
}

private struct EventCard: View {
    let event: AttendedEvent
    let index: Int

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }

    var body: some View {
        HStack(spacing: 16) {
            eventImage

            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)

                Label {
                    Text(event.location)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "location.fill")
                        .font(.caption)
                }

                if let startAt = event.startAt {
                    Label {
                        Text(timeFormatter.string(from: startAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.05), value: event.id)
    }

    @ViewBuilder
    private var eventImage: some View {
        if let coverURL = event.coverImageURL {
            AsyncImage(url: coverURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    placeholderGradient
                @unknown default:
                    placeholderGradient
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if let coverName = event.coverImageName, UIImage(named: coverName) != nil {
            Image(coverName)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            placeholderGradient
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var placeholderGradient: some View {
        LinearGradient(
            colors: [
                Color(hue: Double(index) * 0.15, saturation: 0.7, brightness: 0.9),
                Color(hue: Double(index) * 0.15 + 0.1, saturation: 0.6, brightness: 0.7)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
        )
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ProfileView()
                .environmentObject(AppState())
        }
    }
}
