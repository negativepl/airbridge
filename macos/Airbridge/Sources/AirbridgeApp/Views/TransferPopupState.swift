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

    var filename: String {
        switch self {
        case .idle:
            return ""
        case .incoming(let f, _),
             .waiting(let f),
             .transferring(let f, _, _),
             .complete(let f, _),
             .rejected(let f):
            return f
        }
    }
}
