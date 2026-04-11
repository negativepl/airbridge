import Foundation

@Observable
@MainActor
final class HistoryService {
    private(set) var records: [TransferRecord] = []
    private let storageURL: URL
    private static let maxRecords = 1000

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.records = Self.load(from: self.storageURL)
    }

    func add(type: TransferRecord.TransferType, direction: TransferRecord.Direction, description: String) {
        let record = TransferRecord(type: type, direction: direction, description: description)
        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }
        save()
    }

    func recent(_ count: Int) -> [TransferRecord] {
        Array(records.prefix(count))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private static func load(from url: URL) -> [TransferRecord] {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([TransferRecord].self, from: data) else {
            return []
        }
        return records
    }

    private static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AirBridge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }
}
