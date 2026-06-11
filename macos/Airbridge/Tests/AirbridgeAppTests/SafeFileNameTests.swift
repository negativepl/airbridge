import XCTest
@testable import AirbridgeApp

final class SafeFileNameTests: XCTestCase {

    // MARK: - sanitize

    func testPlainFilenamePassesThrough() {
        XCTAssertEqual(SafeFileName.sanitize("photo.jpg"), "photo.jpg")
    }

    func testTraversalIsReducedToLastComponent() {
        XCTAssertEqual(SafeFileName.sanitize("../../etc/passwd"), "passwd")
        XCTAssertEqual(SafeFileName.sanitize("a/b/c.txt"), "c.txt")
        XCTAssertEqual(SafeFileName.sanitize("/etc/passwd"), "passwd")
    }

    func testDotNamesAreRejected() {
        XCTAssertNil(SafeFileName.sanitize("."))
        XCTAssertNil(SafeFileName.sanitize(".."))
        XCTAssertNil(SafeFileName.sanitize("a/.."))
        XCTAssertNil(SafeFileName.sanitize(""))
        XCTAssertNil(SafeFileName.sanitize("/"))
    }

    func testTrailingSlashUsesDirectoryName() {
        XCTAssertEqual(SafeFileName.sanitize("dir/file/"), "file")
    }

    // MARK: - resolvedURL

    func testResolvedURLStaysInsideDirectory() throws {
        let dir = URL(fileURLWithPath: "/tmp/airbridge-test")
        let url = try XCTUnwrap(SafeFileName.resolvedURL(in: dir, filename: "report.pdf"))
        XCTAssertEqual(url.path, "/tmp/airbridge-test/report.pdf")
    }

    func testResolvedURLRejectsEscapes() {
        let dir = URL(fileURLWithPath: "/tmp/airbridge-test")
        XCTAssertNil(SafeFileName.resolvedURL(in: dir, filename: ".."))
        // Traversal collapses to the last component — never a parent path.
        XCTAssertEqual(
            SafeFileName.resolvedURL(in: dir, filename: "../../x")?.path,
            "/tmp/airbridge-test/x"
        )
        XCTAssertEqual(
            SafeFileName.resolvedURL(in: dir, filename: "../../../etc/passwd")?.path,
            "/tmp/airbridge-test/passwd"
        )
    }
}
