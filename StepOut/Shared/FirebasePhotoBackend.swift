import Foundation
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

final class FirebasePhotoBackend {
#if canImport(FirebaseFunctions) && canImport(FirebaseStorage)
    private let functions: Functions
    private let storage: Storage

    init(functions: Functions = Functions.functions(), storage: Storage = Storage.storage()) {
        self.functions = functions
        self.storage = storage
    }

    // MARK: - Photo Upload

    func uploadPhoto(eventId: String, imageData: Data, caption: String?) async throws -> String {
        print("[PhotoBackend] 🔍 Uploading photo for event: \(eventId), size: \(imageData.count) bytes")

        // Upload to Firebase Storage
        let photoId = UUID().uuidString
        let storageRef = storage.reference().child("event_photos/\(eventId)/\(photoId).jpg")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()

        print("[PhotoBackend] 🔍 Photo uploaded to Storage: \(downloadURL.absoluteString)")

        // Save metadata to Firestore via Cloud Function
        let callable = functions.httpsCallable("uploadEventPhoto")
        let payload: [String: Any] = [
            "eventId": eventId,
            "photoURL": downloadURL.absoluteString,
            "caption": caption as Any
        ]

        let result = try await callable.call(payload)
        guard let response = result.data as? [String: Any],
              let returnedPhotoId = response["photoId"] as? String else {
            throw NSError(domain: "FirebasePhotoBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid upload response"])
        }

        print("[PhotoBackend] 🔍 Photo metadata saved, photoId: \(returnedPhotoId)")
        return returnedPhotoId
    }

    // MARK: - List Photos

    func listPhotos(eventId: String, before: Date? = nil, limit: Int = 30) async throws -> [EventPhoto] {
        print("[PhotoBackend] 🔍 Listing photos for event: \(eventId)")

        let callable = functions.httpsCallable("listEventPhotos")
        var payload: [String: Any] = [
            "eventId": eventId,
            "limit": limit
        ]

        if let before = before {
            payload["before"] = ISO8601DateFormatter().string(from: before)
        }

        let result = try await callable.call(payload)
        guard let response = result.data as? [String: Any],
              let photosArray = response["photos"] as? [[String: Any]] else {
            throw NSError(domain: "FirebasePhotoBackend", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid photos response"])
        }

        let photos = photosArray.compactMap { dict -> EventPhoto? in
            guard let photoId = dict["photoId"] as? String,
                  let userId = dict["userId"] as? String,
                  let userName = dict["userName"] as? String,
                  let photoURLString = dict["photoURL"] as? String,
                  let photoURL = URL(string: photoURLString),
                  let createdAtMs = dict["createdAt"] as? TimeInterval else {
                return nil
            }

            let userPhotoURL: URL? = (dict["userPhotoURL"] as? String).flatMap { URL(string: $0) }
            let caption = dict["caption"] as? String

            return EventPhoto(
                id: photoId,
                eventId: eventId,
                userId: userId,
                userName: userName,
                userPhotoURL: userPhotoURL,
                photoURL: photoURL,
                caption: caption,
                createdAt: Date(timeIntervalSince1970: createdAtMs / 1000)
            )
        }

        print("[PhotoBackend] 🔍 Loaded \(photos.count) photos")
        return photos
    }

    // MARK: - Delete Photo

    func deletePhoto(eventId: String, photoId: String) async throws {
        print("[PhotoBackend] 🔍 Deleting photo: \(photoId)")

        let callable = functions.httpsCallable("deleteEventPhoto")
        let payload: [String: Any] = [
            "eventId": eventId,
            "photoId": photoId
        ]

        _ = try await callable.call(payload)
        print("[PhotoBackend] 🔍 Photo deleted successfully")
    }

    // MARK: - Comments

    func postComment(eventId: String, text: String) async throws -> String {
        print("[PhotoBackend] 🔍 Posting comment on event: \(eventId)")

        let callable = functions.httpsCallable("postEventComment")
        let payload: [String: Any] = [
            "eventId": eventId,
            "text": text
        ]

        let result = try await callable.call(payload)
        guard let response = result.data as? [String: Any],
              let commentId = response["commentId"] as? String else {
            throw NSError(domain: "FirebasePhotoBackend", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid comment response"])
        }

        print("[PhotoBackend] 🔍 Comment posted, commentId: \(commentId)")
        return commentId
    }

    func listComments(eventId: String, limit: Int = 50, before: Date? = nil) async throws -> [EventComment] {
        print("[PhotoBackend] 🔍 Listing comments for event: \(eventId)")

        let callable = functions.httpsCallable("listEventComments")
        var payload: [String: Any] = [
            "eventId": eventId,
            "limit": limit
        ]

        if let before = before {
            payload["before"] = ISO8601DateFormatter().string(from: before)
        }

        let result = try await callable.call(payload)
        guard let response = result.data as? [String: Any],
              let commentsArray = response["comments"] as? [[String: Any]] else {
            throw NSError(domain: "FirebasePhotoBackend", code: -4, userInfo: [NSLocalizedDescriptionKey: "Invalid comments response"])
        }

        let comments = commentsArray.compactMap { dict -> EventComment? in
            guard let commentId = dict["commentId"] as? String,
                  let userId = dict["userId"] as? String,
                  let userName = dict["userName"] as? String,
                  let text = dict["text"] as? String,
                  let createdAtMs = dict["createdAt"] as? TimeInterval else {
                return nil
            }

            let userPhotoURL: URL? = (dict["userPhotoURL"] as? String).flatMap { URL(string: $0) }

            return EventComment(
                id: commentId,
                eventId: eventId,
                userId: userId,
                userName: userName,
                userPhotoURL: userPhotoURL,
                text: text,
                createdAt: Date(timeIntervalSince1970: createdAtMs / 1000)
            )
        }

        print("[PhotoBackend] 🔍 Loaded \(comments.count) comments")
        return comments
    }

    func deleteComment(eventId: String, commentId: String) async throws {
        print("[PhotoBackend] 🔍 Deleting comment: \(commentId)")

        let callable = functions.httpsCallable("deleteEventComment")
        let payload: [String: Any] = [
            "eventId": eventId,
            "commentId": commentId
        ]

        _ = try await callable.call(payload)
        print("[PhotoBackend] 🔍 Comment deleted successfully")
    }

#else
    init() {}

    func uploadPhoto(eventId: String, imageData: Data, caption: String?) async throws -> String {
        throw NSError(domain: "FirebasePhotoBackend", code: -1, userInfo: nil)
    }

    func listPhotos(eventId: String, limit: Int = 50) async throws -> [EventPhoto] {
        return []
    }

    func deletePhoto(eventId: String, photoId: String) async throws {}

    func postComment(eventId: String, text: String) async throws -> String {
        throw NSError(domain: "FirebasePhotoBackend", code: -1, userInfo: nil)
    }

    func listComments(eventId: String, limit: Int = 50, before: Date? = nil) async throws -> [EventComment] {
        return []
    }

    func deleteComment(eventId: String, commentId: String) async throws {}
#endif
}
