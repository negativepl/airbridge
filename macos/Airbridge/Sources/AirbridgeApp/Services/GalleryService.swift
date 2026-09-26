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

    // MARK: - Cache

    private var deviceKey: String? { connectionService?.activeDevice?.publicKey }
    private let cache = DeviceDataCache.shared

    private struct CachedListing: Codable {
        let photos: [GalleryPhotoMeta]
        let totalCount: Int
    }

    /// Show the last listing this phone gave us, if any, before asking again.
    private func restoreFromCache() {
        guard photos.isEmpty, let deviceKey,
              let cached = cache.load(CachedListing.self, device: deviceKey, name: "gallery") else { return }
        photos = cached.photos
        totalCount = cached.totalCount
        currentPage = 0
    }

    // MARK: - Requests

    func loadPhotos(page: Int = 0) {
        guard let connectionService, connectionService.isConnected, !isLoading else { return }
        isLoading = true
        loadFailed = false
        if page == 0 {
            // Keep whatever is on screen (or restore the cached listing) while
            // the fresh page 0 is on its way; the response replaces it.
            restoreFromCache()
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
        if let deviceKey, let cached = cache.loadImage(device: deviceKey, folder: "gallery-thumbs", key: photoId) {
            thumbnailImages[photoId] = cached
            return
        }
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

    /// Ask the phone to delete a photo. The phone shows its own consent sheet;
    /// the photo leaves this listing only when it confirms the deletion.
    func deletePhoto(photoId: String) {
        guard let connectionService else { return }
        deleteError = nil
        Diag.log("Gallery", "delete requested for photo \(photoId)")
        Task {
            do { try await connectionService.sendToActive(Message.galleryDeleteRequest(photoId: photoId)) }
            catch { Diag.log("Gallery", "delete request failed to send: \(error)") }
        }
    }

    /// Last deletion failure ("declined", "not_found", …), for the view to show.
    var deleteError: String?

    // MARK: - ActiveDeviceObserver

    /// The device our requests target changed (switch, drop, or disconnect):
    /// any in-flight listing and all cached data belong to the previous phone
    /// — drop them so the next load is neither blocked nor mislabeled as
    /// failed, and the old phone's photos are never shown as the new one's.
    func activeDeviceChanged() {
        loadWatchdogTask?.cancel()
        isLoading = false
        loadFailed = false
        photos = []
        thumbnailImages = [:]
        previewImages = [:]
        requestedThumbnails = []
        requestedPreviews = []
        totalCount = 0
        currentPage = 0
        restoreFromCache()
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
            if let deviceKey {
                cache.save(CachedListing(photos: photos, totalCount: total), device: deviceKey, name: "gallery")
            }

            for photo in newPhotos {
                requestThumbnail(photoId: photo.id)
            }

        case .galleryDeleteResponse(let photoId, let success, let error):
            if success {
                photos.removeAll { $0.id == photoId }
                thumbnailImages[photoId] = nil
                previewImages[photoId] = nil
                totalCount = max(0, totalCount - 1)
                if let deviceKey {
                    cache.save(CachedListing(photos: photos, totalCount: totalCount), device: deviceKey, name: "gallery")
                }
            } else {
                deleteError = error ?? "delete_failed"
            }

        case .galleryThumbnailResponse(let photoId, let data):
            if let imageData = Data(base64Encoded: data),
               let image = NSImage(data: imageData) {
                thumbnailImages[photoId] = image
                if let deviceKey {
                    cache.saveImage(imageData, device: deviceKey, folder: "gallery-thumbs", key: photoId)
                }
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
