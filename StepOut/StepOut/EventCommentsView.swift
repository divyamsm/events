import SwiftUI

struct EventCommentsView: View {
    let eventId: String
    let isEventOwner: Bool
    @StateObject private var viewModel: EventPhotosViewModel
    @State private var commentText = ""
    @FocusState private var isCommentFieldFocused: Bool

    init(eventId: String, isEventOwner: Bool, currentUserId: String, viewModel: EventPhotosViewModel? = nil) {
        self.eventId = eventId
        self.isEventOwner = isEventOwner
        if let viewModel = viewModel {
            _viewModel = StateObject(wrappedValue: viewModel)
        } else {
            _viewModel = StateObject(wrappedValue: EventPhotosViewModel(currentUserId: currentUserId))
        }
    }

    var body: some View {
        mainContent
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            commentsList
            Divider()
            commentInput
        }
        .task { await viewModel.loadComments(for: eventId) }
    }

    private var commentsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if viewModel.comments.isEmpty && viewModel.isLoadingComments {
                    ProgressView("Loading comments...")
                        .padding()
                } else if viewModel.comments.isEmpty {
                    emptyStateView
                } else {
                    ForEach(viewModel.comments) { comment in
                        CommentRow(
                            comment: comment,
                            canDelete: viewModel.canDelete(comment: comment, isEventOwner: isEventOwner),
                            onDelete: {
                                _Concurrency.Task {
                                    await viewModel.deleteComment(eventId: eventId, commentId: comment.id)
                                }
                            }
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No comments yet")
                .font(.title3.bold())
            Text("Be the first to comment!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
    }

    private var commentInput: some View {
        HStack(spacing: 12) {
            TextField("Add a comment...", text: $commentText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($isCommentFieldFocused)

            Button {
                postComment()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(commentText.isEmpty ? .gray : .blue)
            }
            .disabled(commentText.isEmpty || viewModel.isPostingComment)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private func postComment() {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        commentText = ""
        isCommentFieldFocused = false

        _Concurrency.Task {
            await viewModel.postComment(for: eventId, text: text)
        }
    }
}

struct CommentRow: View {
    let comment: EventComment
    let canDelete: Bool
    let onDelete: () -> Void
    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let avatarURL = comment.userPhotoURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable()
                } placeholder: {
                    Circle().fill(Color.blue)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(comment.userName.prefix(1))
                            .foregroundColor(.white)
                            .font(.headline)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.userName)
                        .font(.subheadline.bold())
                    Text(comment.createdAt.timeAgo())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(comment.text)
                    .font(.body)
            }

            Spacer()

            if canDelete {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .confirmationDialog("Delete Comment", isPresented: $showingDeleteConfirm) {
                    Button("Delete Comment", role: .destructive) {
                        onDelete()
                    }
                } message: {
                    Text("Are you sure you want to delete this comment?")
                }
            }
        }
    }
}

extension Date {
    func timeAgo() -> String {
        let seconds = Date().timeIntervalSince(self)

        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else if seconds < 604800 {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: self)
        }
    }
}
