package com.airbridge.filetransfer

import com.airbridge.protocol.Message
import java.security.MessageDigest

data class PreparedTransfer(
    val totalChunks: Int,
    val totalSize: Long,
    val chunkMessages: List<Message>,
    val completeMessage: Message
)

class FileSender(
    private val chunkSize: Int = 65536,
    private val base64Encoder: (ByteArray) -> String = { android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP) }
) {
    fun prepare(
        filename: String,
        mimeType: String,
        data: ByteArray,
        sourceId: String
    ): PreparedTransfer {
        val totalSize = data.size.toLong()
        val chunks = data.toList().chunked(chunkSize).map { it.toByteArray() }
        val totalChunks = chunks.size
        val transferId = java.util.UUID.randomUUID().toString()

        val chunkMessages = chunks.mapIndexed { index, chunk ->
            Message.FileChunk(
                transferId = transferId,
                chunkIndex = index,
                data = base64Encoder(chunk)
            )
        }

        val digest = MessageDigest.getInstance("SHA-256")
        val checksumBytes = digest.digest(data)
        val checksum = checksumBytes.joinToString("") { "%02x".format(it) }

        val completeMessage = Message.FileTransferComplete(
            transferId = transferId,
            checksumSha256 = checksum
        )

        return PreparedTransfer(
            totalChunks = totalChunks,
            totalSize = totalSize,
            chunkMessages = chunkMessages,
            completeMessage = completeMessage
        )
    }
}
