import Foundation
import Protocol
import AirbridgeSecurity

// MARK: - PairingPayload

/// Type alias so the Pairing module can refer to `PairingPayload` without
/// duplicating the definition that already lives in the Protocol module as
/// `QRPayload`.
public typealias PairingPayload = QRPayload

// MARK: - PairingManager

/// Manages the pairing lifecycle: payload generation, token validation,
/// storing/removing the paired device.
public final class PairingManager: @unchecked Sendable {

    // MARK: Private state

    private let keyManager: KeyManager
    private var activeToken: String?
    private let lock = NSLock()

    // MARK: Init

    public init(keyManager: KeyManager) {
        self.keyManager = keyManager
    }

    // MARK: Payload generation

    /// Creates a `PairingPayload` suitable for encoding in a QR code.
    ///
    /// - Parameters:
    ///   - host: The IPv4/IPv6 address or hostname of this device.
    ///   - port: The TCP port the WebSocket server is listening on.
    /// - Returns: A fully populated `PairingPayload`.
    /// - Throws: If the identity key cannot be read / created.
    public func generatePairingPayload(host: String, port: Int) throws -> PairingPayload {
        let identity = try keyManager.getOrCreateIdentity()
        let token = UUID().uuidString
        lock.withLock { activeToken = token }
        return PairingPayload(
            host: host,
            port: port,
            publicKey: identity.publicKeyBase64,
            pairingToken: token,
            protocolVersion: 1
        )
    }

    // MARK: Token validation

    /// Validates the supplied token against the active one-time token.
    ///
    /// The token is cleared after a successful validation (one-time use).
    ///
    /// - Parameter token: The token received from the remote device.
    /// - Returns: `true` if the token matches; `false` otherwise.
    public func validateToken(_ token: String) -> Bool {
        lock.withLock {
            guard let current = activeToken, current == token else {
                return false
            }
            activeToken = nil
            return true
        }
    }

    // MARK: Pairing state

    /// Stores the paired remote device's name and public key.
    ///
    /// - Parameters:
    ///   - deviceName: Human-readable name of the remote device.
    ///   - publicKey: Base64-encoded Ed25519 public key of the remote device.
    public func completePairing(deviceName: String, publicKey: String) {
        let device = PairedDevice(
            deviceName: deviceName,
            publicKeyBase64: publicKey,
            pairedAt: Date()
        )
        keyManager.addPairedDevice(device)
    }

    /// Returns `true` when at least one paired device is stored.
    public var isPaired: Bool {
        !keyManager.getPairedDevices().isEmpty
    }

    /// All currently paired devices.
    public var pairedDevices: [PairedDevice] {
        keyManager.getPairedDevices()
    }

    /// Removes the paired device with the given public key.
    public func unpair(publicKey: String) {
        keyManager.removePairedDevice(publicKey: publicKey)
    }
}
