import XCTest
@testable import AirbridgeApp

/// Tests that `FileTransferService.uniqueDestination(in:filename:)` is immune
/// to path-traversal attacks via network-supplied filenames.
@MainActor
final class FileTransferServiceDestinationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("airbridge-dest-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Path traversal containment

    /// A crafted `../../escape.sh` must NOT produce a URL outside `tempDir`.
    /// Pre-fix, `uniqueDestination` called `dir.appendingPathComponent(filename)`
    /// directly, so `../../escape.sh` would have resolved outside the target dir.
    /// Post-fix it must return nil (traversal rejected) or a URL inside `tempDir`.
    func testTraversalFilenameDoesNotEscapeDestinationDir() {
        let result = FileTransferService.uniqueDestination(in: tempDir, filename: "../../escape.sh")
        // The only safe outcomes are:
        // 1. nil  — traversal rejected entirely (preferred for a pure `..` component)
        // 2. A URL that still lives inside tempDir (e.g. tempDir/escape.sh)
        if let url = result {
            let dirPath = tempDir.standardizedFileURL.path
            let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
            XCTAssertTrue(
                url.standardizedFileURL.path.hasPrefix(prefix),
                "uniqueDestination must not escape tempDir; got \(url.path)"
            )
        }
        // nil is also an accepted (and preferred) outcome — no assertion needed for that branch
    }

    /// A deeply nested traversal must also be contained.
    func testDeepTraversalFilenameIsContained() {
        let result = FileTransferService.uniqueDestination(
            in: tempDir, filename: "../../../Library/LaunchAgents/evil.plist"
        )
        if let url = result {
            let dirPath = tempDir.standardizedFileURL.path
            let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
            XCTAssertTrue(
                url.standardizedFileURL.path.hasPrefix(prefix),
                "uniqueDestination must not escape tempDir; got \(url.path)"
            )
        }
    }

    /// A plain filename with no traversal components must work normally.
    func testPlainFilenameProducesURLInsideDir() throws {
        let result = try XCTUnwrap(
            FileTransferService.uniqueDestination(in: tempDir, filename: "photo.jpg"),
            "Plain filename must produce a non-nil URL"
        )
        let dirPath = tempDir.standardizedFileURL.path
        let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
        XCTAssertTrue(result.standardizedFileURL.path.hasPrefix(prefix))
        XCTAssertEqual(result.lastPathComponent, "photo.jpg")
    }

    /// When a file with the same name already exists the dedup counter is applied.
    func testDedupCounterAppliedWhenFileExists() throws {
        // Create photo.jpg inside tempDir so the first candidate collides.
        let existing = tempDir.appendingPathComponent("photo.jpg")
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        let result = try XCTUnwrap(
            FileTransferService.uniqueDestination(in: tempDir, filename: "photo.jpg")
        )
        XCTAssertEqual(result.lastPathComponent, "photo (2).jpg")
        let dirPath = tempDir.standardizedFileURL.path
        let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
        XCTAssertTrue(result.standardizedFileURL.path.hasPrefix(prefix))
    }
}
