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

    // MARK: - Finding 2: upload completion wait must not hang forever

    /// After the phone accepts, no upload progress within the stall timeout
    /// must fail the transfer instead of leaving the island on "Sending"
    /// with no way out.
    func testUploadStallTimeoutFailsTransfer() async {
        service.uploadStallTimeout = 0.3
        service.sendFile(url: tempFile)
        let waiting = await waitUntil { self.service.isWaitingForAccept }
        XCTAssertTrue(waiting)

        // Phone accepts, then vanishes — its GET never arrives.
        service.handleMessage(.fileTransferAccept(transferId: "any"))

        let failed = await waitUntil { self.service.isFailed }
        XCTAssertTrue(failed, "a stalled upload must fail instead of hanging in transferring state")
        XCTAssertFalse(service.isWaitingForAccept)
    }

    // MARK: - Finding 3: aborted/stalled preview downloads must complete with nil

    /// A preview download torn down mid-stream must call the preview's
    /// completion with nil (surfacing the error in FilesBrowserView) instead
    /// of leaving the spinner forever.
    func testAbortedPreviewCompletesWithNil() async {
        let installed = await waitUntil { self.connection.httpServer.onUploadAborted != nil }
        XCTAssertTrue(installed, "configure() must install the abort callback")

        var completed = false
        var result: URL? = URL(fileURLWithPath: "/sentinel")
        service.requestPreview(
            filename: "photo.jpg",
            saveTo: FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).jpg"),
            onProgress: { _ in },
            completion: { url in
                completed = true
                result = url
            }
        )

        connection.httpServer.onUploadAborted?("photo.jpg", "1.2.3.4")

        let done = await waitUntil { completed }
        XCTAssertTrue(done, "aborted preview must invoke its completion")
        XCTAssertNil(result)
    }

    /// A preview download that never makes progress must time out with nil.
    func testPreviewStallTimeoutCompletesWithNil() async {
        service.previewStallTimeout = 0.2

        var completed = false
        var result: URL? = URL(fileURLWithPath: "/sentinel")
        service.requestPreview(
            filename: "clip.mp4",
            saveTo: FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).mp4"),
            onProgress: { _ in },
            completion: { url in
                completed = true
                result = url
            }
        )

        let done = await waitUntil { completed }
        XCTAssertTrue(done, "stalled preview must time out and invoke its completion")
        XCTAssertNil(result)
    }

    // MARK: - Finding 5: abort before the popup is claimed must reset receive state

    /// An accepted incoming offer flips `isReceivingFile` on before any byte
    /// arrives. If the upload then aborts before the first progress callback
    /// claims the popup (receivingOwnerKey still nil), the receive state must
    /// be reset anyway — not left stuck behind the owner-key guard.
    func testAbortBeforeOwnerClaimResetsReceiveState() async {
        let installed = await waitUntil { self.connection.httpServer.onUploadAborted != nil }
        XCTAssertTrue(installed)

        service.handleMessage(
            .fileTransferOffer(transferId: "t1", filename: "a.bin",
                               mimeType: "application/octet-stream",
                               fileSize: 10, destinationDir: nil),
            from: "1.1.1.1:5"
        )
        XCTAssertTrue(service.isReceivingFile)
        service.acceptIncomingOffer()
        XCTAssertTrue(service.isReceivingFile)

        // Upload dies before any progress callback claimed the popup.
        connection.httpServer.onUploadAborted?("a.bin", "1.1.1.1")

        let reset = await waitUntil { !self.service.isReceivingFile }
        XCTAssertTrue(reset, "abort before the first byte must reset the receive state")
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
