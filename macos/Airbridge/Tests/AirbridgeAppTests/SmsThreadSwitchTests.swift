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
}
