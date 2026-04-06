package com.airbridge.filetransfer

import com.airbridge.protocol.Message
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class FileSenderTest {

    private val jvmBase64Encoder: (ByteArray) -> String = { bytes ->
        Base64.getEncoder().encodeToString(bytes)
    }

    @Test
    fun `chunks file correctly`() {
        val data = ByteArray(150) { it.toByte() }
        val sender = FileSender(chunkSize = 64, base64Encoder = jvmBase64Encoder)

        val prepared = sender.prepare(
            filename = "test.bin",
            mimeType = "application/octet-stream",
            data = data,
            sourceId = "device-1"
        )

        assertEquals(3, prepared.totalChunks)
        assertEquals(150L, prepared.totalSize)
        assertEquals(3, prepared.chunkMessages.size)
    }

    @Test
    fun `produces valid complete message`() {
        val data = ByteArray(100) { it.toByte() }
        val sender = FileSender(chunkSize = 64, base64Encoder = jvmBase64Encoder)

        val prepared = sender.prepare(
            filename = "sample.txt",
            mimeType = "text/plain",
            data = data,
            sourceId = "device-1"
        )

        val completeMessage = prepared.completeMessage as Message.FileTransferComplete
        assertTrue(completeMessage.checksumSha256.isNotEmpty())
    }
}
