package com.airbridge.protocol

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageTest {

    @Test
    fun `encodes clipboard update to JSON`() {
        val msg = Message.ClipboardUpdate(
            sourceId = "550e8400-e29b-41d4-a716-446655440000",
            contentType = ContentType.PLAIN_TEXT,
            data = "Hello, world!",
            timestamp = 1712345678901L
        )
        val json = msg.toJson()
        val obj = JSONObject(json)
        assertEquals("clipboard_update", obj.getString("type"))
        assertEquals("550e8400-e29b-41d4-a716-446655440000", obj.getString("source_id"))
        assertEquals("text/plain", obj.getString("content_type"))
        assertEquals("Hello, world!", obj.getString("data"))
        assertEquals(1712345678901L, obj.getLong("timestamp"))
    }

    @Test
    fun `decodes clipboard update from JSON`() {
        val json = """{"type":"clipboard_update","source_id":"device-1","content_type":"text/html","data":"<b>bold</b>","timestamp":1712345678901}"""
        val msg = Message.fromJson(json) as Message.ClipboardUpdate
        assertEquals("device-1", msg.sourceId)
        assertEquals(ContentType.HTML, msg.contentType)
        assertEquals("<b>bold</b>", msg.data)
        assertEquals(1712345678901L, msg.timestamp)
    }

    @Test
    fun `decodes file transfer start`() {
        val json = """{"type":"file_transfer_start","source_id":"device-1","transfer_id":"txfr-123","filename":"photo.jpg","mime_type":"image/jpeg","total_size":204800,"total_chunks":200,"timestamp":1712345678901}"""
        val msg = Message.fromJson(json) as Message.FileTransferStart
        assertEquals("txfr-123", msg.transferId)
        assertEquals(200, msg.totalChunks)
        assertEquals(204800L, msg.totalSize)
        assertEquals("photo.jpg", msg.filename)
    }

    @Test
    fun `decodes pair request`() {
        val json = """{"type":"pair_request","device_name":"Pixel 8 Pro","public_key":"MFkwEwYH","pairing_token":"a1b2c3"}"""
        val msg = Message.fromJson(json)
        assertTrue(msg is Message.PairRequest)
        assertEquals("pair_request", JSONObject(msg.toJson()).getString("type"))
    }

    @Test
    fun `roundtrip all message types`() {
        val messages: List<Message> = listOf(
            Message.ClipboardUpdate("src-1", ContentType.PLAIN_TEXT, "test", 1000L),
            Message.FileTransferStart("src-1", "tr-1", "file.txt", "text/plain", 1024L, 1, 1000L),
            Message.FileChunk("tr-1", 0, "SGVsbG8="),
            Message.FileChunkAck("tr-1", 0),
            Message.FileTransferComplete("tr-1", "abc123def456"),
            Message.PairRequest("My Phone", "pubkeyB64", "token123"),
            Message.PairResponse("My Mac", "pubkeyB64", true),
            Message.Ping(1000L),
            Message.Pong(1000L)
        )

        for (original in messages) {
            val json = original.toJson()
            val decoded = Message.fromJson(json)
            assertEquals(
                "Roundtrip failed for ${original::class.simpleName}",
                original::class,
                decoded::class
            )
        }
    }
}
