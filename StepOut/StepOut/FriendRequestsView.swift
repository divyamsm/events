import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

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

class FriendRequestsViewModel: ObservableObject {
    @Published var incomingRequests: [FriendRequest] = []
    @Published var outgoingRequests: [FriendRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?

    func startListening(userId: String) {
        print("[FriendRequests] Starting listener for user: \(userId)")

        // Listen to incoming requests
        listener = db.collection("invites")
            .whereField("recipientUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("[FriendRequests] Error listening: \(error)")
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let documents = snapshot?.documents else { return }
                print("[FriendRequests] Found \(documents.count) incoming requests")

                Task {
                    await self.loadIncomingRequests(documents)
                }
            }

        // Also load outgoing requests
        Task {
            await loadOutgoingRequests(userId: userId)
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    private func loadIncomingRequests(_ documents: [QueryDocumentSnapshot]) async {
        var requests: [FriendRequest] = []

        for doc in documents {
            let data = doc.data()
            guard let senderId = data["senderId"] as? String else { continue }

            // Fetch sender info
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
                print("[FriendRequests] Error fetching sender \(senderId): \(error)")
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

                // Fetch recipient info
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

            print("[FriendRequests] Loaded \(requests.count) outgoing requests")
        } catch {
            print("[FriendRequests] Error loading outgoing: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func acceptRequest(_ request: FriendRequest) async {
        print("[FriendRequests] Accepting request: \(request.id)")

        do {
            let callable = functions.httpsCallable("respondToFriendRequest")
            let result = try await callable.call([
                "inviteId": request.id,
                "accept": true
            ])

            print("[FriendRequests] ✅ Request accepted: \(result.data)")

            // Remove from incoming list
            await MainActor.run {
                incomingRequests.removeAll { $0.id == request.id }
            }
        } catch {
            print("[FriendRequests] ❌ Failed to accept: \(error)")
            await MainActor.run {
                errorMessage = "Failed to accept request: \(error.localizedDescription)"
            }
        }
    }

    func declineRequest(_ request: FriendRequest) async {
        print("[FriendRequests] Declining request: \(request.id)")

        do {
            let callable = functions.httpsCallable("respondToFriendRequest")
            let result = try await callable.call([
                "inviteId": request.id,
                "accept": false
            ])

            print("[FriendRequests] ✅ Request declined: \(result.data)")

            // Remove from incoming list
            await MainActor.run {
                incomingRequests.removeAll { $0.id == request.id }
            }
        } catch {
            print("[FriendRequests] ❌ Failed to decline: \(error)")
            await MainActor.run {
                errorMessage = "Failed to decline request: \(error.localizedDescription)"
            }
        }
    }

    func cancelRequest(_ request: FriendRequest) async {
        print("[FriendRequests] Canceling outgoing request: \(request.id)")

        do {
            try await db.collection("invites").document(request.id).updateData([
                "status": "declined",
                "updatedAt": FieldValue.serverTimestamp()
            ])

            await MainActor.run {
                outgoingRequests.removeAll { $0.id == request.id }
            }

            print("[FriendRequests] ✅ Request canceled")
        } catch {
            print("[FriendRequests] ❌ Failed to cancel: \(error)")
            await MainActor.run {
                errorMessage = "Failed to cancel request: \(error.localizedDescription)"
            }
        }
    }
}

struct FriendRequestsView: View {
    @StateObject private var viewModel = FriendRequestsViewModel()
    @Environment(\.dismiss) private var dismiss
    let userId: String

    var body: some View {
        NavigationStack {
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

                if viewModel.incomingRequests.isEmpty && viewModel.outgoingRequests.isEmpty && !viewModel.isLoading {
                    Section {
                        Text("No pending friend requests")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                }
            }
            .navigationTitle("Friend Requests")
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
            }
            .onDisappear {
                viewModel.stopListening()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
}

struct IncomingRequestRow: View {
    let request: FriendRequest
    @ObservedObject var viewModel: FriendRequestsViewModel
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
    @ObservedObject var viewModel: FriendRequestsViewModel
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
