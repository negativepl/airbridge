import XCTest
import CryptoKit
@testable import AirbridgeApp

final class UpdateManifestTests: XCTestCase {
    let sample = """
    {"version":"2.8.0-beta","versionCode":20800,"publishedAt":"2026-07-09",
     "android":{"url":"https://e/a.apk","sha256":"ab","size":1},
     "macos":{"url":"https://e/a.zip","sha256":"cd","size":2},
     "changelog":{"pl":["Punkt"],"en":["Item"]}}
    """.data(using: .utf8)!

    func testParsesFields() throws {
        let m = try JSONDecoder().decode(UpdateManifest.self, from: sample)
        XCTAssertEqual(m.version, "2.8.0-beta")
        XCTAssertEqual(m.macos.sha256, "cd")
        XCTAssertEqual(m.changelog.pl, ["Punkt"])
    }

    func testVersionCompare() throws {
        let m = try JSONDecoder().decode(UpdateManifest.self, from: sample)
        XCTAssertTrue(m.isNewer(thanInstalled: "2.7.6"))
        XCTAssertTrue(m.isNewer(thanInstalled: "2.7.6-beta"))
        XCTAssertFalse(m.isNewer(thanInstalled: "2.8.0"))
        XCTAssertFalse(m.isNewer(thanInstalled: "2.9.0-beta"))
        XCTAssertFalse(m.isNewer(thanInstalled: "3.0.0"))
    }

    func testSignatureRoundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let sig = try key.signature(for: sample)
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertTrue(UpdateManifest.verifySignature(
            manifestBytes: sample, signatureBase64: sig.base64EncodedString(), publicKeyRawBase64: pub))
        XCTAssertFalse(UpdateManifest.verifySignature(
            manifestBytes: sample + Data([0]), signatureBase64: sig.base64EncodedString(), publicKeyRawBase64: pub))
    }
}
