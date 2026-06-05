import Foundation

public enum MirrorStatusCode: UInt8, CaseIterable, Sendable {
    case screenOff = 1
    case appBackgrounded = 2
    case accessibilityDisabled = 3
    case encoderError = 4
    case accessibilityBlocked = 5
}

public enum MirrorMessageError: Error, Equatable, Sendable {
    case empty
    case unknownType(UInt8)
    case truncated(type: UInt8)
}

public enum MirrorMessage: Equatable, Sendable {
    case hello(token: Data, screenWidth: UInt32, screenHeight: UInt32, orientation: UInt8)
    case helloAck(targetBitrateBps: UInt32, fps: UInt8, keyframeIntervalSeconds: UInt8, targetWidth: UInt32, targetHeight: UInt32)
    case videoConfig(sps: Data, pps: Data)
    case videoFrame(presentationTimestampUs: UInt64, naluBytes: Data)
    case inputTap(xNorm: Float32, yNorm: Float32)
    case status(MirrorStatusCode)

    private enum TypeByte {
        static let hello: UInt8 = 0x01
        static let helloAck: UInt8 = 0x02
        static let videoConfig: UInt8 = 0x10
        static let videoFrame: UInt8 = 0x11
        static let inputTap: UInt8 = 0x20
        static let status: UInt8 = 0x30
    }

    public func encode() -> Data {
        var out = Data()
        switch self {
        case let .hello(token, w, h, orientation):
            out.append(TypeByte.hello)
            out.append(token)
            out.appendBE(w)
            out.appendBE(h)
            out.append(orientation)
        case let .helloAck(bitrate, fps, keyframe, w, h):
            out.append(TypeByte.helloAck)
            out.appendBE(bitrate)
            out.append(fps)
            out.append(keyframe)
            out.appendBE(w)
            out.appendBE(h)
        case let .videoConfig(sps, pps):
            out.append(TypeByte.videoConfig)
            out.appendBE(UInt32(sps.count))
            out.append(sps)
            out.appendBE(UInt32(pps.count))
            out.append(pps)
        case let .videoFrame(pts, nalu):
            out.append(TypeByte.videoFrame)
            out.appendBE(pts)
            out.append(nalu)
        case let .inputTap(xNorm, yNorm):
            out.append(TypeByte.inputTap)
            out.appendBE(xNorm.bitPattern)
            out.appendBE(yNorm.bitPattern)
        case let .status(code):
            out.append(TypeByte.status)
            out.append(code.rawValue)
        }
        return out
    }

    public static func decode(_ data: Data) throws -> MirrorMessage {
        guard let first = data.first else { throw MirrorMessageError.empty }
        let payload = data.dropFirst()
        switch first {
        case TypeByte.hello:
            guard payload.count == 16 + 4 + 4 + 1 else { throw MirrorMessageError.truncated(type: first) }
            let token = Data(payload.prefix(16))
            var i = payload.startIndex + 16
            let w: UInt32 = payload.readBE(at: &i)
            let h: UInt32 = payload.readBE(at: &i)
            let orientation = payload[i]
            return .hello(token: token, screenWidth: w, screenHeight: h, orientation: orientation)

        case TypeByte.helloAck:
            guard payload.count == 4 + 1 + 1 + 4 + 4 else { throw MirrorMessageError.truncated(type: first) }
            var i = payload.startIndex
            let bitrate: UInt32 = payload.readBE(at: &i)
            let fps = payload[i]; i += 1
            let keyframe = payload[i]; i += 1
            let w: UInt32 = payload.readBE(at: &i)
            let h: UInt32 = payload.readBE(at: &i)
            return .helloAck(targetBitrateBps: bitrate, fps: fps, keyframeIntervalSeconds: keyframe, targetWidth: w, targetHeight: h)

        case TypeByte.videoConfig:
            guard payload.count >= 8 else { throw MirrorMessageError.truncated(type: first) }
            var i = payload.startIndex
            let spsLen: UInt32 = payload.readBE(at: &i)
            guard payload.count >= 4 + Int(spsLen) + 4 else { throw MirrorMessageError.truncated(type: first) }
            let sps = Data(payload[i..<i + Int(spsLen)]); i += Int(spsLen)
            let ppsLen: UInt32 = payload.readBE(at: &i)
            guard payload.count == 4 + Int(spsLen) + 4 + Int(ppsLen) else { throw MirrorMessageError.truncated(type: first) }
            let pps = Data(payload[i..<i + Int(ppsLen)])
            return .videoConfig(sps: sps, pps: pps)

        case TypeByte.videoFrame:
            guard payload.count >= 8 else { throw MirrorMessageError.truncated(type: first) }
            var i = payload.startIndex
            let pts: UInt64 = payload.readBE(at: &i)
            let nalu = Data(payload[i...])
            return .videoFrame(presentationTimestampUs: pts, naluBytes: nalu)

        case TypeByte.inputTap:
            guard payload.count == 8 else { throw MirrorMessageError.truncated(type: first) }
            var i = payload.startIndex
            let xBits: UInt32 = payload.readBE(at: &i)
            let yBits: UInt32 = payload.readBE(at: &i)
            return .inputTap(xNorm: Float32(bitPattern: xBits), yNorm: Float32(bitPattern: yBits))

        case TypeByte.status:
            guard payload.count == 1, let code = MirrorStatusCode(rawValue: payload[payload.startIndex]) else {
                throw MirrorMessageError.truncated(type: first)
            }
            return .status(code)

        default:
            throw MirrorMessageError.unknownType(first)
        }
    }
}

// MARK: - Big-endian helpers

private extension Data {
    mutating func appendBE(_ value: UInt32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
    mutating func appendBE(_ value: UInt64) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
    func readBE(at i: inout Int) -> UInt32 {
        let v = self[i..<i+4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
        i += 4
        return v
    }
    func readBE(at i: inout Int) -> UInt64 {
        let v = self[i..<i+8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.bigEndian
        i += 8
        return v
    }
}
