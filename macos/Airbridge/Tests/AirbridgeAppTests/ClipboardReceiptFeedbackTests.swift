import XCTest
@testable import AirbridgeApp
@testable import Protocol

/// Incoming clipboard content used to be applied completely silently: the Mac
/// swapped the pasteboard and showed nothing, so a link shared from the phone
/// looked like nothing had happened. These tests pin the receipt feedback —
/// a preview of what arrived, plus a URL when the content is a plain link.
@MainActor
final class ClipboardReceiptFeedbackTests: XCTestCase {

    // MARK: - URL detection

    func testPlainHttpsLinkIsDetectedAsURL() {
        XCTAssertEqual(
            ClipboardService.detectURL(in: "https://example.com/article?id=1"),
            URL(string: "https://example.com/article?id=1")
        )
    }

    func testSurroundingWhitespaceDoesNotBreakDetection() {
        XCTAssertEqual(
            ClipboardService.detectURL(in: "  http://example.com\n"),
            URL(string: "http://example.com")
        )
    }

    func testProseContainingALinkIsNotTreatedAsALink() {
        // Only clipboard content that IS a link gets the Open button —
        // a sentence that merely mentions one stays plain text.
        XCTAssertNil(ClipboardService.detectURL(in: "Zobacz https://example.com jutro"))
    }

    func testPlainTextIsNotAURL() {
        XCTAssertNil(ClipboardService.detectURL(in: "notatka do siebie"))
    }

    func testNonWebSchemesAreRejected() {
        // Opening arbitrary schemes from a remote device would hand the phone
        // a way to launch local handlers — only http(s) is offered.
        XCTAssertNil(ClipboardService.detectURL(in: "file:///etc/passwd"))
        XCTAssertNil(ClipboardService.detectURL(in: "javascript:alert(1)"))
    }

    // MARK: - Link presentation
    // A raw URL with a query string is unreadable in a popup — the domain is
    // the part that answers "where does this go?", so it leads, and the rest
    // is demoted to a detail line.

    func testHostDropsWWWPrefix() {
        let url = URL(string: "https://www.google.com/search?q=green+inferno")!
        XCTAssertEqual(ClipboardService.linkHost(url), "google.com")
    }

    func testHostKeepsMeaningfulSubdomains() {
        let url = URL(string: "https://docs.swift.org/guide")!
        XCTAssertEqual(ClipboardService.linkHost(url), "docs.swift.org")
    }

    func testDetailShowsReadablePathAndQuery() {
        let url = URL(string: "https://www.google.com/search?q=green+inferno")!
        // "+" and percent-escapes are display noise — a human reads a query,
        // not its encoding.
        XCTAssertEqual(ClipboardService.linkDetail(url), "/search?q=green inferno")
    }

    func testDetailDecodesPercentEscapes() {
        let url = URL(string: "https://example.com/a%20b?x=%C5%BC")!
        XCTAssertEqual(ClipboardService.linkDetail(url), "/a b?x=ż")
    }

    func testBareDomainHasNoDetail() {
        XCTAssertNil(ClipboardService.linkDetail(URL(string: "https://example.com")!))
        XCTAssertNil(ClipboardService.linkDetail(URL(string: "https://example.com/")!))
    }

    // MARK: - Receipt state

    func testIncomingLinkPublishesPreviewAndURL() {
        let service = ClipboardService()
        service.handleMessage(
            .clipboardUpdate(sourceId: "phone", contentType: .plainText, data: "https://example.com/x")
        )
        XCTAssertEqual(service.incomingPreview, "https://example.com/x")
        XCTAssertEqual(service.incomingURL, URL(string: "https://example.com/x"))
    }

    func testIncomingPlainTextPublishesPreviewWithoutURL() {
        let service = ClipboardService()
        service.handleMessage(
            .clipboardUpdate(sourceId: "phone", contentType: .plainText, data: "notatka")
        )
        XCTAssertEqual(service.incomingPreview, "notatka")
        XCTAssertNil(service.incomingURL)
    }

    func testLongTextPreviewIsTruncated() {
        let service = ClipboardService()
        let long = String(repeating: "a", count: 500)
        service.handleMessage(
            .clipboardUpdate(sourceId: "phone", contentType: .plainText, data: long)
        )
        XCTAssertNotNil(service.incomingPreview)
        XCTAssertLessThanOrEqual(service.incomingPreview!.count, 200)
    }

    func testIncomingImagePublishesAnImagePreview() {
        let service = ClipboardService()
        // 1x1 transparent PNG.
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        service.handleMessage(
            .clipboardUpdate(sourceId: "phone", contentType: .png, data: png)
        )
        XCTAssertNotNil(service.incomingPreview)
        XCTAssertNil(service.incomingURL)
    }

    // MARK: - Opt-out
    // Every phone→Mac clipboard send is deliberate (share sheet, "Send to Mac",
    // or the in-app button), so there is no passive traffic to filter out —
    // the only honest way to silence the receipt is a preference.

    func testReceiptCanBeTurnedOff() {
        UserDefaults.standard.set(false, forKey: "clipboardReceipt")
        defer { UserDefaults.standard.removeObject(forKey: "clipboardReceipt") }

        let service = ClipboardService()
        service.handleMessage(
            .clipboardUpdate(sourceId: "phone", contentType: .plainText, data: "https://example.com")
        )
        XCTAssertNil(service.incomingPreview)
        XCTAssertNil(service.incomingURL)
    }

    func testReceiptIsOnByDefault() {
        UserDefaults.standard.removeObject(forKey: "clipboardReceipt")

        let service = ClipboardService()
        service.handleMessage(
            .clipboardUpdate(sourceId: "phone", contentType: .plainText, data: "cokolwiek")
        )
        XCTAssertNotNil(service.incomingPreview)
    }

    /// Turning the receipt off must not stop the clipboard itself syncing.
    func testSilencedReceiptStillAppliesClipboard() {
        UserDefaults.standard.set(false, forKey: "clipboardReceipt")
        defer { UserDefaults.standard.removeObject(forKey: "clipboardReceipt") }

        let service = ClipboardService()
        service.handleMessage(
            .clipboardUpdate(sourceId: "phone", contentType: .plainText, data: "cicha synchronizacja")
        )
        XCTAssertEqual(service.lastSyncedText, "cicha synchronizacja")
    }

    func testDismissClearsReceiptState() {
        let service = ClipboardService()
        service.handleMessage(
            .clipboardUpdate(sourceId: "phone", contentType: .plainText, data: "https://example.com")
        )
        service.dismissIncomingPreview()
        XCTAssertNil(service.incomingPreview)
        XCTAssertNil(service.incomingURL)
    }
}
