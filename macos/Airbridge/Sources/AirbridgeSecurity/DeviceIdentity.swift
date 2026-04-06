import Foundation

/// Represents the local device's cryptographic identity.
public struct DeviceIdentity: Sendable {
    /// A stable unique identifier for this device (UUID string).
    public let deviceId: String
    /// Base64-encoded Ed25519 public key.
    public let publicKeyBase64: String

    public init(deviceId: String, publicKeyBase64: String) {
        self.deviceId = deviceId
        self.publicKeyBase64 = publicKeyBase64
    }
}

/// Represents a remote device that has been paired with this device.
public struct PairedDevice: Codable, Sendable {
    public let deviceName: String
    public let publicKeyBase64: String
    public let pairedAt: Date

    public init(deviceName: String, publicKeyBase64: String, pairedAt: Date) {
        self.deviceName = deviceName
        self.publicKeyBase64 = publicKeyBase64
        self.pairedAt = pairedAt
    }
}
