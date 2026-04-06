# Airbridge Protocol Specification

## Overview

Airbridge uses a JSON-over-WebSocket protocol for communication between the macOS host and Android client. All messages are UTF-8 encoded JSON objects with a `type` field that discriminates the message kind.

## Transport

- **Protocol**: WebSocket (RFC 6455)
- **Port**: 8765 (default)
- **Discovery**: Bonjour/mDNS service type `_airbridge._tcp`
- **File Transfer**: HTTP POST (port 8766 Mac→Android, port 8767 Android→Mac)
- **Security**: Ed25519 signature authentication (no TLS — local network only)

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
| `public_key` | string | Base64-encoded DER public key (ECDH P-256) |
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
| `public_key` | string | Base64-encoded DER public key (ECDH P-256) |
| `accepted` | boolean | Whether pairing was accepted (`true`) or rejected (`false`) |

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
  "protocol_version": 1
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `host` | string | IPv4 address of the macOS device on the local network |
| `port` | integer | WebSocket server port (default: 8765) |
| `public_key` | string | Base64-encoded DER public key (ECDH P-256) of the macOS device |
| `pairing_token` | string | One-time random token; expires after successful pairing or timeout (5 minutes) |
| `protocol_version` | integer | Protocol version number; currently `1` |

**Notes:**
- The QR code payload is compact JSON (no extra whitespace)
- The `pairing_token` is cryptographically random, at least 64 bits of entropy
- After pairing, both devices derive a shared secret via ECDH and use it to derive session keys

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

## Flow Diagrams

### Pairing Flow

```
Android                          macOS
   |                               |
   |   [scans QR code]             |
   |                               |
   |--- WebSocket connect -------->|
   |--- pair_request ------------->|
   |                               | [user confirms on macOS]
   |<-- pair_response (accepted) --|
   |                               |
   |   [ECDH key exchange done]    |
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
   |=== HTTP POST /upload ========>|  [direct file upload over HTTP]
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
   |=== HTTP POST /upload ========>|  [direct file upload, port 8766]
   |                               |  [saves to Downloads/Airbridge]
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
