import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth
import Contacts

// MARK: - Friend Request Model
struct FriendRequest: Identifiable {
    let id: String
    let senderId: String
    let senderName: String
    let senderPhotoURL: String?
    let direction: Direction

    enum Direction {
        case incoming // Someone sent you a request
        case outgoing // You sent a request
    }
}

// Unified Friends View - Like Instagram/LinkedIn
struct UnifiedFriendsView: View {
    @StateObject private var viewModel = UnifiedFriendsViewModel()
    @StateObject private var contactsManager = ContactsManager()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var showSuccessToast = false
    @State private var successMessage = ""

    let userId: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom Tab Picker
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Picker("", selection: $selectedTab) {
                            Text("Requests").tag(0)
                            Text("Friends").tag(1)
                            Text("Find Friends").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding()

                        // Badge overlay on Requests tab
                        let totalRequests = viewModel.incomingRequestsCount + viewModel.outgoingRequestsCount
                        if totalRequests > 0 {
                            Text("\(totalRequests)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: geometry.size.width / 6 + 45, y: 8)
                        }
                    }
                }
                .frame(height: 60)

                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case 0:
                        requestsTab
                    case 1:
                        friendsTab
                    case 2:
                        findFriendsTab
                    default:
                        requestsTab
                    }
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.startListening(userId: userId)
                contactsManager.checkPermission()
                contactsManager.startListeningToOutgoingRequests(currentUserId: userId)
                contactsManager.startListeningToFriends(currentUserId: userId)

                // Auto-fetch if permission already granted
                if contactsManager.permissionStatus == .authorized && contactsManager.contacts.isEmpty {
                    print("[UnifiedFriends] Permission already granted, fetching contacts...")
                    Task {
                        await contactsManager.fetchContacts()
                    }
                }
            }
            .onDisappear {
                viewModel.stopListening()
                contactsManager.stopListeningToOutgoingRequests()
                contactsManager.stopListeningToFriends()
            }
            .overlay(alignment: .top) {
                if showSuccessToast {
                    VStack {
                        HStack(spacing: 12) {
                            Image(systemName: successMessage.contains("Failed") || successMessage.contains("error") ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .font(.title3)
                            Text(successMessage)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            successMessage.contains("Failed") || successMessage.contains("error") ?
                            LinearGradient(colors: [Color.red.opacity(0.95), Color.red.opacity(0.85)], startPoint: .leading, endPoint: .trailing) :
                            LinearGradient(colors: [Color.green.opacity(0.95), Color.green.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal)
                        .padding(.top, 60)
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showSuccessToast)
                }
            }
        }
    }

    // MARK: - Requests Tab
    private var requestsTab: some View {
        List {
            if !viewModel.incomingRequests.isEmpty {
                Section("Friend Requests") {
                    ForEach(viewModel.incomingRequests) { request in
                        IncomingRequestRow(request: request, viewModel: viewModel)
                    }
                }
            }

            if !viewModel.outgoingRequests.isEmpty {
                Section("Sent Requests") {
                    ForEach(viewModel.outgoingRequests) { request in
                        OutgoingRequestRow(request: request, viewModel: viewModel)
                    }
                }
            }

            if viewModel.incomingRequests.isEmpty && viewModel.outgoingRequests.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No pending requests")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Friends Tab
    private var friendsTab: some View {
        List {
            if viewModel.friends.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No friends yet")
                            .foregroundColor(.secondary)
                        Text("Find friends from your contacts!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                ForEach(viewModel.friends) { friend in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay {
                                Text(friend.displayName.prefix(1))
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(friend.displayName)
                                .font(.headline)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Find Friends Tab
    private var findFriendsTab: some View {
        Group {
            if contactsManager.permissionStatus == .notDetermined || contactsManager.permissionStatus == .denied {
                permissionView
            } else if contactsManager.isLoading {
                ProgressView("Loading contacts...")
            } else if contactsManager.contacts.isEmpty {
                VStack {
                    emptyContactsView
                }
                .onAppear {
                    // Fetch contacts when this view appears if we have permission
                    if contactsManager.permissionStatus == .authorized {
                        print("[UnifiedFriends] Contacts empty but permission granted, fetching...")
                        Task {
                            await contactsManager.fetchContacts()
                        }
                    }
                }
            } else {
                contactsList
            }
        }
    }

    private var permissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Find Friends on StepOut")
                .font(.title2.bold())

            Text("Connect with friends who are already using StepOut by accessing your contacts.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button(action: {
                Task {
                    await contactsManager.requestPermission()
                    if contactsManager.permissionStatus == .authorized {
                        await contactsManager.fetchContacts()
                    }
                }
            }) {
                Text("Allow Access to Contacts")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private var emptyContactsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Contacts Found")
                .font(.headline)

            Text("Make sure you have contacts saved on your device")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var contactsList: some View {
        List {
            let filteredContacts = searchText.isEmpty ? contactsManager.contacts : contactsManager.contacts.filter { contact in
                let fullName = "\(contact.contact.givenName) \(contact.contact.familyName)".lowercased()
                return fullName.contains(searchText.lowercased())
            }

            let appUsers = filteredContacts.filter { $0.isAppUser }
            if !appUsers.isEmpty {
                Section {
                    ForEach(appUsers) { appContact in
                        ContactRowUnified(
                            appContact: appContact,
                            contactsManager: contactsManager,
                            successMessage: $successMessage,
                            showSuccessToast: $showSuccessToast
                        )
                    }
                } header: {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("On StepOut (\(appUsers.count))")
                    }
                }
            }

            let nonAppUsers = filteredContacts.filter { !$0.isAppUser }
            if !nonAppUsers.isEmpty {
                Section {
                    ForEach(nonAppUsers) { appContact in
                        ContactRowUnified(
                            appContact: appContact,
                            contactsManager: contactsManager,
                            successMessage: $successMessage,
                            showSuccessToast: $showSuccessToast
                        )
                    }
                } header: {
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text("Invite to StepOut (\(nonAppUsers.count))")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search contacts")
        .onAppear {
            if contactsManager.permissionStatus == .authorized && contactsManager.contacts.isEmpty {
                Task {
                    await contactsManager.fetchContacts()
                }
            }
        }
    }
}

// MARK: - Contact Row for Unified View
struct ContactRowUnified: View {
    let appContact: AppContact
    @ObservedObject var contactsManager: ContactsManager
    @Binding var successMessage: String
    @Binding var showSuccessToast: Bool

    @State private var requestStatus: FriendRequestStatus = .none
    @State private var isProcessing = false
    @State private var showUnfriendAlert = false

    enum FriendRequestStatus {
        case none       // No request sent
        case pending    // Request sent, waiting
        case failed     // Request failed
    }

    private var fullName: String {
        "\(appContact.contact.givenName) \(appContact.contact.familyName)".trimmingCharacters(in: .whitespaces)
    }

    private var initials: String {
        let first = appContact.contact.givenName.prefix(1)
        let last = appContact.contact.familyName.prefix(1)
        return "\(first)\(last)".uppercased()
    }

    private var contactInfo: String {
        if let phone = appContact.contact.phoneNumbers.first {
            return phone.value.stringValue
        } else if let email = appContact.contact.emailAddresses.first {
            return email.value as String
        }
        return ""
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 50, height: 50)

                if let imageData = appContact.contact.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    Text(initials)
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }

            // Name and Status
            VStack(alignment: .leading, spacing: 4) {
                Text(fullName)
                    .font(.headline)

                if appContact.isAppUser {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("On StepOut")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                } else {
                    Text(contactInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action Button
            if appContact.isAppUser {
                if isProcessing {
                    ProgressView()
                        .frame(width: 80)
                } else {
                    let isPending = contactsManager.isPending(userId: appContact.userId ?? "")
                    let isFriend = contactsManager.isFriend(userId: appContact.userId ?? "")

                    Button(action: {
                        guard let userId = appContact.userId else { return }

                        if isFriend {
                            // Show confirmation alert before unfriending
                            showUnfriendAlert = true
                        } else if !isPending && requestStatus == .none {
                            // Send friend request
                            isProcessing = true
                            Task {
                                do {
                                    try await contactsManager.sendFriendRequest(to: userId)
                                    await MainActor.run {
                                        isProcessing = false
                                        requestStatus = .pending
                                    }
                                } catch {
                                    await MainActor.run {
                                        isProcessing = false
                                        requestStatus = .failed

                                        // Show error toast
                                        successMessage = "Failed to send request"
                                        showSuccessToast = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            showSuccessToast = false
                                            requestStatus = .none // Allow retry
                                        }
                                    }
                                }
                            }
                        }
                    }) {
                        Group {
                            if isFriend {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.fill.xmark")
                                        .font(.caption2)
                                    Text("Unfriend")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(20)
                            } else if isPending || requestStatus == .pending {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.fill")
                                        .font(.caption2)
                                    Text("Pending")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(20)
                            } else if requestStatus == .failed {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption2)
                                    Text("Retry")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .cornerRadius(20)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.caption2)
                                    Text("Add")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .cornerRadius(20)
                            }
                        }
                    }
                    .disabled(isPending || requestStatus == .pending)
                }
            } else {
                Button(action: {
                    contactsManager.shareInviteLink(for: appContact.contact)
                }) {
                    Text("Invite")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(20)
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Unfriend \(fullName)?", isPresented: $showUnfriendAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Unfriend", role: .destructive) {
                guard let userId = appContact.userId else { return }
                isProcessing = true
                Task {
                    do {
                        try await contactsManager.unfriend(userId: userId)
                        await MainActor.run {
                            isProcessing = false
                            successMessage = "Removed friend"
                            showSuccessToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showSuccessToast = false
                            }
                        }
                    } catch {
                        await MainActor.run {
                            isProcessing = false
                            successMessage = "Failed to unfriend"
                            showSuccessToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showSuccessToast = false
                            }
                        }
                    }
                }
            }
        } message: {
            Text("Are you sure you want to remove \(fullName) from your friends?")
        }
    }
}

// MARK: - ViewModel
class UnifiedFriendsViewModel: ObservableObject {
    @Published var incomingRequests: [FriendRequest] = []
    @Published var outgoingRequests: [FriendRequest] = []
    @Published var friends: [SimpleFriend] = []
    @Published var incomingRequestsCount: Int = 0
    @Published var outgoingRequestsCount: Int = 0

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var incomingListener: ListenerRegistration?
    private var outgoingListener: ListenerRegistration?
    private var friendsListener: ListenerRegistration?

    struct SimpleFriend: Identifiable {
        let id: String
        let displayName: String
    }

    func startListening(userId: String) {
        // Listen to incoming requests (real-time)
        incomingListener = db.collection("invites")
            .whereField("recipientUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("[UnifiedFriends] Error listening to incoming: \(error)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                Task {
                    await self.loadIncomingRequests(documents)
                    await MainActor.run {
                        self.incomingRequestsCount = documents.count
                    }
                }
            }

        // Listen to outgoing requests (real-time)
        outgoingListener = db.collection("invites")
            .whereField("senderId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("[UnifiedFriends] Error listening to outgoing: \(error)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                Task {
                    await self.loadOutgoingRequests(documents)
                    await MainActor.run {
                        self.outgoingRequestsCount = documents.count
                    }
                }
            }

        // Listen to friends (real-time)
        friendsListener = db.collection("friends")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("[UnifiedFriends] Error listening to friends: \(error)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                Task {
                    await self.loadFriendsFromDocuments(documents)
                }
            }
    }

    func stopListening() {
        incomingListener?.remove()
        outgoingListener?.remove()
        friendsListener?.remove()
    }

    private func loadIncomingRequests(_ documents: [QueryDocumentSnapshot]) async {
        var requests: [FriendRequest] = []
        for doc in documents {
            let data = doc.data()
            guard let senderId = data["senderId"] as? String else { continue }
            do {
                let userDoc = try await db.collection("users").document(senderId).getDocument()
                let userData = userDoc.data()
                let senderName = userData?["displayName"] as? String ?? "Unknown User"
                let photoURL = userData?["photoURL"] as? String
                let request = FriendRequest(
                    id: doc.documentID,
                    senderId: senderId,
                    senderName: senderName,
                    senderPhotoURL: photoURL,
                    direction: .incoming
                )
                requests.append(request)
            } catch {
                print("[UnifiedFriends] Error fetching sender: \(error)")
            }
        }
        await MainActor.run {
            self.incomingRequests = requests
        }
    }

    private func loadOutgoingRequests(_ documents: [QueryDocumentSnapshot]) async {
        var requests: [FriendRequest] = []
        for doc in documents {
            let data = doc.data()
            guard let recipientId = data["recipientUserId"] as? String else { continue }
            do {
                let userDoc = try await db.collection("users").document(recipientId).getDocument()
                let userData = userDoc.data()
                let recipientName = userData?["displayName"] as? String ?? "Unknown User"
                let photoURL = userData?["photoURL"] as? String
                let request = FriendRequest(
                    id: doc.documentID,
                    senderId: recipientId,
                    senderName: recipientName,
                    senderPhotoURL: photoURL,
                    direction: .outgoing
                )
                requests.append(request)
            } catch {
                print("[UnifiedFriends] Error fetching recipient: \(error)")
            }
        }
        await MainActor.run {
            self.outgoingRequests = requests
        }
        print("[UnifiedFriends] ✅ Loaded \(requests.count) outgoing requests")
    }

    private func loadFriendsFromDocuments(_ documents: [QueryDocumentSnapshot]) async {
        var friendsList: [SimpleFriend] = []
        for doc in documents {
            let data = doc.data()
            guard let friendId = data["friendId"] as? String else { continue }
            do {
                let userDoc = try await db.collection("users").document(friendId).getDocument()
                let userData = userDoc.data()
                let displayName = userData?["displayName"] as? String ?? "Unknown"
                friendsList.append(SimpleFriend(id: friendId, displayName: displayName))
            } catch {
                print("[UnifiedFriends] Error fetching friend user data: \(error)")
            }
        }
        await MainActor.run {
            self.friends = friendsList
            print("[UnifiedFriends] ✅ Loaded \(friendsList.count) friends")
        }
    }

    func acceptRequest(_ request: FriendRequest) async {
        do {
            let callable = functions.httpsCallable("respondToFriendRequest")
            let result = try await callable.call([
                "inviteId": request.id,
                "accept": true
            ])

            print("[UnifiedFriends] ✅ Friend request accepted: \(result.data)")

            await MainActor.run {
                incomingRequests.removeAll { $0.id == request.id }
                incomingRequestsCount = incomingRequests.count
            }

            // Friends list will update automatically via real-time listener
        } catch {
            print("[UnifiedFriends] Failed to accept: \(error)")
        }
    }

    func declineRequest(_ request: FriendRequest) async {
        do {
            let callable = functions.httpsCallable("respondToFriendRequest")
            _ = try await callable.call([
                "inviteId": request.id,
                "accept": false
            ])
            await MainActor.run {
                incomingRequests.removeAll { $0.id == request.id }
                incomingRequestsCount = incomingRequests.count
            }
        } catch {
            print("[UnifiedFriends] Failed to decline: \(error)")
        }
    }

    func cancelRequest(_ request: FriendRequest) async {
        do {
            try await db.collection("invites").document(request.id).updateData([
                "status": "declined",
                "updatedAt": FieldValue.serverTimestamp()
            ])
            await MainActor.run {
                outgoingRequests.removeAll { $0.id == request.id }
            }
        } catch {
            print("[UnifiedFriends] Failed to cancel: \(error)")
        }
    }
}

// MARK: - Request Row Components
struct IncomingRequestRow: View {
    let request: FriendRequest
    @ObservedObject var viewModel: UnifiedFriendsViewModel
    @State private var isProcessing = false

    var body: some View {
        HStack(spacing: 12) {
            // Profile photo
            if let photoURL = request.senderPhotoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Text(request.senderName.prefix(1))
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(request.senderName)
                    .font(.headline)

                Text("Wants to be friends")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isProcessing {
                HStack(spacing: 8) {
                    Button {
                        isProcessing = true
                        Task {
                            await viewModel.acceptRequest(request)
                            isProcessing = false
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.green)
                            .clipShape(Circle())
                    }

                    Button {
                        isProcessing = true
                        Task {
                            await viewModel.declineRequest(request)
                            isProcessing = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                }
            } else {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }
}

struct OutgoingRequestRow: View {
    let request: FriendRequest
    @ObservedObject var viewModel: UnifiedFriendsViewModel
    @State private var isProcessing = false

    var body: some View {
        HStack(spacing: 12) {
            // Profile photo
            if let photoURL = request.senderPhotoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Text(request.senderName.prefix(1))
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(request.senderName)
                    .font(.headline)

                Text("Request pending")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isProcessing {
                Button {
                    isProcessing = true
                    Task {
                        await viewModel.cancelRequest(request)
                        isProcessing = false
                    }
                } label: {
                    Text("Cancel")
                        .font(.subheadline.bold())
                        .foregroundColor(.red)
                }
            } else {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }
}
