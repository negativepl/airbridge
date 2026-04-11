import Foundation
import CryptoKit

// MARK: - Errors

public enum KeyManagerError: Error, Sendable {
    case noPrivateKey
    case invalidPublicKey
}

// MARK: - Storage Protocol

protocol Storage: Sendable {
    func load(account: String) -> Data?
    func save(_ data: Data, account: String)
    func delete(account: String)
}

// MARK: - InMemoryStorage

final class InMemoryStorage: Storage, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: Data] = [:]

    func load(account: String) -> Data? {
        lock.withLock { store[account] }
    }

    func save(_ data: Data, account: String) {
        lock.withLock { store[account] = data }
    }

    func delete(account: String) {
        lock.withLock { store.removeValue(forKey: account) }
    }
}

// MARK: - FileStorage

/// Stores key-value data as individual files inside ~/Library/Application Support/AirBridge/.
final class FileStorage: Storage, @unchecked Sendable {
    private let directory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("AirBridge")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for account: String) -> URL {
        directory.appendingPathComponent(account)
    }

    func load(account: String) -> Data? {
        try? Data(contentsOf: url(for: account))
    }

    func save(_ data: Data, account: String) {
        try? data.write(to: url(for: account), options: .atomic)
    }

    func delete(account: String) {
        try? FileManager.default.removeItem(at: url(for: account))
    }
}

// MARK: - KeyManager

/// Manages Ed25519 key pairs and paired-device storage.
/// Use `.ephemeral()` for in-memory (test) storage and `.persistent()` for Keychain-backed production storage.
public final class KeyManager: Sendable {

    // MARK: Keychain account names

    private enum Account {
        static let privateKey = "private_key"
        static let deviceId = "device_id"
        static let pairedDevice = "paired_device"
    }

    // MARK: Private state

    private let storage: any Storage

    // MARK: Init

    private init(storage: any Storage) {
        self.storage = storage
    }

    // MARK: Factory methods

    /// Creates a `KeyManager` backed by in-memory storage (suitable for tests).
    public static func ephemeral() -> KeyManager {
        KeyManager(storage: InMemoryStorage())
    }

    /// Creates a `KeyManager` backed by files in Application Support.
    public static func persistent() -> KeyManager {
        KeyManager(storage: FileStorage())
    }

    // MARK: Identity

    /// Returns the existing device identity or generates a new Ed25519 key pair and persists it.
    public func getOrCreateIdentity() throws -> DeviceIdentity {
        // Load or generate device ID
        let deviceId: String
        if let data = storage.load(account: Account.deviceId),
           let existing = String(data: data, encoding: .utf8) {
            deviceId = existing
        } else {
            let newId = UUID().uuidString
            storage.save(Data(newId.utf8), account: Account.deviceId)
            deviceId = newId
        }

        // Load or generate private key
        let privateKey: Curve25519.Signing.PrivateKey
        if let data = storage.load(account: Account.privateKey) {
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        } else {
            let newKey = Curve25519.Signing.PrivateKey()
            storage.save(newKey.rawRepresentation, account: Account.privateKey)
            privateKey = newKey
        }

        let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        return DeviceIdentity(deviceId: deviceId, publicKeyBase64: publicKeyBase64)
    }

    // MARK: Signing

    /// Signs `data` using the stored private key.
    public func sign(_ data: Data) throws -> Data {
        guard let keyData = storage.load(account: Account.privateKey) else {
            throw KeyManagerError.noPrivateKey
        }
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        return try privateKey.signature(for: data)
    }

    /// Verifies `signature` over `message` using the given Base64-encoded public key.
    public static func verify(message: Data, signature: Data, publicKeyBase64: String) throws -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyBase64) else {
            throw KeyManagerError.invalidPublicKey
        }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        return publicKey.isValidSignature(signature, for: message)
    }

    // MARK: Paired devices (multi-device)

    private static let pairedDevicesAccount = "paired_devices"

    /// Returns all stored paired devices.
    public func getPairedDevices() -> [PairedDevice] {
        guard let data = storage.load(account: Self.pairedDevicesAccount) else { return [] }
        return (try? JSONDecoder().decode([PairedDevice].self, from: data)) ?? []
    }

    /// Adds a paired device. Replaces existing entry with same publicKey.
    public func addPairedDevice(_ device: PairedDevice) {
        var devices = getPairedDevices()
        devices.removeAll { $0.publicKeyBase64 == device.publicKeyBase64 }
        devices.append(device)
        guard let data = try? JSONEncoder().encode(devices) else { return }
        storage.save(data, account: Self.pairedDevicesAccount)
    }

    /// Removes a paired device by public key.
    public func removePairedDevice(publicKey: String) {
        var devices = getPairedDevices()
        devices.removeAll { $0.publicKeyBase64 == publicKey }
        guard let data = try? JSONEncoder().encode(devices) else { return }
        storage.save(data, account: Self.pairedDevicesAccount)
    }

    /// Checks if a device with the given public key fingerprint is paired.
    public func isPaired(fingerprint: String) -> Bool {
        getPairedDevices().contains { fingerprintOf($0.publicKeyBase64) == fingerprint }
    }

    /// Checks if a device with the given public key (base64) is paired.
    public func isPairedByKey(_ publicKeyBase64: String) -> Bool {
        getPairedDevices().contains { $0.publicKeyBase64 == publicKeyBase64 }
    }

    /// SHA-256 fingerprint of a raw base64 public key.
    public func fingerprintOf(_ publicKeyBase64: String) -> String {
        guard let data = Data(base64Encoded: publicKeyBase64) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Migration: import old single paired device if present.
    public func migrateFromSingleDevice() {
        if let data = storage.load(account: Account.pairedDevice),
           let device = try? JSONDecoder().decode(PairedDevice.self, from: data) {
            addPairedDevice(device)
            storage.delete(account: Account.pairedDevice)
        }
    }
}
