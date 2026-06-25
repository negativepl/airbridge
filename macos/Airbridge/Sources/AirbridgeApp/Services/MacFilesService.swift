import Foundation
import Networking
import Protocol

@MainActor
final class MacFilesService {
    private let provider = MacFilesProvider()
    private weak var server: WebSocketServer?
    private weak var uploadServer: HttpUploadServer?

    func configure(server: WebSocketServer, uploadServer: HttpUploadServer) {
        self.server = server
        self.uploadServer = uploadServer
    }

    func handle(_ message: Message, connectionId: String) {
        switch message {
        case .macFilesListRequest(let path, let page, let pageSize, let sortBy, let sortDir, let foldersFirst, let query):
            let result: (entries: [FileEntry], total: Int, accessible: Bool)
            if query.isEmpty {
                result = provider.listDir(path, page: page, pageSize: pageSize, sortBy: sortBy, sortDir: sortDir, foldersFirst: foldersFirst)
            } else {
                let s = provider.searchDir(query, page: page, pageSize: pageSize, sortBy: sortBy, sortDir: sortDir, foldersFirst: foldersFirst)
                result = (s.entries, s.total, true)
            }
            send(.macFilesListResponse(path: path, entries: result.entries, totalCount: result.total,
                                       page: page, needsPermission: !result.accessible), to: connectionId)

        case .macFileThumbnailRequest(let path):
            provider.thumbnailBase64(path) { [weak self] data in
                guard let data else { return }
                Task { @MainActor in self?.send(.macFileThumbnailResponse(path: path, data: data), to: connectionId) }
            }

        case .macFolderStatsRequest(let path):
            let s = provider.folderStats(path)
            send(.macFolderStatsResponse(path: path, dirCount: s.dirCount, fileCount: s.fileCount, totalSize: s.totalSize), to: connectionId)

        case .macFileDownloadRequest(let transferId, let path):
            guard let url = provider.fileURL(path) else { return }
            let name = url.lastPathComponent
            let mime = MacFilesProvider.mime(for: url)
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            guard let uploadServer else { return }
            Task {
                await uploadServer.registerOutgoingFile(transferId: transferId, fileURL: url, filename: name,
                                                        mimeType: mime, onProgress: { _, _ in }, onComplete: { _ in })
                await MainActor.run { self.send(.macFileDownloadReady(transferId: transferId, filename: name, mimeType: mime, fileSize: size), to: connectionId) }
            }

        default:
            break
        }
    }

    private func send(_ message: Message, to connectionId: String) {
        guard let server else { return }
        Task { try? await server.sendTo(message, connectionId: connectionId) }
    }
}
