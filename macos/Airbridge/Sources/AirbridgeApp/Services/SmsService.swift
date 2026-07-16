import Foundation
import AppKit
import Protocol

@Observable
@MainActor
final class SmsService: MessageHandler {

    private(set) var conversations: [SmsConversationMeta] = []
    private(set) var currentMessages: [SmsMessageMeta] = []
    private(set) var currentThreadId: String?
    private(set) var totalConversations: Int = 0
    private(set) var totalMessages: Int = 0
    private(set) var isLoadingConversations: Bool = false
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

    func configure(connectionService: ConnectionService) {
        self.connectionService = connectionService
    }

    func loadConversations(page: Int = 0) {
        guard let connectionService, connectionService.isConnected, !isLoadingConversations else { return }
        isLoadingConversations = true
        conversationsLoadFailed = false
        if page == 0 { conversations = [] }
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

    func loadMessages(threadId: String, page: Int = 0) {
        guard let connectionService, connectionService.isConnected, !isLoadingMessages else { return }
        isLoadingMessages = true
        messagesLoadFailed = false
        if page == 0 || currentThreadId != threadId {
            currentMessages = []
            currentThreadId = threadId
        }
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

    func sendMessage(address: String, body: String) {
        guard let connectionService, connectionService.isConnected else { return }
        sendResult = nil
        Task {
            try? await connectionService.sendToActive(Message.smsSendRequest(address: address, body: body))
        }
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

        case .smsMessagesResponse(let threadId, let msgs, let total, let page):
            guard threadId == currentThreadId else { return }
            messagesWatchdogTask?.cancel()
            messagesLoadFailed = false
            if page == 0 {
                currentMessages = msgs
            } else {
                currentMessages.append(contentsOf: msgs)
            }
            totalMessages = total
            isLoadingMessages = false

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
