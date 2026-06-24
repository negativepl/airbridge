import Foundation
import Protocol

@Observable
@MainActor
final class HomeViewModel {
    @ObservationIgnored private let connectionService: ConnectionService
    @ObservationIgnored private let fileTransferService: FileTransferService

    init(connectionService: ConnectionService, fileTransferService: FileTransferService) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
    }

    var isConnected: Bool { connectionService.isConnected }
    var deviceName: String { connectionService.connectedDeviceName }
    /// Display-only text; branch on `phase` for state logic.
    var statusMessage: String { connectionService.statusMessage }
    var phase: ConnectionPhase { connectionService.phase }
    var localIP: String? { connectionService.getLocalIPAddress() }

    var isTransferring: Bool { fileTransferService.fileTransferProgress > 0 }
    var transferProgress: Double { fileTransferService.fileTransferProgress }
    var transferFileName: String { fileTransferService.fileTransferFileName }
    var transferSpeed: Double { fileTransferService.transferSpeed }
    var transferEta: Int { fileTransferService.transferEta }

    var hasPairedDevices: Bool { !connectionService.keyManager.getPairedDevices().isEmpty }
    var deviceInfo: DeviceInfo? { connectionService.deviceInfo }
    var connectedDevices: [ConnectedDevice] { connectionService.connectedDevices }

    func disconnect() { connectionService.disconnect() }
    func reconnect() { connectionService.reconnect() }
}
