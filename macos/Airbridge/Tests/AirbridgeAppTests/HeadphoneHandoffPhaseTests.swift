import XCTest
@testable import AirbridgeApp

/// Failure-state lifecycle of the headphone handoff: a failed handoff must be
/// visible for a beat (Home error text, menu bar row) and then return to idle
/// on its own instead of sticking around as stale state.
@MainActor
final class HeadphoneHandoffPhaseTests: XCTestCase {

    func testMarkHandoffFailedAutoReturnsToIdle() async throws {
        let svc = ConnectionService()
        svc.handoffFailedResetNanos = 50_000_000 // 50 ms for the test

        svc.markHandoffFailed()
        XCTAssertEqual(svc.headphoneHandoffPhase, .failed)

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(svc.headphoneHandoffPhase, .idle)
    }

    func testFailedResetDoesNotClobberANewHandoff() async throws {
        let svc = ConnectionService()
        svc.handoffFailedResetNanos = 50_000_000

        svc.markHandoffFailed()
        // A retry starts before the reset fires — the stale reset must not
        // knock the new in-progress handoff back to idle.
        svc.headphoneHandoffPhase = .inProgress

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(svc.headphoneHandoffPhase, .inProgress)
    }

    func testTakeoverWithoutConfigurationFailsVisibly() {
        let svc = ConnectionService()
        // No BluetoothAudioService wired at all — a click on a stale button
        // must surface a failure, not silently no-op.
        svc.takeoverHeadphones()
        XCTAssertEqual(svc.headphoneHandoffPhase, .failed)
    }

    func testDisconnectOfLastDeviceClearsHandoffState() {
        let svc = ConnectionService()
        svc.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Fold")
        svc.headphoneHandoffPhase = .inProgress
        svc.headphonePromptVisible = true

        svc.handleClientDisconnected("1.1.1.1:5")

        XCTAssertEqual(svc.headphoneHandoffPhase, .idle)
        XCTAssertFalse(svc.headphonePromptVisible)
        XCTAssertNil(svc.phoneHeadphoneState)
    }
}
