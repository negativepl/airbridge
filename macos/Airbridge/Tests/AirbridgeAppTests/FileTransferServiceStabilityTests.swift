import XCTest
import Protocol
@testable import AirbridgeApp

/// Stability tests for `FileTransferService`: waits that must not hang forever
/// when the peer disappears (outgoing-offer accept wait, upload completion,
/// preview downloads) and receive-state resets on aborted uploads.
@MainActor
final class FileTransferServiceStabilityTests: XCTestCase {

    private var tempFile: URL!
    private var connection: ConnectionService!
    private var service: FileTransferService!

    override func setUp() async throws {
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ft-stability-\(UUID().uuidString).txt")
        try Data("payload".utf8).write(to: tempFile)
        connection = ConnectionService()
        service = FileTransferService()
        service.configure(connectionService: connection)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempFile)
    }

    /// Polls `condition` on the main actor until it holds or `timeout` passes.
    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    // MARK: - Finding 1: outgoing offer wait must not hang forever

    /// All devices dropping while "waiting for acceptance" must fail the wait
    /// and surface the failure state instead of hanging the island forever.
    func testConnectionLostFailsOutgoingOfferWait() async {
        service.sendFile(url: tempFile)
        let waiting = await waitUntil { self.service.isWaitingForAccept }
        XCTAssertTrue(waiting, "sendFile must enter the waiting-for-accept state")

        service.connectionLost()

        let failed = await waitUntil { self.service.isFailed }
        XCTAssertTrue(failed, "connectionLost must fail the pending outgoing offer")
        XCTAssertFalse(service.isWaitingForAccept)
    }

    /// The specific phone the offer was sent to disconnecting must fail the wait.
    func testSenderDisconnectFailsOutgoingOfferWait() async {
        connection.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Phone A")
        service.sendFile(url: tempFile)
        let waiting = await waitUntil { self.service.isWaitingForAccept }
        XCTAssertTrue(waiting)

        service.deviceDisconnected(connectionId: "1.1.1.1:5")

        let failed = await waitUntil { self.service.isFailed }
        XCTAssertTrue(failed, "disconnect of the offer's target device must fail the wait")
        XCTAssertFalse(service.isWaitingForAccept)
    }

    /// A DIFFERENT phone disconnecting must not touch the pending offer.
    func testOtherDeviceDisconnectKeepsOutgoingOfferWaiting() async {
        connection.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Phone A")
        connection.upsertDevice(connectionId: "1.1.1.2:5", publicKey: "kB", name: "Phone B")
        // Active device is A (first connected) — the offer targets it.
        service.sendFile(url: tempFile)
        let waiting = await waitUntil { self.service.isWaitingForAccept }
        XCTAssertTrue(waiting)

        service.deviceDisconnected(connectionId: "1.1.1.2:5")

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(service.isWaitingForAccept, "offer to device A must survive device B's disconnect")
        XCTAssertFalse(service.isFailed)
    }

    /// No accept/reject within the timeout must fail the wait (mirrors the
    /// phone's own 60 s offer timeout).
    func testOfferAcceptTimeoutFailsWait() async {
        service.offerAcceptTimeout = 0.2
        service.sendFile(url: tempFile)
        let waiting = await waitUntil { self.service.isWaitingForAccept }
        XCTAssertTrue(waiting)

        let failed = await waitUntil { self.service.isFailed }
        XCTAssertTrue(failed, "offer wait must time out instead of hanging forever")
        XCTAssertFalse(service.isWaitingForAccept)
    }
}
