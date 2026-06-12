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
