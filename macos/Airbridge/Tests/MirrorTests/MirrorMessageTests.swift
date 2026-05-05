import Testing
import Foundation
@testable import Mirror

@Suite("MirrorMessage binary codec")
struct MirrorMessageTests {

    @Test("HELLO round-trip")
    func helloRoundtrip() throws {
        let token = Data(repeating: 0xAB, count: 16)
        let msg = MirrorMessage.hello(token: token, screenWidth: 1080, screenHeight: 2376, orientation: 0)
        let bytes = msg.encode()
        // Type byte 0x01 + 16 token + 4 width + 4 height + 1 orientation = 26 bytes
        #expect(bytes.count == 26)
        #expect(bytes[0] == 0x01)
        let decoded = try MirrorMessage.decode(bytes)
        #expect(decoded == msg)
    }

    @Test("HELLO_ACK round-trip")
    func helloAckRoundtrip() throws {
        let msg = MirrorMessage.helloAck(targetBitrateBps: 12_000_000, fps: 60, keyframeIntervalSeconds: 2, targetWidth: 1080, targetHeight: 1920)
        let decoded = try MirrorMessage.decode(msg.encode())
        #expect(decoded == msg)
    }

    @Test("VIDEO_CONFIG round-trip")
    func videoConfigRoundtrip() throws {
        let sps = Data([0x67, 0x42, 0x00, 0x1F])
        let pps = Data([0x68, 0xCE, 0x3C, 0x80])
        let msg = MirrorMessage.videoConfig(sps: sps, pps: pps)
        let decoded = try MirrorMessage.decode(msg.encode())
        #expect(decoded == msg)
    }

    @Test("VIDEO_FRAME round-trip")
    func videoFrameRoundtrip() throws {
        let nalu = Data((0..<2048).map { UInt8($0 & 0xFF) })
        let msg = MirrorMessage.videoFrame(presentationTimestampUs: 1_234_567_890, naluBytes: nalu)
        let decoded = try MirrorMessage.decode(msg.encode())
        #expect(decoded == msg)
    }

    @Test("STATUS round-trip")
    func statusRoundtrip() throws {
        for code in MirrorStatusCode.allCases {
            let msg = MirrorMessage.status(code)
            let decoded = try MirrorMessage.decode(msg.encode())
            #expect(decoded == msg)
        }
    }

    @Test("Decode rejects empty payload")
    func decodeRejectsEmpty() {
        #expect(throws: MirrorMessageError.self) { try MirrorMessage.decode(Data()) }
    }

    @Test("Decode rejects unknown type byte")
    func decodeRejectsUnknownType() {
        let bogus = Data([0xFE, 0x00, 0x00, 0x00])
        #expect(throws: MirrorMessageError.self) { try MirrorMessage.decode(bogus) }
    }

    @Test("HELLO truncated payload rejected")
    func helloTruncated() {
        let bytes = Data([0x01, 0x01, 0x02, 0x03])
        #expect(throws: MirrorMessageError.self) { try MirrorMessage.decode(bytes) }
    }
}
