import AppKit
import CryptoKit
import Foundation
import Protocol

// MARK: - ClipboardContent

/// Represents a snapshot of clipboard content at a moment in time.
public struct ClipboardContent {
    public let contentType: ContentType
    public let textData: String?
    public let imageData: Data?

    public init(contentType: ContentType, textData: String?, imageData: Data?) {
        self.contentType = contentType
        self.textData = textData
        self.imageData = imageData
    }
}

// MARK: - PasteboardProtocol

/// Abstracts NSPasteboard so ClipboardMonitor can be tested without a real pasteboard.
public protocol PasteboardProtocol: AnyObject {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }

    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func data(forType type: NSPasteboard.PasteboardType) -> Data?

    @discardableResult
    func clearContents() -> Int

    @discardableResult
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool

    @discardableResult
    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

// MARK: NSPasteboard conformance

extension NSPasteboard: PasteboardProtocol {}

// MARK: - MockPasteboard

/// In-memory pasteboard used in unit tests.
public final class MockPasteboard: PasteboardProtocol {

    private var _changeCount: Int = 0
    private var _string: String?
    private var _data: Data?
    private var _types: [NSPasteboard.PasteboardType] = []

    public var changeCount: Int { _changeCount }
    public var types: [NSPasteboard.PasteboardType]? { _types.isEmpty ? nil : _types }

    public init() {}

    public func string(forType type: NSPasteboard.PasteboardType) -> String? {
        guard type == .string || type == .html else { return nil }
        return _string
    }

    public func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        guard type == .png || type == .tiff else { return nil }
        return _data
    }

    @discardableResult
    public func clearContents() -> Int {
        _string = nil
        _data = nil
        _types = []
        _changeCount += 1
        return _changeCount
    }

    @discardableResult
    public func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        _string = string
        if !_types.contains(dataType) { _types.append(dataType) }
        return true
    }

    @discardableResult
    public func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        _data = data
        if !_types.contains(dataType) { _types.append(dataType) }
        return true
    }

    /// Simulates an external change to the pasteboard (e.g. a user copy action).
    public func simulateChange(string: String) {
        _string = string
        _types = [.string]
        _changeCount += 1
    }
}

// MARK: - ClipboardMonitor

/// Polls the system pasteboard for changes and fires `onChange` when new content is detected.
///
/// Loop-prevention: when `setClipboard(content:)` is called to push remote content,
/// `suppressNextChange` is set so that the resulting pasteboard change does not
/// re-trigger `onChange`.
///
/// Main-actor isolated: all pasteboard access happens on the main thread and the
/// polling timer is installed on `RunLoop.main`, so isolating the whole type both
/// matches reality and makes it `Sendable` for the timer's `@Sendable` closure.
@MainActor
public final class ClipboardMonitor {

    // MARK: Public

    /// Called whenever the pasteboard content changes to new unique content.
    public var onChange: ((ClipboardContent) -> Void)?

    // MARK: Private

    private let pasteboard: PasteboardProtocol
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastContentHash: String?
    private var suppressNextChange: Bool = false

    // MARK: Init

    public init(
        pasteboard: PasteboardProtocol = NSPasteboard.general,
        pollInterval: TimeInterval = 0.5
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.lastChangeCount = pasteboard.changeCount
    }

    // MARK: Control

    /// Starts timer-based polling of the pasteboard.
    public func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let t = Timer.scheduledTimer(
            withTimeInterval: pollInterval,
            repeats: true
        ) { [weak self] _ in
            // Installed on RunLoop.main below, so this @Sendable closure always
            // fires on the main actor; assumeIsolated bridges to it (and asserts
            // it at runtime) without hopping or silencing the isolation check.
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stops polling and invalidates the timer.
    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Writes content to the pasteboard WITHOUT triggering `onChange`.
    public func setClipboard(content: ClipboardContent) {
        suppressNextChange = true
        pasteboard.clearContents()

        switch content.contentType {
        case .plainText:
            if let text = content.textData {
                pasteboard.setString(text, forType: .string)
            }
        case .html:
            if let text = content.textData {
                pasteboard.setString(text, forType: .html)
            }
        case .png:
            if let data = content.imageData {
                pasteboard.setData(data, forType: .png)
            }
        }

        // Update tracking so the next poll skips this write
        lastChangeCount = pasteboard.changeCount
        // Pre-compute hash so a duplicate-check also suppresses it
        lastContentHash = hashForContent(content)
    }

    // MARK: Private Helpers

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if suppressNextChange {
            suppressNextChange = false
            return
        }

        guard let content = readContent() else { return }

        let hash = hashForContent(content)
        guard hash != lastContentHash else { return }
        lastContentHash = hash

        onChange?(content)
    }

    private func readContent() -> ClipboardContent? {
        let availableTypes = pasteboard.types ?? []

        // Plain text wins. The Android side applies every clipboard update via
        // ClipData.newPlainText, so sending the .html representation (which browsers
        // put on the pasteboard alongside .string) surfaces raw markup in the
        // keyboard preview. Prefer .string; only fall back to HTML when it is the
        // sole representation, flattening it to plain text first.
        if availableTypes.contains(.string),
           let text = pasteboard.string(forType: .string) {
            return ClipboardContent(contentType: .plainText, textData: text, imageData: nil)
        }

        if availableTypes.contains(.html),
           let html = pasteboard.string(forType: .html) {
            let text = Self.plainText(fromHTML: html) ?? html
            return ClipboardContent(contentType: .plainText, textData: text, imageData: nil)
        }

        if availableTypes.contains(.png),
           let data = pasteboard.data(forType: .png) {
            return ClipboardContent(contentType: .png, textData: nil, imageData: data)
        }

        return nil
    }

    /// Strips an HTML fragment down to its plain-text content.
    private static func plainText(fromHTML html: String) -> String? {
        guard let data = html.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil).string
    }

    private func hashForContent(_ content: ClipboardContent) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(content.contentType.rawValue.utf8))
        if let text = content.textData {
            hasher.update(data: Data(text.utf8))
        }
        if let imageData = content.imageData {
            hasher.update(data: imageData)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
