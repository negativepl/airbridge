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
  <img src="https://img.shields.io/badge/Kotlin-2.0-7F52FF?logo=kotlin&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-blue" />
  <img src="https://img.shields.io/github/v/release/negativepl/airbridge" />
</p>

<p align="center">
  <a href="https://github.com/negativepl/airbridge/releases/latest">Download Latest Release</a>
</p>

---

## What is AirBridge?

AirBridge connects your Android phone with your Mac over your local Wi-Fi network. Clipboard sync, file transfers, photo gallery browsing, SMS — all without cables, accounts, or cloud services. **Your data never leaves your home network.**

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
> Long-press selected text → tap **⋮ More** → **Manage apps** → enable **AirBridge**.
> After that, "Send to Mac" will appear in the text selection menu.

### File Transfer
- **Android → Mac**: Use the Share Sheet or the in-app Send button. Mac shows an accept/reject prompt with file name and size before the transfer starts.
- **Mac → Android**: Drag & drop files onto the Send tab, or click to select. Android shows an accept/reject notification before any file is transferred.
- **Quick Drop (macOS)**: Press `Cmd+Shift+D` from anywhere — a drop zone slides down from the top of the screen. Drop a file or folder onto it and it's instantly sent to your phone. Requires Accessibility permission for the global hotkey (configurable in Settings).
- **Unified transfer popup**: A single floating "island" at the top of the screen handles every state — waiting for acceptance, sending, complete, or rejected — with smooth in-place transitions. You can cancel a pending transfer with one click while waiting.
- **Speed**: Direct HTTP transfer over your local network. No chunking, no base64, no cloud relay. Limited only by your Wi-Fi speed.

### Photo Gallery
Browse your phone's entire photo library from your Mac. Thumbnails load on scroll in a horizontal strip. Tap any photo to open a full-screen viewer with pinch-to-zoom, pan, and rotation controls. Download originals in full resolution with one click. Photos are sent directly — they don't go through any server.

### SMS Messages
Read all your SMS conversations on your Mac. Send replies directly. Full chat bubble UI with contact name resolution. Short codes (automated messages) are detected and blocked from replying.

### Security & Privacy
- **Ed25519 key pairs** — Each device generates a cryptographic identity on first launch.
- **QR code pairing** — One-time scan to exchange public keys. No accounts, no registration.
- **Signature authentication** — Every reconnection is verified with a signed timestamp. Replay window: 30 seconds.
- **Local only** — All traffic stays on your Wi-Fi network. No internet connection required. No telemetry, no analytics, no tracking.
- **Open source** — Every line of code is auditable. MIT license.
- **SHA-256 checksums** — File integrity verified after every transfer.

### Auto-discovery
No IP addresses, no manual configuration. Mac advertises itself via Bonjour/mDNS, and Android discovers it automatically using NSD. If your devices are on the same Wi-Fi, they will find each other.

### Multi-device
Pair multiple phones with one Mac, or one phone with multiple Macs. Each pairing is independent and uses its own key pair.

### macOS System Integration
- **Menu Bar icon** — Always-visible connection status indicator in the system menu bar with quick access to the main window.
- **Launch at Login** — Optional auto-start so AirBridge is ready when you log in (configurable in Settings).
- **Sound on receive** — Audio feedback when a file or clipboard update arrives (configurable in Settings).
- **Configurable global hotkey** — Record your own keyboard shortcut for Quick Drop in Settings, or use the default.
- **Download folder** — Choose where incoming files are saved (configurable in Settings).

### Android Extras
- **Share Sheet integration** — Share files or photos from any app directly to AirBridge. The app appears as a share target and lets you pick which paired device to send to.
- **Theme selection** — Choose between System, Light, or Dark theme in Settings.
- **Onboarding wizard** — First-launch setup guides you through permissions and pairing with animated explanations.

### Localization
Both apps support **English** and **Polish**. The UI language follows your system setting.

---

## Download

> **Pre-release status:** No published binaries are currently available. Build from source — see [Building from Source](#building-from-source) below. Pre-built releases will return once the next round of UX polish is done.

Supported platforms:

| Platform | Requirement |
|---|---|
| **macOS** | macOS 26 (Tahoe) or newer, Apple Silicon |
| **Android** | Android 10 (API 29) or newer |

> **Why not on Google Play?**
> AirBridge requires a foreground service to maintain the WebSocket connection and HTTP server while the app is in the background. Google Play's [foreground service policies](https://developer.android.com/about/versions/14/changes/fgs-types-required) restrict which apps can use persistent foreground services, and our use case (local network file server + clipboard sync) doesn't fit into any of the allowed foreground service type categories. This is the same reason apps like [LocalSend](https://github.com/localsend/localsend) and [KDE Connect](https://invent.kde.org/network/kdeconnect-android) have limitations with background operation on Android. We chose to prioritize functionality over store compatibility — AirBridge works reliably in the background, which is more important than being on Google Play.

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

1. Open AirBridge on your Mac → **Settings** → **Add New Device**
2. Open AirBridge on your phone → scan the QR code
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

27 message types over JSON-encoded WebSocket:

| Category | Messages |
|---|---|
| Clipboard | `clipboard_update` |
| File Transfer | `file_transfer_offer`, `file_transfer_accept`, `file_transfer_reject`, `file_transfer_start`, `file_chunk`, `file_chunk_ack`, `file_transfer_complete` |
| Authentication | `pair_request`, `pair_response`, `auth_request`, `auth_response` |
| Gallery | `gallery_request`, `gallery_response`, `gallery_thumbnail_request`, `gallery_thumbnail_response`, `gallery_preview_request`, `gallery_preview_response`, `gallery_download_request` |
| SMS | `sms_conversations_request`, `sms_conversations_response`, `sms_messages_request`, `sms_messages_response`, `sms_send_request`, `sms_send_response` |
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

## Design Philosophy

AirBridge is built to feel native on both platforms — not like a cross-platform wrapper.

**macOS** — The app is written in SwiftUI targeting **Xcode 26 and macOS Tahoe**. It uses **Liquid Glass** effects throughout the UI (glass cards, glass buttons, native sidebar via `TabView(.sidebarAdaptable)`). The file transfer notification uses a custom **floating island popup** that slides down from the notch area, inspired by Dynamic Island — showing transfer progress, speed, and ETA in real time.

**Android** — The app is written in **Jetpack Compose with Material 3** (Material Expressive). It uses native notification channels, `Notification.ProgressStyle` (API 36) for transfer progress, and the Android text selection menu ("Send to Mac") for clipboard sharing. The onboarding wizard follows Material 3 patterns with animated page transitions and per-permission explanations.

Both apps share the same WebSocket + HTTP protocol but have completely independent, platform-native implementations. No shared runtime, no React Native, no Flutter — just Swift and Kotlin.

---

## Roadmap

Features we're planning to add:

- **Cellular file transfer** — Send files over mobile data when devices aren't on the same Wi-Fi (relay server or direct connection via WebRTC)
- **Granular sharing controls (macOS)** — Choose what you share with each device: clipboard, files, gallery, SMS. Prevent a paired device from accessing features you don't want to expose
- **Device picker on Send screen** — When multiple devices are paired, show a device selector on the Send tab instead of sending to all
- **Notification improvements** — Explore Samsung Live Notifications / Now Bar integration for file transfer progress on supported devices
- **Auto-update notifications** — Both apps will check for new versions on GitHub and notify you when an update is available, with a direct link to download
- **F-Droid listing** — Publish on F-Droid as an alternative distribution channel

Have an idea? [Open an issue](https://github.com/negativepl/airbridge/issues).

---

## FAQ

**Does it work without internet?**
Yes. AirBridge only needs a local Wi-Fi network. No internet, no cloud, no accounts.

**Is it safe?**
All communication uses Ed25519 signed authentication. Data never leaves your network. The code is open source — audit it yourself.

**Why not Bluetooth?**
Wi-Fi is orders of magnitude faster. File transfers run at your full Wi-Fi speed (typically 20-50 MB/s on local network).

**Why is there a "Running in background" notification on Android?**
Android requires foreground services to show a notification. You can hide it: **Settings → Notifications → "Hide background notification"** — this opens the system channel settings where you can disable it. File transfer notifications will still work.

**Does it work with iOS?**
No. AirBridge is designed for the Android + macOS combination. If you have an iPhone, use AirDrop.

**Can I send files from Mac to Android?**
Yes. Mac sends a transfer offer first — your phone shows an accept/reject notification. Files are only transferred after you explicitly accept.

---

## Credits

- **Author** — [Marcin Baszewski](https://github.com/negativepl)
- **AI** — Built with [Claude Opus 4.6](https://claude.ai) by Anthropic

## License

MIT License — see [LICENSE](LICENSE) for details.
