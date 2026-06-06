import XCTest
@testable import Protocol

final class FilesMessageTests: XCTestCase {
    private func roundTrip(_ message: Message) throws -> Message {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(Message.self, from: data)
    }

    func testFilesListRequestRoundTrip() throws {
        let msg = Message.filesListRequest(path: "Download", page: 0, pageSize: 200)
        XCTAssertEqual(try roundTrip(msg), msg)
    }

    func testFilesListResponseRoundTrip() throws {
        let entry = FileEntry(name: "a.pdf", relativePath: "Download/a.pdf", isDirectory: false,
                              size: 1234, modified: 1_700_000_000_000, mimeType: "application/pdf")
        let msg = Message.filesListResponse(path: "Download", entries: [entry],
                                            totalCount: 1, page: 0, needsPermission: false)
        XCTAssertEqual(try roundTrip(msg), msg)
    }

    func testFileThumbnailRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.fileThumbnailRequest(path: "DCIM/x.jpg")),
                       .fileThumbnailRequest(path: "DCIM/x.jpg"))
        XCTAssertEqual(try roundTrip(.fileThumbnailResponse(path: "DCIM/x.jpg", data: "QQ==")),
                       .fileThumbnailResponse(path: "DCIM/x.jpg", data: "QQ=="))
    }

    func testFileDownloadRequestRoundTrip() throws {
        let msg = Message.fileDownloadRequest(transferId: "T1", path: "Download/a.pdf")
        XCTAssertEqual(try roundTrip(msg), msg)
    }

    func testFileTransferOfferWithDestinationRoundTrip() throws {
        let msg = Message.fileTransferOffer(transferId: "T1", filename: "a.pdf",
                                            mimeType: "application/pdf", fileSize: 10, destinationDir: "Download")
        XCTAssertEqual(try roundTrip(msg), msg)
    }

    func testFilesListRequestSortSearchRoundTrip() throws {
        let msg = Message.filesListRequest(path: "Download", page: 1, pageSize: 200,
                                           sortBy: "size", sortDir: "desc",
                                           foldersFirst: false, query: "raport")
        XCTAssertEqual(try roundTrip(msg), msg)
    }

    func testFilesListRequestDecodesLegacyWithDefaults() throws {
        let legacy = #"{"type":"files_list_request","path":"","page":0,"page_size":200}"#
        let decoded = try JSONDecoder().decode(Message.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded, .filesListRequest(path: "", page: 0, pageSize: 200,
                                                  sortBy: "name", sortDir: "asc",
                                                  foldersFirst: true, query: ""))
    }
}
