import Foundation
import AppKit
import Protocol

enum FileSortKey: String, CaseIterable, Identifiable {
    case name, size, modified, type
    var id: String { rawValue }
}

enum FileViewMode: String {
    case list, grid
}

struct FolderStats: Equatable {
    let dirCount: Int
    let fileCount: Int
    let totalSize: Int64
}

@Observable
@MainActor
final class FilesBrowserService: MessageHandler {

    private(set) var currentPath: String = ""
    private(set) var entries: [FileEntry] = []
    private(set) var totalCount: Int = 0
    private(set) var currentPage: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var needsPermission: Bool = false
    private(set) var hasLoadedOnce: Bool = false
    private(set) var thumbnails: [String: NSImage] = [:]   // relativePath -> thumb
    private(set) var folderStats: [String: FolderStats] = [:]  // relativePath -> stats

    private(set) var searchQuery: String = ""
    /// Komunikat błędu ostatniego usuwania (nil = brak). UI pokazuje alert i czyści.
    var deleteError: String? = nil
    var sortBy: FileSortKey = .name {
        didSet { guard oldValue != sortBy, !isLoadingSortPrefs else { return }; persistSort(); reload() }
    }
    var sortAscending: Bool = true {
        didSet { guard oldValue != sortAscending, !isLoadingSortPrefs else { return }; persistSort(); reload() }
    }
    var foldersFirst: Bool = true {
        didSet { guard oldValue != foldersFirst, !isLoadingSortPrefs else { return }; persistSort(); reload() }
    }
    /// Czy aktualnie pokazujemy wyniki wyszukiwania (globalne, rekurencyjne).
    var isSearching: Bool { !searchQuery.isEmpty }

    private var isLoadingSortPrefs = false
    private var requestedThumbnails: Set<String> = []
    private var requestedFolderStats: Set<String> = []
    private let pageSize = 200
    private weak var connectionService: ConnectionService?
    private weak var fileTransferService: FileTransferService?

    func configure(connectionService: ConnectionService, fileTransferService: FileTransferService) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
    }

    private enum DefaultsKey {
        static let sortBy        = "files.sortBy"
        static let sortAscending = "files.sortAscending"
        static let foldersFirst  = "files.foldersFirst"
    }

    func loadPersistedSort() {
        isLoadingSortPrefs = true
        let d = UserDefaults.standard
        if let raw = d.string(forKey: DefaultsKey.sortBy), let key = FileSortKey(rawValue: raw) {
            sortBy = key
        }
        if d.object(forKey: DefaultsKey.sortAscending) != nil {
            sortAscending = d.bool(forKey: DefaultsKey.sortAscending)
        }
        if d.object(forKey: DefaultsKey.foldersFirst) != nil {
            foldersFirst = d.bool(forKey: DefaultsKey.foldersFirst)
        }
        isLoadingSortPrefs = false
    }

    private func persistSort() {
        let d = UserDefaults.standard
        d.set(sortBy.rawValue, forKey: DefaultsKey.sortBy)
        d.set(sortAscending, forKey: DefaultsKey.sortAscending)
        d.set(foldersFirst, forKey: DefaultsKey.foldersFirst)
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
            folderStats = [:]
            requestedFolderStats = []
        }
        let message = Message.filesListRequest(
            path: path, page: page, pageSize: pageSize,
            sortBy: sortBy.rawValue,
            sortDir: sortAscending ? "asc" : "desc",
            foldersFirst: foldersFirst,
            query: searchQuery
        )
        Task { try? await connectionService.broadcast(message) }
    }

    func reload() { open(path: currentPath) }

    private var searchTask: Task<Void, Never>?

    /// Ustawia frazę z debounce ~300 ms; min. 2 znaki, inaczej czyści wyszukiwanie.
    func setSearchQuery(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        let effective = trimmed.count >= 2 ? trimmed : ""
        guard effective != searchQuery else { return }
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return   // anulowane — nic nie rób
            }
            guard let self else { return }
            self.searchQuery = effective
            self.open(path: self.currentPath)
        }
    }

    func navigateUp() {
        guard !currentPath.isEmpty else { return }
        var segments = currentPath.split(separator: "/").map(String.init)
        segments.removeLast()
        open(path: segments.joined(separator: "/"))
    }

    /// Wejście do folderu lub pobranie pliku.
    func activate(_ entry: FileEntry) {
        if entry.isDirectory {
            if !searchQuery.isEmpty {
                searchTask?.cancel()
                searchQuery = ""
            }
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

    // MARK: - Folder stats

    /// Rows shown to the user: the leading run of entries that are fully ready
    /// (a file is ready immediately; a folder is ready once its stats arrive).
    /// This reveals rows top-to-bottom and never shows a half-loaded folder.
    var displayedEntries: [FileEntry] {
        // W trybie search wyniki to mix z różnych ścieżek — pokazujemy od razu,
        // bez czekania na rekurencyjne folder-stats.
        if isSearching { return entries }
        var result: [FileEntry] = []
        for e in entries {
            let ready = e.isDirectory ? folderStats[e.relativePath] != nil : true
            if ready { result.append(e) } else { break }
        }
        return result
    }

    var isLoadingMoreRows: Bool { displayedEntries.count < entries.count }

    /// Request folder stats one at a time, in list order. Serializing keeps the
    /// phone from running many recursive size walks at once (which is slow) and
    /// makes rows fill in from the top down.
    private func requestNextFolderStats() {
        guard let connectionService else { return }
        // Only one in flight: if the first unresolved folder is already
        // requested, we're waiting on it.
        guard let next = entries.first(where: { $0.isDirectory && folderStats[$0.relativePath] == nil }) else { return }
        guard !requestedFolderStats.contains(next.relativePath) else { return }
        requestedFolderStats.insert(next.relativePath)
        Task { try? await connectionService.broadcast(.folderStatsRequest(path: next.relativePath)) }
    }

    // MARK: - Transfer

    func download(_ entry: FileEntry) {
        guard let connectionService else { return }
        let transferId = UUID().uuidString
        Task { try? await connectionService.broadcast(.fileDownloadRequest(transferId: transferId, path: entry.relativePath)) }
    }

    func delete(_ entry: FileEntry) {
        guard let connectionService else { return }
        Task { try? await connectionService.broadcast(.fileDeleteRequest(path: entry.relativePath)) }
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
            hasLoadedOnce = true
            for entry in newEntries { requestThumbnail(entry) }
            requestNextFolderStats()

        case .fileThumbnailResponse(let path, let data):
            if let imageData = Data(base64Encoded: data), let image = NSImage(data: imageData) {
                thumbnails[path] = image
            }

        case .folderStatsResponse(let path, let dirCount, let fileCount, let totalSize):
            folderStats[path] = FolderStats(dirCount: dirCount, fileCount: fileCount, totalSize: totalSize)
            requestNextFolderStats()

        case .fileDeleteResponse(_, let success, let error):
            if success {
                reload()
            } else {
                deleteError = error ?? "delete_failed"
            }

        default:
            break
        }
    }
}
