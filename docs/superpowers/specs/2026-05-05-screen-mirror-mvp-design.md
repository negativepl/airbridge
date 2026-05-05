# Screen Mirror MVP — Design

**Date:** 2026-05-05
**Status:** Approved, ready for implementation plan
**Scope:** MVP for screen mirroring + remote control between Android phone and macOS app, integrated into AirBridge.

## Goal

Build an Apple-iPhone-Mirroring-style feature for Mac + Android: user opens a window on Mac that shows the phone's screen live, and can interact with the phone using Mac's mouse and keyboard. Owns the full pipeline (no scrcpy / ADB dependency) so the user only grants screen-recording permission once and is set — no developer-mode setup.

The motivating use case: rather than picking up the phone, the user sees and replies to messages, scrolls Instagram, etc. directly from the Mac. Built on top of AirBridge's existing pairing / discovery / transport stack, not as a separate app.

## Non-goals (explicitly out of MVP)

- DeX integration (Phase 2 stretch — Galaxy-only, requires DeX to be manually started by user)
- Audio mirroring (Phase 2)
- UDP/QUIC transport (Phase 2 — TCP is enough on LAN; architecture leaves the door open)
- Custom IME fallback for text injection (Phase 2 — only needed if Accessibility text injection is blocked by an app)
- iOS support (impossible with current stack — Apple's Continuity is closed)
- Internet / NAT-traversed mirroring (LAN only)

## Architecture overview

Mirror is a **separate WebSocket connection** from the existing clipboard / file-transfer channel. The existing transport is a `WebSocketServer` actor (Mac, on `Network` framework with `NWProtocolWebSocket`) on port 8765, paired with OkHttp `WebSocket` client on Android. Mirror reuses that infrastructure: a **second `WebSocketServer` instance on port 8766**, dedicated to mirror traffic only.

Both channels share auth (one pairing token, validated via `PairingService`) and discovery (one mDNS Bonjour service `_airbridge._tcp`). The mirror port is advertised in the existing Bonjour TXT record alongside `http_port`, as a new `mirror_port` key — phone reads both ports from the same Bonjour resolution.

Why a separate connection rather than multiplexing on 8765: bandwidth isolation. A 500 MB file transfer on 8765 cannot starve mirror video frames of throughput, and vice versa. Each WebSocket has independent TCP-level flow control.

Initiation is a JSON message over the **existing** 8765 control channel (`mirrorStartRequest`). Once the phone gets the request and the user grants `MediaProjection` permission, the phone opens the second WebSocket to `ws://<mac-ip>:8766/` and starts streaming.

**Why WebSocket and not raw TCP** for mirror: consistency with existing transport, no new framing code (WebSocket binary frames already give us length-prefixed messages), free `ping/pong` heartbeat (`autoReplyPing = true`), and the existing `WebSocketServer` already exposes the `onBinaryMessage` callback we need. Custom TCP framing on a side channel would be a shortcut, not a native solution.

### Direction of traffic

Following the existing AirBridge constraint that **Mac cannot initiate outbound TCP to local IPs** (ad-hoc signed app + macOS Local Network Privacy silently blocks it), the phone is the connecting party here too:

- **Mac is server** — listens on 7711.
- **Phone is client** — connects after permission granted.
- Both video frames (phone → Mac) and control events (Mac → phone) flow over the same socket bidirectionally.

## Components

### macOS (Swift)

| Component | Path | Responsibility |
|---|---|---|
| `Mirror` SPM target | `Sources/Mirror/` | Pure logic, testable in isolation: H.264 NALU parser, `VTDecompressionSession` wrapper, wire-protocol encode/decode, control-event encoder. Knows nothing about AirBridge specifics. |
| `MirrorService` | `Sources/AirbridgeApp/Services/MirrorService.swift` | Lifecycle (`start()`/`stop()`), owns a second `WebSocketServer` actor instance on port 8766, validates handshake against `PairingService`, holds connected client state. Handoff to `Mirror` for decoding. |
| `MirrorWindow` (SwiftUI scene) | `Sources/AirbridgeApp/Views/MirrorWindow.swift` | Window scene `id="mirror"`. Wraps `AVSampleBufferDisplayLayer` via `NSViewRepresentable`. Toolbar: Stop, Always-on-top toggle, Quality picker. Resizable, content-aspect-locked. |
| `MirrorWindowController` | same file or sibling | Mouse → `INPUT_TAP` / `INPUT_SWIPE` (drag = swipe), keyboard → `INPUT_TEXT` (printables, batched ~50 ms) + `INPUT_KEY` (Backspace, Enter, Esc, arrows). |
| Menu integration | `MenuBarView.swift`, main window | "Mirror" button → triggers `mirrorStartRequest` JSON on the existing 7710 channel. |

### Android (Kotlin)

| Component | Path | Responsibility |
|---|---|---|
| `MirrorService` (Foreground Service) | `app/src/main/java/com/airbridge/mirror/MirrorService.kt` | Foreground-service of type `mediaProjection`. Holds `MediaProjection` token, owns encoder + socket. Foreground notification with Stop action. |
| `ScreenEncoder` | `app/.../mirror/ScreenEncoder.kt` | `MediaProjection` → `VirtualDisplay` → `MediaCodec` H.264 hardware encoder. Outputs NALU + `MediaFormat` (SPS/PPS) callbacks. Hardware encoder mandatory; software fallback only if device lacks H.264 hw (rare). |
| `MirrorClient` | `app/.../mirror/MirrorClient.kt` | Owns the OkHttp `WebSocket` connection to Mac on port 8766. Pushes encoder output as binary frames (`VIDEO_CONFIG`, then `VIDEO_FRAME`s). Receives `INPUT_*` events as binary frames and forwards via in-process `BroadcastReceiver` to the Accessibility service. |
| `MirrorAccessibilityService` | `app/.../mirror/MirrorAccessibilityService.kt` | Standalone `AccessibilityService`. Receives input events from `MirrorClient`, calls `dispatchGesture(...)` for taps/swipes and `performAction(ACTION_SET_TEXT)` / `paste` for text. |
| `MirrorActivity` | `app/.../mirror/MirrorActivity.kt` | Short-lived. Only purpose: receive `MediaProjection` permission result (Android requires an Activity for `MediaProjectionManager.createScreenCaptureIntent()`). |

**AndroidManifest changes:**
- Permissions: `FOREGROUND_SERVICE_MEDIA_PROJECTION`, `BIND_ACCESSIBILITY_SERVICE`, `POST_NOTIFICATIONS` (already required for transfers, but reaffirmed).
- `<service>` for `MirrorService` (`foregroundServiceType="mediaProjection"`) and `MirrorAccessibilityService`.
- `<activity>` for `MirrorActivity` (no launcher entry).

### Module boundaries

- `Mirror` (Swift) does not depend on `AirbridgeApp`. Can be unit-tested by feeding NALU bytes from a fixture file and asserting the decoder produces frames.
- `MirrorService` (Mac) knows pairing + transport but not decoding internals.
- Android: `ScreenEncoder` knows nothing about networking; `MirrorClient` knows nothing about encoding; `MirrorAccessibilityService` knows neither — three loosely coupled units, communicating through narrow interfaces.

## Wire protocol (mirror channel only)

**Framing:** WebSocket binary frame, payload is `[1 B type][N B payload]`. WebSocket already provides length framing per binary message, so we don't need a 4-byte length prefix on top — that would duplicate work. Binary throughout, **not JSON** — base64-wrapping H.264 frames in JSON would be a shortcut. JSON stays on the existing 8765 control channel; binary stays on the 8766 mirror channel.

| Type | Direction | Payload |
|---|---|---|
| `0x01 HELLO` | Phone → Mac | 16 B pairing token + 4 B screen_width + 4 B screen_height + 1 B orientation |
| `0x02 HELLO_ACK` | Mac → Phone | 4 B target_bitrate_bps + 1 B target_fps + 1 B keyframe_interval_s + 4 B target_width + 4 B target_height |
| `0x03 RECONFIGURE` | Mac → Phone | Same payload as `HELLO_ACK`. Phone tears down `ScreenEncoder` and `VirtualDisplay`, re-creates with new params, emits fresh `VIDEO_CONFIG` + IDR. Used by the quality picker to switch resolution / bitrate without dropping the session. |
| `0x10 VIDEO_CONFIG` | Phone → Mac | SPS NALU + PPS NALU. Sent before any `VIDEO_FRAME`, and again after every `RECONFIGURE`. `VTDecompressionSession` requires SPS/PPS to construct the format description. |
| `0x11 VIDEO_FRAME` | Phone → Mac | 8 B PTS (microseconds, monotonic) + raw NALU bytes (one frame per message; multi-NALU frames concatenated with start codes) |
| `0x20 INPUT_TAP` | Mac → Phone | 4 B float x_norm (0..1) + 4 B float y_norm (0..1) |
| `0x21 INPUT_SWIPE` | Mac → Phone | 4 B x1_norm + 4 B y1_norm + 4 B x2_norm + 4 B y2_norm + 4 B duration_ms |
| `0x22 INPUT_KEY` | Mac → Phone | 4 B Android keycode + 4 B modifier flags |
| `0x23 INPUT_TEXT` | Mac → Phone | 4 B UTF-8 byte length + UTF-8 string |
| `0x30 STATUS` | Phone → Mac | 1 B enum: `screen_off=1`, `app_backgrounded=2`, `accessibility_disabled=3`, `encoder_error=4`, `accessibility_blocked=5` (FLAG_SECURE) |

Coordinates are **normalized** (0..1) so changing display dimensions on either side doesn't break things.

### Auth

`HELLO` carries the pairing token already known to both devices via `PairingService`. Mac validates: bad token → `close()` immediately, no retry, no error message back (anti-bruteforce). Good token → `HELLO_ACK` with quality params and stream begins.

## Target quality

- **Resolution:** 1080p default (configurable in toolbar to 480p / 720p / 1080p). Galaxy Z Fold 7's Snapdragon 8 Gen 4 hardware encoder handles 1080p60 trivially; Mac Apple Silicon decodes it without breaking sweat. 1080p chosen over 1440p because perceptual gain on a Mac-window-sized display is marginal vs. the 2× bandwidth cost.
- **Frame rate:** 60 fps target. Encoder may drop frames under thermal throttling, but the wire format is happy with variable cadence.
- **Bitrate:** 12 Mbps default at 1080p60 (eliminates visible artifacts on motion / scrolling). Scales with resolution: 720p → 6 Mbps, 480p → 2.5 Mbps. Adaptive step-down on encoder throttling: drop in 25 % steps until stable.
- **Codec:** H.264 main profile (universal hardware decode on Apple Silicon, supports the low-latency flags below).
- **Latency budget:** end-to-end **<150 ms** on Wi-Fi.
- **Keyframe interval:** 2 s (recovery vs. bandwidth tradeoff).

### Low-latency configuration (matters for the user-visible "responsiveness" feel)

Without these flags the pipeline accumulates frames in encoder/decoder buffers and produces the dreaded "controlling a screen 10 frames behind reality" feel. Native APIs explicitly support real-time use, so we use them.

**Android `MediaCodec` (encoder):**
- `MediaFormat.KEY_LOW_LATENCY = 1` (API 30+, supported on Z Fold 7) — forces no B-frames, minimum encoder pipeline depth
- `MediaFormat.KEY_OPERATING_RATE = Short.MAX_VALUE` — hint to scheduler to run encoder as fast as possible, no power-save throttling
- `MediaFormat.KEY_PRIORITY = 0` — realtime priority for the encoder thread
- `MediaFormat.KEY_BITRATE_MODE = BITRATE_MODE_CBR` — predictable bandwidth, no rate-control spikes that hurt latency

**Mac `VTDecompressionSession` (decoder):**
- `kVTDecompressionPropertyKey_RealTime = kCFBooleanTrue` — VideoToolbox real-time mode; skips frames rather than queuing if it can't keep up
- `kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder = kCFBooleanTrue` — force hardware path
- `kVTDecompressionPropertyKey_MaximizePowerEfficiency = kCFBooleanFalse` — opposite of low latency, explicitly off

**`AVSampleBufferDisplayLayer` (renderer):**
- Sample buffers enqueued with `presentationTimeStamp = .invalid` → immediate display, no playback-timing buffering
- `controlTimebase` not set (so the layer doesn't gate on a wall-clock schedule)

**Network:** No application-level jitter buffer. On a stable LAN this wins on latency; if Wi-Fi gets choppy we'd see frame drops, not stalls — better feel than buffering.

## UX flows

### Start mirror

1. User clicks "Mirror" in `MenuBarView` (or main window button).
2. Mac sends `mirrorStartRequest` JSON over the **existing** 8765 control channel.
3. Phone receives request, posts a system notification "AirBridge wants to mirror your screen", then launches `MirrorActivity` which immediately requests `MediaProjection` permission via the system dialog.
4. User taps "Start now" in the dialog.
5. Phone starts `MirrorService` foreground service, opens OkHttp WebSocket to `ws://<mac-ip>:8766/` (mac IP from existing Bonjour resolution, mirror port from the `mirror_port` TXT record), sends `HELLO` as the first binary frame.
6. Mac validates token, replies `HELLO_ACK` with quality params, opens `MirrorWindow`.
7. Phone receives ACK, starts `ScreenEncoder`, sends `VIDEO_CONFIG`, then begins `VIDEO_FRAME` stream as binary frames.
8. Mac decodes and renders.

### First-time Accessibility onboarding

Triggered the first time the user starts a mirror session:

- Android shows a custom dialog: *"AirBridge needs Accessibility permission to send taps and typing back to your phone. You can enable it now or run mirror in view-only mode."*
- "Enable" → deeplinks to `Settings → Accessibility → AirBridge → Enable`.
- "Skip" → mirror runs view-only; Mac window shows a persistent banner *"Enable Accessibility on phone to control"* with a button that re-triggers the deeplink.

### Stop mirror

Either side initiates:
- **Mac:** user closes `MirrorWindow` → `MirrorService` sends `mirrorStop` JSON over 7710 → Android kills `MirrorService` foreground service, notification dismisses.
- **Phone:** user taps Stop in foreground notification → service stops, socket closes → Mac sees disconnect, closes window after a short "Reconnecting..." wait that times out.

### Mac window behavior

- `MirrorWindow` (SwiftUI scene `id="mirror"`)
- Default size 360×780 (Galaxy Z Fold 7 closed-display proportions; aspect locked to phone's reported `screen_width × screen_height`)
- Toolbar: **Stop**, **Always-on-top** (`window.level = .floating`), **Quality** dropdown (480p / 720p / 1080p — sends `RECONFIGURE` over the mirror channel; encoder restarts on phone with the new resolution/bitrate without closing the session)
- Mouse in content area → `INPUT_TAP` (click) / `INPUT_SWIPE` (drag, mapped to a single swipe with duration = drag time)
- Keyboard when window focused → `INPUT_TEXT` for printable characters (batched every ~50 ms) + `INPUT_KEY` for special keys (Backspace, Enter, Esc, arrows, Tab)

## Error handling and edge cases

### Connection

- **Phone disconnect** (network blip, phone sleeps, WebSocket close): Mac shows a "Reconnecting..." overlay; auto-retry with exponential backoff 1 s → 2 s → 4 s → 8 s → 16 s. After 5 failed attempts, give up and close the window with "Disconnected. Try again?".
- **Mac window closed**: send `mirrorStop` JSON on 8765, Android terminates `MirrorService`, foreground notification dismisses.
- **Phone killed / powered off**: Mac sees socket close, follows the disconnect/retry path above.

### MediaProjection lifecycle

- **Permission denied** in the system dialog → phone sends a one-shot error back over 8765, Mac closes window with an alert.
- **Phone app backgrounded**: Android 14+ pauses `MediaProjection` capture automatically. Phone sends `STATUS=app_backgrounded`. Mac shows "Phone in background, capture paused" overlay until frames resume.
- **Screen off**: no new frames for >2 s → phone sends `STATUS=screen_off`. Mac overlay "Screen off" with a "Wake phone" button that sends `INPUT_KEY KEYCODE_POWER`.

### Encoder

- `MediaCodec` exception → restart encoder with a fresh keyframe + `STATUS=encoder_error`. Three retries; then disconnect.
- Bitrate too aggressive for device (thermal throttling) → encoder throttles → adaptive step-down 5 → 3 → 1.5 Mbps.
- No hardware H.264 encoder available (very rare on modern devices) → fall back to software encoder with a UI warning. Galaxy Z Fold 7 has hardware H.264, so this is a never-in-practice path but worth implementing for cleanliness.

### Accessibility

- Service not enabled when an `INPUT_*` event arrives → no listener handles it, `MirrorClient` checks state and emits `STATUS=accessibility_disabled` once, Mac shows a persistent banner.
- App with `FLAG_SECURE` (banking apps, etc.) → `MediaProjection` returns black frames for that surface. This is an Android security feature, **not bypassable** by design — and that is correct behavior. Phone emits `STATUS=accessibility_blocked` when detected (heuristic: solid black frame for >2 s while otherwise active).

### Auth

- Bad token in `HELLO` → instant `close()`, no error response, no retry — anti-bruteforce.
- Phone not yet paired → cannot send mirror because it lacks the token; the existing `PairingService` flow gates this.

## Testing strategy

### Unit — Swift `Mirror` target

- NALU parser fed fixture files containing recorded H.264 streams; assert SPS/PPS extraction, IDR detection, NALU boundary handling.
- Wire protocol round-trip: encode every message type, decode, assert byte-exact equality of payload.
- Decoder smoke test: feed synthesized NALU into `VTDecompressionSession` wrapper, assert no crash and at least one CMSampleBuffer produced.

### Unit — Android `mirror` package

- `ScreenEncoder` with mocked `MediaProjection`: verify config callback timing (SPS/PPS arrives before frames), encoder start/stop lifecycle.
- `MirrorClient` framing: byte-exact serialization of every message type.
- `MirrorAccessibilityService` in Robolectric: feed `INPUT_TAP` / `INPUT_SWIPE` from a stub `MirrorClient` channel, assert `dispatchGesture(...)` called with correct `GestureDescription`.

### Integration — existing `IntegrationTests` Swift target

- E2E in-process: spin up `MirrorService` `WebSocketServer` on port 8766 (or random `port=0` for tests), write a fake-Android Swift client using `URLSessionWebSocketTask` that pushes `HELLO` + synthesized `VIDEO_CONFIG` + `VIDEO_FRAME`s from a fixture file. Assert Mac decoder produces frames without errors.
- Round-trip control: Mac issues `INPUT_TAP` programmatically through `MirrorService`, fake Android stub records the event, assert coordinates match (within float epsilon).

### Manual smoke (Galaxy Z Fold 7 + Mac)

- 5 minutes of continuous mirroring — no disconnects, no encoder restarts.
- Latency budget: end-to-end < 150 ms (measured with on-screen timestamp burned into a phone-side test pattern).
- Quality: 1080p60 (default) looks crisp on motion/scrolling; 720p and 480p degrade gracefully.
- Recovery: screen off → wake; app switch on phone → return; disconnect → reconnect.

## Phase 2 stretch goals (post-MVP)

- **DeX support**: When `DisplayManager` reports >1 display (DeX active), show a picker on Android: *"Stream: Phone screen / DeX desktop"*. Galaxy Z Fold 7 supports DeX, but this stays out of MVP because it requires DeX to be manually activated by the user (Samsung's `SemDesktopMode` activation API is partner-only).
- **Audio mirror**: `MediaProjection.AudioRecord` + AAC encode + new audio NALU type; Mac decode via `AVAudioEngine`.
- **UDP / QUIC transport**: For lower latency. The TCP MVP is fine on LAN; the architecture is hookable so swapping the transport class doesn't ripple.
- **Custom IME fallback** for text injection when Accessibility `ACTION_SET_TEXT` is blocked by an app. User would temporarily switch to "AirBridge keyboard" while mirroring.
