import SwiftUI
import UIKit
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
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
        let phoneNumber: String?
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

    // Convert Firebase UID (string) to UUID for compatibility with existing code
    static func uuidFromFirebaseUID(_ uid: String) -> UUID {
        // Hash the Firebase UID to create a consistent UUID
        var hasher = Hasher()
        hasher.combine(uid)
        let hash = abs(hasher.finalize())

        // Convert hash to UUID format
        let uuidString = String(format: "%08X-%04X-%04X-%04X-%012X",
                               (hash >> 96) & 0xFFFFFFFF,
                               (hash >> 80) & 0xFFFF,
                               (hash >> 64) & 0xFFFF,
                               (hash >> 48) & 0xFFFF,
                               hash & 0xFFFFFFFFFFFF)

        return UUID(uuidString: uuidString) ?? UUID()
    }

    init?(dictionary: [String: Any]) {
        print("🔴 [RemoteProfileResponse] init called with dictionary keys: \(dictionary.keys.joined(separator: ", "))")

        guard let profileDict = dictionary["profile"] as? [String: Any],
              let userIdString = profileDict["userId"] as? String else {
            print("🔴 [RemoteProfileResponse] init FAILED - missing profile dict or userId")
            return nil
        }

        // Convert Firebase UID to UUID (Firebase UIDs are not valid UUIDs)
        let userUUID: UUID
        if let uuid = UUID(uuidString: userIdString) {
            // Already a valid UUID
            userUUID = uuid
        } else {
            // Convert Firebase UID to deterministic UUID
            userUUID = Self.uuidFromFirebaseUID(userIdString)
        }

        let displayName = profileDict["displayName"] as? String ?? "Friend"
        let username = profileDict["username"] as? String
        let bio = profileDict["bio"] as? String
        let phoneNumber = profileDict["phoneNumber"] as? String
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
            phoneNumber: phoneNumber,
            photoURL: photoURL,
            joinDate: joinDate,
            primaryLocation: primaryLocation,
            stats: stats
        )

        if let friendsArray = dictionary["friends"] as? [[String: Any]] {
            friends = friendsArray.compactMap { item in
                guard let idString = item["id"] as? String else { return nil }
                let uuid = UUID(uuidString: idString) ?? Self.uuidFromFirebaseUID(idString)
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
                guard let idString = item["id"] as? String else { return nil }
                let uuid = UUID(uuidString: idString) ?? Self.uuidFromFirebaseUID(idString)
                let displayName = item["displayName"] as? String ?? "Friend"
                let directionRaw = item["direction"] as? String ?? "sent"
                let direction = RemoteInvite.Direction(rawValue: directionRaw) ?? .sent
                let contact = item["contact"] as? String
                return RemoteInvite(id: uuid, displayName: displayName, direction: direction, contact: contact)
            }
        } else {
            pendingInvites = []
        }

        print("🔴 [RemoteProfileResponse] About to parse attendedEvents...")
        print("🔴 [RemoteProfileResponse] attendedEvents value type: \(type(of: dictionary["attendedEvents"]))")

        if let attendedArray = dictionary["attendedEvents"] as? [[String: Any]] {
            print("🔴 [RemoteProfileResponse] Successfully cast to [[String: Any]], parsing \(attendedArray.count) events")

            #if DEBUG
            print("[RemoteProfileResponse] Parsing \(attendedArray.count) attended events from dictionary")
            #endif

            attendedEvents = attendedArray.compactMap { item in
                guard let idString = item["eventId"] as? String else {
                    print("🔴 [RemoteProfileResponse] ⚠️ Skipping event - missing eventId")
                    return nil
                }
                let uuid = UUID(uuidString: idString) ?? Self.uuidFromFirebaseUID(idString)
                let title = item["title"] as? String ?? "Event"
                let location = item["location"] as? String ?? ""
                let coverImagePath = item["coverImagePath"] as? String

                let startAtString = item["startAt"] as? String
                let startAt = startAtString.flatMap { dateString in
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return formatter.date(from: dateString)
                }
                let endAt = (item["endAt"] as? String).flatMap { dateString in
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return formatter.date(from: dateString)
                }

                print("🔴 [RemoteProfileResponse] Event '\(title)' - startAt string: '\(startAtString ?? "nil")', parsed date: \(startAt?.description ?? "nil")")

                return RemoteAttendedEvent(id: uuid, title: title, startAt: startAt, endAt: endAt, location: location, coverImagePath: coverImagePath)
            }

            print("🔴 [RemoteProfileResponse] Successfully parsed \(attendedEvents.count) attended events")
        } else {
            #if DEBUG
            print("[RemoteProfileResponse] ⚠️ No attendedEvents array in dictionary. Dictionary keys: \(dictionary.keys.joined(separator: ", "))")
            #endif
            attendedEvents = []
        }
    }
}

// MARK: - Backend abstraction

protocol ProfileBackend {
    func fetchProfile(firebaseUID: String) async throws -> RemoteProfileResponse
    func updateProfile(firebaseUID: String, displayName: String, username: String?, bio: String?, phoneNumber: String?, primaryLocation: CLLocationCoordinate2D?) async throws -> RemoteProfileResponse
    func fetchAttendedEvents(firebaseUID: String, limit: Int) async throws -> [RemoteProfileResponse.RemoteAttendedEvent]
}

#if canImport(FirebaseFunctions)
final class FirebaseProfileBackend: ProfileBackend {
    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    func fetchProfile(firebaseUID: String) async throws -> RemoteProfileResponse {
        let callable = functions.httpsCallable("getProfile")
        let result = try await callable.call(["userId": firebaseUID])
        guard let data = result.data as? [String: Any], let response = RemoteProfileResponse(dictionary: data) else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed getProfile response"])
        }
        return response
    }

    func updateProfile(firebaseUID: String, displayName: String, username: String?, bio: String?, phoneNumber: String?, primaryLocation: CLLocationCoordinate2D?) async throws -> RemoteProfileResponse {
        let callable = functions.httpsCallable("updateProfile")
        var payload: [String: Any] = ["userId": firebaseUID, "displayName": displayName]
        if let username { payload["username"] = username }
        if let bio { payload["bio"] = bio }
        if let phoneNumber { payload["phoneNumber"] = phoneNumber }
        if let primaryLocation {
            payload["primaryLocation"] = ["lat": primaryLocation.latitude, "lng": primaryLocation.longitude]
        }
        print("[Backend] updateProfile payload: \(payload)")
        let result = try await callable.call(payload)
        print("[Backend] updateProfile response received")
        guard let data = result.data as? [String: Any], let response = RemoteProfileResponse(dictionary: data) else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed updateProfile response"])
        }
        return response
    }

    func fetchAttendedEvents(firebaseUID: String, limit: Int) async throws -> [RemoteProfileResponse.RemoteAttendedEvent] {
        let callable = functions.httpsCallable("listAttendedEvents")
        let result = try await callable.call(["userId": firebaseUID, "limit": limit])
        guard let data = result.data as? [String: Any], let events = data["events"] as? [[String: Any]] else {
            throw NSError(domain: "FirebaseProfileBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed listAttendedEvents response"])
        }
        return events.compactMap { item in
            guard let idString = item["eventId"] as? String else { return nil }
            let uuid = UUID(uuidString: idString) ?? RemoteProfileResponse.uuidFromFirebaseUID(idString)
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
    func fetchProfile(firebaseUID: String) async throws -> RemoteProfileResponse {
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

    func updateProfile(firebaseUID: String, displayName: String, username: String?, bio: String?, phoneNumber: String?, primaryLocation: CLLocationCoordinate2D?) async throws -> RemoteProfileResponse {
        try await fetchProfile(firebaseUID: firebaseUID)
    }

    func fetchAttendedEvents(firebaseUID: String, limit: Int) async throws -> [RemoteProfileResponse.RemoteAttendedEvent] {
        let response = try await fetchProfile(firebaseUID: firebaseUID)
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
    private let firebaseUID: String
    private static var cachedProfile: UserProfile?
    private static var cachedProfileUID: String?
    private static var lastFetchTime: Date?

    init(firebaseUID: String, backend: ProfileBackend? = nil) {
        self.firebaseUID = firebaseUID
#if canImport(FirebaseFunctions)
        self.backend = backend ?? FirebaseProfileBackend()
        print("🟢 [ProfileViewModel] init - Using FirebaseProfileBackend for firebaseUID: \(firebaseUID)")
#else
        self.backend = backend ?? MockProfileBackend()
        print("🟡 [ProfileViewModel] init - Using MockProfileBackend for firebaseUID: \(firebaseUID)")
#endif

        // Load from cache if available for this user
        if Self.cachedProfileUID == firebaseUID, let cached = Self.cachedProfile {
            profile = cached
            print("[ProfileViewModel] 📦 Loaded profile from cache")
        }

#if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            profile = ProfileRepository.sampleProfile
            print("🔵 [ProfileViewModel] init - Using sample profile for preview")
        }
#endif
    }

    func loadProfile() async {
        #if DEBUG
        print("[Profile] 🔵 loadProfile called for firebaseUID: \(firebaseUID)")
        #endif

        // Only show loading if we don't have cached data
        let shouldShowLoading = Self.cachedProfile == nil
        if shouldShowLoading {
            isLoading = true
        }
        defer {
            if shouldShowLoading {
                isLoading = false
            }
        }

        do {
            #if DEBUG
            print("[Profile] 🔵 Fetching profile from backend...")
            #endif

            let response = try await backend.fetchProfile(firebaseUID: firebaseUID)

            #if DEBUG
            print("[Profile] 🔵 Backend returned profile with \(response.attendedEvents.count) events")
            #endif

            let loadedProfile = mapResponse(response)

            // Update both the published property and cache
            profile = loadedProfile
            Self.cachedProfile = loadedProfile
            Self.cachedProfileUID = firebaseUID
            Self.lastFetchTime = Date()

            errorMessage = nil
            logDebug("loadProfile succeeded", extra: [
                "friends": profile?.friends.count ?? 0,
                "pendingInvites": profile?.pendingInvites.count ?? 0,
                "attended": profile?.attendedEvents.count ?? 0
            ])
            print("✅ [ProfileView] Loaded profile with \(profile?.pendingInvites.count ?? 0) pending invites")
            profile?.pendingInvites.forEach { invite in
                print("  - \(invite.direction.rawValue): \(invite.name)")
            }

            #if DEBUG
            print("[Profile] ✅ Profile loaded successfully with \(profile?.attendedEvents.count ?? 0) attended events")
            #endif
        } catch {
            logFailure(context: "loadProfile", error: error)
            errorMessage = readableMessage(for: error)

            // Keep showing cached data if backend fails
            if Self.cachedProfileUID == firebaseUID, let cached = Self.cachedProfile {
                print("[ProfileViewModel] 🔄 Using cached data due to error")
            } else {
#if DEBUG
                print("[Profile] ❌ Failed to load profile, using sample profile")
                profile = ProfileRepository.sampleProfile
#endif
            }
        }
    }

    func refreshAttendedEvents(limit: Int = 25) async {
        guard profile != nil else { return }
        do {
            let events = try await backend.fetchAttendedEvents(firebaseUID: firebaseUID, limit: limit)
            profile?.attendedEvents = events.map { convertAttendedEvent($0) }
            errorMessage = nil
            logDebug("refreshAttendedEvents succeeded", extra: ["count": events.count])
        } catch {
            logFailure(context: "refreshAttendedEvents", error: error)
            errorMessage = readableMessage(for: error)
        }
    }

    func saveProfile(displayName: String, username: String?, bio: String?, phoneNumber: String?, primaryLocation: CLLocationCoordinate2D?) async {
        do {
            print("[Profile] 🔵 saveProfile called with phoneNumber: '\(phoneNumber ?? "nil")'")
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            var sanitizedUsername: String?
            if let username, username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
                sanitizedUsername = clean.hasPrefix("@") ? String(clean.dropFirst()) : clean
            }
            print("[Profile] 🔵 Calling backend.updateProfile with phoneNumber: '\(phoneNumber ?? "nil")'")
            let response = try await backend.updateProfile(
                firebaseUID: firebaseUID,
                displayName: trimmed,
                username: sanitizedUsername,
                bio: bio,
                phoneNumber: phoneNumber,
                primaryLocation: primaryLocation
            )
            print("[Profile] ✅ Backend updateProfile succeeded")
            profile = mapResponse(response)
            errorMessage = nil
            logDebug("saveProfile succeeded", extra: [
                "displayName": trimmed,
                "username": sanitizedUsername ?? "(nil)",
                "phoneNumber": phoneNumber ?? "(nil)"
            ])
        } catch {
            print("[Profile] ❌ saveProfile failed: \(error.localizedDescription)")
            logFailure(context: "saveProfile", error: error)
            errorMessage = readableMessage(for: error)
        }
    }

    private func mapResponse(_ response: RemoteProfileResponse) -> UserProfile {
        let base = response.profile

        #if DEBUG
        print("[Profile] mapResponse - received \(response.attendedEvents.count) attended events from backend")
        #endif

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

        #if DEBUG
        print("[Profile] mapResponse - converted \(attendedEvents.count) attended events")
        #endif

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
            phoneNumber: base.phoneNumber,
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
        // Use startAt as the primary date
        let eventDate = event.startAt ?? Date()

        #if DEBUG
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        print("[Profile] Converting attended event '\(event.title)' - startAt: \(event.startAt.map { formatter.string(from: $0) } ?? "nil"), using date: \(formatter.string(from: eventDate))")
        #endif

        return AttendedEvent(
            eventID: event.id,
            date: eventDate,
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
    let authManager: AuthenticationManager?

    @StateObject private var viewModel: ProfileViewModel
    @State private var showSettings = false
    @State private var showFriends = false
    @State private var showEditProfile = false
    @State private var showUnifiedFriends = false
    @State private var selectedDayEvents: [AttendedEvent]?
    @State private var selectedDate: Date?
    @State private var showSignOutConfirmation = false
    @State private var pendingRequestsCount = 0
    @State private var showPhoneNumberPrompt = false
    @State private var focusMonth = Date()
    @State private var isEmailVerified = Auth.auth().currentUser?.isEmailVerified ?? true

    init(authManager: AuthenticationManager? = nil) {
        self.authManager = authManager

        // Get firebaseUID from authManager if authenticated, otherwise use a placeholder
        // The backend requires the Firebase UID to query user data correctly
        let firebaseUID = authManager?.currentSession?.firebaseUID ?? "unknown"
        _viewModel = StateObject(wrappedValue: ProfileViewModel(firebaseUID: firebaseUID))
    }

    var body: some View {
        let _ = print("🟣 [ProfileView] body rendering - viewModel.profile events count: \(viewModel.profile?.attendedEvents.count ?? -1)")

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

            // Check if user needs to add phone number
            if let profile = viewModel.profile, profile.phoneNumber == nil || profile.phoneNumber?.isEmpty == true {
                // Show prompt after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    showPhoneNumberPrompt = true
                }
            }

            // Listen for pending friend requests
            if let firebaseUID = authManager?.currentSession?.firebaseUID {
                Firestore.firestore().collection("invites")
                    .whereField("recipientUserId", isEqualTo: firebaseUID)
                    .whereField("status", isEqualTo: "pending")
                    .addSnapshotListener { snapshot, _ in
                        pendingRequestsCount = snapshot?.documents.count ?? 0
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EmailVerified"))) { _ in
            // Reload user data and update verification status
            Task {
                do {
                    try await Auth.auth().currentUser?.reload()
                    await MainActor.run {
                        isEmailVerified = Auth.auth().currentUser?.isEmailVerified ?? false
                    }
                } catch {
                    print("[ProfileView] Failed to reload user: \(error)")
                }
            }
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
                EditProfileSheetView(profile: profile) { updatedName, updatedUsername, updatedBio, updatedPhone in
                    Task {
                        await viewModel.saveProfile(
                            displayName: updatedName,
                            username: updatedUsername.isEmpty ? nil : updatedUsername,
                            bio: updatedBio,
                            phoneNumber: updatedPhone.isEmpty ? nil : updatedPhone,
                            primaryLocation: nil
                        )
                    }
                } onResetPassword: {
                    viewModel.errorMessage = "Password resets will be enabled once authentication is live."
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showUnifiedFriends) {
            if let firebaseUID = authManager?.currentSession?.firebaseUID {
                UnifiedFriendsView(userId: firebaseUID)
            }
        }
        .sheet(isPresented: $showSettings) {
            ModernSettingsView(
                appState: appState,
                authManager: authManager,
                showSignOutConfirmation: $showSignOutConfirmation,
                onDismiss: { showSettings = false },
                onSignOut: {
                    authManager?.signOut()
                    showSettings = false
                }
            )
            .alert("Sign Out", isPresented: $showSignOutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    authManager?.signOut()
                    showSettings = false
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
        .alert("Heads up", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { value in
            if !value { viewModel.errorMessage = nil }
        })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Add Phone Number", isPresented: $showPhoneNumberPrompt) {
            Button("Add Now") {
                showEditProfile = true
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Add your phone number to connect with friends on StepOut!")
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
            ZStack {
                // Modern gradient background matching home page
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

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        modernHeaderSection(profile: profile)
                        modernActionRow(profile: profile)
                        calendarSection(profile: profile)
                        modernStatsStrip(profile: profile)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await viewModel.loadProfile()
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
                .blur(radius: !isEmailVerified ? 10 : 0)
                .allowsHitTesting(isEmailVerified)

                // Email verification overlay
                if !isEmailVerified {
                    EmailVerificationOverlay()
                }
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

    // MARK: - Modern Sections

    private func modernHeaderSection(profile: UserProfile) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.displayName)
                    .font(.title.bold())
                    .lineLimit(1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, .primary.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text(profile.username)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)
                if profile.bio != "Tap to add a bio" && profile.bio.isEmpty == false {
                    Text(profile.bio)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            Spacer()
            modernAvatarView(for: profile)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 108)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .blue.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }

    private func modernAvatarView(for profile: UserProfile) -> some View {
        Group {
            if let url = profile.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure, _:
                        modernPlaceholderAvatar(text: initials(for: profile.displayName))
                    }
                }
                .clipShape(Circle())
            } else {
                modernPlaceholderAvatar(text: initials(for: profile.displayName))
            }
        }
        .frame(width: 68, height: 68)
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        )
        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private func modernPlaceholderAvatar(text: String) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.blue, .purple],
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

    private func modernActionRow(profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            Button { showUnifiedFriends.toggle() } label: {
                ZStack(alignment: .topTrailing) {
                    modernActionButtonLabel(
                        systemImage: "person.2.fill",
                        title: "\(profile.friends.count) Friends"
                    )

                    // Modern notification badge
                    if pendingRequestsCount > 0 {
                        Text("\(pendingRequestsCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                LinearGradient(
                                    colors: [.red, .red.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color(.systemBackground), lineWidth: 2)
                            )
                            .offset(x: 8, y: -8)
                            .shadow(color: .red.opacity(0.4), radius: 4, y: 2)
                    }
                }
            }
            .buttonStyle(.plain)

            Button { showEditProfile.toggle() } label: {
                modernActionButtonLabel(
                    systemImage: "pencil",
                    title: "Edit Profile"
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(height: 44)
    }

    private func modernActionButtonLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .blue.opacity(0.1), radius: 6, x: 0, y: 2)
        )
    }

    private func modernStatsStrip(profile: UserProfile) -> some View {
        HStack(spacing: 20) {
            modernStatTile(
                icon: "heart.fill",
                title: "Attended",
                value: "\(profile.stats.attendedCount)",
                gradient: [.pink, .red]
            )

            modernStatTile(
                icon: "flame.fill",
                title: "Hosted",
                value: "\(profile.stats.hostedCount)",
                gradient: [.orange, .red]
            )

            modernStatTile(
                icon: "person.2.wave.2.fill",
                title: "Invites",
                value: "\(profile.stats.invitesSent)",
                gradient: [.blue, .purple]
            )
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.15), .purple.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .blue.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }

    private func modernStatTile(icon: String, title: String, value: String, gradient: [Color]) -> some View {
        VStack(spacing: 8) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradient.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: gradient[0].opacity(0.3), radius: 6, y: 2)

            Text(value)
                .font(.title2.bold())
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .primary.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Legacy Sections (kept for compatibility)

    private func headerSection(profile: UserProfile) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.displayName)
                    .font(.title.bold())
                    .lineLimit(1)
                Text(profile.username)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                if profile.bio != "Tap to add a bio" && profile.bio.isEmpty == false {
                    Text(profile.bio)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            Spacer()
            avatarView(for: profile)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 108)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func actionRow(profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            Button { showUnifiedFriends.toggle() } label: {
                ZStack(alignment: .topTrailing) {
                    actionButtonLabel(
                        systemImage: "person.2.fill",
                        title: "\(profile.friends.count) Friends"
                    )

                    // Notification badge
                    if pendingRequestsCount > 0 {
                        Text("\(pendingRequestsCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -8)
                    }
                }
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
        .frame(height: 44) // Fixed height for consistency
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
            month: $focusMonth,
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
        .padding(20)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
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
        .frame(maxWidth: .infinity, minHeight: 90)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func statTile(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.primary)
                .frame(height: 18)
            Text(value)
                .font(.headline.bold())
                .frame(height: 20)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity)
    }

    private func avatarView(for profile: UserProfile) -> some View {
        Group {
            if let url = profile.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure, _:
                        placeholderAvatar(text: initials(for: profile.displayName))
                    }
                }
                .clipShape(Circle())
            } else {
                placeholderAvatar(text: initials(for: profile.displayName))
            }
        }
        .frame(width: 68, height: 68)
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
    @Binding var month: Date
    let calendar: Calendar
    let attendedEvents: [AttendedEvent]
    let onDayTapped: (Int, [AttendedEvent]) -> Void

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: month) {
            month = newMonth
        }
    }

    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: month) {
            month = newMonth
        }
    }

    private var weekdaySymbols: [String] {
        calendar.shortWeekdaySymbols.map { String($0.prefix(1)) }
    }

    private var eventsByDay: [Int: [AttendedEvent]] {
        #if DEBUG
        print("[Calendar] Displaying month: \(calendar.component(.month, from: month))/\(calendar.component(.year, from: month))")
        print("[Calendar] Total events: \(attendedEvents.count)")

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        attendedEvents.forEach { event in
            print("[Calendar]   - '\(event.title)' on \(formatter.string(from: event.date))")
        }
        #endif

        // First filter events that belong to the displayed month/year
        let eventsInMonth = attendedEvents.filter { event in
            let eventYear = calendar.component(.year, from: event.date)
            let eventMonth = calendar.component(.month, from: event.date)
            let displayYear = calendar.component(.year, from: month)
            let displayMonth = calendar.component(.month, from: month)
            return eventYear == displayYear && eventMonth == displayMonth
        }

        #if DEBUG
        print("[Calendar] Events in current month: \(eventsInMonth.count)")
        #endif

        // Then group by day
        return Dictionary(grouping: eventsInMonth) { event in
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
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color(.tertiarySystemBackground))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthFormatter.string(from: month))
                    .font(.title3.bold())
                    .frame(height: 24)

                Spacer()

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color(.tertiarySystemBackground))
                        )
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 12) {
                // Weekday headers
                HStack(spacing: 10) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                        Text(symbol.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 16)

                // Calendar grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 12) {
                    ForEach(Array(dayGrid.enumerated()), id: \.offset) { offset, day in
                        CalendarDayCell(
                            day: day,
                            events: day.flatMap { eventsByDay[$0] } ?? []
                        )
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
        .fixedSize(horizontal: false, vertical: true)
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
                    .frame(width: 40, height: 54)
            }
        }
        .frame(height: 60) // Fixed height for all cells
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
#if DEBUG
                    Text("Debug: \(pendingInvites.count) invites loaded")
                        .font(.caption2)
                        .foregroundStyle(.orange)
#endif
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
    let onSave: (String, String, String, String) -> Void
    let onResetPassword: () -> Void

    @State private var displayName: String
    @State private var username: String
    @State private var bio: String
    @State private var phoneNumber: String

    init(profile: UserProfile, onSave: @escaping (String, String, String, String) -> Void, onResetPassword: @escaping () -> Void) {
        self.profile = profile
        self.onSave = onSave
        self.onResetPassword = onResetPassword
        _displayName = State(initialValue: profile.displayName)
        let usernameValue = profile.username.hasPrefix("@") ? String(profile.username.dropFirst()) : profile.username
        _username = State(initialValue: usernameValue)
        _bio = State(initialValue: profile.bio)
        _phoneNumber = State(initialValue: profile.phoneNumber ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Photo Section
                    VStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                                .overlay {
                                    Text(displayName.prefix(1))
                                        .font(.system(size: 40, weight: .bold))
                                        .foregroundColor(.white)
                                }

                            Button(action: {
                                // TODO: Add photo upload
                            }) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                    }
                            }
                        }

                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // Form Fields
                    VStack(spacing: 20) {
                        // Display Name
                        ModernTextField(
                            title: "Display Name",
                            placeholder: "Your name",
                            text: $displayName,
                            icon: "person.fill"
                        )

                        // Username
                        ModernTextField(
                            title: "Username",
                            placeholder: "username",
                            text: $username,
                            icon: "at"
                        )
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                        // Bio
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Bio", systemImage: "text.alignleft")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)

                            TextField("Tell us about yourself", text: $bio, axis: .vertical)
                                .lineLimit(3...6)
                                .frame(minHeight: 100)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.secondarySystemBackground))
                                )
                        }

                        // Phone Number
                        PhoneNumberField(
                            phoneNumber: $phoneNumber
                        )

                        // Actions
                        VStack(spacing: 12) {
                            Button(action: {
                                print("[Profile] 🔵 Save button tapped - phone: '\(phoneNumber)'")
                                onSave(displayName.trimmed(), username.trimmed(), bio, phoneNumber.trimmed())
                                dismiss()
                            }) {
                                Text("Save Changes")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(saveButtonBackground)
                                    .cornerRadius(12)
                            }
                            .disabled(displayName.trimmed().isEmpty)

                            Button(action: {
                                onResetPassword()
                            }) {
                                Text("Reset Password")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var saveButtonBackground: some ShapeStyle {
        if displayName.trimmed().isEmpty {
            return AnyShapeStyle(Color.gray)
        } else {
            return AnyShapeStyle(LinearGradient(
                colors: [.blue, .purple],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
    }
}

// Modern Text Field Component
private struct ModernTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .frame(height: 56)
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }
}

// Phone Number Field with Country Code
private struct PhoneNumberField: View {
    @Binding var phoneNumber: String
    @State private var selectedCountryCode = "+1"
    @State private var numberWithoutCode = ""
    @State private var showCountryPicker = false

    private let countryCodes = [
        ("+1", "🇺🇸 United States / Canada"),
        ("+44", "🇬🇧 United Kingdom"),
        ("+91", "🇮🇳 India"),
        ("+86", "🇨🇳 China"),
        ("+81", "🇯🇵 Japan"),
        ("+49", "🇩🇪 Germany"),
        ("+33", "🇫🇷 France"),
        ("+61", "🇦🇺 Australia"),
        ("+82", "🇰🇷 South Korea"),
        ("+52", "🇲🇽 Mexico"),
        ("+55", "🇧🇷 Brazil"),
        ("+7", "🇷🇺 Russia"),
        ("+39", "🇮🇹 Italy"),
        ("+34", "🇪🇸 Spain"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Phone Number", systemImage: "phone.fill")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                // Country Code Picker
                Button(action: { showCountryPicker.toggle() }) {
                    HStack(spacing: 4) {
                        Text(selectedCountryCode)
                            .font(.body)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                }

                // Phone Number Input
                TextField("2137065381", text: $numberWithoutCode)
                    .keyboardType(.numberPad)
                    .onChange(of: numberWithoutCode) { newValue in
                        // Format and update the full phone number
                        let cleaned = newValue.filter { $0.isNumber }
                        numberWithoutCode = cleaned
                        phoneNumber = selectedCountryCode + cleaned
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
            }

            // Format hint
            Text("Format: \(selectedCountryCode) followed by your number")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            // Parse existing phone number
            if !phoneNumber.isEmpty {
                // Find matching country code
                if let match = countryCodes.first(where: { phoneNumber.hasPrefix($0.0) }) {
                    selectedCountryCode = match.0
                    numberWithoutCode = String(phoneNumber.dropFirst(selectedCountryCode.count))
                }
            }
        }
        .onChange(of: selectedCountryCode) { newCode in
            phoneNumber = newCode + numberWithoutCode
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryCodePickerView(
                selectedCountryCode: $selectedCountryCode,
                countryCodes: countryCodes,
                dismiss: { showCountryPicker = false }
            )
        }
    }
}

// Country Code Picker View
private struct CountryCodePickerView: View {
    @Binding var selectedCountryCode: String
    let countryCodes: [(String, String)]
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(countryCodes, id: \.0) { code, name in
                    Button(action: {
                        selectedCountryCode = code
                        dismiss()
                    }) {
                        HStack {
                            Text(name)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedCountryCode == code {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
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

// MARK: - Email Verification Overlay
private struct EmailVerificationOverlay: View {
    @State private var isResending = false
    @State private var isChecking = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 120, height: 120)

                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                }

                // Message
                VStack(spacing: 12) {
                    Text("Verify Your Email")
                        .font(.title.bold())
                        .foregroundColor(.white)

                    Text("You must verify your email before accessing this feature")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                if let message = message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(message.contains("✓") ? .green : .red)
                        .transition(.opacity)
                }

                // Buttons
                VStack(spacing: 16) {
                    Button(action: {
                        Task { await checkVerification() }
                    }) {
                        HStack {
                            if isChecking {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("I've Verified My Email")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isChecking)

                    Button(action: {
                        Task { await resendVerification() }
                    }) {
                        HStack {
                            if isResending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            } else {
                                Image(systemName: "envelope.fill")
                            }
                            Text("Resend Verification Email")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                    }
                    .disabled(isResending)
                }
                .padding(.horizontal, 40)

                Spacer()
            }
        }
    }

    private func resendVerification() async {
        guard let user = Auth.auth().currentUser else { return }

        isResending = true
        message = nil

        do {
            try await user.sendEmailVerification()
            message = "✓ Verification email sent! Check your inbox."
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            message = nil
        } catch {
            message = "Failed to send email. Try again."
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            message = nil
        }

        isResending = false
    }

    private func checkVerification() async {
        guard let user = Auth.auth().currentUser else { return }

        isChecking = true
        message = nil

        do {
            try await user.reload()
            if user.isEmailVerified {
                message = "✓ Email verified successfully!"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // Force refresh the entire app
                NotificationCenter.default.post(name: NSNotification.Name("EmailVerified"), object: nil)
            } else {
                message = "Email not verified yet. Please check your inbox and click the link."
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                message = nil
            }
        } catch {
            message = "Error checking verification. Try again."
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            message = nil
        }

        isChecking = false
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

// MARK: - Modern Settings View
private struct ModernSettingsView: View {
    @ObservedObject var appState: AppState
    let authManager: AuthenticationManager?
    @Binding var showSignOutConfirmation: Bool
    @State private var showDeleteAccountConfirmation = false
    let onDismiss: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                // Modern gradient background
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

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)

                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            .shadow(color: .blue.opacity(0.2), radius: 8, y: 4)

                            Text("Settings")
                                .font(.title.bold())
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.primary, .primary.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .padding(.top, 20)

                        // Appearance Section
                        ModernSettingsSection(title: "Appearance", icon: "paintbrush.fill", iconGradient: [.blue, .purple]) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Theme")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)

                                Picker("Theme", selection: $appState.selectedTheme) {
                                    ForEach(AppState.AppTheme.allCases) { theme in
                                        Text(theme.title).tag(theme)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        // Social Section
                        ModernSettingsSection(title: "Social", icon: "person.2.fill", iconGradient: [.green, .blue]) {
                            NavigationLink(destination: EventPreferencesView(isOnboarding: false, onComplete: nil)) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.green.opacity(0.2), .blue.opacity(0.2)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 40, height: 40)

                                        Image(systemName: "star.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [.green, .blue],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }

                                    Text("Event Preferences")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(.tertiarySystemBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Safety & Privacy Section
                        ModernSettingsSection(title: "Safety & Privacy", icon: "hand.raised.fill", iconGradient: [.purple, .pink]) {
                            NavigationLink {
                                if let currentUserId = authManager?.currentSession?.firebaseUID {
                                    BlockedUsersView(
                                        currentUserId: currentUserId,
                                        onUnblock: {
                                            print("[ModernSettingsView] 🔄 User unblocked, triggering feed refresh")
                                            // Post notification to refresh feed
                                            NotificationCenter.default.post(name: NSNotification.Name("RefreshFeed"), object: nil)
                                        }
                                    )
                                } else {
                                    Text("Unable to load blocked users")
                                        .foregroundColor(.secondary)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.purple.opacity(0.2), .pink.opacity(0.2)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 40, height: 40)

                                        Image(systemName: "hand.raised.slash.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [.purple, .pink],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }

                                    Text("Blocked Users")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(.tertiarySystemBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Account Section
                        ModernSettingsSection(title: "Account", icon: "person.crop.circle.fill", iconGradient: [.red, .orange]) {
                            Button(action: { showSignOutConfirmation = true }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.red.opacity(0.2), .orange.opacity(0.2)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 40, height: 40)

                                        Image(systemName: "arrow.right.square.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [.red, .orange],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }

                                    Text("Sign Out")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(.tertiarySystemBackground))
                                )
                            }
                            .buttonStyle(.plain)

                            // Delete Account Button
                            Button(action: { showDeleteAccountConfirmation = true }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.red.opacity(0.3), .pink.opacity(0.3)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 40, height: 40)

                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [.red, .pink],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }

                                    Text("Delete Account")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.red)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(.tertiarySystemBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDismiss) {
                        ZStack {
                            Circle()
                                .fill(Color(.tertiarySystemBackground))
                                .frame(width: 32, height: 32)

                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .alert("Delete Account", isPresented: $showDeleteAccountConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("Are you sure you want to permanently delete your account? This action cannot be undone. All your events, profile data, and connections will be permanently removed.")
            }
        }
    }

    private func deleteAccount() {
        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        Task {
            do {
                // Get current user
                guard let user = Auth.auth().currentUser else { return }
                let userId = user.uid

                // Delete user data from Firestore
                let db = Firestore.firestore()

                // Delete user profile
                try await db.collection("users").document(userId).delete()

                // Delete user's events
                let eventsSnapshot = try await db.collection("events")
                    .whereField("ownerId", isEqualTo: userId)
                    .getDocuments()

                for document in eventsSnapshot.documents {
                    try await document.reference.delete()
                }

                // Delete from Firebase Auth
                try await user.delete()

                // Sign out
                await MainActor.run {
                    onSignOut()
                }
            } catch {
                print("Error deleting account: \(error.localizedDescription)")
            }
        }
        #else
        onSignOut()
        #endif
    }
}

private struct ModernSettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let iconGradient: [Color]
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(
                        LinearGradient(
                            colors: iconGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: iconGradient.map { $0.opacity(0.2) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: iconGradient[0].opacity(0.1), radius: 12, x: 0, y: 4)
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
