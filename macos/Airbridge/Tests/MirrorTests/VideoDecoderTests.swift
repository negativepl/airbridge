import Testing
import Foundation
import CoreMedia
@testable import Mirror

@Suite("VideoDecoder")
struct VideoDecoderTests {

    /// Minimal valid SPS + PPS — confirms the wrapper constructs a `CMVideoFormatDescription`
    /// without crashing. Note: the comment in the original fixture described this SPS as "4×4 px"
    /// but VideoToolbox / CMVideoFormatDescription actually parses it as 256×1024 — the H.264
    /// SPS encoding of small resolutions is non-trivial and Apple's parser reports these dims.
    /// The important thing is that the call succeeds and returns a non-nil format description.
    @Test("Constructing format description with valid SPS+PPS succeeds")
    func formatDescriptionConstruction() throws {
        // SPS bytes (H.264 baseline): 67 42 00 0A E9 02 00 80 00 00 03 00 80 00 00 18 47 8C 18 CB
        let sps = Data([0x67, 0x42, 0x00, 0x0A, 0xE9, 0x02, 0x00, 0x80,
                        0x00, 0x00, 0x03, 0x00, 0x80, 0x00, 0x00, 0x18,
                        0x47, 0x8C, 0x18, 0xCB])
        // PPS: 68 CE 3C 80
        let pps = Data([0x68, 0xCE, 0x3C, 0x80])

        let formatDesc = try VideoDecoder.makeFormatDescription(sps: sps, pps: pps)
        let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
        // Apple's SPS parser decodes this fixture as 256×1024 (not 4×4 as originally annotated)
        #expect(dims.width == 256)
        #expect(dims.height == 1024)
    }

    @Test("Construction fails on empty SPS")
    func constructionFailsEmptySPS() {
        #expect(throws: VideoDecoderError.self) {
            _ = try VideoDecoder.makeFormatDescription(sps: Data(), pps: Data([0x68]))
        }
    }
}
