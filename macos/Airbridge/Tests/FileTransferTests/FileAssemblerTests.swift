import XCTest
@testable import FileTransfer
import CryptoKit

final class FileAssemblerTests: XCTestCase {

    // MARK: - Helpers

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - testAssemblesChunksInOrder

    /// Adding chunk 0 then chunk 1 → isComplete, assembled data matches original.
    func testAssemblesChunksInOrder() throws {
        let original = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        let chunk0 = Data([0x01, 0x02, 0x03])
        let chunk1 = Data([0x04, 0x05, 0x06])
        let checksum = sha256Hex(original)

        let assembler = FileAssembler(
            transferId: "transfer-1",
            filename: "file.bin",
            totalSize: 6,
            totalChunks: 2,
            checksumSHA256: checksum
        )

        XCTAssertFalse(assembler.isComplete)

        assembler.addChunk(index: 0, data: chunk0)
        XCTAssertFalse(assembler.isComplete)

        assembler.addChunk(index: 1, data: chunk1)
        XCTAssertTrue(assembler.isComplete)

        let assembled = try assembler.assemble()
        XCTAssertEqual(assembled, original)
    }

    // MARK: - testAssemblesChunksOutOfOrder

    /// Adding chunk 1 before chunk 0 → still assembles correctly in order.
    func testAssemblesChunksOutOfOrder() throws {
        let original = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let chunk0 = Data([0xAA, 0xBB])
        let chunk1 = Data([0xCC, 0xDD])
        let checksum = sha256Hex(original)

        let assembler = FileAssembler(
            transferId: "transfer-2",
            filename: "out-of-order.bin",
            totalSize: 4,
            totalChunks: 2,
            checksumSHA256: checksum
        )

        assembler.addChunk(index: 1, data: chunk1)
        XCTAssertFalse(assembler.isComplete)

        assembler.addChunk(index: 0, data: chunk0)
        XCTAssertTrue(assembler.isComplete)

        let assembled = try assembler.assemble()
        XCTAssertEqual(assembled, original)
    }

    // MARK: - testLastConfirmedChunk

    /// lastConfirmedChunkIndex tracks the last contiguous chunk from 0.
    /// Sequence: initial → add 0 → add 2 (gap) → add 1 (fills gap) → 2
    func testLastConfirmedChunk() {
        let assembler = FileAssembler(
            transferId: "transfer-3",
            filename: "progress.bin",
            totalSize: 9,
            totalChunks: 3,
            checksumSHA256: ""
        )

        // Initially no confirmed chunks
        XCTAssertEqual(assembler.lastConfirmedChunkIndex, -1)

        // After adding chunk 0 → last confirmed = 0
        assembler.addChunk(index: 0, data: Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(assembler.lastConfirmedChunkIndex, 0)

        // After adding chunk 2 (gap at 1) → last confirmed stays 0
        assembler.addChunk(index: 2, data: Data([0x07, 0x08, 0x09]))
        XCTAssertEqual(assembler.lastConfirmedChunkIndex, 0)

        // After adding chunk 1 (fills gap) → last confirmed = 2
        assembler.addChunk(index: 1, data: Data([0x04, 0x05, 0x06]))
        XCTAssertEqual(assembler.lastConfirmedChunkIndex, 2)
    }
}
