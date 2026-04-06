package com.airbridge.filetransfer

import android.util.Base64
import com.airbridge.protocol.Message
import java.security.MessageDigest
import java.util.UUID

data class PreparedFile(
    val transferId: String,
    val totalSize: Long,
    val totalChunks: Int,
    val checksumSHA256: String,
    val startMessage: Message,
    val chunkMessages: List<Message>,
    val completeMessage: Message
)

class FileSender(
    private val chunkSize: Int = 65536,
    private val base64Encoder: (ByteArray) -> String = { bytes ->
        Base64.encodeToString(bytes, Base64.NO_WRAP)
    }
) {

    fun prepare(
        filename: String,
        mimeType: String,
        data: ByteArray,
        sourceId: String
    ): PreparedFile {
        val transferId = UUID.randomUUID().toString()
        val totalSize = data.size.toLong()
        val totalChunks = ((data.size + chunkSize - 1) / chunkSize).coerceAtLeast(1)

        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(data)
        val checksumBytes = digest.digest()
        val checksumSHA256 = checksumBytes.joinToString("") { "%02x".format(it) }

        val startMessage = Message.FileTransferStart(
            sourceId = sourceId,
            transferId = transferId,
            filename = filename,
            mimeType = mimeType,
            totalSize = totalSize,
            totalChunks = totalChunks
        )

        val chunkMessages = mutableListOf<Message>()
        for (i in 0 until totalChunks) {
            val start = i * chunkSize
            val end = minOf(start + chunkSize, data.size)
            val chunkBytes = data.copyOfRange(start, end)
            val encoded = base64Encoder(chunkBytes)
            chunkMessages.add(Message.FileChunk(transferId, i, encoded))
        }

        val completeMessage = Message.FileTransferComplete(
            transferId = transferId,
            checksumSha256 = checksumSHA256
        )

        return PreparedFile(
            transferId = transferId,
            totalSize = totalSize,
            totalChunks = totalChunks,
            checksumSHA256 = checksumSHA256,
            startMessage = startMessage,
            chunkMessages = chunkMessages,
            completeMessage = completeMessage
        )
    }
}
