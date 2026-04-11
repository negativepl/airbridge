package com.airbridge.service

import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

/**
 * HTTP GET client that streams a file from Mac's `HttpUploadServer` via the
 * `/send/{transferId}` endpoint. Used by the inverted Mac→phone file transfer
 * flow: Mac registers the file on its own HTTP server, phone fetches.
 *
 * Why the inverted direction: macOS Local Network Privacy silently blocks
 * Mac → phone outbound TCP for ad-hoc signed apps, so we flip the client/
 * server roles for Mac→phone transfers. Android initiates outbound — phone
 * has no LNP restriction — Mac only accepts incoming, which always works.
 */
class HttpFileDownloader {

    companion object {
        private const val TAG = "HttpFileDownloader"
        private const val BUFFER_SIZE = 256 * 1024 // 256 KB read buffer
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.MINUTES)
        .build()

    /**
     * Download a file from the given host/port for the given transferId.
     * On success returns the temp file. On failure returns null.
     * `onProgress` fires as bytes arrive with (bytesReceived, totalBytes).
     */
    fun download(
        host: String,
        port: Int,
        transferId: String,
        filenameHint: String,
        onProgress: (bytesReceived: Long, totalBytes: Long) -> Unit
    ): File? {
        val url = "http://$host:$port/send/$transferId"
        Log.d(TAG, "GET $url")

        val request = Request.Builder().url(url).get().build()

        return try {
            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                Log.e(TAG, "Download failed: HTTP ${response.code}")
                response.close()
                return null
            }
            val totalBytes = response.header("Content-Length")?.toLongOrNull() ?: -1L
            // Sanitize the filename used in the temp-file name (Mac sends it
            // URL-encoded in X-Filename; we already have `filenameHint` from
            // the offer message, so just strip path separators from it).
            val safeName = filenameHint.replace('/', '_').replace('\\', '_')
            val tempFile = File.createTempFile("airbridge_", "_$safeName")
            response.body?.byteStream()?.use { input ->
                FileOutputStream(tempFile).use { out ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    var totalRead = 0L
                    var read: Int
                    while (input.read(buffer).also { read = it } != -1) {
                        out.write(buffer, 0, read)
                        totalRead += read
                        onProgress(totalRead, totalBytes)
                    }
                }
            }
            response.close()
            Log.d(TAG, "Download complete: ${tempFile.absolutePath}")
            tempFile
        } catch (e: Exception) {
            Log.e(TAG, "Download exception", e)
            null
        }
    }
}
