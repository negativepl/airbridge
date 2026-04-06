import Foundation

@Observable
@MainActor
final class HomeViewModel {
    @ObservationIgnored private let connectionService: ConnectionService
    @ObservationIgnored private let fileTransferService: FileTransferService
    @ObservationIgnored private let historyService: HistoryService

    init(connectionService: ConnectionService, fileTransferService: FileTransferService, historyService: HistoryService) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
        self.historyService = historyService
    }

    var isConnected: Bool { connectionService.isConnected }
    var deviceName: String { connectionService.connectedDeviceName }
    var statusMessage: String { connectionService.statusMessage }
    var localIP: String? { connectionService.getLocalIPAddress() }

    var isTransferring: Bool { fileTransferService.fileTransferProgress > 0 }
    var transferProgress: Double { fileTransferService.fileTransferProgress }
    var transferFileName: String { fileTransferService.fileTransferFileName }
    var transferSpeed: Double { fileTransferService.transferSpeed }
    var transferEta: Int { fileTransferService.transferEta }

    var recentActivity: [TransferRecord] { historyService.recent(3) }
    var hasPairedDevices: Bool { !connectionService.keyManager.getPairedDevices().isEmpty }

    func disconnect() { connectionService.disconnect() }
    func reconnect() { connectionService.reconnect() }
}
