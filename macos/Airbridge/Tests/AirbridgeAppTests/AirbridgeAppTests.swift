import XCTest
@testable import AirbridgeApp

final class AirbridgeAppTests: XCTestCase {

    private let bundleId = "com.airbridge.macos"

    /// Druga instancja: ten sam bundle ID, inny PID → zwróć PID istniejącej.
    func testDetectsOtherRunningInstance() {
        let running: [(bundleId: String?, pid: Int32)] = [
            ("com.apple.finder", 100),
            (bundleId, 200),   // już działająca instancja
        ]
        let other = InstanceGuard.otherInstancePID(bundleId: bundleId, selfPID: 999, running: running)
        XCTAssertEqual(other, 200)
    }

    /// Jedyna instancja (tylko my) → brak innej, nie kończymy procesu.
    func testNoOtherInstanceWhenOnlySelf() {
        let running: [(bundleId: String?, pid: Int32)] = [
            ("com.apple.finder", 100),
            (bundleId, 999),   // to my
        ]
        let other = InstanceGuard.otherInstancePID(bundleId: bundleId, selfPID: 999, running: running)
        XCTAssertNil(other)
    }

    /// Inne apki o innym bundle ID nie liczą się jako nasza instancja.
    func testIgnoresDifferentBundleIds() {
        let running: [(bundleId: String?, pid: Int32)] = [
            ("com.apple.finder", 100),
            (nil, 101),
            ("com.airbridge.android", 102),
        ]
        let other = InstanceGuard.otherInstancePID(bundleId: bundleId, selfPID: 999, running: running)
        XCTAssertNil(other)
    }
}
