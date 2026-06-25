import Foundation
import Protocol
import UniformTypeIdentifiers
import QuickLookThumbnailing
import AppKit

/// Browses the Mac's home directory for the phone. Relative paths use "/"; root ("") == home.
/// Every resolve is contained to the root (symlink-resolved) — mirror of FilesProvider's guard.
final class MacFilesProvider {
    private let root: URL
    private let rootCanonical: String

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.root = root
        self.rootCanonical = root.resolvingSymlinksInPath().path
    }

    /// Absolute URL for a relative path, only if it stays inside root. Empty == root.
    func resolve(_ relPath: String) -> URL? {
        // Reject absolute paths (starting with "/") before appending — appendingPathComponent
        // on macOS treats an absolute component as relative (prepends root), so the canonical
        // check below would incorrectly allow e.g. resolve("/etc/passwd").
        guard !relPath.hasPrefix("/") else { return nil }
        let url = relPath.isEmpty ? root : root.appendingPathComponent(relPath)
        let canonical = url.resolvingSymlinksInPath().path
        if canonical == rootCanonical { return url }          // root itself
        guard canonical.hasPrefix(rootCanonical + "/") else { return nil }
        return url
    }

    func entry(for url: URL, parentRel: String) -> FileEntry {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let isDir = values?.isDirectory ?? false
        let modifiedMillis = Int64((values?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)
        let child = parentRel.isEmpty ? url.lastPathComponent : "\(parentRel)/\(url.lastPathComponent)"
        return FileEntry(
            name: url.lastPathComponent,
            relativePath: child,
            isDirectory: isDir,
            size: isDir ? 0 : Int64(values?.fileSize ?? 0),
            modified: modifiedMillis,
            mimeType: isDir ? "inode/directory" : Self.mime(for: url)
        )
    }

    /// Returns (page entries, total, accessible). `accessible == false` means the directory
    /// could not be read (TCC-gated) — caller maps it to needsPermission.
    func listDir(_ relPath: String, page: Int, pageSize: Int,
                 sortBy: String, sortDir: String, foldersFirst: Bool)
    -> (entries: [FileEntry], total: Int, accessible: Bool) {
        guard let dir = resolve(relPath) else { return ([], 0, true) }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else {
            return ([], 0, false)   // unreadable → permission needed
        }
        let all = children.map { entry(for: $0, parentRel: relPath) }
        let sorted = Self.sort(all, sortBy: sortBy, sortDir: sortDir, foldersFirst: foldersFirst)
        return (Self.paginate(sorted, page: page, pageSize: pageSize), sorted.count, true)
    }

    func searchDir(_ query: String, page: Int, pageSize: Int,
                   sortBy: String, sortDir: String, foldersFirst: Bool)
    -> (entries: [FileEntry], total: Int) {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return ([], 0) }
        var hits: [FileEntry] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                   options: [.skipsHiddenFiles]) {
            for case let url as URL in en {
                if url.lastPathComponent.lowercased().contains(needle) {
                    // Resolve the parent's path canonically before slicing: on macOS,
                    // FileManager.enumerator returns /private/var/... paths even when root
                    // is /var/... (symlink), so we must resolve both sides consistently.
                    let parentCanonical = url.deletingLastPathComponent().resolvingSymlinksInPath().path
                    let parentRel = String(parentCanonical
                        .dropFirst(rootCanonical.count).drop(while: { $0 == "/" }))
                    hits.append(entry(for: url, parentRel: parentRel))
                    if hits.count >= Self.searchLimit { break }
                }
            }
        }
        let sorted = Self.sort(hits, sortBy: sortBy, sortDir: sortDir, foldersFirst: foldersFirst)
        return (Self.paginate(sorted, page: page, pageSize: pageSize), sorted.count)
    }

    func folderStats(_ relPath: String) -> (dirCount: Int, fileCount: Int, totalSize: Int64) {
        guard let dir = resolve(relPath),
              let children = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return (0, 0, 0)
        }
        var dirCount = 0, fileCount = 0
        for c in children {
            if (try? c.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { dirCount += 1 }
            else { fileCount += 1 }
        }
        var total: Int64 = 0
        if let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in en {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return (dirCount, fileCount, total)
    }

    func fileURL(_ relPath: String) -> URL? {
        guard let url = resolve(relPath), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Helpers (mirror FilesProvider.sortFileEntries / paginate)

    static let searchLimit = 500

    static func sort(_ entries: [FileEntry], sortBy: String, sortDir: String, foldersFirst: Bool) -> [FileEntry] {
        let base: (FileEntry, FileEntry) -> Bool
        switch sortBy {
        case "size":     base = { $0.size < $1.size }
        case "modified": base = { $0.modified < $1.modified }
        case "type":     base = { ($0.name as NSString).pathExtension.lowercased() < ($1.name as NSString).pathExtension.lowercased() }
        default:         base = { $0.name.lowercased() < $1.name.lowercased() }
        }
        var sorted = entries.sorted(by: base)
        if sortDir == "desc" { sorted.reverse() }
        if foldersFirst {
            sorted.sort { a, b in a.isDirectory && !b.isDirectory }
        }
        return sorted
    }

    static func paginate(_ sorted: [FileEntry], page: Int, pageSize: Int) -> [FileEntry] {
        let from = min(page * pageSize, sorted.count)
        let to = min(from + pageSize, sorted.count)
        return Array(sorted[from..<to])
    }

    static func mime(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

// MARK: - Thumbnail

extension MacFilesProvider {
    /// Returns a 400px JPEG base64 thumbnail for image/video files; nil for everything else.
    func thumbnailBase64(_ relPath: String, completion: @escaping @Sendable (String?) -> Void) {
        guard let url = fileURL(relPath) else { return completion(nil) }
        let mime = Self.mime(for: url)
        guard mime.hasPrefix("image/") || mime.hasPrefix("video/") else { return completion(nil) }
        let size = CGSize(width: 400, height: 400)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 1,
                                                   representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let cg = rep?.cgImage else { return completion(nil) }
            let bitmap = NSBitmapImageRep(cgImage: cg)
            let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
            completion(jpeg?.base64EncodedString())
        }
    }
}
