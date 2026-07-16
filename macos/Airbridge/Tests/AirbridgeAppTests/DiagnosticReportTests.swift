import XCTest
@testable import AirbridgeApp

final class DiagnosticReportTests: XCTestCase {

    private func makeInput(
        devices: [DiagnosticReport.DeviceSummary] = [],
        logTail: [String] = []
    ) -> DiagnosticReport.Input {
        DiagnosticReport.Input(
            appVersion: "2.9.0-beta",
            buildNumber: "20900",
            macOSVersion: "Version 26.1 (Build 26B101)",
            phase: "connected",
            statusMessage: "Connected to Fold7",
            devices: devices,
            logTail: logTail
        )
    }

    // MARK: - compose

    func testComposeContainsVersionsAndPhase() {
        let report = DiagnosticReport.compose(makeInput(), now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(report.contains("2.9.0-beta"))
        XCTAssertTrue(report.contains("20900"))
        XCTAssertTrue(report.contains("Version 26.1 (Build 26B101)"))
        XCTAssertTrue(report.contains("connected"))
        XCTAssertTrue(report.contains("Connected to Fold7"))
    }

    func testComposeListsDevices() {
        let devices = [
            DiagnosticReport.DeviceSummary(name: "Fold7", ip: "192.168.1.20", appVersion: "2.9.0-beta", isActive: true),
            DiagnosticReport.DeviceSummary(name: "Find X9", ip: nil, appVersion: nil, isActive: false)
        ]
        let report = DiagnosticReport.compose(makeInput(devices: devices))
        XCTAssertTrue(report.contains("Fold7"))
        XCTAssertTrue(report.contains("192.168.1.20"))
        XCTAssertTrue(report.contains("Find X9"))
        XCTAssertTrue(report.contains("active"))
        XCTAssertTrue(report.contains("Connected devices: 2"))
    }

    func testComposeWithoutDevicesSaysNone() {
        let report = DiagnosticReport.compose(makeInput())
        XCTAssertTrue(report.contains("Connected devices: 0"))
    }

    func testComposeIncludesLogTail() {
        let report = DiagnosticReport.compose(makeInput(logTail: ["line A", "line B"]))
        XCTAssertTrue(report.contains("line A\nline B"))
    }

    func testComposeWithEmptyLogSaysUnavailable() {
        let report = DiagnosticReport.compose(makeInput(logTail: []))
        XCTAssertTrue(report.contains("(no log entries)"))
    }

    // MARK: - tail

    func testTailReturnsAllLinesWhenShort() {
        XCTAssertEqual(DiagnosticReport.tail("a\nb\nc", maxLines: 500), ["a", "b", "c"])
    }

    func testTailTruncatesToLastLines() {
        let text = (1...600).map { "line \($0)" }.joined(separator: "\n")
        let tail = DiagnosticReport.tail(text, maxLines: 500)
        XCTAssertEqual(tail.count, 500)
        XCTAssertEqual(tail.first, "line 101")
        XCTAssertEqual(tail.last, "line 600")
    }

    func testTailIgnoresTrailingNewlineAndEmptyText() {
        XCTAssertEqual(DiagnosticReport.tail("a\nb\n", maxLines: 500), ["a", "b"])
        XCTAssertEqual(DiagnosticReport.tail("", maxLines: 500), [])
    }

    // MARK: - suggestedFileName

    func testSuggestedFileNameFormat() {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 16
        components.hour = 9; components.minute = 5
        let date = Calendar(identifier: .gregorian).date(from: components)!
        XCTAssertEqual(DiagnosticReport.suggestedFileName(now: date), "airbridge-diagnostics-20260716-0905.txt")
    }
}
