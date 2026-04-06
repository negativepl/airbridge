import Foundation
import AppKit
import CoreImage
import Protocol

// MARK: - QRCodeGeneratorError

public enum QRCodeGeneratorError: Error, Sendable {
    case encodingFailed
    case filterOutputUnavailable
    case imageCreationFailed
}

// MARK: - QRCodeGenerator

/// Converts a `PairingPayload` into a QR-code `NSImage`.
public enum QRCodeGenerator {

    /// Generates a square QR-code image from `payload`.
    ///
    /// - Parameters:
    ///   - payload: The pairing payload to encode.
    ///   - size: The desired edge length in points (default 256).
    /// - Returns: An `NSImage` containing the rendered QR code.
    /// - Throws: `QRCodeGeneratorError` if any step fails.
    public static func generate(
        from payload: PairingPayload,
        size: CGFloat = 256
    ) throws -> NSImage {
        // 1. Encode the payload to compact JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(payload) else {
            throw QRCodeGeneratorError.encodingFailed
        }

        // 2. Build the CIQRCodeGenerator filter
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw QRCodeGeneratorError.filterOutputUnavailable
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else {
            throw QRCodeGeneratorError.filterOutputUnavailable
        }

        // 3. Scale up from the tiny native filter output to the requested size
        let nativeSize = ciImage.extent.size
        let scaleX = size / nativeSize.width
        let scaleY = size / nativeSize.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // 4. Convert CIImage → CGImage → NSImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw QRCodeGeneratorError.imageCreationFailed
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
