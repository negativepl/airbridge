import Foundation
import CryptoKit
import Protocol

// MARK: - ChunkData

/// A single chunk of a file transfer, carrying its index and base64-encoded bytes.
public struct ChunkData: Equatable, Sendable {
    public let chunkIndex: Int
    public let base64Data: String

    public init(chunkIndex: Int, base64Data: String) {
        self.chunkIndex = chunkIndex
        self.base64Data = base64Data
    }
}

// MARK: - ChunkedFile

/// The result of splitting a file into chunks, ready for transmission.
public struct ChunkedFile: Sendable {
    public let transferId: String
    public let filename: String
    public let mimeType: String
    public let totalSize: Int
    public let totalChunks: Int
    public let chunks: [ChunkData]
    public let checksumSHA256: String
    public let startMessage: Message

    public init(
        transferId: String,
        filename: String,
        mimeType: String,
        totalSize: Int,
        totalChunks: Int,
        chunks: [ChunkData],
        checksumSHA256: String,
        startMessage: Message
    ) {
        self.transferId = transferId
        self.filename = filename
        self.mimeType = mimeType
        self.totalSize = totalSize
        self.totalChunks = totalChunks
        self.chunks = chunks
        self.checksumSHA256 = checksumSHA256
        self.startMessage = startMessage
    }
}

// MARK: - FileChunker

/// Splits raw `Data` into fixed-size chunks for transmission.
public struct FileChunker: Sendable {

    /// The maximum number of bytes per chunk (default 64 KiB).
    public let chunkSize: Int

    public init(chunkSize: Int = 65_536) {
        self.chunkSize = chunkSize
    }

    /// Splits `data` into chunks and returns a `ChunkedFile` ready for transmission.
    ///
    /// - Parameters:
    ///   - filename:  The original filename (e.g. `"photo.png"`).
    ///   - mimeType:  The MIME type of the file (e.g. `"image/png"`).
    ///   - data:      The raw file bytes to split.
    ///   - sourceId:  The identifier of the sending device.
    /// - Returns: A `ChunkedFile` with all chunk data and metadata.
    public func prepare(
        filename: String,
        mimeType: String,
        data: Data,
        sourceId: String
    ) -> ChunkedFile {
        let transferId = UUID().uuidString
        let totalSize = data.count
        let totalChunks = totalSize == 0 ? 1 : (totalSize + chunkSize - 1) / chunkSize

        // Build chunks
        var chunks: [ChunkData] = []
        chunks.reserveCapacity(totalChunks)

        for index in 0..<totalChunks {
            let start = index * chunkSize
            let end = Swift.min(start + chunkSize, totalSize)
            let slice = data[start..<end]
            let base64 = slice.base64EncodedString()
            chunks.append(ChunkData(chunkIndex: index, base64Data: base64))
        }

        // Compute SHA-256 checksum
        let digest = SHA256.hash(data: data)
        let checksumSHA256 = digest.map { String(format: "%02x", $0) }.joined()

        // Build the start message
        let startMessage = Message.fileTransferStart(
            sourceId: sourceId,
            transferId: transferId,
            filename: filename,
            mimeType: mimeType,
            totalSize: totalSize,
            totalChunks: totalChunks
        )

        return ChunkedFile(
            transferId: transferId,
            filename: filename,
            mimeType: mimeType,
            totalSize: totalSize,
            totalChunks: totalChunks,
            chunks: chunks,
            checksumSHA256: checksumSHA256,
            startMessage: startMessage
        )
    }
}
