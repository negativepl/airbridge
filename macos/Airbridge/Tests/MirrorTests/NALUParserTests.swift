import Testing
import Foundation
@testable import Mirror

@Suite("NALUParser")
struct NALUParserTests {

    /// Annex-B start code: 00 00 00 01
    private let startCode = Data([0x00, 0x00, 0x00, 0x01])

    @Test("Splits two NALUs separated by 4-byte start code")
    func splitsTwoNALUs() {
        let nalu1 = Data([0x67, 0x42, 0x00, 0x1F]) // SPS
        let nalu2 = Data([0x68, 0xCE, 0x3C, 0x80]) // PPS
        let stream = startCode + nalu1 + startCode + nalu2
        let parsed = NALUParser.splitAnnexB(stream)
        #expect(parsed.count == 2)
        #expect(parsed[0] == nalu1)
        #expect(parsed[1] == nalu2)
    }

    @Test("Recognises 3-byte start code")
    func recognises3ByteStart() {
        let nalu = Data([0x65, 0x88, 0x82, 0x00])
        let stream = Data([0x00, 0x00, 0x01]) + nalu
        let parsed = NALUParser.splitAnnexB(stream)
        #expect(parsed == [nalu])
    }

    @Test("NALU type extraction: SPS=7, PPS=8, IDR=5")
    func naluTypeExtraction() {
        #expect(NALUParser.naluType(Data([0x67])) == 7)
        #expect(NALUParser.naluType(Data([0x68])) == 8)
        #expect(NALUParser.naluType(Data([0x65])) == 5)
    }

    @Test("Annex-B → AVCC adds 4-byte length prefix")
    func annexBToAVCC() {
        let nalu = Data([0x65, 0x88, 0x82, 0x00])
        let avcc = NALUParser.toAVCC(nalu)
        // 4-byte BE length + nalu = 4 + 4 = 8
        #expect(avcc.count == 8)
        #expect(avcc.prefix(4) == Data([0x00, 0x00, 0x00, 0x04]))
        #expect(avcc.suffix(4) == nalu)
    }
}
