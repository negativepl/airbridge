# Screen Mirror MVP — Plan A: View-only

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stream the Android phone's screen live to a window on the Mac. View-only — no remote control yet (that's Plan B). User sees their phone's display in real time on Mac with <150 ms latency, 1080p60.

**Architecture:** Reuse the existing `WebSocketServer` actor (Mac, on `Network` framework with `NWProtocolWebSocket`) on a second port (8766) for mirror traffic — bandwidth isolation from clipboard/file-transfer traffic on 8765. Phone uses OkHttp WebSocket client. Wire protocol is binary frames: `[1 B type][N B payload]`. Phone captures via `MediaProjection` → `MediaCodec` H.264 with `KEY_LOW_LATENCY`. Mac decodes via `VTDecompressionSession` (RealTime mode) and renders into `AVSampleBufferDisplayLayer` with immediate display.

**Tech Stack:** Swift 6, SwiftUI, `Network` framework, VideoToolbox, AVFoundation. Kotlin, OkHttp 4.12, MediaProjection/MediaCodec, Android Foreground Services. Spec: `docs/superpowers/specs/2026-05-05-screen-mirror-mvp-design.md`.

**Out of scope (Plan B):** `RECONFIGURE` message, `INPUT_*` messages, `MirrorAccessibilityService`, mouse/keyboard input handling on Mac, quality picker, reconnect overlay, accessibility-onboarding flow.

---

## File Structure

### Mac — new files

| Path | Responsibility |
|---|---|
| `macos/Airbridge/Sources/Mirror/MirrorMessage.swift` | `MirrorMessage` enum (cases for view-only set) + binary encode/decode helpers. Pure value types, no I/O. |
| `macos/Airbridge/Sources/Mirror/NALUParser.swift` | Parses Annex-B byte stream from MediaCodec into individual NALU `Data` slices. Detects SPS/PPS/IDR. Converts Annex-B start codes to AVCC length prefixes for `VTDecompressionSession`. |
| `macos/Airbridge/Sources/Mirror/VideoDecoder.swift` | Owns `VTDecompressionSession`. Constructs `CMVideoFormatDescription` from SPS+PPS, decodes incoming AVCC frames into `CMSampleBuffer`s, hands them to a callback. |
| `macos/Airbridge/Sources/Mirror/MirrorRendererView.swift` | `NSViewRepresentable` wrapping `AVSampleBufferDisplayLayer` with immediate-display configuration. Accepts a stream of `CMSampleBuffer`s. |
| `macos/Airbridge/Sources/AirbridgeApp/Services/MirrorService.swift` | Orchestrator: starts second `WebSocketServer` on 8766, validates handshake, wires the binary frame stream into `VideoDecoder`, exposes the latest sample-buffer stream to the SwiftUI window. |
| `macos/Airbridge/Sources/AirbridgeApp/Views/MirrorWindow.swift` | SwiftUI `Window` scene with id `"mirror"`. Hosts `MirrorRendererView`. Has Stop button. |
| `macos/Airbridge/Tests/MirrorTests/MirrorMessageTests.swift` | Binary codec round-trip tests. |
| `macos/Airbridge/Tests/MirrorTests/NALUParserTests.swift` | Annex-B parse + AVCC conversion + SPS/PPS detection tests. |
| `macos/Airbridge/Tests/MirrorTests/VideoDecoderTests.swift` | Smoke test: synthesized SPS/PPS + IDR → decoder produces a `CMSampleBuffer`. |
| `macos/Airbridge/Tests/MirrorTests/Fixtures/sample_h264_1080p.bin` | Recorded H.264 Annex-B stream used by integration tests. Captured manually from a phone once and committed. |
| `macos/Airbridge/Tests/IntegrationTests/MirrorIntegrationTests.swift` | E2E test: `MirrorService` server up, fake `URLSessionWebSocketTask` client pushes fixture frames, asserts decoder output. |

### Mac — modified files

| Path | Change |
|---|---|
| `macos/Airbridge/Package.swift` | Add `Mirror` target, `MirrorTests` test target, add `Mirror` as dependency of `AirbridgeApp`. |
| `macos/Airbridge/Sources/Protocol/Message.swift` | Add `mirrorStartRequest(token: String)`, `mirrorStop`, `mirrorError(reason: String)` cases to the `Message` enum + matching `TypeKey`s + Codable encode/decode wiring. |
| `macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift` | Construct `MirrorService` in `init()`, wire to `connectionService` callbacks, register `MirrorWindow` scene with id `"mirror"`. |
| `macos/Airbridge/Sources/AirbridgeApp/MenuBarView.swift` | Add "Mirror telefon" / "Mirror Phone" `MenuRow` between status and "Open AirBridge". On click: send `mirrorStartRequest` over `connectionService` and open the mirror window. |
| `macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift` | When `start()` is called, also pass `mirrorPort` into the existing Bonjour TXT publish (alongside `httpPort`). Reuse `MirrorService.actualPort` as source. |
| `macos/Airbridge/Sources/Networking/WebSocketServer.swift` | Extend Bonjour publishing to accept `mirrorPort: UInt16?` in addition to `httpPort`. (1-line addition.) |

### Android — new files

| Path | Responsibility |
|---|---|
| `android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorMessage.kt` | `MirrorMessage` sealed class + binary encode/decode functions. Mirrors the Swift wire format byte-for-byte. |
| `android/Airbridge/app/src/main/java/com/airbridge/mirror/ScreenEncoder.kt` | Owns `MediaProjection`, `VirtualDisplay`, `MediaCodec` H.264 encoder. Emits `(MirrorMessage)` via callback: first `VideoConfig` (with extracted SPS+PPS), then `VideoFrame`s. Configured with `KEY_LOW_LATENCY`, `KEY_OPERATING_RATE`, `KEY_PRIORITY=0`, CBR. |
| `android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorClient.kt` | Owns OkHttp `WebSocket` to `ws://<mac-ip>:<mirror_port>/`. Sends `Hello`, listens for `HelloAck`, then forwards `MirrorMessage`s from `ScreenEncoder` as binary frames. |
| `android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorService.kt` | Foreground `Service` of type `mediaProjection`. Started by `MirrorActivity` after permission. Hosts `ScreenEncoder` + `MirrorClient`. Foreground notification with Stop action. |
| `android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorActivity.kt` | No-UI activity. On launch, requests `MediaProjection` permission. On grant, starts `MirrorService` with the result intent. On deny, sends a `mirrorError` JSON over the existing connection and finishes. |
| `android/Airbridge/app/src/test/java/com/airbridge/mirror/MirrorMessageTest.kt` | Binary codec round-trip tests + cross-checks against pinned byte fixtures (so Swift and Kotlin can't drift). |
| `android/Airbridge/app/src/test/java/com/airbridge/mirror/MirrorClientTest.kt` | OkHttp `MockWebServer` test: client connects, sends `Hello`, handles `HelloAck`, forwards binary frames. |

### Android — modified files

| Path | Change |
|---|---|
| `android/Airbridge/app/src/main/AndroidManifest.xml` | `FOREGROUND_SERVICE_MEDIA_PROJECTION`, `POST_NOTIFICATIONS` permissions; `<service>` for `MirrorService` (`foregroundServiceType="mediaProjection"`); `<activity>` for `MirrorActivity` (`exported="false"`, no launcher). |
| `android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt` | Add `MirrorStartRequest`, `MirrorStop`, `MirrorError` sealed-class cases, matching JSON `type` keys, encode/decode wiring. |
| `android/Airbridge/app/src/main/java/com/airbridge/discovery/NsdDiscovery.kt` | Read `mirror_port` from TXT record alongside `http_port`. Expose via the resolved-service result. |
| The existing controller that handles incoming `Message`s from Mac (lives in the WebSocket-client area) | On `MirrorStartRequest`, launch `MirrorActivity`. On `MirrorStop`, broadcast/intent to stop `MirrorService`. |

---

## M1 — Wire protocol foundation

### Task 1.1: Add `Mirror` SPM target

**Files:**
- Modify: `macos/Airbridge/Package.swift`
- Create directory: `macos/Airbridge/Sources/Mirror/` (placeholder `.gitkeep` or empty Swift file)
- Create directory: `macos/Airbridge/Tests/MirrorTests/`

- [ ] **Step 1: Add target + test target + dependency**

In `Package.swift`, add to `products`:

```swift
.library(name: "Mirror", targets: ["Mirror"]),
```

Add to `targets`:

```swift
.target(
    name: "Mirror",
    path: "Sources/Mirror"
),
```

Add to test targets:

```swift
.testTarget(
    name: "MirrorTests",
    dependencies: ["Mirror"],
    path: "Tests/MirrorTests"
),
```

Add `"Mirror"` to the `dependencies` array of the existing `AirbridgeApp` executable target.

- [ ] **Step 2: Create placeholder source so swift build succeeds**

Create `macos/Airbridge/Sources/Mirror/Mirror.swift`:

```swift
// Module marker. Real types arrive in Task 1.2.
public enum Mirror {}
```

- [ ] **Step 3: Verify build**

Run: `cd macos/Airbridge && swift build`
Expected: PASS, no errors.

- [ ] **Step 4: Commit**

```bash
git add macos/Airbridge/Package.swift macos/Airbridge/Sources/Mirror/Mirror.swift
git commit -m "feat(mirror): add Mirror SPM target scaffolding"
```

---

### Task 1.2: `MirrorMessage` Swift types + binary codec

**Files:**
- Create: `macos/Airbridge/Sources/Mirror/MirrorMessage.swift`
- Create: `macos/Airbridge/Tests/MirrorTests/MirrorMessageTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/MirrorTests/MirrorMessageTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd macos/Airbridge && swift test --filter MirrorMessageTests`
Expected: FAIL — `MirrorMessage` not defined.

- [ ] **Step 3: Implement `MirrorMessage.swift`**

Create `Sources/Mirror/MirrorMessage.swift`:

```swift
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
    case status(MirrorStatusCode)

    private enum TypeByte {
        static let hello: UInt8 = 0x01
        static let helloAck: UInt8 = 0x02
        static let videoConfig: UInt8 = 0x10
        static let videoFrame: UInt8 = 0x11
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
        let v = self[i..<i+4].withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        i += 4
        return v
    }
    func readBE(at i: inout Int) -> UInt64 {
        let v = self[i..<i+8].withUnsafeBytes { $0.load(as: UInt64.self) }.bigEndian
        i += 8
        return v
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `cd macos/Airbridge && swift test --filter MirrorMessageTests`
Expected: PASS, all 8 tests green.

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/Mirror/MirrorMessage.swift macos/Airbridge/Tests/MirrorTests/MirrorMessageTests.swift
git commit -m "feat(mirror): MirrorMessage binary codec with round-trip tests"
```

---

### Task 1.3: `MirrorMessage` Kotlin types + binary codec

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorMessage.kt`
- Create: `android/Airbridge/app/src/test/java/com/airbridge/mirror/MirrorMessageTest.kt`

- [ ] **Step 1: Write failing tests**

Create `app/src/test/java/com/airbridge/mirror/MirrorMessageTest.kt`:

```kotlin
package com.airbridge.mirror

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MirrorMessageTest {

    @Test fun `HELLO round-trip`() {
        val token = ByteArray(16) { 0xAB.toByte() }
        val msg = MirrorMessage.Hello(token = token, screenWidth = 1080u, screenHeight = 2376u, orientation = 0u)
        val bytes = msg.encode()
        assertEquals(26, bytes.size)
        assertEquals(0x01.toByte(), bytes[0])
        assertEquals(msg, MirrorMessage.decode(bytes))
    }

    @Test fun `HELLO_ACK round-trip`() {
        val msg = MirrorMessage.HelloAck(targetBitrateBps = 12_000_000u, fps = 60u, keyframeIntervalSeconds = 2u, targetWidth = 1080u, targetHeight = 1920u)
        assertEquals(msg, MirrorMessage.decode(msg.encode()))
    }

    @Test fun `VIDEO_CONFIG round-trip`() {
        val sps = byteArrayOf(0x67, 0x42, 0x00, 0x1F)
        val pps = byteArrayOf(0x68.toByte(), 0xCE.toByte(), 0x3C, 0x80.toByte())
        val msg = MirrorMessage.VideoConfig(sps = sps, pps = pps)
        assertEquals(msg, MirrorMessage.decode(msg.encode()))
    }

    @Test fun `VIDEO_FRAME round-trip`() {
        val nalu = ByteArray(2048) { (it and 0xFF).toByte() }
        val msg = MirrorMessage.VideoFrame(presentationTimestampUs = 1_234_567_890uL, naluBytes = nalu)
        assertEquals(msg, MirrorMessage.decode(msg.encode()))
    }

    @Test fun `STATUS round-trip - all codes`() {
        for (code in MirrorStatusCode.values()) {
            val msg = MirrorMessage.Status(code)
            assertEquals(msg, MirrorMessage.decode(msg.encode()))
        }
    }

    @Test fun `decode rejects empty`() {
        assertThrows(MirrorMessageException::class.java) { MirrorMessage.decode(byteArrayOf()) }
    }

    @Test fun `decode rejects unknown type`() {
        assertThrows(MirrorMessageException::class.java) { MirrorMessage.decode(byteArrayOf(0xFE.toByte(), 0, 0, 0)) }
    }

    @Test fun `cross-platform pinned bytes - HELLO`() {
        val token = ByteArray(16) { 0xAB.toByte() }
        val msg = MirrorMessage.Hello(token, 1080u, 2376u, 0u)
        val expected = byteArrayOf(0x01) + token +
            byteArrayOf(0, 0, 0x04, 0x38) + // 1080
            byteArrayOf(0, 0, 0x09, 0x48) + // 2376
            byteArrayOf(0)
        assertEquals(expected.toList(), msg.encode().toList())
    }
}
```

- [ ] **Step 2: Run tests, verify fail**

Run: `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.mirror.MirrorMessageTest"`
Expected: FAIL — class not found.

- [ ] **Step 3: Implement `MirrorMessage.kt`**

Create `app/src/main/java/com/airbridge/mirror/MirrorMessage.kt`:

```kotlin
package com.airbridge.mirror

import java.nio.ByteBuffer
import java.nio.ByteOrder

enum class MirrorStatusCode(val raw: Byte) {
    SCREEN_OFF(1),
    APP_BACKGROUNDED(2),
    ACCESSIBILITY_DISABLED(3),
    ENCODER_ERROR(4),
    ACCESSIBILITY_BLOCKED(5);

    companion object {
        fun fromRaw(raw: Byte): MirrorStatusCode? = values().firstOrNull { it.raw == raw }
    }
}

class MirrorMessageException(message: String) : RuntimeException(message)

@OptIn(ExperimentalUnsignedTypes::class)
sealed class MirrorMessage {
    data class Hello(
        val token: ByteArray,
        val screenWidth: UInt,
        val screenHeight: UInt,
        val orientation: UByte
    ) : MirrorMessage() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Hello) return false
            return token.contentEquals(other.token) &&
                screenWidth == other.screenWidth &&
                screenHeight == other.screenHeight &&
                orientation == other.orientation
        }
        override fun hashCode(): Int =
            (((token.contentHashCode() * 31) + screenWidth.hashCode()) * 31 + screenHeight.hashCode()) * 31 + orientation.hashCode()
    }

    data class HelloAck(
        val targetBitrateBps: UInt,
        val fps: UByte,
        val keyframeIntervalSeconds: UByte,
        val targetWidth: UInt,
        val targetHeight: UInt
    ) : MirrorMessage()

    data class VideoConfig(val sps: ByteArray, val pps: ByteArray) : MirrorMessage() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is VideoConfig) return false
            return sps.contentEquals(other.sps) && pps.contentEquals(other.pps)
        }
        override fun hashCode() = sps.contentHashCode() * 31 + pps.contentHashCode()
    }

    data class VideoFrame(val presentationTimestampUs: ULong, val naluBytes: ByteArray) : MirrorMessage() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is VideoFrame) return false
            return presentationTimestampUs == other.presentationTimestampUs && naluBytes.contentEquals(other.naluBytes)
        }
        override fun hashCode() = presentationTimestampUs.hashCode() * 31 + naluBytes.contentHashCode()
    }

    data class Status(val code: MirrorStatusCode) : MirrorMessage()

    companion object {
        private const val TYPE_HELLO: Byte = 0x01
        private const val TYPE_HELLO_ACK: Byte = 0x02
        private const val TYPE_VIDEO_CONFIG: Byte = 0x10
        private const val TYPE_VIDEO_FRAME: Byte = 0x11
        private const val TYPE_STATUS: Byte = 0x30

        fun decode(bytes: ByteArray): MirrorMessage {
            if (bytes.isEmpty()) throw MirrorMessageException("empty payload")
            val buf = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
            return when (val type = buf.get()) {
                TYPE_HELLO -> {
                    if (bytes.size != 1 + 16 + 4 + 4 + 1) throw MirrorMessageException("HELLO truncated")
                    val token = ByteArray(16); buf.get(token)
                    val w = buf.int.toUInt(); val h = buf.int.toUInt()
                    val orient = buf.get().toUByte()
                    Hello(token, w, h, orient)
                }
                TYPE_HELLO_ACK -> {
                    if (bytes.size != 1 + 4 + 1 + 1 + 4 + 4) throw MirrorMessageException("HELLO_ACK truncated")
                    val bitrate = buf.int.toUInt()
                    val fps = buf.get().toUByte()
                    val kf = buf.get().toUByte()
                    val w = buf.int.toUInt(); val h = buf.int.toUInt()
                    HelloAck(bitrate, fps, kf, w, h)
                }
                TYPE_VIDEO_CONFIG -> {
                    if (buf.remaining() < 4) throw MirrorMessageException("VIDEO_CONFIG short SPS len")
                    val spsLen = buf.int
                    if (buf.remaining() < spsLen + 4) throw MirrorMessageException("VIDEO_CONFIG short SPS")
                    val sps = ByteArray(spsLen); buf.get(sps)
                    val ppsLen = buf.int
                    if (buf.remaining() != ppsLen) throw MirrorMessageException("VIDEO_CONFIG bad PPS")
                    val pps = ByteArray(ppsLen); buf.get(pps)
                    VideoConfig(sps, pps)
                }
                TYPE_VIDEO_FRAME -> {
                    if (buf.remaining() < 8) throw MirrorMessageException("VIDEO_FRAME no PTS")
                    val pts = buf.long.toULong()
                    val nalu = ByteArray(buf.remaining()); buf.get(nalu)
                    VideoFrame(pts, nalu)
                }
                TYPE_STATUS -> {
                    if (buf.remaining() != 1) throw MirrorMessageException("STATUS truncated")
                    val code = MirrorStatusCode.fromRaw(buf.get())
                        ?: throw MirrorMessageException("STATUS unknown code")
                    Status(code)
                }
                else -> throw MirrorMessageException("unknown type 0x${type.toUByte().toString(16)}")
            }
        }
    }

    fun encode(): ByteArray = when (this) {
        is Hello -> ByteBuffer.allocate(1 + 16 + 4 + 4 + 1).order(ByteOrder.BIG_ENDIAN)
            .put(TYPE_HELLO).put(token).putInt(screenWidth.toInt()).putInt(screenHeight.toInt()).put(orientation.toByte()).array()
        is HelloAck -> ByteBuffer.allocate(1 + 4 + 1 + 1 + 4 + 4).order(ByteOrder.BIG_ENDIAN)
            .put(TYPE_HELLO_ACK).putInt(targetBitrateBps.toInt()).put(fps.toByte()).put(keyframeIntervalSeconds.toByte())
            .putInt(targetWidth.toInt()).putInt(targetHeight.toInt()).array()
        is VideoConfig -> ByteBuffer.allocate(1 + 4 + sps.size + 4 + pps.size).order(ByteOrder.BIG_ENDIAN)
            .put(TYPE_VIDEO_CONFIG).putInt(sps.size).put(sps).putInt(pps.size).put(pps).array()
        is VideoFrame -> ByteBuffer.allocate(1 + 8 + naluBytes.size).order(ByteOrder.BIG_ENDIAN)
            .put(TYPE_VIDEO_FRAME).putLong(presentationTimestampUs.toLong()).put(naluBytes).array()
        is Status -> byteArrayOf(TYPE_STATUS, code.raw)
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.mirror.MirrorMessageTest"`
Expected: PASS, all 8 tests.

- [ ] **Step 5: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorMessage.kt android/Airbridge/app/src/test/java/com/airbridge/mirror/MirrorMessageTest.kt
git commit -m "feat(mirror): Kotlin MirrorMessage codec matching Swift wire format"
```

---

## M2 — Mac decoder + renderer

### Task 2.1: NALU parser (Annex-B → AVCC + SPS/PPS extraction)

**Files:**
- Create: `macos/Airbridge/Sources/Mirror/NALUParser.swift`
- Create: `macos/Airbridge/Tests/MirrorTests/NALUParserTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/MirrorTests/NALUParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests, verify fail**

Run: `cd macos/Airbridge && swift test --filter NALUParserTests`
Expected: FAIL.

- [ ] **Step 3: Implement `NALUParser.swift`**

```swift
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
```

- [ ] **Step 4: Run tests, verify pass**

Run: `cd macos/Airbridge && swift test --filter NALUParserTests`
Expected: PASS, 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/Mirror/NALUParser.swift macos/Airbridge/Tests/MirrorTests/NALUParserTests.swift
git commit -m "feat(mirror): NALU Annex-B parser + AVCC conversion"
```

---

### Task 2.2: `VideoDecoder` (`VTDecompressionSession` wrapper)

**Files:**
- Create: `macos/Airbridge/Sources/Mirror/VideoDecoder.swift`
- Create: `macos/Airbridge/Tests/MirrorTests/VideoDecoderTests.swift`

- [ ] **Step 1: Write failing smoke test**

Create `Tests/MirrorTests/VideoDecoderTests.swift`:

```swift
import Testing
import Foundation
import CoreMedia
@testable import Mirror

@Suite("VideoDecoder")
struct VideoDecoderTests {

    /// Minimal valid SPS + PPS captured from MediaCodec H.264 baseline at 4×4 px.
    /// Real fixtures live in Tests/MirrorTests/Fixtures; this is just to confirm the wrapper
    /// validates inputs and constructs a `CMVideoFormatDescription` without crashing.
    @Test("Constructing format description with valid SPS+PPS succeeds")
    func formatDescriptionConstruction() throws {
        // SPS for 4x4 baseline: 67 42 00 0A E9 02 00 80 00 00 03 00 80 00 00 18 47 8C 18 CB
        let sps = Data([0x67, 0x42, 0x00, 0x0A, 0xE9, 0x02, 0x00, 0x80,
                        0x00, 0x00, 0x03, 0x00, 0x80, 0x00, 0x00, 0x18,
                        0x47, 0x8C, 0x18, 0xCB])
        // PPS: 68 CE 3C 80
        let pps = Data([0x68, 0xCE, 0x3C, 0x80])

        let formatDesc = try VideoDecoder.makeFormatDescription(sps: sps, pps: pps)
        let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
        #expect(dims.width == 4)
        #expect(dims.height == 4)
    }

    @Test("Construction fails on empty SPS")
    func constructionFailsEmptySPS() {
        #expect(throws: VideoDecoderError.self) {
            _ = try VideoDecoder.makeFormatDescription(sps: Data(), pps: Data([0x68]))
        }
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `cd macos/Airbridge && swift test --filter VideoDecoderTests`
Expected: FAIL.

- [ ] **Step 3: Implement `VideoDecoder.swift`**

```swift
import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

public enum VideoDecoderError: Error, Sendable {
    case emptyParameterSet
    case formatDescriptionFailed(OSStatus)
    case sessionCreateFailed(OSStatus)
    case decodeFailed(OSStatus)
}

public final class VideoDecoder: @unchecked Sendable {

    public typealias OnSample = @Sendable (CMSampleBuffer) -> Void

    private let onSample: OnSample
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?

    public init(onSample: @escaping OnSample) {
        self.onSample = onSample
    }

    public func configure(sps: Data, pps: Data) throws {
        let fmt = try Self.makeFormatDescription(sps: sps, pps: pps)
        self.formatDescription = fmt
        try createSession(formatDescription: fmt)
    }

    public func decode(avccFrame: Data, presentationTimestampUs pts: UInt64) throws {
        guard let session, let formatDescription else { return }
        var blockBuffer: CMBlockBuffer?
        var bytes = [UInt8](avccFrame)
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: bytes.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else { throw VideoDecoderError.decodeFailed(status) }
        CMBlockBufferReplaceDataBytes(with: &bytes, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: bytes.count)

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = bytes.count
        let timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(pts), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        var timings = [timing]
        let createStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timings,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else { throw VideoDecoderError.decodeFailed(createStatus) }

        var flags: VTDecodeFrameFlags = ._EnableAsynchronousDecompression
        var infoFlags: VTDecodeInfoFlags = []
        let decodeStatus = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: flags, frameRefcon: nil, infoFlagsOut: &infoFlags)
        if decodeStatus != noErr { throw VideoDecoderError.decodeFailed(decodeStatus) }
    }

    public static func makeFormatDescription(sps: Data, pps: Data) throws -> CMVideoFormatDescription {
        guard !sps.isEmpty, !pps.isEmpty else { throw VideoDecoderError.emptyParameterSet }
        var formatDesc: CMVideoFormatDescription?
        let spsBytes = [UInt8](sps), ppsBytes = [UInt8](pps)
        let parameterSetPointers: [UnsafePointer<UInt8>] = [
            UnsafePointer(spsBytes), UnsafePointer(ppsBytes)
        ]
        let parameterSetSizes = [spsBytes.count, ppsBytes.count]
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 2,
            parameterSetPointers: parameterSetPointers,
            parameterSetSizes: parameterSetSizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &formatDesc
        )
        guard status == noErr, let formatDesc else { throw VideoDecoderError.formatDescriptionFailed(status) }
        return formatDesc
    }

    private func createSession(formatDescription: CMVideoFormatDescription) throws {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var session: VTDecompressionSession?
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { decompressionOutputRefCon, _, _, _, sampleBuffer, _, _ in
                guard let refCon = decompressionOutputRefCon, let sampleBuffer else { return }
                let me = Unmanaged<VideoDecoder>.fromOpaque(refCon).takeUnretainedValue()
                me.onSample(sampleBuffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        guard status == noErr, let session else { throw VideoDecoderError.sessionCreateFailed(status) }

        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_MaximizePowerEfficiency, value: kCFBooleanFalse)
        self.session = session
    }

    deinit {
        if let session { VTDecompressionSessionInvalidate(session) }
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `cd macos/Airbridge && swift test --filter VideoDecoderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/Mirror/VideoDecoder.swift macos/Airbridge/Tests/MirrorTests/VideoDecoderTests.swift
git commit -m "feat(mirror): VideoDecoder wrapping VTDecompressionSession in real-time mode"
```

---

### Task 2.3: `MirrorRendererView` (NSViewRepresentable)

**Files:**
- Create: `macos/Airbridge/Sources/Mirror/MirrorRendererView.swift`

This is glue between `CMSampleBuffer` and SwiftUI; not unit-tested in isolation (no headless rendering target). Smoke-tested via the integration test in M7.

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import AppKit
import AVFoundation

public final class MirrorRendererLayerView: NSView {
    public override func makeBackingLayer() -> CALayer {
        return AVSampleBufferDisplayLayer()
    }
    public override var wantsUpdateLayer: Bool { true }

    public var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        displayLayer.videoGravity = .resizeAspect
    }
    public required init?(coder: NSCoder) { fatalError() }

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.isReadyForMoreMediaData {
            displayLayer.enqueue(sampleBuffer)
        }
    }
}

public struct MirrorRendererView: NSViewRepresentable {
    public final class Coordinator {
        weak var view: MirrorRendererLayerView?
    }

    private let stream: AsyncStream<CMSampleBuffer>

    public init(stream: AsyncStream<CMSampleBuffer>) {
        self.stream = stream
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> MirrorRendererLayerView {
        let view = MirrorRendererLayerView(frame: .zero)
        context.coordinator.view = view
        Task { @MainActor in
            for await sample in stream {
                context.coordinator.view?.enqueue(sample)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: MirrorRendererLayerView, context: Context) {}
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd macos/Airbridge && swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add macos/Airbridge/Sources/Mirror/MirrorRendererView.swift
git commit -m "feat(mirror): SwiftUI MirrorRendererView with AVSampleBufferDisplayLayer immediate display"
```

---

## M3 — Mac MirrorService

### Task 3.1: `MirrorService` skeleton with second `WebSocketServer`

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeApp/Services/MirrorService.swift`

This is a service object integrated into the SwiftUI `@Observable` lifecycle; tested via the integration test in M7 rather than unit-isolated.

- [ ] **Step 1: Implement skeleton**

```swift
import Foundation
import Network
import Networking
import Mirror
import CoreMedia
import Observation

@Observable @MainActor
public final class MirrorService {

    public private(set) var isStreaming: Bool = false
    public private(set) var actualPort: UInt16?
    public let sampleBufferStream: AsyncStream<CMSampleBuffer>
    private let sampleBufferContinuation: AsyncStream<CMSampleBuffer>.Continuation

    private let server: WebSocketServer
    private var pairingTokenProvider: () -> Data?
    private var decoder: VideoDecoder?

    public init(pairingTokenProvider: @escaping () -> Data? = { nil }) {
        self.pairingTokenProvider = pairingTokenProvider
        self.server = WebSocketServer(port: 8766)
        var continuation: AsyncStream<CMSampleBuffer>.Continuation!
        self.sampleBufferStream = AsyncStream { continuation = $0 }
        self.sampleBufferContinuation = continuation
    }

    public func setPairingTokenProvider(_ provider: @escaping () -> Data?) {
        self.pairingTokenProvider = provider
    }

    public func start() async throws {
        guard actualPort == nil else { return }
        await server.setCallbacks(
            onMessage: nil,
            onBinaryMessage: { [weak self] data in
                Task { @MainActor in self?.handleBinaryFrame(data) }
            },
            onClientConnected: { _ in },
            onClientDisconnected: { [weak self] _ in
                Task { @MainActor in self?.handleDisconnect() }
            }
        )
        try await server.start()
        actualPort = await server.actualPort
    }

    public func stop() async {
        await server.disconnectAllClients()
        actualPort = nil
        isStreaming = false
        decoder = nil
    }

    private func handleBinaryFrame(_ data: Data) {
        do {
            let msg = try MirrorMessage.decode(data)
            switch msg {
            case let .hello(token, _, _, _):
                guard let expected = pairingTokenProvider(), token == expected else {
                    Task { await server.disconnectAllClients() }
                    return
                }
                // Reply with HELLO_ACK at fixed defaults; quality picker is Plan B
                let ack = MirrorMessage.helloAck(targetBitrateBps: 12_000_000, fps: 60, keyframeIntervalSeconds: 2, targetWidth: 1920, targetHeight: 1080)
                Task { try? await server.broadcastBinary(ack.encode()) }

            case let .videoConfig(sps, pps):
                let dec = VideoDecoder { [weak self] sample in
                    self?.sampleBufferContinuation.yield(sample)
                }
                try dec.configure(sps: sps, pps: pps)
                self.decoder = dec
                self.isStreaming = true

            case let .videoFrame(pts, naluBytes):
                guard let decoder else { return }
                // Phone sends each frame as a single NALU (one VIDEO_FRAME = one NALU).
                // Convert to AVCC by prepending 4-byte length.
                let avcc = NALUParser.toAVCC(naluBytes)
                try decoder.decode(avccFrame: avcc, presentationTimestampUs: pts)

            case .status, .helloAck:
                // Status logging in Plan B; HELLO_ACK is server→client only
                break
            }
        } catch {
            // Decode error → ignore frame, will recover on next keyframe.
        }
    }

    private func handleDisconnect() {
        isStreaming = false
        decoder = nil
    }
}
```

- [ ] **Step 2: Add `broadcastBinary` to `WebSocketServer`**

Modify `Sources/Networking/WebSocketServer.swift`. Add this method on the actor:

```swift
public func broadcastBinary(_ data: Data) async throws {
    for (_, conn) in connections {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "binary", metadata: [metadata])
        try await withCheckedThrowingContinuation { (cc: CheckedContinuation<Void, Error>) in
            conn.send(content: data, contentContext: context, isComplete: true,
                      completion: .contentProcessed { err in
                          if let err { cc.resume(throwing: err) } else { cc.resume() }
                      })
        }
    }
}
```

- [ ] **Step 3: Verify build**

Run: `cd macos/Airbridge && swift build`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Services/MirrorService.swift macos/Airbridge/Sources/Networking/WebSocketServer.swift
git commit -m "feat(mirror): MirrorService skeleton with second WebSocketServer on 8766"
```

---

## M4 — Android encoder + transport

### Task 4.1: `ScreenEncoder` with `MediaCodec` low-latency config

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/mirror/ScreenEncoder.kt`

This is a hardware-encoder integration; tested manually + by integration test in M7.

- [ ] **Step 1: Implement**

```kotlin
package com.airbridge.mirror

import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.os.Build
import android.util.Log
import java.nio.ByteBuffer

class ScreenEncoder(
    private val mediaProjection: MediaProjection,
    private val width: Int,
    private val height: Int,
    private val fps: Int,
    private val bitrateBps: Int,
    private val keyframeIntervalSeconds: Int,
    private val onMessage: (MirrorMessage) -> Unit
) {
    private var encoder: MediaCodec? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var pendingSps: ByteArray? = null
    private var pendingPps: ByteArray? = null
    private var configEmitted = false

    fun start() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrateBps)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, keyframeIntervalSeconds)
            setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setInteger(MediaFormat.KEY_OPERATING_RATE, Short.MAX_VALUE.toInt())
                setInteger(MediaFormat.KEY_PRIORITY, 0)
            }
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = codec.createInputSurface()

        codec.setCallback(object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(c: MediaCodec, idx: Int) { /* Surface input, ignored */ }
            override fun onOutputBufferAvailable(c: MediaCodec, idx: Int, info: MediaCodec.BufferInfo) {
                val buf: ByteBuffer = c.getOutputBuffer(idx) ?: return run { c.releaseOutputBuffer(idx, false) }
                buf.position(info.offset); buf.limit(info.offset + info.size)
                val payload = ByteArray(info.size); buf.get(payload)

                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    extractSpsPps(payload)
                    maybeEmitConfig()
                } else if (info.size > 0) {
                    val nalu = stripAnnexBStartCode(payload)
                    onMessage(MirrorMessage.VideoFrame(presentationTimestampUs = info.presentationTimeUs.toULong(), naluBytes = nalu))
                }
                c.releaseOutputBuffer(idx, false)
            }
            override fun onError(c: MediaCodec, e: MediaCodec.CodecException) {
                Log.e(TAG, "MediaCodec error", e)
                onMessage(MirrorMessage.Status(MirrorStatusCode.ENCODER_ERROR))
            }
            override fun onOutputFormatChanged(c: MediaCodec, format: MediaFormat) {
                format.getByteBuffer("csd-0")?.let { pendingSps = it.toBytes() }
                format.getByteBuffer("csd-1")?.let { pendingPps = it.toBytes() }
                maybeEmitConfig()
            }
        })

        codec.start()
        encoder = codec

        // MediaProjection.createVirtualDisplay handles scaling internally — pass target encoder dims.
        virtualDisplay = mediaProjection.createVirtualDisplay(
            "AirBridgeMirror", width, height, /*dpi*/ 320,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            inputSurface, null, null
        )
    }

    fun stop() {
        virtualDisplay?.release(); virtualDisplay = null
        encoder?.stop(); encoder?.release(); encoder = null
        configEmitted = false; pendingSps = null; pendingPps = null
    }

    private fun extractSpsPps(annexB: ByteArray) {
        val parts = NALUSplitter.split(annexB)
        for (nalu in parts) {
            when ((nalu[0].toInt() and 0x1F)) {
                7 -> pendingSps = nalu
                8 -> pendingPps = nalu
            }
        }
    }

    private fun maybeEmitConfig() {
        val sps = pendingSps; val pps = pendingPps
        if (!configEmitted && sps != null && pps != null) {
            onMessage(MirrorMessage.VideoConfig(sps, pps))
            configEmitted = true
        }
    }

    private fun stripAnnexBStartCode(annexB: ByteArray): ByteArray {
        // Each output frame from MediaCodec starts with 00 00 00 01 or 00 00 01.
        // For VIDEO_FRAME we send the raw NALU without the start code; AVCC-prefix added on Mac side.
        return when {
            annexB.size > 4 && annexB[0] == 0.toByte() && annexB[1] == 0.toByte() && annexB[2] == 0.toByte() && annexB[3] == 1.toByte() -> annexB.copyOfRange(4, annexB.size)
            annexB.size > 3 && annexB[0] == 0.toByte() && annexB[1] == 0.toByte() && annexB[2] == 1.toByte() -> annexB.copyOfRange(3, annexB.size)
            else -> annexB
        }
    }

    private fun ByteBuffer.toBytes(): ByteArray = ByteArray(remaining()).also { get(it) }

    companion object { private const val TAG = "ScreenEncoder" }
}

internal object NALUSplitter {
    fun split(stream: ByteArray): List<ByteArray> {
        val out = mutableListOf<ByteArray>()
        var i = 0; var lastStart = -1
        while (i + 2 < stream.size) {
            val isStart4 = i + 3 < stream.size && stream[i] == 0.toByte() && stream[i+1] == 0.toByte() && stream[i+2] == 0.toByte() && stream[i+3] == 1.toByte()
            val isStart3 = stream[i] == 0.toByte() && stream[i+1] == 0.toByte() && stream[i+2] == 1.toByte()
            when {
                isStart4 -> { if (lastStart >= 0) out += stream.copyOfRange(lastStart, i); lastStart = i + 4; i += 4 }
                isStart3 -> { if (lastStart >= 0) out += stream.copyOfRange(lastStart, i); lastStart = i + 3; i += 3 }
                else -> i++
            }
        }
        if (lastStart in 0 until stream.size) out += stream.copyOfRange(lastStart, stream.size)
        return out
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd android/Airbridge && ./gradlew :app:assembleDebug`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/mirror/ScreenEncoder.kt
git commit -m "feat(mirror): ScreenEncoder with MediaCodec KEY_LOW_LATENCY config"
```

---

### Task 4.2: `MirrorClient` (OkHttp WebSocket)

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorClient.kt`
- Create: `android/Airbridge/app/src/test/java/com/airbridge/mirror/MirrorClientTest.kt`

- [ ] **Step 1: Write failing test**

```kotlin
package com.airbridge.mirror

import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.WebSocketRecorder
import okio.ByteString.Companion.toByteString
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class MirrorClientTest {

    private lateinit var server: MockWebServer

    @Before fun setUp() { server = MockWebServer().apply { start() } }
    @After fun tearDown() { server.shutdown() }

    @Test fun `sends HELLO on connect`() {
        val recorder = WebSocketRecorder("server")
        server.enqueue(MockResponse().withWebSocketUpgrade(recorder))

        val token = ByteArray(16) { 0xAB.toByte() }
        val client = MirrorClient(
            host = server.hostName, port = server.port, pairingToken = token,
            screenWidth = 1080u, screenHeight = 2376u, orientation = 0u,
            onAck = {}, onDisconnect = {}
        )
        client.connect()

        val firstMessage = recorder.nextMessage(5, TimeUnit.SECONDS)
        val bytes = firstMessage.bytes!!.toByteArray()
        val msg = MirrorMessage.decode(bytes) as MirrorMessage.Hello
        assertEquals(token.toList(), msg.token.toList())
        client.close()
    }
}
```

- [ ] **Step 2: Add `okhttp-mockwebserver` test dependency**

Edit `android/Airbridge/app/build.gradle.kts`, add to `dependencies`:

```kotlin
testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
```

- [ ] **Step 3: Run test, verify fail**

Run: `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.mirror.MirrorClientTest"`
Expected: FAIL — class not found.

- [ ] **Step 4: Implement `MirrorClient.kt`**

```kotlin
package com.airbridge.mirror

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import java.util.concurrent.TimeUnit

class MirrorClient(
    private val host: String,
    private val port: Int,
    private val pairingToken: ByteArray,
    private val screenWidth: UInt,
    private val screenHeight: UInt,
    private val orientation: UByte,
    private val onAck: (MirrorMessage.HelloAck) -> Unit,
    private val onDisconnect: () -> Unit
) {
    private val http = OkHttpClient.Builder()
        .pingInterval(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .build()
    private var webSocket: WebSocket? = null

    fun connect() {
        val req = Request.Builder().url("ws://$host:$port/").build()
        webSocket = http.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                val hello = MirrorMessage.Hello(pairingToken, screenWidth, screenHeight, orientation)
                ws.send(hello.encode().toByteString())
            }
            override fun onMessage(ws: WebSocket, bytes: ByteString) {
                runCatching { MirrorMessage.decode(bytes.toByteArray()) }
                    .onSuccess { msg -> if (msg is MirrorMessage.HelloAck) onAck(msg) }
            }
            override fun onClosed(ws: WebSocket, code: Int, reason: String) { onDisconnect() }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) { onDisconnect() }
        })
    }

    fun send(message: MirrorMessage) {
        webSocket?.send(message.encode().toByteString())
    }

    fun close() {
        webSocket?.close(1000, "client stop")
        webSocket = null
    }
}
```

- [ ] **Step 5: Run test, verify pass**

Run: `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.mirror.MirrorClientTest"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorClient.kt android/Airbridge/app/src/test/java/com/airbridge/mirror/MirrorClientTest.kt android/Airbridge/app/build.gradle.kts
git commit -m "feat(mirror): MirrorClient over OkHttp WebSocket with mock-server test"
```

---

### Task 4.3: `MirrorService` Foreground Service

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorService.kt`
- Modify: `android/Airbridge/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add manifest permissions and `<service>`**

Inside `<manifest>`, add:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Inside `<application>`, add:

```xml
<service
    android:name=".mirror.MirrorService"
    android:foregroundServiceType="mediaProjection"
    android:exported="false" />
<activity
    android:name=".mirror.MirrorActivity"
    android:exported="false"
    android:theme="@android:style/Theme.Translucent.NoTitleBar" />
```

- [ ] **Step 2: Implement `MirrorService.kt`**

```kotlin
package com.airbridge.mirror

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import com.airbridge.R

class MirrorService : Service() {

    private var mediaProjection: MediaProjection? = null
    private var encoder: ScreenEncoder? = null
    private var client: MirrorClient? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent ?: return START_NOT_STICKY
        when (intent.action) {
            ACTION_START -> startMirror(intent)
            ACTION_STOP -> { stopMirror(); stopSelf() }
        }
        return START_NOT_STICKY
    }

    private fun startMirror(intent: Intent) {
        startForegroundCompat()
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val data = intent.getParcelableExtra<Intent>(EXTRA_RESULT_DATA) ?: return stopSelf()
        val host = intent.getStringExtra(EXTRA_HOST) ?: return stopSelf()
        val port = intent.getIntExtra(EXTRA_PORT, 0)
        val token = intent.getByteArrayExtra(EXTRA_TOKEN) ?: return stopSelf()

        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = mpm.getMediaProjection(resultCode, data)
        mediaProjection = projection

        val (w, h) = displayDimensions()

        client = MirrorClient(
            host = host, port = port, pairingToken = token,
            screenWidth = w.toUInt(), screenHeight = h.toUInt(), orientation = 0u,
            onAck = { ack ->
                val targetW = ack.targetWidth.toInt().coerceAtLeast(1)
                val targetH = ack.targetHeight.toInt().coerceAtLeast(1)
                val enc = ScreenEncoder(
                    mediaProjection = projection,
                    width = targetW, height = targetH,
                    fps = ack.fps.toInt(),
                    bitrateBps = ack.targetBitrateBps.toInt(),
                    keyframeIntervalSeconds = ack.keyframeIntervalSeconds.toInt()
                ) { msg -> client?.send(msg) }
                enc.start()
                encoder = enc
            },
            onDisconnect = { stopSelf() }
        ).also { it.connect() }
    }

    private fun stopMirror() {
        encoder?.stop(); encoder = null
        client?.close(); client = null
        mediaProjection?.stop(); mediaProjection = null
    }

    override fun onDestroy() { stopMirror(); super.onDestroy() }

    private fun startForegroundCompat() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(
                CHANNEL, "Mirror", NotificationManager.IMPORTANCE_LOW))
        }
        val stopIntent = Intent(this, MirrorService::class.java).setAction(ACTION_STOP)
        val stopPi = PendingIntent.getService(this, 0, stopIntent, PendingIntent.FLAG_IMMUTABLE)
        val notif = Notification.Builder(this, CHANNEL)
            .setContentTitle(getString(R.string.app_name))
            .setContentText("Mirror trwa")
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .addAction(0, "Stop", stopPi)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun displayDimensions(): Pair<Int, Int> {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics().also { wm.defaultDisplay.getRealMetrics(it) }
        return metrics.widthPixels to metrics.heightPixels
    }

    companion object {
        const val ACTION_START = "com.airbridge.mirror.START"
        const val ACTION_STOP = "com.airbridge.mirror.STOP"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"
        const val EXTRA_TOKEN = "token"
        private const val CHANNEL = "mirror"
        private const val NOTIF_ID = 4711
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd android/Airbridge && ./gradlew :app:assembleDebug`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorService.kt android/Airbridge/app/src/main/AndroidManifest.xml
git commit -m "feat(mirror): MirrorService foreground service with mediaProjection type"
```

---

### Task 4.4: `MirrorActivity` permission gate

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorActivity.kt`

- [ ] **Step 1: Implement**

```kotlin
package com.airbridge.mirror

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle

class MirrorActivity : Activity() {

    private var host: String = ""
    private var port: Int = 0
    private var token: ByteArray = ByteArray(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        host = intent.getStringExtra(EXTRA_HOST) ?: return finish()
        port = intent.getIntExtra(EXTRA_PORT, 0)
        token = intent.getByteArrayExtra(EXTRA_TOKEN) ?: return finish()

        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(mpm.createScreenCaptureIntent(), REQUEST_CAPTURE)
    }

    @Deprecated("Activity result API in older form; sufficient for short-lived gate activity.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAPTURE) { finish(); return }
        if (resultCode != RESULT_OK || data == null) { finish(); return }

        val svc = Intent(this, MirrorService::class.java).apply {
            action = MirrorService.ACTION_START
            putExtra(MirrorService.EXTRA_RESULT_CODE, resultCode)
            putExtra(MirrorService.EXTRA_RESULT_DATA, data)
            putExtra(MirrorService.EXTRA_HOST, host)
            putExtra(MirrorService.EXTRA_PORT, port)
            putExtra(MirrorService.EXTRA_TOKEN, token)
        }
        startForegroundService(svc)
        finish()
    }

    companion object {
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"
        const val EXTRA_TOKEN = "token"
        private const val REQUEST_CAPTURE = 4711
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android/Airbridge && ./gradlew :app:assembleDebug`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/mirror/MirrorActivity.kt
git commit -m "feat(mirror): MirrorActivity permission gate for MediaProjection"
```

---

## M5 — Discovery (Bonjour TXT advertisement of mirror_port)

### Task 5.1: Mac advertises `mirror_port` in Bonjour TXT

**Files:**
- Modify: `macos/Airbridge/Sources/Networking/WebSocketServer.swift`
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift`

- [ ] **Step 1: Extend `start(...)` signature**

In `WebSocketServer.swift`, change the `start` method signature to include `mirrorPort`:

```swift
public func start(bonjourName: String? = nil,
                  httpPort: UInt16? = nil,
                  mirrorPort: UInt16? = nil,
                  publicKeyFingerprint: String? = nil) async throws {
```

Inside the `txtRecord` building block, add (next to the existing `http_port`):

```swift
if let mirrorPort {
    txtRecord["mirror_port"] = "\(mirrorPort)"
}
```

- [ ] **Step 2: Pass `mirrorPort` from `ConnectionService`**

In `ConnectionService.start(...)` (around line 84), modify the call:

```swift
try await server.start(
    bonjourName: deviceName,
    httpPort: httpPort,
    mirrorPort: mirrorService?.actualPort,
    publicKeyFingerprint: fingerprint
)
```

(Add a `mirrorService: MirrorService?` property to `ConnectionService`, set by `AirbridgeApp.init()` after `MirrorService.start()` resolves.)

- [ ] **Step 3: Build**

Run: `cd macos/Airbridge && swift build`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add macos/Airbridge/Sources/Networking/WebSocketServer.swift macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift
git commit -m "feat(mirror): advertise mirror_port via Bonjour TXT"
```

---

### Task 5.2: Android reads `mirror_port` from TXT record

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/discovery/NsdDiscovery.kt`

- [ ] **Step 1: Read existing file, add `mirrorPort` to resolved-service result**

After the existing `httpPortStr` extraction (around line 64), add:

```kotlin
val mirrorPortStr = serviceInfo.attributes["mirror_port"]?.let { String(it, Charsets.UTF_8) }
val mirrorPort = mirrorPortStr?.toIntOrNull()
```

Plumb `mirrorPort` into the result data class (the existing one that carries `httpPort`). Add an Int? field there.

- [ ] **Step 2: Build**

Run: `cd android/Airbridge && ./gradlew :app:assembleDebug`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/discovery/NsdDiscovery.kt
git commit -m "feat(mirror): NsdDiscovery exposes mirror_port from TXT"
```

---

## M6 — UI initiation

### Task 6.1: `mirrorStartRequest` / `mirrorStop` / `mirrorError` messages on existing channel

**Files:**
- Modify: `macos/Airbridge/Sources/Protocol/Message.swift`
- Modify: `macos/Airbridge/Tests/ProtocolTests/MessageTests.swift` (or appropriate existing file)
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt`
- Modify: `android/Airbridge/app/src/test/java/com/airbridge/protocol/MessageTest.kt`

- [ ] **Step 1: Swift — add cases + Codable wiring**

Add to the `Message` enum:

```swift
case mirrorStartRequest(token: String)
case mirrorStop
case mirrorError(reason: String)
```

Add to `TypeKey`:

```swift
case mirrorStartRequest = "mirror_start_request"
case mirrorStop = "mirror_stop"
case mirrorError = "mirror_error"
```

Wire encode/decode in the existing `encode(to:)` / `init(from:)` blocks following the existing `pairRequest`/`pairResponse` style.

- [ ] **Step 2: Swift test — round-trip JSON**

Add to existing protocol tests:

```swift
@Test("mirrorStartRequest round-trips JSON")
func mirrorStartRequestRoundtrip() throws {
    let msg = Message.mirrorStartRequest(token: "abc123")
    let json = try JSONEncoder().encode(msg)
    let decoded = try JSONDecoder().decode(Message.self, from: json)
    #expect(decoded == msg)
}
```

(Add similar tests for `mirrorStop`, `mirrorError`.)

- [ ] **Step 3: Run, verify failing then passing**

Run: `swift test --filter ProtocolTests`
Expected: FAIL initially (cases not added), PASS after wiring complete.

- [ ] **Step 4: Kotlin — add cases + JSON wiring**

In `protocol/Message.kt`, add:

```kotlin
data class MirrorStartRequest(val token: String) : Message()
object MirrorStop : Message()
data class MirrorError(val reason: String) : Message()
```

Wire `type` keys (`mirror_start_request`, `mirror_stop`, `mirror_error`) and JSON serializers following existing pattern.

- [ ] **Step 5: Kotlin test**

Add to `MessageTest.kt`:

```kotlin
@Test fun `MirrorStartRequest JSON round-trip`() {
    val msg = Message.MirrorStartRequest(token = "abc123")
    val json = msg.toJson()
    val decoded = Message.fromJson(json)
    assertEquals(msg, decoded)
}
```

- [ ] **Step 6: Run tests**

Run: `cd android/Airbridge && ./gradlew :app:testDebugUnitTest`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add macos/Airbridge/Sources/Protocol/Message.swift macos/Airbridge/Tests/ProtocolTests \
  android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt \
  android/Airbridge/app/src/test/java/com/airbridge/protocol/MessageTest.kt
git commit -m "feat(mirror): mirrorStartRequest/Stop/Error messages on control channel"
```

---

### Task 6.2: Wire `MirrorService` into `AirbridgeApp` + `MirrorWindow` scene

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift`
- Create: `macos/Airbridge/Sources/AirbridgeApp/Views/MirrorWindow.swift`

- [ ] **Step 1: Construct service in `AirbridgeApp.init()`**

Add to existing `init()`:

```swift
let mirror = MirrorService(pairingTokenProvider: { pairing.currentTokenData() })
Task { try? await mirror.start() }
connection.mirrorService = mirror
```

Add `@State private var mirrorService: MirrorService` and store it.

- [ ] **Step 2: Add `currentTokenData()` helper to `PairingService`**

Whatever returns the active pairing token as `Data?` — likely a one-line getter wrapping existing storage.

- [ ] **Step 3: Create `MirrorWindow.swift`**

```swift
import SwiftUI
import Mirror

struct MirrorWindow: View {
    let mirrorService: MirrorService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MirrorRendererView(stream: mirrorService.sampleBufferStream)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Stop") {
                    Task { await mirrorService.stop() }
                }
            }
        }
        .navigationTitle("AirBridge Mirror")
    }
}
```

- [ ] **Step 4: Register the scene in `AirbridgeApp.body`**

Add (next to existing `Window` scenes):

```swift
Window("AirBridge Mirror", id: "mirror") {
    MirrorWindow(mirrorService: mirrorService)
}
.defaultSize(width: 540, height: 1170)
.windowResizability(.contentSize)
```

- [ ] **Step 5: Build**

Run: `cd macos/Airbridge && swift build`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp
git commit -m "feat(mirror): MirrorWindow scene wired into app + token provider"
```

---

### Task 6.3: `MenuBarView` — "Mirror Phone" button

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/MenuBarView.swift`

- [ ] **Step 1: Add `MenuRow`**

Between the connection-status block and the existing "Open AirBridge" `MenuRow`, add:

```swift
MenuRow(title: L10n.isPL ? "Mirror telefon" : "Mirror Phone", systemImage: "iphone.gen3.radiowaves.left.and.right") {
    let token = connectionService.currentPairingTokenString()
    Task { try? await connectionService.send(.mirrorStartRequest(token: token)) }
    openWindow(id: "mirror")
    NSApp.activate(ignoringOtherApps: true)
}
```

(`currentPairingTokenString()` returns the same token used at pairing time, base64-encoded — already exists or trivially added on `ConnectionService`.)

- [ ] **Step 2: Build**

Run: `cd macos/Airbridge && swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/MenuBarView.swift
git commit -m "feat(mirror): Mirror Phone button in MenuBarView"
```

---

### Task 6.4: Android handles `MirrorStartRequest` → launches `MirrorActivity`

**Files:**
- Modify: the Android-side message router (the existing class that dispatches `Message`s received from Mac — locate via `grep "is Message\."` in WS-related files)

- [ ] **Step 1: Locate router**

Run: `grep -rn "is Message\." android/Airbridge/app/src/main`. The class with the `when (msg)` dispatch is the router.

- [ ] **Step 2: Add branch**

```kotlin
is Message.MirrorStartRequest -> {
    val resolved = currentResolvedMacEndpoint() // existing — returns host + ports
    val mirrorPort = resolved.mirrorPort
    if (mirrorPort == null) return@when  // Mac running an old version

    val intent = Intent(context, MirrorActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        putExtra(MirrorActivity.EXTRA_HOST, resolved.host)
        putExtra(MirrorActivity.EXTRA_PORT, mirrorPort)
        putExtra(MirrorActivity.EXTRA_TOKEN, /* base64-decode msg.token */ tokenBytes(msg.token))
    }
    context.startActivity(intent)
}
is Message.MirrorStop -> {
    context.startService(Intent(context, MirrorService::class.java).setAction(MirrorService.ACTION_STOP))
}
is Message.MirrorError -> {
    /* logged only — Mac will show its own alert */
}
```

- [ ] **Step 3: Build**

Run: `cd android/Airbridge && ./gradlew :app:assembleDebug`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add android/Airbridge/app/src/main
git commit -m "feat(mirror): Android router launches MirrorActivity on MirrorStartRequest"
```

---

## M7 — Integration

### Task 7.1: Swift integration test — fake Android client

**Files:**
- Create: `macos/Airbridge/Tests/MirrorTests/Fixtures/sample_h264_1080p.bin` (recorded once on phone, committed)
- Create: `macos/Airbridge/Tests/IntegrationTests/MirrorIntegrationTests.swift`

- [ ] **Step 1: Capture fixture**

On the phone (manual, one-time): run `MirrorService` against a script that captures the byte stream to disk. Commit the resulting `~3 MB` file (5 seconds of 1080p60).

- [ ] **Step 2: Write integration test**

```swift
import Testing
import Foundation
import CoreMedia
@testable import Mirror
@testable import AirbridgeApp

@Suite("Mirror end-to-end (Mac side, fake Android)")
@MainActor
struct MirrorIntegrationTests {

    @Test("Server accepts HELLO with valid token, decodes fixture frames")
    func endToEnd() async throws {
        let token = Data(repeating: 0xAB, count: 16)
        let service = MirrorService(pairingTokenProvider: { token })
        try await service.start()
        let port = service.actualPort!

        let url = URL(string: "ws://127.0.0.1:\(port)/")!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()

        // Send HELLO
        let hello = MirrorMessage.hello(token: token, screenWidth: 1080, screenHeight: 2376, orientation: 0)
        try await task.send(.data(hello.encode()))

        // Stream fixture as VIDEO_CONFIG + VIDEO_FRAMEs
        let fixtureURL = Bundle.module.url(forResource: "sample_h264_1080p", withExtension: "bin")!
        let raw = try Data(contentsOf: fixtureURL)
        let nalus = NALUParser.splitAnnexB(raw)

        // First SPS+PPS
        let sps = nalus.first { NALUParser.naluType($0) == 7 }!
        let pps = nalus.first { NALUParser.naluType($0) == 8 }!
        try await task.send(.data(MirrorMessage.videoConfig(sps: sps, pps: pps).encode()))

        // Frames
        var pts: UInt64 = 0
        for nalu in nalus where NALUParser.naluType(nalu) != 7 && NALUParser.naluType(nalu) != 8 {
            try await task.send(.data(MirrorMessage.videoFrame(presentationTimestampUs: pts, naluBytes: nalu).encode()))
            pts += 16_666 // 60fps
        }

        // Wait for at least one decoded frame
        let firstSample = try await withTimeout(seconds: 5) {
            for await sample in service.sampleBufferStream {
                return sample
            }
            throw URLError(.timedOut)
        }
        #expect(CMSampleBufferGetFormatDescription(firstSample) != nil)

        await service.stop()
    }
}

// helper not shown — `withTimeout` straightforward Task.race wrapper.
```

- [ ] **Step 3: Run, verify pass**

Run: `cd macos/Airbridge && swift test --filter MirrorIntegrationTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add macos/Airbridge/Tests/MirrorTests/Fixtures macos/Airbridge/Tests/IntegrationTests/MirrorIntegrationTests.swift
git commit -m "test(mirror): end-to-end integration test with H.264 fixture"
```

---

### Task 7.2: Manual smoke test on real Z Fold 7 + Mac

**Files:** none — checklist in PR description.

- [ ] **Step 1: Run `dev-install.sh` on Mac**

```bash
bash scripts/dev-install.sh
```

- [ ] **Step 2: Build + install Android APK on Z Fold 7**

```bash
cd android/Airbridge && ./gradlew :app:installDebug
```

- [ ] **Step 3: Pair phone if not already paired (existing flow)**

- [ ] **Step 4: Click "Mirror Phone" in Mac MenuBar**

Expected: Phone shows `MediaProjection` permission dialog. Tap "Start now". Mac opens `MirrorWindow`. Phone screen visible within ~2 s.

- [ ] **Step 5: Verify smoke checklist**

- Frames flowing for at least 5 minutes without freeze
- Latency feels <150 ms (eyeball test: tap on phone, sync on Mac)
- Closing Mac window stops phone foreground service (notification dismisses)
- Re-opening Mac window after stop reconnects cleanly
- 1080p quality looks crisp; no banding or block artifacts on motion

- [ ] **Step 6: If all green, mark Plan A done**

```bash
git tag mirror-mvp-plan-a
```

---

## What Plan B will add

- `RECONFIGURE` message + quality picker
- `INPUT_*` messages + `MirrorAccessibilityService`
- Mac mouse / keyboard event capture + INPUT message generation
- Reconnect overlay with exponential backoff (Mac UI)
- Accessibility-onboarding flow on Android (deeplink to Settings)
- Permission-denied alert + `mirrorError` handling on Mac
- Screen-off / app-backgrounded `STATUS` overlays
