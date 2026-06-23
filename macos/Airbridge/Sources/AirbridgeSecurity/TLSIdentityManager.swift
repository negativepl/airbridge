import Foundation
import Security
import CryptoKit

public enum TLSIdentityError: Error, Sendable {
    case generationFailed(String)
    case importFailed(OSStatus)
    case certificateUnavailable
}

/// Owns the Mac's self-signed TLS identity. The PKCS#12 blob is persisted in
/// `FileStorage` (NOT the keychain); the `SecIdentity` is re-imported from it
/// on demand **into process memory only** (`kSecImportToMemoryOnly`), so macOS
/// never guards it behind a keychain prompt. The certificate is the app's TLS
/// trust anchor — its SHA-256(DER) fingerprint is distributed to the phone
/// inside the pairing QR code.
public final class TLSIdentityManager: @unchecked Sendable {
    private static let account = "tls_identity_p12"
    private static let passphrase = "airbridge-tls"   // protects only the on-disk P12 blob

    private let storage: any Storage
    private let lock = NSLock()
    private var cached: SecIdentity?

    init(storage: any Storage) {
        self.storage = storage
    }

    public convenience init() {
        // File-backed: a self-signed binary cannot keep a stable keychain
        // partition across re-signs, so any keychain re-prompts on every
        // rebuild. The P12 blob lives in FileStorage; the identity is imported
        // memory-only (see importIdentity) so no keychain is ever touched.
        self.init(storage: FileStorage())
    }

    /// Returns the persistent identity, generating it on first use.
    public func identity() throws -> SecIdentity {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let p12: Data
        if let existing = storage.load(account: Self.account) {
            p12 = existing
        } else {
            p12 = try Self.generatePKCS12()
            storage.save(p12, account: Self.account)
        }
        let identity = try Self.importIdentity(from: p12)
        cached = identity
        return identity
    }

    /// Lowercase SHA-256 hex over the certificate DER.
    public func certificateFingerprint() throws -> String {
        let identity = try identity()
        var cert: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &cert)
        guard status == errSecSuccess, let cert else {
            throw TLSIdentityError.certificateUnavailable
        }
        let der = SecCertificateCopyData(cert) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Generation (openssl / LibreSSL, ships with macOS)

    private static func generatePKCS12() throws -> Data {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("airbridge-tls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = dir.appendingPathComponent("key.pem").path
        let cert = dir.appendingPathComponent("cert.pem").path
        let p12 = dir.appendingPathComponent("identity.p12").path

        // ec_param_enc:named_curve is required: LibreSSL otherwise emits explicit
        // EC curve parameters, which SecPKCS12Import rejects (it crashes inside
        // SecIdentityCreate with a NULL SecKeyRef on macOS 26+).
        try run("/usr/bin/openssl",
                ["req", "-x509", "-newkey", "ec",
                 "-pkeyopt", "ec_paramgen_curve:P-256",
                 "-pkeyopt", "ec_param_enc:named_curve",
                 "-keyout", key, "-out", cert,
                 "-days", "3650", "-nodes", "-subj", "/CN=AirBridge"])
        try run("/usr/bin/openssl",
                ["pkcs12", "-export", "-inkey", key, "-in", cert,
                 "-out", p12, "-passout", "pass:\(passphrase)"])
        return try Data(contentsOf: URL(fileURLWithPath: p12))
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let stderr = Pipe()
        process.standardError = stderr
        // Discard stdout: an unread Pipe() would deadlock the process once its
        // buffer (~64 KB) fills up.
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? "unknown"
            throw TLSIdentityError.generationFailed(msg)
        }
    }

    private static func importIdentity(from p12: Data) throws -> SecIdentity {
        // Import WYŁĄCZNIE do pamięci procesu — żadnego keychaina. To definitywnie
        // eliminuje wszystkie monity macOS o hasło/dostęp do pęku: dla self-signed
        // apki keychain jest nie do ucywilizowania (ACL przypięty do cdhash zmienia
        // się co re-sign, partition list, auto-lock — każdy z osobna wywołuje monit
        // przy KAŻDYM użyciu klucza w handshake'u TLS). `kSecImportToMemoryOnly`
        // sprawia, że SecIdentity żyje w RAM i jest używana bezpośrednio przez
        // Network.framework (sec_identity_create) — nic nie trafia na dysk/pęk.
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: passphrase,
            kSecImportToMemoryOnly as String: kCFBooleanTrue as Any
        ]
        var items: CFArray?
        let status = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let identityRef = first[kSecImportItemIdentity as String] else {
            throw TLSIdentityError.importFailed(status)
        }
        // kSecImportItemIdentity is guaranteed SecIdentityRef by the Security framework.
        return (identityRef as! SecIdentity)
    }
}
