import Foundation
import Network

// MARK: - BonjourPublisher

/// Advertises the Airbridge service over Bonjour/mDNS using `NWListener`.
///
/// Creates a separate `NWListener` solely for service advertisement.
/// Incoming connections are immediately cancelled — the `WebSocketServer`
/// handles the actual WebSocket traffic.
public final class BonjourPublisher {

    // MARK: - Private State

    private let port: UInt16
    private var listener: NWListener?

    // MARK: - Init

    public init(port: UInt16) {
        self.port = port
    }

    // MARK: - Publish / Unpublish

    /// Starts advertising `"_airbridge._tcp"` with the given device name.
    ///
    /// - Parameter deviceName: The human-readable name shown in Bonjour discovery.
    public func publish(deviceName: String) {
        unpublish()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            print("[BonjourPublisher] Invalid port: \(port)")
            return
        }

        let service = NWListener.Service(
            name: deviceName,
            type: "_airbridge._tcp"
        )

        guard let listener = try? NWListener(using: .tcp, on: nwPort) else {
            print("[BonjourPublisher] Failed to create listener")
            return
        }

        listener.service = service

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[BonjourPublisher] Advertising '\(deviceName)' on port \(nwPort.rawValue)")
            case .failed(let error):
                print("[BonjourPublisher] Listener failed: \(error)")
            default:
                break
            }
        }

        // Cancel any incoming connections — WebSocketServer handles real traffic
        listener.newConnectionHandler = { connection in
            connection.cancel()
        }

        listener.start(queue: .global(qos: .background))
        self.listener = listener
    }

    /// Stops the Bonjour advertisement.
    public func unpublish() {
        listener?.cancel()
        listener = nil
    }
}
