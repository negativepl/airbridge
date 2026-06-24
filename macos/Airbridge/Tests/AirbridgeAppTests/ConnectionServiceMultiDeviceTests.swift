import XCTest
@testable import AirbridgeApp

@MainActor
final class ConnectionServiceMultiDeviceTests: XCTestCase {

    func testShimsDeriveFromConnectedDevices() {
        let svc = ConnectionService()
        XCTAssertFalse(svc.isConnected)
        XCTAssertEqual(svc.connectedDeviceName, "")
        XCTAssertNil(svc.connectedClientIP)

        svc.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Oppo", clientIP: "1.1.1.1")
        svc.upsertDevice(connectionId: "1.1.1.2:5", publicKey: "kB", name: "Samsung", clientIP: "1.1.1.2")

        XCTAssertTrue(svc.isConnected)
        XCTAssertEqual(svc.connectedDevices.count, 2)
        // primary = most recently added
        XCTAssertEqual(svc.connectedDeviceName, "Samsung")
        XCTAssertEqual(svc.connectedClientIP, "1.1.1.2")
    }

    func testUpsertUpdatesInPlaceNotDuplicate() {
        let svc = ConnectionService()
        svc.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Oppo")
        // Same connectionId re-auths with a resolved name — must update, not append.
        svc.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Oppo Find X8")

        XCTAssertEqual(svc.connectedDevices.count, 1)
        XCTAssertEqual(svc.connectedDevices.first?.name, "Oppo Find X8")
    }

    func testActiveDeviceDefaultsToFirstAndHoldsSelection() {
        let svc = ConnectionService()
        XCTAssertNil(svc.activeDevice)

        svc.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Oppo")
        // First connection becomes active automatically.
        XCTAssertEqual(svc.activeDevice?.connectionId, "1.1.1.1:5")

        svc.upsertDevice(connectionId: "1.1.1.2:5", publicKey: "kB", name: "Samsung")
        // A second connection does NOT steal the active selection.
        XCTAssertEqual(svc.activeDevice?.connectionId, "1.1.1.1:5")
    }

    func testSetActiveDeviceSelectsAndIgnoresUnknown() {
        let svc = ConnectionService()
        svc.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Oppo")
        svc.upsertDevice(connectionId: "1.1.1.2:5", publicKey: "kB", name: "Samsung")

        svc.setActiveDevice("1.1.1.2:5")
        XCTAssertEqual(svc.activeDevice?.name, "Samsung")

        svc.setActiveDevice("9.9.9.9:9") // not connected — ignored
        XCTAssertEqual(svc.activeDevice?.name, "Samsung")
    }

    func testPairedSignalIncrementsOnBump() {
        let svc = ConnectionService()
        let before = svc.pairedSignal
        svc.bumpPairedSignal()
        XCTAssertEqual(svc.pairedSignal, before + 1)
    }
}
