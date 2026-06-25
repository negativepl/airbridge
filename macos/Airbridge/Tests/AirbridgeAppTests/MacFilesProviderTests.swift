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

    func testSearchDirRelativePath() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // File at root level
        try "hello".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        // File in subdirectory
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "world".write(to: sub.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let p = MacFilesProvider(root: root)
        // Search for "a.txt"
        let resultA = p.searchDir("a.txt", page: 0, pageSize: 200,
                                  sortBy: "name", sortDir: "asc", foldersFirst: false)
        XCTAssertEqual(resultA.total, 1, "Expected exactly one hit for 'a.txt'")
        let entryA = try XCTUnwrap(resultA.entries.first)
        XCTAssertEqual(entryA.relativePath, "a.txt",
                       "Root-level file must have relativePath == 'a.txt', got '\(entryA.relativePath)'")

        // Search for "b.txt"
        let resultB = p.searchDir("b.txt", page: 0, pageSize: 200,
                                  sortBy: "name", sortDir: "asc", foldersFirst: false)
        XCTAssertEqual(resultB.total, 1, "Expected exactly one hit for 'b.txt'")
        let entryB = try XCTUnwrap(resultB.entries.first)
        XCTAssertEqual(entryB.relativePath, "sub/b.txt",
                       "Nested file must have relativePath == 'sub/b.txt', got '\(entryB.relativePath)'")
    }

    func testThumbnailNilForTextFile() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "hi".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let p = MacFilesProvider(root: root)
        let exp = expectation(description: "thumb")
        p.thumbnailBase64("a.txt") { result in XCTAssertNil(result); exp.fulfill() }
        wait(for: [exp], timeout: 5)
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
