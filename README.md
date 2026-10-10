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
  <img src="https://img.shields.io/badge/Kotlin-2.4-7F52FF?logo=kotlin&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-blue" />
  <img src="https://img.shields.io/github/v/release/negativepl/airbridge" />
</p>

<p align="center">
  <a href="https://github.com/negativepl/airbridge/releases/latest">Download Latest Release</a>
</p>

---

AirBridge connects an Android phone and a Mac over local Wi-Fi: notifications, clipboard, files, photos, SMS, Bluetooth headphones and screen sharing in both directions. There are no cables, accounts or cloud services, and all traffic is TLS-encrypted and stays on your network.

It is an open-source alternative to Phone Link, KDE Connect and Intel Unison, built for the Android and macOS combination. Both apps are fully native: SwiftUI on macOS and Jetpack Compose with Material 3 Expressive on Android, sharing one protocol.

---

## Features

### Screen sharing and remote control

- **Phone on the Mac:** the Android screen appears in a Mac window, and a mouse click taps the phone.
- **Mac on the phone:** the Mac screen streams to the phone, and you control it by touch. A tap is a click, two fingers scroll, a long press is a right-click. The phone also has a trackpad panel and a keyboard for text input.
- **Phone as a second display:** macOS gets a virtual Retina display shaped to the phone's screen, including the Fold's cover screen.
- **Low latency:** hardware H.264 encoding, with HEVC as an option. Each mode has its own resolution, frame rate and bitrate settings.
- Capturing the phone screen always goes through the Android system consent prompt.

### Notifications

Phone notifications appear on the Mac as native macOS notifications. Apps that support inline replies, such as WhatsApp, can be answered directly from the notification on the Mac.

### Files

- **Sending:** in both directions, and the receiver always accepts or declines first. On the Mac, a global shortcut (`⌃⌥⌘A` by default) opens a drop zone from anywhere. Transfers show their speed and remaining time, can be cancelled, and are verified with a SHA-256 checksum.
- **Phone storage on the Mac:** a Finder-style browser with a sortable list and an icon view, Back and Forward, Quick Look, thumbnails, downloading, and drag-and-drop upload into the open folder.
- **Mac files on the phone:** browse the Mac's folders, download files and upload into the current folder.

### Photos

Browse the phone's photo library on the Mac in a Photos-style grid. You can zoom into and rotate a photo, download the original in full resolution, or delete it from the phone.

### Messages

Read and reply to SMS conversations on the Mac, with contact names and search. Short-code senders are read-only.

### Clipboard

Text copied on one device can be pasted on the other, automatically and in both directions, with HTML formatting preserved. On Android, a "Send to Mac" option is also available in the text-selection menu of any app.

### Headphone handoff

Move Bluetooth headphones between the phone and the Mac with one click. Both devices coordinate the switch, so headphones that connect to one device at a time, such as Galaxy Buds, switch reliably. AirBridge can optionally offer to switch when playback starts on the other device. Nothing moves without confirmation.

Known limitation: some LE Audio headphones, such as Galaxy Buds4 Pro, may not release cleanly when moving away from the Mac, because macOS gives apps access only to the classic Bluetooth link. In that case, reconnect them manually.

### Device overview

The phone shows the connected Mac with its wallpaper, model, chip, and live CPU, memory, disk and battery use. The Mac shows each phone's model, battery, storage and memory, and can ring a misplaced phone.

### Multiple devices

One Mac can pair with several phones and keep them connected at the same time. A device switcher chooses which phone Photos, Files, Messages and transfers apply to.

### Integration

- Devices on the same Wi-Fi find each other automatically over Bonjour.
- **macOS:** menu bar status, Launch at Login, and settings for the shortcut, download folder and sounds.
- **Android:** a Share sheet target, guided setup for permissions and pairing, adaptive navigation on foldables, and dynamic colour.
- English and Polish, following the system language.

---

## Security and privacy

- **TLS on every channel:** control, file transfer and screen streams.
- **Certificate pinning:** the pairing QR code carries the fingerprint of the Mac's certificate, and the phone connects to nothing else.
- **Ed25519 authentication:** every reconnection is signed and accepted only within a 30-second window. On Android the private key is protected by the hardware-backed AndroidKeyStore.
- **Local only:** no internet connection, telemetry, analytics or accounts.

---

## Download

The latest builds are on the [Releases](https://github.com/negativepl/airbridge/releases/latest) page.

| Platform | File | Requirement |
|---|---|---|
| **macOS** | `AirBridge.dmg` | macOS 26 (Tahoe) or later, Apple Silicon |
| **Android** | `AirBridge.apk` | Android 10 (API 29) or later |

- **macOS:** the app is self-signed. The first time, right-click it and choose **Open**. Permissions are kept across updates.
- **Android:** allow installing unknown apps from your browser or file manager.

AirBridge is not on Google Play because it relies on persistent foreground services that do not fit Google Play's foreground service policy.

---

## Tested On

| Device | OS |
|---|---|
| Samsung Galaxy Z Fold7 | One UI 9 (Android 17), One UI 8.5 (Android 16) |
| OPPO Find X9 Ultra | ColorOS 16 (Android 16) |
| OPPO Find N6 | ColorOS 16 (Android 16) |
| MacBook Pro 16″ (M1 Max) | macOS 26 (Tahoe), macOS 27 (beta) |
| MacBook Pro 16″ (M4 Max) | macOS 26 (Tahoe) |

Other recent Android phones and Apple Silicon Macs should work as well.

---

## How it works

The Mac runs three TLS servers and advertises itself over Bonjour. The phone always opens the connections.

| Channel | Port | Purpose |
|---|---|---|
| Control WebSocket | 8765 | Clipboard, notifications, photos, SMS, files, device info |
| HTTPS | 8766 | File transfers in both directions |
| Mirror WebSocket | 8767 | Screen video and input |

Pairing takes a single QR code scan: on the Mac, open Settings, choose Add Device, and scan the code with the phone. After that, paired devices connect automatically whenever they are on the same network. The protocol is described in [docs/protocol.md](docs/protocol.md).

---

## Building from source

Requirements: macOS 26 with Xcode 26 or later, and JDK 17 or later.

```bash
# macOS
cd macos/Airbridge && swift build -c release

# Android
cd android/Airbridge && ./gradlew assembleRelease
```

For development installs, use `scripts/dev-install.sh` on macOS and `./gradlew installDebug` on Android.

---

## Android permissions

Each permission is explained during setup. Most are optional, and declining one turns off only the feature that needs it.

| Permission | Purpose |
|---|---|
| Notifications | Transfer progress and incoming file requests |
| Notification access | Showing phone notifications on the Mac |
| All files access | Browsing and transferring files across the phone's storage |
| Photos | Browsing the photo library from the Mac |
| SMS and contacts | Reading and sending SMS from the Mac, with contact names |
| Camera | Scanning the pairing QR code |
| Screen capture | Sharing the phone screen |
| Accessibility service | Applying taps, swipes and text sent from the Mac |
| Bluetooth | Headphone handoff |

---

## Credits

- **Author:** [Marcin Baszewski](https://github.com/negativepl)
- **AI:** built with [Claude](https://claude.ai) by Anthropic

## License

MIT License. See [LICENSE](LICENSE) for details.
