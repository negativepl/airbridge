import Foundation
import AppKit
import Protocol

@Observable
@MainActor
final class GalleryService: MessageHandler, ActiveDeviceObserver {

    private(set) var photos: [GalleryPhotoMeta] = []
    private(set) var thumbnailImages: [String: NSImage] = [:]  // photoId -> cached small thumb
    private(set) var previewImages: [String: NSImage] = [:]    // photoId -> cached larger preview
    private(set) var totalCount: Int = 0
    private(set) var currentPage: Int = 0
    private(set) var isLoading: Bool = false
    /// The last listing request received no response within `requestTimeout`.
    /// Views show a retryable failure state instead of spinning forever.
    private(set) var loadFailed: Bool = false

    private var requestedThumbnails: Set<String> = []
    private var requestedPreviews: Set<String> = []
    private let pageSize = 50
    private weak var connectionService: ConnectionService?
    /// How long a listing request may wait for the phone's response before it
    /// counts as lost (frozen phone app, reply dropped on a live socket).
    /// Internal so tests can shorten it.
    @ObservationIgnored var requestTimeout: TimeInterval = 20
    @ObservationIgnored private var loadWatchdogTask: Task<Void, Never>?

    func configure(connectionService: ConnectionService) {
        self.connectionService = connectionService
    }

    // MARK: - Requests

    func loadPhotos(page: Int = 0) {
        guard let connectionService, connectionService.isConnected, !isLoading else { return }
        isLoading = true
        loadFailed = false
        if page == 0 {
            photos = []
            thumbnailImages = [:]
            requestedThumbnails = []
        }
        let message = Message.galleryRequest(page: page, pageSize: pageSize)
        Task {
            try? await connectionService.sendToActive(message)
        }
        startLoadWatchdog()
    }

    /// Fails the in-flight listing request when no response arrives in time —
    /// the WebSocket itself still looks healthy in that case, so without this
    /// the view would spin forever.
    private func startLoadWatchdog() {
        loadWatchdogTask?.cancel()
        loadWatchdogTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.requestTimeout * 1_000_000_000))
            guard !Task.isCancelled, self.isLoading else { return }
            self.isLoading = false
            self.loadFailed = true
        }
    }

    func clearAndReload() {
        loadWatchdogTask?.cancel()
        photos = []
        thumbnailImages = [:]
        previewImages = [:]
        requestedThumbnails = []
        requestedPreviews = []
        isLoading = false
        loadFailed = false
        currentPage = 0
        totalCount = 0
        loadPhotos()
    }

    func loadNextPage() {
        let nextPage = currentPage + 1
        let totalPages = (totalCount + pageSize - 1) / pageSize
        guard nextPage < totalPages else { return }
        loadPhotos(page: nextPage)
    }

    func requestThumbnail(photoId: String) {
        guard thumbnailImages[photoId] == nil,
              !requestedThumbnails.contains(photoId),
              let connectionService else { return }
        requestedThumbnails.insert(photoId)
        let message = Message.galleryThumbnailRequest(photoId: photoId)
        Task {
            try? await connectionService.sendToActive(message)
        }
    }

    func requestPreview(photoId: String, maxSize: Int = 1920) {
        // Skip only if we already have the image; always allow re-requesting
        // if nothing arrived (covers stale pending state after APK restart).
        guard previewImages[photoId] == nil,
              let connectionService else { return }
        requestedPreviews.insert(photoId)
        let message = Message.galleryPreviewRequest(photoId: photoId, maxSize: maxSize)
        NSLog("[Gallery] requesting preview for \(photoId) maxSize=\(maxSize)")
        Task {
            try? await connectionService.sendToActive(message)
        }
    }

    func downloadPhoto(photoId: String) {
        guard let connectionService else { return }
        let message = Message.galleryDownloadRequest(photoId: photoId)
        Task {
            try? await connectionService.sendToActive(message)
        }
    }

    // MARK: - ActiveDeviceObserver

    /// The device our requests target changed (switch, drop, or disconnect):
    /// any in-flight listing belongs to the previous phone — drop its
    /// loading/failure state so the next load is neither blocked nor
    /// mislabeled as failed.
    func activeDeviceChanged() {
        loadWatchdogTask?.cancel()
        isLoading = false
        loadFailed = false
    }

    // MARK: - MessageHandler

    func handleMessage(_ message: Message) {
        switch message {
        case .galleryResponse(let newPhotos, let total, let page):
            loadWatchdogTask?.cancel()
            loadFailed = false
            if page == 0 {
                photos = newPhotos
            } else {
                photos.append(contentsOf: newPhotos)
            }
            totalCount = total
            currentPage = page
            isLoading = false

            for photo in newPhotos {
                requestThumbnail(photoId: photo.id)
            }

        case .galleryThumbnailResponse(let photoId, let data):
            if let imageData = Data(base64Encoded: data),
               let image = NSImage(data: imageData) {
                thumbnailImages[photoId] = image
            }

        case .galleryPreviewResponse(let photoId, let data):
            NSLog("[Gallery] received preview response for \(photoId), data length=\(data.count)")
            if let imageData = Data(base64Encoded: data),
               let image = NSImage(data: imageData) {
                previewImages[photoId] = image
                NSLog("[Gallery] stored preview image \(image.size.width)x\(image.size.height)")
            } else {
                NSLog("[Gallery] failed to decode preview image data")
            }
            requestedPreviews.remove(photoId)

        default:
            break
        }
    }
}
