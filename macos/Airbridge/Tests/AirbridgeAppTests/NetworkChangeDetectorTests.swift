import XCTest
@testable import AirbridgeApp

/// Czysta logika decyzji "czy to realna zmiana sieci" — wcześniej zaszyta
/// w NetworkChangeMonitor.handle() i nietestowalna (wymagała NWPath).
final class NetworkChangeDetectorTests: XCTestCase {

    func testFirstSatisfiedPathIsBaselineAndDoesNotFire() {
        var d = NetworkChangeDetector()
        XCTAssertFalse(d.register(satisfied: true, key: "en0|192.168.1.1|192.168.1.20"))
    }

    func testSameKeyDoesNotFire() {
        var d = NetworkChangeDetector()
        _ = d.register(satisfied: true, key: "en0|192.168.1.1|192.168.1.20")
        XCTAssertFalse(d.register(satisfied: true, key: "en0|192.168.1.1|192.168.1.20"))
    }

    /// Scenariusz z diagnozy czerwcowej: dom i praca mają ten sam gateway
    /// (192.168.1.1), zmienia się tylko przydzielone IP Maca — musi odpalić.
    func testKeyChangeWithSameGatewayFires() {
        var d = NetworkChangeDetector()
        _ = d.register(satisfied: true, key: "en0|192.168.1.1|192.168.1.20")
        XCTAssertTrue(d.register(satisfied: true, key: "en0|192.168.1.1|192.168.1.77"))
    }

    /// Zerwanie i powrót do TEJ SAMEJ sieci też ma re-advertise
    /// (satisfied -> unsatisfied -> satisfied).
    func testUnsatisfiedThenSatisfiedSameKeyFires() {
        var d = NetworkChangeDetector()
        _ = d.register(satisfied: true, key: "en0|gw|ip")
        XCTAssertFalse(d.register(satisfied: false, key: "ignored"))
        XCTAssertTrue(d.register(satisfied: true, key: "en0|gw|ip"))
    }

    func testUnsatisfiedBeforeAnyBaselineDoesNotFire() {
        var d = NetworkChangeDetector()
        XCTAssertFalse(d.register(satisfied: false, key: "ignored"))
        // pierwszy satisfied po starcie w trybie offline to nadal baseline
        XCTAssertFalse(d.register(satisfied: true, key: "en0|gw|ip"))
    }

    func testAfterChangeNewKeyBecomesBaseline() {
        var d = NetworkChangeDetector()
        _ = d.register(satisfied: true, key: "A")
        _ = d.register(satisfied: true, key: "B")   // zmiana
        XCTAssertFalse(d.register(satisfied: true, key: "B")) // B to nowy baseline
    }
}
