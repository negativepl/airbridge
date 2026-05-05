import Foundation

public enum NALUParser {
    /// Split an Annex-B byte stream into individual NALU payloads (without start codes).
    public static func splitAnnexB(_ data: Data) -> [Data] {
        var result: [Data] = []
        var i = data.startIndex
        var lastNALUStart: Int? = nil

        while i < data.endIndex - 2 {
            // 4-byte start code 00 00 00 01
            if i + 3 < data.endIndex
                && data[i] == 0 && data[i+1] == 0 && data[i+2] == 0 && data[i+3] == 1 {
                if let s = lastNALUStart { result.append(data.subdata(in: s..<i)) }
                lastNALUStart = i + 4
                i += 4
                continue
            }
            // 3-byte start code 00 00 01
            if data[i] == 0 && data[i+1] == 0 && data[i+2] == 1 {
                if let s = lastNALUStart { result.append(data.subdata(in: s..<i)) }
                lastNALUStart = i + 3
                i += 3
                continue
            }
            i += 1
        }
        if let s = lastNALUStart, s < data.endIndex {
            result.append(data.subdata(in: s..<data.endIndex))
        }
        return result
    }

    /// H.264 NALU type from the first byte (`nal_unit_type` is bits 0–4).
    public static func naluType(_ nalu: Data) -> UInt8 {
        guard let first = nalu.first else { return 0 }
        return first & 0x1F
    }

    /// Convert a single NALU from Annex-B (no start code) to AVCC by prepending a 4-byte big-endian length.
    public static func toAVCC(_ nalu: Data) -> Data {
        var out = Data(capacity: nalu.count + 4)
        var len = UInt32(nalu.count).bigEndian
        Swift.withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(nalu)
        return out
    }
}
