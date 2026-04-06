import XCTest
import Foundation
import CryptoKit
@testable import Networking
import Protocol

// MARK: - EndToEndTests

final class EndToEndTests: XCTestCase {

    // MARK: - Test 1: Clipboard Sync Round Trip

    /// Verifies that:
    /// 1. The client can send a `clipboardUpdate` to the server and the server records it.
    /// 2. The server can broadcast a `clipboardUpdate` back to the client.
    func testClipboardSyncRoundTrip() async throws {
        // 1. Start server on an ephemeral port
        let server = WebSocketServer(port: 0)
        try await server.start()

        let port = await server.actualPort
        XCTAssertNotNil(port, "Server should have an assigned port after start")
        guard let port else { return }

        // 2. Connect a URLSession WebSocket client
        let url = URL(string: "ws://127.0.0.1:\(port)")!
        let client = URLSession.shared.webSocketTask(with: url)
        client.resume()

        // Allow connection handshake to complete
        try await Task.sleep(nanoseconds: 300_000_000)

        // 3. Client sends clipboard_update to the server
        let androidMessage = Message.clipboardUpdate(
            sourceId: "android-sim",
            contentType: .plainText,
            data: "Hello from Android"
        )
        let encoded = try JSONEncoder().encode(androidMessage)
        let jsonString = String(data: encoded, encoding: .utf8)!
        try await client.send(.string(jsonString))

        // 4. Wait for server to process the message
        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify server.lastReceivedMessage matches the sent message
        let serverReceived = await server.lastReceivedMessage
        XCTAssertNotNil(serverReceived, "Server should have received a message")

        guard case .clipboardUpdate(let srcId, let contentType, let data) = serverReceived else {
            XCTFail("Expected clipboardUpdate, got \(String(describing: serverReceived))")
            client.cancel(with: .normalClosure, reason: Data())
            await server.stop()
            return
        }
        XCTAssertEqual(srcId, "android-sim")
        XCTAssertEqual(contentType, .plainText)
        XCTAssertEqual(data, "Hello from Android")

        // 5. Server broadcasts clipboard_update back to the client
        let macMessage = Message.clipboardUpdate(
            sourceId: "mac-1",
            contentType: .plainText,
            data: "Hello from Mac"
        )
        try await server.broadcast(macMessage)

        // 6. Client receives and decodes the broadcast
        let receivedFrame = try await client.receive()

        switch receivedFrame {
        case .string(let frameString):
            let decoded = try JSONDecoder().decode(Message.self, from: Data(frameString.utf8))
            guard case .clipboardUpdate(_, _, let receivedData) = decoded else {
                XCTFail("Expected clipboardUpdate from server, got \(decoded)")
                break
            }
            XCTAssertEqual(receivedData, "Hello from Mac")

        case .data(let bytes):
            XCTFail("Expected string WebSocket frame, received \(bytes.count) raw bytes")

        @unknown default:
            XCTFail("Received unknown WebSocket frame type")
        }

        // 7. Cleanup
        client.cancel(with: .normalClosure, reason: Data())
        await server.stop()
    }

    // MARK: - Test 2: File Transfer Simulation

    /// Verifies that a multi-step file transfer sequence
    /// (fileTransferStart → fileChunk → fileTransferComplete) can be sent
    /// from a client to the server and that the server records the final
    /// `fileTransferComplete` with the correct transferId.
    func testFileTransferSimulation() async throws {
        // 1. Start server and connect client
        let server = WebSocketServer(port: 0)
        try await server.start()

        let port = await server.actualPort
        XCTAssertNotNil(port, "Server should have an assigned port after start")
        guard let port else { return }

        let url = URL(string: "ws://127.0.0.1:\(port)")!
        let client = URLSession.shared.webSocketTask(with: url)
        client.resume()

        try await Task.sleep(nanoseconds: 300_000_000)

        // 2. Prepare file content
        let fileContent = "Hello"
        let fileData = Data(fileContent.utf8)
        let base64Chunk = fileData.base64EncodedString()

        // Compute SHA-256 checksum of the file bytes
        let digest = SHA256.hash(data: fileData)
        let checksumHex = digest.map { String(format: "%02x", $0) }.joined()

        let transferId = "transfer-e2e-001"

        // Send fileTransferStart
        let startMessage = Message.fileTransferStart(
            sourceId: "android-sim",
            transferId: transferId,
            filename: "hello.txt",
            mimeType: "text/plain",
            totalSize: fileData.count,
            totalChunks: 1
        )
        try await client.send(.string(jsonString(for: startMessage)))

        try await Task.sleep(nanoseconds: 100_000_000)

        // Send fileChunk
        let chunkMessage = Message.fileChunk(
            transferId: transferId,
            chunkIndex: 0,
            data: base64Chunk
        )
        try await client.send(.string(jsonString(for: chunkMessage)))

        try await Task.sleep(nanoseconds: 100_000_000)

        // Send fileTransferComplete with correct SHA-256
        let completeMessage = Message.fileTransferComplete(
            transferId: transferId,
            checksumSHA256: checksumHex
        )
        try await client.send(.string(jsonString(for: completeMessage)))

        // 3. Wait for server to process the final message
        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify server's lastReceivedMessage is fileTransferComplete
        let serverReceived = await server.lastReceivedMessage
        XCTAssertNotNil(serverReceived, "Server should have received the fileTransferComplete message")

        guard case .fileTransferComplete(let receivedId, let receivedChecksum) = serverReceived else {
            XCTFail("Expected fileTransferComplete, got \(String(describing: serverReceived))")
            client.cancel(with: .normalClosure, reason: Data())
            await server.stop()
            return
        }
        XCTAssertEqual(receivedId, transferId, "transferId should match")
        XCTAssertEqual(receivedChecksum, checksumHex, "SHA-256 checksum should match")

        // Cleanup
        client.cancel(with: .normalClosure, reason: Data())
        await server.stop()
    }

    // MARK: - Private Helpers

    private func jsonString(for message: Message) throws -> String {
        let data = try JSONEncoder().encode(message)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(message, .init(codingPath: [], debugDescription: "UTF-8 encoding failed"))
        }
        return string
    }
}
