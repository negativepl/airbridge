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
        EmptyStateView(
            systemImage: "photo.on.rectangle",
            title: L10n.isPL ? "Galeria" : "Gallery",
            subtitle: L10n.isPL
                ? "Połącz się z telefonem, aby przeglądać zdjęcia."
                : "Connect to your phone to browse photos."
        )
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            EmptyStateView(
                systemImage: "photo.on.rectangle",
                title: L10n.isPL ? "Brak zdjęć" : "No Photos",
                subtitle: L10n.isPL
                    ? "Nie znaleziono zdjęć na telefonie."
                    : "No photos found on your phone."
            )
            Button(L10n.isPL ? "Odśwież" : "Refresh") {
                galleryService.clearAndReload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 80)
        }
    }

    private var groupedGallery: some View {
        GeometryReader { geo in
            let rowHeight = max(200, geo.size.height - 56)
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 12) {
                    ForEach(galleryService.photos) { photo in
                        ThumbnailCell(
                            photo: photo,
                            galleryService: galleryService,
                            height: rowHeight
                        ) {
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
                            .frame(width: 80, height: rowHeight)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
            }
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
    let height: CGFloat
    let onTap: () -> Void

    @State private var image: NSImage?

    private var aspect: CGFloat {
        guard photo.height > 0 else { return 1 }
        return CGFloat(photo.width) / CGFloat(photo.height)
    }

    private var width: CGFloat {
        max(180, min(720, height * aspect))
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
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    @State private var rotation: Angle = .zero
    @State private var scale: CGFloat = 1.0
    @State private var committedScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var downloaded = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            photoLayer

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(20)
        }
        .frame(minWidth: 760, idealWidth: 960, minHeight: 580, idealHeight: 720)
    }

    // MARK: - Photo with zoom / pan / rotation

    private var displayedImage: NSImage? {
        galleryService.previewImages[photo.id] ?? galleryService.thumbnailImages[photo.id]
    }

    private var photoLayer: some View {
        Group {
            if let nsImage = displayedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(rotation)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoomGesture)
                    .simultaneousGesture(panGesture)
                    .onTapGesture(count: 2) { toggleDoubleTapZoom() }
                    .animation(.airbridgeSmooth, value: rotation)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 80)
        .onAppear {
            galleryService.requestPreview(photoId: photo.id, maxSize: 1920)
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(0.8, min(6, committedScale * value.magnification))
            }
            .onEnded { _ in
                if scale < 1 {
                    resetZoomAndOffset()
                } else {
                    committedScale = scale
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                committedOffset = offset
            }
    }

    private func toggleDoubleTapZoom() {
        withAnimation(.airbridgeSmooth) {
            if scale > 1 {
                resetZoomAndOffset()
            } else {
                scale = 2
                committedScale = 2
            }
        }
    }

    private func resetZoomAndOffset() {
        withAnimation(.airbridgeSmooth) {
            scale = 1
            committedScale = 1
            offset = .zero
            committedOffset = .zero
        }
    }

    private var isAltered: Bool {
        rotation != .zero || scale != 1 || offset != .zero
    }

    // MARK: - Top bar (close + rotate/reset)

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .keyboardShortcut(.cancelAction)
            .help(L10n.isPL ? "Zamknij" : "Close")

            Spacer()

            HStack(spacing: 4) {
                iconButton(systemName: "rotate.left", help: L10n.isPL ? "Obróć w lewo" : "Rotate left") {
                    withAnimation(.airbridgeSmooth) { rotation -= .degrees(90) }
                }
                iconButton(systemName: "rotate.right", help: L10n.isPL ? "Obróć w prawo" : "Rotate right") {
                    withAnimation(.airbridgeSmooth) { rotation += .degrees(90) }
                }

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 2)

                iconButton(systemName: "arrow.counterclockwise", help: L10n.isPL ? "Resetuj widok" : "Reset view") {
                    withAnimation(.airbridgeSmooth) {
                        rotation = .zero
                        resetZoomAndOffset()
                    }
                }
                .disabled(!isAltered)
            }
            .padding(.horizontal, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Bottom bar (meta + download)

    private var bottomBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(photo.filename)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metaLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
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
                        ? (L10n.isPL ? "Pobrano" : "Downloaded")
                        : (L10n.isPL ? "Pobierz oryginał" : "Download Original"),
                    systemImage: downloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
            .symbolEffect(.bounce, value: downloaded)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private var metaLine: String {
        let res = "\(photo.width) × \(photo.height)"
        let size = formatFileSize(photo.size)
        let date = formatDate(photo.dateTaken)
        let format = photo.mimeType.replacingOccurrences(of: "image/", with: "").uppercased()
        return "\(res)  ·  \(size)  ·  \(format)  ·  \(date)"
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
