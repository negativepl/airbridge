import XCTest
@testable import AirbridgeApp

/// "Remaining: calculating…" used to stay on screen for the whole transfer.
/// Two causes, both here: the estimate truncated to whole seconds (so a
/// nearly-finished transfer reported 0, which the view reads as "unknown"),
/// and it was only computed after half a second had elapsed — longer than a
/// small file takes end to end.
@MainActor
final class TransferEtaTests: XCTestCase {

    func testHalfASecondLeftRoundsUpToOne() {
        // Truncation reported 0 here, which the popup renders as "calculating…"
        // right when the transfer is about to finish.
        XCTAssertEqual(FileTransferService.etaSeconds(remainingBytes: 500_000, speed: 1_000_000), 1)
    }

    func testASliverLeftIsStillOneSecond() {
        XCTAssertEqual(FileTransferService.etaSeconds(remainingBytes: 1, speed: 1_000_000), 1)
    }

    func testNothingLeftIsZero() {
        XCTAssertEqual(FileTransferService.etaSeconds(remainingBytes: 0, speed: 1_000_000), 0)
    }

    func testWholeSecondsAreNotInflated() {
        XCTAssertEqual(FileTransferService.etaSeconds(remainingBytes: 3_000_000, speed: 1_000_000), 3)
    }

    func testUnknownSpeedYieldsNoEstimate() {
        XCTAssertEqual(FileTransferService.etaSeconds(remainingBytes: 1_000, speed: 0), 0)
    }

    func testNegativeRemainingIsClampedNotNegative() {
        // bytesReceived can briefly exceed the advertised total.
        XCTAssertEqual(FileTransferService.etaSeconds(remainingBytes: -10, speed: 1_000), 0)
    }

    // MARK: - When an estimate may be produced

    func testEstimateIsAvailableEarlyEnoughForASmallFile() {
        // A file that transfers in ~0.3s must still get an estimate; the old
        // 0.5s gate meant it never did and the label never left "calculating".
        XCTAssertTrue(FileTransferService.canEstimate(elapsed: 0.3))
    }

    func testNoEstimateFromAnInstantaneousSample() {
        // Too soon to divide by: speed would be wild.
        XCTAssertFalse(FileTransferService.canEstimate(elapsed: 0.0))
    }
}
