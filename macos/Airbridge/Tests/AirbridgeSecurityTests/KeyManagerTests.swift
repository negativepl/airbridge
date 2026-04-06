import XCTest
import Foundation
@testable import AirbridgeSecurity

final class KeyManagerTests: XCTestCase {

    // MARK: - testGenerateKeyPair

    func testGenerateKeyPair() throws {
        let manager = KeyManager.ephemeral()

        let identity = try manager.getOrCreateIdentity()

        XCTAssertFalse(identity.deviceId.isEmpty, "deviceId should not be empty")
        XCTAssertFalse(identity.publicKeyBase64.isEmpty, "publicKeyBase64 should not be empty")

        // Second call must return the same identity
        let identityAgain = try manager.getOrCreateIdentity()
        XCTAssertEqual(identity.deviceId, identityAgain.deviceId)
        XCTAssertEqual(identity.publicKeyBase64, identityAgain.publicKeyBase64)
    }

    // MARK: - testSignAndVerify

    func testSignAndVerify() throws {
        let manager = KeyManager.ephemeral()
        let identity = try manager.getOrCreateIdentity()

        let message = "Hello, Airbridge!".data(using: .utf8)!
        let signature = try manager.sign(message)

        let valid = try KeyManager.verify(
            message: message,
            signature: signature,
            publicKeyBase64: identity.publicKeyBase64
        )

        XCTAssertTrue(valid, "Signature should be valid when verified with matching public key")
    }

    // MARK: - testVerifyFailsWithWrongKey

    func testVerifyFailsWithWrongKey() throws {
        let manager1 = KeyManager.ephemeral()
        let manager2 = KeyManager.ephemeral()

        _ = try manager1.getOrCreateIdentity()
        let identity2 = try manager2.getOrCreateIdentity()

        let message = "Hello, Airbridge!".data(using: .utf8)!
        let signature = try manager1.sign(message)

        let valid = try KeyManager.verify(
            message: message,
            signature: signature,
            publicKeyBase64: identity2.publicKeyBase64
        )

        XCTAssertFalse(valid, "Signature should be invalid when verified with wrong public key")
    }

    // MARK: - testStorePairedDevice

    func testStorePairedDevice() throws {
        let manager = KeyManager.ephemeral()

        let device = PairedDevice(
            deviceName: "iPhone 15",
            publicKeyBase64: "dGVzdA==",
            pairedAt: Date()
        )

        manager.addPairedDevice(device)

        let devices = manager.getPairedDevices()
        XCTAssertFalse(devices.isEmpty)
        XCTAssertEqual(devices.first?.deviceName, "iPhone 15")
        XCTAssertEqual(devices.first?.publicKeyBase64, "dGVzdA==")
    }

    // MARK: - testRemovePairedDevice

    func testRemovePairedDevice() throws {
        let manager = KeyManager.ephemeral()

        let device = PairedDevice(
            deviceName: "iPhone 15",
            publicKeyBase64: "dGVzdA==",
            pairedAt: Date()
        )

        manager.addPairedDevice(device)
        XCTAssertFalse(manager.getPairedDevices().isEmpty)

        manager.removePairedDevice(publicKey: "dGVzdA==")
        XCTAssertTrue(manager.getPairedDevices().isEmpty, "Paired devices should be empty after removal")
    }
}
