import Foundation
import UniformTypeIdentifiers
import AppKit

@Observable
@MainActor
final class TransferViewModel {
    @ObservationIgnored private let fileTransferService: FileTransferService
    @ObservationIgnored private let connectionService: ConnectionService

    init(fileTransferService: FileTransferService, connectionService: ConnectionService) {
        self.fileTransferService = fileTransferService
        self.connectionService = connectionService
    }

    var isConnected: Bool { connectionService.isConnected }
    var progress: Double { fileTransferService.fileTransferProgress }
    var fileName: String { fileTransferService.fileTransferFileName }
    var isSending: Bool { progress > 0 }

    func sendFile(url: URL) {
        fileTransferService.sendFile(url: url)
    }
}
