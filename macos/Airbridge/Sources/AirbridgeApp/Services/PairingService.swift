import Foundation
import Protocol
import Pairing
import AirbridgeSecurity

/// Manages device pairing: QR generation, token validation, paired device list.
@Observable
@MainActor
final class PairingService {

    private(set) var pairedDevices: [PairedDevice] = []

    private weak var connectionService: ConnectionService?

    func configure(connectionService: ConnectionService) {
        self.connectionService = connectionService
        refreshPairedDevices()
    }

    func generateQRPayload() -> QRPayload? {
        guard let connectionService,
              let ip = connectionService.getLocalIPAddress() else { return nil }
        do {
            return try connectionService.pairingManager.generatePairingPayload(host: ip, port: 8765)
        } catch {
            return nil
        }
    }

    func unpairDevice(publicKey: String) {
        guard let connectionService else { return }
        connectionService.pairingManager.unpair(publicKey: publicKey)
        refreshPairedDevices()
        connectionService.disconnect()
    }

    func unpairAll() {
        guard let connectionService else { return }
        for device in connectionService.pairingManager.pairedDevices {
            connectionService.pairingManager.unpair(publicKey: device.publicKeyBase64)
        }
        refreshPairedDevices()
        connectionService.disconnect()
    }

    func refreshPairedDevices() {
        guard let connectionService else { return }
        pairedDevices = connectionService.keyManager.getPairedDevices()
    }
}
