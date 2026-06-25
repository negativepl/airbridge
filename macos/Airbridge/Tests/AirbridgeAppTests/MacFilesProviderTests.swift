import XCTest
@testable import AirbridgeApp

final class MacFilesProviderTests: XCTestCase {
    private func tempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macfiles-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testResolveRejectsEscapes() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let p = MacFilesProvider(root: root)
        XCTAssertNotNil(p.resolve(""))                // root itself OK for listing
        XCTAssertNotNil(p.resolve("sub/file.txt"))    // inside OK (resolves lexically)
        XCTAssertNil(p.resolve("../escape"))          // parent escape rejected
        XCTAssertNil(p.resolve("/etc/passwd"))        // absolute rejected
        XCTAssertNil(p.resolve("sub/../../escape"))   // traversal rejected
    }

    func testListDirReturnsEntries() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "hi".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dir"), withIntermediateDirectories: true)
        let p = MacFilesProvider(root: root)
        let result = p.listDir("", page: 0, pageSize: 200, sortBy: "name", sortDir: "asc", foldersFirst: true)
        XCTAssertTrue(result.accessible)
        XCTAssertEqual(result.total, 2)
        XCTAssertEqual(result.entries.first?.name, "dir")          // folders first
        XCTAssertTrue(result.entries.first?.isDirectory ?? false)
        XCTAssertEqual(result.entries.last?.name, "a.txt")
    }
}
