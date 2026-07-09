import Foundation
import AppKit
import CryptoKit
import Observation

/// Fully user-initiated updater: nothing here runs except from an explicit
/// button tap (transparency rule — no timers, no startup checks).
@Observable @MainActor
final class UpdateService {
    enum Phase: Equatable {
        case idle, checking, upToDate, available(UpdateManifest), downloading(Double), installing
        case failed(String)
        static func == (l: Phase, r: Phase) -> Bool {
            switch (l, r) {
            case (.idle, .idle), (.checking, .checking), (.upToDate, .upToDate), (.installing, .installing):
                return true
            case let (.available(a), .available(b)): return a.version == b.version
            case let (.downloading(a), .downloading(b)): return a == b
            case let (.failed(a), .failed(b)): return a == b
            default: return false
            }
        }
    }

    static let manifestURL = URL(string: "https://updates.vintrhall.com/airbridge/manifest.json")!
    static let publicKeyB64 = "842aa+wK7BUs8CVyg/d2cgyKYC6IGQ2kiYgeyR9YxTo="

    private(set) var phase: Phase = .idle

    func checkForUpdates() async {
        phase = .checking
        do {
            let (manifestData, _) = try await URLSession.shared.data(from: Self.manifestURL)
            let sigURL = URL(string: Self.manifestURL.absoluteString + ".sig")!
            let (sigData, _) = try await URLSession.shared.data(from: sigURL)
            let sigB64 = String(decoding: sigData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard UpdateManifest.verifySignature(
                manifestBytes: manifestData, signatureBase64: sigB64,
                publicKeyRawBase64: Self.publicKeyB64) else {
                phase = .failed(L10n.isPL ? "Nieprawidłowy podpis manifestu" : "Invalid manifest signature")
                return
            }
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: manifestData)
            let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            phase = manifest.isNewer(thanInstalled: installed) ? .available(manifest) : .upToDate
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func downloadAndInstall() async {
        guard case .available(let manifest) = phase,
              let url = URL(string: manifest.macos.url) else { return }
        phase = .downloading(0)
        do {
            let zipURL = try await download(url, expectedSha256: manifest.macos.sha256, expectedSize: manifest.macos.size)
            phase = .installing
            try install(fromZip: zipURL)   // hands off to helper + terminates app
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Streams the update archive to a temp file while reporting progress,
    /// then verifies its SHA256 against the manifest before returning.
    private func download(_ url: URL, expectedSha256: String, expectedSize: Int64) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(for: URLRequest(url: url))
        let totalBytes = response.expectedContentLength > 0 ? response.expectedContentLength : expectedSize

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("airbridge-update-\(UUID().uuidString).zip")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: tempURL.path) else {
            throw UpdateError.cannotCreateTempFile
        }

        var hasher = SHA256()
        var received: Int64 = 0
        var buffer = [UInt8]()
        buffer.reserveCapacity(1 << 16) // 64 KiB chunks

        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 16 {
                    let chunk = Data(buffer)
                    handle.write(chunk)
                    hasher.update(data: chunk)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if totalBytes > 0 {
                        phase = .downloading(min(1, Double(received) / Double(totalBytes)))
                    }
                }
            }
            if !buffer.isEmpty {
                let chunk = Data(buffer)
                handle.write(chunk)
                hasher.update(data: chunk)
                received += Int64(buffer.count)
                if totalBytes > 0 {
                    phase = .downloading(min(1, Double(received) / Double(totalBytes)))
                }
            }
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        let digest = hasher.finalize()
        let computedHex = digest.map { String(format: "%02x", $0) }.joined()
        guard computedHex.caseInsensitiveCompare(expectedSha256) == .orderedSame else {
            try? FileManager.default.removeItem(at: tempURL)
            throw UpdateError.checksumMismatch(expected: expectedSha256, actual: computedHex)
        }
        return tempURL
    }

    /// `install(fromZip:)` — the running app cannot replace its own bundle
    /// safely, so write a small script to `/tmp` and run it detached
    /// (Sparkle pattern). `xattr -dr com.apple.quarantine` runs BEFORE the
    /// swap — the zip download carries quarantine and Gatekeeper would block
    /// the self-signed app. The new bundle is signed with the same
    /// "AirBridge Signing" cert (release.sh signs it), so TCC grants survive
    /// — the same property `dev-install.sh` relies on.
    private func install(fromZip zipURL: URL) throws {
        let script = """
        #!/bin/bash
        set -e
        exec >> "$HOME/Library/Logs/AirBridge-update.log" 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] update: begin"
        sleep 1                              # let the app finish quitting
        STAGE="$(mktemp -d)"
        /usr/bin/ditto -x -k "\(zipURL.path)" "$STAGE"
        /usr/bin/xattr -dr com.apple.quarantine "$STAGE/AirBridge.app" || true
        [ -d "$STAGE/AirBridge.app" ] || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] update: extracted payload missing, aborting"; exit 1; }
        mv "/Applications/AirBridge.app" "$STAGE/previous" 2>/dev/null || true
        if ! /usr/bin/ditto "$STAGE/AirBridge.app" "/Applications/AirBridge.app"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] update: install failed, rolling back"
            # Restore only when the aside-move actually produced a backup — if it
            # silently failed, the original is still in /Applications and deleting
            # it here would remove the only good copy.
            if [ -d "$STAGE/previous" ]; then
                rm -rf "/Applications/AirBridge.app"
                mv "$STAGE/previous" "/Applications/AirBridge.app"
            fi
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] update: end (rollback)"
            exit 1
        fi
        rm -rf "$STAGE" "\(zipURL.path)"
        /usr/bin/open "/Applications/AirBridge.app"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] update: end (success)"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("airbridge-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scriptURL.path]
        try p.run()                           // detached: not waited on
        NSApplication.shared.terminate(nil)
    }

    enum UpdateError: LocalizedError {
        case cannotCreateTempFile
        case checksumMismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateTempFile:
                return L10n.isPL
                    ? "Nie można utworzyć pliku tymczasowego dla aktualizacji"
                    : "Could not create a temporary file for the update"
            case .checksumMismatch(let expected, let actual):
                return L10n.isPL
                    ? "Suma kontrolna pobranego pliku nie zgadza się (oczekiwano \(expected), otrzymano \(actual))"
                    : "Downloaded file checksum mismatch (expected \(expected), got \(actual))"
            }
        }
    }
}
