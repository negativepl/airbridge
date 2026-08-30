import XCTest
@testable import AirbridgeApp
@testable import Protocol

/// Rejecting an incoming file on the Mac should say so — the island shows
/// "Transfer rejected" for a beat before it goes away. Reported symptom: no
/// such confirmation, the island just freezes briefly and closes.
/// `withObservationTracking`'s onChange is not main-actor isolated, so the
/// flag it sets needs a reference box rather than a captured `var`.
private final class NotifiedBox: @unchecked Sendable {
    var value = false
}

@MainActor
final class RejectFeedbackTests: XCTestCase {

    private func serviceWithOffer(filename: String = "raport.pdf") -> FileTransferService {
        let service = FileTransferService()
        service.handleMessage(
            .fileTransferOffer(transferId: "t1", filename: filename,
                               mimeType: "application/pdf", fileSize: 1234, destinationDir: nil)
        )
        return service
    }

    func testOfferArrives() {
        let service = serviceWithOffer()
        XCTAssertTrue(service.hasIncomingOffer)
        XCTAssertEqual(service.fileTransferFileName, "raport.pdf")
    }

    func testRejectingRaisesTheRejectedState() {
        let service = serviceWithOffer()
        service.rejectIncomingOffer()
        XCTAssertTrue(service.isRejected, "the island has nothing to show without this")
    }

    /// The offer must be gone at the same time, otherwise the popup keeps
    /// computing .incoming (which outranks .rejected) and the user sees the
    /// original "Incoming file" pane frozen until the popup hides.
    func testRejectingClearsTheOfferSoRejectedCanShow() {
        let service = serviceWithOffer()
        service.rejectIncomingOffer()
        XCTAssertFalse(service.hasIncomingOffer)
    }

    /// The real defect: the popup reads `hasIncomingOffer` FIRST, so while an
    /// offer is on screen that is the only dependency SwiftUI recorded. If
    /// rejecting mutates nothing observable, the view is never invalidated and
    /// the "Incoming file" pane stays frozen until the hide timer fires —
    /// which is exactly what a user sees as "it freezes, then just closes".
    func testRejectingInvalidatesAViewObservingTheOfferFlag() {
        let service = serviceWithOffer()
        let notified = NotifiedBox()
        withObservationTracking {
            _ = service.hasIncomingOffer
        } onChange: {
            notified.value = true
        }
        service.rejectIncomingOffer()
        XCTAssertTrue(notified.value, "rejecting must invalidate a view that observes hasIncomingOffer")
    }

    /// Same trap for accepting: it clears the offer through the same field.
    func testAcceptingInvalidatesAViewObservingTheOfferFlag() {
        let service = serviceWithOffer()
        let notified = NotifiedBox()
        withObservationTracking {
            _ = service.hasIncomingOffer
        } onChange: {
            notified.value = true
        }
        service.acceptIncomingOffer()
        XCTAssertTrue(notified.value, "accepting must invalidate a view that observes hasIncomingOffer")
    }

    // MARK: - The gap between accepting and the first byte
    // Accepting clears the offer, but the upload has not started, so nothing
    // is in progress yet. Without a state covering that gap the popup falls
    // through to .idle and flashes "Drop file here" at someone who just
    // accepted a file.

    func testAcceptingHoldsTheIslandUntilTheTransferStarts() {
        let service = serviceWithOffer()
        service.acceptIncomingOffer()
        XCTAssertTrue(service.isAwaitingAcceptedTransfer,
                      "the island would fall through to the idle drop zone")
    }

    func testTheFirstProgressTickEndsTheWait() {
        let service = serviceWithOffer()
        service.acceptIncomingOffer()
        service.noteIncomingTransferStarted()
        XCTAssertFalse(service.isAwaitingAcceptedTransfer)
    }

    func testRejectingDoesNotHoldTheIsland() {
        let service = serviceWithOffer()
        service.rejectIncomingOffer()
        XCTAssertFalse(service.isAwaitingAcceptedTransfer)
    }

    /// A dropped connection must release the hold too, otherwise the popup
    /// waits forever for an upload that can never arrive.
    func testConnectionLossEndsTheWait() {
        let service = serviceWithOffer()
        service.acceptIncomingOffer()
        service.connectionLost()
        XCTAssertFalse(service.isAwaitingAcceptedTransfer)
    }

    /// The filename has to survive the reject — the rejected pane prints it.
    func testFilenameSurvivesForTheRejectedPane() {
        let service = serviceWithOffer()
        service.rejectIncomingOffer()
        XCTAssertEqual(service.fileTransferFileName, "raport.pdf")
    }
}
