# Airbridge

**Connect your Android phone with your Mac. Clipboard sync, file transfer, photo gallery, SMS — all local, no cloud.**

Airbridge lets you seamlessly share clipboard, transfer files, browse your phone's photo gallery, and read & send SMS — all over your local Wi-Fi network. Your data never leaves your home network.

## Features

- **Clipboard Sync** — Copy on your phone, paste on your Mac (and vice versa). Text, HTML, and images.
- **File Transfer** — Drag & drop files on Mac, use Share Sheet on Android. No cables, no cloud.
- **Photo Gallery** — Browse your phone's photos on Mac with thumbnails, metadata, and full-resolution downloads.
- **SMS Messages** — Read and send SMS from your Mac. Full conversation view with chat bubbles.
- **Secure** — Ed25519 key exchange, all traffic stays on your local network.
- **Zero Config** — Bonjour/mDNS auto-discovery. One-time QR code pairing — that's it.
- **Multi-device** — Pair multiple phones with one Mac, or one phone with multiple Macs.

## Download

Download the latest release from the [Releases](https://github.com/negativepl/airbridge/releases) page:

- **macOS** — `Airbridge.dmg` (drag to Applications)
- **Android** — `Airbridge.apk` (install manually, allow "Install from unknown sources")

## How It Works

```
┌──────────────┐       Local Wi-Fi       ┌──────────────┐
│    macOS     │◄──────────────────────► │   Android    │
│   (Server)   │     WebSocket + HTTP    │   (Client)   │
└──────────────┘                         └──────────────┘
  Clipboard ◄──────────────────────────► Clipboard
  File Drop  ◄──────────────────────────► Share Sheet
  Gallery    ◄────── Photo browsing ────► MediaStore
  Messages   ◄──────── SMS sync ────────► SMS Provider
```

Airbridge runs a WebSocket server on your Mac. Your Android phone discovers it automatically via Bonjour/mDNS and connects over your local Wi-Fi. All communication stays within your network — nothing goes through the internet.

### Pairing

1. Open Airbridge on your Mac
2. Go to **Settings** → **Add New Device**
3. Scan the QR code with the Airbridge app on your phone
4. Done — devices are now paired and will auto-connect whenever they're on the same Wi-Fi

## Building from Source

### Requirements

- macOS 14 (Sonoma) or later
- Android 10 or later
- Same Wi-Fi network
- Xcode 15+ (for macOS build)
- Android Studio or JDK 17+ (for Android build)

### macOS

```bash
cd macos/Airbridge
swift build -c release
```

The binary will be at `.build/release/AirbridgeApp`. To create an .app bundle, see the release workflow.

### Android

```bash
cd android/Airbridge
./gradlew assembleDebug
```

The APK will be at `android/Airbridge/app/build/outputs/apk/debug/app-debug.apk`.

## Architecture

### macOS — MVVM with Services

```
Views (SwiftUI)
  └── ViewModels (@Observable)
        └── Services (@Observable)
              └── Library Modules (Protocol, Networking, Clipboard, FileTransfer, Pairing, Security)
```

- **Swift 5.9+**, SwiftUI, Swift Observation (`@Observable`)
- **Network.framework** for WebSocket server
- **CryptoKit** for Ed25519 signing and verification
- Modular SPM package with 6 library targets + app target

### Android — Service + ViewModel

```
UI (Jetpack Compose + Material 3)
  └── MainViewModel
        └── AirbridgeService (Foreground Service)
              ├── WebSocketClient (OkHttp)
              ├── NsdDiscovery (mDNS)
              ├── ClipboardSync
              ├── GalleryProvider (MediaStore)
              ├── SmsProvider (Telephony)
              └── HttpFileUploader
```

- **Kotlin**, Jetpack Compose, Material 3
- **OkHttp** for WebSocket client
- **ML Kit** for QR code scanning
- **CameraX** for camera preview

### Protocol

19 message types over JSON-encoded WebSocket. See [docs/protocol.md](docs/protocol.md) for the full specification.

Key message types:
- `clipboard_update` — Bidirectional clipboard sync
- `file_transfer_start/chunk/complete` — Chunked file transfer with SHA-256 verification
- `pair_request/response` — QR-based device pairing
- `auth_request/response` — Ed25519 signature authentication
- `gallery_request/response/thumbnail` — Remote photo gallery browsing
- `sms_conversations/messages/send` — SMS sync and sending

### Android Permissions

| Permission | Why |
|---|---|
| `INTERNET` | WebSocket and HTTP communication |
| `POST_NOTIFICATIONS` | File transfer progress notifications |
| `READ_MEDIA_IMAGES` | Photo gallery browsing |
| `READ_SMS` / `SEND_SMS` | SMS reading and sending |
| `READ_CONTACTS` | Contact names in SMS conversations |
| `CAMERA` | QR code scanning for pairing |

## Project Structure

```
airbridge/
├── android/Airbridge/       # Android app (Kotlin + Compose)
│   └── app/src/main/java/com/airbridge/
│       ├── ui/              # Compose screens
│       ├── service/         # Background service
│       ├── protocol/        # Message types
│       ├── pairing/         # QR scanner
│       ├── gallery/         # Photo provider
│       ├── sms/             # SMS provider
│       └── security/        # Key management
├── macos/Airbridge/         # macOS app (Swift + SwiftUI)
│   └── Sources/
│       ├── AirbridgeApp/    # App, Services, ViewModels, Views
│       ├── Protocol/        # Message types
│       ├── Networking/      # WebSocket + HTTP server
│       ├── Clipboard/       # Clipboard monitor
│       ├── FileTransfer/    # File chunking
│       ├── Pairing/         # QR + pairing logic
│       └── AirbridgeSecurity/ # Ed25519 keys
├── docs/
│   └── protocol.md          # Protocol specification
├── LICENSE                   # MIT License
└── README.md
```

## Credits

- **Author** — [Marcin Baszewski](https://github.com/negativepl)
- **AI** — Built with [Claude](https://claude.ai) by Anthropic

## License

MIT License — see [LICENSE](LICENSE) for details.
