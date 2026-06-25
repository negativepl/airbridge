import XCTest
@testable import Protocol

final class MacFilesMessageTests: XCTestCase {
    private func roundTrip(_ message: Message) throws -> Message {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(Message.self, from: data)
    }

    func testListRequestRoundTrips() throws {
        let msg = Message.macFilesListRequest(path: "Documents", page: 1, pageSize: 200,
                                              sortBy: "modified", sortDir: "desc",
                                              foldersFirst: true, query: "report")
        guard case let .macFilesListRequest(path, page, pageSize, sortBy, sortDir, foldersFirst, query) = try roundTrip(msg) else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(path, "Documents"); XCTAssertEqual(page, 1); XCTAssertEqual(pageSize, 200)
        XCTAssertEqual(sortBy, "modified"); XCTAssertEqual(sortDir, "desc")
        XCTAssertTrue(foldersFirst); XCTAssertEqual(query, "report")
    }

    func testListResponseRoundTrips() throws {
        let entry = FileEntry(name: "a.txt", relativePath: "Documents/a.txt", isDirectory: false,
                              size: 12, modified: 99, mimeType: "text/plain")
        let msg = Message.macFilesListResponse(path: "Documents", entries: [entry],
                                               totalCount: 1, page: 0, needsPermission: false)
        guard case let .macFilesListResponse(path, entries, total, page, needsPerm) = try roundTrip(msg) else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(path, "Documents"); XCTAssertEqual(entries, [entry])
        XCTAssertEqual(total, 1); XCTAssertEqual(page, 0); XCTAssertFalse(needsPerm)
    }

    func testDownloadReadyRoundTrips() throws {
        let msg = Message.macFileDownloadReady(transferId: "T1", filename: "a.txt",
                                               mimeType: "text/plain", fileSize: 12)
        guard case let .macFileDownloadReady(tid, name, mime, size) = try roundTrip(msg) else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(tid, "T1"); XCTAssertEqual(name, "a.txt")
        XCTAssertEqual(mime, "text/plain"); XCTAssertEqual(size, 12)
    }
}
