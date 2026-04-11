import Foundation

enum TransferPopupState: Equatable {
    case incoming(filename: String, sizeBytes: Int64)
    case waiting(filename: String)
    case transferring(filename: String, progress: Double, isReceiving: Bool)
    case complete(filename: String, isReceiving: Bool)
    case rejected(filename: String)

    var filename: String {
        switch self {
        case .incoming(let f, _),
             .waiting(let f),
             .transferring(let f, _, _),
             .complete(let f, _),
             .rejected(let f):
            return f
        }
    }
}
