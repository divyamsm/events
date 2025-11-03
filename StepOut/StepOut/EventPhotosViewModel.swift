import Foundation
import SwiftUI
import PhotosUI

@MainActor
final class EventPhotosViewModel: ObservableObject {
    @Published var photos: [EventPhoto] = []
    @Published var comments: [EventComment] = []
    @Published var isLoadingPhotos = false
    @Published var isLoadingComments = false
    @Published var isUploadingPhoto = false
    @Published var isPostingComment = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var hasMorePhotos = true
    @Published var hasMoreComments = true

    private let backend: FirebasePhotoBackend
    private let currentUserId: String

    init(backend: FirebasePhotoBackend = FirebasePhotoBackend(), currentUserId: String) {
        self.backend = backend
        self.currentUserId = currentUserId
    }

    // MARK: - Photos

    func loadPhotos(for eventId: String, loadMore: Bool = false) async {
        guard !isLoadingPhotos else { return }
        guard hasMorePhotos || !loadMore else { return }

        // Load from cache first (instant)
        if !loadMore {
            let cacheKey = CacheManager.photosKey(eventId: eventId)
            if let cachedPhotos: [EventPhoto] = await CacheManager.shared.load(forKey: cacheKey) {
                photos = cachedPhotos
                print("[EventPhotosVM] 📦 Loaded \(cachedPhotos.count) photos from cache")
            }
        }

        isLoadingPhotos = true
        defer { isLoadingPhotos = false }

        do {
            let before = loadMore ? photos.last?.createdAt : nil
            let newPhotos = try await backend.listPhotos(eventId: eventId, before: before, limit: 30)

            if loadMore {
                photos.append(contentsOf: newPhotos)
            } else {
                photos = newPhotos
                // Cache fresh data
                let cacheKey = CacheManager.photosKey(eventId: eventId)
                await CacheManager.shared.save(newPhotos, forKey: cacheKey)
            }

            hasMorePhotos = newPhotos.count == 30
        } catch {
            print("[EventPhotosVM] ❌ Failed to load photos: \(error.localizedDescription)")
            errorMessage = "Couldn't load photos. Please try again."
        }
    }

    func uploadPhoto(for eventId: String, imageData: Data, caption: String?) async {
        guard !isUploadingPhoto else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }

        do {
            let photoId = try await backend.uploadPhoto(eventId: eventId, imageData: imageData, caption: caption)
            print("[EventPhotosVM] ✅ Photo uploaded: \(photoId)")

            // Reload photos to show the new one
            await loadPhotos(for: eventId)
            successMessage = "Photo uploaded!"

            // Clear success message after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            successMessage = nil
        } catch {
            print("[EventPhotosVM] ❌ Failed to upload photo: \(error.localizedDescription)")
            errorMessage = "Couldn't upload photo. Please try again."
        }
    }

    func deletePhoto(eventId: String, photoId: String) async {
        do {
            try await backend.deletePhoto(eventId: eventId, photoId: photoId)
            photos.removeAll { $0.id == photoId }
            successMessage = "Photo deleted"

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            successMessage = nil
        } catch {
            print("[EventPhotosVM] ❌ Failed to delete photo: \(error.localizedDescription)")
            errorMessage = "Couldn't delete photo. Please try again."
        }
    }

    // MARK: - Comments

    func loadComments(for eventId: String, loadMore: Bool = false) async {
        guard !isLoadingComments else { return }
        guard hasMoreComments || !loadMore else { return }

        // Load from cache first (instant)
        if !loadMore {
            let cacheKey = CacheManager.commentsKey(eventId: eventId)
            if let cachedComments: [EventComment] = await CacheManager.shared.load(forKey: cacheKey) {
                comments = cachedComments
                print("[EventPhotosVM] 📦 Loaded \(cachedComments.count) comments from cache")
            }
        }

        isLoadingComments = true
        defer { isLoadingComments = false }

        do {
            let before = loadMore ? comments.last?.createdAt : nil
            let newComments = try await backend.listComments(eventId: eventId, limit: 50, before: before)

            if loadMore {
                comments.append(contentsOf: newComments)
            } else {
                comments = newComments
                // Cache fresh data
                let cacheKey = CacheManager.commentsKey(eventId: eventId)
                await CacheManager.shared.save(newComments, forKey: cacheKey)
            }

            hasMoreComments = newComments.count == 50
        } catch {
            print("[EventPhotosVM] ❌ Failed to load comments: \(error.localizedDescription)")
            errorMessage = "Couldn't load comments. Please try again."
        }
    }

    func postComment(for eventId: String, text: String) async {
        guard !isPostingComment else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isPostingComment = true
        defer { isPostingComment = false }

        do {
            let commentId = try await backend.postComment(eventId: eventId, text: text)
            print("[EventPhotosVM] ✅ Comment posted: \(commentId)")

            // Reload comments to show the new one
            await loadComments(for: eventId)
        } catch {
            print("[EventPhotosVM] ❌ Failed to post comment: \(error.localizedDescription)")
            errorMessage = "Couldn't post comment. Please try again."
        }
    }

    func deleteComment(eventId: String, commentId: String) async {
        do {
            try await backend.deleteComment(eventId: eventId, commentId: commentId)
            comments.removeAll { $0.id == commentId }
            successMessage = "Comment deleted"

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            successMessage = nil
        } catch {
            print("[EventPhotosVM] ❌ Failed to delete comment: \(error.localizedDescription)")
            errorMessage = "Couldn't delete comment. Please try again."
        }
    }

    func canDelete(photo: EventPhoto, isEventOwner: Bool) -> Bool {
        return photo.userId == currentUserId || isEventOwner
    }

    func canDelete(comment: EventComment, isEventOwner: Bool) -> Bool {
        return comment.userId == currentUserId || isEventOwner
    }
}
