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

                VStack(spacing: 0) {
                    // Modern header
                    ModernChatsHeader(showOnlyActive: $showOnlyActive)
                        .padding(.bottom, 8)

                    Group {
                        if viewModel.isLoading {
                            ProgressView("Loading chats...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if filteredChats.isEmpty {
                            emptyState
                        } else {
                            chatsList
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("Messages")
                            .font(.title3.bold())
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

                Image(systemName: "bubble.left.and.bubble.right.fill")
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
                Text("No Chats Yet")
                    .font(.title.bold())
                    .foregroundStyle(.primary)

                Text("Join events to start chatting\nwith other attendees")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var chatsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredChats) { chat in
                    NavigationLink {
                        ChatView(chat: chat, authManager: authManager)
                    } label: {
                        ModernChatRowView(chat: chat)
                    }
                    .buttonStyle(.plain)

                    if chat.id != filteredChats.last?.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
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

// MARK: - Modern Chats Header
struct ModernChatsHeader: View {
    @Binding var showOnlyActive: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Messages")
                        .font(.largeTitle.bold())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .primary.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Stay connected with your events")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)

            // Filter tabs
            HStack(spacing: 8) {
                FilterButton(
                    title: "Active",
                    isSelected: showOnlyActive,
                    action: { showOnlyActive = true }
                )

                FilterButton(
                    title: "All",
                    isSelected: !showOnlyActive,
                    action: { showOnlyActive = false }
                )

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 8)
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        } else {
                            LinearGradient(
                                colors: [Color(.secondarySystemBackground), Color(.secondarySystemBackground)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                    }
                )
                .cornerRadius(20)
                .shadow(
                    color: isSelected ? Color.blue.opacity(0.3) : Color.clear,
                    radius: isSelected ? 8 : 0,
                    y: isSelected ? 2 : 0
                )
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Modern Chat Row
struct ModernChatRowView: View {
    let chat: ChatInfo

    var body: some View {
        HStack(spacing: 14) {
            // Modern gradient icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: .blue.opacity(0.1), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(chat.eventTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer()

                    // Status badge with modern styling
                    HStack(spacing: 4) {
                        Circle()
                            .fill(chat.eventStatus.color)
                            .frame(width: 6, height: 6)
                        Text(chat.eventStatus.displayText)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(chat.eventStatus.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(chat.eventStatus.color.opacity(0.15))
                    )
                }

                HStack {
                    if let lastMessageText = chat.lastMessageText {
                        Text(lastMessageText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("No messages yet")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    if let lastMessageAt = chat.lastMessageAt {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(lastMessageAt, style: .relative)
                                .font(.caption)
                        }
                        .foregroundStyle(.tertiary)
                    }

                    if chat.unreadCount > 0 {
                        HStack(spacing: 4) {
                            Text("\(chat.unreadCount)")
                                .font(.caption.bold())
                            Image(systemName: "envelope.badge.fill")
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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
