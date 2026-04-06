import XCTest
@testable import Protocol

final class MessageTests: XCTestCase {

    // MARK: - Helpers

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    private let decoder = JSONDecoder()

    private func encode(_ message: Message) throws -> [String: Any] {
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json
    }

    private func decode(_ dict: [String: Any]) throws -> Message {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try decoder.decode(Message.self, from: data)
    }

    // MARK: - ClipboardUpdate Encode

    func testEncodeClipboardUpdate_hasCorrectType() throws {
        let msg = Message.clipboardUpdate(
            sourceId: "device-123",
            contentType: .plainText,
            data: "Hello, world!"
        )
        let json = try encode(msg)
        XCTAssertEqual(json["type"] as? String, "clipboard_update")
    }

    func testEncodeClipboardUpdate_hasSourceId() throws {
        let msg = Message.clipboardUpdate(
            sourceId: "device-abc",
            contentType: .plainText,
            data: "test"
        )
        let json = try encode(msg)
        XCTAssertEqual(json["source_id"] as? String, "device-abc")
    }

    func testEncodeClipboardUpdate_hasContentType() throws {
        let msg = Message.clipboardUpdate(
            sourceId: "device-123",
            contentType: .html,
            data: "<b>bold</b>"
        )
        let json = try encode(msg)
        XCTAssertEqual(json["content_type"] as? String, "text/html")
    }

    func testEncodeClipboardUpdate_hasData() throws {
        let msg = Message.clipboardUpdate(
            sourceId: "device-123",
            contentType: .plainText,
            data: "clipboard content"
        )
        let json = try encode(msg)
        XCTAssertEqual(json["data"] as? String, "clipboard content")
    }

    func testEncodeClipboardUpdate_hasTimestamp() throws {
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let msg = Message.clipboardUpdate(
            sourceId: "device-123",
            contentType: .plainText,
            data: "test"
        )
        let after = Int64(Date().timeIntervalSince1970 * 1000)
        let json = try encode(msg)
        let ts = json["timestamp"] as? Int64 ?? (json["timestamp"] as? Int).map(Int64.init) ?? -1
        XCTAssertGreaterThanOrEqual(ts, before)
        XCTAssertLessThanOrEqual(ts, after)
    }

    func testEncodeClipboardUpdate_plainTextContentType() throws {
        let msg = Message.clipboardUpdate(sourceId: "s", contentType: .plainText, data: "d")
        let json = try encode(msg)
        XCTAssertEqual(json["content_type"] as? String, "text/plain")
    }

    func testEncodeClipboardUpdate_pngContentType() throws {
        let msg = Message.clipboardUpdate(sourceId: "s", contentType: .png, data: "base64data")
        let json = try encode(msg)
        XCTAssertEqual(json["content_type"] as? String, "image/png")
    }

    // MARK: - ClipboardUpdate Decode

    func testDecodeClipboardUpdate_fromJSON() throws {
        let dict: [String: Any] = [
            "type": "clipboard_update",
            "source_id": "device-xyz",
            "content_type": "text/plain",
            "data": "decoded text",
            "timestamp": 1712345678901
        ]
        let msg = try decode(dict)
        guard case .clipboardUpdate(let sourceId, let contentType, let data) = msg else {
            XCTFail("Expected clipboardUpdate, got \(msg)")
            return
        }
        XCTAssertEqual(sourceId, "device-xyz")
        XCTAssertEqual(contentType, .plainText)
        XCTAssertEqual(data, "decoded text")
    }

    func testDecodeClipboardUpdate_htmlContentType() throws {
        let dict: [String: Any] = [
            "type": "clipboard_update",
            "source_id": "s",
            "content_type": "text/html",
            "data": "<p>hello</p>",
            "timestamp": 1234567890
        ]
        let msg = try decode(dict)
        guard case .clipboardUpdate(_, let contentType, _) = msg else {
            XCTFail("Expected clipboardUpdate")
            return
        }
        XCTAssertEqual(contentType, .html)
    }

    // MARK: - FileTransferStart Encode

    func testEncodeFileTransferStart_hasCorrectType() throws {
        let msg = Message.fileTransferStart(
            sourceId: "device-1",
            transferId: "transfer-abc",
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            totalSize: 204800,
            totalChunks: 200
        )
        let json = try encode(msg)
        XCTAssertEqual(json["type"] as? String, "file_transfer_start")
    }

    func testEncodeFileTransferStart_hasAllFields() throws {
        let msg = Message.fileTransferStart(
            sourceId: "src-001",
            transferId: "xfer-999",
            filename: "document.pdf",
            mimeType: "application/pdf",
            totalSize: 10240,
            totalChunks: 10
        )
        let json = try encode(msg)
        XCTAssertEqual(json["source_id"] as? String, "src-001")
        XCTAssertEqual(json["transfer_id"] as? String, "xfer-999")
        XCTAssertEqual(json["filename"] as? String, "document.pdf")
        XCTAssertEqual(json["mime_type"] as? String, "application/pdf")
        XCTAssertEqual(json["total_size"] as? Int, 10240)
        XCTAssertEqual(json["total_chunks"] as? Int, 10)
    }

    func testEncodeFileTransferStart_hasTimestamp() throws {
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let msg = Message.fileTransferStart(
            sourceId: "s",
            transferId: "t",
            filename: "f.txt",
            mimeType: "text/plain",
            totalSize: 100,
            totalChunks: 1
        )
        let after = Int64(Date().timeIntervalSince1970 * 1000)
        let json = try encode(msg)
        let ts = json["timestamp"] as? Int64 ?? (json["timestamp"] as? Int).map(Int64.init) ?? -1
        XCTAssertGreaterThanOrEqual(ts, before)
        XCTAssertLessThanOrEqual(ts, after)
    }

    // MARK: - PairRequest Encode

    func testEncodePairRequest_hasCorrectType() throws {
        let msg = Message.pairRequest(
            deviceName: "Pixel 8",
            publicKey: "base64key==",
            pairingToken: "token123"
        )
        let json = try encode(msg)
        XCTAssertEqual(json["type"] as? String, "pair_request")
    }

    func testEncodePairRequest_hasAllFields() throws {
        let msg = Message.pairRequest(
            deviceName: "My Phone",
            publicKey: "pubkey==",
            pairingToken: "abc123"
        )
        let json = try encode(msg)
        XCTAssertEqual(json["device_name"] as? String, "My Phone")
        XCTAssertEqual(json["public_key"] as? String, "pubkey==")
        XCTAssertEqual(json["pairing_token"] as? String, "abc123")
    }

    // MARK: - Round-trip Tests

    func testRoundTrip_clipboardUpdate() throws {
        let original = Message.clipboardUpdate(
            sourceId: "uuid-1",
            contentType: .plainText,
            data: "round trip text"
        )
        let data1 = try encoder.encode(original)
        let decoded = try decoder.decode(Message.self, from: data1)
        let data2 = try encoder.encode(decoded)

        let json1 = try JSONSerialization.jsonObject(with: data1) as! [String: Any]
        let json2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]

        XCTAssertEqual(json1["type"] as? String, json2["type"] as? String)
        XCTAssertEqual(json1["source_id"] as? String, json2["source_id"] as? String)
        XCTAssertEqual(json1["content_type"] as? String, json2["content_type"] as? String)
        XCTAssertEqual(json1["data"] as? String, json2["data"] as? String)
    }

    func testRoundTrip_fileChunk() throws {
        let original = Message.fileChunk(
            transferId: "xfer-123",
            chunkIndex: 5,
            data: "SGVsbG8="
        )
        let data1 = try encoder.encode(original)
        let decoded = try decoder.decode(Message.self, from: data1)
        let data2 = try encoder.encode(decoded)

        let json1 = try JSONSerialization.jsonObject(with: data1) as! [String: Any]
        let json2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]

        XCTAssertEqual(json1["type"] as? String, json2["type"] as? String)
        XCTAssertEqual(json1["transfer_id"] as? String, json2["transfer_id"] as? String)
        XCTAssertEqual(json1["chunk_index"] as? Int, json2["chunk_index"] as? Int)
        XCTAssertEqual(json1["data"] as? String, json2["data"] as? String)
    }

    func testRoundTrip_fileChunkAck() throws {
        let original = Message.fileChunkAck(transferId: "xfer-456", chunkIndex: 3)
        let data1 = try encoder.encode(original)
        let decoded = try decoder.decode(Message.self, from: data1)
        let data2 = try encoder.encode(decoded)

        let json1 = try JSONSerialization.jsonObject(with: data1) as! [String: Any]
        let json2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]

        XCTAssertEqual(json1["type"] as? String, json2["type"] as? String)
        XCTAssertEqual(json1["transfer_id"] as? String, json2["transfer_id"] as? String)
        XCTAssertEqual(json1["chunk_index"] as? Int, json2["chunk_index"] as? Int)
    }

    func testRoundTrip_fileTransferComplete() throws {
        let original = Message.fileTransferComplete(
            transferId: "xfer-789",
            checksumSHA256: "abc123def456"
        )
        let data1 = try encoder.encode(original)
        let decoded = try decoder.decode(Message.self, from: data1)
        let data2 = try encoder.encode(decoded)

        let json1 = try JSONSerialization.jsonObject(with: data1) as! [String: Any]
        let json2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]

        XCTAssertEqual(json1["type"] as? String, json2["type"] as? String)
        XCTAssertEqual(json1["transfer_id"] as? String, json2["transfer_id"] as? String)
        XCTAssertEqual(json1["checksum_sha256"] as? String, json2["checksum_sha256"] as? String)
    }

    func testRoundTrip_pairRequest() throws {
        let original = Message.pairRequest(
            deviceName: "Phone",
            publicKey: "key==",
            pairingToken: "tok"
        )
        let data1 = try encoder.encode(original)
        let decoded = try decoder.decode(Message.self, from: data1)
        let data2 = try encoder.encode(decoded)

        let json1 = try JSONSerialization.jsonObject(with: data1) as! [String: Any]
        let json2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]

        XCTAssertEqual(json1["type"] as? String, json2["type"] as? String)
        XCTAssertEqual(json1["device_name"] as? String, json2["device_name"] as? String)
        XCTAssertEqual(json1["public_key"] as? String, json2["public_key"] as? String)
        XCTAssertEqual(json1["pairing_token"] as? String, json2["pairing_token"] as? String)
    }

    func testRoundTrip_pairResponse() throws {
        let original = Message.pairResponse(
            deviceName: "MacBook",
            publicKey: "mackey==",
            accepted: true
        )
        let data1 = try encoder.encode(original)
        let decoded = try decoder.decode(Message.self, from: data1)
        let data2 = try encoder.encode(decoded)

        let json1 = try JSONSerialization.jsonObject(with: data1) as! [String: Any]
        let json2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]

        XCTAssertEqual(json1["type"] as? String, json2["type"] as? String)
        XCTAssertEqual(json1["device_name"] as? String, json2["device_name"] as? String)
        XCTAssertEqual(json1["public_key"] as? String, json2["public_key"] as? String)
        XCTAssertEqual(json1["accepted"] as? Bool, json2["accepted"] as? Bool)
    }

    func testRoundTrip_ping() throws {
        let original = Message.ping(timestamp: 1712345678901)
        let data1 = try encoder.encode(original)
        let decoded = try decoder.decode(Message.self, from: data1)
        let data2 = try encoder.encode(decoded)

        let json1 = try JSONSerialization.jsonObject(with: data1) as! [String: Any]
        let json2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]

        XCTAssertEqual(json1["type"] as? String, json2["type"] as? String)
        XCTAssertEqual(json1["timestamp"] as? Int, json2["timestamp"] as? Int)
    }

    func testRoundTrip_pong() throws {
        let original = Message.pong(timestamp: 1712345678901)
        let data1 = try encoder.encode(original)
        let decoded = try decoder.decode(Message.self, from: data1)
        let data2 = try encoder.encode(decoded)

        let json1 = try JSONSerialization.jsonObject(with: data1) as! [String: Any]
        let json2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]

        XCTAssertEqual(json1["type"] as? String, json2["type"] as? String)
        XCTAssertEqual(json1["timestamp"] as? Int, json2["timestamp"] as? Int)
    }

    func testRoundTrip_fileTransferStart() throws {
        let original = Message.fileTransferStart(
            sourceId: "src",
            transferId: "xfr",
            filename: "file.zip",
            mimeType: "application/zip",
            totalSize: 99999,
            totalChunks: 100
        )
        let data1 = try encoder.encode(original)
        let decoded = try decoder.decode(Message.self, from: data1)
        let data2 = try encoder.encode(decoded)

        let json1 = try JSONSerialization.jsonObject(with: data1) as! [String: Any]
        let json2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]

        XCTAssertEqual(json1["type"] as? String, json2["type"] as? String)
        XCTAssertEqual(json1["source_id"] as? String, json2["source_id"] as? String)
        XCTAssertEqual(json1["transfer_id"] as? String, json2["transfer_id"] as? String)
        XCTAssertEqual(json1["filename"] as? String, json2["filename"] as? String)
        XCTAssertEqual(json1["mime_type"] as? String, json2["mime_type"] as? String)
        XCTAssertEqual(json1["total_size"] as? Int, json2["total_size"] as? Int)
        XCTAssertEqual(json1["total_chunks"] as? Int, json2["total_chunks"] as? Int)
    }

    // MARK: - Decode specific message types

    func testDecodeFileChunk() throws {
        let dict: [String: Any] = [
            "type": "file_chunk",
            "transfer_id": "t-001",
            "chunk_index": 7,
            "data": "Y2h1bmtEYXRh"
        ]
        let msg = try decode(dict)
        guard case .fileChunk(let transferId, let chunkIndex, let data) = msg else {
            XCTFail("Expected fileChunk, got \(msg)")
            return
        }
        XCTAssertEqual(transferId, "t-001")
        XCTAssertEqual(chunkIndex, 7)
        XCTAssertEqual(data, "Y2h1bmtEYXRh")
    }

    func testDecodeFileChunkAck() throws {
        let dict: [String: Any] = [
            "type": "file_chunk_ack",
            "transfer_id": "t-002",
            "chunk_index": 3
        ]
        let msg = try decode(dict)
        guard case .fileChunkAck(let transferId, let chunkIndex) = msg else {
            XCTFail("Expected fileChunkAck, got \(msg)")
            return
        }
        XCTAssertEqual(transferId, "t-002")
        XCTAssertEqual(chunkIndex, 3)
    }

    func testDecodeFileTransferComplete() throws {
        let dict: [String: Any] = [
            "type": "file_transfer_complete",
            "transfer_id": "t-003",
            "checksum_sha256": "deadbeef"
        ]
        let msg = try decode(dict)
        guard case .fileTransferComplete(let transferId, let checksum) = msg else {
            XCTFail("Expected fileTransferComplete, got \(msg)")
            return
        }
        XCTAssertEqual(transferId, "t-003")
        XCTAssertEqual(checksum, "deadbeef")
    }

    func testDecodePairResponse() throws {
        let dict: [String: Any] = [
            "type": "pair_response",
            "device_name": "iMac",
            "public_key": "key123==",
            "accepted": false
        ]
        let msg = try decode(dict)
        guard case .pairResponse(let deviceName, let publicKey, let accepted) = msg else {
            XCTFail("Expected pairResponse, got \(msg)")
            return
        }
        XCTAssertEqual(deviceName, "iMac")
        XCTAssertEqual(publicKey, "key123==")
        XCTAssertFalse(accepted)
    }

    func testDecodePing() throws {
        let dict: [String: Any] = [
            "type": "ping",
            "timestamp": 9999999
        ]
        let msg = try decode(dict)
        guard case .ping(let ts) = msg else {
            XCTFail("Expected ping, got \(msg)")
            return
        }
        XCTAssertEqual(ts, 9999999)
    }

    func testDecodePong() throws {
        let dict: [String: Any] = [
            "type": "pong",
            "timestamp": 8888888
        ]
        let msg = try decode(dict)
        guard case .pong(let ts) = msg else {
            XCTFail("Expected pong, got \(msg)")
            return
        }
        XCTAssertEqual(ts, 8888888)
    }
}
