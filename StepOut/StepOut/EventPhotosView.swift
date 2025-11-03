import SwiftUI
import PhotosUI

struct EventPhotosView: View {
    let eventId: String
    let isEventOwner: Bool
    @StateObject private var viewModel: EventPhotosViewModel
    @State private var selectedPhoto: EventPhoto?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var captionText = ""
    @State private var showingCaptionInput = false
    @State private var pendingImageData: Data?
    @State private var isSelectionMode = false
    @State private var selectedPhotos: Set<String> = []
    @State private var isDownloading = false
    @State private var downloadMessage: String?
    @State private var showingDownloadAlert = false

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
        contentWithToolbar
            .onChange(of: selectedPhotoItem) { newValue in
                handlePhotoItemChange(nil, newValue)
            }
            .sheet(isPresented: $showingCaptionInput) { captionSheet }
            .sheet(item: $selectedPhoto) { photo in photoDetailView(for: photo) }
            .alert("Error", isPresented: errorBinding) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
    }

    private var contentWithToolbar: some View {
        mainContent
            .navigationTitle("Event Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.photos.isEmpty {
                        Button(isSelectionMode ? "Cancel" : "Select") {
                            withAnimation {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedPhotos.removeAll()
                                }
                            }
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !isSelectionMode {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Image(systemName: "photo.badge.plus").font(.title3)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                uploadProgressOverlay
            }
            .overlay(alignment: .bottom) {
                if isSelectionMode {
                    selectionToolbar
                }
            }
            .alert("Download Status", isPresented: $showingDownloadAlert) {
                Button("OK") { downloadMessage = nil }
            } message: {
                Text(downloadMessage ?? "")
            }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Info banner
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("All participants can add photos")
                            .font(.subheadline.bold())
                        Text("Tap 'Select' to download photos to your device")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

                if viewModel.photos.isEmpty && viewModel.isLoadingPhotos {
                    ProgressView("Loading photos...")
                        .padding()
                } else if viewModel.photos.isEmpty {
                    emptyStateView
                } else {
                    photoGridView
                }
            }
            .padding()
        }
        .task { await viewModel.loadPhotos(for: eventId) }
    }

    private var uploadProgressOverlay: some View {
        VStack(spacing: 0) {
            // Upload progress bar (Instagram-style)
            if viewModel.isUploadingPhoto {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Uploading photo...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .overlay(
                        Rectangle()
                            .fill(Color.blue)
                            .frame(height: 2)
                        , alignment: .bottom
                    )
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Success message
            if let successMessage = viewModel.successMessage {
                Text(successMessage)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(8)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .animation(.spring(response: 0.3), value: viewModel.isUploadingPhoto)
        .animation(.spring(response: 0.3), value: viewModel.successMessage)
        .allowsHitTesting(false)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func handlePhotoItemChange(_ old: PhotosPickerItem?, _ new: PhotosPickerItem?) {
        guard let new = new else { return }
        _Concurrency.Task {
            await loadSelectedPhoto(new)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No photos yet")
                .font(.title3.bold())
            Text("Be the first to share a photo from this event!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
    }

    private var photoGridView: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
            ForEach(viewModel.photos) { photo in
                Button {
                    if isSelectionMode {
                        togglePhotoSelection(photo.id)
                    } else {
                        selectedPhoto = photo
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: photo.photoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            case .failure:
                                Rectangle().fill(Color.gray.opacity(0.3))
                            case .empty:
                                ProgressView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 120, height: 120)
                        .clipped()
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelectionMode && selectedPhotos.contains(photo.id) ? Color.blue : Color.clear, lineWidth: 3)
                        )

                        // Selection checkmark (Apple Photos style)
                        if isSelectionMode {
                            Circle()
                                .fill(selectedPhotos.contains(photo.id) ? Color.blue : Color.white)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                )
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .opacity(selectedPhotos.contains(photo.id) ? 1 : 0)
                                )
                                .padding(6)
                        }
                    }
                }
            }
        }
    }

    private var captionSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Add a caption (optional)")
                    .font(.headline)
                TextField("Caption", text: $captionText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                Spacer()
            }
            .padding()
            .navigationTitle("Photo Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pendingImageData = nil
                        captionText = ""
                        showingCaptionInput = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        uploadPendingPhoto()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func photoDetailView(for photo: EventPhoto) -> some View {
        PhotoDetailView(
            photo: photo,
            canDelete: viewModel.canDelete(photo: photo, isEventOwner: isEventOwner),
            onDelete: {
                _Concurrency.Task {
                    await viewModel.deletePhoto(eventId: eventId, photoId: photo.id)
                }
                selectedPhoto = nil
            }
        )
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                if let uiImage = UIImage(data: data) {
                    let resized = uiImage.resized(to: 1920)
                    if let jpegData = resized.jpegData(compressionQuality: 0.8) {
                        await MainActor.run {
                            pendingImageData = jpegData
                            showingCaptionInput = true
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                viewModel.errorMessage = "Failed to load photo: \(error.localizedDescription)"
            }
        }
    }

    private func uploadPendingPhoto() {
        guard let imageData = pendingImageData else { return }
        let caption = captionText.isEmpty ? nil : captionText

        // Close sheet immediately
        pendingImageData = nil
        captionText = ""
        showingCaptionInput = false
        selectedPhotoItem = nil

        // Upload in background
        _Concurrency.Task {
            await viewModel.uploadPhoto(for: eventId, imageData: imageData, caption: caption)
        }
    }

    // MARK: - Selection Mode

    private var selectionToolbar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 20) {
                // Select All button
                Button {
                    if selectedPhotos.count == viewModel.photos.count {
                        selectedPhotos.removeAll()
                    } else {
                        selectedPhotos = Set(viewModel.photos.map { $0.id })
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selectedPhotos.count == viewModel.photos.count ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.title2)
                        Text(selectedPhotos.count == viewModel.photos.count ? "Deselect All" : "Select All")
                            .font(.caption)
                    }
                }
                .foregroundColor(.blue)

                Spacer()

                // Selected count
                Text("\(selectedPhotos.count) selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                // Download button
                Button {
                    downloadSelectedPhotos()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                        Text("Save")
                            .font(.caption)
                    }
                }
                .foregroundColor(selectedPhotos.isEmpty ? .gray : .blue)
                .disabled(selectedPhotos.isEmpty || isDownloading)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .transition(.move(edge: .bottom))
    }

    private func togglePhotoSelection(_ photoId: String) {
        if selectedPhotos.contains(photoId) {
            selectedPhotos.remove(photoId)
        } else {
            selectedPhotos.insert(photoId)
        }
    }

    private func downloadSelectedPhotos() {
        guard !selectedPhotos.isEmpty else { return }

        isDownloading = true
        let photosToDownload = viewModel.photos.filter { selectedPhotos.contains($0.id) }

        Task {
            var successCount = 0
            var failCount = 0

            for photo in photosToDownload {
                do {
                    let (data, _) = try await URLSession.shared.data(from: photo.photoURL)
                    guard let image = UIImage(data: data) else {
                        failCount += 1
                        continue
                    }

                    // Save to photo library
                    await MainActor.run {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    }
                    successCount += 1
                } catch {
                    failCount += 1
                }
            }

            await MainActor.run {
                isDownloading = false
                if failCount == 0 {
                    downloadMessage = "\(successCount) photo\(successCount == 1 ? "" : "s") saved to your library"
                } else {
                    downloadMessage = "\(successCount) saved, \(failCount) failed"
                }
                showingDownloadAlert = true

                // Exit selection mode
                isSelectionMode = false
                selectedPhotos.removeAll()
            }
        }
    }
}

struct PhotoDetailView: View {
    let photo: EventPhoto
    let canDelete: Bool
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AsyncImage(url: photo.photoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Text("Failed to load image")
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(photo.userName)
                            .font(.headline)
                        Spacer()
                        Text(photo.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let caption = photo.caption {
                        Text(caption)
                            .font(.body)
                    }
                }
                .padding()

                Spacer()
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if canDelete {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                    }
                }
            }
            .confirmationDialog("Delete Photo", isPresented: $showingDeleteConfirm) {
                Button("Delete Photo", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete this photo?")
            }
        }
    }
}

extension UIImage {
    func resized(to maxDimension: CGFloat) -> UIImage {
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        if ratio >= 1 { return self }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? self
    }
}
