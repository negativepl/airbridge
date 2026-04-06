import Foundation
import CryptoKit

// MARK: - FileAssemblerError

/// Errors that can be thrown when assembling a chunked file transfer.
public enum FileAssemblerError: Error, Equatable {
    /// Not all chunks have been received yet.
    case incomplete
    /// A chunk at the given index is missing.
    case missingChunk(Int)
    /// The assembled data's SHA-256 does not match the expected checksum.
    case checksumMismatch(expected: String, got: String)
}

// MARK: - FileAssembler

/// Collects incoming chunks and reassembles them into the original file data.
public final class FileAssembler {

    // MARK: Public Properties

    public let transferId: String
    public let filename: String
    public let totalSize: Int
    public let totalChunks: Int
    public let checksumSHA256: String

    /// `true` when all `totalChunks` chunks have been received.
    public var isComplete: Bool {
        receivedChunks.count == totalChunks
    }

    /// Index of the last contiguous chunk received starting from 0.
    /// Returns `-1` if chunk 0 has not been received yet.
    public var lastConfirmedChunkIndex: Int {
        var last = -1
        while receivedChunks[last + 1] != nil {
            last += 1
            if last == totalChunks - 1 { break }
        }
        return last
    }

    /// Fraction of chunks received (0.0 … 1.0).
    public var progress: Double {
        guard totalChunks > 0 else { return 1.0 }
        return Double(receivedChunks.count) / Double(totalChunks)
    }

    // MARK: Private Storage

    /// Sparse dictionary of received chunks keyed by their index.
    private var receivedChunks: [Int: Data] = [:]

    // MARK: Init

    public init(
        transferId: String,
        filename: String,
        totalSize: Int,
        totalChunks: Int,
        checksumSHA256: String
    ) {
        self.transferId = transferId
        self.filename = filename
        self.totalSize = totalSize
        self.totalChunks = totalChunks
        self.checksumSHA256 = checksumSHA256
    }

    // MARK: Public Methods

    /// Stores a received chunk.
    ///
    /// - Parameters:
    ///   - index: Zero-based position of this chunk in the file.
    ///   - data:  Raw bytes for this chunk.
    public func addChunk(index: Int, data: Data) {
        receivedChunks[index] = data
    }

    /// Assembles all received chunks into the original file data.
    ///
    /// - Throws: `FileAssemblerError.incomplete` if not all chunks are present.
    ///           `FileAssemblerError.missingChunk` if a specific chunk is absent.
    ///           `FileAssemblerError.checksumMismatch` if the SHA-256 does not match
    ///           (only checked when `checksumSHA256` is non-empty).
    /// - Returns: The reassembled file `Data` in chunk order.
    public func assemble() throws -> Data {
        guard isComplete else {
            // Find the first missing chunk to surface a helpful error.
            for i in 0..<totalChunks {
                if receivedChunks[i] == nil {
                    throw FileAssemblerError.missingChunk(i)
                }
            }
            throw FileAssemblerError.incomplete
        }

        var assembled = Data()
        assembled.reserveCapacity(totalSize)

        for i in 0..<totalChunks {
            guard let chunk = receivedChunks[i] else {
                throw FileAssemblerError.missingChunk(i)
            }
            assembled.append(chunk)
        }

        // Verify checksum when provided
        if !checksumSHA256.isEmpty {
            let digest = SHA256.hash(data: assembled)
            let got = digest.map { String(format: "%02x", $0) }.joined()
            if got != checksumSHA256 {
                throw FileAssemblerError.checksumMismatch(expected: checksumSHA256, got: got)
            }
        }

        return assembled
    }
}
