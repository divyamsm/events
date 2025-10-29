import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

/// Backend API for chat functionality
@MainActor
class ChatBackend: ObservableObject {
    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    // MARK: - Fetch Chats

    func listChats() async throws -> [ChatInfo] {
        let callable = functions.httpsCallable("listChats")
        let result = try await callable.call()

        guard let data = result.data as? [String: Any],
              let chatsArray = data["chats"] as? [[String: Any]] else {
            throw NSError(domain: "ChatBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        return chatsArray.compactMap { chatDict in
            print("[ChatBackend] 📦 Raw chat keys: \(chatDict.keys.sorted())")

            guard let chatId = chatDict["chatId"] as? String,
                  let eventId = chatDict["eventId"] as? String,
                  let eventTitle = chatDict["eventTitle"] as? String else {
                return nil
            }

            let lastMessageText = chatDict["lastMessageText"] as? String
            let lastMessageSenderName = chatDict["lastMessageSenderName"] as? String
            let unreadCount = chatDict["unreadCount"] as? Int ?? 0
            let participantCount = chatDict["participantCount"] as? Int ?? 0

            let lastMessageAt: Date?
            if let lastMessageAtString = chatDict["lastMessageAt"] as? String {
                lastMessageAt = ISO8601DateFormatter().date(from: lastMessageAtString)
            } else {
                lastMessageAt = nil
            }

            let eventEndAt: Date?
            if let eventEndAtString = chatDict["eventEndAt"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                eventEndAt = formatter.date(from: eventEndAtString)
                print("[ChatBackend] ✅ Chat '\(eventTitle)' endAt: \(eventEndAtString) -> parsed: \(eventEndAt?.description ?? "FAILED TO PARSE")")
            } else {
                eventEndAt = nil
                print("[ChatBackend] ⚠️ Chat '\(eventTitle)' (eventId: \(eventId)) - NO eventEndAt!")
            }

            return ChatInfo(
                chatId: chatId,
                eventId: eventId,
                eventTitle: eventTitle,
                eventEndAt: eventEndAt,
                lastMessageAt: lastMessageAt,
                lastMessageText: lastMessageText,
                lastMessageSenderName: lastMessageSenderName,
                unreadCount: unreadCount,
                participantCount: participantCount
            )
        }
    }

    // MARK: - Send Message

    func sendMessage(chatId: String, text: String) async throws -> String {
        let callable = functions.httpsCallable("sendMessage")
        let result = try await callable.call([
            "chatId": chatId,
            "text": text
        ])

        guard let data = result.data as? [String: Any],
              let messageId = data["messageId"] as? String else {
            throw NSError(domain: "ChatBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        return messageId
    }

    // MARK: - Real-time Message Listener

    func listenToMessages(chatId: String, onUpdate: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration {
        let messagesRef = db.collection("chats").document(chatId).collection("messages")

        return messagesRef
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                guard let snapshot = snapshot else {
                    print("[Chat] Listen error: \(error?.localizedDescription ?? "unknown")")
                    return
                }

                var messages: [ChatMessage] = []

                for document in snapshot.documents {
                    let data = document.data()

                    guard let messageId = data["messageId"] as? String,
                          let senderId = data["senderId"] as? String,
                          let senderName = data["senderName"] as? String,
                          let text = data["text"] as? String,
                          let createdAtTimestamp = data["createdAt"] as? Timestamp,
                          let type = data["type"] as? String else {
                        continue
                    }

                    let senderPhotoURL = data["senderPhotoURL"] as? String
                    let createdAt = createdAtTimestamp.dateValue()

                    let message = ChatMessage(
                        id: messageId,
                        senderId: senderId,
                        senderName: senderName,
                        senderPhotoURL: senderPhotoURL,
                        text: text,
                        createdAt: createdAt,
                        type: type == "system" ? .system : .text
                    )

                    messages.append(message)
                }

                Task { @MainActor in
                    onUpdate(messages)
                }
            }
    }
}

// MARK: - Models

struct ChatInfo: Identifiable {
    let id: String
    let chatId: String
    let eventId: String
    let eventTitle: String
    let eventEndAt: Date?
    let lastMessageAt: Date?
    let lastMessageText: String?
    let lastMessageSenderName: String?
    let unreadCount: Int
    let participantCount: Int

    init(chatId: String, eventId: String, eventTitle: String, eventEndAt: Date?, lastMessageAt: Date?, lastMessageText: String?, lastMessageSenderName: String?, unreadCount: Int, participantCount: Int) {
        self.id = chatId
        self.chatId = chatId
        self.eventId = eventId
        self.eventTitle = eventTitle
        self.eventEndAt = eventEndAt
        self.lastMessageAt = lastMessageAt
        self.lastMessageText = lastMessageText
        self.lastMessageSenderName = lastMessageSenderName
        self.unreadCount = unreadCount
        self.participantCount = participantCount
    }

    // Computed property for event status
    var eventStatus: EventStatus {
        guard let endAt = eventEndAt else {
            print("[ChatInfo] '\(eventTitle)' has no endAt, defaulting to .active")
            return .active
        }

        let now = Date()
        let sevenDaysAfterEnd = Calendar.current.date(byAdding: .day, value: 7, to: endAt) ?? endAt

        let status: EventStatus
        if now < endAt {
            status = .active
        } else if now < sevenDaysAfterEnd {
            status = .expired
        } else {
            status = .archived
        }

        print("[ChatInfo] '\(eventTitle)' status: \(status.displayText) (now: \(now), endAt: \(endAt), 7daysAfter: \(sevenDaysAfterEnd))")
        return status
    }

    var canSendMessages: Bool {
        return eventStatus == .active
    }
}

enum EventStatus {
    case active
    case expired
    case archived

    var displayText: String {
        switch self {
        case .active: return "Active"
        case .expired: return "Event Ended"
        case .archived: return "Archived"
        }
    }

    var color: Color {
        switch self {
        case .active: return .green
        case .expired: return .orange
        case .archived: return .gray
        }
    }
}

struct ChatMessage: Identifiable {
    let id: String
    let senderId: String
    let senderName: String
    let senderPhotoURL: String?
    let text: String
    let createdAt: Date
    let type: MessageType

    enum MessageType {
        case text
        case system
    }
}
