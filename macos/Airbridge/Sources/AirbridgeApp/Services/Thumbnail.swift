import AppKit
import ImageIO

/// One picture's thumbnail, observed on its own: with every thumbnail in one
/// observed dictionary, each arrival redrew every tile or row on screen.
@Observable
@MainActor
final class Thumbnail {
    var image: NSImage?
}

/// Thumbnails by key. Boxes live as long as their owner; a reset empties them
/// in place, so a view still holding one sees the next image.
@MainActor
final class ThumbnailBoxes {
    private var boxes: [String: Thumbnail] = [:]

    func box(for key: String) -> Thumbnail {
        if let existing = boxes[key] { return existing }
        let created = Thumbnail()
        boxes[key] = created
        return created
    }

    func set(_ image: CGImage, for key: String) {
        box(for: key).image = NSImage(cgImage: image, size: .zero)
    }

    func clear(_ key: String) { boxes[key]?.image = nil }

    func clearAll() {
        for box in boxes.values { box.image = nil }
    }

    /// Decoded off the main thread and up front (the bitmap is cached
    /// immediately), with the EXIF orientation applied as NSImage(data:)
    /// would; decoding lazily on first draw stalled scrolling and clicks.
    nonisolated static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
