<p align="center">
  <img src="docs/logo.png" alt="AirBridge" width="120" height="120" style="border-radius: 24px;" />
</p>

<h1 align="center">AirBridge</h1>

<p align="center">
  <strong>Your phone and Mac, finally on the same team.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26+-black?logo=apple" />
  <img src="https://img.shields.io/badge/Android-10+-3DDC84?logo=android&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/Kotlin-2.3-7F52FF?logo=kotlin&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-blue" />
  <img src="https://img.shields.io/github/v/release/negativepl/airbridge" />
</p>

<p align="center">
  <a href="https://github.com/negativepl/airbridge/releases/latest">Download Latest Release</a>
</p>

---

## What is AirBridge?

AirBridge connects your Android phone with your Mac over your local Wi-Fi network. Clipboard sync, file transfers, a full phone-storage browser, photo gallery, SMS, live Mac system monitoring, and two-way **screen mirroring with remote control** — all without cables, accounts, or cloud services. **Your data never leaves your home network.**

This is an open-source alternative to apps like Phone Link, KDE Connect, or Intel Unison — built specifically for the Android + macOS combination that Apple ignores.

---

## Tech Stack

| | macOS | Android |
|---|---|---|
| **Language** | Swift 6.2 (strict concurrency) | Kotlin 2.3 |
| **UI** | SwiftUI + Liquid Glass (macOS 26) | Jetpack Compose + Material 3 Expressive |
| **Networking** | Network.framework (NWListener) | OkHttp WebSocket |
| **Discovery** | Bonjour / mDNS (NWListener.service) | NSD (NsdManager) |
| **File Transfer** | HTTP server (NWListener, GET/POST) | HTTP upload + pull-download (OkHttp) |
| **Screen Mirror** | VideoToolbox (VTDecompressionSession) + AVSampleBufferDisplayLayer | MediaProjection + MediaCodec (HW H.264/HEVC) |
| **Remote control** | CGEvent injection (mouse/keyboard) | AccessibilityService (gesture/text injection) |
| **Crypto** | CryptoKit (Ed25519) | java.security (Ed25519) |
| **Camera** | — | CameraX + ML Kit (QR scanning) |
| **Architecture** | MVVM, SPM, @Observable | MVVM, Foreground Service, StateFlow |
| **Min version** | macOS 26 (Tahoe) | Android 10 (API 29) |
| **Target SDK** | — | API 35 (Android 15), compileSdk 37 |
| **Build** | Swift Package Manager | Gradle 9 + AGP 9 (built-in Kotlin) |

---

## Features

### Screen Mirroring & Remote Control

AirBridge streams screens **both ways** over a dedicated low-latency video channel, with full interactive control:

- **Phone → Mac (forward)** — Mirror your Android screen into a window on the Mac and **tap to click** with your mouse to drive the phone. Taps are injected on the phone through an AccessibilityService. (Full pointer and keyboard control — drag, scroll, type, right-click — is available in the **reverse** direction, below.)
- **Mac → Phone (reverse)** — Mirror your **Mac's screen onto the phone** and control the Mac with touch: tap to click, drag to move the cursor, two-finger scroll, long-press for right-click, and the soft keyboard for text. Drive your Mac from the couch.
- **Virtual second display** — In reverse mode, the phone can act as a **second display shaped to the phone's own aspect ratio** instead of mirroring the main screen — a portable extra monitor.
- **Codecs** — Hardware **H.264** by default, with an optional **HEVC / H.265** toggle for better quality per bit. Decoded with VideoToolbox on the Mac and rendered with no jitter buffer for minimal LAN latency.
- **Per-mode quality settings** — Each mode (forward, reverse-mirror, reverse-virtual) keeps its **own** resolution, frame rate, bitrate, UI scale, and HEVC preference. Live FPS / Mbps read-outs and a pop-out window are available from the toolbar. A blurred ambient backdrop softly fills the letterbox bars around the stream.
- **Consent-gated** — On the phone, mirroring starts a foreground service and goes through the system **MediaProjection** permission prompt; nothing is captured without you tapping Allow.

### Phone File Browser

Browse your phone's **entire storage** from the Mac in a Finder-like view:

- **Navigate the whole filesystem** — Download, Documents, DCIM, WhatsApp, anything. A clickable breadcrumb path sits at the top of the window.
- **Thumbnails** — Image files get real JPEG thumbnails generated on the phone; everything else gets a type icon. Folders show a live item/size summary.
- **Download** — Pull any file to your Mac with one click, over the same fast HTTP transfer path as everything else.
- **Upload to a chosen folder** — Drag a file from Finder into the folder you have open in the browser and it lands **right there** on the phone (not just the default Downloads).
- **Access model** — Uses Android's **All Files Access** (`MANAGE_EXTERNAL_STORAGE`) for full, direct filesystem access. Granted from the onboarding wizard or Settings.

### Live Mac System Monitor

When connected, the phone shows a **Phone Link-style card for your Mac**: the Mac's wallpaper as a hero banner with computer name, model and chip, plus **live CPU load, RAM, disk usage, and battery** (with charging / AC-power state). The Mac's Home tab mirrors this back — showing the **phone's wallpaper, model, battery, storage and RAM** in a glass hero card.

### Clipboard Sync
Copy text on your phone, paste on your Mac — and vice versa. Works automatically in the background. Supports plain text and HTML.

You can also send selected text directly from any Android app:

1. **Select text** in any app (browser, notes, messages...)
2. Tap **"Send to Mac"** in the text selection menu (the floating toolbar that appears)
3. The text is instantly sent to your Mac's clipboard

> **Note:** Some apps may not show "Send to Mac" by default. If you don't see it:
> Long-press selected text → tap **⋮ More** → **Manage apps** → enable **AirBridge**.
> After that, "Send to Mac" will appear in the text selection menu.

### File Transfer
- **Android → Mac**: Use the Share Sheet or the in-app Send button. Mac shows an accept/reject prompt with file name and size before the transfer starts.
- **Mac → Android**: Drag & drop files onto the Send tab, or click to select. Android shows an accept/reject notification before any file is transferred.
- **Quick Drop (macOS)**: Press the global hotkey from anywhere (default `⌃⌥⌘A`) — a drop zone slides down from the top of the screen. Drop a file or folder onto it and it's instantly sent to your phone. Requires Accessibility permission for the global hotkey (the shortcut is configurable in Settings).
- **Unified transfer popup**: A single floating "island" at the top of the screen handles every state — waiting for acceptance, sending, complete, or rejected — with smooth in-place transitions. You can cancel a pending transfer with one click while waiting.
- **Speed**: Direct HTTP transfer over your local network. No chunking, no base64, no cloud relay. Limited only by your Wi-Fi speed.

### Photo Gallery
Browse your phone's entire photo library from your Mac. Thumbnails load on scroll in a horizontal strip. Tap any photo to open a full-screen viewer with pinch-to-zoom, pan, and rotation controls. Download originals in full resolution with one click. Thumbnails and previews stream over the control WebSocket; full-resolution downloads come over the same HTTP transfer path as files.

### SMS Messages
Read all your SMS conversations on your Mac. Send replies directly. Full chat bubble UI with contact name resolution. Short codes (automated messages) are detected and blocked from replying.

### Security & Privacy
- **Ed25519 key pairs** — Each device generates a cryptographic identity on first launch.
- **QR code pairing** — One-time scan to exchange public keys. No accounts, no registration.
- **Signature authentication** — Every reconnection is verified with a signed timestamp. Replay window: 30 seconds.
- **Token-gated mirror channel** — The video channel requires a 16-byte token derived from the paired device's key; a bad token is dropped instantly with no response.
- **Local only** — All traffic stays on your Wi-Fi network. No internet connection required. No telemetry, no analytics, no tracking.
- **Open source** — Every line of code is auditable. MIT license.
- **SHA-256 checksums** — File transfers carry a SHA-256 hash that the receiver verifies when present.

### Auto-discovery
No IP addresses, no manual configuration. Mac advertises itself via Bonjour/mDNS (including the mirror port in its TXT record), and Android discovers it automatically using NSD. If your devices are on the same Wi-Fi, they will find each other.

### Multi-device
Pair multiple phones with one Mac, or one phone with multiple Macs. Each pairing is independent and uses its own key pair.

### macOS System Integration
- **Menu Bar icon** — Always-visible connection status indicator in the system menu bar with quick access to open the main window.
- **Launch at Login** — Optional auto-start so AirBridge is ready when you log in (configurable in Settings).
- **Sound on receive** — Audio feedback when a file or clipboard update arrives (configurable in Settings).
- **Configurable global hotkey** — Record your own keyboard shortcut for Quick Drop in Settings, or use the default.
- **Download folder** — Choose where incoming files are saved (configurable in Settings).

### Android Extras
- **Material 3 Expressive UI** — The whole app runs on `MaterialExpressiveTheme` with spring-based motion, Material You dynamic color (wallpaper palette on Android 12+), a wavy progress indicator for transfers, a shape-morphing loading indicator while connecting, a connected button group for theme selection, and expressive `MaterialShapes` icon containers.
- **FAB send menu** — The Send button expands into a native expressive FAB menu (File / Photo / Clipboard) with a morphing icon.
- **Share Sheet integration** — Share files or photos from any app directly to AirBridge. The app appears as a share target and lets you pick which paired device to send to.
- **Theme selection** — Choose between System, Light, or Dark theme in Settings.
- **Onboarding wizard** — First-launch setup guides you through permissions (including All Files Access and Accessibility) and pairing with animated explanations.

### Localization
Both apps support **English** and **Polish**. The UI language follows your system setting.

---

## Download

Grab the latest signed builds from the [**Releases**](https://github.com/negativepl/airbridge/releases/latest) page:

| Platform | File | Requirement |
|---|---|---|
| **macOS** | `AirBridge.dmg` | macOS 26 (Tahoe) or newer, Apple Silicon |
| **Android** | `AirBridge.apk` | Android 10 (API 29) or newer |

> **macOS first launch:** the app is self-signed, so right-click → **Open** once to get past Gatekeeper ("unidentified developer"). Updates afterwards are friction-free — the Accessibility grant survives because the signing identity is stable.
> **Android:** allow "Install unknown apps" for your browser or file manager to install the APK.

Or build it yourself — see [Building from Source](#building-from-source) below.

> **Why not on Google Play?**
> AirBridge requires a foreground service to maintain the WebSocket connection and HTTP server while the app is in the background (and a MediaProjection foreground service for screen mirroring). Google Play's [foreground service policies](https://developer.android.com/about/versions/14/changes/fgs-types-required) restrict which apps can use persistent foreground services, and our use case (local network file server + clipboard sync + mirroring) doesn't fit into the allowed foreground service type categories. This is the same reason apps like [LocalSend](https://github.com/localsend/localsend) and [KDE Connect](https://invent.kde.org/network/kdeconnect-android) have limitations with background operation on Android. We chose to prioritize functionality over store compatibility — AirBridge works reliably in the background, which is more important than being on Google Play.

---

## How It Works

```
┌──────────────┐       Local Wi-Fi       ┌──────────────┐
│    macOS     │◄──────────────────────►│   Android    │
│   (Server)   │  WebSocket + HTTP +    │   (Client)   │
│              │     Video stream       │              │
└──────────────┘                         └──────────────┘
```

| Channel | Port | Direction | Purpose |
|---|---|---|---|
| Control WebSocket | **8765** | Phone → Mac | Clipboard, gallery, SMS, files, device info, control |
| HTTP transfer | **8766** | Phone → Mac | File transfer both ways — phone `POST`s uploads and pulls Mac → phone files via `GET /send/{id}` |
| Mirror WebSocket | **8767** | Phone → Mac | Screen mirror video + input stream (advertised as `mirror_port`) |

1. **Mac** starts a control WebSocket server (8765), an HTTP upload server (8766), and a mirror WebSocket server (8767)
2. **Mac** advertises itself via Bonjour as `_airbridge._tcp`, publishing `http_port` and `mirror_port` in its TXT record
3. **Android** discovers the service via NSD and connects over the control WebSocket
4. **Android** authenticates with its Ed25519 key pair
5. **Both** exchange JSON messages over the control channel (clipboard, SMS, gallery, files, device info, mirror control)
6. **Files** are transferred via HTTP POST; **screen frames and input events** flow over the binary mirror channel

> Because macOS quietly blocks outbound TCP to local IPs, the phone always initiates every connection — including the mirror channel. The Mac only ever listens.

### Pairing (one-time)

1. Open AirBridge on your Mac → **Settings** → **Add New Device**
2. Open AirBridge on your phone → scan the QR code
3. Done — devices are paired and will auto-connect on the same Wi-Fi

### File Transfer Protocol

Mac → Android follows a consent-based flow:

1. Mac sends `file_transfer_offer` (filename, size, type, optional destination folder) via WebSocket
2. Android shows a notification: **"Mac wants to send you a file"** with Accept / Reject buttons
3. User taps **Accept** → Android sends `file_transfer_accept` → Mac uploads via HTTP
4. User taps **Reject** → Android sends `file_transfer_reject` → nothing is transferred

Android → Mac follows the same consent flow in reverse: the phone sends `file_transfer_offer`, the Mac shows an accept/reject popup with the file name and size, and only after you accept does the phone upload via HTTP POST.

---

## Building from Source

### Requirements

| | Minimum |
|---|---|
| macOS | 26 (Tahoe) |
| Xcode | 26+ |
| Android | 10 (API 29) |
| JDK | 17+ |
| Both devices | Same Wi-Fi network |

### macOS

```bash
cd macos/Airbridge
swift build -c release
```

Binary: `.build/arm64-apple-macosx/release/AirbridgeApp`

### Android

```bash
cd android/Airbridge
./gradlew assembleRelease
```

APK: `app/build/outputs/apk/release/app-release.apk`

### Versioning

```bash
./scripts/bump-version.sh patch   # 2.0.0 → 2.0.1
./scripts/bump-version.sh minor   # 2.0.0 → 2.1.0
./scripts/bump-version.sh major   # 2.0.0 → 3.0.0
```

Updates version in `build.gradle.kts`, `Info.plist`, and app bundle simultaneously.

---

## Architecture

### macOS — MVVM with Services

```
Views (SwiftUI + Liquid Glass)
  └── ViewModels (@Observable)
        └── Services (@Observable, @MainActor)
              └── Library Modules (SPM)
                    ├── Protocol      — Message types, JSON coding
                    ├── Networking    — WebSocket server, HTTP upload server, Bonjour
                    ├── Clipboard     — NSPasteboard monitoring
                    ├── FileTransfer  — File chunking, assembly
                    ├── Mirror        — Video encode/decode, renderer, reverse pipeline
                    ├── Pairing       — QR generation, key exchange
                    └── AirbridgeSecurity — Ed25519 keys, device identity
```

- **Swift 6** language mode with strict `Sendable` concurrency
- **Liquid Glass** UI throughout (macOS 26 native glass effects)
- **7 tabs** — Home, Send, Gallery, Files, Messages, Mirror, Settings (`TabView(.sidebarAdaptable)`)
- **`MacSystemInfo`** service collects CPU/RAM/disk/battery + a downscaled wallpaper to feed the phone's monitor card

### Android — Service + Compose

```
UI (Jetpack Compose + Material 3 Expressive)
  └── MainViewModel (AndroidViewModel)
        └── AirbridgeService (Foreground Service)
              ├── WebSocketClient     — OkHttp WebSocket (control channel)
              ├── HttpFileUploader    — HTTP POST to Mac
              ├── HttpFileDownloader  — pulls Mac → phone files over HTTP
              ├── NsdDiscovery        — Bonjour/mDNS discovery (reads mirror_port)
              ├── ClipboardSync       — System clipboard monitoring
              ├── GalleryProvider     — MediaStore queries
              ├── FilesProvider       — Full filesystem listing + thumbnails (All Files Access)
              ├── SmsProvider         — SMS ContentProvider
              └── KeyManager          — Ed25519 key generation
        └── MirrorService (Foreground Service, mediaProjection)
              ├── ScreenEncoder       — Hardware H.264/HEVC via MediaCodec
              ├── MirrorClient        — Binary video/input WebSocket to Mac
              └── MirrorAccessibilityService — Injects Mac-driven input on the phone
```

- **compileSdk 37** (Android 16) with `Notification.ProgressStyle`
- **AGP 9 / Gradle 9** with AGP's built-in Kotlin (no standalone `kotlin-android` plugin)
- **R8/ProGuard** minification — release APK is ~25 MB (vs 83 MB debug)

### Protocol

**49 JSON message types** over the control WebSocket, plus a separate **binary video/input protocol** for the mirror channel:

| Category | Messages |
|---|---|
| Clipboard | `clipboard_update` |
| File Transfer | `file_transfer_offer`, `file_transfer_accept`, `file_transfer_reject`, `file_transfer_start`, `file_chunk`, `file_chunk_ack`, `file_transfer_complete` |
| Authentication | `pair_request`, `pair_response`, `auth_request`, `auth_response` |
| Gallery | `gallery_request`, `gallery_response`, `gallery_thumbnail_request`, `gallery_thumbnail_response`, `gallery_preview_request`, `gallery_preview_response`, `gallery_download_request` |
| SMS | `sms_conversations_request`, `sms_conversations_response`, `sms_messages_request`, `sms_messages_response`, `sms_send_request`, `sms_send_response` |
| Files Browser | `files_list_request`, `files_list_response`, `file_thumbnail_request`, `file_thumbnail_response`, `file_download_request`, `folder_stats_request`, `folder_stats_response`, `file_delete_request`, `file_delete_response` |
| Device Info & Monitor | `device_info_request`, `device_info_response`, `wallpaper_request`, `wallpaper_response`, `mac_info_request`, `mac_info_response`, `mac_wallpaper_request`, `mac_wallpaper_response` |
| Mirror control | `mirror_start_request`, `reverse_mirror_start`, `mirror_stop`, `mirror_error` |
| Notifications | `notification_posted` |
| Utility | `ping`, `pong` |

The mirror video stream is **not** JSON — it's a binary frame protocol (`[1B type][payload]`): `HELLO` / `HELLO_ACK` handshake, `VIDEO_CONFIG` (H.264 SPS/PPS) and `VIDEO_CONFIG_HEVC` (VPS/SPS/PPS), `VIDEO_FRAME`, a `STATUS` channel (screen off, app backgrounded, accessibility state, encoder errors), forward input (`INPUT_TAP`), and reverse input (`REVERSE_HELLO`, `REVERSE_INPUT`, `REVERSE_SCROLL`, `REVERSE_TEXT`, `REVERSE_KEY`). See [docs/protocol.md](docs/protocol.md) for the full spec.

---

## Android Permissions

Every permission is explained during onboarding. Most are optional — the app works with reduced functionality if you decline.

| Permission | Purpose |
|---|---|
| `POST_NOTIFICATIONS` | Show file transfer progress and incoming file requests |
| `MANAGE_EXTERNAL_STORAGE` | Browse and transfer files across the whole phone storage from Mac |
| `READ_MEDIA_IMAGES` | Browse your photo gallery from Mac |
| `READ_SMS` / `SEND_SMS` | Browse and send SMS from Mac. Messages stay on your phone. |
| `READ_CONTACTS` | Show contact names instead of phone numbers in SMS |
| `CAMERA` | Scan QR code for pairing |
| `FOREGROUND_SERVICE_MEDIA_PROJECTION` | Capture the screen for mirroring |
| Accessibility service | Inject Mac-driven taps, swipes and text when controlling the phone |
| `INTERNET` | Local network communication (WebSocket + HTTP) |

---

## Project Structure

```
airbridge/
├── android/Airbridge/          # Android app
│   └── app/src/main/java/com/airbridge/
│       ├── ui/                 # Compose screens + ViewModel
│       ├── service/            # AirbridgeService, WebSocket, HTTP
│       ├── protocol/           # Message types + JSON parsing
│       ├── mirror/             # MediaProjection capture, encoder, input injection
│       ├── files/              # Full filesystem provider (All Files Access)
│       ├── pairing/            # QR scanner (CameraX + ML Kit)
│       ├── gallery/            # MediaStore photo provider
│       ├── sms/                # SMS provider
│       ├── clipboard/          # Clipboard sync
│       ├── discovery/          # mDNS/NSD discovery
│       ├── security/           # Ed25519 key management
│       └── share/              # Share Sheet + text selection handler
├── macos/Airbridge/            # macOS app (SPM)
│   ├── Sources/
│   │   ├── AirbridgeApp/       # App entry, Views, ViewModels, Services
│   │   ├── Protocol/           # Shared message types
│   │   ├── Networking/         # WebSocket + HTTP servers + Bonjour
│   │   ├── Clipboard/          # NSPasteboard monitor
│   │   ├── FileTransfer/       # File chunking + assembly
│   │   ├── Mirror/             # Video encode/decode, renderer, reverse pipeline
│   │   ├── Pairing/            # QR code generation
│   │   └── AirbridgeSecurity/  # Ed25519 + device identity
│   ├── Tests/                  # Unit + integration tests
│   └── Package.swift           # SPM manifest (swift-tools-version 6.2)
├── scripts/
│   ├── bump-version.sh         # Version bumping across platforms
│   └── release.sh              # Build + GitHub release automation
├── docs/
│   ├── protocol.md             # Protocol specification
│   └── landing/                # Landing page + screenshots
└── LICENSE                     # MIT
```

---

## Design Philosophy

AirBridge is built to feel native on both platforms — not like a cross-platform wrapper.

**macOS** — The app is written in SwiftUI targeting **Xcode 26 and macOS Tahoe**. It uses **Liquid Glass** effects throughout the UI (glass cards, glass buttons, native sidebar via `TabView(.sidebarAdaptable)`). The file transfer notification uses a custom **floating island popup** that slides down from the notch area, inspired by Dynamic Island — showing transfer progress, speed, and ETA in real time. Mirrored video is decoded with VideoToolbox and rendered directly into an `AVSampleBufferDisplayLayer` for near-zero added latency.

**Android** — The app is written in **Jetpack Compose with Material 3 Expressive**: `MaterialExpressiveTheme` brings spring-physics motion to every component, transfers show a wavy progress indicator, connecting states use the shape-morphing `LoadingIndicator`, the Send FAB expands into a native FAB menu, theme selection is a connected toggle-button group, and onboarding hero icons sit in expressive `MaterialShapes` containers — the same component language Android 16 uses system-wide, with Material You dynamic color throughout. Beyond the UI it uses native notification channels, `Notification.ProgressStyle` for transfer progress, the Android text selection menu ("Send to Mac") for clipboard sharing, and hardware `MediaCodec` for low-latency screen encoding.

Both apps share the same protocol but have completely independent, platform-native implementations. No shared runtime, no React Native, no Flutter — just Swift and Kotlin.

---

## Roadmap

Features we're planning to add:

- **Cellular file transfer** — Send files over mobile data when devices aren't on the same Wi-Fi (relay server or direct connection via WebRTC)
- **Granular sharing controls (macOS)** — Choose what you share with each device: clipboard, files, gallery, SMS, screen. Prevent a paired device from accessing features you don't want to expose
- **Device picker on Send screen** — When multiple devices are paired, show a device selector on the Send tab instead of sending to all
- **Mirror audio** — Stream the phone's audio alongside the screen
- **Notification improvements** — Explore Samsung Live Notifications / Now Bar integration for file transfer progress on supported devices
- **Auto-update notifications** — Both apps will check for new versions on GitHub and notify you when an update is available, with a direct link to download
- **F-Droid listing** — Publish on F-Droid as an alternative distribution channel

Have an idea? [Open an issue](https://github.com/negativepl/airbridge/issues).

---

## FAQ

**Does it work without internet?**
Yes. AirBridge only needs a local Wi-Fi network. No internet, no cloud, no accounts.

**Is it safe?**
All communication uses Ed25519 signed authentication, and the mirror channel is gated by the same pairing token. Data never leaves your network. The code is open source — audit it yourself.

**Can I control my phone from my Mac (and vice versa)?**
Yes — both ways. Mirror the phone to the Mac and drive it with mouse + keyboard, or mirror the Mac to the phone and control it by touch. The phone can even act as a phone-shaped second display.

**Why is screen mirroring fast?**
Frames are hardware-encoded on the phone (H.264 or HEVC), streamed over a dedicated WebSocket on your LAN, and decoded with VideoToolbox into a display layer with no jitter buffer.

**Why not Bluetooth?**
Wi-Fi is orders of magnitude faster. File transfers run at your full Wi-Fi speed (typically 20–50 MB/s on local network), and screen mirroring needs the bandwidth.

**Why is there a "Running in background" notification on Android?**
Android requires foreground services to show a notification. You can hide it: **Settings → Notifications → "Hide background notification"** — this opens the system channel settings where you can disable it. File transfer notifications will still work.

**Does it work with iOS?**
No. AirBridge is designed for the Android + macOS combination. If you have an iPhone, use AirDrop.

**Can I send files from Mac to Android?**
Yes. Mac sends a transfer offer first — your phone shows an accept/reject notification. Files are only transferred after you explicitly accept, and Mac can even target a specific folder on the phone.

---

## Credits

- **Author** — [Marcin Baszewski](https://github.com/negativepl)
- **AI** — Built with [Claude Opus](https://claude.ai) by Anthropic

## License

MIT License — see [LICENSE](LICENSE) for details.
