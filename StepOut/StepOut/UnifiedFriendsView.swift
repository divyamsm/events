import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
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
                Picker("", selection: $selectedTab) {
                    HStack {
                        Text("Requests")
                        if viewModel.incomingRequestsCount > 0 {
                            Text("\(viewModel.incomingRequestsCount)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                        }
                    }
                    .tag(0)

                    Text("Friends").tag(1)
                    Text("Find Friends").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                // Content based on selected tab
                TabView(selection: $selectedTab) {
                    // Tab 0: Friend Requests
                    requestsTab
                        .tag(0)

                    // Tab 1: Friends List
                    friendsTab
                        .tag(1)

                    // Tab 2: Find Friends (from contacts)
                    findFriendsTab
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
            }
            .overlay(alignment: .top) {
                if showSuccessToast {
                    VStack {
                        Text(successMessage)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green.opacity(0.95))
                            .cornerRadius(10)
                            .shadow(radius: 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 60)
                    }
                    .animation(.spring(), value: showSuccessToast)
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
            let appUsers = contactsManager.contacts.filter { $0.isAppUser }
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

            let nonAppUsers = contactsManager.contacts.filter { !$0.isAppUser }
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
    let contactsManager: ContactsManager
    @Binding var successMessage: String
    @Binding var showSuccessToast: Bool

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
                Button(action: {
                    guard let userId = appContact.userId else { return }
                    Task {
                        do {
                            try await contactsManager.sendFriendRequest(to: userId)
                            await MainActor.run {
                                successMessage = "Friend request sent to \(fullName)"
                                showSuccessToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showSuccessToast = false
                                }
                            }
                        } catch {
                            await MainActor.run {
                                successMessage = "Failed to send request"
                                showSuccessToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showSuccessToast = false
                                }
                            }
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                        Text("Add")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(20)
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
    }
}

// MARK: - ViewModel
class UnifiedFriendsViewModel: ObservableObject {
    @Published var incomingRequests: [FriendRequest] = []
    @Published var outgoingRequests: [FriendRequest] = []
    @Published var friends: [SimpleFriend] = []
    @Published var incomingRequestsCount: Int = 0

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    struct SimpleFriend: Identifiable {
        let id: String
        let displayName: String
    }

    func startListening(userId: String) {
        // Listen to incoming requests
        listener = db.collection("invites")
            .whereField("recipientUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("[UnifiedFriends] Error: \(error)")
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

        // Load outgoing requests and friends
        Task {
            await loadOutgoingRequests(userId: userId)
            await loadFriends(userId: userId)
        }
    }

    func stopListening() {
        listener?.remove()
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

    private func loadOutgoingRequests(userId: String) async {
        do {
            let snapshot = try await db.collection("invites")
                .whereField("senderId", isEqualTo: userId)
                .whereField("status", isEqualTo: "pending")
                .getDocuments()

            var requests: [FriendRequest] = []
            for doc in snapshot.documents {
                let data = doc.data()
                guard let recipientId = data["recipientUserId"] as? String else { continue }
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
            }
            await MainActor.run {
                self.outgoingRequests = requests
            }
        } catch {
            print("[UnifiedFriends] Error loading outgoing: \(error)")
        }
    }

    private func loadFriends(userId: String) async {
        do {
            let snapshot = try await db.collection("friends")
                .whereField("userId", isEqualTo: userId)
                .whereField("status", isEqualTo: "active")
                .getDocuments()

            var friendsList: [SimpleFriend] = []
            for doc in snapshot.documents {
                let data = doc.data()
                guard let friendId = data["friendId"] as? String else { continue }
                let userDoc = try await db.collection("users").document(friendId).getDocument()
                let userData = userDoc.data()
                let displayName = userData?["displayName"] as? String ?? "Unknown"
                friendsList.append(SimpleFriend(id: friendId, displayName: displayName))
            }
            await MainActor.run {
                self.friends = friendsList
            }
        } catch {
            print("[UnifiedFriends] Error loading friends: \(error)")
        }
    }

    func acceptRequest(_ request: FriendRequest) async {
        do {
            let callable = functions.httpsCallable("respondToFriendRequest")
            _ = try await callable.call([
                "inviteId": request.id,
                "accept": true
            ])
            await MainActor.run {
                incomingRequests.removeAll { $0.id == request.id }
                incomingRequestsCount = incomingRequests.count
            }
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
