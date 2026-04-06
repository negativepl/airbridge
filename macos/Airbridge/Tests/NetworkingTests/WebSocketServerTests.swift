import XCTest
import Foundation
@testable import Networking
import Protocol

final class WebSocketServerTests: XCTestCase {

    // MARK: - Test 1: Server starts and accepts connection

    func testServerStartsAndAcceptsConnection() async throws {
        let server = WebSocketServer(port: 0)
        try await server.start()

        let port = await server.actualPort
        XCTAssertNotNil(port, "Server should have assigned a port")
        guard let port else { return }

        let url = URL(string: "ws://127.0.0.1:\(port)")!
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        // Give server time to register the connection
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        // Send a ping message from the client
        let ping = Message.ping(timestamp: 12345)
        let encoder = JSONEncoder()
        let data = try encoder.encode(ping)
        let jsonString = String(data: data, encoding: .utf8)!
        try await task.send(URLSessionWebSocketTask.Message.string(jsonString))

        // Give server time to receive the message
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        let received = await server.lastReceivedMessage
        XCTAssertNotNil(received, "Server should have received the ping message")

        if case .ping(let ts) = received {
            XCTAssertEqual(ts, 12345)
        } else {
            XCTFail("Expected ping message, got \(String(describing: received))")
        }

        task.cancel(with: .normalClosure, reason: Data())
        await server.stop()
    }

    // MARK: - Test 2: Server sends broadcast message to connected client

    func testServerSendsMessage() async throws {
        let server = WebSocketServer(port: 0)
        try await server.start()

        let port = await server.actualPort
        XCTAssertNotNil(port, "Server should have assigned a port")
        guard let port else { return }

        let url = URL(string: "ws://127.0.0.1:\(port)")!
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        // Wait for connection to be established
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        // Broadcast a pong message from the server
        let pong = Message.pong(timestamp: 99999)
        try await server.broadcast(pong)

        // Receive message on client side
        let received = try await task.receive()

        switch received {
        case .string(let jsonString):
            let decoder = JSONDecoder()
            let message = try decoder.decode(Message.self, from: Data(jsonString.utf8))
            if case .pong(let ts) = message {
                XCTAssertEqual(ts, 99999)
            } else {
                XCTFail("Expected pong, got \(message)")
            }
        case .data(let data):
            XCTFail("Expected string frame, got \(data.count) bytes")
        @unknown default:
            XCTFail("Unknown message type")
        }

        task.cancel(with: .normalClosure, reason: Data())
        await server.stop()
    }
}
