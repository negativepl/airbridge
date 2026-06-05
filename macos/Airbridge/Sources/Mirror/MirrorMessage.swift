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
    /// codec: 0 = H.264, 1 = HEVC. Tells the (encoding) phone which codec to use.
    case helloAck(targetBitrateBps: UInt32, fps: UInt8, keyframeIntervalSeconds: UInt8, targetWidth: UInt32, targetHeight: UInt32, codec: UInt8)
    case videoConfig(sps: Data, pps: Data)
    /// HEVC parameter sets (VPS, SPS, PPS). Self-describes the stream as HEVC.
    case videoConfigHEVC(vps: Data, sps: Data, pps: Data)
    case videoFrame(presentationTimestampUs: UInt64, naluBytes: Data)
    case inputTap(xNorm: Float32, yNorm: Float32)
    case status(MirrorStatusCode)
    /// Reverse mirror: phone -> Mac, "start sending me YOUR screen". Carries the
    /// phone's screen size and the mode (0 = mirror Mac's main display,
    /// 1 = create a virtual display shaped to the phone). The Mac then sends
    /// videoConfig/videoFrame down this connection (Mac -> phone).
    case reverseHello(token: Data, screenWidth: UInt32, screenHeight: UInt32, mode: UInt8)
    /// Reverse control: phone -> Mac pointer input on the captured display.
    /// type: 0 = move, 1 = down, 2 = up, 3 = drag. Coords normalized 0..1.
    case reverseInput(type: UInt8, xNorm: Float32, yNorm: Float32)
    /// Reverse control: phone -> Mac scroll wheel (points).
    case reverseScroll(deltaX: Float32, deltaY: Float32)

    private enum TypeByte {
        static let hello: UInt8 = 0x01
        static let helloAck: UInt8 = 0x02
        static let videoConfig: UInt8 = 0x10
        static let videoFrame: UInt8 = 0x11
        static let videoConfigHEVC: UInt8 = 0x12
        static let inputTap: UInt8 = 0x20
        static let status: UInt8 = 0x30
        static let reverseHello: UInt8 = 0x40
        static let reverseInput: UInt8 = 0x41
        static let reverseScroll: UInt8 = 0x42
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
        case let .helloAck(bitrate, fps, keyframe, w, h, codec):
            out.append(TypeByte.helloAck)
            out.appendBE(bitrate)
            out.append(fps)
            out.append(keyframe)
            out.appendBE(w)
            out.appendBE(h)
            out.append(codec)
        case let .videoConfig(sps, pps):
            out.append(TypeByte.videoConfig)
            out.appendBE(UInt32(sps.count))
            out.append(sps)
            out.appendBE(UInt32(pps.count))
            out.append(pps)
        case let .videoConfigHEVC(vps, sps, pps):
            out.append(TypeByte.videoConfigHEVC)
            out.appendBE(UInt32(vps.count))
            out.append(vps)
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
        case let .reverseHello(token, w, h, mode):
            out.append(TypeByte.reverseHello)
            out.append(token)
            out.appendBE(w)
            out.appendBE(h)
            out.append(mode)
        case let .reverseInput(type, x, y):
            out.append(TypeByte.reverseInput)
            out.append(type)
            out.appendBE(x.bitPattern)
            out.appendBE(y.bitPattern)
        case let .reverseScroll(dx, dy):
            out.append(TypeByte.reverseScroll)
            out.appendBE(dx.bitPattern)
            out.appendBE(dy.bitPattern)
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
            guard payload.count >= 4 + 1 + 1 + 4 + 4 else { throw MirrorMessageError.truncated(type: first) }
            var i = payload.startIndex
            let bitrate: UInt32 = payload.readBE(at: &i)
            let fps = payload[i]; i += 1
            let keyframe = payload[i]; i += 1
            let w: UInt32 = payload.readBE(at: &i)
            let h: UInt32 = payload.readBE(at: &i)
            let codec: UInt8 = i < payload.endIndex ? payload[i] : 0   // back-compat: absent = H.264
            return .helloAck(targetBitrateBps: bitrate, fps: fps, keyframeIntervalSeconds: keyframe, targetWidth: w, targetHeight: h, codec: codec)

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

        case TypeByte.videoConfigHEVC:
            guard payload.count >= 12 else { throw MirrorMessageError.truncated(type: first) }
            var i = payload.startIndex
            let vpsLen: UInt32 = payload.readBE(at: &i)
            guard payload.count >= 4 + Int(vpsLen) + 8 else { throw MirrorMessageError.truncated(type: first) }
            let vps = Data(payload[i..<i + Int(vpsLen)]); i += Int(vpsLen)
            let spsLen: UInt32 = payload.readBE(at: &i)
            guard payload.count >= 4 + Int(vpsLen) + 4 + Int(spsLen) + 4 else { throw MirrorMessageError.truncated(type: first) }
            let sps = Data(payload[i..<i + Int(spsLen)]); i += Int(spsLen)
            let ppsLen: UInt32 = payload.readBE(at: &i)
            guard payload.count == 4 + Int(vpsLen) + 4 + Int(spsLen) + 4 + Int(ppsLen) else { throw MirrorMessageError.truncated(type: first) }
            let pps = Data(payload[i..<i + Int(ppsLen)])
            return .videoConfigHEVC(vps: vps, sps: sps, pps: pps)

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

        case TypeByte.reverseHello:
            guard payload.count == 16 + 4 + 4 + 1 else { throw MirrorMessageError.truncated(type: first) }
            let token = Data(payload.prefix(16))
            var i = payload.startIndex + 16
            let w: UInt32 = payload.readBE(at: &i)
            let h: UInt32 = payload.readBE(at: &i)
            let mode = payload[i]
            return .reverseHello(token: token, screenWidth: w, screenHeight: h, mode: mode)

        case TypeByte.reverseInput:
            guard payload.count == 1 + 4 + 4 else { throw MirrorMessageError.truncated(type: first) }
            var i = payload.startIndex
            let type = payload[i]; i += 1
            let xBits: UInt32 = payload.readBE(at: &i)
            let yBits: UInt32 = payload.readBE(at: &i)
            return .reverseInput(type: type, xNorm: Float32(bitPattern: xBits), yNorm: Float32(bitPattern: yBits))

        case TypeByte.reverseScroll:
            guard payload.count == 4 + 4 else { throw MirrorMessageError.truncated(type: first) }
            var i = payload.startIndex
            let dxBits: UInt32 = payload.readBE(at: &i)
            let dyBits: UInt32 = payload.readBE(at: &i)
            return .reverseScroll(deltaX: Float32(bitPattern: dxBits), deltaY: Float32(bitPattern: dyBits))

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
