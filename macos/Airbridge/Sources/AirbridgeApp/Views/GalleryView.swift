import SwiftUI
import Protocol

struct GalleryView: View {
    let galleryService: GalleryService
    let connectionService: ConnectionService

    @State private var selectedPhoto: GalleryPhotoMeta?

    var body: some View {
        Group {
            if !connectionService.isConnected {
                notConnectedView
            } else if galleryService.photos.isEmpty && !galleryService.isLoading {
                emptyView
            } else {
                groupedGallery
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .leading)
        .onAppear {
            if connectionService.isConnected && galleryService.photos.isEmpty {
                galleryService.loadPhotos()
            }
        }
        .onChange(of: connectionService.isConnected) { _, connected in
            if connected && galleryService.photos.isEmpty {
                galleryService.loadPhotos()
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo, galleryService: galleryService, onClose: { selectedPhoto = nil })
        }
    }

    private var notConnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(L10n.isPL ? "Galeria" : "Gallery")
                .font(.title3).fontWeight(.semibold).foregroundStyle(.secondary)
            Text(L10n.isPL
                ? "Połącz się z telefonem, aby przeglądać zdjęcia."
                : "Connect to your phone to browse photos.")
                .font(.subheadline).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(L10n.isPL ? "Brak zdjęć" : "No Photos")
                .font(.title3).fontWeight(.semibold).foregroundStyle(.secondary)
            Text(L10n.isPL
                ? "Nie znaleziono zdjęć na telefonie."
                : "No photos found on your phone.")
                .font(.subheadline).foregroundStyle(.tertiary)
            Button(L10n.isPL ? "Odśwież" : "Refresh") {
                galleryService.clearAndReload()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupedGallery: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(spacing: 10) {
                ForEach(galleryService.photos) { photo in
                    ThumbnailCell(photo: photo, galleryService: galleryService) {
                        selectedPhoto = photo
                    }
                    .onAppear {
                        if photo.id == galleryService.photos.last?.id {
                            galleryService.loadNextPage()
                        }
                    }
                }

                if galleryService.isLoading {
                    ProgressView()
                        .frame(width: 80)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    galleryService.clearAndReload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.isPL ? "Odśwież" : "Refresh")
            }
        }
    }
}

// MARK: - Thumbnail Cell (isolated to avoid full-grid re-renders)

private struct ThumbnailCell: View {
    let photo: GalleryPhotoMeta
    let galleryService: GalleryService
    let onTap: () -> Void

    @State private var image: NSImage?

    private let rowHeight: CGFloat = 220

    private var aspect: CGFloat {
        guard photo.height > 0 else { return 1 }
        return CGFloat(photo.width) / CGFloat(photo.height)
    }

    private var width: CGFloat {
        max(140, min(420, rowHeight * aspect))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.15))
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: width, height: rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onAppear { loadImage() }
        .onChange(of: galleryService.thumbnailImages[photo.id]) { _, newImage in
            image = newImage
        }
    }

    private func loadImage() {
        if let cached = galleryService.thumbnailImages[photo.id] {
            image = cached
        } else {
            galleryService.requestThumbnail(photoId: photo.id)
        }
    }
}

// MARK: - Photo Detail View

struct PhotoDetailView: View {
    let photo: GalleryPhotoMeta
    let galleryService: GalleryService
    let onClose: () -> Void
    @State private var downloaded = false

    var body: some View {
        VStack(spacing: 0) {
            // Photo
            ZStack {
                Color.black
                if let nsImage = galleryService.thumbnailImages[photo.id] {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Info
            VStack(spacing: 14) {
                HStack {
                    Text(photo.filename)
                        .font(.title3).fontWeight(.semibold)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                }

                HStack(spacing: 24) {
                    metaItem(icon: "photo", title: L10n.isPL ? "Rozdzielczość" : "Resolution", value: "\(photo.width) × \(photo.height)")
                    metaItem(icon: "doc", title: L10n.isPL ? "Rozmiar" : "Size", value: formatFileSize(photo.size))
                    metaItem(icon: "calendar", title: L10n.isPL ? "Data" : "Date", value: formatDate(photo.dateTaken))
                    metaItem(icon: "doc.text", title: "Format", value: photo.mimeType.replacingOccurrences(of: "image/", with: "").uppercased())
                }

                HStack(spacing: 12) {
                    Button(L10n.isPL ? "Zamknij" : "Close") {
                        onClose()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button {
                        galleryService.downloadPhoto(photoId: photo.id)
                        downloaded = true
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            downloaded = false
                        }
                    } label: {
                        Label(
                            downloaded
                                ? (L10n.isPL ? "Pobrano do Downloads" : "Saved to Downloads")
                                : (L10n.isPL ? "Pobierz oryginał" : "Download Original"),
                            systemImage: downloaded ? "checkmark.circle" : "arrow.down.circle.fill"
                        )
                        .frame(minWidth: 180)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 700, height: 600)
    }

    private func metaItem(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.callout).fontWeight(.medium)
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes > 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        } else if bytes > 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
        return "\(bytes) B"
    }

    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
