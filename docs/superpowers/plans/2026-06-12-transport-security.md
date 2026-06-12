# Transport Security (TLS + Secure Key Storage) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encrypt all Mac↔phone traffic with TLS (pinned self-signed cert, trust anchor = pairing QR) and move private keys into Keychain (macOS) / Keystore-wrapped storage (Android).

**Architecture:** Mac generates a self-signed EC P-256 cert via `openssl` at first run, keeps it as a `SecIdentity` (PKCS#12 blob in Keychain), and serves TLS on all three listeners (WS 8765, HTTP 8766, mirror 8767). The cert's SHA-256(DER) fingerprint travels in the QR payload (`cert_fingerprint`) and informationally in the NSD TXT record. Android pins exactly that fingerprint via a custom `X509TrustManager` shared by all OkHttp clients (`wss://`/`https://`). Existing pairings have no pin → user re-pairs once (approved decision, no migration of trust). Independently, the Android Ed25519 private key gets encrypted at rest with an AndroidKeyStore AES-GCM master key, and macOS `Storage.persistent()` moves from files to the Keychain.

**Tech Stack:** Network.framework (`NWProtocolTLS`), Security.framework (`SecPKCS12Import`, `SecItem*`), CryptoKit, LibreSSL (`/usr/bin/openssl` via `Process`), OkHttp 4 (`sslSocketFactory`), AndroidKeyStore (`KeyGenParameterSpec`), javax.crypto AES-GCM.

**Spec:** `docs/superpowers/specs/2026-06-12-transport-security-design.md`

**Conventions:** commits in English (public repo), conventional commits, work on `master`. Build/test commands: macOS `cd macos/Airbridge && swift build && swift test`; Android `cd android/Airbridge && ./gradlew assembleDebug testDebugUnitTest`. Known pre-existing flaky: `MirrorIntegrationTests` HELLO_ACK (UserDefaults pollution) — verify in isolation before calling anything a regression. Do NOT touch the user's uncommitted WIP in `docs/landing/index.html`.

---

### Task 1: macOS KeychainStorage + migration from FileStorage

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeSecurity/KeyManager.swift`
- Test: `macos/Airbridge/Tests/AirbridgeSecurityTests/KeychainStorageTests.swift` (create; check `Package.swift` — if no `AirbridgeSecurityTests` target exists, add one mirroring the existing test targets)

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import AirbridgeSecurity

final class KeychainStorageTests: XCTestCase {
    // Unique service per run so tests never touch real app data and never collide.
    private let service = "com.airbridge.tests.\(UUID().uuidString)"
    private var storage: KeychainStorage!

    override func setUp() {
        super.setUp()
        storage = KeychainStorage(service: service)
    }

    override func tearDown() {
        for account in ["a", "b", "private_key"] { storage.delete(account: account) }
        super.tearDown()
    }

    func testRoundTrip() {
        XCTAssertNil(storage.load(account: "a"))
        storage.save(Data("hello".utf8), account: "a")
        XCTAssertEqual(storage.load(account: "a"), Data("hello".utf8))
        storage.save(Data("world".utf8), account: "a")   // update path
        XCTAssertEqual(storage.load(account: "a"), Data("world".utf8))
        storage.delete(account: "a")
        XCTAssertNil(storage.load(account: "a"))
    }

    func testMigrationCopiesLegacyDataOnce() {
        let legacy = InMemoryStorage()
        legacy.save(Data("key-bytes".utf8), account: "private_key")
        KeyManager.migrate(from: legacy, to: storage, accounts: ["private_key"])
        XCTAssertEqual(storage.load(account: "private_key"), Data("key-bytes".utf8))
        XCTAssertNil(legacy.load(account: "private_key"))   // legacy cleared
        // Second migration with different legacy content must NOT overwrite.
        legacy.save(Data("attacker".utf8), account: "private_key")
        KeyManager.migrate(from: legacy, to: storage, accounts: ["private_key"])
        XCTAssertEqual(storage.load(account: "private_key"), Data("key-bytes".utf8))
    }
}
```

- [ ] **Step 2: Run tests, verify they fail** (`swift test --filter KeychainStorageTests`) — expected: compile error, `KeychainStorage`/`migrate` undefined.

- [ ] **Step 3: Implement.** In `KeyManager.swift` add after `FileStorage`:

```swift
// MARK: - KeychainStorage

/// Keychain-backed Storage (kSecClassGenericPassword). One item per account.
final class KeychainStorage: Storage, @unchecked Sendable {
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
            SecItemUpdate(query as CFDictionary,
                          [kSecValueData as String: data] as CFDictionary)
        } else {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
```

Add `import Security` at the top of the file. In `KeyManager` add the migration helper and switch `persistent()`:

```swift
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

/// Creates a `KeyManager` backed by the Keychain, migrating any legacy
/// file-based data from Application Support on first use.
public static func persistent() -> KeyManager {
    let keychain = KeychainStorage()
    migrate(from: FileStorage(), to: keychain,
            accounts: [Account.privateKey, Account.deviceId,
                       Account.pairedDevice, pairedDevicesAccount])
    return KeyManager(storage: keychain)
}
```

Update the class doc comment (line 70) — it finally tells the truth. `migrate` needs `Account`/`pairedDevicesAccount` visibility: `Account` is a private enum — make the migration call sites pass string literals OR widen `Account` to `internal`; prefer widening to `internal` (same file/module, no API leak).

- [ ] **Step 4: Run tests** (`swift test --filter KeychainStorageTests`) — expected: PASS. Also run `swift test --filter AirbridgeSecurity` to confirm nothing else broke.

- [ ] **Step 5: Commit** — `git add macos/ && git commit -m "feat(macos): Keychain-backed key storage with one-time file migration"`

---

### Task 2: macOS TLSIdentityManager

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeSecurity/TLSIdentityManager.swift`
- Test: `macos/Airbridge/Tests/AirbridgeSecurityTests/TLSIdentityManagerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import AirbridgeSecurity

final class TLSIdentityManagerTests: XCTestCase {
    private let service = "com.airbridge.tests.tls.\(UUID().uuidString)"

    override func tearDown() {
        KeychainStorage(service: service).delete(account: "tls_identity_p12")
        super.tearDown()
    }

    func testCreatesIdentityAndStableFingerprint() throws {
        let manager = TLSIdentityManager(storage: KeychainStorage(service: service))
        let identity = try manager.identity()
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        XCTAssertNotNil(cert)

        let fp1 = try manager.certificateFingerprint()
        XCTAssertEqual(fp1.count, 64)                      // SHA-256 hex
        XCTAssertEqual(fp1, fp1.lowercased())

        // Second manager over the same storage loads the SAME identity.
        let manager2 = TLSIdentityManager(storage: KeychainStorage(service: service))
        XCTAssertEqual(try manager2.certificateFingerprint(), fp1)
    }
}
```

- [ ] **Step 2: Run, verify failure** (`swift test --filter TLSIdentityManagerTests`) — compile error expected.

- [ ] **Step 3: Implement** `TLSIdentityManager.swift`:

```swift
import Foundation
import Security
import CryptoKit

public enum TLSIdentityError: Error, Sendable {
    case generationFailed(String)
    case importFailed(OSStatus)
    case certificateUnavailable
}

/// Owns the Mac's self-signed TLS identity. The PKCS#12 blob lives in the
/// Keychain (via Storage); the SecIdentity is re-imported from it on demand.
/// The certificate is the app's TLS trust anchor — its SHA-256(DER)
/// fingerprint is distributed to the phone inside the pairing QR code.
public final class TLSIdentityManager: @unchecked Sendable {
    private static let account = "tls_identity_p12"
    private static let passphrase = "airbridge-tls"   // protects only the in-Keychain blob

    private let storage: any Storage
    private let lock = NSLock()
    private var cached: SecIdentity?

    init(storage: any Storage) {
        self.storage = storage
    }

    public convenience init() {
        self.init(storage: KeychainStorage())
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
        SecIdentityCopyCertificate(identity, &cert)
        guard let cert else { throw TLSIdentityError.certificateUnavailable }
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

        try run("/usr/bin/openssl",
                ["req", "-x509", "-newkey", "ec",
                 "-pkeyopt", "ec_paramgen_curve:P-256",
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
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? "unknown"
            throw TLSIdentityError.generationFailed(msg)
        }
    }

    private static func importIdentity(from p12: Data) throws -> SecIdentity {
        let options = [kSecImportExportPassphrase as String: passphrase]
        var items: CFArray?
        let status = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let identityRef = first[kSecImportItemIdentity as String] else {
            throw TLSIdentityError.importFailed(status)
        }
        return (identityRef as! SecIdentity)
    }
}
```

Note: `SecPKCS12Import` on modern macOS may require `kSecUseDataProtectionKeychain`-style handling; if the plain call returns `errSecMissingEntitlement` in tests, add `kSecReturnRef` no — instead pass `[kSecImportExportPassphrase: passphrase, kSecUseDataProtectionKeychain: false]`. Verify empirically in Step 4 and keep whichever variant works in the test runner AND in the signed app.

- [ ] **Step 4: Run tests** (`swift test --filter TLSIdentityManagerTests`) — expected: PASS (generation takes ~1 s).

- [ ] **Step 5: Commit** — `git commit -m "feat(macos): self-signed TLS identity manager backed by the Keychain"`

---

### Task 3: TLS on all macOS listeners + integration tests over TLS

**Files:**
- Modify: `macos/Airbridge/Sources/Networking/WebSocketServer.swift` (start(); NWParameters construction ~line 101-123)
- Modify: `macos/Airbridge/Sources/Networking/HttpUploadServer.swift` (start(); NWParameters ~line 99-110)
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/MirrorService.swift` (its own `WebSocketServer(port: 8767)` start call)
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift` (owns `TLSIdentityManager`, passes identity into all three)
- Modify: `macos/Airbridge/Tests/NetworkingTests/WebSocketServerTests.swift`, `macos/Airbridge/Tests/IntegrationTests/EndToEndTests.swift`, `macos/Airbridge/Tests/IntegrationTests/MirrorIntegrationTests.swift` (TLS client + test identity)
- Modify: `macos/Airbridge/Package.swift` (Networking target may NOT depend on AirbridgeSecurity today — check; the TLS parameter type is `SecIdentity`, plain Security framework, so no new target dependency is needed in Networking; tests need AirbridgeSecurity for `TLSIdentityManager`)

- [ ] **Step 1: Change server signatures.** In `WebSocketServer.start(...)` add a required parameter `tlsIdentity: SecIdentity` and build parameters like this (replacing `NWParameters.tcp`):

```swift
import Security   // top of file

// inside start(), replacing `let parameters = NWParameters.tcp`:
let tlsOptions = NWProtocolTLS.Options()
sec_protocol_options_set_local_identity(
    tlsOptions.securityProtocolOptions,
    sec_identity_create(tlsIdentity)!)
let parameters = NWParameters(tls: tlsOptions)
```

The existing WebSocket options insertion (`parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)`) stays exactly as it is. Apply the same `NWParameters(tls:)` change in `HttpUploadServer.start()` (it has no WS options — only the TLS swap). Keep everything else (Bonjour TXT, stop logic, continuations) untouched.

- [ ] **Step 2: Wire the identity through.** In `ConnectionService`: create one `private let tlsIdentityManager = TLSIdentityManager()`; in `startServerNow()` (and any other `server.start`/`httpServer.start` call sites) obtain `let identity = try tlsIdentityManager.identity()` and pass `tlsIdentity: identity`. In `MirrorService`: add `var tlsIdentity: SecIdentity?` (set by `ConnectionService` before `start()`, same place it sets callbacks) and pass it to its server's `start`. A `nil` mirror identity is a programmer error → `guard let` + log + return without starting (mirror simply won't run; main channels unaffected).

- [ ] **Step 3: Fix the tests.** All tests that start a server must pass a test identity; all test clients must trust it. Add a shared helper file `macos/Airbridge/Tests/NetworkingTests/TLSTestSupport.swift`:

```swift
import Foundation
import Security
@testable import AirbridgeSecurity

enum TLSTestSupport {
    /// One throwaway identity per test process.
    static let identity: SecIdentity = {
        let storage = InMemoryStorage()
        return try! TLSIdentityManager(storage: storage).identity()
    }()
}

/// URLSession delegate that accepts any server certificate (test-only).
final class TrustAllDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
```

If `InMemoryStorage`/`TLSIdentityManager` aren't visible from NetworkingTests, give IntegrationTests/NetworkingTests a dependency on `AirbridgeSecurity` in `Package.swift`. Update every `server.start(...)` in tests to add `tlsIdentity: TLSTestSupport.identity`, every test URL from `ws://`→`wss://`, and every `URLSession.shared.webSocketTask` to `URLSession(configuration: .default, delegate: TrustAllDelegate(), delegateQueue: nil).webSocketTask(...)`. Same treatment in `MirrorIntegrationTests` (it spins up the mirror server).

- [ ] **Step 4: Build and run the full suite.** `swift build && swift test`. Expected: all green except (possibly) the known flaky HELLO_ACK. The TLS handshake is now exercised by `WebSocketServerTests` and `EndToEndTests` for real.

- [ ] **Step 5: Commit** — `git commit -m "feat(macos): serve all listeners over TLS with the persistent self-signed identity"`

---

### Task 4: cert_fingerprint in QR payload + NSD TXT (macOS)

**Files:**
- Modify: `macos/Airbridge/Sources/Protocol/Message.swift` (`QRPayload`, ~line 1046-1074)
- Modify: `macos/Airbridge/Sources/Pairing/PairingManager.swift` (`generatePairingPayload`, ~line 39-50)
- Modify: `macos/Airbridge/Sources/Networking/WebSocketServer.swift` (Bonjour TXT, ~line 123-133)
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift` (pass fingerprint to both)
- Test: extend `macos/Airbridge/Tests/ProtocolTests/MessageTests.swift` (QRPayload) and `macos/Airbridge/Tests/PairingTests/PairingManagerTests.swift`

- [ ] **Step 1: Write failing tests.** In `MessageTests` (follow the file's existing QRPayload test style if one exists, otherwise add):

```swift
func testQRPayloadCarriesCertFingerprint() throws {
    let payload = QRPayload(host: "1.2.3.4", port: 8765,
                            publicKey: "cGs=", pairingToken: "tok",
                            certFingerprint: "ab12")
    let data = try JSONEncoder().encode(payload)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["cert_fingerprint"] as? String, "ab12")
    let decoded = try JSONDecoder().decode(QRPayload.self, from: data)
    XCTAssertEqual(decoded.certFingerprint, "ab12")
}
```

In `PairingManagerTests`: assert `generatePairingPayload(...)` (with a fingerprint argument, see Step 3) produces a payload whose `certFingerprint` equals the argument.

- [ ] **Step 2: Run, verify failure.**

- [ ] **Step 3: Implement.** `QRPayload`: add `public let certFingerprint: String`, CodingKey `case certFingerprint = "cert_fingerprint"`, update the memberwise init (keep `protocolVersion` defaulting to `ProtocolConstants.version`). `PairingManager.generatePairingPayload` gains `certFingerprint: String` parameter and passes it through. `WebSocketServer.start` gains `certFingerprint: String?` and adds `txtRecord["cert_fingerprint"] = certFingerprint` next to `pk_fingerprint`. `ConnectionService` computes `try tlsIdentityManager.certificateFingerprint()` once in `startServerNow()` and passes it to both `server.start` and wherever `generatePairingPayload` is invoked (PairingView/PairingManager call site — grep for `generatePairingPayload`).

- [ ] **Step 4: Run** `swift build && swift test --filter ProtocolTests && swift test --filter PairingTests` — PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(macos): distribute TLS certificate fingerprint via pairing QR and NSD TXT"`

---

### Task 5: Android KeyManager — Keystore-wrapped private key

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/security/KeyCrypto.kt`
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/security/KeyManager.kt`
- Test: `android/Airbridge/app/src/test/java/com/airbridge/security/KeyCryptoTest.kt` (create)

AndroidKeyStore does not exist on the JVM, so the AES-GCM logic is a pure object taking a `SecretKey` (unit-testable); only the master-key lookup touches AndroidKeyStore.

- [ ] **Step 1: Write failing tests**

```kotlin
package com.airbridge.security

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import javax.crypto.AEADBadTagException
import javax.crypto.KeyGenerator

class KeyCryptoTest {

    private fun jvmKey() = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()

    @Test
    fun `encrypt then decrypt round-trips`() {
        val key = jvmKey()
        val plaintext = "private-key-bytes".toByteArray()
        val blob = KeyCrypto.encrypt(key, plaintext)
        assertArrayEquals(plaintext, KeyCrypto.decrypt(key, blob))
    }

    @Test
    fun `each encryption uses a fresh IV`() {
        val key = jvmKey()
        val a = KeyCrypto.encrypt(key, byteArrayOf(1, 2, 3))
        val b = KeyCrypto.encrypt(key, byteArrayOf(1, 2, 3))
        org.junit.Assert.assertFalse(a.contentEquals(b))
    }

    @Test
    fun `tampered blob fails authentication`() {
        val key = jvmKey()
        val blob = KeyCrypto.encrypt(key, byteArrayOf(9, 9, 9))
        blob[blob.size - 1] = (blob[blob.size - 1].toInt() xor 1).toByte()
        assertThrows(AEADBadTagException::class.java) { KeyCrypto.decrypt(key, blob) }
    }
}
```

- [ ] **Step 2: Run** `./gradlew testDebugUnitTest --tests com.airbridge.security.KeyCryptoTest` — compile failure expected.

- [ ] **Step 3: Implement** `KeyCrypto.kt`:

```kotlin
package com.airbridge.security

import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM wrap/unwrap for the Ed25519 private key blob.
 * Blob layout: 12-byte IV || ciphertext+tag. Pure JVM logic — the Keystore
 * master key is resolved by the caller (KeyManager) so this stays unit-testable.
 */
object KeyCrypto {
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    fun encrypt(key: SecretKey, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        return cipher.iv + cipher.doFinal(plaintext)
    }

    fun decrypt(key: SecretKey, blob: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(TAG_BITS, blob, 0, IV_BYTES)
        cipher.init(Cipher.DECRYPT_MODE, key, spec)
        return cipher.doFinal(blob, IV_BYTES, blob.size - IV_BYTES)
    }
}
```

Then in `KeyManager.kt`: add the Keystore master key + migration and switch `sign()`/`generateKeyPair()` to the encrypted entry:

```kotlin
// new imports
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

// inside KeyManager
private companion object MasterKey {
    const val ALIAS = "airbridge_master_key"
    const val PREF_ENC = "private_key_enc"
    const val PREF_PLAINTEXT = "private_key_base64"   // legacy
}

private fun masterKey(): SecretKey {
    val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (ks.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
    val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    generator.init(
        KeyGenParameterSpec.Builder(ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build())
    return generator.generateKey()
}

/** One-time migration: encrypt a legacy plaintext private key, drop the plaintext. */
private fun migratePrivateKeyIfNeeded() {
    val plaintext = prefs.getString(PREF_PLAINTEXT, null) ?: return
    val blob = KeyCrypto.encrypt(masterKey(), Base64.decode(plaintext, Base64.NO_WRAP))
    prefs.edit()
        .putString(PREF_ENC, Base64.encodeToString(blob, Base64.NO_WRAP))
        .remove(PREF_PLAINTEXT)
        .apply()
}

private fun loadPrivateKeyBytes(): ByteArray {
    migratePrivateKeyIfNeeded()
    val enc = prefs.getString(PREF_ENC, null) ?: throw IllegalStateException("No private key")
    return KeyCrypto.decrypt(masterKey(), Base64.decode(enc, Base64.NO_WRAP))
}
```

`sign()` uses `loadPrivateKeyBytes()` instead of reading `private_key_base64`. `generateKeyPair()` stores `PREF_ENC` (encrypt the PKCS#8 bytes) instead of `private_key_base64`. Note: there is a name clash risk — `private companion object MasterKey` cannot coexist with the existing `companion object { fun fingerprintOf }`; merge the constants into the existing companion object instead (Kotlin allows one companion per class).

- [ ] **Step 4: Run** `./gradlew testDebugUnitTest --tests com.airbridge.security.KeyCryptoTest` (PASS) and `./gradlew assembleDebug` (compiles; Keystore path runs only on device).

- [ ] **Step 5: Commit** — `git commit -m "feat(android): encrypt the Ed25519 private key at rest with an AndroidKeyStore master key"`

---

### Task 6: Android PairedDevice.certFingerprint

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/security/PairedDeviceStore.kt`
- Test: `android/Airbridge/app/src/test/java/com/airbridge/security/PairedDeviceStoreTest.kt` — check if it exists; the store needs a `Context` for prefs, which JVM tests don't have. Test ONLY the JSON mapping by extracting it: move the per-device JSON (de)serialization into two internal functions and test those.

- [ ] **Step 1: Extract + extend.** In `PairedDeviceStore.kt`:

```kotlin
data class PairedDevice(
    val deviceName: String,
    val publicKeyBase64: String,
    val publicKeyFingerprint: String,
    val pairedAt: Long,
    /** SHA-256 hex of the Mac's TLS certificate DER, learned from the pairing QR.
     *  Empty = paired before TLS support → re-pairing required. */
    val certFingerprint: String = ""
)

internal fun PairedDevice.toJson(): JSONObject = JSONObject().apply {
    put("device_name", deviceName)
    put("public_key", publicKeyBase64)
    put("fingerprint", publicKeyFingerprint)
    put("paired_at", pairedAt)
    put("cert_fingerprint", certFingerprint)
}

internal fun pairedDeviceFromJson(obj: JSONObject): PairedDevice = PairedDevice(
    deviceName = obj.getString("device_name"),
    publicKeyBase64 = obj.getString("public_key"),
    publicKeyFingerprint = obj.getString("fingerprint"),
    pairedAt = obj.getLong("paired_at"),
    certFingerprint = obj.optString("cert_fingerprint", "")
)
```

`getAll()`/`save()` use these helpers.

- [ ] **Step 2: Write tests** (`PairedDeviceStoreTest.kt`):

```kotlin
package com.airbridge.security

import org.junit.Assert.assertEquals
import org.junit.Test

class PairedDeviceStoreTest {
    @Test
    fun `round-trips cert fingerprint`() {
        val device = PairedDevice("Mac", "cGs=", "fp", 123L, certFingerprint = "ab12")
        assertEquals(device, pairedDeviceFromJson(device.toJson()))
    }

    @Test
    fun `legacy entry without cert fingerprint defaults to empty`() {
        val legacy = PairedDevice("Mac", "cGs=", "fp", 123L).toJson()
        legacy.remove("cert_fingerprint")
        assertEquals("", pairedDeviceFromJson(legacy).certFingerprint)
    }
}
```

- [ ] **Step 3: Run** `./gradlew testDebugUnitTest --tests com.airbridge.security.PairedDeviceStoreTest` — PASS (org.json is available to unit tests in this project; MessageTest already relies on it).

- [ ] **Step 4: Fix call sites.** `PairedDevice(...)` constructors exist in `MainViewModel.handlePairingPayload` and `AirbridgeService` (PairResponse handler) — they compile unchanged thanks to the default value; they get real fingerprints in Task 8.

- [ ] **Step 5: Commit** — `git commit -m "feat(android): store the Mac TLS certificate fingerprint per paired device"`

---

### Task 7: Android PinnedTls (TrustManager + OkHttp factory)

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/network/PinnedTls.kt`
- Test: `android/Airbridge/app/src/test/java/com/airbridge/network/PinnedTlsTest.kt`

- [ ] **Step 1: Write failing tests.** Deterministic fixtures (pre-generated EC P-256 self-signed certs; fingerprints are SHA-256 over DER):

```kotlin
package com.airbridge.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayInputStream
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate

class PinnedTlsTest {

    private val cert1Pem = """
        -----BEGIN CERTIFICATE-----
        MIIBfDCCASOgAwIBAgIUQcmS7oUNI2lcw6LT2yH/57usCrswCgYIKoZIzj0EAwIw
        FDESMBAGA1UEAwwJQWlyQnJpZGdlMB4XDTI2MDYxMjA3MDIyM1oXDTM2MDYwOTA3
        MDIyM1owFDESMBAGA1UEAwwJQWlyQnJpZGdlMFkwEwYHKoZIzj0CAQYIKoZIzj0D
        AQcDQgAE73bimpGMpysoScU4VeW7284J9yY9Af+EBIo8juY6rpuwPh1bZuzgB72E
        nSwITIFoD6qO5FnCpZDDVJVX+rGDxKNTMFEwHQYDVR0OBBYEFAOvXG/i2bJDlJH9
        rCU6gISFUXWQMB8GA1UdIwQYMBaAFAOvXG/i2bJDlJH9rCU6gISFUXWQMA8GA1Ud
        EwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDRwAwRAIgfEGHuBiRrW9Fdlu7xZJTRQ8D
        vo3FVnEo1K5M2MovfVkCICEoGnoZwz0oKFJS8CZcwe4oVOww7+tdiXuOD2cdDBiY
        -----END CERTIFICATE-----
    """.trimIndent()
    private val cert1Fingerprint =
        "7cd93ad957b9858cbabd681a754452115a797505f27a160c38b8b71222321471"

    private val cert2Pem = """
        -----BEGIN CERTIFICATE-----
        MIIBfjCCASOgAwIBAgIUL1I4fkdey31ShkDY4xnjbtvgKWYwCgYIKoZIzj0EAwIw
        FDESMBAGA1UEAwwJQWlyQnJpZGdlMB4XDTI2MDYxMjA3MDIyM1oXDTM2MDYwOTA3
        MDIyM1owFDESMBAGA1UEAwwJQWlyQnJpZGdlMFkwEwYHKoZIzj0CAQYIKoZIzj0D
        AQcDQgAE8nF35IOvlyHNNy2H2VbWliL8eD8k/rGlmhRhxdN1MOwLxH7UjvAWiHky
        PWi1urOPrgSA7rv/9K3SrcOnQ5Po0qNTMFEwHQYDVR0OBBYEFKHDMSirBpYBWY2r
        GyA2pd1d9SztMB8GA1UdIwQYMBaAFKHDMSirBpYBWY2rGyA2pd1d9SztMA8GA1Ud
        EwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSQAwRgIhAMoPfpGH6XxGUrlmkiF0yW4W
        wSNcZU8TnD65gRlWRpGsAiEA28TqlE5x95I0QziPDkFV2Nbx4xcdRhV0Lyp4Kb6r
        8A8=
        -----END CERTIFICATE-----
    """.trimIndent()

    private fun parse(pem: String): X509Certificate =
        CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(pem.toByteArray())) as X509Certificate

    @Test
    fun `fingerprint matches openssl sha256 over DER`() {
        assertEquals(cert1Fingerprint, PinnedTls.fingerprintOf(parse(cert1Pem)))
    }

    @Test
    fun `pinned cert is accepted`() {
        PinnedTls.trustManager(cert1Fingerprint)
            .checkServerTrusted(arrayOf(parse(cert1Pem)), "ECDHE_ECDSA")
    }

    @Test
    fun `different cert is rejected`() {
        assertThrows(CertificateException::class.java) {
            PinnedTls.trustManager(cert1Fingerprint)
                .checkServerTrusted(arrayOf(parse(cert2Pem)), "ECDHE_ECDSA")
        }
    }

    @Test
    fun `blank pin rejects everything`() {
        assertThrows(CertificateException::class.java) {
            PinnedTls.trustManager("")
                .checkServerTrusted(arrayOf(parse(cert1Pem)), "ECDHE_ECDSA")
        }
    }

    @Test
    fun `empty chain is rejected`() {
        assertThrows(CertificateException::class.java) {
            PinnedTls.trustManager(cert1Fingerprint)
                .checkServerTrusted(emptyArray(), "ECDHE_ECDSA")
        }
    }
}
```

- [ ] **Step 2: Run** — compile failure expected.

- [ ] **Step 3: Implement** `PinnedTls.kt`:

```kotlin
package com.airbridge.network

import okhttp3.OkHttpClient
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

/**
 * Certificate pinning for the Mac's self-signed TLS certificate. The pin is
 * the SHA-256 hex of the certificate DER, learned from the pairing QR code —
 * that physical scan is the trust anchor, not any CA. Hostname verification is
 * disabled (we connect to raw LAN IPs); identity comes solely from the pin.
 */
object PinnedTls {

    fun fingerprintOf(cert: X509Certificate): String =
        MessageDigest.getInstance("SHA-256").digest(cert.encoded)
            .joinToString("") { "%02x".format(it) }

    fun trustManager(pinnedFingerprint: String): X509TrustManager =
        object : X509TrustManager {
            override fun checkServerTrusted(chain: Array<X509Certificate>?, authType: String?) {
                val leaf = chain?.firstOrNull()
                    ?: throw CertificateException("Empty certificate chain")
                if (pinnedFingerprint.isBlank()) {
                    throw CertificateException("No pinned certificate — device not paired over TLS")
                }
                val presented = fingerprintOf(leaf)
                if (!MessageDigest.isEqual(
                        presented.toByteArray(), pinnedFingerprint.lowercase().toByteArray())) {
                    throw CertificateException(
                        "Certificate fingerprint mismatch: expected $pinnedFingerprint, got $presented")
                }
            }

            override fun checkClientTrusted(chain: Array<X509Certificate>?, authType: String?) {
                throw CertificateException("Client certificates are not used")
            }

            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }

    /** Applies pinned TLS to an OkHttp builder; callers keep their own timeouts. */
    fun apply(builder: OkHttpClient.Builder, pinnedFingerprint: String): OkHttpClient.Builder {
        val tm = trustManager(pinnedFingerprint)
        val context = SSLContext.getInstance("TLS")
        context.init(null, arrayOf(tm), SecureRandom())
        return builder
            .sslSocketFactory(context.socketFactory, tm)
            .hostnameVerifier { _, _ -> true }
    }
}
```

- [ ] **Step 4: Run** `./gradlew testDebugUnitTest --tests com.airbridge.network.PinnedTlsTest` — PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(android): pinned TLS trust manager and OkHttp factory"`

---

### Task 8: Android wiring — wss/https everywhere + fingerprint plumbing + re-pair UX

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/service/WebSocketClient.kt`
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/service/HttpFileUploader.kt`, `HttpFileDownloader.kt`
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorClient.kt`, `ReverseMirrorClient.kt`, `ReverseMirrorActivity.kt`
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt`
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/MainViewModel.kt` (PairingPayload→certFingerprint), `android/Airbridge/app/src/main/java/com/airbridge/pairing/QrScannerScreen.kt` (parse new field — find where PairingPayload is parsed; it may live in MainActivity/MainViewModel)
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/discovery/NsdDiscovery.kt` (read `cert_fingerprint` TXT attribute, extend `onServiceFound` signature)

This task is wiring — verified by compilation, existing unit tests, and the final E2E. Sub-steps:

- [ ] **Step 1: WebSocketClient.** `connect(host, port)` → `connect(host: String, port: Int, certFingerprint: String)`. Store `@Volatile private var currentCertFingerprint: String = ""` next to `currentHost`; build the client per connection:

```kotlin
val client = PinnedTls.apply(
    OkHttpClient.Builder().pingInterval(15, TimeUnit.SECONDS),
    certFingerprint
).build()
val request = Request.Builder().url("wss://$host:$port").build()
```

(The long-lived `httpClient` field goes away or becomes the builder template; keep the duplicate-connect guard and reconnect logic intact — `scheduleReconnect` re-uses `currentCertFingerprint`.) Expose `val certFingerprintInUse: String get() = currentCertFingerprint` for the service. `forgetHost()` clears it.

- [ ] **Step 2: HTTP clients.** `HttpFileUploader.upload(...)` and `HttpFileDownloader.download(...)` gain a `certFingerprint: String` parameter; their `OkHttpClient.Builder()` chains get wrapped in `PinnedTls.apply(...)`; URLs `http://` → `https://`. Call sites in `AirbridgeService` pass `webSocketClient.certFingerprintInUse`.

- [ ] **Step 3: Mirror clients.** `MirrorClient` and `ReverseMirrorClient` constructors/connect gain `certFingerprint: String`; `ws://` → `wss://`; OkHttp builders wrapped in `PinnedTls.apply`. `AirbridgeService` passes the fingerprint where it starts the forward mirror; `ReverseMirrorActivity` receives it via a new intent extra `EXTRA_CERT_FINGERPRINT` set by the service when launching the activity.

- [ ] **Step 4: QR pairing path.** Wherever the QR JSON is parsed into `PairingPayload` (grep `pairing_token`), add `certFingerprint = obj.optString("cert_fingerprint", "")`. `MainViewModel.handlePairingPayload`: include `certFingerprint = payload.certFingerprint` in the optimistic `PairedDevice(...)` and in `PendingPairRequest`. `AirbridgeService`: `PendingPairRequest` gains `certFingerprint`; the ACTION_CONNECT/pairing connect call uses it; the PairResponse-accepted `pairedDeviceStore.add(...)` stores it. If the scanned payload has a BLANK `certFingerprint` (old Mac), refuse pairing with a logged error — both sides must be updated together.

- [ ] **Step 5: NSD path + re-pair UX.** `NsdDiscovery`: read `attributes["cert_fingerprint"]` like the existing `pk_fingerprint` and add it to the `onServiceFound` callback signature. In `AirbridgeService.setupNsdDiscovery` handler:

```kotlin
val device = pairedDeviceStore.findByFingerprint(fingerprint) ?: return@handler  // unpaired → ignore (existing behavior)
val pinned = device.certFingerprint
if (pinned.isEmpty()) {
    Log.w(TAG, "Paired Mac has no TLS pin (pre-TLS pairing) — re-pair required")
    return@handler
}
if (nsdCertFingerprint.isNotEmpty() && nsdCertFingerprint != pinned) {
    Log.w(TAG, "Mac TLS certificate changed — re-pair required")
    return@handler
}
webSocketClient.connect(host, port, pinned)
```

(Adapt to the actual handler shape — it currently checks `fingerprint.isEmpty()` and `isPaired`.)

The spec requires a **visible** message, not just a log. Add to `AirbridgeService` companion (next to the existing StateFlows): `val pairingIssue = MutableStateFlow<String?>(null)` — set it to the string resource key context in the two re-pair branches above (new string resources `repair_needed_no_pin` / `repair_needed_cert_changed`, added to `values/strings.xml` AND `values-pl/strings.xml` if present), clear it (null) on successful connect and on successful pairing. In `MainScreen.kt`, below the connection card, render it when non-null using the existing card/typography patterns (simple `Text` in an outlined card with a warning icon is enough — follow the file's existing error/empty-state styling).

- [ ] **Step 6: Build + full unit tests.** `./gradlew assembleDebug testDebugUnitTest`. `WebSocketClientTest` uses MockWebServer over plain `ws://` — MockWebServer can serve TLS but wiring its handshake to the pinned client is brittle; instead update those tests to inject a blank-pin bypass? **No.** Keep the tests honest: MockWebServer supports TLS via `HandshakeCertificates` (okhttp-tls artifact, test-only dependency `testImplementation("com.squareup.okhttp3:okhttp-tls:4.12.0")`): create a `HeldCertificate`, serve it from MockWebServer, pin `PinnedTls.fingerprintOf(heldCertificate.certificate)` in the test. Update the three existing tests accordingly.

- [ ] **Step 7: Commit** — `git commit -m "feat(android): pinned TLS on all connections with re-pair guidance for stale pairings"`

---

### Task 9: Final verification + deploy for E2E

- [ ] **Step 1:** Full builds + suites both platforms: `cd macos/Airbridge && swift build && swift test`; `cd android/Airbridge && ./gradlew assembleDebug testDebugUnitTest`. Everything green except (possibly) the known flaky HELLO_ACK — verify in isolation.
- [ ] **Step 2:** Grep-sanity: no remaining `"ws://`, `"http://` literals in production source of either app (tests with MockWebServer/TLSTestSupport excluded); no `private_key_base64` writes; `cert_fingerprint` present in QR generation, QR parsing, NSD TXT write and read.
- [ ] **Step 3:** Deploy: `scripts/dev-install.sh` (Mac) + `./gradlew installDebug` (phone), launch both.
- [ ] **Step 4:** Report the manual E2E checklist to the user (do not perform it for them): re-pair via QR → clipboard both ways → file transfer both ways → mirror open/close → (optional) `tcpdump -i en0 port 8765` shows TLS records, not JSON.
- [ ] **Step 5:** Commit any stragglers; final commit message `feat: end-to-end TLS between Mac and phone` if a merge-style summary commit is warranted (otherwise nothing — work is already committed per task).
