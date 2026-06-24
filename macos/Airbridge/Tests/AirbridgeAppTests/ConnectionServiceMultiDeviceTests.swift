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

    func testPairedSignalIncrementsOnBump() {
        let svc = ConnectionService()
        let before = svc.pairedSignal
        svc.bumpPairedSignal()
        XCTAssertEqual(svc.pairedSignal, before + 1)
    }
}
