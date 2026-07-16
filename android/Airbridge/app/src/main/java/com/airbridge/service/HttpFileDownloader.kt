package com.airbridge.service

import android.util.Log
import com.airbridge.network.PinnedTls
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
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
class HttpFileDownloader(
    // Injectable so unit tests can exercise the stall path without waiting
    // out the production timeout.
    private val readTimeoutMs: Long = DEFAULT_READ_TIMEOUT_MS
) {

    companion object {
        private const val TAG = "HttpFileDownloader"
        private const val BUFFER_SIZE = 256 * 1024 // 256 KB read buffer
        // OkHttp's read timeout is per read operation, so any byte arriving
        // resets it — 30 s therefore means "no data at all for 30 s", i.e. a
        // stalled sender, not a slow link. The previous 5-minute value froze
        // the transfer UI for the full duration when the Mac stalled.
        const val DEFAULT_READ_TIMEOUT_MS = 30_000L
    }

    /**
     * Download a file from the given host/port for the given transferId.
     * On success returns the temp file. On failure returns null.
     * `onCallCreated` hands out the OkHttp Call so the caller can cancel the
     * transfer from another thread; `onProgress` fires as bytes arrive with
     * (bytesReceived, totalBytes).
     */
    fun download(
        host: String,
        port: Int,
        certFingerprint: String,
        transferId: String,
        filenameHint: String,
        onCallCreated: (okhttp3.Call) -> Unit = {},
        onProgress: (bytesReceived: Long, totalBytes: Long) -> Unit
    ): File? {
        // Built per call: the TLS pin is per-host, so the client cannot be a
        // long-lived field.
        val client = PinnedTls.apply(
            OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(readTimeoutMs, TimeUnit.MILLISECONDS),
            certFingerprint
        ).build()
        val url = "https://${com.airbridge.service.WebSocketClient.formatUrlHost(host)}:$port/send/$transferId"
        Log.d(TAG, "GET $url")

        val request = Request.Builder().url(url).get().build()

        var tempFile: File? = null
        return try {
            val call = client.newCall(request)
            onCallCreated(call)
            val response = call.execute()
            if (!response.isSuccessful) {
                Log.e(TAG, "Download failed: HTTP ${response.code}")
                response.close()
                return null
            }
            val totalBytes = response.header("Content-Length")?.toLongOrNull() ?: -1L
            val expectedChecksum = response.header("X-Checksum-SHA256")
            // Sanitize the filename used in the temp-file name (Mac sends it
            // URL-encoded in X-Filename; we already have `filenameHint` from
            // the offer message, so just strip path separators from it).
            val safeName = filenameHint.replace('/', '_').replace('\\', '_')
            val outFile = File.createTempFile("airbridge_", "_$safeName")
            tempFile = outFile
            val digest = MessageDigest.getInstance("SHA-256")
            response.body.byteStream().use { input ->
                FileOutputStream(outFile).use { out ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    var totalRead = 0L
                    var read: Int
                    while (input.read(buffer).also { read = it } != -1) {
                        digest.update(buffer, 0, read)
                        out.write(buffer, 0, read)
                        totalRead += read
                        onProgress(totalRead, totalBytes)
                    }
                }
            }
            response.close()

            // Verify integrity when the Mac advertised a checksum. A mismatch
            // means the bytes were corrupted in transit — drop the temp file
            // and fail the download rather than handing back bad data.
            if (expectedChecksum != null) {
                val actual = digest.digest().joinToString("") { "%02x".format(it) }
                if (!actual.equals(expectedChecksum, ignoreCase = true)) {
                    Log.e(TAG, "Checksum mismatch: expected $expectedChecksum, got $actual")
                    outFile.delete()
                    return null
                }
            }
            Log.d(TAG, "Download complete: ${outFile.absolutePath}")
            outFile
        } catch (e: Exception) {
            Log.e(TAG, "Download exception", e)
            // A stall/cancel mid-stream leaves a partial temp file behind —
            // remove it, nothing will consume it.
            tempFile?.delete()
            null
        } finally {
            // The per-call client would otherwise leave a live Dispatcher and
            // ConnectionPool behind until GC (same pattern as MirrorClient.close()).
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
        }
    }
}
