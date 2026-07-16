import XCTest
import Protocol
@testable import AirbridgeApp

@MainActor
private final class DummyHandler: MessageHandler {
    func handleMessage(_ message: Message) {}
}

/// Findings P2-1 / P2-2: in-flight listing state (isLoading* flags and
/// device-scoped data) must be reset whenever the device the requests target
/// changes — a manual switch, the active device dropping, or a full
/// disconnect. Before this, an SMS load interrupted by a reconnect left
/// `isLoadingConversations == true` forever, and the guard in
/// `loadConversations()` rejected every reload — an empty list for good.
@MainActor
final class ActiveDeviceResetTests: XCTestCase {

    private var connection: ConnectionService!
    private var gallery: GalleryService!
    private var sms: SmsService!
    private var files: FilesBrowserService!

    override func setUp() async throws {
        connection = ConnectionService()
        gallery = GalleryService()
        sms = SmsService()
        files = FilesBrowserService()
        gallery.configure(connectionService: connection)
        sms.configure(connectionService: connection)
        files.configure(connectionService: connection, fileTransferService: FileTransferService())
        let dummy = DummyHandler()
        connection.registerHandlers(
            clipboard: dummy, fileTransfer: dummy,
            gallery: gallery, sms: sms, files: files,
            notifications: dummy
        )
    }

    // MARK: - Finding 2: reconnect must not leave a stale isLoading guard

    /// The exact reported scenario: SMS view mid-load, the phone disconnects
    /// and reconnects (new connectionId). The stale guard must not reject the
    /// reload triggered by the view's onChange(activeDeviceId).
    func testSmsLoadingFlagsResetOnDisconnectAndReloadWorksAfterReconnect() {
        connection.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Phone A")
        sms.loadConversations()
        sms.loadMessages(threadId: "t1")
        XCTAssertTrue(sms.isLoadingConversations)
        XCTAssertTrue(sms.isLoadingMessages)

        connection.disconnect()
        XCTAssertFalse(sms.isLoadingConversations, "disconnect must clear the in-flight conversations load")
        XCTAssertFalse(sms.isLoadingMessages, "disconnect must clear the in-flight messages load")

        // Phone reconnects under a fresh connectionId.
        connection.upsertDevice(connectionId: "1.1.1.1:6", publicKey: "kA", name: "Phone A")
        sms.loadConversations()
        XCTAssertTrue(sms.isLoadingConversations, "reload after reconnect must pass the guard")
    }

    func testGalleryAndFilesLoadingFlagsResetOnDisconnect() {
        connection.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Phone A")
        gallery.loadPhotos()
        files.open(path: "")
        XCTAssertTrue(gallery.isLoading)
        XCTAssertTrue(files.isLoading)

        connection.disconnect()
        XCTAssertFalse(gallery.isLoading)
        XCTAssertFalse(files.isLoading)
    }

    /// Switching the active device mid-load must clear the previous device's
    /// in-flight state so the new device's load isn't blocked.
    func testLoadingFlagsResetOnManualActiveDeviceSwitch() {
        connection.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Phone A")
        connection.upsertDevice(connectionId: "1.1.1.2:5", publicKey: "kB", name: "Phone B")
        sms.loadConversations()
        gallery.loadPhotos()
        files.open(path: "")
        XCTAssertTrue(sms.isLoadingConversations)

        connection.setActiveDevice("1.1.1.2:5")
        XCTAssertFalse(sms.isLoadingConversations)
        XCTAssertFalse(gallery.isLoading)
        XCTAssertFalse(files.isLoading)
    }

    // MARK: - Finding P2-2: silent re-target on active-device drop

    /// When the active phone drops while another stays connected,
    /// `activeDeviceId` silently re-targets. The previous device's data and
    /// loading state must be cleared at that moment — no zombie spinner and
    /// never data from two phones at once.
    func testActiveDeviceDropClearsPreviousDeviceData() {
        connection.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Phone A")
        connection.upsertDevice(connectionId: "1.1.1.2:5", publicKey: "kB", name: "Phone B")
        XCTAssertEqual(connection.activeDevice?.connectionId, "1.1.1.1:5")

        // Device A's data is on screen; a messages load is in flight.
        gallery.handleMessage(.galleryResponse(
            photos: [GalleryPhotoMeta(id: "p1", filename: "a.jpg", dateTaken: 0, width: 1, height: 1, size: 1, mimeType: "image/jpeg")],
            totalCount: 1, page: 0))
        sms.handleMessage(.smsConversationsResponse(
            conversations: [SmsConversationMeta(threadId: "t1", address: "1", displayName: "A", snippet: "", date: 0, messageCount: 1, unreadCount: 0)],
            totalCount: 1, page: 0))
        sms.loadMessages(threadId: "t1")
        files.handleMessage(.filesListResponse(
            path: "",
            entries: [FileEntry(name: "a.txt", relativePath: "a.txt", isDirectory: false, size: 1, modified: 0, mimeType: "text/plain")],
            totalCount: 1, page: 0, needsPermission: false))

        // Active phone A drops; B remains — silent re-target.
        connection.handleClientDisconnected("1.1.1.1:5")

        XCTAssertEqual(connection.activeDevice?.connectionId, "1.1.1.2:5")
        XCTAssertTrue(gallery.photos.isEmpty, "phone A's photos must not be shown as phone B's")
        XCTAssertTrue(sms.conversations.isEmpty)
        XCTAssertTrue(sms.currentMessages.isEmpty)
        XCTAssertNil(sms.currentThreadId)
        XCTAssertTrue(files.entries.isEmpty)
        XCTAssertFalse(sms.isLoadingMessages, "no zombie spinner for the dropped device's request")
    }

    /// A non-active device dropping must not disturb the active device's data.
    func testNonActiveDeviceDropKeepsActiveDeviceData() {
        connection.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Phone A")
        connection.upsertDevice(connectionId: "1.1.1.2:5", publicKey: "kB", name: "Phone B")
        gallery.handleMessage(.galleryResponse(
            photos: [GalleryPhotoMeta(id: "p1", filename: "a.jpg", dateTaken: 0, width: 1, height: 1, size: 1, mimeType: "image/jpeg")],
            totalCount: 1, page: 0))

        connection.handleClientDisconnected("1.1.1.2:5")

        XCTAssertEqual(connection.activeDevice?.connectionId, "1.1.1.1:5")
        XCTAssertEqual(gallery.photos.count, 1, "the active device's data must survive another phone's drop")
    }

    /// A stale timeout-failure flag from the previous device must not survive
    /// a device change either.
    func testFailureFlagsResetOnDeviceChange() async {
        connection.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Phone A")
        sms.requestTimeout = 0.1
        gallery.requestTimeout = 0.1
        files.requestTimeout = 0.1
        sms.loadConversations()
        gallery.loadPhotos()
        files.open(path: "")
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(sms.conversationsLoadFailed)
        XCTAssertTrue(gallery.loadFailed)
        XCTAssertTrue(files.loadFailed)

        connection.disconnect()
        XCTAssertFalse(sms.conversationsLoadFailed)
        XCTAssertFalse(gallery.loadFailed)
        XCTAssertFalse(files.loadFailed)
    }
}
