import Foundation

@Observable
@MainActor
final class ConnectionViewModel {
    @ObservationIgnored private let connectionService: ConnectionService

    init(connectionService: ConnectionService) {
        self.connectionService = connectionService
    }

    var isConnected: Bool { connectionService.isConnected }
    var deviceName: String { connectionService.connectedDeviceName }
    var statusMessage: String { connectionService.statusMessage }
}
