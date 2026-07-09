import Foundation
import CryptoKit

/// The update manifest published by release.sh. The detached signature covers
/// the RAW manifest bytes — verify before decoding.
struct UpdateManifest: Decodable {
    struct Asset: Decodable { let url: String; let sha256: String; let size: Int64 }
    struct Changelog: Decodable { let pl: [String]; let en: [String] }

    let version: String
    let versionCode: Int
    let publishedAt: String
    let macos: Asset
    let changelog: Changelog

    /// Compares numeric version bases ("2.8.0-beta" → [2,8,0]); pre-release
    /// suffixes are ignored — every release ships to everyone.
    func isNewer(thanInstalled installed: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: "-").first.map {
                $0.split(separator: ".").compactMap { Int($0) }
            } ?? []
        }
        let a = parts(version), b = parts(installed)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func verifySignature(
        manifestBytes: Data, signatureBase64: String, publicKeyRawBase64: String
    ) -> Bool {
        guard let sig = Data(base64Encoded: signatureBase64),
              let raw = Data(base64Encoded: publicKeyRawBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else { return false }
        return key.isValidSignature(sig, for: manifestBytes)
    }
}
