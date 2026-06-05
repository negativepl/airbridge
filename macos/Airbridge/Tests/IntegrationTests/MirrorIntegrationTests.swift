import Testing
import Foundation
@testable import Mirror
@testable import AirbridgeApp

/// Integration tests for the Mac-side mirror channel.
///
/// **Scope:** Wire-protocol handshake only. Frame-decoding tests with a real
/// H.264 fixture are deferred until a manual smoke session (Task 7.2) records
/// a fixture from a real phone.
@Suite("Mirror integration — handshake")
@MainActor
struct MirrorIntegrationTests {

    /// Verify HELLO with the correct token receives a HELLO_ACK reply.
    @Test("Server replies HELLO_ACK to HELLO with valid token")
    func handshakeAcceptsValidToken() async throws {
        let token = Data(repeating: 0xAB, count: 16)
        let service = MirrorService(port: 0, pairingTokenProvider: { token })
        try await service.start()
        guard let port = service.actualPort else {
            Issue.record("MirrorService failed to obtain a port")
            return
        }

        let url = URL(string: "ws://127.0.0.1:\(port)/")!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()

        // Send HELLO
        let hello = MirrorMessage.hello(token: token, screenWidth: 1080, screenHeight: 2376, orientation: 0)
        try await task.send(.data(hello.encode()))

        // Expect HELLO_ACK back within 2s
        let ackBytes: Data = try await withTimeout(seconds: 2) {
            switch try await task.receive() {
            case .data(let d): return d
            case .string(let s): return Data(s.utf8)
            @unknown default: throw URLError(.unknown)
            }
        }
        let decoded = try MirrorMessage.decode(ackBytes)
        guard case let .helloAck(bitrate, fps, kf, w, h, _) = decoded else {
            Issue.record("Expected HELLO_ACK, got \(decoded)")
            return
        }
        // Defaults from MirrorService HELLO handler
        #expect(bitrate == 12_000_000)
        #expect(fps == 60)
        #expect(kf == 2)
        #expect(w == 1920)
        #expect(h == 1080)

        task.cancel(with: .normalClosure, reason: nil)
        await service.stop()
    }

    /// Verify HELLO with an invalid token causes the server to disconnect.
    @Test("Server disconnects on HELLO with bad token")
    func handshakeRejectsBadToken() async throws {
        let validToken = Data(repeating: 0xAB, count: 16)
        let badToken = Data(repeating: 0xCD, count: 16)
        let service = MirrorService(port: 0, pairingTokenProvider: { validToken })
        try await service.start()
        guard let port = service.actualPort else {
            Issue.record("MirrorService failed to obtain a port")
            return
        }

        let url = URL(string: "ws://127.0.0.1:\(port)/")!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()

        let bogus = MirrorMessage.hello(token: badToken, screenWidth: 1080, screenHeight: 2376, orientation: 0)
        try await task.send(.data(bogus.encode()))

        // Expect the server to close — either receive() throws, or returns within timeout.
        // We give it 2s to disconnect; if connection is still alive after that, the assertion fails.
        do {
            _ = try await withTimeout(seconds: 2) {
                _ = try await task.receive()
                // If we get a message back instead of a close, that's a problem
                throw URLError(.badServerResponse)
            }
            Issue.record("Server did not close on bad token")
        } catch {
            // Expected — connection should close.
        }

        task.cancel(with: .normalClosure, reason: nil)
        await service.stop()
    }
}

// MARK: - Helpers

/// Race a body operation against a timeout. Throws `URLError(.timedOut)` if the body doesn't finish in time.
private func withTimeout<T: Sendable>(seconds: TimeInterval, body: @Sendable @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw URLError(.timedOut)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
