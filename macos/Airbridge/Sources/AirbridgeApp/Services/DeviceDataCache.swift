import Foundation
import AppKit
import CryptoKit

/// On-disk cache of what the phone last told us — gallery listing and thumbs,
/// SMS conversations and threads, file listings, folder stats and thumbs —
/// keyed by the phone's public key, so each paired device keeps its own.
///
/// The services show the cached data the moment a tab opens (or the app
/// launches, or the connection comes back after a network change) and refresh
/// it from the phone in the background; the user never waits for a listing
/// they have already seen. JSON for listings, JPEG/PNG bytes for images,
/// written on a background queue.
final class DeviceDataCache: @unchecked Sendable {
    static let shared = DeviceDataCache()

    private let root: URL
    private let io = DispatchQueue(label: "com.airbridge.devicecache", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        root = support.appendingPathComponent("AirBridge/cache", isDirectory: true)
    }

    // MARK: - Listings

    func save<T: Encodable & Sendable>(_ value: T, device: String, name: String) {
        let url = fileURL(device: device, name: name + ".json")
        let encoder = self.encoder
        io.async {
            guard let data = try? encoder.encode(value) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    func load<T: Decodable>(_ type: T.Type, device: String, name: String) -> T? {
        let url = fileURL(device: device, name: name + ".json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    // MARK: - Images

    func saveImage(_ data: Data, device: String, folder: String, key: String) {
        let url = imageURL(device: device, folder: folder, key: key)
        io.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadImage(device: String, folder: String, key: String) -> NSImage? {
        let url = imageURL(device: device, folder: folder, key: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Paths

    private func fileURL(device: String, name: String) -> URL {
        root.appendingPathComponent(Self.hash(device), isDirectory: true).appendingPathComponent(name)
    }

    private func imageURL(device: String, folder: String, key: String) -> URL {
        root.appendingPathComponent(Self.hash(device), isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(Self.hash(key) + ".img")
    }

    /// Short stable file-system-safe name for a key (public key, path, id).
    static func hash(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
