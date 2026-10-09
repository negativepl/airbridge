import Foundation

/// Lekki diagnostyczny logger pisany do PLIKU
/// `~/Library/Application Support/AirBridge/diagnostics.log`.
///
/// Po co, skoro jest `os.Logger`: na tym Macu unified logging nie utrwala na
/// dysk wpisów poziomu default/info tego subsystemu (widać je tylko na żywo w
/// `log stream`). Diagnostyka reconnectu i sesji mirrora musi przeżyć realne
/// użycie, żeby dało się ją odczytać po fakcie — stąd prosty append do pliku.
///
/// Plik jest przycinany: gdy przekroczy `maxBytes`, zostaje jego końcówka
/// o rozmiarze `keepBytes`, więc log nigdy nie rośnie bez końca.
enum Diag {
    private static let lock = NSLock()
    // Dostęp wyłącznie pod `lock` (patrz `log`), więc współdzielenie jest bezpieczne.
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AirBridge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.log")
    }()

    private static let maxBytes: UInt64 = 2 * 1024 * 1024
    private static let keepBytes: UInt64 = 1 * 1024 * 1024
    /// Writes between size checks; the size check is a stat, cheap but not free.
    private static let checkEvery = 200
    nonisolated(unsafe) private static var writesSinceCheck = 0

    static func log(_ category: String, _ message: String) {
        lock.lock(); defer { lock.unlock() }
        let line = "\(formatter.string(from: Date())) [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: fileURL)
        }
        writesSinceCheck += 1
        if writesSinceCheck >= checkEvery {
            writesSinceCheck = 0
            trimIfNeeded()
        }
    }

    /// Keeps the file under `maxBytes` by dropping its oldest part, cut at a
    /// line boundary so the surviving head is a whole entry.
    private static func trimIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64, size > maxBytes,
              let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: size - keepBytes)
        guard var tail = try? handle.readToEnd() else { return }
        if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) {
            tail = tail[tail.index(after: newline)...]
        }
        try? tail.write(to: fileURL, options: .atomic)
    }
}
