import Foundation

/// Lekki diagnostyczny logger pisany do PLIKU
/// `~/Library/Application Support/AirBridge/diagnostics.log`.
///
/// Po co, skoro jest `os.Logger`: na tym Macu unified logging nie utrwala na
/// dysk wpisów poziomu default/info tego subsystemu (widać je tylko na żywo w
/// `log stream`). Diagnostyka reconnectu musi przeżyć realny dojazd dom↔praca,
/// żeby dało się ją odczytać po fakcie — stąd prosty append do pliku.
///
/// TYMCZASOWE: po zdiagnozowaniu problemu z przełączaniem sieci do usunięcia.
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
    }
}
