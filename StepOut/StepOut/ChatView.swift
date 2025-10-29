import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
struct ChatView: View {
    let chat: ChatInfo
    let authManager: AuthenticationManager?

    @StateObject private var viewModel: ChatViewModel
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    init(chat: ChatInfo, authManager: AuthenticationManager?) {
        self.chat = chat
        self.authManager = authManager
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatId: chat.id))
    }

    var body: some View {
        ZStack {
            // Modern gradient background matching home page theme
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.03),
                    Color.purple.opacity(0.03),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(
                                    message: message,
                                    isFromCurrentUser: message.senderId == Auth.auth().currentUser?.uid
                                )
                                .id(message.id)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation(.spring(response: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let lastMessage = viewModel.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }

                // Modern input bar or blocked message banner
                if chat.canSendMessages {
                    ModernChatInputBar(
                        messageText: $messageText,
                        isInputFocused: $isInputFocused,
                        onSend: {
                            Task {
                                await sendMessage()
                            }
                        }
                    )
                } else {
                    ChatBlockedBanner(status: chat.eventStatus)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 4) {
                    Text(chat.eventTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .primary.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    // Event status badge with modern styling
                    HStack(spacing: 6) {
                        Circle()
                            .fill(chat.eventStatus.color)
                            .frame(width: 7, height: 7)
                            .shadow(color: chat.eventStatus.color.opacity(0.4), radius: 2, y: 1)

                        Text(chat.eventStatus.displayText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(chat.eventStatus.color)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(chat.eventStatus.color.opacity(0.15))
                    )
                }
            }
        }
        .task {
            await viewModel.loadMessages()
            viewModel.startListeningForMessages()
        }
        .onDisappear {
            viewModel.stopListeningForMessages()
        }
    }

    private func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messageText = ""

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        await viewModel.sendMessage(text: text)
    }
}

// MARK: - Modern Chat Input Bar
struct ModernChatInputBar: View {
    @Binding var messageText: String
    @FocusState.Binding var isInputFocused: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Modern gradient divider
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.15),
                    Color.purple.opacity(0.15),
                    Color(.separator).opacity(0.3)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            HStack(alignment: .bottom, spacing: 12) {
                // Enhanced text input field
                HStack(spacing: 10) {
                    TextField("Type a message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .lineLimit(1...6)
                        .padding(.vertical, 11)
                        .font(.body)

                    // Character count for long messages
                    if messageText.count > 100 {
                        Text("\(messageText.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(
                                    isInputFocused ?
                                        LinearGradient(
                                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ) :
                                        LinearGradient(
                                            colors: [.clear, .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(
                            color: isInputFocused ?
                                Color.blue.opacity(0.1) :
                                Color.black.opacity(0.03),
                            radius: isInputFocused ? 8 : 4,
                            y: 2
                        )
                )
                .animation(.spring(response: 0.3), value: isInputFocused)

                // Enhanced animated send button
                Button(action: onSend) {
                    ZStack {
                        Circle()
                            .fill(
                                canSend ?
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color(.systemGray5), Color(.systemGray4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                            .shadow(
                                color: canSend ?
                                    Color.blue.opacity(0.3) :
                                    Color.clear,
                                radius: canSend ? 8 : 0,
                                y: canSend ? 2 : 0
                            )

                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .disabled(!canSend)
                .scaleEffect(canSend ? 1.0 : 0.85)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Color(.systemBackground)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: -2)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser {
                Spacer(minLength: 50)
            } else {
                // Avatar for other users
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.7), .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(message.senderName.prefix(1).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 6) {
                // Sender name for other users
                if !isFromCurrentUser {
                    Text(message.senderName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                // Message bubble with modern styling
                Text(message.text)
                    .font(.system(size: 16, weight: .regular))
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Group {
                            if isFromCurrentUser {
                                // Enhanced gradient bubble for current user
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.3), .clear],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 0.5
                                            )
                                    )
                            } else {
                                // Modern background for other users
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
                                    )
                            }
                        }
                    )
                    .foregroundStyle(isFromCurrentUser ? .white : .primary)
                    .shadow(
                        color: isFromCurrentUser ?
                            Color.blue.opacity(0.25) :
                            Color.black.opacity(0.06),
                        radius: isFromCurrentUser ? 12 : 6,
                        x: 0,
                        y: isFromCurrentUser ? 4 : 2
                    )

                // Timestamp with subtle styling
                HStack(spacing: 4) {
                    Text(message.createdAt, style: .time)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    // Read receipt indicator for current user messages
                    if isFromCurrentUser {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.blue.opacity(0.6))
                    }
                }
                .padding(.horizontal, 4)
            }

            if !isFromCurrentUser {
                Spacer(minLength: 50)
            }
        }
    }
}

// MARK: - Chat Blocked Banner
struct ChatBlockedBanner: View {
    let status: EventStatus

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(height: 0.5)

            HStack(spacing: 12) {
                Image(systemName: status == .expired ? "clock.badge.exclamationmark" : "archivebox")
                    .font(.title3)
                    .foregroundStyle(status.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status == .expired ? "Event has ended" : "Chat archived")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    Text(status == .expired ?
                        "Messaging will be disabled 7 days after the event" :
                        "This chat was archived 7 days after the event"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                status.color.opacity(0.1)
            )
        }
    }
}

// MARK: - Chat View Model
@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let chatId: String
    private let backend = ChatBackend()
    private var messageListener: ListenerRegistration?

    init(chatId: String) {
        self.chatId = chatId
    }

    func loadMessages() async {
        // Messages are loaded via real-time listener, no need for initial load
    }

    func sendMessage(text: String) async {
        do {
            let _ = try await backend.sendMessage(chatId: chatId, text: text)
            // Message will appear via real-time listener
        } catch {
            errorMessage = error.localizedDescription
            print("[ChatViewModel] Error sending message: \(error)")
        }
    }

    func startListeningForMessages() {
        guard messageListener == nil else { return }

        messageListener = backend.listenToMessages(chatId: chatId) { [weak self] newMessages in
            self?.messages = newMessages
        }
    }

    func stopListeningForMessages() {
        messageListener?.remove()
        messageListener = nil
    }
}
