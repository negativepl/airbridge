# Airbridge Protocol Specification

## Overview

Airbridge uses a JSON-over-WebSocket protocol for communication between the macOS host and Android client. All messages are UTF-8 encoded JSON objects with a `type` field that discriminates the message kind.

## Transport

- **Control protocol**: WebSocket (RFC 6455) over TLS on port **8765** (default)
- **Discovery**: Bonjour/mDNS service type `_airbridge._tcp` (TXT record carries `http_port`, `mirror_port`, `pk_fingerprint`, `cert_fingerprint`)
- **File Transfer**: HTTPS on port **8766** — the phone POSTs uploads (`POST /upload`) and pulls Mac → phone files (`GET /send/{transfer_id}`). The Mac only ever listens; the phone initiates every connection (macOS Local Network Privacy blocks Mac-side outbound TCP to local IPs).
- **Screen Mirror**: binary WebSocket over TLS on port **8767** (advertised as `mirror_port`) — see [Mirror Binary Protocol](#mirror-binary-protocol)
- **Encryption**: all three channels run over TLS using a persistent self-signed identity generated on the Mac. The phone pins the certificate by the SHA-256 fingerprint of its DER encoding, exchanged in the pairing QR code (the `cert_fingerprint` TXT key is informational only — the pinned value always comes from pairing). Hostname verification is disabled because connections are made by IP; the pin is the trust anchor.
- **Authentication**: Ed25519 signature authentication on top of TLS (see [Authentication](#authentication))

## Message Format

All messages are JSON objects. The `type` field identifies the message kind. Field names use `snake_case`.

---

## Message Types

### `clipboard_update`

Sent when the clipboard contents change on either device.

```json
{
  "type": "clipboard_update",
  "source_id": "550e8400-e29b-41d4-a716-446655440000",
  "content_type": "text/plain",
  "data": "Hello, world!",
  "timestamp": 1712345678901
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"clipboard_update"` |
| `source_id` | string (UUID) | Identifier of the sending device |
| `content_type` | string | MIME type of the clipboard data (`text/plain`, `text/html`, `image/png`) |
| `data` | string | The clipboard content. Plain text as-is; binary data (images) as base64 |
| `timestamp` | integer | Unix timestamp in milliseconds (added automatically on encode) |

---

### `file_transfer_start`

Initiates a chunked file transfer.

```json
{
  "type": "file_transfer_start",
  "source_id": "550e8400-e29b-41d4-a716-446655440000",
  "transfer_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "filename": "photo.jpg",
  "mime_type": "image/jpeg",
  "total_size": 204800,
  "total_chunks": 200,
  "timestamp": 1712345678901
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"file_transfer_start"` |
| `source_id` | string (UUID) | Identifier of the sending device |
| `transfer_id` | string (UUID) | Unique identifier for this transfer session |
| `filename` | string | Original filename including extension |
| `mime_type` | string | MIME type of the file |
| `total_size` | integer | Total file size in bytes |
| `total_chunks` | integer | Total number of chunks to be sent |
| `timestamp` | integer | Unix timestamp in milliseconds (added automatically on encode) |

---

### `file_chunk`

A single chunk of a file transfer.

```json
{
  "type": "file_chunk",
  "transfer_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "chunk_index": 0,
  "data": "SGVsbG8gV29ybGQ="
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"file_chunk"` |
| `transfer_id` | string (UUID) | Matches the `transfer_id` from `file_transfer_start` |
| `chunk_index` | integer | Zero-based index of this chunk |
| `data` | string | Base64-encoded chunk data |

---

### `file_chunk_ack`

Acknowledgement of a received file chunk.

```json
{
  "type": "file_chunk_ack",
  "transfer_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "chunk_index": 0
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"file_chunk_ack"` |
| `transfer_id` | string (UUID) | Matches the `transfer_id` from `file_transfer_start` |
| `chunk_index` | integer | Zero-based index of the acknowledged chunk |

---

### `file_transfer_complete`

Signals that all chunks have been sent and provides a checksum for integrity verification.

```json
{
  "type": "file_transfer_complete",
  "transfer_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "checksum_sha256": "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"file_transfer_complete"` |
| `transfer_id` | string (UUID) | Matches the `transfer_id` from `file_transfer_start` |
| `checksum_sha256` | string | Lowercase hex-encoded SHA-256 checksum of the complete file |

---

### `pair_request`

Sent by the Android device when initiating pairing (scanned QR code).

```json
{
  "type": "pair_request",
  "device_name": "Pixel 8 Pro",
  "public_key": "MFkwEwYHKoZIzj0CAQY...",
  "pairing_token": "a1b2c3d4e5f6"
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"pair_request"` |
| `device_name` | string | Human-readable name of the Android device |
| `public_key` | string | Base64-encoded Ed25519 public key |
| `pairing_token` | string | One-time token from the QR code, proves physical proximity |

---

### `pair_response`

Sent by the macOS device in response to a `pair_request`.

```json
{
  "type": "pair_response",
  "device_name": "MacBook Pro",
  "public_key": "MFkwEwYHKoZIzj0CAQY...",
  "accepted": true
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"pair_response"` |
| `device_name` | string | Human-readable name of the macOS device |
| `public_key` | string | Base64-encoded Ed25519 public key |
| `accepted` | boolean | Whether pairing was accepted (`true`) or rejected (`false`) |

---

## Authentication

After pairing, the phone re-authenticates on every reconnection by signing the current timestamp with its Ed25519 private key. There is no shared-secret handshake — the Mac verifies the signature against the public key stored at pairing time.

### `auth_request`

Sent by the phone immediately after the WebSocket connects.

```json
{
  "type": "auth_request",
  "public_key": "MCowBQYDK2VwAyEA...",
  "signature": "base64-ed25519-signature",
  "timestamp": 1712345678901,
  "protocol_version": 1
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"auth_request"` |
| `public_key` | string | Base64-encoded Ed25519 public key, used to look up the paired device |
| `signature` | string | Base64 Ed25519 signature over the `timestamp` |
| `timestamp` | integer | Unix milliseconds; the Mac rejects the request if it is more than **30 seconds** off (replay protection) |
| `protocol_version` | integer | (Optional) sender's protocol version; absent means `1` (pre-versioning peers). Mismatches are logged, not rejected |

### `auth_response`

Sent by the Mac after verifying (or rejecting) an `auth_request`.

```json
{
  "type": "auth_response",
  "accepted": true,
  "mirror_port": 8767,
  "protocol_version": 1
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"auth_response"` |
| `accepted` | boolean | Whether authentication succeeded |
| `reason` | string | (Optional) failure reason when `accepted` is `false` (e.g. `"not_paired"`, `"expired"`, `"bad_signature"`) |
| `mirror_port` | integer | (Optional) the mirror WebSocket port — re-supplied here because the Bonjour TXT record is only seen once and is lost across reconnects |
| `protocol_version` | integer | (Optional) sender's protocol version; absent means `1` (pre-versioning peers). Mismatches are logged, not rejected |

---

### `ping`

Keepalive message sent by either side to check connection liveness.

```json
{
  "type": "ping",
  "timestamp": 1712345678901
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"ping"` |
| `timestamp` | integer | Unix timestamp in milliseconds when the ping was sent |

---

### `pong`

Response to a `ping` message.

```json
{
  "type": "pong",
  "timestamp": 1712345678901
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"pong"` |
| `timestamp` | integer | Echo of the `timestamp` from the corresponding `ping` |

---

## QR Code Payload Format

The QR code displayed on the macOS device encodes a JSON object that allows the Android app to discover and initiate a pairing session.

```json
{
  "host": "192.168.1.100",
  "port": 8765,
  "public_key": "MFkwEwYHKoZIzj0CAQY...",
  "pairing_token": "a1b2c3d4e5f6",
  "cert_fingerprint": "3f1a9c...64-hex-chars...b2e0",
  "protocol_version": 1
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `host` | string | IPv4 address of the macOS device on the local network |
| `port` | integer | WebSocket server port (default: 8765) |
| `public_key` | string | Base64-encoded Ed25519 public key of the macOS device |
| `pairing_token` | string | One-time random token; cleared after successful pairing |
| `cert_fingerprint` | string | Lowercase SHA-256 hex over the DER encoding of the Mac's TLS certificate; the phone pins it for every TLS connection to this Mac |
| `protocol_version` | integer | Protocol version number; currently `1` |

**Notes:**
- The QR code payload is compact JSON (no extra whitespace)
- The `pairing_token` proves physical proximity and is one-time use — the Mac clears it once a matching `pair_request` is accepted
- There is no key exchange / shared secret. Each device keeps a long-lived Ed25519 identity; after pairing, every reconnection is authenticated by the phone signing a fresh timestamp (see [Authentication](#authentication)), which the Mac verifies against the stored public key
- Pairings created on a pre-TLS version have no stored certificate fingerprint; the phone refuses to connect unpinned and prompts the user to pair again instead

---

## Content Types

The following MIME types are supported for clipboard content:

| MIME Type | Description |
|-----------|-------------|
| `text/plain` | Plain UTF-8 text |
| `text/html` | HTML-formatted text |
| `image/png` | PNG image, base64-encoded in the `data` field |

---

## Protocol Version

Current version: **1**

---

## Complete Message Type List

The sections above detail the representative messages. The full set of **52** control-channel message types is:

| Category | Types |
|---|---|
| Clipboard | `clipboard_update` |
| File Transfer | `file_transfer_offer`, `file_transfer_accept`, `file_transfer_reject`, `file_transfer_start`, `file_chunk`, `file_chunk_ack`, `file_transfer_complete` |
| Authentication | `pair_request`, `pair_response`, `auth_request`, `auth_response` |
| Gallery | `gallery_request`, `gallery_response`, `gallery_thumbnail_request`, `gallery_thumbnail_response`, `gallery_preview_request`, `gallery_preview_response`, `gallery_download_request` |
| SMS | `sms_conversations_request`, `sms_conversations_response`, `sms_messages_request`, `sms_messages_response`, `sms_send_request`, `sms_send_response` |
| Files Browser | `files_list_request`, `files_list_response`, `file_thumbnail_request`, `file_thumbnail_response`, `file_download_request`, `folder_stats_request`, `folder_stats_response`, `file_delete_request`, `file_delete_response` |
| Device Info & Monitor | `device_info_request`, `device_info_response`, `wallpaper_request`, `wallpaper_response`, `mac_info_request`, `mac_info_response`, `mac_wallpaper_request`, `mac_wallpaper_response` |
| Mirror control | `mirror_start_request`, `reverse_mirror_start`, `mirror_stop`, `mirror_error` |
| Notifications | `notification_posted`, `notification_reply` |
| Find My Phone | `phone_ring`, `phone_ring_stop` |
| Utility | `ping`, `pong` |

> The `file_transfer_start` / `file_chunk` / `file_chunk_ack` cluster is a legacy WebSocket-chunk transport. The active file transfer path is HTTP (`POST /upload` and `GET /send/{id}` on port 8766).

---

## Mirror Binary Protocol

The screen-mirror channel does **not** use JSON. It is a binary WebSocket (port 8767) where every message is framed as `[1-byte type][payload]`. The control WebSocket only carries the start/stop/error messages (`mirror_start_request`, `reverse_mirror_start`, `mirror_stop`, `mirror_error`); pixels and input flow over this binary channel.

| Byte | Frame | Direction | Purpose |
|---|---|---|---|
| `0x01` | `HELLO` | Phone → Mac | Opens the channel; payload begins with the 16-byte pairing token |
| `0x02` | `HELLO_ACK` | Mac → Phone | Token accepted, channel ready |
| `0x10` | `VIDEO_CONFIG` | Phone → Mac | H.264 codec config (SPS/PPS) |
| `0x12` | `VIDEO_CONFIG_HEVC` | Phone → Mac | HEVC codec config (VPS/SPS/PPS) |
| `0x11` | `VIDEO_FRAME` | Phone → Mac | Encoded video frame |
| `0x20` | `INPUT_TAP` | Mac → Phone | Tap-to-click coordinate, injected on the phone via AccessibilityService |
| `0x30` | `STATUS` | Phone → Mac | Stream status (screen off, app backgrounded, accessibility disabled/blocked, encoder error) |
| `0x40` | `REVERSE_HELLO` | Phone → Mac | Opens reverse mirroring; `mode` selects screen-mirror (0) or phone-shaped virtual display (1) |
| `0x41` | `REVERSE_INPUT` | Phone → Mac | Pointer event (click, move, drag, right-click) injected on the Mac via CGEvent |
| `0x42` | `REVERSE_SCROLL` | Phone → Mac | Scroll event injected on the Mac |
| `0x43` | `REVERSE_TEXT` | Phone → Mac | Text input injected on the Mac |
| `0x44` | `REVERSE_KEY` | Phone → Mac | Key event injected on the Mac |

In reverse modes the roles flip for video: the Mac encodes its screen and the phone decodes it, while input travels phone → Mac.

A bad pairing token in `HELLO` / `REVERSE_HELLO` causes the connection to be dropped immediately with no response.

---

## Flow Diagrams

### Pairing Flow

```
Android                          macOS
   |                               |
   |   [scans QR code]             |
   |   [pins cert_fingerprint]     |
   |                               |
   |--- TLS WebSocket connect ---->|
   |--- pair_request ------------->|
   |                               | [user confirms on macOS]
   |<-- pair_response (accepted) --|
   |                               |
   |   [public keys exchanged]     |
   |   [session established]       |
```

### Clipboard Sync Flow

```
Device A                         Device B
   |                               |
   |   [clipboard changes]         |
   |--- clipboard_update --------->|
   |                               | [applies to clipboard]
```

### File Transfer Flow (Mac → Android, consent-based)

```
Mac (Sender)                     Android (Receiver)
   |                               |
   |--- file_transfer_offer ------>|  [shows accept/reject notification]
   |                               |
   |<-- file_transfer_accept ------|  [user taps Accept]
   |                               |
   |<-- GET /send/{id} ------------|  [phone pulls the file, port 8766]
   |=== file bytes + X-Checksum ==>|  [Mac streams; phone verifies SHA-256]
   |                               |  [saves to Downloads/Airbridge]
```

If rejected:
```
   |<-- file_transfer_reject ------|  [user taps Reject]
   |   [transfer cancelled]        |
```

### File Transfer Flow (Android → Mac, HTTP upload)

```
Android (Sender)                 Mac (Receiver)
   |                               |
   |--- file_transfer_offer ------>|  [Mac shows accept/reject popup]
   |<-- (accept) ------------------|  [user accepts on Mac]
   |=== POST /upload + X-Checksum >|  [upload over HTTP, port 8766]
   |                               |  [Mac verifies SHA-256, saves to Downloads/Airbridge]
```

### File Transfer Flow (Legacy WebSocket chunks)

```
Sender                           Receiver
   |                               |
   |--- file_transfer_start ------>|
   |--- file_chunk (index 0) ----->|
   |<-- file_chunk_ack (index 0) --|
   |--- file_chunk (index 1) ----->|
   |<-- file_chunk_ack (index 1) --|
   |         ...                   |
   |--- file_transfer_complete --->|
   |                               | [verifies checksum]
```

### Message Types Added in v1.2.0

| Type | Fields | Description |
|---|---|---|
| `file_transfer_offer` | `transfer_id`, `filename`, `mime_type`, `file_size` | Mac asks Android for permission to send a file |
| `file_transfer_accept` | `transfer_id` | Android accepts the file transfer |
| `file_transfer_reject` | `transfer_id` | Android rejects the file transfer |
