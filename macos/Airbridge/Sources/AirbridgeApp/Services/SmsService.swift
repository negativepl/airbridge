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
    private(set) var sendResult: (success: Bool, error: String?)?

    private let pageSize = 30
    private weak var connectionService: ConnectionService?

    func configure(connectionService: ConnectionService) {
        self.connectionService = connectionService
    }

    func loadConversations(page: Int = 0) {
        guard let connectionService, connectionService.isConnected, !isLoadingConversations else { return }
        isLoadingConversations = true
        if page == 0 { conversations = [] }
        Task {
            try? await connectionService.broadcast(Message.smsConversationsRequest(page: page, pageSize: pageSize))
        }
    }

    func loadMessages(threadId: String, page: Int = 0) {
        guard let connectionService, connectionService.isConnected, !isLoadingMessages else { return }
        isLoadingMessages = true
        if page == 0 || currentThreadId != threadId {
            currentMessages = []
            currentThreadId = threadId
        }
        Task {
            try? await connectionService.broadcast(Message.smsMessagesRequest(threadId: threadId, page: page, pageSize: pageSize))
        }
    }

    func sendMessage(address: String, body: String) {
        guard let connectionService, connectionService.isConnected else { return }
        sendResult = nil
        Task {
            try? await connectionService.broadcast(Message.smsSendRequest(address: address, body: body))
        }
    }

    func handleMessage(_ message: Message) {
        switch message {
        case .smsConversationsResponse(let convos, let total, let page):
            if page == 0 {
                conversations = convos
            } else {
                conversations.append(contentsOf: convos)
            }
            totalConversations = total
            isLoadingConversations = false

        case .smsMessagesResponse(let threadId, let msgs, let total, let page):
            guard threadId == currentThreadId else { return }
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
