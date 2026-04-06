import XCTest
@testable import FileTransfer
import Protocol

final class FileChunkerTests: XCTestCase {

    // MARK: - testChunksSmallFile

    /// 100 bytes split into 64-byte chunks → 2 chunks with indices 0 and 1.
    func testChunksSmallFile() {
        let data = Data(repeating: 0xAB, count: 100)
        let chunker = FileChunker(chunkSize: 64)
        let chunked = chunker.prepare(
            filename: "test.bin",
            mimeType: "application/octet-stream",
            data: data,
            sourceId: "src-1"
        )

        XCTAssertEqual(chunked.totalChunks, 2)
        XCTAssertEqual(chunked.chunks.count, 2)
        XCTAssertEqual(chunked.chunks[0].chunkIndex, 0)
        XCTAssertEqual(chunked.chunks[1].chunkIndex, 1)

        // First chunk should be 64 bytes, second 36 bytes
        let firstData = Data(base64Encoded: chunked.chunks[0].base64Data)!
        let secondData = Data(base64Encoded: chunked.chunks[1].base64Data)!
        XCTAssertEqual(firstData.count, 64)
        XCTAssertEqual(secondData.count, 36)
    }

    // MARK: - testChunksExactMultiple

    /// 128 bytes / 64 bytes per chunk → exactly 2 chunks, no remainder.
    func testChunksExactMultiple() {
        let data = Data(repeating: 0xFF, count: 128)
        let chunker = FileChunker(chunkSize: 64)
        let chunked = chunker.prepare(
            filename: "exact.bin",
            mimeType: "application/octet-stream",
            data: data,
            sourceId: "src-2"
        )

        XCTAssertEqual(chunked.totalChunks, 2)
        XCTAssertEqual(chunked.chunks.count, 2)
        XCTAssertEqual(chunked.chunks[0].chunkIndex, 0)
        XCTAssertEqual(chunked.chunks[1].chunkIndex, 1)

        let firstData = Data(base64Encoded: chunked.chunks[0].base64Data)!
        let secondData = Data(base64Encoded: chunked.chunks[1].base64Data)!
        XCTAssertEqual(firstData.count, 64)
        XCTAssertEqual(secondData.count, 64)
    }

    // MARK: - testStartMessage

    /// The startMessage should be a .fileTransferStart with correct fields.
    func testStartMessage() {
        let data = Data(repeating: 0x01, count: 100)
        let chunker = FileChunker(chunkSize: 64)
        let chunked = chunker.prepare(
            filename: "hello.png",
            mimeType: "image/png",
            data: data,
            sourceId: "device-42"
        )

        let msg = chunked.startMessage
        guard case .fileTransferStart(
            let sourceId,
            let transferId,
            let filename,
            let mimeType,
            let totalSize,
            let totalChunks
        ) = msg else {
            XCTFail("Expected .fileTransferStart, got \(msg)")
            return
        }

        XCTAssertEqual(sourceId, "device-42")
        XCTAssertEqual(transferId, chunked.transferId)
        XCTAssertEqual(filename, "hello.png")
        XCTAssertEqual(mimeType, "image/png")
        XCTAssertEqual(totalSize, 100)
        XCTAssertEqual(totalChunks, 2)
    }
}
