import Foundation

enum TransferPopupState: Equatable {
    /// No transfer in progress. Popup is showing the drop-zone affordance
    /// (connected → "drop file here", disconnected → "no device paired").
    case idle(connected: Bool)
    case incoming(filename: String, sizeBytes: Int64)
    case waiting(filename: String)
    case transferring(filename: String, progress: Double, isReceiving: Bool)
    case complete(filename: String, isReceiving: Bool)
    case rejected(filename: String)
    /// The transfer ended abnormally: the peer disconnected, the offer wait
    /// timed out, or the upload stalled mid-stream.
    case failed(filename: String)
    /// Ask-first headphone-switch prompt: playback started on this Mac while
    /// the phone holds idle headphones, and the user hasn't confirmed yet.
    case headphonePrompt
    /// Clipboard content just arrived from the phone and was applied to the
    /// pasteboard. `isLink` drives the "Open" button for plain web links.
    case clipboardReceived(preview: String, isLink: Bool)

    /// States the popup may leave on its own: nothing is in flight, so the
    /// idle countdown (with its hover pause) applies. A clipboard receipt is a
    /// notice, not a job — it must never hold the island open.
    var autoHides: Bool {
        switch self {
        case .idle, .clipboardReceived: return true
        default: return false
        }
    }

    var filename: String {
        switch self {
        case .idle, .headphonePrompt, .clipboardReceived:
            return ""
        case .incoming(let f, _),
             .waiting(let f),
             .transferring(let f, _, _),
             .complete(let f, _),
             .rejected(let f),
             .failed(let f):
            return f
        }
    }
}
