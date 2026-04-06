<p align="center">
  <img src="docs/logo.png" alt="Airbridge" width="120" height="120" style="border-radius: 24px;" />
</p>

<h1 align="center">Airbridge</h1>

<p align="center">
  <strong>Your phone and Mac, finally on the same team.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26+-black?logo=apple" />
  <img src="https://img.shields.io/badge/Android-10+-3DDC84?logo=android&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/Kotlin-2.0-7F52FF?logo=kotlin&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-blue" />
  <img src="https://img.shields.io/github/v/release/negativepl/airbridge" />
</p>

<p align="center">
  <a href="https://github.com/negativepl/airbridge/releases/latest">Download Latest Release</a>
</p>

---

## What is Airbridge?

Airbridge connects your Android phone with your Mac over your local Wi-Fi network. Clipboard sync, file transfers, photo gallery browsing, SMS — all without cables, accounts, or cloud services. **Your data never leaves your home network.**

This is an open-source alternative to apps like AirDrop, KDE Connect, or Intel Unison — built specifically for the Android + macOS combination that Apple ignores.

---

## Tech Stack

| | macOS | Android |
|---|---|---|
| **Language** | Swift 6.2 (strict concurrency) | Kotlin 2.0 |
| **UI** | SwiftUI + Liquid Glass (macOS 26) | Jetpack Compose + Material 3 |
| **Networking** | Network.framework (NWListener) | OkHttp WebSocket |
| **Discovery** | Bonjour / mDNS (NWListener.service) | NSD (NsdManager) |
| **File Transfer** | HTTP upload (URLSession) | HTTP server (ServerSocket) + HTTP upload (OkHttp) |
| **Crypto** | CryptoKit (Ed25519) | AndroidX Security |
| **Camera** | — | CameraX + ML Kit (QR scanning) |
| **Architecture** | MVVM, SPM, @Observable | MVVM, Foreground Service, StateFlow |
| **Min version** | macOS 26 (Tahoe) | Android 10 (API 29) |
| **Target SDK** | — | API 36 (Android 16) |
| **Build** | Swift Package Manager | Gradle + Kotlin DSL |

---

## Features

### Clipboard Sync
Copy text on your phone, paste on your Mac — and vice versa. Works automatically in the background. Supports plain text and HTML.

You can also send selected text directly from any Android app:

1. **Select text** in any app (browser, notes, messages...)
2. Tap **"Send to Mac"** in the text selection menu (the floating toolbar that appears)
3. The text is instantly sent to your Mac's clipboard

> **Note:** Some apps may not show "Send to Mac" by default. If you don't see it:
> Long-press selected text → tap **⋮ More** → **Manage apps** → enable **Airbridge**.
> After that, "Send to Mac" will appear in the text selection menu.

### File Transfer
- **Android → Mac**: Use the Share Sheet or the in-app Send button. Files are uploaded via HTTP directly to your Mac.
- **Mac → Android**: Drag & drop files onto the Send tab, or click to select. Mac asks for permission first — Android shows an accept/reject prompt before any file is transferred.
- **Speed**: Direct HTTP transfer over your local network. No chunking, no base64, no cloud relay. Limited only by your Wi-Fi speed.

### Photo Gallery
Browse your phone's entire photo library from your Mac. Thumbnails load on scroll, and you can download originals in full resolution. Photos are sent directly — they don't go through any server.

### SMS Messages
Read all your SMS conversations on your Mac. Send replies directly. Full chat bubble UI with contact name resolution. Short codes (automated messages) are detected and blocked from replying.

### Security & Privacy
- **Ed25519 key pairs** — Each device generates a cryptographic identity on first launch.
- **QR code pairing** — One-time scan to exchange public keys. No accounts, no registration.
- **Signature authentication** — Every reconnection is verified with a signed timestamp. Replay window: 30 seconds.
- **Local only** — All traffic stays on your Wi-Fi network. No internet connection required. No telemetry, no analytics, no tracking.
- **Open source** — Every line of code is auditable. MIT license.

### Auto-discovery
No IP addresses, no manual configuration. Mac advertises itself via Bonjour/mDNS, and Android discovers it automatically using NSD. If your devices are on the same Wi-Fi, they will find each other.

### Multi-device
Pair multiple phones with one Mac, or one phone with multiple Macs. Each pairing is independent and uses its own key pair.

---

## Download

Get the latest release from the [Releases](https://github.com/negativepl/airbridge/releases/latest) page:

| Platform | File | Notes |
|---|---|---|
| **macOS** | `Airbridge.dmg` | Drag to Applications. Requires macOS 26+. |
| **Android** | `Airbridge.apk` | Install manually. Enable "Install from unknown sources". |

The APK is signed with a debug key — it won't update from Google Play, but it works on any Android 10+ device.

---

## How It Works

```
┌──────────────┐       Local Wi-Fi       ┌──────────────┐
│    macOS     │◄──────────────────────►│   Android    │
│   (Server)   │   WebSocket + HTTP     │   (Client)   │
└──────────────┘                         └──────────────┘
```

1. **Mac** starts a WebSocket server (port 8765) and HTTP server (port 8766)
2. **Mac** advertises itself via Bonjour as `_airbridge._tcp`
3. **Android** discovers the service via NSD and connects over WebSocket
4. **Android** authenticates with its Ed25519 key pair
5. **Both** exchange messages over WebSocket (clipboard, SMS, gallery, control)
6. **Files** are transferred via HTTP POST — Android → Mac on port 8766, Mac → Android on port 8767

### Pairing (one-time)

1. Open Airbridge on your Mac → **Settings** → **Add New Device**
2. Open Airbridge on your phone → scan the QR code
3. Done — devices are paired and will auto-connect on the same Wi-Fi

### File Transfer Protocol

Mac → Android follows a consent-based flow:

1. Mac sends `fileTransferOffer` (filename, size, type) via WebSocket
2. Android shows a notification: **"Mac wants to send you a file"** with Accept / Reject buttons
3. User taps **Accept** → Android sends `fileTransferAccept` → Mac uploads via HTTP
4. User taps **Reject** → Android sends `fileTransferReject` → nothing is transferred

Android → Mac uploads directly via HTTP POST — no confirmation needed (Mac always accepts from paired devices).

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
./scripts/bump-version.sh patch   # 1.2.0 → 1.2.1
./scripts/bump-version.sh minor   # 1.2.0 → 1.3.0
./scripts/bump-version.sh major   # 1.2.0 → 2.0.0
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
                    ├── Networking    — WebSocket server, HTTP upload server
                    ├── Clipboard     — NSPasteboard monitoring
                    ├── FileTransfer  — File chunking, assembly
                    ├── Pairing       — QR generation, key exchange
                    └── AirbridgeSecurity — Ed25519 keys, device identity
```

- **Swift 6** language mode with strict `Sendable` concurrency
- **Liquid Glass** UI throughout (macOS 26 native glass effects)
- **Modular SPM package** — 6 library targets, 1 executable, 8 test targets

### Android — Service + Compose

```
UI (Jetpack Compose + Material 3)
  └── MainViewModel (AndroidViewModel)
        └── AirbridgeService (Foreground Service)
              ├── WebSocketClient     — OkHttp WebSocket
              ├── HttpFileUploader    — HTTP POST to Mac
              ├── HttpFileServer      — HTTP server for receiving from Mac
              ├── NsdDiscovery        — Bonjour/mDNS discovery
              ├── ClipboardSync       — System clipboard monitoring
              ├── GalleryProvider     — MediaStore queries
              ├── SmsProvider         — SMS ContentProvider
              └── KeyManager          — Ed25519 key generation
```

- **compileSdk 36** (Android 16) with `Notification.ProgressStyle`
- **R8/ProGuard** minification — release APK is ~25 MB (vs 83 MB debug)

### Protocol

25 message types over JSON-encoded WebSocket:

| Category | Messages |
|---|---|
| Clipboard | `clipboard_update` |
| File Transfer | `file_transfer_offer`, `file_transfer_accept`, `file_transfer_reject`, `file_transfer_start`, `file_chunk`, `file_chunk_ack`, `file_transfer_complete` |
| Authentication | `pair_request`, `pair_response`, `auth_request`, `auth_response` |
| Gallery | `gallery_request`, `gallery_response`, `gallery_thumbnail_request`, `gallery_thumbnail_response`, `gallery_download_request` |
| SMS | `sms_conversations_request/response`, `sms_messages_request/response`, `sms_send_request/response` |
| Utility | `ping`, `pong` |

---

## Android Permissions

Every permission is explained during onboarding. All are optional — the app works with reduced functionality if you decline.

| Permission | Purpose |
|---|---|
| `POST_NOTIFICATIONS` | Show file transfer progress and incoming file requests |
| `READ_MEDIA_IMAGES` | Browse your photo gallery from Mac |
| `READ_SMS` / `SEND_SMS` | Browse and send SMS from Mac. Messages stay on your phone. |
| `READ_CONTACTS` | Show contact names instead of phone numbers in SMS |
| `CAMERA` | Scan QR code for pairing |
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
│   │   ├── Networking/         # WebSocket + HTTP servers
│   │   ├── Clipboard/          # NSPasteboard monitor
│   │   ├── FileTransfer/       # File chunking + assembly
│   │   ├── Pairing/            # QR code generation
│   │   └── AirbridgeSecurity/  # Ed25519 + device identity
│   ├── Tests/                  # Unit + integration tests
│   └── Package.swift           # SPM manifest (swift-tools-version 6.2)
├── scripts/
│   ├── bump-version.sh         # Version bumping across platforms
│   └── release.sh              # Build + GitHub release automation
├── docs/
│   └── protocol.md             # Protocol specification
└── LICENSE                     # MIT
```

---

## FAQ

**Does it work without internet?**
Yes. Airbridge only needs a local Wi-Fi network. No internet, no cloud, no accounts.

**Is it safe?**
All communication uses Ed25519 signed authentication. Data never leaves your network. The code is open source — audit it yourself.

**Why not Bluetooth?**
Wi-Fi is orders of magnitude faster. File transfers run at your full Wi-Fi speed (typically 20-50 MB/s on local network).

**Why is there a "Running in background" notification on Android?**
Android requires foreground services to show a notification. You can hide it: **Settings → Notifications → "Hide background notification"** — this opens the system channel settings where you can disable it. File transfer notifications will still work.

**Does it work with iOS?**
No. Airbridge is designed for the Android + macOS combination. If you have an iPhone, use AirDrop.

**Can I send files from Mac to Android?**
Yes. Mac sends a transfer offer first — your phone shows an accept/reject notification. Files are only transferred after you explicitly accept.

---

## Credits

- **Author** — [Marcin Baszewski](https://github.com/negativepl)
- **AI** — Built with [Claude Opus 4.6](https://claude.ai) by Anthropic

## License

MIT License — see [LICENSE](LICENSE) for details.
