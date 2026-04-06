package com.airbridge.filetransfer

import android.util.Base64
import java.io.File

class FileReceiver(
    val transferId: String,
    val filename: String,
    val totalSize: Long,
    val totalChunks: Int
) {
    private val chunks = mutableMapOf<Int, ByteArray>()

    val isComplete: Boolean
        get() = chunks.size == totalChunks

    val progress: Float
        get() = if (totalChunks == 0) 1f else chunks.size.toFloat() / totalChunks.toFloat()

    fun addChunk(index: Int, base64Data: String) {
        val decoded = Base64.decode(base64Data, Base64.NO_WRAP)
        chunks[index] = decoded
    }

    fun assemble(): ByteArray {
        val result = mutableListOf<Byte>()
        for (i in 0 until totalChunks) {
            val chunk = chunks[i] ?: error("Missing chunk at index $i")
            result.addAll(chunk.toList())
        }
        return result.toByteArray()
    }

    fun saveToDownloads(): File {
        val downloadsDir = File(
            android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_DOWNLOADS
            ),
            "Airbridge"
        )
        downloadsDir.mkdirs()

        val outputFile = File(downloadsDir, filename)
        outputFile.writeBytes(assemble())
        return outputFile
    }
}
