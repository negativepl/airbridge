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

AirBridge connects your Android phone with your Mac over local Wi-Fi. Clipboard sync, file transfers, file browsing in both directions, photo gallery, SMS, live system monitoring, Bluetooth headphone handoff, and two-way **screen mirroring with remote control** — no cables, no accounts, no cloud. All traffic is TLS-encrypted and never leaves your network.

An open-source alternative to Phone Link, KDE Connect, or Intel Unison — built specifically for the Android + macOS combination that Apple ignores. Two fully native apps (SwiftUI with Liquid Glass on macOS, Jetpack Compose with Material 3 Expressive on Android) sharing one protocol — no cross-platform wrapper.

---

## Features

### Screen Mirroring & Remote Control

Screens stream **both ways** over a dedicated low-latency video channel, with full interactive control:

- **Phone → Mac** — mirror the Android screen into a Mac window and tap to click with the mouse.
- **Mac → Phone** — mirror the Mac onto the phone and control it by touch: tap to click, drag the cursor, two-finger scroll, long-press for right-click, soft keyboard for text, plus a dedicated trackpad panel. The screen view works as a passive magnifier with pinch and double-tap zoom.
- **Virtual second display** — the phone can act as an extra monitor shaped to its own aspect ratio instead of mirroring the main screen.
- **Fast** — hardware H.264 by default with an optional HEVC toggle, decoded with VideoToolbox and rendered with no jitter buffer. Each mode keeps its own resolution, frame rate, bitrate, and quality settings.
- **Consent-gated** — mirroring on the phone goes through the system MediaProjection prompt; nothing is captured without an explicit Allow.

### File Transfer

- **Both directions, always with consent** — the receiver sees an accept/reject prompt with file name and size before any transfer starts.
- **Quick Drop (macOS)** — press a global hotkey (default `⌃⌥⌘A`) anywhere and drop a file onto the slide-down zone to send it to the phone instantly.
- **Transfer island** — a single floating popup on the Mac handles waiting, progress, completion, and rejection with live speed and ETA. Transfers can be cancelled at any point, and unanswered offers time out cleanly.
- **Fast** — direct HTTP over your LAN, limited only by Wi-Fi speed. Transfers carry a SHA-256 checksum the receiver verifies.

### File Browsing — Both Ways

- **Phone storage from the Mac** — a Finder-like browser over the phone's entire filesystem (All Files Access): breadcrumb navigation, real image thumbnails, one-click download, and drag-and-drop upload straight into the folder you have open.
- **Mac files from the phone** — a Files tab on Android browses the Mac's filesystem with smooth navigation, tap-to-download, and upload into the current folder.

### Photo Gallery

Browse the phone's photo library from the Mac. Thumbnails load on scroll, a full-screen viewer offers zoom, pan, and rotation, and originals download in full resolution with one click.

### SMS Messages

Read and reply to SMS conversations from the Mac, with contact name resolution and a chat-bubble UI. Short codes are detected and blocked from replying.

### Clipboard Sync

Copy on one device, paste on the other — automatic, in both directions, for plain text and HTML. Android additionally adds a **"Send to Mac"** action to the system text-selection menu in any app.

### Headphone Handoff

Move Bluetooth headphones between the phone and the Mac with one click — the continuity trick vendors reserve for their own ecosystems:

- **One-click transfer both ways**, coordinated over AirBridge's own channel so single-point headphones (e.g. Galaxy Buds) switch reliably instead of fighting over the link.
- **Optional switching suggestions** — when playback starts on the device without the headphones, AirBridge asks before switching. Off by default; nothing ever moves without confirmation.
- **LE Audio aware** — presence is detected from the actual audio route, not the Bluetooth link, which keeps state truthful on modern earbuds.

Known limitation: some LE Audio devices (e.g. Galaxy Buds4 Pro) may not release cleanly when handing off away from the Mac, because macOS exposes only the classic BR/EDR link to applications. Reconnect them manually on the target device if that happens.

### Live System Monitor

The phone shows a card for the connected Mac — wallpaper, model, chip, live CPU, RAM, disk, and battery. The Mac's Home tab mirrors this back with each connected phone's wallpaper, model, battery, storage, and RAM.

### Multi-Device

Pair multiple phones with one Mac (or one phone with multiple Macs) — each pairing is independent. Several phones can be connected simultaneously; an active-device switcher chooses which one the Gallery, Files, Messages, and transfers target.

### In-App Updates

Both apps check for new versions and offer a signed, one-tap update — no need to watch the Releases page.

### Everything Else

- **Auto-discovery** — Bonjour/mDNS, no IP addresses or configuration; devices on the same Wi-Fi find each other.
- **macOS integration** — menu bar status, Launch at Login, configurable hotkey, download folder and sound settings.
- **Android integration** — Share Sheet target, onboarding wizard for permissions and pairing, home dashboard with transfer statistics, Material You dynamic color.
- **Find my phone** — ring the phone from the Mac.
- **Localization** — English and Polish, following the system language.

---

## Security & Privacy

- **TLS on every channel** — control WebSocket, file transfer server, and mirror stream all run over TLS with a persistent identity generated on the Mac.
- **Certificate pinning** — the pairing QR code carries the SHA-256 fingerprint of the Mac's TLS certificate; the phone refuses to connect to anything else.
- **Ed25519 authentication** — every reconnection is verified with a signed timestamp (30-second replay window). On Android the private key is encrypted at rest via the hardware-backed AndroidKeyStore.
- **Token-gated mirror channel** — the video channel requires a pairing-derived token; a bad token is dropped instantly.
- **Local only** — no internet required, no telemetry, no analytics, no accounts.
- **Open source** — every line is auditable. MIT license.

---

## Download

Grab the latest signed builds from the [**Releases**](https://github.com/negativepl/airbridge/releases/latest) page:

| Platform | File | Requirement |
|---|---|---|
| **macOS** | `AirBridge.dmg` | macOS 26 (Tahoe) or newer, Apple Silicon |
| **Android** | `AirBridge.apk` | Android 10 (API 29) or newer |

> **macOS first launch:** the app is self-signed, so right-click → **Open** once to get past Gatekeeper. Later updates are friction-free — permissions survive because the signing identity is stable.
> **Android:** allow "Install unknown apps" for your browser or file manager.

**Why not on Google Play?** AirBridge needs persistent foreground services (local network server, clipboard sync, screen mirroring) that don't fit Google Play's [allowed foreground service categories](https://developer.android.com/about/versions/14/changes/fgs-types-required). Reliable background operation matters more than store presence.

---

## Tested On

Developed and verified on real hardware:

| Device | OS |
|---|---|
| Samsung Galaxy Z Fold7 | One UI 8.5 (Android 16) |
| OPPO Find X9 Ultra | ColorOS 16 (Android 16) |
| OPPO Find N6 | ColorOS 16 (Android 16) |
| MacBook Pro 16″ (M1 Max) | macOS 26 (Tahoe) · 27 (beta) |
| MacBook Pro 16″ (M4 Max) | macOS 26 (Tahoe) |

Other recent Android phones and Apple Silicon Macs should work too — these are just the devices the app is actively tested on.

---

## How It Works

The Mac runs three TLS servers and advertises itself via Bonjour; the phone discovers it and initiates every connection (macOS blocks outbound TCP to local IPs, so the Mac only ever listens):

| Channel | Port | Purpose |
|---|---|---|
| Control WebSocket | 8765 | Clipboard, gallery, SMS, files, device info, control messages |
| HTTPS transfer | 8766 | File uploads and downloads in both directions |
| Mirror WebSocket | 8767 | Screen video + input stream (binary protocol) |

**Pairing is a one-time QR scan**: Mac → Settings → Add New Device, scan with the phone, done. The QR code exchanges the Mac's address, its Ed25519 public key, a one-time pairing token, and the TLS certificate fingerprint the phone pins from then on. Paired devices auto-connect whenever they share a Wi-Fi network.

The full message and wire format specification lives in [docs/protocol.md](docs/protocol.md).

---

## Under the Hood

| | macOS | Android |
|---|---|---|
| **Language** | Swift 6.2 (strict concurrency) | Kotlin 2.3 |
| **UI** | SwiftUI + Liquid Glass | Jetpack Compose + Material 3 Expressive |
| **Networking** | Network.framework (TLS) | OkHttp (TLS, pinned certificate) |
| **Mirror** | VideoToolbox decode | MediaProjection + MediaCodec (HW H.264/HEVC) |
| **Remote control** | CGEvent injection | AccessibilityService |
| **Crypto** | CryptoKit (Ed25519) | java.security + AndroidKeyStore |
| **Build** | Swift Package Manager | Gradle 9 + AGP 9, targetSdk 36 |

Both apps are MVVM, fully native, and independently implemented — the protocol is the only shared piece.

---

## Building from Source

Requirements: macOS 26 with Xcode 26+, JDK 17+.

```bash
# macOS
cd macos/Airbridge && swift build -c release

# Android
cd android/Airbridge && ./gradlew assembleRelease
```

For local development installs use `scripts/dev-install.sh` (macOS) and `./gradlew installDebug` (Android). Version bumps across both platforms: `scripts/bump-version.sh patch|minor|major`.

---

## Android Permissions

Every permission is explained during onboarding, and most are optional — the app works with reduced functionality if you decline.

| Permission | Purpose |
|---|---|
| Notifications | Transfer progress and incoming file requests |
| All Files Access | Browse and transfer files across the whole phone storage |
| Photos | Browse the gallery from the Mac |
| SMS + Contacts | Read and send SMS from the Mac, with contact names |
| Camera | Scan the pairing QR code |
| Media projection | Capture the screen for mirroring |
| Accessibility service | Inject Mac-driven taps, swipes, and text |
| Bluetooth | Headphone handoff |

---

## Roadmap

- **Cellular file transfer** — send files over mobile data when devices aren't on the same Wi-Fi
- **Granular sharing controls (macOS)** — choose per device what is shared: clipboard, files, gallery, SMS, screen
- **Mirror audio** — stream the phone's audio alongside the screen
- **F-Droid listing** — publish on F-Droid as an alternative distribution channel

Have an idea? [Open an issue](https://github.com/negativepl/airbridge/issues).

---

## FAQ

**Does it work without internet?**
Yes. AirBridge only needs a local Wi-Fi network. No internet, no cloud, no accounts.

**Is it safe?**
All traffic is TLS-encrypted with a certificate pinned at pairing time, every reconnection uses Ed25519 signed authentication, and the mirror channel is token-gated. The code is open source — audit it yourself.

**Can I control my phone from my Mac (and vice versa)?**
Yes — both ways. Mirror the phone to the Mac and drive it with mouse and keyboard, or mirror the Mac to the phone and control it by touch. The phone can even act as a second display.

**Why is there a "Running in background" notification on Android?**
Android requires foreground services to show a notification. You can hide it via the notification's channel settings — transfer notifications keep working.

**Does it work with iOS?**
No. AirBridge is designed for the Android + macOS combination. If you have an iPhone, use AirDrop.

---

## Credits

- **Author** — [Marcin Baszewski](https://github.com/negativepl)
- **AI** — Built with [Claude](https://claude.ai) by Anthropic

## License

MIT License — see [LICENSE](LICENSE) for details.
