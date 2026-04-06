import Foundation
import AppKit
import AirbridgeSecurity

@Observable
@MainActor
final class SettingsViewModel {
    @ObservationIgnored private let connectionService: ConnectionService
    @ObservationIgnored private let pairingService: PairingService

    init(connectionService: ConnectionService, pairingService: PairingService) {
        self.connectionService = connectionService
        self.pairingService = pairingService
    }

    var isConnected: Bool { connectionService.isConnected }
    var deviceName: String { connectionService.connectedDeviceName }
    var localIP: String? { connectionService.getLocalIPAddress() }
    var pairedDevices: [PairedDevice] { pairingService.pairedDevices }

    func unpairDevice(publicKey: String) {
        pairingService.unpairDevice(publicKey: publicKey)
    }
}
