import XCTest
import Protocol
@testable import AirbridgeApp

@MainActor
private final class DummyHandler: MessageHandler {
    func handleMessage(_ message: Message) {}
}

/// A conversation picked while the previous one is still loading must load.
/// The in-flight guard rejected the second request, the first thread's reply
/// then arrived for a conversation no longer shown, and the panel stayed empty.
@MainActor
final class SmsThreadSwitchTests: XCTestCase {

    private var connection: ConnectionService!
    private var sms: SmsService!

    override func setUp() async throws {
        connection = ConnectionService()
        sms = SmsService()
        sms.configure(connectionService: connection)
        let dummy = DummyHandler()
        connection.registerHandlers(
            clipboard: dummy, fileTransfer: dummy,
            gallery: dummy, sms: sms, files: dummy,
            notifications: dummy
        )
        connection.upsertDevice(connectionId: "1.1.1.1:5", publicKey: "kA", name: "Phone A")
    }

    private func message(_ id: String) -> SmsMessageMeta {
        SmsMessageMeta(id: id, address: "+48000", body: id, date: 1, type: 1, read: true)
    }

    func testSwitchingThreadMidLoadLoadsTheNewThread() {
        sms.loadMessages(threadId: "A")
        sms.loadMessages(threadId: "B")
        XCTAssertEqual(sms.currentThreadId, "B", "the newly picked thread must be requested")

        // The late reply for A must not land in B's conversation.
        sms.handleMessage(.smsMessagesResponse(threadId: "A", messages: [message("a1")], totalCount: 1, page: 0))
        XCTAssertTrue(sms.currentMessages.isEmpty)
        XCTAssertTrue(sms.isLoadingMessages)

        sms.handleMessage(.smsMessagesResponse(threadId: "B", messages: [message("b1")], totalCount: 1, page: 0))
        XCTAssertEqual(sms.currentMessages.map(\.id), ["b1"])
        XCTAssertFalse(sms.isLoadingMessages)
    }

    func testOlderPageAppendsWithoutDuplicates() {
        sms.loadMessages(threadId: "A")
        sms.handleMessage(.smsMessagesResponse(threadId: "A", messages: [message("m3"), message("m2")], totalCount: 4, page: 0))
        XCTAssertTrue(sms.hasOlderMessages)

        sms.loadOlderMessages()
        XCTAssertTrue(sms.isLoadingMessages, "the older page must be requested")
        // A new message shifted the phone's offsets: m2 comes again.
        sms.handleMessage(.smsMessagesResponse(threadId: "A", messages: [message("m2"), message("m1"), message("m0")], totalCount: 4, page: 1))
        XCTAssertEqual(sms.currentMessages.map(\.id), ["m3", "m2", "m1", "m0"])
        XCTAssertFalse(sms.hasOlderMessages)
    }

    /// Nothing of a thread is kept once another is opened: back on it, the
    /// phone is asked again and only its newest page shows.
    func testReopenedThreadStartsFromThePhoneAgain() {
        sms.loadMessages(threadId: "A")
        sms.handleMessage(.smsMessagesResponse(threadId: "A", messages: [message("m3"), message("m2")], totalCount: 4, page: 0))
        sms.loadOlderMessages()
        sms.handleMessage(.smsMessagesResponse(threadId: "A", messages: [message("m1"), message("m0")], totalCount: 4, page: 1))

        sms.loadMessages(threadId: "B")
        sms.handleMessage(.smsMessagesResponse(threadId: "B", messages: [message("b0")], totalCount: 1, page: 0))

        sms.loadMessages(threadId: "A")
        XCTAssertTrue(sms.currentMessages.isEmpty, "nothing restored from earlier")
        sms.handleMessage(.smsMessagesResponse(threadId: "A", messages: [message("m3"), message("m2")], totalCount: 4, page: 0))
        XCTAssertEqual(sms.currentMessages.map(\.id), ["m3", "m2"])
    }

    /// A reply sent refreshes the open thread without dropping older pages.
    func testRefreshOfOpenThreadKeepsOlderPages() {
        sms.loadMessages(threadId: "A")
        sms.handleMessage(.smsMessagesResponse(threadId: "A", messages: [message("m3"), message("m2")], totalCount: 4, page: 0))
        sms.loadOlderMessages()
        sms.handleMessage(.smsMessagesResponse(threadId: "A", messages: [message("m1"), message("m0")], totalCount: 4, page: 1))

        sms.loadMessages(threadId: "A")
        sms.handleMessage(.smsMessagesResponse(threadId: "A", messages: [message("m4"), message("m3")], totalCount: 5, page: 0))
        XCTAssertEqual(sms.currentMessages.map(\.id), ["m4", "m3", "m2", "m1", "m0"])
    }
}
