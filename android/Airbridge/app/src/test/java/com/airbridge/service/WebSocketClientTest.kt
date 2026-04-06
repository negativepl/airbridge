package com.airbridge.service

import com.airbridge.protocol.ContentType
import com.airbridge.protocol.Message
import org.junit.Assert.assertEquals
import org.junit.Test

class WebSocketClientTest {

    @Test
    fun `message serialization roundtrip`() {
        val original = Message.ClipboardUpdate(
            sourceId = "device-abc",
            contentType = ContentType.PLAIN_TEXT,
            data = "Hello, Airbridge!",
            timestamp = 1712345678901L
        )

        val json = original.toJson()
        val decoded = Message.fromJson(json) as Message.ClipboardUpdate

        assertEquals(original.sourceId, decoded.sourceId)
        assertEquals(original.contentType, decoded.contentType)
        assertEquals(original.data, decoded.data)
        assertEquals(original.timestamp, decoded.timestamp)
    }

    @Test
    fun `file chunk message roundtrip`() {
        val original = Message.FileChunk(
            transferId = "transfer-xyz-123",
            chunkIndex = 42,
            data = "SGVsbG8gV29ybGQ="
        )

        val json = original.toJson()
        val decoded = Message.fromJson(json) as Message.FileChunk

        assertEquals(original.transferId, decoded.transferId)
        assertEquals(original.chunkIndex, decoded.chunkIndex)
        assertEquals(original.data, decoded.data)
    }
}
