import Foundation
import AppKit
import Protocol

@Observable
@MainActor
final class GalleryService: MessageHandler {

    private(set) var photos: [GalleryPhotoMeta] = []
    private(set) var thumbnailImages: [String: NSImage] = [:]  // photoId -> cached small thumb
    private(set) var previewImages: [String: NSImage] = [:]    // photoId -> cached larger preview
    private(set) var totalCount: Int = 0
    private(set) var currentPage: Int = 0
    private(set) var isLoading: Bool = false

    private var requestedThumbnails: Set<String> = []
    private var requestedPreviews: Set<String> = []
    private let pageSize = 50
    private weak var connectionService: ConnectionService?

    func configure(connectionService: ConnectionService) {
        self.connectionService = connectionService
    }

    // MARK: - Requests

    func loadPhotos(page: Int = 0) {
        guard let connectionService, connectionService.isConnected, !isLoading else { return }
        isLoading = true
        if page == 0 {
            photos = []
            thumbnailImages = [:]
            requestedThumbnails = []
        }
        let message = Message.galleryRequest(page: page, pageSize: pageSize)
        Task {
            try? await connectionService.broadcast(message)
        }
    }

    func clearAndReload() {
        photos = []
        thumbnailImages = [:]
        previewImages = [:]
        requestedThumbnails = []
        requestedPreviews = []
        isLoading = false
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
            try? await connectionService.broadcast(message)
        }
    }

    func requestPreview(photoId: String, maxSize: Int = 1920) {
        guard previewImages[photoId] == nil,
              !requestedPreviews.contains(photoId),
              let connectionService else { return }
        requestedPreviews.insert(photoId)
        let message = Message.galleryPreviewRequest(photoId: photoId, maxSize: maxSize)
        Task {
            try? await connectionService.broadcast(message)
        }
    }

    func downloadPhoto(photoId: String) {
        guard let connectionService else { return }
        let message = Message.galleryDownloadRequest(photoId: photoId)
        Task {
            try? await connectionService.broadcast(message)
        }
    }

    // MARK: - MessageHandler

    func handleMessage(_ message: Message) {
        switch message {
        case .galleryResponse(let newPhotos, let total, let page):
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
            if let imageData = Data(base64Encoded: data),
               let image = NSImage(data: imageData) {
                previewImages[photoId] = image
            }
            requestedPreviews.remove(photoId)

        default:
            break
        }
    }
}
