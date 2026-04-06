package com.airbridge.service

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okio.BufferedSink
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

class HttpFileUploader {

    companion object {
        private const val TAG = "HttpFileUploader"
        private const val BUFFER_SIZE = 1024 * 1024 // 1MB read buffer
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(5, TimeUnit.MINUTES)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    fun upload(
        host: String,
        port: Int,
        uri: Uri,
        contentResolver: ContentResolver,
        onProgress: (bytesSent: Long, totalBytes: Long) -> Unit
    ): Boolean {
        val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
        var filename = "file"
        var fileSize = 0L

        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIdx >= 0) filename = cursor.getString(nameIdx) ?: "file"
                val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIdx >= 0) fileSize = cursor.getLong(sizeIdx)
            }
        }

        Log.d(TAG, "Uploading $filename ($mimeType, $fileSize bytes) to $host:$port")

        // Single pass: stream upload while computing SHA-256 inline
        val digest = MessageDigest.getInstance("SHA-256")
        val body = object : RequestBody() {
            override fun contentType() = mimeType.toMediaType()
            override fun contentLength() = fileSize

            override fun writeTo(sink: BufferedSink) {
                contentResolver.openInputStream(uri)?.use { stream ->
                    val buf = ByteArray(BUFFER_SIZE)
                    var totalSent = 0L
                    var read: Int
                    while (stream.read(buf).also { read = it } != -1) {
                        digest.update(buf, 0, read)
                        sink.write(buf, 0, read)
                        totalSent += read
                        onProgress(totalSent, fileSize)
                    }
                    sink.flush()
                }
            }
        }

        val encodedFilename = java.net.URLEncoder.encode(filename, "UTF-8")
        val request = Request.Builder()
            .url("http://$host:$port/upload")
            .header("X-Filename", encodedFilename)
            .header("X-Mime-Type", mimeType)
            .post(body)
            .build()

        return try {
            val response = client.newCall(request).execute()
            val success = response.isSuccessful
            if (!success) {
                Log.e(TAG, "Upload failed: ${response.code} ${response.body?.string()}")
            } else {
                Log.d(TAG, "Upload successful: ${response.body?.string()}")
            }
            response.close()
            success
        } catch (e: Exception) {
            Log.e(TAG, "Upload exception", e)
            false
        }
    }
}
