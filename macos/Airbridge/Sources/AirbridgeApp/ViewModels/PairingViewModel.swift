import Foundation
import AppKit
import Pairing

@Observable
@MainActor
final class PairingViewModel {
    @ObservationIgnored private let pairingService: PairingService
    @ObservationIgnored private let connectionService: ConnectionService

    var qrImage: NSImage?
    var errorMessage: String?
    var phase: Int = 0
    var pairedDeviceName: String = ""

    init(pairingService: PairingService, connectionService: ConnectionService) {
        self.pairingService = pairingService
        self.connectionService = connectionService
    }

    var isConnected: Bool { connectionService.isConnected }

    func generateQR() {
        guard let payload = pairingService.generateQRPayload() else {
            errorMessage = L10n.pairingFailed
            return
        }
        do {
            qrImage = try QRCodeGenerator.generate(from: payload, size: 256)
        } catch {
            errorMessage = "\(L10n.qrFailed): \(error.localizedDescription)"
        }
    }

    func onConnectionChanged() {
        if connectionService.isConnected && phase == 0 {
            pairedDeviceName = connectionService.connectedDeviceName
            phase = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.phase = 2
            }
        }
    }
}
