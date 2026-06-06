import XCTest
@testable import Protocol

final class ChargeTimeTests: XCTestCase {
    func testMinutesOnlyPL() {
        XCTAssertEqual(formatChargeTime(45 * 60_000, isPL: true), "45 min")
    }
    func testWholeHoursPL() {
        XCTAssertEqual(formatChargeTime(2 * 3_600_000, isPL: true), "2 godz.")
    }
    func testHoursAndMinutesPL() {
        XCTAssertEqual(formatChargeTime(80 * 60_000, isPL: true), "1 godz. 20 min")
    }
    func testHoursAndMinutesEN() {
        XCTAssertEqual(formatChargeTime(80 * 60_000, isPL: false), "1 hr 20 min")
    }
    func testMinutesOnlyEN() {
        XCTAssertEqual(formatChargeTime(45 * 60_000, isPL: false), "45 min")
    }
    func testWholeHoursEN() {
        XCTAssertEqual(formatChargeTime(2 * 3_600_000, isPL: false), "2 hr")
    }
}
