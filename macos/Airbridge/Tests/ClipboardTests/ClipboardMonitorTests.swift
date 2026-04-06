import XCTest
@testable import Clipboard

final class ClipboardMonitorTests: XCTestCase {

    // MARK: - testDetectsTextChange

    func testDetectsTextChange() {
        let mock = MockPasteboard()
        let monitor = ClipboardMonitor(pasteboard: mock, pollInterval: 0.05)

        var received: ClipboardContent?
        let expectation = expectation(description: "onChange fires")

        monitor.onChange = { content in
            received = content
            expectation.fulfill()
        }

        monitor.start()
        mock.simulateChange(string: "Hello, Airbridge!")

        wait(for: [expectation], timeout: 1.0)
        monitor.stop()

        XCTAssertEqual(received?.textData, "Hello, Airbridge!")
        XCTAssertEqual(received?.contentType, .plainText)
    }

    // MARK: - testIgnoresDuplicateContent

    func testIgnoresDuplicateContent() {
        let mock = MockPasteboard()
        let monitor = ClipboardMonitor(pasteboard: mock, pollInterval: 0.05)

        var callCount = 0
        monitor.onChange = { _ in callCount += 1 }

        monitor.start()
        mock.simulateChange(string: "same text")

        // Pump run loop to allow timer to fire
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        // Simulate second change with the same content (new changeCount but identical text)
        mock.simulateChange(string: "same text")

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        monitor.stop()

        XCTAssertEqual(callCount, 1, "onChange should fire only once for duplicate content")
    }

    // MARK: - testSetClipboardDoesNotTriggerCallback

    func testSetClipboardDoesNotTriggerCallback() {
        let mock = MockPasteboard()
        let monitor = ClipboardMonitor(pasteboard: mock, pollInterval: 0.05)

        var callCount = 0
        monitor.onChange = { _ in callCount += 1 }

        monitor.start()

        let content = ClipboardContent(contentType: .plainText, textData: "remote text", imageData: nil)
        monitor.setClipboard(content: content)

        // Pump run loop long enough for several poll cycles
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
        monitor.stop()

        XCTAssertEqual(callCount, 0, "onChange must NOT fire when content is set from remote")
    }
}
