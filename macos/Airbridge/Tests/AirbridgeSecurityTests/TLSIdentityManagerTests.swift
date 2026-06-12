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
