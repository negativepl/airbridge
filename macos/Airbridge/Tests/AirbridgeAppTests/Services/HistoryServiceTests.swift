import XCTest
@testable import AirbridgeApp

@MainActor
final class HistoryServiceTests: XCTestCase {
    private func makeService() -> HistoryService {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("airbridge-test-\(UUID().uuidString)")
            .appendingPathExtension("json")
        return HistoryService(storageURL: tempURL)
    }

    func testInitiallyEmpty() {
        let service = makeService()
        XCTAssertTrue(service.records.isEmpty)
    }

    func testAddRecord() {
        let service = makeService()
        service.add(type: .clipboard, direction: .sent, description: "Hello")
        XCTAssertEqual(service.records.count, 1)
        XCTAssertEqual(service.records.first?.description, "Hello")
        XCTAssertEqual(service.records.first?.type, .clipboard)
        XCTAssertEqual(service.records.first?.direction, .sent)
    }

    func testRecentReturnsLatestFirst() {
        let service = makeService()
        service.add(type: .clipboard, direction: .sent, description: "First")
        service.add(type: .file, direction: .received, description: "Second")
        service.add(type: .clipboard, direction: .sent, description: "Third")
        let recent = service.recent(2)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].description, "Third")
        XCTAssertEqual(recent[1].description, "Second")
    }

    func testPersistenceRoundTrip() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("airbridge-test-\(UUID().uuidString)")
            .appendingPathExtension("json")
        let service1 = HistoryService(storageURL: tempURL)
        service1.add(type: .file, direction: .received, description: "photo.jpg")
        let service2 = HistoryService(storageURL: tempURL)
        XCTAssertEqual(service2.records.count, 1)
        XCTAssertEqual(service2.records.first?.description, "photo.jpg")
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testMaxRecordsLimit() {
        let service = makeService()
        for i in 0..<1100 {
            service.add(type: .clipboard, direction: .sent, description: "Item \(i)")
        }
        XCTAssertEqual(service.records.count, 1000)
        XCTAssertEqual(service.records.first?.description, "Item 1099")
    }
}
