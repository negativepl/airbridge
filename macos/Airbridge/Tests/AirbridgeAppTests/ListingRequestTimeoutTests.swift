import XCTest
import Protocol
@testable import AirbridgeApp

/// Finding P1-4: listing requests to the phone (gallery, SMS, files) had no
/// timeout — a frozen phone app or a response lost on a live WebSocket left
/// the view spinning forever, because `isConnected == true` blocks the
/// not-connected state. Every listing request must be time-boxed: on timeout
/// the loading flag clears and a retryable failure state is exposed.
@MainActor
final class ListingRequestTimeoutTests: XCTestCase {

    private var connection: ConnectionService!

    override func setUp() async throws {
        connection = ConnectionService()
        connection.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Phone A")
    }

    /// Polls `condition` on the main actor until it holds or `timeout` passes.
    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    // MARK: - Gallery

    func testGalleryListingTimesOutIntoRetryableFailure() async {
        let service = GalleryService()
        service.configure(connectionService: connection)
        service.requestTimeout = 0.2

        service.loadPhotos()
        XCTAssertTrue(service.isLoading)

        let failed = await waitUntil { service.loadFailed }
        XCTAssertTrue(failed, "a listing with no response must time out into a failure state")
        XCTAssertFalse(service.isLoading)

        // Retry must not be blocked by the stale isLoading guard.
        service.loadPhotos()
        XCTAssertTrue(service.isLoading)
        XCTAssertFalse(service.loadFailed)
    }

    func testGalleryResponseCancelsTimeout() async {
        let service = GalleryService()
        service.configure(connectionService: connection)
        service.requestTimeout = 0.2

        service.loadPhotos()
        service.handleMessage(.galleryResponse(photos: [], totalCount: 0, page: 0))
        XCTAssertFalse(service.isLoading)

        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(service.loadFailed, "an answered request must not be flagged as failed later")
    }

    // MARK: - SMS

    func testSmsConversationsTimeoutIntoRetryableFailure() async {
        let service = SmsService()
        service.configure(connectionService: connection)
        service.requestTimeout = 0.2

        service.loadConversations()
        XCTAssertTrue(service.isLoadingConversations)

        let failed = await waitUntil { service.conversationsLoadFailed }
        XCTAssertTrue(failed)
        XCTAssertFalse(service.isLoadingConversations)

        service.loadConversations()
        XCTAssertTrue(service.isLoadingConversations, "retry must pass the isLoading guard after a timeout")
        XCTAssertFalse(service.conversationsLoadFailed)
    }

    func testSmsMessagesTimeoutIntoRetryableFailure() async {
        let service = SmsService()
        service.configure(connectionService: connection)
        service.requestTimeout = 0.2

        service.loadMessages(threadId: "t1")
        XCTAssertTrue(service.isLoadingMessages)

        let failed = await waitUntil { service.messagesLoadFailed }
        XCTAssertTrue(failed)
        XCTAssertFalse(service.isLoadingMessages)

        service.loadMessages(threadId: "t1")
        XCTAssertTrue(service.isLoadingMessages)
        XCTAssertFalse(service.messagesLoadFailed)
    }

    func testSmsResponsesCancelTimeouts() async {
        let service = SmsService()
        service.configure(connectionService: connection)
        service.requestTimeout = 0.2

        service.loadConversations()
        service.handleMessage(.smsConversationsResponse(conversations: [], totalCount: 0, page: 0))
        service.loadMessages(threadId: "t1")
        service.handleMessage(.smsMessagesResponse(threadId: "t1", messages: [], totalCount: 0, page: 0))

        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(service.conversationsLoadFailed)
        XCTAssertFalse(service.messagesLoadFailed)
    }

    // MARK: - Files

    func testFilesListingTimesOutIntoRetryableFailure() async {
        let service = FilesBrowserService()
        service.configure(connectionService: connection, fileTransferService: FileTransferService())
        service.requestTimeout = 0.2

        service.open(path: "")
        XCTAssertTrue(service.isLoading)

        let failed = await waitUntil { service.loadFailed }
        XCTAssertTrue(failed)
        XCTAssertFalse(service.isLoading)

        service.open(path: "")
        XCTAssertTrue(service.isLoading)
        XCTAssertFalse(service.loadFailed)
    }

    func testFilesResponseCancelsTimeout() async {
        let service = FilesBrowserService()
        service.configure(connectionService: connection, fileTransferService: FileTransferService())
        service.requestTimeout = 0.2

        service.open(path: "")
        service.handleMessage(.filesListResponse(path: "", entries: [], totalCount: 0, page: 0, needsPermission: false))
        XCTAssertFalse(service.isLoading)

        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(service.loadFailed)
    }

    /// The top-down row reveal waits for each folder's stats — a stats request
    /// that never gets an answer must not block the reveal (and the spinner
    /// shown while `displayedEntries` is empty) forever.
    func testFolderStatsTimeoutUnblocksRowReveal() async {
        let service = FilesBrowserService()
        service.configure(connectionService: connection, fileTransferService: FileTransferService())
        service.requestTimeout = 0.2

        let dir = FileEntry(name: "DCIM", relativePath: "DCIM", isDirectory: true, size: 0, modified: 0, mimeType: "")
        service.handleMessage(.filesListResponse(path: "", entries: [dir], totalCount: 1, page: 0, needsPermission: false))
        XCTAssertTrue(service.displayedEntries.isEmpty, "a folder without stats is not revealed yet")

        let revealed = await waitUntil { service.displayedEntries.count == 1 }
        XCTAssertTrue(revealed, "a folder whose stats never arrive must be revealed after the timeout")
    }
}
