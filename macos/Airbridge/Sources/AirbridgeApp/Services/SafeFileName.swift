import Foundation

/// Path-traversal protection for filenames received from the network.
///
/// Every code path that writes a received file under a local directory must
/// go through this helper — a peer-supplied name like `"../../x"` must never
/// be able to escape the destination directory.
enum SafeFileName {

    /// Returns just the final path component of `raw`, or `nil` when the
    /// result is empty or a dot-name (`"."` / `".."`) that could be used to
    /// escape the destination directory.
    static func sanitize(_ raw: String) -> String? {
        let name = (raw as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name != "/" else { return nil }
        return name
    }

    /// Builds `directory/filename` after sanitizing, then verifies that the
    /// standardized result still lives inside `directory`.
    /// Returns `nil` on any escape attempt.
    static func resolvedURL(in directory: URL, filename: String) -> URL? {
        guard let name = sanitize(filename) else { return nil }
        let fileURL = directory.appendingPathComponent(name).standardizedFileURL
        let dirPath = directory.standardizedFileURL.path
        guard fileURL.path.hasPrefix(dirPath.hasSuffix("/") ? dirPath : dirPath + "/") else { return nil }
        return fileURL
    }
}
