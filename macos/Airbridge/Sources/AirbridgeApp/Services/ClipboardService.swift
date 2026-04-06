import Foundation
import AppKit
import Protocol
import Clipboard
import AirbridgeSecurity

/// Monitors the local clipboard and syncs changes with the connected device.
@Observable
@MainActor
final class ClipboardService: MessageHandler {

    private(set) var lastSyncedText: String = ""

    private let clipboardMonitor = ClipboardMonitor()
    private weak var connectionService: ConnectionService?
    private weak var historyService: HistoryService?

    func configure(connectionService: ConnectionService, historyService: HistoryService) {
        self.connectionService = connectionService
        self.historyService = historyService
    }

    func startMonitoring() {
        clipboardMonitor.onChange = { [weak self] content in
            Task { @MainActor in
                self?.handleClipboardChange(content)
            }
        }
        clipboardMonitor.start()
    }

    func stopMonitoring() {
        clipboardMonitor.stop()
    }

    func sendCurrentClipboard() {
        guard let connectionService, connectionService.isConnected else { return }
        guard let text = NSPasteboard.general.string(forType: .string) else { return }

        let identity: DeviceIdentity
        do {
            identity = try connectionService.keyManager.getOrCreateIdentity()
        } catch {
            return
        }

        let message = Message.clipboardUpdate(
            sourceId: identity.deviceId,
            contentType: .plainText,
            data: text
        )

        lastSyncedText = String(text.prefix(200))
        Task {
            try? await connectionService.broadcast(message)
        }
        historyService?.add(type: .clipboard, direction: .sent, description: lastSyncedText)
    }

    // MARK: - MessageHandler

    func handleMessage(_ message: Message) {
        guard case .clipboardUpdate(_, let contentType, let data) = message else { return }
        handleIncomingClipboard(contentType: contentType, data: data)
    }

    // MARK: - Incoming

    private func handleIncomingClipboard(contentType: ContentType, data: String) {
        let content: ClipboardContent
        switch contentType {
        case .plainText, .html:
            content = ClipboardContent(contentType: contentType, textData: data, imageData: nil)
            lastSyncedText = String(data.prefix(200))
        case .png:
            guard let imageData = Data(base64Encoded: data) else { return }
            content = ClipboardContent(contentType: contentType, textData: nil, imageData: imageData)
            lastSyncedText = "[Image]"
        }
        clipboardMonitor.setClipboard(content: content)
        historyService?.add(type: .clipboard, direction: .received, description: lastSyncedText)
    }

    // MARK: - Outgoing

    private func handleClipboardChange(_ content: ClipboardContent) {
        guard let connectionService, connectionService.isConnected else { return }

        let identity: DeviceIdentity
        do {
            identity = try connectionService.keyManager.getOrCreateIdentity()
        } catch {
            return
        }

        let dataString: String
        switch content.contentType {
        case .plainText, .html:
            guard let text = content.textData else { return }
            dataString = text
            lastSyncedText = String(text.prefix(200))
        case .png:
            guard let imageData = content.imageData else { return }
            dataString = imageData.base64EncodedString()
            lastSyncedText = "[Image]"
        }

        let message = Message.clipboardUpdate(
            sourceId: identity.deviceId,
            contentType: content.contentType,
            data: dataString
        )

        Task {
            try? await connectionService.broadcast(message)
        }
        historyService?.add(type: .clipboard, direction: .sent, description: lastSyncedText)
    }
}
