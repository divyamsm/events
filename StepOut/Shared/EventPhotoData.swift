import Foundation

struct EventPhoto: Identifiable, Hashable, Codable {
    let id: String // photoId
    let eventId: String
    let userId: String
    let userName: String
    let userPhotoURL: URL?
    let photoURL: URL
    let caption: String?
    let createdAt: Date

    init(
        id: String,
        eventId: String,
        userId: String,
        userName: String,
        userPhotoURL: URL? = nil,
        photoURL: URL,
        caption: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.eventId = eventId
        self.userId = userId
        self.userName = userName
        self.userPhotoURL = userPhotoURL
        self.photoURL = photoURL
        self.caption = caption
        self.createdAt = createdAt
    }
}

struct EventComment: Identifiable, Hashable, Codable {
    let id: String // commentId
    let eventId: String
    let userId: String
    let userName: String
    let userPhotoURL: URL?
    let text: String
    let createdAt: Date

    init(
        id: String,
        eventId: String,
        userId: String,
        userName: String,
        userPhotoURL: URL? = nil,
        text: String,
        createdAt: Date
    ) {
        self.id = id
        self.eventId = eventId
        self.userId = userId
        self.userName = userName
        self.userPhotoURL = userPhotoURL
        self.text = text
        self.createdAt = createdAt
    }
}
