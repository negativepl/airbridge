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

    /// Short preview of the clipboard content that most recently arrived from
    /// the phone. Non-nil while the transfer popup is showing the receipt —
    /// without it an incoming link is applied to the pasteboard silently and
    /// the Mac looks like it did nothing at all.
    private(set) var incomingPreview: String? = nil

    /// Set when the received content is nothing but a web link, so the popup
    /// can offer an "Open" button. Restricted to http(s): opening arbitrary
    /// schemes on request of a remote device would hand the phone a way to
    /// launch local handlers.
    private(set) var incomingURL: URL? = nil

    /// Longest preview kept for the popup — matches `lastSyncedText`'s cap.
    private static let previewLimit = 200

    /// User preference: show the popup when clipboard content arrives.
    /// Every phone→Mac send is a deliberate user action, so there is no
    /// passive traffic to filter — silencing it has to be a choice.
    static var receiptEnabled: Bool {
        UserDefaults.standard.object(forKey: "clipboardReceipt") as? Bool ?? true
    }

    private let clipboardMonitor = ClipboardMonitor()
    private weak var connectionService: ConnectionService?

    func configure(connectionService: ConnectionService) {
        self.connectionService = connectionService
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
    }

    // MARK: - MessageHandler

    func handleMessage(_ message: Message) {
        guard case .clipboardUpdate(_, let contentType, let data) = message else { return }
        handleIncomingClipboard(contentType: contentType, data: data)
    }

    // MARK: - Incoming

    private func handleIncomingClipboard(contentType: ContentType, data: String) {
        let content: ClipboardContent
        let preview: String
        let url: URL?
        switch contentType {
        case .plainText, .html:
            content = ClipboardContent(contentType: contentType, textData: data, imageData: nil)
            lastSyncedText = String(data.prefix(Self.previewLimit))
            preview = Self.previewText(for: data)
            url = Self.detectURL(in: data)
        case .png:
            guard let imageData = Data(base64Encoded: data) else { return }
            content = ClipboardContent(contentType: contentType, textData: nil, imageData: imageData)
            lastSyncedText = "[Image]"
            preview = L10n.clipboardReceivedImage
            url = nil
        }
        clipboardMonitor.setClipboard(content: content)

        // The clipboard itself always syncs — the preference only governs
        // whether that is announced.
        guard Self.receiptEnabled else { return }

        incomingPreview = preview
        incomingURL = url
        // Surface the receipt in the transfer popup. The popup clears this
        // state again when it hides (see `TransferPopup.hide`), so the
        // countdown is the popup's — including the hover pause.
        TransferPopup.shared.show()
        TransferPopup.shared.resetIdleAutoHideTimer()
    }

    /// Called by the popup when it goes away, and by the "Open" action.
    func dismissIncomingPreview() {
        incomingPreview = nil
        incomingURL = nil
    }

    /// Open the received link in the default browser and drop the receipt.
    func openIncomingURL() {
        guard let url = incomingURL else { return }
        NSWorkspace.shared.open(url)
        dismissIncomingPreview()
        TransferPopup.shared.hide(delay: 0)
    }

    /// Single-line, length-capped rendering of received text for the popup.
    static func previewText(for text: String) -> String {
        let collapsed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return String(collapsed.prefix(previewLimit))
    }

    /// Domain the link points at — the part that actually answers "where does
    /// this go?". `www.` is dropped (it carries no information), any other
    /// subdomain stays.
    static func linkHost(_ url: URL) -> String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Everything after the domain, rendered for a human rather than for a
    /// browser: percent-escapes resolved and query "+" shown as spaces.
    /// Nil for a bare domain, which has no detail worth a second line.
    static func linkDetail(_ url: URL) -> String? {
        var detail = url.path
        if let query = url.query {
            detail += "?" + query.replacingOccurrences(of: "+", with: " ")
        }
        if let fragment = url.fragment {
            detail += "#" + fragment
        }
        let readable = detail.removingPercentEncoding ?? detail
        guard readable != "/" , !readable.isEmpty else { return nil }
        return String(readable.prefix(previewLimit))
    }

    /// The received text as a web link, or nil when it is ordinary text.
    /// Content that merely *mentions* a link stays plain text — only content
    /// that IS a single http(s) URL gets the Open affordance.
    static func detectURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
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
    }
}
