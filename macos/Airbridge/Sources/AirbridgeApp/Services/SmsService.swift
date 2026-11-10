import Foundation
import AppKit
import Protocol

@Observable
@MainActor
final class SmsService: MessageHandler, ActiveDeviceObserver {

    private(set) var conversations: [SmsConversationMeta] = []
    private(set) var currentMessages: [SmsMessageMeta] = []
    private(set) var currentThreadId: String?
    private(set) var totalConversations: Int = 0
    private(set) var totalMessages: Int = 0
    private(set) var isLoadingConversations: Bool = false
    /// The phone has answered a conversations request for this device. Tells
    /// "the phone has no messages to show" from "nothing was asked yet".
    private(set) var conversationsLoaded: Bool = false
    private(set) var isLoadingMessages: Bool = false
    /// The last conversations request received no response within `requestTimeout`.
    /// Views show a retryable failure state instead of spinning forever.
    private(set) var conversationsLoadFailed: Bool = false
    /// Same as `conversationsLoadFailed`, for the messages-of-a-thread request.
    private(set) var messagesLoadFailed: Bool = false
    private(set) var sendResult: (success: Bool, error: String?)?

    private let pageSize = 30
    private weak var connectionService: ConnectionService?
    /// How long a listing request may wait for the phone's response before it
    /// counts as lost (frozen phone app, reply dropped on a live socket).
    /// Internal so tests can shorten it.
    @ObservationIgnored var requestTimeout: TimeInterval = 20
    @ObservationIgnored private var conversationsWatchdogTask: Task<Void, Never>?
    @ObservationIgnored private var messagesWatchdogTask: Task<Void, Never>?
    /// When the pending requests left, for the response time in the diagnostics log.
    @ObservationIgnored private var conversationsRequestedAt: Date?
    @ObservationIgnored private var messagesRequestedAt: Date?

    func configure(connectionService: ConnectionService) {
        self.connectionService = connectionService
        // Earlier versions wrote conversation lists and whole threads to disk.
        DeviceDataCache.shared.removeFiles(named: "sms-")
    }

    // SMS stay on the phone: nothing of them is kept on the Mac beyond the
    // conversation on screen. Each opening asks the phone again.

    func loadConversations(page: Int = 0) {
        guard let connectionService, connectionService.isConnected, !isLoadingConversations else { return }
        isLoadingConversations = true
        conversationsLoadFailed = false
        conversationsRequestedAt = .now
        Task {
            try? await connectionService.sendToActive(Message.smsConversationsRequest(page: page, pageSize: pageSize))
        }
        conversationsWatchdogTask?.cancel()
        conversationsWatchdogTask = startWatchdog { service in
            guard service.isLoadingConversations else { return }
            service.isLoadingConversations = false
            service.conversationsLoadFailed = true
        }
    }

    /// The next page of conversations, when the phone has more.
    func loadMoreConversations() {
        guard conversations.count < totalConversations else { return }
        loadConversations(page: conversations.count / pageSize)
    }

    /// The open thread has older messages the phone has not sent yet.
    var hasOlderMessages: Bool { currentThreadId != nil && currentMessages.count < totalMessages }

    /// The next page back in the open thread, when it has one.
    func loadOlderMessages() {
        guard let currentThreadId, hasOlderMessages else { return }
        loadMessages(threadId: currentThreadId, page: currentMessages.count / pageSize)
    }

    func loadMessages(threadId: String, page: Int = 0) {
        // Only a request for the thread already loading waits; another thread
        // replaces it. Rejected, a conversation picked mid-load never loaded:
        // the earlier thread's reply was dropped and the panel stayed empty.
        guard let connectionService, connectionService.isConnected,
              !(isLoadingMessages && currentThreadId == threadId) else { return }
        isLoadingMessages = true
        messagesLoadFailed = false
        // Another thread starts empty. The open one refreshing (after a reply
        // is sent) keeps what is on screen; its newest page merges in.
        if currentThreadId != threadId {
            currentMessages = []
            totalMessages = 0
            currentThreadId = threadId
        }
        messagesRequestedAt = .now
        Task {
            try? await connectionService.sendToActive(Message.smsMessagesRequest(threadId: threadId, page: page, pageSize: pageSize))
        }
        messagesWatchdogTask?.cancel()
        messagesWatchdogTask = startWatchdog { service in
            guard service.isLoadingMessages else { return }
            service.isLoadingMessages = false
            service.messagesLoadFailed = true
        }
    }

    /// Fails an in-flight listing request when no response arrives within
    /// `requestTimeout` — the WebSocket itself still looks healthy in that
    /// case, so without this the view would spin forever.
    private func startWatchdog(onTimeout: @escaping @MainActor (SmsService) -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.requestTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onTimeout(self)
        }
    }

    private static func elapsedMillis(since start: Date?) -> Int {
        start.map { Int(Date.now.timeIntervalSince($0) * 1000) } ?? -1
    }

    func sendMessage(address: String, body: String) {
        guard let connectionService, connectionService.isConnected else { return }
        sendResult = nil
        Task {
            try? await connectionService.sendToActive(Message.smsSendRequest(address: address, body: body))
        }
    }

    /// The device our requests target changed (switch, drop, or disconnect):
    /// any in-flight load belongs to the previous phone — drop its
    /// loading/failure state so the stale `isLoading*` guards cannot reject
    /// the reload for the new device (the "empty list forever" bug).
    func activeDeviceChanged() {
        conversationsWatchdogTask?.cancel()
        messagesWatchdogTask?.cancel()
        isLoadingConversations = false
        isLoadingMessages = false
        conversationsLoaded = false
        conversationsLoadFailed = false
        messagesLoadFailed = false
        // Conversations and messages belong to the previous phone — clear
        // them so they are never shown as the new device's data.
        conversations = []
        currentMessages = []
        currentThreadId = nil
        totalConversations = 0
        totalMessages = 0
        sendResult = nil
    }

    func handleMessage(_ message: Message) {
        switch message {
        case .smsConversationsResponse(let convos, let total, let page):
            conversationsWatchdogTask?.cancel()
            conversationsLoadFailed = false
            if page == 0 {
                conversations = convos
            } else {
                conversations.append(contentsOf: convos)
            }
            totalConversations = total
            isLoadingConversations = false
            conversationsLoaded = true
            Diag.log("SMS", "conversations page \(page): \(convos.count) in \(Self.elapsedMillis(since: conversationsRequestedAt)) ms")

        case .smsMessagesResponse(let threadId, let msgs, let total, let page):
            guard threadId == currentThreadId else { return }
            messagesWatchdogTask?.cancel()
            messagesLoadFailed = false
            if page == 0 {
                // The fresh newest page replaces only its own span; older
                // pages already scrolled through stay where the reader is.
                let fresh = Set(msgs.map(\.id))
                let oldestFresh = msgs.last?.date ?? .max
                currentMessages = msgs + currentMessages.filter { !fresh.contains($0.id) && $0.date <= oldestFresh }
            } else {
                // A message arriving between pages shifts the phone's offsets
                // by one; skip what is already here rather than show it twice.
                let known = Set(currentMessages.map(\.id))
                currentMessages.append(contentsOf: msgs.filter { !known.contains($0.id) })
            }
            totalMessages = total
            isLoadingMessages = false
            Diag.log("SMS", "thread \(threadId) page \(page): \(msgs.count) of \(total) in \(Self.elapsedMillis(since: messagesRequestedAt)) ms")

        case .smsSendResponse(let success, let error):
            sendResult = (success, error)
            if success, let threadId = currentThreadId {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self?.loadMessages(threadId: threadId)
                }
            }

        default:
            break
        }
    }
}
