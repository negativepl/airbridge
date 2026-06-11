import XCTest
import Foundation
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

}
