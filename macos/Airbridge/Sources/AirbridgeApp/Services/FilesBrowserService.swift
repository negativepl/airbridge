import Foundation
import AppKit
import Protocol

@Observable
@MainActor
final class FilesBrowserService: MessageHandler {

    private(set) var currentPath: String = ""
    private(set) var entries: [FileEntry] = []
    private(set) var totalCount: Int = 0
    private(set) var currentPage: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var needsPermission: Bool = false
    private(set) var thumbnails: [String: NSImage] = [:]   // relativePath -> thumb

    private var requestedThumbnails: Set<String> = []
    private let pageSize = 200
    private weak var connectionService: ConnectionService?
    private weak var fileTransferService: FileTransferService?

    func configure(connectionService: ConnectionService, fileTransferService: FileTransferService) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
    }

    /// Breadcrumb segmenty bieżącej ścieżki.
    var breadcrumbs: [String] {
        currentPath.split(separator: "/").map(String.init)
    }

    // MARK: - Navigation

    func open(path: String, page: Int = 0) {
        guard let connectionService, connectionService.isConnected else { return }
        isLoading = true
        if page == 0 {
            currentPath = path
            entries = []
            thumbnails = [:]
            requestedThumbnails = []
        }
        let message = Message.filesListRequest(path: path, page: page, pageSize: pageSize)
        Task { try? await connectionService.broadcast(message) }
    }

    func reload() { open(path: currentPath) }

    func navigateUp() {
        guard !currentPath.isEmpty else { return }
        var segments = currentPath.split(separator: "/").map(String.init)
        segments.removeLast()
        open(path: segments.joined(separator: "/"))
    }

    /// Wejście do folderu lub pobranie pliku.
    func activate(_ entry: FileEntry) {
        if entry.isDirectory {
            open(path: entry.relativePath)
        } else {
            download(entry)
        }
    }

    func loadNextPage() {
        let nextPage = currentPage + 1
        let totalPages = (totalCount + pageSize - 1) / pageSize
        guard nextPage < totalPages, !isLoading else { return }
        open(path: currentPath, page: nextPage)
    }

    // MARK: - Thumbnails

    func requestThumbnail(_ entry: FileEntry) {
        guard !entry.isDirectory,
              entry.mimeType.hasPrefix("image/"),
              thumbnails[entry.relativePath] == nil,
              !requestedThumbnails.contains(entry.relativePath),
              let connectionService else { return }
        requestedThumbnails.insert(entry.relativePath)
        Task { try? await connectionService.broadcast(.fileThumbnailRequest(path: entry.relativePath)) }
    }

    // MARK: - Transfer

    func download(_ entry: FileEntry) {
        guard let connectionService else { return }
        let transferId = UUID().uuidString
        Task { try? await connectionService.broadcast(.fileDownloadRequest(transferId: transferId, path: entry.relativePath)) }
    }

    func upload(urls: [URL]) {
        guard let fileTransferService else { return }
        for url in urls {
            fileTransferService.sendFile(url: url, destinationDir: currentPath)
        }
    }

    // MARK: - MessageHandler

    func handleMessage(_ message: Message) {
        switch message {
        case .filesListResponse(let path, let newEntries, let total, let page, let needsPerm):
            guard path == currentPath else { return }
            needsPermission = needsPerm
            if page == 0 {
                entries = newEntries
            } else {
                entries.append(contentsOf: newEntries)
            }
            totalCount = total
            currentPage = page
            isLoading = false
            for entry in newEntries { requestThumbnail(entry) }

        case .fileThumbnailResponse(let path, let data):
            if let imageData = Data(base64Encoded: data), let image = NSImage(data: imageData) {
                thumbnails[path] = image
            }

        default:
            break
        }
    }
}
