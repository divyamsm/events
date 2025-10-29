import SwiftUI
import FirebaseAuth

@MainActor
struct ChatsTabView: View {
    let authManager: AuthenticationManager?
    @StateObject private var viewModel = ChatsViewModel()
    @State private var showOnlyActive = true

    var filteredChats: [ChatInfo] {
        if showOnlyActive {
            return viewModel.chats.filter { $0.eventStatus == .active }
        }
        return viewModel.chats
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading chats...")
                } else if filteredChats.isEmpty {
                    emptyState
                } else {
                    chatsList
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showOnlyActive = true }) {
                            Label("Active Only", systemImage: showOnlyActive ? "checkmark" : "")
                        }
                        Button(action: { showOnlyActive = false }) {
                            Label("Show All", systemImage: !showOnlyActive ? "checkmark" : "")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task {
                await viewModel.loadChats()
            }
            .refreshable {
                await viewModel.loadChats()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Chats Yet")
                .font(.title2.bold())

            Text("When you join events, you'll be able to chat with other attendees here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatsList: some View {
        List(filteredChats) { chat in
            NavigationLink {
                ChatView(chat: chat, authManager: authManager)
            } label: {
                ChatRowView(chat: chat)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Chat Row View
struct ChatRowView: View {
    let chat: ChatInfo

    var body: some View {
        HStack(spacing: 12) {
            // Event icon/image
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 56, height: 56)

                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.eventTitle)
                        .font(.headline)
                        .lineLimit(1)

                    // Status badge
                    HStack(spacing: 3) {
                        Circle()
                            .fill(chat.eventStatus.color)
                            .frame(width: 5, height: 5)
                        Text(chat.eventStatus.displayText)
                            .font(.caption2)
                            .foregroundStyle(chat.eventStatus.color)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(chat.eventStatus.color.opacity(0.1))
                    .cornerRadius(8)

                    Spacer()

                    if let lastMessageAt = chat.lastMessageAt {
                        Text(lastMessageAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastMessageText = chat.lastMessageText {
                    Text(lastMessageText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount) unread")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Chats View Model
@MainActor
final class ChatsViewModel: ObservableObject {
    @Published private(set) var chats: [ChatInfo] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let backend = ChatBackend()

    func loadChats() async {
        isLoading = true
        defer { isLoading = false }

        do {
            chats = try await backend.listChats()
        } catch {
            errorMessage = error.localizedDescription
            print("[ChatsViewModel] Error loading chats: \(error)")
        }
    }
}
