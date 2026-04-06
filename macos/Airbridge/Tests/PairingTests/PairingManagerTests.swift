import XCTest
import AppKit
@testable import Pairing
import Protocol
import AirbridgeSecurity

final class PairingManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makePairingManager() -> PairingManager {
        let km = KeyManager.ephemeral()
        return PairingManager(keyManager: km)
    }

    // MARK: - Tests

    func testGeneratesPairingPayload() throws {
        let manager = makePairingManager()
        let payload = try manager.generatePairingPayload(host: "192.168.1.10", port: 8765)

        XCTAssertEqual(payload.host, "192.168.1.10")
        XCTAssertEqual(payload.port, 8765)
        XCTAssertEqual(payload.protocolVersion, 1)
        XCTAssertFalse(payload.publicKey.isEmpty, "publicKey should be non-empty")
        XCTAssertFalse(payload.pairingToken.isEmpty, "pairingToken should be non-empty")
    }

    func testPairingPayloadSerializesToJSON() throws {
        let manager = makePairingManager()
        let payload = try manager.generatePairingPayload(host: "10.0.0.1", port: 9000)

        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["host"] as? String, "10.0.0.1")
        XCTAssertEqual(json["port"] as? Int, 9000)
        XCTAssertEqual(json["protocol_version"] as? Int, 1)
        XCTAssertNotNil(json["public_key"], "JSON should contain public_key")
        XCTAssertNotNil(json["pairing_token"], "JSON should contain pairing_token")
    }

    func testGeneratesQRImage() throws {
        let manager = makePairingManager()
        let payload = try manager.generatePairingPayload(host: "localhost", port: 12345)

        let image = try QRCodeGenerator.generate(from: payload)

        XCTAssertFalse(image.size == .zero, "QR image size should be non-zero")
    }

    func testValidatesPairingToken() throws {
        let manager = makePairingManager()
        let payload = try manager.generatePairingPayload(host: "localhost", port: 8080)

        let token = payload.pairingToken

        // Wrong token should fail
        XCTAssertFalse(manager.validateToken("wrong-token"), "Wrong token must not validate")

        // Correct token validates true
        XCTAssertTrue(manager.validateToken(token), "Correct token must validate")

        // One-time use: second call with same token should fail
        XCTAssertFalse(manager.validateToken(token), "Token must be invalidated after first use")
    }
}
