import Foundation
import CryptoKit
import Security
import os

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
        lock.withLock { _ = store.removeValue(forKey: account) }
    }
}

// MARK: - FileStorage

/// Stores key-value data as individual files inside ~/Library/Application Support/AirBridge/.
///
/// This is the PRODUCTION backing store (see `KeyManager.persistent()` for the
/// rationale). The directory is created `0700` and every file `0600`, so only
/// the current macOS user account can read the material. That threat model —
/// "any process running as this user can read it" — is identical to what an
/// open-ACL login-keychain item would give us, and is the deliberate trade-off
/// documented on `KeyManager.persistent()`.
final class FileStorage: Storage, @unchecked Sendable {
    private let directory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("AirBridge")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // Tighten perms even if the directory already existed with looser bits.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func url(for account: String) -> URL {
        directory.appendingPathComponent(account)
    }

    func load(account: String) -> Data? {
        try? Data(contentsOf: url(for: account))
    }

    func save(_ data: Data, account: String) {
        let url = url(for: account)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Best-effort: storage failures surface later as a missing key.
        }
    }

    func delete(account: String) {
        try? FileManager.default.removeItem(at: url(for: account))
    }
}

// MARK: - KeychainStorage

/// Keychain-backed Storage (kSecClassGenericPassword). One item per account.
final class KeychainStorage: Storage, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.airbridge.macos", category: "keychain")

    private let service: String

    init(service: String = "com.airbridge.macos") {
        self.service = service
    }

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func save(_ data: Data, account: String) {
        let query = baseQuery(account: account)
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let status = SecItemUpdate(query as CFDictionary,
                                       [kSecValueData as String: data] as CFDictionary)
            if status != errSecSuccess {
                Self.logger.error("SecItemUpdate failed for account \(account, privacy: .public): status \(status)")
            }
        } else {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            if status != errSecSuccess {
                Self.logger.error("SecItemAdd failed for account \(account, privacy: .public): status \(status)")
            }
        }
    }

    func delete(account: String) {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Self.logger.error("SecItemDelete failed for account \(account, privacy: .public): status \(status)")
        }
    }

    /// Removes every item belonging to this service. Test-only helper.
    func deleteAll() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Self.logger.error("SecItemDelete (all) failed for service \(self.service, privacy: .public): status \(status)")
        }
    }
}

// MARK: - KeyManager

/// Manages Ed25519 key pairs and paired-device storage.
/// Use `.ephemeral()` for in-memory (test) storage and `.persistent()` for
/// disk-backed production storage.
public final class KeyManager: @unchecked Sendable {

    // MARK: Account names

    enum Account {
        static let privateKey = "private_key"
        static let deviceId = "device_id"
        static let pairedDevice = "paired_device"
    }

    // MARK: Private state

    private let storage: any Storage

    /// In-memory cache of the signing key so `sign()` does not hit storage on
    /// every AuthRequest / reconnect. Guarded by `keyLock`, mirroring the
    /// caching pattern in `TLSIdentityManager`.
    private let keyLock = NSLock()
    private var cachedPrivateKey: Curve25519.Signing.PrivateKey?

    // MARK: Init

    private init(storage: any Storage) {
        self.storage = storage
    }

    // MARK: Factory methods

    /// Creates a `KeyManager` backed by in-memory storage (suitable for tests).
    public static func ephemeral() -> KeyManager {
        KeyManager(storage: InMemoryStorage())
    }

    /// Copies each account from `legacy` into `target` (only when target has no
    /// value yet), then removes the legacy copy. Idempotent.
    static func migrate(from legacy: any Storage, to target: any Storage, accounts: [String]) {
        for account in accounts {
            guard target.load(account: account) == nil,
                  let data = legacy.load(account: account) else { continue }
            target.save(data, account: account)
            legacy.delete(account: account)
        }
    }

    /// Creates a `KeyManager` backed by on-disk storage in Application Support.
    ///
    /// Why not the login Keychain? AirBridge ships with a **self-signed** code
    /// signature (no Apple Developer ID). macOS keychain "partition lists"
    /// (securityd `clientid.cpp` / `acls.cpp`) classify self-signed code by its
    /// `cdhash:<hash>` — which changes on every rebuild — and match partitions
    /// by *exact* string. Only Apple-anchored code gets a stable `teamid:` /
    /// `apple:` partition. The Data-Protection keychain
    /// (`kSecUseDataProtectionKeychain`) needs an `application-identifier`
    /// entitlement we cannot mint without an Apple team, and returns
    /// `errSecMissingEntitlement` (-34018) for self-signed binaries.
    ///
    /// Net effect: every `dev-install` re-sign produced a new cdhash, so the
    /// previously granted "Always Allow" no longer matched and the login-keychain
    /// password prompt returned on each access. Verified empirically on this Mac
    /// (a differently-cdhashed but identically-cert-signed reader is denied an
    /// open-ACL item with errSecAuthFailed / a password prompt).
    ///
    /// File storage sidesteps securityd entirely: it never prompts and survives
    /// re-signs. Files are `0600` in a `0700` directory (see `FileStorage`).
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

        // Load or generate the private key (cached after first use).
        let privateKey = try loadOrCreatePrivateKey()

        let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        return DeviceIdentity(deviceId: deviceId, publicKeyBase64: publicKeyBase64)
    }

    /// Returns the cached signing key, loading it from storage (or generating
    /// and persisting a fresh one) on first use. Subsequent calls never touch
    /// storage. Thread-safe via `keyLock`.
    private func loadOrCreatePrivateKey() throws -> Curve25519.Signing.PrivateKey {
        keyLock.lock(); defer { keyLock.unlock() }
        if let cachedPrivateKey { return cachedPrivateKey }
        let key: Curve25519.Signing.PrivateKey
        if let data = storage.load(account: Account.privateKey) {
            key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        } else {
            key = Curve25519.Signing.PrivateKey()
            storage.save(key.rawRepresentation, account: Account.privateKey)
        }
        cachedPrivateKey = key
        return key
    }

    // MARK: Signing

    /// Signs `data` using the stored private key (read once, then cached).
    public func sign(_ data: Data) throws -> Data {
        let privateKey: Curve25519.Signing.PrivateKey
        do {
            privateKey = try loadOrCreatePrivateKey()
        } catch {
            throw KeyManagerError.noPrivateKey
        }
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
