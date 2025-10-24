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

    init(chat: ChatInfo, authManager: AuthenticationManager?) {
        self.chat = chat
        self.authManager = authManager
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatId: chat.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isFromCurrentUser: message.senderId == Auth.auth().currentUser?.uid
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
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

            Divider()

            // Input bar
            HStack(spacing: 12) {
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .focused($isInputFocused)
                    .lineLimit(1...5)

                Button {
                    Task {
                        await sendMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .navigationTitle(chat.eventTitle)
        .navigationBarTitleDisplayMode(.inline)
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
        await viewModel.sendMessage(text: text)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool

    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isFromCurrentUser {
                    Text(message.senderName)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isFromCurrentUser ? Color.blue : Color(.secondarySystemBackground))
                    )
                    .foregroundStyle(isFromCurrentUser ? .white : .primary)

                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isFromCurrentUser {
                Spacer(minLength: 60)
            }
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
